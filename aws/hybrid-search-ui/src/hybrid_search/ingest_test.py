from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr

import hybrid_search.ingest as ingest_module
from hybrid_search.settings import HybridSearchSettings


def _settings(**overrides: object) -> HybridSearchSettings:
    base: dict[str, object] = {"mongodb_uri": SecretStr("mongodb://localhost")}
    base.update(overrides)
    return HybridSearchSettings(**base)


@pytest.mark.asyncio
async def test_ingest_upserts_one_doc_per_chunk(tmp_path: Path):
    path = tmp_path / "doc.txt"
    path.write_text("hello world\n\nsecond paragraph")
    collection = MagicMock()
    collection.bulk_write = AsyncMock()

    result = await ingest_module.ingest_file(path, settings=_settings(), collection=collection)
    assert result.chunk_count == 1
    ops = collection.bulk_write.await_args.args[0]
    assert len(ops) == 1
    assert ops[0]._filter == {"_id": f"{path}#0"}
    assert "vector" not in ops[0]._doc


@pytest.mark.asyncio
async def test_ingest_splits_large_text(tmp_path: Path):
    path = tmp_path / "big.txt"
    path.write_text("\n\n".join(["x" * 4000] * 4))
    collection = MagicMock()
    collection.bulk_write = AsyncMock()

    result = await ingest_module.ingest_file(
        path, settings=_settings(chunk_max_tokens=2500), collection=collection
    )
    assert result.chunk_count == 2
    ops = collection.bulk_write.await_args.args[0]
    assert [op._filter["_id"] for op in ops] == [f"{path}#0", f"{path}#1"]


@pytest.mark.asyncio
async def test_ingest_skips_empty_chunks(tmp_path: Path, monkeypatch):
    path = tmp_path / "doc.txt"
    path.write_text("hello")

    def fake_chunk(_text, *, max_tokens):
        del max_tokens
        return ["", "good", "   "]

    collection = MagicMock()
    collection.bulk_write = AsyncMock()
    monkeypatch.setattr(ingest_module.extract_module, "chunk_text", fake_chunk)
    result = await ingest_module.ingest_file(path, settings=_settings(), collection=collection)
    assert result.chunk_count == 1
    ops = collection.bulk_write.await_args.args[0]
    assert len(ops) == 1
    assert ops[0]._doc["content"] == "good"


@pytest.mark.asyncio
async def test_ingest_uses_source_name_for_stored_file_path(tmp_path: Path):
    path = tmp_path / "upload-temp.txt"
    path.write_text("hello world")
    collection = MagicMock()
    collection.bulk_write = AsyncMock()

    await ingest_module.ingest_file(
        path,
        settings=_settings(),
        collection=collection,
        source_name="NIST.AI.100-1.pdf",
    )
    ops = collection.bulk_write.await_args.args[0]
    assert ops[0]._filter == {"_id": "NIST.AI.100-1.pdf#0"}
    assert ops[0]._doc["file_path"] == "NIST.AI.100-1.pdf"


@pytest.mark.asyncio
async def test_ingest_progress_callback(tmp_path: Path):
    path = tmp_path / "doc.txt"
    path.write_text("hello\n\nworld")
    collection = MagicMock()
    collection.bulk_write = AsyncMock()
    steps: list[str] = []

    await ingest_module.ingest_file(
        path,
        settings=_settings(),
        collection=collection,
        on_progress=steps.append,
    )
    assert steps == ["Stored 1 chunks", "Completed processing file"]


@pytest.mark.asyncio
async def test_ingested_display_names():
    collection = MagicMock()
    collection.distinct = AsyncMock(return_value=["NIST.AI.100-1.pdf", "/tmp/notes.txt"])
    names = await ingest_module.ingested_display_names(collection)
    assert names == {"NIST.AI.100-1.pdf", "notes.txt"}


def test_skip_reason_for_filename():
    ingested = {"a.pdf"}
    batch: set[str] = set()
    assert ingest_module.skip_reason_for_filename("a.pdf", ingested=ingested, batch=batch) == (
        "already ingested"
    )
    assert ingest_module.skip_reason_for_filename("b.pdf", ingested=ingested, batch=batch) is None
    batch.add("b.pdf")
    assert ingest_module.skip_reason_for_filename("b.pdf", ingested=ingested, batch=batch) == (
        "already ingested"
    )


@pytest.mark.asyncio
async def test_list_ingested_files_groups_by_file_path():
    collection = MagicMock()
    collection.aggregate = MagicMock(
        return_value=MagicMock(
            to_list=AsyncMock(
                return_value=[
                    {"_id": "/tmp/a.pdf", "chunk_count": 3},
                    {"_id": "/tmp/b.txt", "chunk_count": 1},
                ]
            )
        )
    )
    files = await ingest_module.list_ingested_files(collection)
    assert [item.display_name for item in files] == ["a.pdf", "b.txt"]
    assert files[0].chunk_count == 3


@pytest.mark.asyncio
async def test_delete_by_file_path():
    collection = MagicMock()
    collection.delete_many = AsyncMock(return_value=MagicMock(deleted_count=5))
    result = await ingest_module.delete_by_file_path("/tmp/a.pdf", collection=collection)
    assert result.chunk_count == 5
    collection.delete_many.assert_awaited_once_with({"file_path": "/tmp/a.pdf"})


@pytest.mark.asyncio
async def test_delete_all_chunks():
    collection = MagicMock()
    collection.delete_many = AsyncMock(return_value=MagicMock(deleted_count=12))
    deleted = await ingest_module.delete_all_chunks(collection=collection)
    assert deleted == 12
    collection.delete_many.assert_awaited_once_with({})
