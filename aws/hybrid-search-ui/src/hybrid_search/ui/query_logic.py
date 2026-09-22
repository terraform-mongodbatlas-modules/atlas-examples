from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from motor.motor_asyncio import AsyncIOMotorCollection

from hybrid_search.generate import generate_answer, unique_source_files
from hybrid_search.search import SearchResult, search_with_modes
from hybrid_search.search_modes import DEFAULT, SearchModes
from hybrid_search.settings import HybridSearchSettings


@dataclass(frozen=True)
class QueryResult:
    references: list[dict[str, Any]]
    answer: str | None
    source_files: list[str]
    modes: SearchModes
    search_result: SearchResult


async def retrieve(
    query: str,
    *,
    modes: SearchModes,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
) -> SearchResult:
    modes.validate_retrieval()
    return await search_with_modes(
        query,
        modes=modes,
        collection=collection,
        settings=settings,
    )


async def answer_or_format(
    query: str,
    search_result: SearchResult,
    *,
    modes: SearchModes,
    settings: HybridSearchSettings,
) -> QueryResult:
    references = search_result.references
    source_files = unique_source_files(references)
    if modes.llm and settings.enable_llm:
        result = await generate_answer(query, references, settings=settings)
        return QueryResult(
            references=references,
            answer=result.answer,
            source_files=result.source_files,
            modes=modes,
            search_result=search_result,
        )
    return QueryResult(
        references=references,
        answer=None,
        source_files=source_files,
        modes=modes,
        search_result=search_result,
    )


async def answer_query(
    query: str,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    modes: SearchModes = DEFAULT,
) -> QueryResult:
    search_result = await retrieve(
        query,
        modes=modes,
        settings=settings,
        collection=collection,
    )
    return await answer_or_format(query, search_result, modes=modes, settings=settings)
