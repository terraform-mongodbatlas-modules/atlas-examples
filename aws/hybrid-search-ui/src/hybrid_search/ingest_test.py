from __future__ import annotations

import hybrid_search.ingest as ingest_module
from hybrid_search.extract import Chunk


def test_chunk_doc_id():
    assert ingest_module.chunk_doc_id("/tmp/a.pdf", 2) == "/tmp/a.pdf#2"


def test_upsert_ops_one_doc_per_chunk():
    ops = ingest_module._upsert_ops("/tmp/a.txt", [Chunk(text="first"), Chunk(text="second")])

    assert len(ops) == 2
    assert [op._filter for op in ops] == [{"_id": "/tmp/a.txt#0"}, {"_id": "/tmp/a.txt#1"}]
    assert [op._doc["content"] for op in ops] == ["first", "second"]
    assert all(op._doc["file_path"] == "/tmp/a.txt" for op in ops)
    assert all("vector" not in op._doc for op in ops)


def test_upsert_ops_skips_empty_chunks():
    ops = ingest_module._upsert_ops(
        "/tmp/a.txt",
        [Chunk(text=""), Chunk(text="good", start_line=1, end_line=1), Chunk(text="   ")],
    )

    assert len(ops) == 1
    assert ops[0]._doc["content"] == "good"


def test_upsert_ops_writes_location_fields_when_set():
    ops = ingest_module._upsert_ops(
        "/tmp/a.md",
        [Chunk(text="body", start_line=1, end_line=4)],
    )

    assert ops[0]._doc["start_line"] == 1
    assert ops[0]._doc["end_line"] == 4
    assert "page" not in ops[0]._doc


def test_upsert_ops_omits_location_fields_when_absent():
    ops = ingest_module._upsert_ops("/tmp/a.txt", [Chunk(text="hello")])

    assert "page" not in ops[0]._doc
    assert "start_line" not in ops[0]._doc
    assert "end_line" not in ops[0]._doc


def test_upsert_ops_uses_source_name_for_stored_file_path():
    ops = ingest_module._upsert_ops("NIST.AI.100-1.pdf", [Chunk(text="hello")])

    assert ops[0]._filter == {"_id": "NIST.AI.100-1.pdf#0"}
    assert ops[0]._doc["file_path"] == "NIST.AI.100-1.pdf"


def test_skip_reason_for_filename():
    ingested = {"a.pdf"}
    batch: set[str] = set()
    assert ingest_module.skip_reason_for_filename("a.pdf", ingested=ingested, batch=batch) == (
        "already ingested"
    )
    assert ingest_module.skip_reason_for_filename("b.pdf", ingested=ingested, batch=batch) is None
    batch.add("b.pdf")
    assert ingest_module.skip_reason_for_filename("b.pdf", ingested=ingested, batch=batch) == (
        "already ingested"
    )


def test_ingested_file_display_name():
    item = ingest_module.IngestedFile(file_path="/tmp/nested/a.pdf", chunk_count=3)
    assert item.display_name == "a.pdf"
