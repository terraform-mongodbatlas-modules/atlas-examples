from __future__ import annotations

import asyncio
import logging
import time
from datetime import UTC, datetime
from typing import Any

from motor.motor_asyncio import AsyncIOMotorCollection
from pymongo.errors import OperationFailure
from pymongo.operations import SearchIndexModel

from hybrid_search.settings import HybridSearchSettings

IndexStatus = tuple[str, str, str]
_NAMESPACE_NOT_FOUND = 26
_BOOTSTRAP_ID = "__hybrid_search_bootstrap"
logger = logging.getLogger(__name__)


def vector_index_definition(*, dimensions: int) -> dict[str, Any]:
    return {
        "fields": [
            {
                "type": "vector",
                "path": "vector",
                "numDimensions": dimensions,
                "similarity": "cosine",
            },
            {"type": "filter", "path": "file_path"},
        ]
    }


def text_index_definition() -> dict[str, Any]:
    return {
        "mappings": {
            "dynamic": False,
            "fields": {
                "content": {
                    "type": "string",
                    "analyzer": "lucene.standard",
                }
            },
        }
    }


async def _materialize_namespace(collection: AsyncIOMotorCollection) -> None:
    # Mongo only creates a database on write. createCollection is not enough for
    # Atlas Search: listSearchIndexes can return [] while createSearchIndexes
    # still raises NamespaceNotFound.
    namespace = f"{collection.database.name}.{collection.name}"
    logger.info("Atlas Search namespace missing; creating %s", namespace)
    await collection.insert_one({"_id": _BOOTSTRAP_ID})
    await collection.delete_one({"_id": _BOOTSTRAP_ID})


async def _list_search_indexes(collection: AsyncIOMotorCollection) -> list[dict[str, Any]]:
    try:
        return await collection.list_search_indexes().to_list(length=None)
    except OperationFailure as exc:
        if exc.code != _NAMESPACE_NOT_FOUND:
            raise
        await _materialize_namespace(collection)
        return await collection.list_search_indexes().to_list(length=None)


async def _create_search_index(
    collection: AsyncIOMotorCollection,
    model: SearchIndexModel,
) -> None:
    try:
        await collection.create_search_index(model)
    except OperationFailure as exc:
        if exc.code != _NAMESPACE_NOT_FOUND:
            raise
        await _materialize_namespace(collection)
        await collection.create_search_index(model)


async def create_chunks_indexes_if_missing(
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> None:
    existing = {index.get("name") for index in await _list_search_indexes(collection)}
    if settings.vector_index_name not in existing:
        await _create_search_index(
            collection,
            SearchIndexModel(
                definition=vector_index_definition(dimensions=settings.voyage_output_dimension),
                name=settings.vector_index_name,
                type="vectorSearch",
            ),
        )
    if settings.text_index_name not in existing:
        await _create_search_index(
            collection,
            SearchIndexModel(
                definition=text_index_definition(),
                name=settings.text_index_name,
                type="search",
            ),
        )


async def wait_chunks_indexes_ready(
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
    *,
    timeout_s: int = 600,
    interval_s: int = 10,
) -> list[IndexStatus]:
    names = {settings.vector_index_name, settings.text_index_name}
    deadline = time.monotonic() + timeout_s
    ready: list[IndexStatus] = []
    seen_ready: set[str] = set()
    while time.monotonic() < deadline:
        indexes = await _list_search_indexes(collection)
        by_name = {index.get("name"): index.get("status") for index in indexes if index.get("name")}
        for name in names:
            status = by_name.get(name)
            if status == "FAILED":
                msg = f"index {settings.chunks_collection}.{name} failed"
                raise RuntimeError(msg)
            if status == "READY" and name not in seen_ready:
                seen_ready.add(name)
                ready.append((settings.chunks_collection, name, status))
        if seen_ready == names:
            return ready
        await asyncio.sleep(interval_s)
    msg = f"timed out waiting for indexes on {settings.chunks_collection}"
    raise TimeoutError(msg)


def format_index_ready_line(collection: str, index_name: str) -> str:
    date = datetime.now(UTC).strftime("%Y-%m-%d")
    return f"{date} {collection}.{index_name} READY"
