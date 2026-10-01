from __future__ import annotations

import pytest
import typer
from pydantic import SecretStr

import hybrid_search.cli.cmd_query as cmd_module
from hybrid_search.cli.cmd_query import cmd_query, modes_for
from hybrid_search.cli.query_logic import QueryOutput
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings


def _settings() -> HybridSearchSettings:
    return HybridSearchSettings(mongodb_uri=SecretStr("mongodb://localhost"))


@pytest.mark.parametrize(
    ("mode", "expected"),
    [
        ("keyword", SearchModes(keyword=True, vector=False, llm=False)),
        ("vector", SearchModes(keyword=False, vector=True, llm=False)),
        ("rank_fusion", SearchModes(keyword=True, vector=True, llm=False)),
    ],
)
def test_modes_for_maps_mode_and_no_llm(mode, expected):
    assert modes_for(mode, no_llm=True) == expected


def test_modes_for_defaults_llm_on():
    assert modes_for("keyword", no_llm=False).llm is True


def test_modes_for_rejects_unknown_mode():
    with pytest.raises(typer.BadParameter):
        modes_for("bogus", no_llm=True)


def _capture(monkeypatch, output: QueryOutput) -> list:
    calls: list = []
    monkeypatch.setattr(cmd_module, "get_settings", _settings)
    monkeypatch.setattr(cmd_module, "apply_log_level", lambda _level: None)
    monkeypatch.setattr(
        cmd_module,
        "run_query",
        lambda input: calls.append(input) or output,
    )
    return calls


def test_cmd_query_passes_mode_and_no_llm(monkeypatch):
    calls = _capture(monkeypatch, QueryOutput(answer="ok"))

    cmd_query(query="risk", mode="vector", no_llm=True)

    assert calls[0].query == "risk"
    assert calls[0].modes == SearchModes(keyword=False, vector=True, llm=False)


def test_cmd_query_exits_nonzero(monkeypatch):
    _capture(monkeypatch, QueryOutput(exit_code=1, error="indexes not ready"))

    with pytest.raises(typer.Exit) as excinfo:
        cmd_query(query="risk", mode="keyword", no_llm=True)

    assert excinfo.value.exit_code == 1
