from __future__ import annotations

from pathlib import Path
from typing import Any

import chainlit as cl
from motor.motor_asyncio import AsyncIOMotorCollection

from hybrid_search.search import SearchResult
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui.query_logic import QueryResult, answer_or_format, retrieve
from hybrid_search.ui.result_format import (
    format_location,
    format_retrieval_body,
    retrieval_header,
)


def _retrieval_status(search_result: SearchResult, modes: SearchModes) -> str:
    if not modes.vector:
        return "Keyword search (no query embedding)"
    header = retrieval_header(search_result.pipeline)
    return f"{header} · {len(search_result.references)} hits"


def _source_lines(references: list[dict[str, Any]]) -> list[str]:
    seen: set[str] = set()
    lines: list[str] = []
    for ref in references:
        filename = Path(ref.get("file_path", "")).name or "unknown"
        location = format_location(ref)
        label = f"{filename} · {location}" if location else filename
        if label in seen:
            continue
        seen.add(label)
        lines.append(label)
    return lines


def _answer_output(result: QueryResult) -> str:
    if result.answer:
        lines = _source_lines(result.references)
        if lines:
            footer = "### Sources\n" + "\n".join(f"- {line}" for line in lines)
        else:
            footer = "### Sources\nNo sources retrieved"
        return f"{result.answer}\n\n{footer}"
    return format_retrieval_body(result.references)


async def run_query_with_steps(
    query: str,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    modes: SearchModes,
) -> QueryResult:
    async with cl.Step(name="Query", type="run"):
        async with cl.Step(name="Retrieving", type="tool") as retrieve_step:
            search_result = await retrieve(
                query,
                modes=modes,
                settings=settings,
                collection=collection,
            )
            retrieve_step.output = _retrieval_status(search_result, modes)
            await retrieve_step.update()

        answer_type = "llm" if modes.llm and settings.enable_llm else "tool"
        async with cl.Step(name="Answering", type=answer_type) as answer_step:
            result = await answer_or_format(
                query,
                search_result,
                modes=modes,
                settings=settings,
            )
            answer_step.output = _answer_output(result)
            await answer_step.update()
            return result
