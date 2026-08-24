from __future__ import annotations

import chainlit as cl
from chainlit.input_widget import Switch

from hybrid_search.search_modes import DEFAULT, SearchModes

SEARCH_MODES_KEY = "search_modes"
_KEYWORD = "keyword"
_VECTOR = "vector"
_LLM = "llm"


def build_chat_settings(modes: SearchModes) -> cl.ChatSettings:
    return cl.ChatSettings(
        [
            Switch(id=_KEYWORD, label="Keyword search", initial=modes.keyword),
            Switch(id=_VECTOR, label="Vector search", initial=modes.vector),
            Switch(id=_LLM, label="LLM answer", initial=modes.llm),
        ]
    )


def modes_from_settings(settings: dict) -> SearchModes:
    modes = SearchModes(
        keyword=bool(settings.get(_KEYWORD, True)),
        vector=bool(settings.get(_VECTOR, True)),
        llm=bool(settings.get(_LLM, True)),
    )
    modes.validate_retrieval()
    return modes


def confirmation_message(modes: SearchModes) -> str:
    active = [
        name
        for enabled, name in (
            (modes.keyword, "keyword"),
            (modes.vector, "vector"),
            (modes.llm, "LLM"),
        )
        if enabled
    ]
    return f"Search modes: {', '.join(active)}."


async def send_default_settings() -> None:
    cl.user_session.set(SEARCH_MODES_KEY, DEFAULT)
    await build_chat_settings(DEFAULT).send()
