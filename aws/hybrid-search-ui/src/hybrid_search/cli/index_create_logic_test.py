from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr

import hybrid_search.cli.index_create_logic as index_create_logic_module
from hybrid_search.cli.index_create_logic import IndexCreateInput, index_create
from hybrid_search.settings import HybridSearchSettings, clear_settings_cache, get_settings


@pytest.fixture(autouse=True)
def _clear_settings():
    clear_settings_cache()
    yield
    clear_settings_cache()


def test_index_create_prints_ready_lines(monkeypatch):
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    client = MagicMock()
    client.close = MagicMock()
    collection = MagicMock()
    db = MagicMock()
    db.__getitem__.return_value = collection
    client.__getitem__.return_value = db

    monkeypatch.setattr(index_create_logic_module, "get_client", lambda _settings: client)
    monkeypatch.setattr(
        index_create_logic_module,
        "create_chunks_indexes_if_missing",
        AsyncMock(),
    )
    monkeypatch.setattr(
        index_create_logic_module,
        "wait_chunks_indexes_ready",
        AsyncMock(
            return_value=[
                ("chunks", "vector_idx", "READY"),
                ("chunks", "text_idx", "READY"),
            ]
        ),
    )
    printed: list[str] = []
    monkeypatch.setattr("builtins.print", lambda line: printed.append(line))

    result = index_create(IndexCreateInput(settings=settings))
    assert result.exit_code == 0
    assert len(result.ready_lines) == 2
    assert all(" READY" in line and "chunks." in line for line in printed)


def test_index_create_ignores_skip_flag(monkeypatch):
    monkeypatch.setenv("SKIP_INDEX_CREATION", "true")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost")
    monkeypatch.setenv("VOYAGE_API_KEY", "key")
    clear_settings_cache()
    settings = get_settings().model_copy(update={"skip_index_creation": False})
    assert settings.skip_index_creation is False
