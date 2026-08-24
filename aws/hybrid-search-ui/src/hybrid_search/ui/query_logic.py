from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import voyageai
from motor.motor_asyncio import AsyncIOMotorCollection

from hybrid_search.generate import generate_answer, unique_source_files
from hybrid_search.search import search_with_modes
from hybrid_search.search_modes import DEFAULT, SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.voyage import embed_query


@dataclass(frozen=True)
class QueryResult:
    references: list[dict[str, Any]]
    answer: str | None
    source_files: list[str]
    modes: SearchModes


async def retrieve(
    query: str,
    *,
    modes: SearchModes,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    voyage: voyageai.AsyncClient,
) -> list[dict[str, Any]]:
    modes.validate_retrieval()
    query_vector = None
    if modes.vector:
        query_vector = await embed_query(query, client=voyage, settings=settings)
    return await search_with_modes(
        query,
        query_vector,
        modes=modes,
        collection=collection,
        settings=settings,
    )


async def answer_or_format(
    query: str,
    references: list[dict[str, Any]],
    *,
    modes: SearchModes,
    settings: HybridSearchSettings,
) -> QueryResult:
    source_files = unique_source_files(references)
    if modes.llm and settings.enable_llm:
        result = await generate_answer(query, references, settings=settings)
        return QueryResult(
            references=references,
            answer=result.answer,
            source_files=result.source_files,
            modes=modes,
        )
    return QueryResult(
        references=references,
        answer=None,
        source_files=source_files,
        modes=modes,
    )


async def answer_query(
    query: str,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    voyage: voyageai.AsyncClient,
    modes: SearchModes = DEFAULT,
) -> QueryResult:
    references = await retrieve(
        query,
        modes=modes,
        settings=settings,
        collection=collection,
        voyage=voyage,
    )
    return await answer_or_format(query, references, modes=modes, settings=settings)
