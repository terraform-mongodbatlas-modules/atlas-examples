from __future__ import annotations

import re
from pathlib import Path
from typing import Any

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


def format_location(ref: dict[str, Any]) -> str:
    page = ref.get("page")
    if page is not None:
        return f"p. {page}"
    start = ref.get("start_line")
    end = ref.get("end_line")
    if start is not None and end is not None:
        return f"lines {start}-{end}"
    return ""


def _format_sources(references: list[dict[str, Any]]) -> str:
    if not references:
        return "### Sources\nNo sources retrieved"
    seen: set[str] = set()
    lines: list[str] = []
    for ref in references:
        filename = Path(ref.get("file_path", "")).name or "unknown"
        location = format_location(ref)
        label = f"{filename} · {location}" if location else filename
        if label in seen:
            continue
        seen.add(label)
        lines.append(f"- {label}")
    return "### Sources\n" + "\n".join(lines)


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
    location = format_location(ref)
    label = f"{filename} · {location}" if location else filename
    score = float(ref.get("score") or 0.0)
    snippet = _plain_snippet(str(ref.get("content", "")))
    return f"**{index} · {label}** · {score:.3f}\n\n> {snippet}"


def format_retrieval_body(references: list[dict[str, Any]]) -> str:
    lines: list[str] = []
    if references:
        hits = "\n\n---\n\n".join(
            _format_hit(index, ref) for index, ref in enumerate(references, start=1)
        )
        lines.append(hits)
    else:
        lines.append("No matching chunks found.")
    lines.extend(["", _format_sources(references)])
    return "\n".join(lines)


def format_retrieval_results(
    references: list[dict[str, Any]],
    *,
    pipeline: RetrievalPipeline,
) -> str:
    header = retrieval_header(pipeline)
    body = format_retrieval_body(references)
    return f"{header}\n\n{body}"
