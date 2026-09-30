from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

from pydantic import SecretStr

import hybrid_search.cli.ingest_logic as ingest_logic_module
from hybrid_search.cli.ingest_logic import IngestInput, ingest
from hybrid_search.ingest import IngestResult
from hybrid_search.ingest_state import content_hash, source_key
from hybrid_search.settings import HybridSearchSettings


def _settings(**overrides: object) -> HybridSearchSettings:
    base: dict[str, object] = {"mongodb_uri": SecretStr("mongodb://localhost")}
    base.update(overrides)
    return HybridSearchSettings(**base)


def _patch_module(monkeypatch, *, states: dict[str, str], ingest_file: AsyncMock):
    client = MagicMock()
    client.close = MagicMock()
    collection = MagicMock()
    collection.delete_many = AsyncMock()
    state_collection = MagicMock()
    monkeypatch.setattr(ingest_logic_module, "get_client", lambda _settings: client)
    monkeypatch.setattr(ingest_logic_module, "chunks_collection", lambda _c, _s: collection)
    monkeypatch.setattr(
        ingest_logic_module, "ingest_state_collection", lambda _c, _s: state_collection
    )
    monkeypatch.setattr(ingest_logic_module, "load_states", AsyncMock(return_value=states))
    upsert = AsyncMock()
    monkeypatch.setattr(ingest_logic_module, "upsert_state", upsert)
    monkeypatch.setattr(ingest_logic_module, "ingest_file", ingest_file)
    return client, collection, state_collection, upsert


def _tree(tmp_path: Path) -> Path:
    root = tmp_path / "docs"
    (root / "nested").mkdir(parents=True)
    (root / "top.md").write_text("top")
    (root / "nested" / "note.txt").write_text("note")
    (root / "nested" / "paper.pdf").write_bytes(b"%PDF-1.4")
    (root / "nested" / "data.csv").write_text("a,b")
    return root


def test_ingest_scans_supported_files_recursively(monkeypatch, tmp_path: Path):
    root = _tree(tmp_path)
    ingest_file = AsyncMock(return_value=IngestResult(chunk_count=1))
    _patch_module(monkeypatch, states={}, ingest_file=ingest_file)

    result = ingest(IngestInput(settings=_settings(), dirs=[root]))

    assert result.exit_code == 0
    assert result.ingested == 3
    ingested_names = {call.kwargs["source_name"] for call in ingest_file.await_args_list}
    assert ingested_names == {
        source_key(root / "top.md"),
        source_key(root / "nested" / "note.txt"),
        source_key(root / "nested" / "paper.pdf"),
    }


def test_ingest_skips_unchanged_hash(monkeypatch, tmp_path: Path):
    root = _tree(tmp_path)
    path = root / "top.md"
    states = {source_key(path): content_hash(path)}
    ingest_file = AsyncMock(return_value=IngestResult(chunk_count=1))
    _patch_module(monkeypatch, states=states, ingest_file=ingest_file)

    result = ingest(IngestInput(settings=_settings(), dirs=[root]))

    assert result.skipped >= 1
    skipped_names = [call.kwargs["source_name"] for call in ingest_file.await_args_list]
    assert source_key(path) not in skipped_names


def test_ingest_reingests_on_hash_change(monkeypatch, tmp_path: Path):
    root = _tree(tmp_path)
    path = root / "top.md"
    states = {source_key(path): "stale-digest"}
    ingest_file = AsyncMock(return_value=IngestResult(chunk_count=1))
    _client, collection, _state, _upsert = _patch_module(
        monkeypatch, states=states, ingest_file=ingest_file
    )

    result = ingest(IngestInput(settings=_settings(), dirs=[root]))

    assert result.ingested == 3
    collection.delete_many.assert_any_await({"file_path": source_key(path)})
    ingested_names = {call.kwargs["source_name"] for call in ingest_file.await_args_list}
    assert source_key(path) in ingested_names


def test_ingest_force_reingests_unchanged(monkeypatch, tmp_path: Path):
    root = _tree(tmp_path)
    path = root / "top.md"
    states = {source_key(path): content_hash(path)}
    ingest_file = AsyncMock(return_value=IngestResult(chunk_count=1))
    _client, collection, _state, _upsert = _patch_module(
        monkeypatch, states=states, ingest_file=ingest_file
    )

    result = ingest(IngestInput(settings=_settings(), dirs=[root], force=True))

    assert result.skipped == 0
    assert result.ingested == 3
    collection.delete_many.assert_any_await({"file_path": source_key(path)})


def test_ingest_stores_state_after_ingest(monkeypatch, tmp_path: Path):
    root = _tree(tmp_path)
    path = root / "top.md"
    ingest_file = AsyncMock(return_value=IngestResult(chunk_count=4))
    _client, _collection, _state, upsert = _patch_module(
        monkeypatch, states={}, ingest_file=ingest_file
    )

    ingest(IngestInput(settings=_settings(), dirs=[root]))

    stored = {call.args[1].source_key: call.args[1] for call in upsert.await_args_list}
    assert stored[source_key(path)].content_hash == content_hash(path)
    assert stored[source_key(path)].chunk_count == 4


def test_ingest_returns_nonzero_on_failure(monkeypatch, tmp_path: Path):
    root = _tree(tmp_path)
    ingest_file = AsyncMock(side_effect=RuntimeError("boom"))
    client, _collection, _state, _upsert = _patch_module(
        monkeypatch, states={}, ingest_file=ingest_file
    )

    result = ingest(IngestInput(settings=_settings(), dirs=[root]))

    assert result.exit_code == 1
    client.close.assert_called_once()


def test_ingest_returns_nonzero_for_missing_dir(monkeypatch, tmp_path: Path):
    ingest_file = AsyncMock()
    client, _collection, _state, _upsert = _patch_module(
        monkeypatch, states={}, ingest_file=ingest_file
    )

    result = ingest(IngestInput(settings=_settings(), dirs=[tmp_path / "missing"]))

    assert result.exit_code == 1
    ingest_file.assert_not_awaited()
    client.close.assert_called_once()


def test_ingest_skips_when_flag_set(monkeypatch, tmp_path: Path):
    get_client = MagicMock()
    monkeypatch.setattr(ingest_logic_module, "get_client", get_client)

    result = ingest(IngestInput(settings=_settings(skip_ingest=True), dirs=[tmp_path]))

    assert result.exit_code == 0
    get_client.assert_not_called()
