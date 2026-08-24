from __future__ import annotations

from hybrid_search.search_modes import SearchModes
from hybrid_search.ui.result_format import format_retrieval_results

_MODES = SearchModes(keyword=True, vector=True, llm=False)


def test_format_retrieval_results_empty():
    text = format_retrieval_results([], modes=_MODES)
    assert "Keyword + vector retrieval" in text
    assert "No matching chunks found." in text
    assert "### Sources\nNo sources retrieved" in text


def test_format_retrieval_results_one_hit():
    refs = [{"file_path": "docs/NIST.AI.100-1.pdf", "content": "AI RMF context", "score": 0.87}]
    text = format_retrieval_results(refs, modes=SearchModes(keyword=True, vector=False))
    assert "Keyword search only" in text
    assert "**NIST.AI.100-1.pdf** (score 0.870)" in text
    assert "AI RMF context" in text
    assert "- NIST.AI.100-1.pdf" in text


def test_format_retrieval_results_truncates_snippet():
    refs = [{"file_path": "a.txt", "content": "x" * 250, "score": 1.0}]
    text = format_retrieval_results(refs, modes=_MODES)
    assert "…" in text
    assert "x" * 201 not in text
