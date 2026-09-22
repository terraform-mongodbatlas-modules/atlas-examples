from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any

from motor.motor_asyncio import AsyncIOMotorCollection

from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import HybridSearchSettings


class RetrievalPipeline(StrEnum):
    KEYWORD = "keyword"
    VECTOR = "vector"
    RANK_FUSION = "rank_fusion"


@dataclass(frozen=True)
class SearchResult:
    references: list[dict[str, Any]]
    pipeline: RetrievalPipeline


# $rankFusion pipeline adapted from Hybrid-Search-RAG (Apache-2.0).
NUM_CANDIDATES_MULTIPLIER = 20
FUZZY_MAX_EDITS = 2
FUZZY_PREFIX_LENGTH = 3
VECTOR_PATH = "content"
TEXT_PATH = "content"


def _text_search_stages(
    query_text: str,
    *,
    text_index_name: str,
    limit: int,
) -> list[dict[str, Any]]:
    return [
        {
            "$search": {
                "index": text_index_name,
                "compound": {
                    "must": [
                        {
                            "text": {
                                "query": query_text,
                                "path": TEXT_PATH,
                                "fuzzy": {
                                    "maxEdits": FUZZY_MAX_EDITS,
                                    "prefixLength": FUZZY_PREFIX_LENGTH,
                                },
                            }
                        }
                    ]
                },
            }
        },
        {"$limit": limit},
    ]


def build_text_search_pipeline(
    query_text: str,
    *,
    settings: HybridSearchSettings,
) -> list[dict[str, Any]]:
    return [
        *_text_search_stages(
            query_text,
            text_index_name=settings.text_index_name,
            limit=settings.top_k,
        ),
        {"$addFields": {"hybrid_score": {"$meta": "searchScore"}}},
        {"$project": {"vector": 0}},
    ]


def build_vector_search_pipeline(
    query_text: str,
    *,
    settings: HybridSearchSettings,
) -> list[dict[str, Any]]:
    top_k = settings.top_k
    return [
        {
            "$vectorSearch": {
                "index": settings.vector_index_name,
                "path": VECTOR_PATH,
                "query": {"text": query_text},
                "numCandidates": top_k * NUM_CANDIDATES_MULTIPLIER,
                "limit": top_k,
            }
        },
        {"$limit": top_k},
        {"$addFields": {"hybrid_score": {"$meta": "vectorSearchScore"}}},
        {"$project": {"vector": 0}},
    ]


def build_rank_fusion_pipeline(
    query_text: str,
    *,
    settings: HybridSearchSettings,
) -> list[dict[str, Any]]:
    top_k = settings.top_k
    inner_limit = top_k * 2
    num_candidates = top_k * NUM_CANDIDATES_MULTIPLIER
    vector_pipeline = [
        {
            "$vectorSearch": {
                "index": settings.vector_index_name,
                "path": VECTOR_PATH,
                "query": {"text": query_text},
                "numCandidates": num_candidates,
                "limit": inner_limit,
            }
        },
        {"$limit": inner_limit},
    ]
    text_pipeline = _text_search_stages(
        query_text,
        text_index_name=settings.text_index_name,
        limit=inner_limit,
    )
    return [
        {
            "$rankFusion": {
                "input": {
                    "pipelines": {
                        "vector": vector_pipeline,
                        "text": text_pipeline,
                    }
                },
                "combination": {
                    "weights": {
                        "vector": settings.vector_weight,
                        "text": settings.text_weight,
                    }
                },
                "scoreDetails": True,
            }
        },
        {"$addFields": {"hybrid_score": {"$meta": "score"}}},
        {"$limit": top_k},
        {"$project": {"vector": 0}},
    ]


def _docs_to_results(docs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return [
        {
            "file_path": doc.get("file_path", ""),
            "content": doc.get("content", ""),
            "score": float(doc.get("hybrid_score") or 0.0),
        }
        for doc in docs
    ]


async def _pipeline_search(
    pipeline: list[dict[str, Any]],
    *,
    collection: AsyncIOMotorCollection,
    pipeline_type: RetrievalPipeline,
) -> SearchResult:
    docs = await _run_search_pipeline(collection, pipeline)
    return SearchResult(
        references=_docs_to_results(docs),
        pipeline=pipeline_type,
    )


async def _keyword_search(
    query_text: str,
    *,
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> SearchResult:
    pipeline = build_text_search_pipeline(query_text, settings=settings)
    return await _pipeline_search(
        pipeline,
        collection=collection,
        pipeline_type=RetrievalPipeline.KEYWORD,
    )


async def _vector_search(
    query_text: str,
    *,
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> SearchResult:
    pipeline = build_vector_search_pipeline(query_text, settings=settings)
    return await _pipeline_search(
        pipeline,
        collection=collection,
        pipeline_type=RetrievalPipeline.VECTOR,
    )


async def _rank_fusion_search(
    query_text: str,
    *,
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> SearchResult:
    pipeline = build_rank_fusion_pipeline(query_text, settings=settings)
    return await _pipeline_search(
        pipeline,
        collection=collection,
        pipeline_type=RetrievalPipeline.RANK_FUSION,
    )


async def search_with_modes(
    query_text: str,
    *,
    modes: SearchModes,
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> SearchResult:
    modes.validate_retrieval()

    if modes.keyword and not modes.vector:
        return await _keyword_search(query_text, collection=collection, settings=settings)

    if modes.vector and not modes.keyword:
        return await _vector_search(query_text, collection=collection, settings=settings)

    return await _rank_fusion_search(query_text, collection=collection, settings=settings)


async def search(
    query_text: str,
    *,
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> list[dict[str, Any]]:
    result = await search_with_modes(
        query_text,
        modes=SearchModes(keyword=True, vector=True, llm=True),
        collection=collection,
        settings=settings,
    )
    return result.references


async def _run_search_pipeline(
    collection: AsyncIOMotorCollection,
    pipeline: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    cursor = collection.aggregate(pipeline, allowDiskUse=True)
    return await cursor.to_list(length=None)
