from __future__ import annotations

import json
import logging

import typer

from hybrid_search.cli.query_logic import QueryInput, run_query
from hybrid_search.search_modes import SearchModes
from hybrid_search.settings import apply_log_level, get_settings

logger = logging.getLogger(__name__)


def modes_for(mode: str, *, no_llm: bool) -> SearchModes:
    match mode:
        case "keyword":
            return SearchModes(keyword=True, vector=False, llm=not no_llm)
        case "vector":
            return SearchModes(keyword=False, vector=True, llm=not no_llm)
        case "rank_fusion":
            return SearchModes(keyword=True, vector=True, llm=not no_llm)
        case _:
            msg = f"unknown mode: {mode}"
            raise typer.BadParameter(msg)


def cmd_query(
    query: str = typer.Option(..., "--query", help="Query text."),
    mode: str = typer.Option(
        "rank_fusion",
        "--mode",
        help="Retrieval mode: keyword, vector, or rank_fusion.",
    ),
    no_llm: bool = typer.Option(
        False,
        "--no-llm",
        help="Skip answer generation and return retrieved references only.",
    ),
):
    settings = get_settings()
    apply_log_level(settings.log_level)
    result = run_query(
        QueryInput(settings=settings, query=query, modes=modes_for(mode, no_llm=no_llm))
    )
    if result.exit_code != 0:
        logger.error(result.error)
        raise typer.Exit(result.exit_code)
    typer.echo(
        json.dumps(
            {"answer": result.answer, "source_files": result.source_files},
            indent=2,
        )
    )
