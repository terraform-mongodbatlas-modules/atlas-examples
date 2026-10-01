from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import SecretStr

from hybrid_search.search import RetrievalPipeline, SearchResult
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui import query_logic

_REFERENCES = [{"file_path": "docs/a.pdf", "content": "ctx", "score": 0.9}]
_SETTINGS = HybridSearchSettings(mongodb_uri=SecretStr("mongodb://localhost"))
_MODULE = query_logic.__name__


def _collection(states: dict[str, str]) -> MagicMock:
    collection = MagicMock()
    collection.name = "chunks"
    collection.list_search_indexes.return_value.to_list = AsyncMock(
        return_value=[{"name": name, "status": status} for name, status in states.items()]
    )
    return collection


@pytest.mark.asyncio
async def test_retrieve_keyword_only_passes_text_query():
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
            collection=_collection({"autoembed_idx": "READY", "text_idx": "READY"}),
        )

    assert search.await_args.args[0] == "risk"
    assert search_result.references == _REFERENCES
    assert search_result.pipeline == RetrievalPipeline.KEYWORD


@pytest.mark.asyncio
async def test_retrieve_raises_when_indexes_not_ready():
    with pytest.raises(RuntimeError, match="autoembed_idx"):
        await query_logic.retrieve(
            "risk",
            modes=SearchModes(keyword=True, vector=False),
            settings=_SETTINGS,
            collection=_collection({"autoembed_idx": "BUILDING", "text_idx": "READY"}),
        )


@pytest.mark.asyncio
async def test_answer_or_format_skips_llm_when_disabled():
    search_result = SearchResult(
        references=_REFERENCES,
        pipeline=RetrievalPipeline.RANK_FUSION,
    )
    result = await query_logic.answer_or_format(
        "risk",
        search_result,
        modes=SearchModes(llm=False),
        settings=_SETTINGS,
    )

    assert result.answer is None
    assert result.source_files == ["a.pdf"]
