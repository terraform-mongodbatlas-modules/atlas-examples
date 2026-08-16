from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr

from hybrid_search.generate import GenerateResult
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui import query_logic as query_logic_module


@pytest.mark.asyncio
async def test_answer_query(monkeypatch):
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    voyage = MagicMock()
    collection = MagicMock()

    monkeypatch.setattr(
        query_logic_module._voyage,
        "embed_query",
        AsyncMock(return_value=[0.1, 0.2]),
    )
    monkeypatch.setattr(
        query_logic_module._search,
        "search",
        AsyncMock(return_value=[{"file_path": "/data/nist.pdf", "content": "ctx"}]),
    )
    monkeypatch.setattr(
        query_logic_module._generate,
        "generate_answer",
        AsyncMock(return_value=GenerateResult(answer="four functions", source_files=["nist.pdf"])),
    )

    result = await query_logic_module.answer_query(
        "What are the four functions?",
        settings=settings,
        collection=collection,
        voyage=voyage,
    )
    assert result.answer == "four functions"
    assert result.source_files == ["nist.pdf"]
