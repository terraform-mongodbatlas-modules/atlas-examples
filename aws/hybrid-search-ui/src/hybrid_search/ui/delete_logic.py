from __future__ import annotations

from hybrid_search.ingest import IngestedFile


def format_ingested_file_list(files: list[IngestedFile]) -> str:
    if not files:
        return "No ingested documents."
    lines = ["**Ingested documents**", ""]
    for index, item in enumerate(files, start=1):
        lines.append(f"{index}. {item.display_name} ({item.chunk_count} chunks)")
    lines.extend(
        [
            "",
            "Reply with a number, comma-separated numbers, a filename, or `all` to delete.",
        ]
    )
    return "\n".join(lines)


def resolve_delete_selection(selection: str, files: list[IngestedFile]) -> list[str] | None:
    text = selection.strip()
    if not text:
        return None
    if text.lower() == "all":
        return [item.file_path for item in files]
    if text.isdigit():
        index = int(text)
        if 1 <= index <= len(files):
            return [files[index - 1].file_path]
        return None
    if all(part.strip().isdigit() for part in text.split(",")):
        paths: list[str] = []
        for part in text.split(","):
            index = int(part.strip())
            if not 1 <= index <= len(files):
                return None
            path = files[index - 1].file_path
            if path not in paths:
                paths.append(path)
        return paths
    lowered = text.lower()
    matches = [item.file_path for item in files if item.display_name.lower() == lowered]
    if len(matches) == 1:
        return matches
    return None
