from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import SecretStr

from hybrid_search.generate import GenerateResult
from hybrid_search.search import RetrievalPipeline, SearchResult
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui import query_logic

_REFERENCES = [{"file_path": "docs/a.pdf", "content": "ctx", "score": 0.9}]
_SEARCH_RESULT = SearchResult(
    references=_REFERENCES,
    pipeline=RetrievalPipeline.RANK_FUSION,
)
_SETTINGS = HybridSearchSettings(mongodb_uri=SecretStr("mongodb://localhost"))
_MODULE = query_logic.__name__


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("modes", "expect_generate"),
    [
        (SearchModes(), True),
        (SearchModes(keyword=True, vector=False), True),
        (SearchModes(keyword=False, vector=True), True),
        (SearchModes(keyword=True, vector=True, llm=False), False),
    ],
)
async def test_answer_query_modes(modes, expect_generate):
    collection = MagicMock()
    search = AsyncMock(return_value=_SEARCH_RESULT)
    generate = AsyncMock(return_value=GenerateResult(answer="generated", source_files=["a.pdf"]))
    with (
        patch(f"{_MODULE}.search_with_modes", search),
        patch(f"{_MODULE}.generate_answer", generate),
    ):
        result = await query_logic.answer_query(
            "risk",
            settings=_SETTINGS,
            collection=collection,
            modes=modes,
        )

    search.assert_awaited_once()
    assert search.await_args.kwargs["modes"] == modes
    assert "query_vector" not in search.await_args.args
    if expect_generate:
        generate.assert_awaited_once()
        assert result.answer == "generated"
    else:
        generate.assert_not_awaited()
        assert result.answer is None
        assert result.source_files == ["a.pdf"]
    assert result.search_result.pipeline == RetrievalPipeline.RANK_FUSION


@pytest.mark.asyncio
async def test_retrieve_keyword_only_passes_text_query():
    collection = MagicMock()
    search = AsyncMock(
        return_value=SearchResult(
            references=_REFERENCES,
            pipeline=RetrievalPipeline.KEYWORD,
        )
    )
    with patch(f"{_MODULE}.search_with_modes", search):
        search_result = await query_logic.retrieve(
            "risk",
            modes=SearchModes(keyword=True, vector=False),
            settings=_SETTINGS,
            collection=collection,
        )

    assert search.await_args.args[0] == "risk"
    assert search_result.references == _REFERENCES
    assert search_result.pipeline == RetrievalPipeline.KEYWORD
