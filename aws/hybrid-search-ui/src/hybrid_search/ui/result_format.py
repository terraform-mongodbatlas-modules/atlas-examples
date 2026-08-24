from __future__ import annotations

from pathlib import Path
from typing import Any

from hybrid_search.generate import unique_source_files
from hybrid_search.search_modes import SearchModes

_SNIPPET_MAX = 200


def _retrieval_header(modes: SearchModes) -> str:
    if modes.keyword and modes.vector:
        return "Keyword + vector retrieval ($rankFusion)"
    if modes.keyword:
        return "Keyword search only"
    return "Vector search only"


def _format_sources(source_files: list[str]) -> str:
    if source_files:
        bullets = "\n".join(f"- {name}" for name in source_files)
        return f"### Sources\n{bullets}"
    return "### Sources\nNo sources retrieved"


def format_retrieval_results(
    references: list[dict[str, Any]],
    *,
    modes: SearchModes,
) -> str:
    lines = [_retrieval_header(modes), ""]
    if references:
        for index, ref in enumerate(references, start=1):
            filename = Path(ref.get("file_path", "")).name or "unknown"
            score = float(ref.get("score") or 0.0)
            snippet = ref.get("content", "").strip()
            if len(snippet) > _SNIPPET_MAX:
                snippet = f"{snippet[:_SNIPPET_MAX]}…"
            lines.append(f"{index}. **{filename}** (score {score:.3f}) — {snippet}")
    else:
        lines.append("No matching chunks found.")
    lines.extend(["", _format_sources(unique_source_files(references))])
    return "\n".join(lines)
