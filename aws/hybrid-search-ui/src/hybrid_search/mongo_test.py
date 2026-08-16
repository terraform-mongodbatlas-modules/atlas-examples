from __future__ import annotations

from pydantic import SecretStr

from hybrid_search.mongo import chunks_collection
from hybrid_search.settings import HybridSearchSettings


def test_chunks_collection_name():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )

    class DB:
        def __getitem__(self, name: str) -> str:
            return f"db.{name}"

    class Client:
        def __getitem__(self, name: str) -> DB:
            assert name == settings.mongodb_database
            return DB()

    coll = chunks_collection(Client(), settings)
    assert coll == f"db.{settings.chunks_collection}"
