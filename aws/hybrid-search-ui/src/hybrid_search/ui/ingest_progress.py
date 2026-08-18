from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

type FileStatus = Literal["waiting", "running", "done", "error", "skipped"]

_HIDDEN_RUNNING_STEP = "Completed processing file"


@dataclass(frozen=True)
class FileProgress:
    name: str
    status: FileStatus
    step: str = ""
    elapsed_s: float = 0.0
    chunk_count: int | None = None
    detail: str = ""


def format_time(seconds: float) -> str:
    if seconds < 60:
        return f"{seconds:.0f}s"
    mins = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{mins}m {secs}s"


def render_ingest_batch(files: list[FileProgress]) -> str:
    n = len(files)
    noun = "file" if n == 1 else "files"
    in_progress = any(item.status in {"waiting", "running"} for item in files)
    verb = "Ingesting" if in_progress else "Ingested"
    lines = [f"**{verb} {n} {noun}**", ""]
    lines.extend(_row(item) for item in files)
    return "\n".join(lines)


def _row(item: FileProgress) -> str:
    elapsed = format_time(item.elapsed_s)
    match item.status:
        case "waiting":
            return f"- {item.name}: waiting"
        case "running":
            if item.step and item.step != _HIDDEN_RUNNING_STEP:
                return f"- {item.name}: {item.step}, {elapsed}"
            return f"- {item.name}: {elapsed}"
        case "done":
            n = item.chunk_count or 0
            return f"- {item.name}: {n} chunks, {elapsed}"
        case "skipped" | "error":
            return f"- {item.name}: {item.detail}"
