from hybrid_search.ui.ingest_progress import FileProgress, render_ingest_batch


def test_in_progress_heading_and_waiting_row():
    text = render_ingest_batch(
        [
            FileProgress(
                name="NIST.AI.600-1.pdf",
                status="running",
                step="Embedding 113 chunks",
                elapsed_s=7,
            ),
            FileProgress(name="NIST.AI.100-1.pdf", status="waiting"),
        ]
    )
    assert text.startswith("**Ingesting 2 files**")
    assert "- NIST.AI.600-1.pdf: Embedding 113 chunks, 7s" in text
    assert "- NIST.AI.100-1.pdf: waiting" in text
    assert "File 1/2" not in text
    assert "Elapsed:" not in text
    assert "Step:" not in text
    assert "`" not in text


def test_done_heading_and_chunk_counts():
    text = render_ingest_batch(
        [
            FileProgress(name="NIST.AI.600-1.pdf", status="done", elapsed_s=7, chunk_count=113),
            FileProgress(name="NIST.AI.100-1.pdf", status="done", elapsed_s=4, chunk_count=72),
        ]
    )
    assert text.startswith("**Ingested 2 files**")
    assert "- NIST.AI.600-1.pdf: 113 chunks, 7s" in text
    assert "- NIST.AI.100-1.pdf: 72 chunks, 4s" in text


def test_hides_completed_step_while_running():
    text = render_ingest_batch(
        [
            FileProgress(
                name="doc.pdf",
                status="running",
                step="Completed processing file",
                elapsed_s=7,
            )
        ]
    )
    assert "Completed processing file" not in text
    assert "- doc.pdf: 7s" in text


def test_skipped_and_error_include_detail():
    text = render_ingest_batch(
        [
            FileProgress(name="notes.exe", status="skipped", detail="unsupported type"),
            FileProgress(name="bad.pdf", status="error", detail="voyage timeout"),
        ]
    )
    assert "- notes.exe: unsupported type" in text
    assert "- bad.pdf: voyage timeout" in text
