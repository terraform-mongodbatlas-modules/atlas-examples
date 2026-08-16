from __future__ import annotations

from pydantic import SecretStr

from hybrid_search.search import build_rank_fusion_pipeline
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
