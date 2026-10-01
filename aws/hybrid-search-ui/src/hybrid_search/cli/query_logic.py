from __future__ import annotations

import asyncio
import logging

from pydantic import BaseModel, Field
from pymongo.errors import PyMongoError

from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.ui.query_logic import answer_query

logger = logging.getLogger(__name__)

QUERY_ERRORS = (OSError, ValueError, RuntimeError, PyMongoError)


class QueryInput(BaseModel):
    settings: HybridSearchSettings
    query: str
    modes: SearchModes


class QueryOutput(BaseModel):
    exit_code: int = 0
    references: list[dict] = Field(default_factory=list)
    answer: str | None = None
    source_files: list[str] = Field(default_factory=list)
    error: str | None = None


def run_query(input: QueryInput) -> QueryOutput:
    return asyncio.run(_run_query_async(input))


async def _run_query_async(input: QueryInput) -> QueryOutput:
    settings = input.settings
    client = get_client(settings)
    try:
        collection = chunks_collection(client, settings)
        result = await answer_query(
            input.query,
            settings=settings,
            collection=collection,
            modes=input.modes,
        )
        return QueryOutput(
            references=result.references,
            answer=result.answer,
            source_files=result.source_files,
        )
    except QUERY_ERRORS as exc:
        logger.error(f"query failed: {exc}")
        return QueryOutput(exit_code=1, error=str(exc))
    finally:
        client.close()
