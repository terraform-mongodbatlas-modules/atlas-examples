from __future__ import annotations


def format_time(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.0f}s"
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{mins}m {secs}s"


def render_ingest_progress(
    *,
    file_name: str,
    file_idx: int,
    total_files: int,
    elapsed_s: float,
    step: str,
) -> str:
    return "\n".join(
        [
            f"**File {file_idx + 1}/{total_files}:** `{file_name}`",
            f"**Elapsed:** {format_time(elapsed_s)}",
            f"**Step:** {step}",
        ]
    )
