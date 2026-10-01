"""Live `/health` smoke for a deployed hybrid-search UI.

Resolves the URL from the `lz` Terraform output when it exists, else from
`HYBRID_SEARCH_URL`. `/health` returns 503 until Atlas is reachable, so a 503 is
treated as pending: the script polls until `data_ingested` and `indexes_ready`
are both true or the deadline passes, then exits non-zero with the last payload.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from collections.abc import Callable
from pathlib import Path
from subprocess import CompletedProcess
from typing import Annotated

import httpx
import typer

DEFAULT_LZ_DIR = Path(__file__).resolve().parent.parent / "lz"
DEFAULT_TIMEOUT_S = 600
DEFAULT_INTERVAL_S = 10
URL_OUTPUT_NAME = "https_url"

Run = Callable[..., CompletedProcess[str]]
Sleep = Callable[[float], None]

app = typer.Typer(add_completion=False, help=__doc__)


def resolve_url(lz_dir: Path, *, run: Run = subprocess.run) -> str | None:
    try:
        completed = run(
            ["terraform", f"-chdir={lz_dir}", "output", "-raw", URL_OUTPUT_NAME],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return os.environ.get("HYBRID_SEARCH_URL")
    value = completed.stdout.strip()
    if not value or value == "null":
        return os.environ.get("HYBRID_SEARCH_URL")
    return value


def health_is_ready(payload: dict) -> bool:
    return bool(payload.get("data_ingested")) and bool(payload.get("indexes_ready"))


def poll_health(
    url: str,
    *,
    client: httpx.Client,
    timeout_s: int = DEFAULT_TIMEOUT_S,
    interval_s: int = DEFAULT_INTERVAL_S,
    sleep: Sleep = time.sleep,
) -> tuple[bool, dict | None]:
    endpoint = f"{url.rstrip('/')}/health"
    deadline = time.monotonic() + timeout_s
    last: dict | None = None
    while time.monotonic() < deadline:
        try:
            response = client.get(endpoint)
        except httpx.HTTPError:
            sleep(interval_s)
            continue
        if response.status_code == 200:
            last = response.json()
            if health_is_ready(last):
                return True, last
        sleep(interval_s)
    return False, last


@app.command()
def main(
    url: Annotated[
        str | None,
        typer.Option("--url", help="Override the resolved URL."),
    ] = None,
    lz_dir: Annotated[
        Path,
        typer.Option("--lz-dir", help="Directory holding the lz Terraform state."),
    ] = DEFAULT_LZ_DIR,
    timeout: Annotated[
        int,
        typer.Option("--timeout", help="Seconds to poll before giving up."),
    ] = DEFAULT_TIMEOUT_S,
) -> None:
    resolved = url or resolve_url(lz_dir)
    if not resolved:
        typer.echo("no URL: apply lz, set HYBRID_SEARCH_URL, or pass --url", err=True)
        raise typer.Exit(1)

    typer.echo(f"polling {resolved.rstrip('/')}/health for up to {timeout}s")
    with httpx.Client(timeout=10.0) as client:
        ready, payload = poll_health(resolved, client=client, timeout_s=timeout)
    if ready:
        typer.echo(f"healthy: {json.dumps(payload)}")
        return
    typer.echo(f"timed out waiting for a healthy deployment; last payload: {json.dumps(payload)}")
    raise typer.Exit(1)


if __name__ == "__main__":
    app()
