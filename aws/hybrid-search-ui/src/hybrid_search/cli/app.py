import typer

from hybrid_search.cli.cmd_index_create import cmd_index_create
from hybrid_search.cli.cmd_ingest import cmd_ingest
from hybrid_search.cli.cmd_query import cmd_query

app = typer.Typer()
# Flat commands keep the `hybrid-search <command> --option ...` shape; a sub-typer
# would force `hybrid-search <group> <command>` for every entry point.
app.command(name="index-create", help="Atlas search indexes")(cmd_index_create)
app.command(name="ingest", help="Ingest documents into the chunks collection")(cmd_ingest)
app.command(name="query")(cmd_query)


def main():
    app()
