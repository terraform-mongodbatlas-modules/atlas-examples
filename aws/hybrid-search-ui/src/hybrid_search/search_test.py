from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr
from pymongo.errors import OperationFailure

from hybrid_search.search import (
    ZERO_QUERY_EMBEDDING,
    RetrievalPipeline,
    build_rank_fusion_pipeline,
    build_text_search_pipeline,
    build_vector_search_pipeline,
    search,
    search_with_modes,
)
from hybrid_search.search_modes import SearchModes
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


def test_vector_search_pipeline_shape():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        top_k=5,
    )
    pipeline = build_vector_search_pipeline([0.1, 0.2], settings=settings)
    assert pipeline[0]["$vectorSearch"]["index"] == "vector_idx"
    assert pipeline[1] == {"$limit": 5}
    assert pipeline[2] == {"$addFields": {"hybrid_score": {"$meta": "vectorSearchScore"}}}
    assert pipeline[3] == {"$project": {"vector": 0}}


def _settings() -> HybridSearchSettings:
    return HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )


def _mock_collection(docs: list[dict]) -> MagicMock:
    collection = MagicMock()
    cursor = MagicMock()
    cursor.to_list = AsyncMock(return_value=docs)
    collection.aggregate = MagicMock(return_value=cursor)
    return collection


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("modes", "query_vector", "expected_root", "expected_pipeline"),
    [
        (
            SearchModes(keyword=True, vector=False),
            None,
            "$search",
            RetrievalPipeline.KEYWORD,
        ),
        (
            SearchModes(keyword=False, vector=True),
            [0.1, 0.2],
            "$vectorSearch",
            RetrievalPipeline.VECTOR,
        ),
        (
            SearchModes(keyword=True, vector=True),
            [0.1, 0.2],
            "$rankFusion",
            RetrievalPipeline.RANK_FUSION,
        ),
    ],
)
async def test_search_with_modes_pipeline(modes, query_vector, expected_root, expected_pipeline):
    collection = _mock_collection([{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}])
    result = await search_with_modes(
        "risk",
        query_vector,
        modes=modes,
        collection=collection,
        settings=_settings(),
    )
    assert result.references == [{"file_path": "a.pdf", "content": "ctx", "score": 1.0}]
    assert result.pipeline == expected_pipeline
    assert result.vector_skipped_reason is None
    pipeline = collection.aggregate.call_args.args[0]
    assert expected_root in pipeline[0]


@pytest.mark.asyncio
async def test_search_with_modes_hybrid_falls_back_on_zero_query_vector():
    collection = _mock_collection([{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}])
    result = await search_with_modes(
        "risk",
        [0.0, 0.0],
        modes=SearchModes(keyword=True, vector=True),
        collection=collection,
        settings=_settings(),
    )
    assert result.pipeline == RetrievalPipeline.KEYWORD
    assert result.vector_skipped_reason == ZERO_QUERY_EMBEDDING
    pipeline = collection.aggregate.call_args.args[0]
    assert "$search" in pipeline[0]


@pytest.mark.asyncio
async def test_search_falls_back_to_text_on_zero_query_vector():
    settings = _settings()
    collection = _mock_collection([{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}])

    docs = await search("risk", [0.0, 0.0], collection=collection, settings=settings)
    assert docs == [{"file_path": "a.pdf", "content": "ctx", "score": 1.0}]
    collection.aggregate.assert_called_once()


@pytest.mark.asyncio
async def test_search_falls_back_to_text_on_zero_vector_error():
    settings = _settings()
    collection = MagicMock()
    first_cursor = MagicMock()
    first_cursor.to_list = AsyncMock(
        side_effect=OperationFailure(
            "Cosine similarity cannot be calculated against a zero vector."
        )
    )
    second_cursor = MagicMock()
    second_cursor.to_list = AsyncMock(
        return_value=[{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}]
    )
    collection.aggregate = MagicMock(side_effect=[first_cursor, second_cursor])

    docs = await search("risk", [0.1, 0.2], collection=collection, settings=settings)
    assert docs == [{"file_path": "a.pdf", "content": "ctx", "score": 1.0}]
    assert collection.aggregate.call_count == 2
