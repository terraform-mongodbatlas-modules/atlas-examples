from __future__ import annotations

from contextlib import ExitStack
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import SecretStr

from hybrid_search.search import RetrievalPipeline, SearchResult
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui import query_steps
from hybrid_search.ui.query_logic import QueryResult

_REFERENCES = [{"file_path": "docs/a.pdf", "content": "ctx", "score": 0.9}]
_SEARCH_RESULT = SearchResult(
    references=_REFERENCES,
    pipeline=RetrievalPipeline.RANK_FUSION,
)
_SETTINGS = HybridSearchSettings(
    mongodb_uri=SecretStr("mongodb://localhost"),
    voyage_api_key=SecretStr("key"),
)
_MODULE = query_steps.__name__


class _FakeStepCtx:
    def __init__(self, **_kwargs):
        self.output = None
        self.update = AsyncMock()

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_args):
        return None


def _chainlit_stack(stack: ExitStack, steps: list[_FakeStepCtx] | None = None):
    class RecordingStepCtx(_FakeStepCtx):
        def __init__(self, **_kwargs):
            super().__init__()
            if steps is not None:
                steps.append(self)

    stack.enter_context(patch.object(query_steps.cl, "Step", RecordingStepCtx))


@pytest.mark.asyncio
async def test_run_query_with_steps_calls_retrieve_then_answer():
    retrieve = AsyncMock(return_value=_SEARCH_RESULT)
    answer = AsyncMock(
        return_value=QueryResult(
            references=_REFERENCES,
            answer="generated",
            source_files=["a.pdf"],
            modes=SearchModes(),
            search_result=_SEARCH_RESULT,
        )
    )
    with ExitStack() as stack:
        _chainlit_stack(stack)
        stack.enter_context(patch(f"{_MODULE}.retrieve", retrieve))
        stack.enter_context(patch(f"{_MODULE}.answer_or_format", answer))
        result = await query_steps.run_query_with_steps(
            "risk",
            settings=_SETTINGS,
            collection=MagicMock(),
            voyage=MagicMock(),
            modes=SearchModes(),
        )

    retrieve.assert_awaited_once()
    answer.assert_awaited_once()
    assert answer.await_args.args[1] == _SEARCH_RESULT
    assert result.answer == "generated"


@pytest.mark.asyncio
async def test_run_query_with_steps_retrieval_only_formats_in_answer_step():
    retrieve = AsyncMock(return_value=_SEARCH_RESULT)
    answer = AsyncMock(
        return_value=QueryResult(
            references=_REFERENCES,
            answer=None,
            source_files=["a.pdf"],
            modes=SearchModes(keyword=True, vector=True, llm=False),
            search_result=_SEARCH_RESULT,
        )
    )
    steps: list[_FakeStepCtx] = []
    with ExitStack() as stack:
        _chainlit_stack(stack, steps)
        stack.enter_context(patch(f"{_MODULE}.retrieve", retrieve))
        stack.enter_context(patch(f"{_MODULE}.answer_or_format", answer))
        await query_steps.run_query_with_steps(
            "risk",
            settings=_SETTINGS,
            collection=MagicMock(),
            voyage=MagicMock(),
            modes=SearchModes(keyword=True, vector=True, llm=False),
        )

    answer.assert_awaited_once()
    assert steps[2].output is not None
    assert "a.pdf" in steps[2].output


@pytest.mark.asyncio
async def test_retrieval_status_keyword_only():
    status = query_steps._retrieval_status(
        SearchResult(references=[], pipeline=RetrievalPipeline.KEYWORD),
        SearchModes(keyword=True, vector=False),
    )
    assert status == "Keyword search (no query embedding)"
