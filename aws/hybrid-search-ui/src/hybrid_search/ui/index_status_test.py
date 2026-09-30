from __future__ import annotations

from hybrid_search.health import IndexState
from hybrid_search.ui.index_status import (
    failed_names,
    not_ready_names,
    problem_message,
    render_index_status,
)


def _states(*statuses: str) -> list[IndexState]:
    names = ["autoembed_idx", "text_idx"]
    return [IndexState(name=name, status=status) for name, status in zip(names, statuses)]


def test_render_ready_lines():
    text = render_index_status(_states("READY", "READY"))
    assert text == "chunks.autoembed_idx READY\nchunks.text_idx READY"


def test_render_building_line():
    states = _states("BUILDING", "READY")
    assert "chunks.autoembed_idx BUILDING" in render_index_status(states)
    assert not_ready_names(states) == ["autoembed_idx"]
    assert failed_names(states) == []


def test_render_failed_line():
    states = _states("FAILED", "READY")
    assert "chunks.autoembed_idx FAILED" in render_index_status(states)
    assert failed_names(states) == ["autoembed_idx"]
    assert not_ready_names(states) == ["autoembed_idx"]


def test_problem_message_none_when_ready():
    assert problem_message(_states("READY", "READY"), query=True) is None
    assert problem_message(_states("READY", "READY"), query=False) is None


def test_problem_message_failed_is_error():
    message = problem_message(_states("FAILED", "READY"), query=True)
    assert message is not None
    assert "unavailable" in message
    assert "chunks.autoembed_idx FAILED" in message


def test_problem_message_not_ready_wording_differs_for_query():
    states = _states("BUILDING", "READY")
    query_message = problem_message(states, query=True)
    session_message = problem_message(states, query=False)
    assert query_message is not None and "not ready yet" in query_message
    assert session_message is not None and "still building" in session_message
    assert "chunks.autoembed_idx BUILDING" in query_message
