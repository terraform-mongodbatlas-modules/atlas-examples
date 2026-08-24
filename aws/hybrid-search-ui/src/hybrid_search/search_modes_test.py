from __future__ import annotations

import pytest

from hybrid_search.search_modes import DEFAULT, SearchModes


def test_search_modes_defaults():
    assert DEFAULT == SearchModes()
    assert DEFAULT.keyword and DEFAULT.vector and DEFAULT.llm


def test_search_modes_rejects_all_retrieval_off():
    with pytest.raises(ValueError, match="keyword or vector"):
        SearchModes(keyword=False, vector=False).validate_retrieval()
