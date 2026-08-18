from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr

import hybrid_search.ingest as ingest_module
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.voyage import DocumentEmbedResult


@pytest.mark.asyncio
async def test_ingest_upserts_one_doc_per_chunk(tmp_path: Path, monkeypatch):
    path = tmp_path / "doc.txt"
    path.write_text("hello world")
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    collection = MagicMock()
    collection.bulk_write = AsyncMock()
    voyage = MagicMock()

    async def fake_embed(_text, *, client, settings):
        del client, settings
        return DocumentEmbedResult(
            chunk_texts=["chunk-a", "chunk-b"],
            embeddings=[[0.1], [0.2]],
        )

    monkeypatch.setattr(ingest_module.voyage_module, "embed_document", fake_embed)
    result = await ingest_module.ingest_file(
        path, settings=settings, collection=collection, voyage=voyage
    )
    assert result.chunk_count == 2
    ops = collection.bulk_write.await_args.args[0]
    assert len(ops) == 2
    assert ops[0]._filter == {"_id": f"{path}#0"}


@pytest.mark.asyncio
async def test_ingest_splits_large_text(tmp_path: Path, monkeypatch):
    path = tmp_path / "big.txt"
    path.write_text("x" * (120_000 * 4))
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    collection = MagicMock()
    collection.bulk_write = AsyncMock()
    calls: list[str] = []

    async def fake_embed(text, *, client, settings):
        del client, settings
        calls.append(text)
        return DocumentEmbedResult(chunk_texts=["c"], embeddings=[[0.1]])

    monkeypatch.setattr(ingest_module.voyage_module, "embed_document", fake_embed)
    result = await ingest_module.ingest_file(
        path, settings=settings, collection=collection, voyage=MagicMock()
    )
    assert result.chunk_count == 2
    assert len(calls) == 2


@pytest.mark.asyncio
async def test_ingest_skips_empty_chunks_and_zero_vectors(tmp_path: Path, monkeypatch):
    path = tmp_path / "doc.txt"
    path.write_text("hello")
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    collection = MagicMock()
    collection.bulk_write = AsyncMock()

    async def fake_embed(_text, *, client, settings):
        del client, settings
        return DocumentEmbedResult(
            chunk_texts=["", "good", "   "],
            embeddings=[[0.0, 0.0], [0.1], [0.2, 0.0]],
        )

    monkeypatch.setattr(ingest_module.voyage_module, "embed_document", fake_embed)
    result = await ingest_module.ingest_file(
        path, settings=settings, collection=collection, voyage=MagicMock()
    )
    assert result.chunk_count == 1
    ops = collection.bulk_write.await_args.args[0]
    assert len(ops) == 1
    assert ops[0]._doc["content"] == "good"


@pytest.mark.asyncio
async def test_ingest_progress_callback(tmp_path: Path, monkeypatch):
    path = tmp_path / "doc.txt"
    path.write_text("hello")
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    collection = MagicMock()
    collection.bulk_write = AsyncMock()
    steps: list[str] = []

    async def fake_embed(_text, *, client, settings):
        del client, settings
        return DocumentEmbedResult(chunk_texts=["a", "b"], embeddings=[[0.1], [0.2]])

    monkeypatch.setattr(ingest_module.voyage_module, "embed_document", fake_embed)
    await ingest_module.ingest_file(
        path,
        settings=settings,
        collection=collection,
        voyage=MagicMock(),
        on_progress=steps.append,
    )
    assert steps == ["Embedding 2 chunks", "Stored 2 chunks", "Completed processing file"]


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
