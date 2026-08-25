from __future__ import annotations

import logging

import pytest
from pydantic import SecretStr

from hybrid_search.settings import (
    HybridSearchSettings,
    apply_log_level,
    clear_settings_cache,
    get_settings,
)


@pytest.fixture(autouse=True)
def _clear_settings_cache():
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def _settings(**overrides: object) -> HybridSearchSettings:
    base = {
        "mongodb_uri": SecretStr("mongodb+srv://user:pass@cluster"),
        "voyage_api_key": SecretStr("voyage-key"),
    }
    base.update(overrides)
    return HybridSearchSettings(**base)


def test_defaults():
    settings = _settings()
    assert settings.top_k == 20
    assert settings.mongodb_database == "hybrid_search"
    assert settings.vector_index_name == "vector_idx"
    assert settings.text_index_name == "text_idx"


def test_env_override(monkeypatch):
    monkeypatch.setenv("TOP_K", "15")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("VOYAGE_API_KEY", "key")
    settings = HybridSearchSettings()
    assert settings.top_k == 15


def test_rejects_bad_mongodb_uri():
    with pytest.raises(ValueError, match="mongodb_uri"):
        _settings(mongodb_uri=SecretStr("http://bad"))


def test_skip_index_creation_default():
    assert _settings().skip_index_creation is False


def test_skip_index_creation_env(monkeypatch):
    monkeypatch.setenv("SKIP_INDEX_CREATION", "true")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost")
    monkeypatch.setenv("VOYAGE_API_KEY", "key")
    clear_settings_cache()
    assert get_settings().skip_index_creation is True


def test_log_level_default():
    assert _settings().log_level == "INFO"


def test_log_level_env_uppercases(monkeypatch):
    monkeypatch.setenv("LOG_LEVEL", "debug")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost")
    monkeypatch.setenv("VOYAGE_API_KEY", "key")
    clear_settings_cache()
    assert get_settings().log_level == "DEBUG"


def test_apply_log_level_configures_root_and_hybrid_search(monkeypatch):
    configured: dict[str, object] = {}

    def fake_basic_config(**kwargs: object) -> None:
        configured.update(kwargs)

    monkeypatch.setattr(logging, "basicConfig", fake_basic_config)
    apply_log_level("DEBUG")
    assert configured["level"] == "DEBUG"
    apply_log_level("INFO")
