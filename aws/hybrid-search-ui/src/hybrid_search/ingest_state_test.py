from __future__ import annotations

from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest

from hybrid_search.ingest_state import (
    IngestState,
    content_hash,
    is_unchanged,
    load_states,
    source_key,
    upsert_state,
)


def test_source_key_is_stable_for_the_same_path(tmp_path: Path):
    path = tmp_path / "doc.md"
    path.write_text("hello")
    assert source_key(path) == source_key(path)


def test_source_key_distinguishes_same_named_files(tmp_path: Path):
    first = tmp_path / "a" / "doc.md"
    second = tmp_path / "b" / "doc.md"
    first.parent.mkdir()
    second.parent.mkdir()
    first.write_text("hello")
    second.write_text("hello")
    assert source_key(first) != source_key(second)


def test_content_hash_changes_with_bytes(tmp_path: Path):
    path = tmp_path / "doc.md"
    path.write_text("one")
    before = content_hash(path)
    path.write_text("two")
    assert content_hash(path) != before


def test_is_unchanged_matches_and_misses():
    states = {"doc.md": "abc"}
    assert is_unchanged(states, source_key="doc.md", content_hash="abc") is True
    assert is_unchanged(states, source_key="doc.md", content_hash="xyz") is False
    assert is_unchanged(states, source_key="other.md", content_hash="abc") is False


@pytest.mark.asyncio
async def test_upsert_state_keys_on_source_key():
    collection = MagicMock()
    collection.replace_one = AsyncMock()
    state = IngestState(source_key="doc.md", content_hash="abc", chunk_count=2)
    await upsert_state(collection, state)
    args = collection.replace_one.await_args.args
    assert args[0] == {"_id": "doc.md"}
    assert args[1]["content_hash"] == "abc"
    assert collection.replace_one.await_args.kwargs == {"upsert": True}


@pytest.mark.asyncio
async def test_load_states_reads_seeded_collection():
    cursor = MagicMock()
    cursor.to_list = AsyncMock(
        return_value=[
            {"_id": "doc.md", "content_hash": "abc"},
            {"_id": "other.txt", "content_hash": "def"},
        ]
    )
    collection = MagicMock()
    collection.find = MagicMock(return_value=cursor)

    states = await load_states(collection)

    assert states == {"doc.md": "abc", "other.txt": "def"}
    collection.find.assert_called_once_with({})
