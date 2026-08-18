from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr
from pymongo.errors import OperationFailure

from hybrid_search.search import build_rank_fusion_pipeline, build_text_search_pipeline, search
from hybrid_search.settings import HybridSearchSettings


def test_rank_fusion_pipeline_shape():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        top_k=20,
        vector_weight=0.6,
        text_weight=0.4,
    )
    pipeline = build_rank_fusion_pipeline("risk", [0.1, 0.2], settings=settings)
    fusion = pipeline[0]["$rankFusion"]
    assert fusion["combination"]["weights"] == {"vector": 0.6, "text": 0.4}
    assert fusion["input"]["pipelines"]["vector"][-1] == {"$limit": 40}
    assert fusion["input"]["pipelines"]["text"][-1] == {"$limit": 40}
    assert pipeline[1] == {"$addFields": {"hybrid_score": {"$meta": "score"}}}
    assert pipeline[2] == {"$limit": 20}
    assert pipeline[3] == {"$project": {"vector": 0}}


def test_text_search_pipeline_shape():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        top_k=5,
    )
    pipeline = build_text_search_pipeline("risk", settings=settings)
    assert pipeline[0]["$search"]["index"] == "text_idx"
    assert pipeline[1] == {"$limit": 5}
    assert pipeline[2] == {"$addFields": {"hybrid_score": {"$meta": "searchScore"}}}


@pytest.mark.asyncio
async def test_search_falls_back_to_text_on_zero_vector_error():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )
    collection = MagicMock()
    first_cursor = MagicMock()
    first_cursor.to_list = AsyncMock(
        side_effect=OperationFailure("Cosine similarity cannot be calculated against a zero vector.")
    )
    second_cursor = MagicMock()
    second_cursor.to_list = AsyncMock(
        return_value=[{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}]
    )
    collection.aggregate = MagicMock(side_effect=[first_cursor, second_cursor])

    docs = await search("risk", [0.1, 0.2], collection=collection, settings=settings)
    assert docs == [{"file_path": "a.pdf", "content": "ctx", "score": 1.0}]
    assert collection.aggregate.call_count == 2
