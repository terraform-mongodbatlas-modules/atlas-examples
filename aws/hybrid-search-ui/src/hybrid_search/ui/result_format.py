from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from hybrid_search.generate import unique_source_files
from hybrid_search.search import (
    ZERO_QUERY_EMBEDDING,
    ZERO_STORED_VECTORS,
    RetrievalPipeline,
)
from hybrid_search.search_modes import SearchModes

_SNIPPET_MAX = 200
_HEADING_RE = re.compile(r"^#+\s*")
_ORDERED_LIST_RE = re.compile(r"^\d+\.\s+")
_BULLET_LIST_RE = re.compile(r"^[-*+]\s+")
_VECTOR_SKIP_HINTS = {
    ZERO_QUERY_EMBEDDING: ("Check VOYAGE_API_KEY and VOYAGE_BASE_URL. "),
    ZERO_STORED_VECTORS: (
        "Stored chunk vectors are zero. Re-ingest documents after fixing Voyage credentials."
    ),
}


def retrieval_header(
    pipeline: RetrievalPipeline,
    *,
    vector_skipped_reason: str | None = None,
) -> str:
    match pipeline:
        case RetrievalPipeline.KEYWORD:
            if vector_skipped_reason:
                return f"Keyword search only (vector skipped: {vector_skipped_reason})"
            return "Keyword search only"
        case RetrievalPipeline.VECTOR:
            if vector_skipped_reason:
                return f"Vector search unavailable ({vector_skipped_reason})"
            return "Vector search only"
        case RetrievalPipeline.RANK_FUSION:
            return "Keyword + vector retrieval ($rankFusion)"


def _vector_skip_notice(vector_skipped_reason: str | None) -> str | None:
    if not vector_skipped_reason:
        return None
    hint = _VECTOR_SKIP_HINTS.get(vector_skipped_reason, vector_skipped_reason)
    return f"Vector search was not used ({vector_skipped_reason}). {hint}"


def _format_sources(source_files: list[str]) -> str:
    if source_files:
        bullets = "\n".join(f"- {name}" for name in source_files)
        return f"### Sources\n{bullets}"
    return "### Sources\nNo sources retrieved"


def _plain_snippet(content: str) -> str:
    lines: list[str] = []
    for raw in content.strip().splitlines():
        line = raw.strip()
        if not line:
            continue
        line = _HEADING_RE.sub("", line)
        line = _ORDERED_LIST_RE.sub("", line)
        line = _BULLET_LIST_RE.sub("", line)
        if line:
            lines.append(line)
    text = " ".join(lines)
    if len(text) > _SNIPPET_MAX:
        text = f"{text[:_SNIPPET_MAX].rstrip()}…"
    return text or "(no preview)"


def _format_hit(index: int, ref: dict[str, Any]) -> str:
    filename = Path(ref.get("file_path", "")).name or "unknown"
    score = float(ref.get("score") or 0.0)
    snippet = _plain_snippet(str(ref.get("content", "")))
    return f"**{index} · {filename}** · {score:.3f}\n\n> {snippet}"


def format_retrieval_body(
    references: list[dict[str, Any]],
    *,
    modes: SearchModes,
    pipeline: RetrievalPipeline,
    vector_skipped_reason: str | None = None,
) -> str:
    lines: list[str] = []
    notice = _vector_skip_notice(vector_skipped_reason)
    if notice:
        lines.extend([notice, ""])
    if references:
        hits = "\n\n---\n\n".join(
            _format_hit(index, ref) for index, ref in enumerate(references, start=1)
        )
        lines.append(hits)
    elif pipeline == RetrievalPipeline.VECTOR and vector_skipped_reason:
        lines.append("No vector results. Fix Voyage credentials and try again.")
    else:
        lines.append("No matching chunks found.")
    lines.extend(["", _format_sources(unique_source_files(references))])
    return "\n".join(lines)


def format_retrieval_results(
    references: list[dict[str, Any]],
    *,
    modes: SearchModes,
    pipeline: RetrievalPipeline,
    vector_skipped_reason: str | None = None,
) -> str:
    header = retrieval_header(pipeline, vector_skipped_reason=vector_skipped_reason)
    body = format_retrieval_body(
        references,
        modes=modes,
        pipeline=pipeline,
        vector_skipped_reason=vector_skipped_reason,
    )
    return f"{header}\n\n{body}"
