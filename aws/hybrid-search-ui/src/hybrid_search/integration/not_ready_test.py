"""A query against a database with no indexes must fail with a clear error."""

from __future__ import annotations

import logging

from typer.testing import CliRunner

from hybrid_search.cli.app import app
from hybrid_search.settings import clear_settings_cache

FRESH_DATABASE = "hybrid_search_not_ready"
runner = CliRunner()


def test_query_without_indexes_exits_nonzero(caplog):
    clear_settings_cache()
    with caplog.at_level(logging.ERROR):
        result = runner.invoke(
            app,
            ["query", "--query", "risk", "--mode", "keyword", "--no-llm"],
            env={"MONGODB_DATABASE": FRESH_DATABASE},
        )

    assert result.exit_code == 1
    assert "not ready" in caplog.text
    assert "autoembed_idx" in caplog.text
    assert "text_idx" in caplog.text
