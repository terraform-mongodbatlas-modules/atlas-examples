from __future__ import annotations

import inspect
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import voyageai
from motor.motor_asyncio import AsyncIOMotorCollection
from pymongo import ReplaceOne

from hybrid_search import extract as extract_module
from hybrid_search import voyage as voyage_module
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.voyage import DocumentEmbedResult, assert_nonzero_embeddings, is_zero_vector


@dataclass(frozen=True)
class IngestResult:
    chunk_count: int


@dataclass(frozen=True)
class IngestedFile:
    file_path: str
    chunk_count: int

    @property
    def display_name(self) -> str:
        return Path(self.file_path).name


@dataclass(frozen=True)
class DeleteResult:
    file_path: str
    chunk_count: int


def chunk_doc_id(file_path: str, chunk_index: int) -> str:
    return f"{file_path}#{chunk_index}"


OnProgress = Callable[[str], Any]


async def list_ingested_files(collection: AsyncIOMotorCollection) -> list[IngestedFile]:
    pipeline = [
        {"$group": {"_id": "$file_path", "chunk_count": {"$sum": 1}}},
        {"$sort": {"_id": 1}},
    ]
    cursor = collection.aggregate(pipeline)
    docs = await cursor.to_list(length=None)
    return [
        IngestedFile(file_path=doc["_id"], chunk_count=doc["chunk_count"])
        for doc in docs
        if doc.get("_id")
    ]


async def ingested_display_names(collection: AsyncIOMotorCollection) -> set[str]:
    file_paths = await collection.distinct("file_path")
    return {Path(path).name for path in file_paths if path}


def skip_reason_for_filename(
    name: str,
    *,
    ingested: set[str],
    batch: set[str],
) -> str | None:
    if name in ingested or name in batch:
        return "already ingested"
    return None


async def delete_by_file_path(
    file_path: str,
    *,
    collection: AsyncIOMotorCollection,
) -> DeleteResult:
    result = await collection.delete_many({"file_path": file_path})
    return DeleteResult(file_path=file_path, chunk_count=result.deleted_count)


async def delete_all_chunks(*, collection: AsyncIOMotorCollection) -> int:
    result = await collection.delete_many({})
    return result.deleted_count


async def ingest_file(
    path: Path,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    voyage: voyageai.AsyncClient,
    source_name: str | None = None,
    on_progress: OnProgress | None = None,
) -> IngestResult:
    extracted = extract_module.extract_text(path)
    file_path = source_name or str(path)
    batches = _text_batches(path, extracted.text)
    chunk_index = 0
    total = 0
    for batch in batches:
        embed = await voyage_module.embed_document(batch, client=voyage, settings=settings)
        assert_nonzero_embeddings(embed, voyage_base_url=settings.voyage_base_url)
        await _emit_progress(on_progress, f"Embedding {len(embed.chunk_texts)} chunks")
        ops = _upsert_ops(file_path, chunk_index, embed)
        if ops:
            await collection.bulk_write(ops, ordered=False)
            await _emit_progress(on_progress, f"Stored {len(ops)} chunks")
            chunk_index += len(ops)
            total += len(ops)
    if on_progress is not None:
        await _emit_progress(on_progress, "Completed processing file")
    return IngestResult(chunk_count=total)


async def _emit_progress(on_progress: OnProgress | None, message: str) -> None:
    if on_progress is None:
        return
    result = on_progress(message)
    if inspect.isawaitable(result):
        await result


def _text_batches(path: Path, text: str) -> list[str]:
    if extract_module.text_needs_split(text):
        if path.suffix.lower() == ".pdf":
            return list(
                extract_module.iter_pdf_page_groups(
                    path,
                    max_pages_per_group=extract_module.PDF_PAGES_PER_GROUP,
                )
            )
        midpoint = len(text) // 2
        return [text[:midpoint], text[midpoint:]]
    return [text]


def _upsert_ops(
    file_path: str,
    start_index: int,
    embed: DocumentEmbedResult,
) -> list[ReplaceOne]:
    ops: list[ReplaceOne] = []
    chunk_index = start_index
    for content, vector in zip(embed.chunk_texts, embed.embeddings, strict=True):
        if not content.strip() or is_zero_vector(vector):
            continue
        doc_id = chunk_doc_id(file_path, chunk_index)
        ops.append(
            ReplaceOne(
                {"_id": doc_id},
                {
                    "_id": doc_id,
                    "content": content,
                    "vector": vector,
                    "file_path": file_path,
                    "chunk_index": chunk_index,
                },
                upsert=True,
            )
        )
        chunk_index += 1
    return ops
