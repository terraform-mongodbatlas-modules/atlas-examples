from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import voyageai
from motor.motor_asyncio import AsyncIOMotorCollection
from pymongo import ReplaceOne

from hybrid_search import extract as extract_module
from hybrid_search import voyage as voyage_module
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.voyage import DocumentEmbedResult


@dataclass(frozen=True)
class IngestResult:
    chunk_count: int


def chunk_doc_id(file_path: str, chunk_index: int) -> str:
    return f"{file_path}#{chunk_index}"


async def ingest_file(
    path: Path,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    voyage: voyageai.AsyncClient,
) -> IngestResult:
    extracted = extract_module.extract_text(path)
    file_path = str(path)
    batches = _text_batches(path, extracted.text)
    chunk_index = 0
    total = 0
    for batch in batches:
        embed = await voyage_module.embed_document(batch, client=voyage, settings=settings)
        ops = _upsert_ops(file_path, chunk_index, embed)
        if ops:
            await collection.bulk_write(ops, ordered=False)
            chunk_index += len(ops)
            total += len(ops)
    return IngestResult(chunk_count=total)


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
    for offset, (content, vector) in enumerate(
        zip(embed.chunk_texts, embed.embeddings, strict=True)
    ):
        chunk_index = start_index + offset
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
    return ops
