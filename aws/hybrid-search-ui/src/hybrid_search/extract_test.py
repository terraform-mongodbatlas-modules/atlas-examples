from __future__ import annotations

from pathlib import Path

import pytest

import hybrid_search.extract as extract_module


def test_extract_txt(tmp_path: Path):
    path = tmp_path / "note.md"
    path.write_text("hello")
    assert extract_module.extract_text(path).text == "hello"


def test_pdf_requires_pymupdf(tmp_path: Path, monkeypatch):
    path = tmp_path / "doc.pdf"
    path.write_bytes(b"%PDF-1.4")
    monkeypatch.setattr(extract_module, "pymupdf", None)
    with pytest.raises(RuntimeError, match="pymupdf"):
        extract_module.extract_text(path)


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
