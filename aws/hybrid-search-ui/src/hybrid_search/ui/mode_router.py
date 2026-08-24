from __future__ import annotations

from enum import StrEnum

import chainlit as cl

from hybrid_search.ui.demo import Mode
from hybrid_search.ui.demo import resolve_mode as _resolve_mode

UI_MODE_KEY = "ui_mode"
PENDING_FILE_ASK_KEY = "pending_file_ask"


class UiMode(StrEnum):
    QUERY = "query"
    INGEST = "ingest"
    DELETE = "delete"


def get_ui_mode() -> UiMode:
    stored = cl.user_session.get(UI_MODE_KEY)
    if stored is None:
        return UiMode.QUERY
    return UiMode(stored)


def set_ui_mode(mode: UiMode) -> None:
    cl.user_session.set(UI_MODE_KEY, mode)


def resolve_mode(*, command: str | None = None, content: str = "") -> Mode | None:
    return _resolve_mode(command=command, content=content)
