"""Content-hash state for the CLI and startup ingest paths.

State lives in its own ``ingest_state`` collection so it never collides with
chunk queries, ``$rankFusion``, or ``list_ingested_files``, all of which read
``chunks`` with no filter.

The state document ``_id`` is the source key. That key is also the ``file_path``
the chunk documents carry, so ``delete_many({"file_path": key})`` targets exactly
one file's chunks. Two same-named files in different ``document_dirs`` stay
separate because the key is path-derived, not filename-derived.

The key is the path relative to the working directory when the file sits under
it (the bundled corpus under ``/app``), and the resolved absolute path otherwise.
Either form is stable across runs, so a redeploy reuses the key and only changed
content re-ingests. The browser upload flow keeps its filename rule in
``ingest.py``; the two rules coexist because they serve different users.
"""

from __future__ import annotations

import hashlib
from datetime import UTC, datetime
from pathlib import Path

from motor.motor_asyncio import AsyncIOMotorCollection
from pydantic import BaseModel, Field

_HASH_CHUNK_BYTES = 1024 * 1024


def source_key(path: Path) -> str:
    resolved = path.resolve()
    try:
        return resolved.relative_to(Path.cwd().resolve()).as_posix()
    except ValueError:
        return resolved.as_posix()


def content_hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(_HASH_CHUNK_BYTES), b""):
            digest.update(block)
    return digest.hexdigest()


class IngestState(BaseModel):
    source_key: str
    content_hash: str
    chunk_count: int
    ts: datetime = Field(default_factory=lambda: datetime.now(UTC))


def is_unchanged(states: dict[str, str], *, source_key: str, content_hash: str) -> bool:
    return states.get(source_key) == content_hash


async def upsert_state(collection: AsyncIOMotorCollection, state: IngestState) -> None:
    await collection.replace_one({"_id": state.source_key}, state.model_dump(), upsert=True)


async def load_states(collection: AsyncIOMotorCollection) -> dict[str, str]:
    cursor = collection.find({})
    docs = await cursor.to_list(length=None)
    return {
        doc["_id"]: doc["content_hash"]
        for doc in docs
        if doc.get("_id") is not None and doc.get("content_hash") is not None
    }
