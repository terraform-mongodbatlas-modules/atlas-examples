from __future__ import annotations

import re
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

# Split after sentence terminators and on single newlines (headings, list items).
# The lookbehind keeps the delimiter attached to the sentence it closes.
_SENTENCE_BOUNDARY = re.compile(r"(?<=[.!?] )|(?<=\n)")


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
            chunks.extend(_pack_sentences(_split_sentences(paragraph), max_chars=max_chars))
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


def _split_sentences(paragraph: str) -> list[str]:
    return [part for part in _SENTENCE_BOUNDARY.split(paragraph) if part]


def _pack_sentences(sentences: list[str], *, max_chars: int) -> list[str]:
    pieces: list[str] = []
    current = ""
    for sentence in sentences:
        if len(sentence) > max_chars:
            if current:
                pieces.append(current)
                current = ""
            pieces.extend(_hard_split(sentence, max_chars=max_chars))
            continue
        if current and len(current) + len(sentence) > max_chars:
            pieces.append(current)
            current = sentence
            continue
        current += sentence
    if current:
        pieces.append(current)
    return pieces


def _hard_split(paragraph: str, *, max_chars: int) -> list[str]:
    return [paragraph[start : start + max_chars] for start in range(0, len(paragraph), max_chars)]
