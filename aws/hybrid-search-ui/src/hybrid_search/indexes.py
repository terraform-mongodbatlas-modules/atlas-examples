from __future__ import annotations

import asyncio
import time
from datetime import UTC, datetime
from typing import Any

from motor.motor_asyncio import AsyncIOMotorCollection, AsyncIOMotorDatabase
from pymongo.operations import SearchIndexModel

from hybrid_search.settings import HybridSearchSettings

IndexStatus = tuple[str, str, str]


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


async def create_chunks_indexes_if_missing(
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> None:
    existing = {
        index.get("name") for index in await collection.list_search_indexes().to_list(length=None)
    }
    if settings.vector_index_name not in existing:
        await collection.create_search_index(
            SearchIndexModel(
                definition=vector_index_definition(dimensions=settings.voyage_output_dimension),
                name=settings.vector_index_name,
                type="vectorSearch",
            )
        )
    if settings.text_index_name not in existing:
        await collection.create_search_index(
            SearchIndexModel(
                definition=text_index_definition(),
                name=settings.text_index_name,
                type="search",
            )
        )


async def wait_chunks_indexes_ready(
    db: AsyncIOMotorDatabase,
    settings: HybridSearchSettings,
    *,
    timeout_s: int = 600,
    interval_s: int = 10,
) -> list[IndexStatus]:
    collection = db[settings.chunks_collection]
    names = {settings.vector_index_name, settings.text_index_name}
    deadline = time.monotonic() + timeout_s
    ready: list[IndexStatus] = []
    seen_ready: set[str] = set()
    while time.monotonic() < deadline:
        indexes = await collection.list_search_indexes().to_list(length=None)
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
