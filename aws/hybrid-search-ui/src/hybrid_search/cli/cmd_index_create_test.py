from __future__ import annotations

from pydantic import SecretStr

import hybrid_search.cli.cmd_index_create as cmd_module
from hybrid_search.cli.cmd_index_create import cmd_index_create
from hybrid_search.cli.index_create_logic import IndexCreateResult
from hybrid_search.settings import HybridSearchSettings


def test_cmd_index_create_applies_settings_log_level(monkeypatch):
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        log_level="DEBUG",
    )
    applied: list[str] = []
    monkeypatch.setattr(cmd_module, "get_settings", lambda: settings)
    monkeypatch.setattr(cmd_module, "apply_log_level", applied.append)
    monkeypatch.setattr(cmd_module, "index_create", lambda _input: IndexCreateResult())

    cmd_index_create()

    assert applied == ["DEBUG"]
