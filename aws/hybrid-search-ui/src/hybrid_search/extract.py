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


@dataclass(frozen=True)
class Chunk:
    text: str
    page: int | None = None
    start_line: int | None = None
    end_line: int | None = None


def _page_texts(path: Path) -> list[str]:
    if pymupdf is None:
        msg = "PDF extract requires pymupdf; install with uv sync --extra ui"
        raise RuntimeError(msg)
    doc = pymupdf.open(path)
    try:
        return [text for page in doc if (text := page.get_text()).strip()]
    finally:
        doc.close()


def extract_text(path: Path) -> ExtractResult:
    suffix = path.suffix.lower()
    if suffix in {".txt", ".md"}:
        return ExtractResult(text=path.read_text())
    if suffix == ".pdf":
        return ExtractResult(text="\n\n".join(_page_texts(path)))
    msg = f"unsupported file type: {suffix or path.name}"
    raise ValueError(msg)


def _chunk_locations(
    chunks: list[str],
    normalized: str,
    *,
    is_pdf: bool,
    page_starts: list[int],
) -> list[Chunk]:
    located: list[Chunk] = []
    cursor = 0
    for chunk in chunks:
        start = normalized.find(chunk, cursor)
        if start < 0:
            located.append(Chunk(text=chunk))
            continue
        end = start + len(chunk)
        cursor = end
        if is_pdf:
            page = max(
                (index for index, page_start in enumerate(page_starts) if page_start <= start),
                default=0,
            )
            located.append(Chunk(text=chunk, page=page + 1))
        else:
            located.append(
                Chunk(
                    text=chunk,
                    start_line=normalized.count("\n", 0, start) + 1,
                    end_line=normalized.count("\n", 0, end) + 1,
                )
            )
    return located


def extract_chunks(path: Path, *, max_tokens: int) -> list[Chunk]:
    suffix = path.suffix.lower()
    if suffix == ".pdf":
        pages = _page_texts(path)
        normalized = "\n\n".join(page.strip() for page in pages)
        page_starts: list[int] = []
        cursor = 0
        for page in pages:
            page_starts.append(cursor)
            cursor += len(page.strip()) + 2
        is_pdf = True
    elif suffix in {".txt", ".md"}:
        normalized = path.read_text()
        page_starts = []
        is_pdf = False
    else:
        msg = f"unsupported file type: {suffix or path.name}"
        raise ValueError(msg)
    chunks = chunk_text(normalized, max_tokens=max_tokens)
    return _chunk_locations(chunks, normalized, is_pdf=is_pdf, page_starts=page_starts)


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
