from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class IndexState:
    name: str
    status: str


def build_health_payload(
    *,
    index_states: list[IndexState],
    has_chunks: bool,
) -> dict:
    return {
        "indexes_ready": bool(index_states)
        and all(state.status == "READY" for state in index_states),
        "data_ingested": has_chunks,
        "indexes": [{"name": state.name, "status": state.status} for state in index_states],
    }
