from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock

import pytest

import hybrid_search.extract as extract_module


def test_is_supported_accepts_known_suffixes_case_insensitively(tmp_path: Path):
    for name in ("doc.md", "doc.txt", "doc.pdf", "DOC.PDF"):
        assert extract_module.is_supported(tmp_path / name)


def test_is_supported_rejects_other_suffixes(tmp_path: Path):
    assert not extract_module.is_supported(tmp_path / "data.csv")


def test_pdf_chunks_require_pymupdf(tmp_path: Path, monkeypatch):
    path = tmp_path / "doc.pdf"
    path.write_bytes(b"%PDF-1.4")
    monkeypatch.setattr(extract_module, "pymupdf", None)
    with pytest.raises(RuntimeError, match="pymupdf"):
        extract_module.extract_chunks(path, max_tokens=512)


def test_chunk_text_single_small_input():
    assert extract_module.chunk_text("hello", max_tokens=512) == ["hello"]


def test_chunk_text_splits_on_paragraph_boundaries():
    paragraph = "a" * 1000
    text = "\n\n".join([paragraph] * 5)
    chunks = extract_module.chunk_text(text, max_tokens=1000)
    assert len(chunks) > 1
    assert all(len(chunk) <= 4000 for chunk in chunks)
    assert "".join(chunks).replace("\n\n", "") == text.replace("\n\n", "")


def test_chunk_text_hard_splits_oversized_paragraph():
    paragraph = "b" * 10_000
    chunks = extract_module.chunk_text(paragraph, max_tokens=1000)
    assert len(chunks) == 3
    assert all(len(chunk) <= 4000 for chunk in chunks)


def test_chunk_text_skips_blank_input():
    assert extract_module.chunk_text("   \n\n  ", max_tokens=512) == []


def test_chunk_text_sentence_boundary():
    paragraph = "".join(f"{'s' * 596}. " for _ in range(10))
    chunks = extract_module.chunk_text(paragraph, max_tokens=500)
    assert len(chunks) > 1
    assert all(len(chunk) <= 2000 for chunk in chunks)
    assert all(chunk.endswith(". ") for chunk in chunks)
    assert "".join(chunks) == paragraph


def test_chunk_text_heading_boundary():
    paragraph = "\n".join(f"## Section {i}\n{'b' * 2000}" for i in range(3))
    chunks = extract_module.chunk_text(paragraph, max_tokens=1000)
    assert len(chunks) > 1
    assert all(len(chunk) <= 4000 for chunk in chunks)
    assert all(chunk.endswith("\n") for chunk in chunks[:-1])
    assert all(sum(f"## Section {i}\n" in chunk for chunk in chunks) == 1 for i in range(3))
    assert "".join(chunks) == paragraph


def test_extract_chunks_markdown_carries_line_range(tmp_path: Path):
    path = tmp_path / "notes.md"
    path.write_text("# Title\n\nFirst paragraph.\n\nSecond paragraph.\n")

    chunks = extract_module.extract_chunks(path, max_tokens=512)

    assert len(chunks) == 1
    assert chunks[0].text.startswith("# Title")
    assert chunks[0].page is None
    assert chunks[0].start_line == 1
    assert chunks[0].end_line == 6


def test_extract_chunks_txt_has_no_page(tmp_path: Path):
    path = tmp_path / "note.txt"
    path.write_text("just text")

    chunks = extract_module.extract_chunks(path, max_tokens=512)

    assert len(chunks) == 1
    assert chunks[0].page is None
    assert chunks[0].start_line == 1
    assert chunks[0].end_line == 1


def test_extract_chunks_rejects_unsupported_suffix(tmp_path: Path):
    path = tmp_path / "data.csv"
    path.write_text("a,b")

    with pytest.raises(ValueError, match="unsupported file type"):
        extract_module.extract_chunks(path, max_tokens=512)


def test_extract_chunks_pdf_carries_page(tmp_path: Path, monkeypatch):
    class FakePage:
        def __init__(self, text: str):
            self._text = text

        def get_text(self) -> str:
            return self._text

    class FakeDoc:
        def __init__(self, pages: list[str]):
            self._pages = [FakePage(text) for text in pages]

        def __iter__(self):
            return iter(self._pages)

        def close(self) -> None:
            return None

    monkeypatch.setattr(
        extract_module,
        "pymupdf",
        MagicMock(open=MagicMock(return_value=FakeDoc(["page one", "page two"]))),
    )
    path = tmp_path / "doc.pdf"
    path.write_bytes(b"%PDF-1.4")

    chunks = extract_module.extract_chunks(path, max_tokens=512)

    assert len(chunks) == 1
    assert chunks[0].text == "page one\n\npage two"
    assert chunks[0].page == 1
    assert chunks[0].start_line is None
    assert chunks[0].end_line is None
