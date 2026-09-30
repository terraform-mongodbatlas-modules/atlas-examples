from __future__ import annotations

import certifi
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorCollection

from hybrid_search.settings import HybridSearchSettings

INGEST_STATE_COLLECTION = "ingest_state"


def get_client(
    settings: HybridSearchSettings,
    *,
    server_selection_timeout_ms: int | None = None,
) -> AsyncIOMotorClient:
    timeout_ms = server_selection_timeout_ms or settings.mongo_server_selection_timeout_ms
    return AsyncIOMotorClient(
        settings.mongodb_uri.get_secret_value(),
        tlsCAFile=certifi.where(),
        serverSelectionTimeoutMS=timeout_ms,
    )


def chunks_collection(
    client: AsyncIOMotorClient,
    settings: HybridSearchSettings,
) -> AsyncIOMotorCollection:
    return client[settings.mongodb_database][settings.chunks_collection]


def ingest_state_collection(
    client: AsyncIOMotorClient,
    settings: HybridSearchSettings,
) -> AsyncIOMotorCollection:
    return client[settings.mongodb_database][INGEST_STATE_COLLECTION]
