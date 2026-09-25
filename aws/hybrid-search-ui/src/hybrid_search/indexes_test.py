from __future__ import annotations

import logging
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr
from pymongo.errors import OperationFailure
from pymongo.operations import SearchIndexModel

from hybrid_search.indexes import (
    autoembed_index_definition,
    create_chunks_indexes_if_missing,
    format_index_ready_line,
    wait_chunks_indexes_ready,
)
from hybrid_search.settings import HybridSearchSettings


@pytest.fixture
def settings() -> HybridSearchSettings:
    return HybridSearchSettings(
        mongodb_uri=SecretStr("mongodb://localhost"),
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
    assert models[0].document["name"] == "autoembed_idx"
    assert models[1].document["name"] == "text_idx"


@pytest.mark.asyncio
async def test_creates_collection_when_list_indexes_missing_namespace(settings, caplog):
    collection = MagicMock()
    collection.name = "chunks"
    collection.database.name = "hybrid_search"
    collection.insert_one = AsyncMock()
    collection.delete_one = AsyncMock()
    collection.list_search_indexes.return_value.to_list = AsyncMock(
        side_effect=[
            OperationFailure("database hybrid_search not found", 26),
            [],
        ]
    )
    collection.create_search_index = AsyncMock()
    caplog.set_level(logging.INFO)

    await create_chunks_indexes_if_missing(collection, settings)

    collection.insert_one.assert_awaited()
    collection.delete_one.assert_awaited()
    assert collection.create_search_index.await_count == 2
    assert "hybrid_search.chunks" in caplog.text
    assert "namespace missing" in caplog.text.lower()


@pytest.mark.asyncio
async def test_materializes_collection_when_create_index_missing_namespace(settings):
    collection = MagicMock()
    collection.name = "chunks"
    collection.insert_one = AsyncMock()
    collection.delete_one = AsyncMock()
    collection.database.create_collection = AsyncMock()
    collection.list_search_indexes.return_value.to_list = AsyncMock(return_value=[])
    collection.create_search_index = AsyncMock(
        side_effect=[
            OperationFailure("database hybrid_search not found", 26),
            None,
            None,
        ]
    )

    await create_chunks_indexes_if_missing(collection, settings)

    collection.insert_one.assert_awaited()
    collection.delete_one.assert_awaited()
    assert collection.create_search_index.await_count == 3


@pytest.mark.asyncio
async def test_reraises_list_indexes_other_operation_failure(settings):
    collection = MagicMock()
    collection.list_search_indexes.return_value.to_list = AsyncMock(
        side_effect=OperationFailure("unauthorized", 13)
    )

    with pytest.raises(OperationFailure, match="unauthorized"):
        await create_chunks_indexes_if_missing(collection, settings)
    collection.insert_one.assert_not_called()


@pytest.mark.asyncio
async def test_wait_until_ready(settings):
    statuses = iter(
        [
            [
                {"name": "autoembed_idx", "status": "BUILDING"},
                {"name": "text_idx", "status": "READY"},
            ],
            [{"name": "autoembed_idx", "status": "READY"}, {"name": "text_idx", "status": "READY"}],
        ]
    )
    collection = MagicMock()
    collection.list_search_indexes.side_effect = lambda: MagicMock(
        to_list=AsyncMock(return_value=next(statuses))
    )

    ready = await wait_chunks_indexes_ready(collection, settings, timeout_s=5, interval_s=0)
    assert ("chunks", "text_idx", "READY") in ready
    assert ("chunks", "autoembed_idx", "READY") in ready


@pytest.mark.asyncio
async def test_wait_materializes_namespace_when_list_missing(settings, caplog):
    collection = MagicMock()
    collection.name = "chunks"
    collection.database.name = "hybrid_search"
    collection.insert_one = AsyncMock()
    collection.delete_one = AsyncMock()
    collection.list_search_indexes.return_value.to_list = AsyncMock(
        side_effect=[
            OperationFailure("database hybrid_search not found", 26),
            [
                {"name": "autoembed_idx", "status": "READY"},
                {"name": "text_idx", "status": "READY"},
            ],
        ]
    )
    caplog.set_level(logging.INFO)

    ready = await wait_chunks_indexes_ready(collection, settings, timeout_s=5, interval_s=0)

    collection.insert_one.assert_awaited()
    assert ("chunks", "autoembed_idx", "READY") in ready
    assert "hybrid_search.chunks" in caplog.text


@pytest.mark.asyncio
async def test_wait_logs_status_transitions(settings, caplog):
    statuses = iter(
        [
            [
                {"name": "autoembed_idx", "status": "BUILDING"},
                {"name": "text_idx", "status": "BUILDING"},
            ],
            [{"name": "autoembed_idx", "status": "READY"}, {"name": "text_idx", "status": "READY"}],
        ]
    )
    collection = MagicMock()
    collection.list_search_indexes.side_effect = lambda: MagicMock(
        to_list=AsyncMock(return_value=next(statuses))
    )
    caplog.set_level(logging.INFO)

    await wait_chunks_indexes_ready(collection, settings, timeout_s=5, interval_s=0)

    assert "chunks.autoembed_idx BUILDING" in caplog.text
    assert "chunks.autoembed_idx READY" in caplog.text
    assert "chunks.text_idx BUILDING" in caplog.text
    assert "chunks.text_idx READY" in caplog.text


@pytest.mark.asyncio
async def test_wait_logs_missing_index_as_pending_once(settings, caplog):
    statuses = iter(
        [
            [{"name": "autoembed_idx", "status": "BUILDING"}],
            [{"name": "autoembed_idx", "status": "READY"}, {"name": "text_idx", "status": "READY"}],
        ]
    )
    collection = MagicMock()
    collection.list_search_indexes.side_effect = lambda: MagicMock(
        to_list=AsyncMock(return_value=next(statuses))
    )
    caplog.set_level(logging.INFO)

    await wait_chunks_indexes_ready(collection, settings, timeout_s=5, interval_s=0)

    assert caplog.text.count("chunks.text_idx PENDING") == 1


def test_autoembed_index_definition():
    definition = autoembed_index_definition(model="voyage-4-lite")
    assert definition["fields"][0] == {
        "type": "autoEmbed",
        "modality": "text",
        "path": "content",
        "model": "voyage-4-lite",
    }
    assert definition["fields"][1] == {"type": "filter", "path": "file_path"}


def test_autoembed_index_definition_has_no_dimensions():
    definition = autoembed_index_definition(model="voyage-4-lite")
    assert "numDimensions" not in str(definition)
    assert all(field.get("type") != "vector" for field in definition["fields"])


def test_format_index_ready_line():
    line = format_index_ready_line("chunks", "autoembed_idx")
    assert line.endswith(" chunks.autoembed_idx READY")
