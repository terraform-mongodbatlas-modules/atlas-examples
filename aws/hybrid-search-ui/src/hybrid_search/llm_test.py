from __future__ import annotations

import pytest
from pydantic import SecretStr
from pydantic_ai.models.bedrock import BedrockConverseModel

from hybrid_search.llm import build_agent
from hybrid_search.settings import HybridSearchSettings


def test_build_agent_requires_anthropic_key():
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        llm_provider="anthropic",
    )
    with pytest.raises(ValueError, match="ANTHROPIC_API_KEY"):
        build_agent(settings)


def test_build_agent_bedrock_needs_no_api_key(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        llm_provider="bedrock",
    )
    agent = build_agent(settings)
    assert isinstance(agent.model, BedrockConverseModel)
    assert agent.model.model_name == "amazon.nova-lite-v1:0"


def test_build_agent_bedrock_requires_region(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.delenv("AWS_REGION", raising=False)
    monkeypatch.delenv("AWS_DEFAULT_REGION", raising=False)
    settings = HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
        llm_provider="bedrock",
    )
    with pytest.raises(ValueError, match="AWS_REGION"):
        build_agent(settings)
