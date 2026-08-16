from __future__ import annotations

from unittest.mock import AsyncMock

import pytest
from pydantic import SecretStr

import hybrid_search.generate as generate_module
import hybrid_search.llm as llm_module
from hybrid_search.settings import HybridSearchSettings


def test_unique_source_files_basenames_dedupe_skip_unknown():
    refs = [
        {"file_path": "/data/NIST.AI.100-1.pdf"},
        {"file_path": "uploads/NIST.AI.100-1.pdf"},
        {"file_path": "unknown_source"},
        {"file_path": ""},
        {"file_path": "owasp.md"},
    ]
    assert generate_module.unique_source_files(refs) == ["NIST.AI.100-1.pdf", "owasp.md"]


@pytest.mark.asyncio
async def test_generate_answer_retrieval_only():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        enable_llm=False,
    )
    result = await generate_module.generate_answer(
        "question",
        [{"file_path": "a.pdf", "content": "ctx"}],
        settings=settings,
    )
    assert "Retrieval-only" in result.answer
    assert result.source_files == ["a.pdf"]


@pytest.mark.asyncio
async def test_generate_answer_calls_llm(monkeypatch):
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        anthropic_api_key=SecretStr("anthropic-key"),
    )
    mock_run = AsyncMock(return_value="answer text")
    monkeypatch.setattr(llm_module, "run_rag_prompt", mock_run)
    result = await generate_module.generate_answer(
        "q", [{"file_path": "b.md", "content": "c"}], settings=settings
    )
    assert result.answer == "answer text"
    assert result.source_files == ["b.md"]
