from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from motor.motor_asyncio import AsyncIOMotorCollection
from pydantic import BaseModel, Field
from pymongo.errors import PyMongoError

from hybrid_search.extract import SUPPORTED_SUFFIXES
from hybrid_search.ingest import ingest_file
from hybrid_search.ingest_state import (
    IngestState,
    content_hash,
    is_unchanged,
    load_states,
    source_key,
    upsert_state,
)
from hybrid_search.mongo import chunks_collection, get_client, ingest_state_collection
from hybrid_search.settings import HybridSearchSettings

logger = logging.getLogger(__name__)

# The CLI and the startup task catch the same set; OSError covers a missing dir.
INGEST_ERRORS = (OSError, ValueError, RuntimeError, PyMongoError)


class IngestInput(BaseModel):
    settings: HybridSearchSettings
    dirs: list[Path] = Field(default_factory=list)
    force: bool = False


class IngestResult(BaseModel):
    exit_code: int = 0
    ingested: int = 0
    skipped: int = 0


def ingest(input: IngestInput) -> IngestResult:
    return asyncio.run(_ingest_async(input))


async def _ingest_async(input: IngestInput) -> IngestResult:
    settings = input.settings
    if settings.skip_ingest:
        logger.info("skip_ingest is set; nothing to do")
        return IngestResult()
    client = get_client(settings)
    try:
        collection = chunks_collection(client, settings)
        state_collection = ingest_state_collection(client, settings)
        return await ingest_dirs(
            settings,
            collection,
            state_collection,
            input.dirs,
            force=input.force,
        )
    except INGEST_ERRORS as exc:
        logger.error(f"ingest failed: {exc}")
        return IngestResult(exit_code=1)
    finally:
        client.close()


async def ingest_dirs(
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    state_collection: AsyncIOMotorCollection,
    dirs: list[Path],
    *,
    force: bool = False,
) -> IngestResult:
    states = await load_states(state_collection)
    result = IngestResult()
    for directory in dirs:
        if not directory.is_dir():
            msg = f"document directory not found: {directory}"
            raise FileNotFoundError(msg)
        for path in _iter_supported_files(directory):
            await _ingest_one(
                path,
                settings=settings,
                collection=collection,
                state_collection=state_collection,
                states=states,
                force=force,
                result=result,
            )
    return result


def _iter_supported_files(directory: Path) -> list[Path]:
    return sorted(
        path
        for path in directory.rglob("*")
        if path.is_file() and path.suffix.lower() in SUPPORTED_SUFFIXES
    )


async def _ingest_one(
    path: Path,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    state_collection: AsyncIOMotorCollection,
    states: dict[str, str],
    force: bool,
    result: IngestResult,
) -> None:
    key = source_key(path)
    digest = content_hash(path)
    if not force and is_unchanged(states, source_key=key, content_hash=digest):
        logger.info(f"skipping unchanged file: {key}")
        result.skipped += 1
        return
    # A shorter file would otherwise leave stale higher-index chunks behind.
    await collection.delete_many({"file_path": key})
    ingested = await ingest_file(
        path,
        settings=settings,
        collection=collection,
        source_name=key,
    )
    await upsert_state(
        state_collection,
        IngestState(source_key=key, content_hash=digest, chunk_count=ingested.chunk_count),
    )
    result.ingested += 1
