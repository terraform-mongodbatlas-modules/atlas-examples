from __future__ import annotations

import pytest
from pydantic import SecretStr

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
