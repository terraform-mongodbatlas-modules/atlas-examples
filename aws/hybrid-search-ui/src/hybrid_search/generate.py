from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any

from hybrid_search import llm as llm_module
from hybrid_search.settings import HybridSearchSettings


@dataclass(frozen=True)
class GenerateResult:
    answer: str
    source_files: list[str]


def unique_source_files(references: list[dict[str, Any]]) -> list[str]:
    seen: set[str] = set()
    names: list[str] = []
    for ref in references:
        raw = ref.get("file_path", "")
        if raw in {"", "unknown_source"}:
            continue
        name = Path(raw).name
        if name in seen:
            continue
        seen.add(name)
        names.append(name)
    return names


async def generate_answer(
    query: str,
    references: list[dict[str, Any]],
    *,
    settings: HybridSearchSettings,
) -> GenerateResult:
    source_files = unique_source_files(references)
    if settings.enable_llm:
        context = _build_context(references)
        prompt = (
            "Answer the question using only the context snippets. "
            "If the context is insufficient, say so briefly.\n\n"
            f"Question: {query}\n\nContext:\n{context}"
        )
        answer = await llm_module.run_rag_prompt(prompt, settings=settings)
        return GenerateResult(answer=answer, source_files=source_files)
    return GenerateResult(
        answer="Retrieval-only mode (ENABLE_LLM=false). See sources below.",
        source_files=source_files,
    )


def _build_context(references: list[dict[str, Any]], *, max_snippets: int = 5) -> str:
    parts: list[str] = []
    for ref in references[:max_snippets]:
        content = ref.get("content", "").strip()
        if content:
            parts.append(content)
    return "\n---\n".join(parts)
