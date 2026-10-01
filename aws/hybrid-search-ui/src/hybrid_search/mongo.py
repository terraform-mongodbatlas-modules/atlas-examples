from __future__ import annotations

import certifi
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorCollection

from hybrid_search.settings import HybridSearchSettings

INGEST_STATE_COLLECTION = "ingest_state"


def get_client(
    settings: HybridSearchSettings,
    *,
    server_selection_timeout_ms: int | None = None,
    tls: bool | None = None,
) -> AsyncIOMotorClient:
    timeout_ms = server_selection_timeout_ms or settings.mongo_server_selection_timeout_ms
    use_tls = settings.mongodb_tls if tls is None else tls
    tls_kwargs = {"tlsCAFile": certifi.where()} if use_tls else {"tls": False}
    return AsyncIOMotorClient(
        settings.mongodb_uri.get_secret_value(),
        serverSelectionTimeoutMS=timeout_ms,
        **tls_kwargs,
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
