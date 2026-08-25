import logging
from pathlib import Path
from unittest.mock import MagicMock

import pytest
from pydantic import SecretStr
from pymongo.errors import OperationFailure

import hybrid_search.ui.chat as chat_module
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
        voyage_api_key=SecretStr("key"),
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
