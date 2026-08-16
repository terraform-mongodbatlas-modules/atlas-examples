from __future__ import annotations

from importlib import import_module

import voyageai
from motor.motor_asyncio import AsyncIOMotorCollection

from hybrid_search.generate import GenerateResult
from hybrid_search.settings import HybridSearchSettings

_search = import_module("hybrid_search.search")
_generate = import_module("hybrid_search.generate")
_voyage = import_module("hybrid_search.voyage")


async def answer_query(
    query: str,
    *,
    settings: HybridSearchSettings,
    collection: AsyncIOMotorCollection,
    voyage: voyageai.AsyncClient,
) -> GenerateResult:
    vector = await _voyage.embed_query(query, client=voyage, settings=settings)
    references = await _search.search(query, vector, collection=collection, settings=settings)
    return await _generate.generate_answer(query, references, settings=settings)
