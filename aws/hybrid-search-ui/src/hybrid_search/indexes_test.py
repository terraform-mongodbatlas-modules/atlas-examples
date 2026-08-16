from __future__ import annotations

from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr
from pymongo.operations import SearchIndexModel

from hybrid_search.indexes import (
    create_chunks_indexes_if_missing,
    format_index_ready_line,
    wait_chunks_indexes_ready,
)
from hybrid_search.settings import HybridSearchSettings


@pytest.fixture
def settings() -> HybridSearchSettings:
    return HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
        voyage_api_key=SecretStr("key"),
    )


@pytest.mark.asyncio
async def test_create_indexes_when_missing(settings):
    collection = MagicMock()
    collection.list_search_indexes.return_value.to_list = AsyncMock(return_value=[])
    collection.create_search_index = AsyncMock()
    await create_chunks_indexes_if_missing(collection, settings)
    assert collection.create_search_index.await_count == 2
    models = [call.args[0] for call in collection.create_search_index.await_args_list]
    assert all(isinstance(model, SearchIndexModel) for model in models)
    assert models[0].document["name"] == "vector_idx"
    assert models[1].document["name"] == "text_idx"


@pytest.mark.asyncio
async def test_wait_until_ready(settings):
    statuses = iter(
        [
            [{"name": "vector_idx", "status": "BUILDING"}, {"name": "text_idx", "status": "READY"}],
            [{"name": "vector_idx", "status": "READY"}, {"name": "text_idx", "status": "READY"}],
        ]
    )
    collection = MagicMock()
    collection.list_search_indexes.side_effect = lambda: MagicMock(
        to_list=AsyncMock(return_value=next(statuses))
    )
    db = MagicMock()
    db.__getitem__.return_value = collection

    ready = await wait_chunks_indexes_ready(db, settings, timeout_s=5, interval_s=0)
    assert ("chunks", "text_idx", "READY") in ready
    assert ("chunks", "vector_idx", "READY") in ready


def test_format_index_ready_line():
    line = format_index_ready_line("chunks", "vector_idx")
    assert line.endswith(" chunks.vector_idx READY")
