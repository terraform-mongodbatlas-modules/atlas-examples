import typer

from hybrid_search.cli.cmd_index_create import index_app
from hybrid_search.cli.cmd_ingest import ingest_app

app = typer.Typer()
app.add_typer(index_app, name="index")
app.add_typer(ingest_app, name="ingest")


def main():
    app()
