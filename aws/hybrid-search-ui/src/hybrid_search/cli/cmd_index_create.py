from __future__ import annotations

import typer

from hybrid_search.cli.index_create_logic import IndexCreateInput, index_create
from hybrid_search.settings import apply_log_level, get_settings

index_app = typer.Typer(help="Atlas search indexes")


@index_app.command("create")
def cmd_index_create():
    settings = get_settings().model_copy(update={"skip_index_creation": False})
    apply_log_level(settings.log_level)
    result = index_create(IndexCreateInput(settings=settings))
    if result.exit_code != 0:
        raise typer.Exit(result.exit_code)
