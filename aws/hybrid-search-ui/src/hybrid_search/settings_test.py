from __future__ import annotations

import logging
from pathlib import Path

import pytest
from pydantic import SecretStr

import hybrid_search.settings as settings_module
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
    }
    base.update(overrides)
    return HybridSearchSettings(**base)


def test_defaults():
    settings = _settings()
    assert settings.top_k == 20
    assert settings.mongodb_database == "hybrid_search"
    assert settings.autoembed_model == "voyage-4-lite"
    assert settings.chunk_max_tokens == 512
    assert settings.vector_index_name == "autoembed_idx"
    assert settings.text_index_name == "text_idx"
    assert settings.demo_queries_path == Path("demo_queries.yaml")


def test_voyage_fields_are_not_settings():
    settings = _settings()
    assert not hasattr(settings, "voyage_api_key")
    assert not hasattr(settings, "voyage_model")


def test_env_override(monkeypatch):
    monkeypatch.setenv("TOP_K", "15")
    monkeypatch.setenv("DEMO_QUERIES_PATH", "/tmp/custom.yaml")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost:27017")
    monkeypatch.setenv("AUTOEMBED_MODEL", "voyage-4")
    settings = HybridSearchSettings()
    assert settings.top_k == 15
    assert settings.autoembed_model == "voyage-4"
    assert settings.demo_queries_path == Path("/tmp/custom.yaml")


def test_rejects_bad_mongodb_uri():
    with pytest.raises(ValueError, match="mongodb_uri"):
        _settings(mongodb_uri=SecretStr("http://bad"))


def test_skip_index_creation_default():
    assert _settings().skip_index_creation is False


def test_skip_index_creation_env(monkeypatch):
    monkeypatch.setenv("SKIP_INDEX_CREATION", "true")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost")
    clear_settings_cache()
    assert get_settings().skip_index_creation is True


def test_log_level_default():
    assert _settings().log_level == "INFO"


def test_log_level_env_uppercases(monkeypatch):
    monkeypatch.setenv("LOG_LEVEL", "debug")
    monkeypatch.setenv("MONGODB_URI", "mongodb://localhost")
    clear_settings_cache()
    assert get_settings().log_level == "DEBUG"


def test_chunk_max_tokens_accepts_bounds():
    assert _settings(chunk_max_tokens=40).chunk_max_tokens == 40
    assert _settings(chunk_max_tokens=512).chunk_max_tokens == 512
    assert _settings(chunk_max_tokens=1500).chunk_max_tokens == 1500


def test_chunk_max_tokens_rejects_below_minimum():
    with pytest.raises(ValueError, match="chunk_max_tokens"):
        _settings(chunk_max_tokens=39)


def test_chunk_max_tokens_rejects_zero_or_negative():
    with pytest.raises(ValueError, match="chunk_max_tokens"):
        _settings(chunk_max_tokens=0)
    with pytest.raises(ValueError, match="chunk_max_tokens"):
        _settings(chunk_max_tokens=-1)


def test_chunk_max_tokens_rejects_above_context_window(monkeypatch):
    monkeypatch.setattr(settings_module, "AUTOEMBED_CONTEXT_TOKENS", 1_000)
    with pytest.raises(ValueError, match="context window"):
        _settings(chunk_max_tokens=1_200)


def test_apply_log_level_configures_root_and_hybrid_search(monkeypatch):
    configured: dict[str, object] = {}

    def fake_basic_config(**kwargs: object) -> None:
        configured.update(kwargs)

    monkeypatch.setattr(logging, "basicConfig", fake_basic_config)
    apply_log_level("DEBUG")
    assert configured["level"] == "DEBUG"
    apply_log_level("INFO")
