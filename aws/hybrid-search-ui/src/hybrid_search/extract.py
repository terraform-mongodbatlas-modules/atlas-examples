from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

try:
    import pymupdf
except ImportError:
    pymupdf = None

# Voyage tokenizers average about 5 characters per token on English prose.
# https://www.mongodb.com/docs/voyageai/tutorials/tokenization/
# Use 4 to overestimate tokens and keep chunks under the model context window.
_CHARS_PER_TOKEN_ESTIMATE = 4


@dataclass(frozen=True)
class ExtractResult:
    text: str


def extract_text(path: Path) -> ExtractResult:
    suffix = path.suffix.lower()
    if suffix in {".txt", ".md"}:
        return ExtractResult(text=path.read_text())
    if suffix == ".pdf":
        if pymupdf is None:
            msg = "PDF extract requires pymupdf; install with uv sync --extra ui"
            raise RuntimeError(msg)
        doc = pymupdf.open(path)
        try:
            pages = [page.get_text() for page in doc if page.get_text().strip()]
        finally:
            doc.close()
        return ExtractResult(text="\n\n".join(pages))
    msg = f"unsupported file type: {suffix or path.name}"
    raise ValueError(msg)


def chunk_text(text: str, *, max_tokens: int) -> list[str]:
    max_chars = max_tokens * _CHARS_PER_TOKEN_ESTIMATE
    if len(text) <= max_chars:
        return [text] if text.strip() else []
    chunks: list[str] = []
    current: list[str] = []
    current_chars = 0
    for paragraph in text.split("\n\n"):
        if not paragraph.strip():
            continue
        if len(paragraph) > max_chars:
            if current:
                chunks.append("\n\n".join(current))
                current = []
                current_chars = 0
            chunks.extend(_hard_split(paragraph, max_chars=max_chars))
            continue
        separator = 2 if current else 0
        if current_chars + separator + len(paragraph) > max_chars:
            chunks.append("\n\n".join(current))
            current = [paragraph]
            current_chars = len(paragraph)
            continue
        current.append(paragraph)
        current_chars += separator + len(paragraph)
    if current:
        chunks.append("\n\n".join(current))
    return chunks


def _hard_split(paragraph: str, *, max_chars: int) -> list[str]:
    return [paragraph[start : start + max_chars] for start in range(0, len(paragraph), max_chars)]
