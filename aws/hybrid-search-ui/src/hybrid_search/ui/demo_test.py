import pytest
from pydantic import ValidationError

from hybrid_search.ui.demo import (
    CANCEL_ACTION,
    DELETE_COMMAND_ID,
    DELETE_STARTER,
    DEMO_COMMAND_ID,
    INGEST_COMMAND_ID,
    UPLOAD_STARTER,
    DemoQuery,
    Mode,
    load_demo_queries,
    query_from_demo_response,
    resolve_mode,
)


def test_resolve_mode_from_command():
    assert resolve_mode(command=INGEST_COMMAND_ID) == Mode.INGEST
    assert resolve_mode(command=DELETE_COMMAND_ID) == Mode.DELETE
    assert resolve_mode(command=DEMO_COMMAND_ID) == Mode.DEMO


def test_resolve_mode_from_starter_message():
    assert resolve_mode(content=UPLOAD_STARTER["message"]) == Mode.INGEST
    assert resolve_mode(content=DELETE_STARTER["message"]) == Mode.DELETE


def test_resolve_mode_from_command_id_text():
    assert resolve_mode(content=INGEST_COMMAND_ID) == Mode.INGEST
    assert resolve_mode(content=DELETE_COMMAND_ID) == Mode.DELETE


def test_resolve_mode_unknown():
    assert resolve_mode(content="What is prompt injection?") is None
    assert resolve_mode(content="2") is None


def test_load_demo_queries(tmp_path):
    path = tmp_path / "demo_queries.yaml"
    path.write_text("queries:\n  - label: A\n    message: What is A?\n")
    assert load_demo_queries(path) == [DemoQuery(label="A", message="What is A?")]


def test_load_demo_queries_rejects_missing_file(tmp_path):
    with pytest.raises(FileNotFoundError, match="not found"):
        load_demo_queries(tmp_path / "missing.yaml")


def test_load_demo_queries_rejects_empty_list(tmp_path):
    path = tmp_path / "demo_queries.yaml"
    path.write_text("queries: []\n")
    with pytest.raises(ValidationError, match="at least 1"):
        load_demo_queries(path)


def test_query_from_demo_response_returns_message():
    assert query_from_demo_response({"payload": {"message": "What is A?"}}) == "What is A?"


def test_query_from_demo_response_skips_cancel_and_timeout():
    assert query_from_demo_response(None) is None
    assert query_from_demo_response({"name": CANCEL_ACTION, "payload": {}}) is None
