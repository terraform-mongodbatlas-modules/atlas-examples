from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

from fastapi.testclient import TestClient
from pydantic import SecretStr
from pymongo.errors import ServerSelectionTimeoutError

import hybrid_search.ui.health_endpoint as health_module
from hybrid_search.app import app
from hybrid_search.health import IndexState
from hybrid_search.settings import HybridSearchSettings

client = TestClient(app)


def _patch_health(monkeypatch, *, states: list[IndexState], has_chunks: bool) -> None:
    settings = HybridSearchSettings(mongodb_uri=SecretStr("mongodb://localhost"))
    collection = MagicMock()
    collection.count_documents = AsyncMock(return_value=1 if has_chunks else 0)
    monkeypatch.setattr(health_module, "get_settings", lambda: settings)
    monkeypatch.setattr(health_module, "get_client", MagicMock())
    monkeypatch.setattr(health_module, "chunks_collection", lambda _client, _settings: collection)
    monkeypatch.setattr(health_module, "index_states", AsyncMock(return_value=states))


def test_health_returns_flags_and_no_extra_data(monkeypatch):
    _patch_health(
        monkeypatch,
        states=[
            IndexState(name="autoembed_idx", status="READY"),
            IndexState(name="text_idx", status="READY"),
        ],
        has_chunks=True,
    )

    response = client.get("/health")

    assert response.status_code == 200
    assert response.json() == {
        "indexes_ready": True,
        "data_ingested": True,
        "indexes": [
            {"name": "autoembed_idx", "status": "READY"},
            {"name": "text_idx", "status": "READY"},
        ],
    }


def test_health_returns_503_when_mongo_unreachable(monkeypatch):
    monkeypatch.setattr(
        health_module,
        "get_client",
        MagicMock(side_effect=ServerSelectionTimeoutError("no server")),
    )

    response = client.get("/health")

    assert response.status_code == 503
    assert response.json() == {"indexes_ready": False, "data_ingested": False, "indexes": []}


def test_root_is_not_intercepted():
    response = client.get("/")

    assert response.status_code == 200
    assert "text/html" in response.headers["content-type"]


def test_docs_and_openapi_are_served():
    assert client.get("/openapi.json").status_code == 200
    assert client.get("/docs").status_code == 200
