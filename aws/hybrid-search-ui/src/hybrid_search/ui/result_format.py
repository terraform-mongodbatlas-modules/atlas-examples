from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from hybrid_search.generate import unique_source_files
from hybrid_search.search import RetrievalPipeline

_SNIPPET_MAX = 200
_HEADING_RE = re.compile(r"^#+\s*")
_ORDERED_LIST_RE = re.compile(r"^\d+\.\s+")
_BULLET_LIST_RE = re.compile(r"^[-*+]\s+")


def retrieval_header(pipeline: RetrievalPipeline) -> str:
    match pipeline:
        case RetrievalPipeline.KEYWORD:
            return "Keyword search only"
        case RetrievalPipeline.VECTOR:
            return "Vector search only"
        case RetrievalPipeline.RANK_FUSION:
            return "Keyword + vector retrieval ($rankFusion)"


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


def format_retrieval_body(references: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    if references:
        hits = "\n\n---\n\n".join(
            _format_hit(index, ref) for index, ref in enumerate(references, start=1)
        )
        lines.append(hits)
    else:
        lines.append("No matching chunks found.")
    lines.extend(["", _format_sources(unique_source_files(references))])
    return "\n".join(lines)


def format_retrieval_results(
    references: list[dict[str, Any]],
    *,
    pipeline: RetrievalPipeline,
) -> str:
    header = retrieval_header(pipeline)
    body = format_retrieval_body(references)
    return f"{header}\n\n{body}"
