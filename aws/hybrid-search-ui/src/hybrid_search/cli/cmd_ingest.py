from __future__ import annotations

from pathlib import Path

import typer

from hybrid_search.cli.ingest_logic import IngestInput, ingest
from hybrid_search.settings import apply_log_level, get_settings

ingest_app = typer.Typer(help="Ingest documents into the chunks collection")


@ingest_app.command("run")
def cmd_ingest(
    dirs: list[Path] = typer.Option(
        [],
        "--dir",
        help="Directory to scan; repeat for more. Defaults to DOCUMENT_DIRS.",
    ),
    skip_ingest: bool | None = typer.Option(
        None,
        "--skip-ingest/--no-skip-ingest",
        help="Skip ingest. Overrides SKIP_INGEST.",
    ),
    force: bool = typer.Option(
        False,
        "--force",
        help="Re-ingest even when the content hash is unchanged.",
    ),
):
    settings = get_settings()
    if skip_ingest is not None:
        settings = settings.model_copy(update={"skip_ingest": skip_ingest})
    apply_log_level(settings.log_level)
    effective_dirs = dirs or settings.document_dirs
    result = ingest(IngestInput(settings=settings, dirs=effective_dirs, force=force))
    if result.exit_code != 0:
        raise typer.Exit(result.exit_code)
