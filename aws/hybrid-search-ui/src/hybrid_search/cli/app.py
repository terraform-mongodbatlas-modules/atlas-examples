import typer

from hybrid_search.cli.cmd_index_create import index_app
from hybrid_search.cli.cmd_ingest import ingest_app
from hybrid_search.cli.cmd_query import cmd_query

app = typer.Typer()
app.add_typer(index_app, name="index")
app.add_typer(ingest_app, name="ingest")
# A direct command keeps the flat `hybrid-search query --query ...` shape; a sub-typer
# would force `hybrid-search query <command>`.
app.command(name="query")(cmd_query)


def main():
    app()
