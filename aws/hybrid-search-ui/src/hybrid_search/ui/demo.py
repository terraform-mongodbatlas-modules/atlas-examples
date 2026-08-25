from __future__ import annotations

from enum import StrEnum
from pathlib import Path

import yaml
from pydantic import BaseModel, Field


class Mode(StrEnum):
    INGEST = "ingest"
    DELETE = "delete"
    DEMO = "demo"


class DemoQuery(BaseModel):
    label: str
    message: str


class DemoQueriesFile(BaseModel):
    queries: list[DemoQuery] = Field(min_length=1)


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


def load_demo_queries(path: Path) -> list[DemoQuery]:
    if not path.is_file():
        raise FileNotFoundError(f"Demo queries file not found: {path}")
    try:
        data = yaml.safe_load(path.read_text())
    except yaml.YAMLError as exc:
        raise ValueError(f"Invalid demo queries YAML in {path}: {exc}") from exc
    return DemoQueriesFile.model_validate(data).queries


def query_from_demo_response(response: dict | None) -> str | None:
    if response is None or response.get("name") == CANCEL_ACTION:
        return None
    query = response.get("payload", {}).get("message")
    if not query:
        return None
    return query


def resolve_mode(*, command: str | None = None, content: str = "") -> Mode | None:
    text = content.strip()
    if command == INGEST_COMMAND_ID or text in {UPLOAD_STARTER["message"], INGEST_COMMAND_ID}:
        return Mode.INGEST
    if command == DELETE_COMMAND_ID or text in {DELETE_STARTER["message"], DELETE_COMMAND_ID}:
        return Mode.DELETE
    if command == DEMO_COMMAND_ID or text == DEMO_COMMAND_ID:
        return Mode.DEMO
    return None
