"""Fixtures for the Atlas Local integration tier.

The wrapper behind `just integration-test` owns the container and sets
`MONGODB_URI`. `integration_environment` is autouse, so every test in this
directory skips without that variable and the default run stays offline.

The test database is kept between runs, and the tests clean up their own
documents, so a re-run skips the index build. `just integration-test --clean`
drops the database first when a full re-ingest is wanted.
"""

from __future__ import annotations

import os
from collections.abc import Iterator

import pytest
from pydantic import SecretStr

from hybrid_search.settings import HybridSearchSettings

TEST_DATABASE = "hybrid_search_integration"


def integration_settings() -> HybridSearchSettings:
    """Settings pointed at the local deployment, with the LLM off."""
    return HybridSearchSettings(
        mongodb_uri=SecretStr(os.environ["MONGODB_URI"]),
        mongodb_tls=False,
        mongodb_database=TEST_DATABASE,
        enable_llm=False,
    )


@pytest.fixture(scope="session", autouse=True)
def integration_environment() -> Iterator[None]:
    if not os.environ.get("MONGODB_URI"):
        pytest.skip("MONGODB_URI is unset; run `just integration-test`")
    yield
