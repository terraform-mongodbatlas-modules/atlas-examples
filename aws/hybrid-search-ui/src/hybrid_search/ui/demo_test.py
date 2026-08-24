from hybrid_search.ui.demo import (
    DELETE_COMMAND_ID,
    DELETE_STARTER,
    DEMO_COMMAND_ID,
    INGEST_COMMAND_ID,
    UPLOAD_STARTER,
    Mode,
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
