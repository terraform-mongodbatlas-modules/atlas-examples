from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from pydantic import SecretStr

import hybrid_search.cli.query_logic as query_logic_module
from hybrid_search.cli.query_logic import QueryInput
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui.query_logic import QueryResult

_MODULE = query_logic_module.__name__
_SETTINGS = HybridSearchSettings(mongodb_uri=SecretStr("mongodb://localhost"))


def _result() -> QueryResult:
    return QueryResult(
        references=[{"file_path": "docs/a.md", "content": "ctx", "score": 0.9}],
        answer="answer",
        source_files=["a.md"],
        modes=SearchModes(llm=False),
        search_result=MagicMock(),
    )


@pytest.mark.asyncio
async def test_run_query_async_maps_answer_query_result(monkeypatch):
    client = MagicMock()
    client.close = MagicMock()
    monkeypatch.setattr(query_logic_module, "get_client", lambda _settings: client)
    monkeypatch.setattr(query_logic_module, "chunks_collection", lambda _c, _s: MagicMock())
    answer = AsyncMock(return_value=_result())
    with patch(f"{_MODULE}.answer_query", answer):
        output = await query_logic_module._run_query_async(
            QueryInput(settings=_SETTINGS, query="risk", modes=SearchModes(llm=False))
        )

    assert output.exit_code == 0
    assert output.answer == "answer"
    assert output.source_files == ["a.md"]
    assert output.references[0]["file_path"] == "docs/a.md"
    assert answer.await_args.kwargs["modes"] == SearchModes(llm=False)
    client.close.assert_called_once()


@pytest.mark.asyncio
async def test_run_query_async_returns_nonzero_on_runtime_error(monkeypatch, caplog):
    client = MagicMock()
    client.close = MagicMock()
    monkeypatch.setattr(query_logic_module, "get_client", lambda _settings: client)
    monkeypatch.setattr(query_logic_module, "chunks_collection", lambda _c, _s: MagicMock())
    with patch(f"{_MODULE}.answer_query", AsyncMock(side_effect=RuntimeError("indexes not ready"))):
        output = await query_logic_module._run_query_async(
            QueryInput(settings=_SETTINGS, query="risk", modes=SearchModes(llm=False))
        )

    assert output.exit_code == 1
    assert output.error == "indexes not ready"
    client.close.assert_called_once()
