from __future__ import annotations

from pydantic import SecretStr

from hybrid_search.search import (
    build_rank_fusion_pipeline,
    build_text_search_pipeline,
    build_vector_search_pipeline,
)
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
