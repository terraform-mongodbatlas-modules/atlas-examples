from __future__ import annotations

from typing import Any

from motor.motor_asyncio import AsyncIOMotorCollection
from pymongo.errors import OperationFailure

from hybrid_search.settings import HybridSearchSettings
from hybrid_search.voyage import is_zero_vector

# $rankFusion pipeline adapted from Hybrid-Search-RAG (Apache-2.0).
NUM_CANDIDATES_MULTIPLIER = 20
FUZZY_MAX_EDITS = 2
FUZZY_PREFIX_LENGTH = 3
VECTOR_PATH = "vector"
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


def build_rank_fusion_pipeline(
    query_text: str,
    query_vector: list[float],
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
                "queryVector": query_vector,
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


async def search(
    query_text: str,
    query_vector: list[float],
    *,
    collection: AsyncIOMotorCollection,
    settings: HybridSearchSettings,
) -> list[dict[str, Any]]:
    if is_zero_vector(query_vector):
        msg = "Query embedding is a zero vector; try different wording."
        raise ValueError(msg)
    pipeline = build_rank_fusion_pipeline(query_text, query_vector, settings=settings)
    try:
        docs = await _run_search_pipeline(collection, pipeline)
    except OperationFailure as exc:
        if "zero vector" not in str(exc).lower():
            raise
        # existing chunks may still have zero vectors from before ingest filtering
        pipeline = build_text_search_pipeline(query_text, settings=settings)
        docs = await _run_search_pipeline(collection, pipeline)
    return [
        {
            "file_path": doc.get("file_path", ""),
            "content": doc.get("content", ""),
            "score": float(doc.get("hybrid_score") or 0.0),
        }
        for doc in docs
    ]


async def _run_search_pipeline(
    collection: AsyncIOMotorCollection,
    pipeline: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    cursor = collection.aggregate(pipeline, allowDiskUse=True)
    return await cursor.to_list(length=None)
