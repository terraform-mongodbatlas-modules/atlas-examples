from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

try:
    import pymupdf
except ImportError:
    pymupdf = None

VOYAGE_AUTO_CHUNK_TOKEN_CAP = 120_000
_CHARS_PER_TOKEN_ESTIMATE = 4
PDF_PAGES_PER_GROUP = 25


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


def iter_pdf_page_groups(path: Path, *, max_pages_per_group: int) -> Iterator[str]:
    if pymupdf is None:
        msg = "PDF page groups require pymupdf; install with uv sync --extra ui"
        raise RuntimeError(msg)
    doc = pymupdf.open(path)
    try:
        batch: list[str] = []
        for page in doc:
            text = page.get_text()
            if not text.strip():
                continue
            batch.append(text)
            if len(batch) >= max_pages_per_group:
                yield "\n\n".join(batch)
                batch = []
        if batch:
            yield "\n\n".join(batch)
    finally:
        doc.close()


def estimate_tokens(text: str) -> int:
    return len(text) // _CHARS_PER_TOKEN_ESTIMATE


def text_needs_split(text: str) -> bool:
    return estimate_tokens(text) >= VOYAGE_AUTO_CHUNK_TOKEN_CAP
