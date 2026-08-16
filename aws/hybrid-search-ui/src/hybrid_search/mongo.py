from __future__ import annotations

import certifi
from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorCollection

from hybrid_search.settings import HybridSearchSettings


def get_client(settings: HybridSearchSettings) -> AsyncIOMotorClient:
    return AsyncIOMotorClient(
        settings.mongodb_uri.get_secret_value(),
        tlsCAFile=certifi.where(),
    )


def chunks_collection(
    client: AsyncIOMotorClient,
    settings: HybridSearchSettings,
) -> AsyncIOMotorCollection:
    return client[settings.mongodb_database][settings.chunks_collection]
