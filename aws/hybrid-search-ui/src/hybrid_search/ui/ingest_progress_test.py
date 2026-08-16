from hybrid_search.ui.ingest_progress import render_ingest_progress


def test_render_includes_progress_steps():
    text = render_ingest_progress(
        file_name="doc.pdf",
        file_idx=0,
        total_files=2,
        elapsed_s=12.0,
        step="Embedding 3 chunks",
    )
    assert "doc.pdf" in text
    assert "Embedding 3 chunks" in text

    stored = render_ingest_progress(
        file_name="doc.pdf",
        file_idx=0,
        total_files=1,
        elapsed_s=30.0,
        step="Stored 3 chunks",
    )
    assert "Stored 3 chunks" in stored
