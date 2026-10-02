"""The CLI surface is flat: three commands, no sub-typers."""

from __future__ import annotations

from typer.testing import CliRunner

from hybrid_search.cli.app import app

runner = CliRunner()
COMMANDS = ("index-create", "ingest", "query")


def test_help_lists_the_flat_commands():
    result = runner.invoke(app, ["--help"])

    assert result.exit_code == 0, result.output
    for command in COMMANDS:
        assert command in result.output


def test_index_is_not_a_command_group():
    result = runner.invoke(app, ["index", "--help"])

    assert result.exit_code != 0, "index still resolves as a command group"
