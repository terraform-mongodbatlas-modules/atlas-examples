from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr

from hybrid_search.search import (
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
        top_k=20,
        vector_weight=0.6,
        text_weight=0.4,
    )
    pipeline = build_rank_fusion_pipeline("risk", settings=settings)
    fusion = pipeline[0]["$rankFusion"]
    assert fusion["combination"]["weights"] == {"vector": 0.6, "text": 0.4}
    assert fusion["input"]["pipelines"]["vector"][-1] == {"$limit": 40}
    assert fusion["input"]["pipelines"]["text"][-1] == {"$limit": 40}
    assert fusion["input"]["pipelines"]["vector"][0]["$vectorSearch"]["query"] == {"text": "risk"}
    assert "queryVector" not in str(fusion["input"]["pipelines"]["vector"])
    assert pipeline[1] == {"$addFields": {"hybrid_score": {"$meta": "score"}}}
    assert pipeline[2] == {"$limit": 20}
    assert pipeline[3] == {"$project": {"vector": 0}}


def test_text_search_pipeline_shape():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        top_k=5,
    )
    pipeline = build_text_search_pipeline("risk", settings=settings)
    assert pipeline[0]["$search"]["index"] == "text_idx"
    assert pipeline[1] == {"$limit": 5}
    assert pipeline[2] == {"$addFields": {"hybrid_score": {"$meta": "searchScore"}}}


def test_vector_search_pipeline_shape():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        top_k=5,
    )
    pipeline = build_vector_search_pipeline("risk", settings=settings)
    vector_stage = pipeline[0]["$vectorSearch"]
    assert vector_stage["index"] == "autoembed_idx"
    assert vector_stage["path"] == "content"
    assert vector_stage["query"] == {"text": "risk"}
    assert "queryVector" not in vector_stage
    assert pipeline[1] == {"$limit": 5}
    assert pipeline[2] == {"$addFields": {"hybrid_score": {"$meta": "vectorSearchScore"}}}
    assert pipeline[3] == {"$project": {"vector": 0}}


def _settings() -> HybridSearchSettings:
    return HybridSearchSettings(mongodb_uri=SecretStr("mongodb://localhost"))


def _mock_collection(docs: list[dict]) -> MagicMock:
    collection = MagicMock()
    cursor = MagicMock()
    cursor.to_list = AsyncMock(return_value=docs)
    collection.aggregate = MagicMock(return_value=cursor)
    return collection


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("modes", "expected_root", "expected_pipeline"),
    [
        (
            SearchModes(keyword=True, vector=False),
            "$search",
            RetrievalPipeline.KEYWORD,
        ),
        (
            SearchModes(keyword=False, vector=True),
            "$vectorSearch",
            RetrievalPipeline.VECTOR,
        ),
        (
            SearchModes(keyword=True, vector=True),
            "$rankFusion",
            RetrievalPipeline.RANK_FUSION,
        ),
    ],
)
async def test_search_with_modes_pipeline(modes, expected_root, expected_pipeline):
    collection = _mock_collection([{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}])
    result = await search_with_modes(
        "risk",
        modes=modes,
        collection=collection,
        settings=_settings(),
    )
    assert result.references == [{"file_path": "a.pdf", "content": "ctx", "score": 1.0}]
    assert result.pipeline == expected_pipeline
    pipeline = collection.aggregate.call_args.args[0]
    assert expected_root in pipeline[0]


@pytest.mark.asyncio
async def test_search_uses_text_query_once():
    settings = _settings()
    collection = _mock_collection([{"file_path": "a.pdf", "content": "ctx", "hybrid_score": 1.0}])

    docs = await search("risk", collection=collection, settings=settings)
    assert docs == [{"file_path": "a.pdf", "content": "ctx", "score": 1.0}]
    collection.aggregate.assert_called_once()
    pipeline = collection.aggregate.call_args.args[0]
    assert pipeline[0]["$rankFusion"]["input"]["pipelines"]["vector"][0]["$vectorSearch"][
        "query"
    ] == {"text": "risk"}
