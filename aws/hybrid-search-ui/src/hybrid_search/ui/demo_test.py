from hybrid_search.ui.demo import DEMO_STARTERS, INGEST_COMMAND, INGEST_COMMAND_ID, UPLOAD_STARTER


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
