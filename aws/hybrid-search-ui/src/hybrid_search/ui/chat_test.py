import logging
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr
from pymongo.errors import OperationFailure

import hybrid_search.ui.chat as chat_module
from hybrid_search.health import IndexState
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui.chat import is_allowed_upload, on_chat_start


def test_upload_extension_filter():
    assert is_allowed_upload(Path("doc.pdf"))
    assert is_allowed_upload(Path("notes.TXT"))
    assert not is_allowed_upload(Path("image.png"))


@pytest.mark.asyncio
async def test_on_chat_start_logs_startup_failure(monkeypatch, caplog, tmp_path):
    queries = tmp_path / "demo_queries.yaml"
    queries.write_text("queries:\n  - label: A\n    message: What is A?\n")
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        demo_queries_path=queries,
    )
    sent: list[str] = []

    class FakeMessage:
        def __init__(self, content: str):
            self.content = content

        async def send(self):
            sent.append(self.content)

    monkeypatch.setattr(chat_module, "get_settings", lambda: settings)
    monkeypatch.setattr(
        chat_module,
        "get_client",
        MagicMock(side_effect=OperationFailure("database hybrid_search not found", 26)),
    )
    monkeypatch.setattr(chat_module.cl, "Message", FakeMessage)
    caplog.set_level(logging.ERROR)

    await on_chat_start()

    assert "Startup failed" in caplog.text
    assert "database hybrid_search not found" in caplog.text
    assert sent
    assert "database hybrid_search not found" in sent[0]


class _FakeSession:
    def __init__(self, data: dict | None = None):
        self._data = data or {}

    def get(self, key: str, default: object = None) -> object:
        return self._data.get(key, default)

    def set(self, key: str, value: object) -> None:
        self._data[key] = value


class _FakeMessage:
    def __init__(self, content: str):
        self.content = content

    async def send(self) -> None:
        pass


def _patch_query_env(monkeypatch, states: list[IndexState]) -> list[str]:
    sent: list[str] = []

    class RecordingMessage(_FakeMessage):
        async def send(self) -> None:
            sent.append(self.content)

    monkeypatch.setattr(chat_module.cl, "user_session", _FakeSession({"collection": object()}))
    monkeypatch.setattr(chat_module.cl, "Message", RecordingMessage)
    monkeypatch.setattr(chat_module, "index_states", AsyncMock(return_value=states))
    return sent


@pytest.mark.asyncio
async def test_handle_query_stops_when_index_not_ready(monkeypatch):
    states = [IndexState(name="autoembed_idx", status="BUILDING")]
    sent = _patch_query_env(monkeypatch, states)
    run = AsyncMock()
    monkeypatch.setattr(chat_module, "run_query_with_steps", run)

    await chat_module._handle_query("what is risk?")

    run.assert_not_awaited()
    assert sent
    assert "not ready" in sent[0]
    assert "chunks.autoembed_idx BUILDING" in sent[0]


@pytest.mark.asyncio
async def test_handle_query_errors_when_index_failed(monkeypatch):
    states = [IndexState(name="text_idx", status="FAILED")]
    sent = _patch_query_env(monkeypatch, states)
    run = AsyncMock()
    monkeypatch.setattr(chat_module, "run_query_with_steps", run)

    await chat_module._handle_query("what is risk?")

    run.assert_not_awaited()
    assert sent
    assert "unavailable" in sent[0]
    assert "chunks.text_idx FAILED" in sent[0]
