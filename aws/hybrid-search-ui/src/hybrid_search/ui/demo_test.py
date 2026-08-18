from hybrid_search.ui.demo import (
    DELETE_COMMAND,
    DELETE_COMMAND_ID,
    DELETE_STARTER,
    DEMO_STARTERS,
    INGEST_COMMAND,
    INGEST_COMMAND_ID,
    UPLOAD_STARTER,
)


def test_demo_starters_shape():
    assert len(DEMO_STARTERS) == 3
    for item in DEMO_STARTERS:
        assert "label" in item and "message" in item
        assert "command" not in item


def test_ingest_command_and_upload_starter():
    assert INGEST_COMMAND["id"] == INGEST_COMMAND_ID == "Ingest"
    assert INGEST_COMMAND["button"]
    assert INGEST_COMMAND["icon"] == "upload"
    assert UPLOAD_STARTER["command"] == "Ingest"
    assert UPLOAD_STARTER["label"] == "Upload documents"
    assert UPLOAD_STARTER["message"] == "Ingest files"


def test_delete_command_and_starter():
    assert DELETE_COMMAND["id"] == DELETE_COMMAND_ID == "Delete"
    assert DELETE_COMMAND["button"]
    assert DELETE_COMMAND["icon"] == "trash-2"
    assert DELETE_STARTER["command"] == "Delete"
    assert DELETE_STARTER["label"] == "Delete documents"
    assert DELETE_STARTER["message"] == "Delete files"

