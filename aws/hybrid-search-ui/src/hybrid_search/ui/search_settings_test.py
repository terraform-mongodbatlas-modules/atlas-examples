from __future__ import annotations

import pytest

from hybrid_search.search_modes import SearchModes
from hybrid_search.ui.search_settings import modes_from_settings


def test_modes_from_settings_round_trip():
    modes = SearchModes(keyword=True, vector=False, llm=False)
    assert modes_from_settings({"keyword": True, "vector": False, "llm": False}) == modes


def test_modes_from_settings_defaults():
    assert modes_from_settings({}) == SearchModes()


def test_modes_from_settings_rejects_both_retrieval_off():
    with pytest.raises(ValueError, match="keyword or vector"):
        modes_from_settings({"keyword": False, "vector": False, "llm": True})
