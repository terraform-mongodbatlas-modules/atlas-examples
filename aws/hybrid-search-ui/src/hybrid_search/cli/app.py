import typer

from hybrid_search.cli.cmd_index_create import index_app

app = typer.Typer()
app.add_typer(index_app, name="index")


def main():
    app()
