from __future__ import annotations

from typing import Any

from motor.motor_asyncio import AsyncIOMotorCollection

from hybrid_search.settings import HybridSearchSettings

# $rankFusion pipeline adapted from Hybrid-Search-RAG (Apache-2.0).
NUM_CANDIDATES_MULTIPLIER = 20
FUZZY_MAX_EDITS = 2
FUZZY_PREFIX_LENGTH = 3
VECTOR_PATH = "vector"
TEXT_PATH = "content"


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
    text_pipeline = [
        {
            "$search": {
                "index": settings.text_index_name,
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
        {"$limit": inner_limit},
    ]
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
    pipeline = build_rank_fusion_pipeline(query_text, query_vector, settings=settings)
    cursor = collection.aggregate(pipeline, allowDiskUse=True)
    docs = await cursor.to_list(length=None)
    return [
        {
            "file_path": doc.get("file_path", ""),
            "content": doc.get("content", ""),
            "score": float(doc.get("hybrid_score") or 0.0),
        }
        for doc in docs
    ]
