from hybrid_search.ui.demo import DEMO_STARTERS


def test_demo_starters_shape():
    assert len(DEMO_STARTERS) == 3
    for item in DEMO_STARTERS:
        assert "label" in item and "message" in item
