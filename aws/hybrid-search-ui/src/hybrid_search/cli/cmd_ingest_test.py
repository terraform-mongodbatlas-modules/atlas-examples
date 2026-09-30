from __future__ import annotations

from pathlib import Path

import pytest
import typer
from pydantic import SecretStr

import hybrid_search.cli.cmd_ingest as cmd_module
from hybrid_search.cli.cmd_ingest import cmd_ingest
from hybrid_search.cli.ingest_logic import IngestResult
from hybrid_search.settings import HybridSearchSettings


def _settings(**overrides: object) -> HybridSearchSettings:
    base: dict[str, object] = {"mongodb_uri": SecretStr("mongodb://localhost")}
    base.update(overrides)
    return HybridSearchSettings(**base)


def _capture(monkeypatch, settings: HybridSearchSettings) -> list:
    calls: list = []
    monkeypatch.setattr(cmd_module, "get_settings", lambda: settings)
    monkeypatch.setattr(cmd_module, "apply_log_level", lambda _level: None)
    monkeypatch.setattr(
        cmd_module,
        "ingest",
        lambda input: calls.append(input) or IngestResult(),
    )
    return calls


def test_cmd_ingest_defaults_to_settings_dirs(monkeypatch):
    seed_dir = Path("seed")
    settings = _settings(document_dirs=[Path("/a"), Path("/b")], seed_dir=seed_dir)
    calls = _capture(monkeypatch, settings)

    cmd_ingest(dirs=[], skip_ingest=None, force=False)

    assert calls[0].dirs == [Path("/a"), Path("/b"), seed_dir]


def test_cmd_ingest_explicit_dir_replaces_defaults(monkeypatch):
    settings = _settings(document_dirs=[Path("/a")], seed_dir=Path("seed"))
    calls = _capture(monkeypatch, settings)

    cmd_ingest(dirs=[Path("/custom")], skip_ingest=None, force=False)

    assert calls[0].dirs == [Path("/custom")]


def test_cmd_ingest_flag_overrides_env(monkeypatch):
    settings = _settings(skip_ingest=True)
    calls = _capture(monkeypatch, settings)

    cmd_ingest(dirs=[], skip_ingest=False, force=False)

    assert calls[0].settings.skip_ingest is False


def test_cmd_ingest_passes_force(monkeypatch):
    settings = _settings()
    calls = _capture(monkeypatch, settings)

    cmd_ingest(dirs=[], skip_ingest=None, force=True)

    assert calls[0].force is True


def test_cmd_ingest_exits_nonzero(monkeypatch):
    settings = _settings()
    monkeypatch.setattr(cmd_module, "get_settings", lambda: settings)
    monkeypatch.setattr(cmd_module, "apply_log_level", lambda _level: None)
    monkeypatch.setattr(cmd_module, "ingest", lambda _input: IngestResult(exit_code=1))

    with pytest.raises(typer.Exit) as excinfo:
        cmd_ingest(dirs=[], skip_ingest=None, force=False)

    assert excinfo.value.exit_code == 1
