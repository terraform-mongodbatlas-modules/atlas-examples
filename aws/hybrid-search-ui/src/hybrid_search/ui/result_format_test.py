from __future__ import annotations

from hybrid_search.search import RetrievalPipeline
from hybrid_search.ui.result_format import (
    format_location,
    format_retrieval_body,
    format_retrieval_results,
    retrieval_header,
)


def test_retrieval_header_fused():
    assert retrieval_header(RetrievalPipeline.RANK_FUSION) == (
        "Keyword + vector retrieval ($rankFusion)"
    )


def test_retrieval_header_keyword_only():
    header = retrieval_header(RetrievalPipeline.KEYWORD)
    assert header == "Keyword search only"


def test_format_retrieval_results_empty():
    text = format_retrieval_results(
        [],
        pipeline=RetrievalPipeline.RANK_FUSION,
    )
    assert "Keyword + vector retrieval" in text
    assert "No matching chunks found." in text
    assert "### Sources\nNo sources retrieved" in text


def test_format_retrieval_results_one_hit():
    refs = [{"file_path": "docs/NIST.AI.100-1.pdf", "content": "AI RMF context", "score": 0.87}]
    text = format_retrieval_results(
        refs,
        pipeline=RetrievalPipeline.KEYWORD,
    )
    assert "Keyword search only" in text
    assert "**1 · NIST.AI.100-1.pdf** · 0.870" in text
    assert "> AI RMF context" in text
    assert "- NIST.AI.100-1.pdf" in text


def test_format_retrieval_results_truncates_snippet():
    refs = [{"file_path": "a.txt", "content": "x" * 250, "score": 1.0}]
    text = format_retrieval_results(refs, pipeline=RetrievalPipeline.RANK_FUSION)
    assert "…" in text
    assert "x" * 201 not in text


def test_format_retrieval_body_strips_markdown_noise():
    refs = [
        {
            "file_path": "LLM08.md",
            "content": "## Description\n\n9. Vector-store protection",
            "score": 3.4,
        }
    ]
    text = format_retrieval_body(refs)
    assert "## Description" not in text
    assert "> Description Vector-store protection" in text
    assert "\n9. " not in text


def test_format_retrieval_body_empty():
    text = format_retrieval_body([])
    assert "No matching chunks found." in text


def test_format_location_page():
    assert format_location({"page": 12}) == "p. 12"


def test_format_location_line_range():
    assert format_location({"start_line": 40, "end_line": 58}) == "lines 40-58"


def test_format_location_none():
    assert format_location({}) == ""


def test_format_hit_with_page_shows_location():
    refs = [{"file_path": "docs/NIST.AI.100-1.pdf", "content": "ctx", "score": 0.9, "page": 12}]
    text = format_retrieval_results(refs, pipeline=RetrievalPipeline.KEYWORD)
    assert "**1 · NIST.AI.100-1.pdf · p. 12** · 0.900" in text
    assert "- NIST.AI.100-1.pdf · p. 12" in text


def test_format_hit_with_line_range_shows_location():
    refs = [
        {"file_path": "notes.md", "content": "ctx", "score": 0.5, "start_line": 40, "end_line": 58}
    ]
    text = format_retrieval_results(refs, pipeline=RetrievalPipeline.KEYWORD)
    assert "**1 · notes.md · lines 40-58** · 0.500" in text


def test_format_hit_without_location_shows_filename_alone():
    refs = [{"file_path": "a.txt", "content": "ctx", "score": 0.5}]
    text = format_retrieval_results(refs, pipeline=RetrievalPipeline.KEYWORD)
    assert "**1 · a.txt** · 0.500" in text
