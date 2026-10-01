from __future__ import annotations

from unittest.mock import patch

import certifi
from pydantic import SecretStr

from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.settings import HybridSearchSettings


def test_chunks_collection_name():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
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


def _settings(**overrides: object) -> HybridSearchSettings:
    base: dict[str, object] = {"mongodb_uri": SecretStr("mongodb://localhost")}
    base.update(overrides)
    return HybridSearchSettings(**base)


def test_get_client_uses_configured_server_selection_timeout():
    with patch("hybrid_search.mongo.AsyncIOMotorClient") as client:
        get_client(_settings(mongo_server_selection_timeout_ms=30_000))
    assert client.call_args.kwargs["serverSelectionTimeoutMS"] == 30_000


def test_get_client_override_uses_health_timeout():
    with patch("hybrid_search.mongo.AsyncIOMotorClient") as client:
        get_client(_settings(), server_selection_timeout_ms=2_000)
    assert client.call_args.kwargs["serverSelectionTimeoutMS"] == 2_000


def test_get_client_uses_tls_by_default():
    with patch("hybrid_search.mongo.AsyncIOMotorClient") as client:
        get_client(_settings())
    kwargs = client.call_args.kwargs
    assert kwargs["tlsCAFile"] == certifi.where()
    assert "tls" not in kwargs


def test_get_client_disables_tls_for_plaintext_local():
    with patch("hybrid_search.mongo.AsyncIOMotorClient") as client:
        get_client(_settings(mongodb_tls=False))
    kwargs = client.call_args.kwargs
    assert kwargs["tls"] is False
    assert "tlsCAFile" not in kwargs


def test_get_client_tls_parameter_overrides_settings():
    with patch("hybrid_search.mongo.AsyncIOMotorClient") as client:
        get_client(_settings(mongodb_tls=False), tls=True)
    assert client.call_args.kwargs["tlsCAFile"] == certifi.where()
