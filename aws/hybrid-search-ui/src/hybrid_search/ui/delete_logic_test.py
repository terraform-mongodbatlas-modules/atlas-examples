from hybrid_search.ingest import IngestedFile
from hybrid_search.ui.delete_logic import format_ingested_file_list, resolve_delete_selection


def _files() -> list[IngestedFile]:
    return [
        IngestedFile(file_path="/tmp/NIST.AI.100-1.pdf", chunk_count=72),
        IngestedFile(file_path="/tmp/NIST.AI.600-1.pdf", chunk_count=113),
    ]


def test_format_ingested_file_list_empty():
    assert format_ingested_file_list([]) == "No ingested documents."


def test_format_ingested_file_list_numbered():
    text = format_ingested_file_list(_files())
    assert "1. NIST.AI.100-1.pdf (72 chunks)" in text
    assert "2. NIST.AI.600-1.pdf (113 chunks)" in text


def test_resolve_delete_selection_by_number():
    paths = resolve_delete_selection("2", _files())
    assert paths == ["/tmp/NIST.AI.600-1.pdf"]


def test_resolve_delete_selection_by_numbers():
    paths = resolve_delete_selection("1,2", _files())
    assert paths == ["/tmp/NIST.AI.100-1.pdf", "/tmp/NIST.AI.600-1.pdf"]


def test_resolve_delete_selection_by_filename():
    paths = resolve_delete_selection("NIST.AI.100-1.pdf", _files())
    assert paths == ["/tmp/NIST.AI.100-1.pdf"]


def test_resolve_delete_selection_all():
    paths = resolve_delete_selection("all", _files())
    assert len(paths) == 2


def test_resolve_delete_selection_invalid():
    assert resolve_delete_selection("9", _files()) is None
    assert resolve_delete_selection("", _files()) is None
