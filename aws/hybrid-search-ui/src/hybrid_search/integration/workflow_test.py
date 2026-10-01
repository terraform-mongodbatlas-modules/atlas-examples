"""Ingest then query, delete then query, and edit then re-ingest, all through the CLI.

Atlas Search indexes are eventually consistent, so the assertions poll the query
CLI until the expected reference appears or disappears.
"""

from __future__ import annotations

import asyncio
import time
from collections.abc import Callable
from pathlib import Path

from pymongo import MongoClient
from typer.testing import CliRunner

from hybrid_search.cli.app import app
from hybrid_search.ingest import delete_by_file_path
from hybrid_search.ingest_state import source_key
from hybrid_search.integration.conftest import TEST_DATABASE, integration_settings
from hybrid_search.mongo import get_client
from hybrid_search.settings import HybridSearchSettings, clear_settings_cache

QUERY = "quantum flux capacitor"
MODES = ("keyword", "vector", "rank_fusion")
POLL_TIMEOUT_S = 120
POLL_INTERVAL_S = 3
runner = CliRunner()

_LONG_PARAGRAPH = "The quantum flux capacitor regulates temporal drift across the fleet. " * 30
_EDIT_PARAGRAPH = "The quantum flux capacitor was decommissioned in the spring audit."


def _invoke(env: dict[str, str], args: list[str]):
    clear_settings_cache()
    return runner.invoke(app, args, env=env)


def _query_until(env: dict[str, str], mode: str, predicate: Callable[[str], bool]) -> str:
    deadline = time.monotonic() + POLL_TIMEOUT_S
    output = ""
    while time.monotonic() < deadline:
        result = _invoke(env, ["query", "--query", QUERY, "--mode", mode, "--no-llm"])
        assert result.exit_code == 0, result.output
        output = result.output
        if predicate(output):
            return output
        time.sleep(POLL_INTERVAL_S)
    return output


def _chunk_count(uri: str, file_path: str) -> int:
    client = MongoClient(uri)
    try:
        return client[TEST_DATABASE]["chunks"].count_documents({"file_path": file_path})
    finally:
        client.close()


def _delete_chunks(settings: HybridSearchSettings, file_path: str) -> None:
    async def run() -> None:
        client = get_client(settings)
        try:
            database = client[settings.mongodb_database]
            await delete_by_file_path(
                file_path,
                collection=database[settings.chunks_collection],
                state_collection=database["ingest_state"],
            )
        finally:
            client.close()

    asyncio.run(run())


def _integration_settings() -> HybridSearchSettings:
    return integration_settings()


def test_ingest_query_then_delete(tmp_path: Path):
    settings = _integration_settings()
    uri = settings.mongodb_uri.get_secret_value()
    env = {"MONGODB_DATABASE": TEST_DATABASE}
    doc = tmp_path / "delete_me.md"
    doc.write_text(f"# Risk Management\n\n{_LONG_PARAGRAPH}\n\n{_LONG_PARAGRAPH}\n")
    file_path = source_key(doc)

    index = _invoke(env, ["index", "create"])
    assert index.exit_code == 0, index.output

    ingest = _invoke(env, ["ingest", "run", "--dir", str(tmp_path)])
    assert ingest.exit_code == 0, ingest.output
    assert _chunk_count(uri, file_path) > 1

    for mode in MODES:
        output = _query_until(env, mode, lambda out: "delete_me.md" in out)
        assert "delete_me.md" in output, f"{mode} did not return the ingested file"

    _delete_chunks(settings, file_path)
    for mode in MODES:
        output = _query_until(env, mode, lambda out: "delete_me.md" not in out)
        assert "delete_me.md" not in output, f"{mode} still returned the deleted file"


def test_edit_reingest_replaces_chunks(tmp_path: Path):
    settings = _integration_settings()
    uri = settings.mongodb_uri.get_secret_value()
    env = {"MONGODB_DATABASE": TEST_DATABASE}
    doc = tmp_path / "edit_me.md"
    doc.write_text(f"# Risk Management\n\n{_LONG_PARAGRAPH}\n\n{_LONG_PARAGRAPH}\n")
    file_path = source_key(doc)

    index = _invoke(env, ["index", "create"])
    assert index.exit_code == 0, index.output
    first = _invoke(env, ["ingest", "run", "--dir", str(tmp_path)])
    assert first.exit_code == 0, first.output
    assert _chunk_count(uri, file_path) > 1

    doc.write_text(f"# Risk Management\n\n{_EDIT_PARAGRAPH}\n")
    second = _invoke(env, ["ingest", "run", "--dir", str(tmp_path)])
    assert second.exit_code == 0, second.output
    assert "skipping unchanged" not in second.output
    assert _chunk_count(uri, file_path) == 1
