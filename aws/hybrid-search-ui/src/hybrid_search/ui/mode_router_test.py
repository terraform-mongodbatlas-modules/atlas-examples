from unittest.mock import MagicMock, patch

import chainlit as cl

from hybrid_search.ui.demo import INGEST_COMMAND_ID, Mode
from hybrid_search.ui.mode_router import UI_MODE_KEY, UiMode, get_ui_mode, resolve_mode, set_ui_mode


def test_resolve_mode_reexport():
    assert resolve_mode(command=INGEST_COMMAND_ID) == Mode.INGEST


@patch.object(cl, "user_session", new_callable=MagicMock)
def test_get_ui_mode_default(session):
    session.get.return_value = None
    assert get_ui_mode() == UiMode.QUERY


@patch.object(cl, "user_session", new_callable=MagicMock)
def test_set_and_get_ui_mode(session):
    store: dict[str, str] = {}
    session.get.side_effect = store.get
    session.set.side_effect = store.__setitem__
    set_ui_mode(UiMode.DELETE)
    assert get_ui_mode() == UiMode.DELETE
    session.get.assert_called_with(UI_MODE_KEY)
