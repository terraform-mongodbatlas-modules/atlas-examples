from __future__ import annotations

from enum import StrEnum


class Mode(StrEnum):
    INGEST = "ingest"
    DELETE = "delete"
    DEMO = "demo"


DEMO_STARTERS = [
    {
        "label": "AI RMF functions",
        "message": "What are the four functions of the AI RMF?",
    },
    {
        "label": "Measure GenAI risk",
        "message": "How should we measure generative AI risk?",
    },
    {
        "label": "Prompt injection",
        "message": "What is prompt injection and how do we mitigate it?",
    },
]

INGEST_COMMAND_ID = "Ingest"
DELETE_COMMAND_ID = "Delete"
DEMO_COMMAND_ID = "Demo"
DEMO_ACTION_NAME = "demo"
DELETE_FILE_ACTION = "delete_file"
DELETE_ALL_ACTION = "delete_all"
CANCEL_ACTION = "cancel"

INGEST_COMMAND = {
    "id": INGEST_COMMAND_ID,
    "icon": "upload",
    "description": "Ingest pdf, txt, or md",
    "button": True,
}

DELETE_COMMAND = {
    "id": DELETE_COMMAND_ID,
    "icon": "trash-2",
    "description": "Delete ingested documents",
    "button": True,
}

DEMO_COMMAND = {
    "id": DEMO_COMMAND_ID,
    "icon": "message-circle-question",
    "description": "Show demo questions",
    "button": True,
}

UPLOAD_STARTER = {
    "label": "Upload documents",
    "message": "Ingest files",
    "command": INGEST_COMMAND_ID,
}

DELETE_STARTER = {
    "label": "Delete documents",
    "message": "Delete files",
    "command": DELETE_COMMAND_ID,
}


def resolve_mode(*, command: str | None = None, content: str = "") -> Mode | None:
    text = content.strip()
    if command == INGEST_COMMAND_ID or text in {UPLOAD_STARTER["message"], INGEST_COMMAND_ID}:
        return Mode.INGEST
    if command == DELETE_COMMAND_ID or text in {DELETE_STARTER["message"], DELETE_COMMAND_ID}:
        return Mode.DELETE
    if command == DEMO_COMMAND_ID or text == DEMO_COMMAND_ID:
        return Mode.DEMO
    return None
