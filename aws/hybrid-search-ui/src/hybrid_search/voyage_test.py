from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr

from hybrid_search import voyage as voyage_module
from hybrid_search.settings import HybridSearchSettings
from hybrid_search.voyage import DocumentEmbedResult, is_zero_vector


@pytest.fixture
def settings() -> HybridSearchSettings:
    return HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )


@pytest.mark.asyncio
async def test_embed_document_kwargs(settings):
    client = MagicMock()
    chunk = MagicMock(chunk_texts=["a"], embeddings=[[0.1, 0.2]])
    result = MagicMock(results=[chunk])
    client.contextualized_embed = AsyncMock(return_value=result)

    out = await voyage_module.embed_document("hello", client=client, settings=settings)
    assert out == DocumentEmbedResult(chunk_texts=["a"], embeddings=[[0.1, 0.2]])
    kwargs = client.contextualized_embed.await_args.kwargs
    assert kwargs["model"] == "voyage-context-4"
    assert kwargs["input_type"] == "document"
    assert kwargs["enable_auto_chunking"] is True
    assert kwargs["chunk_size"] == 512
    assert kwargs["output_dimension"] == 1024


def test_is_zero_vector():
    assert is_zero_vector([]) is True
    assert is_zero_vector([0.0, 0.0]) is True
    assert is_zero_vector([0.1, 0.0]) is False


@pytest.mark.asyncio
async def test_embed_query_disables_auto_chunk(settings):
    client = MagicMock()
    chunk = MagicMock(embeddings=[[0.5]])
    result = MagicMock(results=[chunk])
    client.contextualized_embed = AsyncMock(return_value=result)

    vector = await voyage_module.embed_query("query", client=client, settings=settings)
    assert vector == [0.5]
    assert client.contextualized_embed.await_args.kwargs["enable_auto_chunking"] is False
