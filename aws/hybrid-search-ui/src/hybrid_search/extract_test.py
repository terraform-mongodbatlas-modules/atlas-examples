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


def test_iter_pdf_page_groups(monkeypatch):
    class FakePage:
        def __init__(self, text: str) -> None:
            self._text = text

        def get_text(self) -> str:
            return self._text

    class FakeDoc:
        def __init__(self, _path) -> None:
            self.pages = [FakePage("p1"), FakePage("p2"), FakePage("p3")]

        def __iter__(self):
            return iter(self.pages)

        def close(self) -> None:
            return None

    fake_pymupdf = type("pymupdf", (), {"open": staticmethod(lambda path: FakeDoc(path))})
    monkeypatch.setattr(extract_module, "pymupdf", fake_pymupdf)
    groups = list(extract_module.iter_pdf_page_groups(Path("x.pdf"), max_pages_per_group=2))
    assert groups == ["p1\n\np2", "p3"]


def test_text_needs_split():
    assert extract_module.text_needs_split("x" * (120_000 * 4)) is True


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
