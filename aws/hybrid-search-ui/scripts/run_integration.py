"""Run the hybrid_search integration tier against a local Atlas deployment.

The process that creates the container also owns the test run, because a justfile
target cannot export an environment into a later `just` call. `atlas-local-lib-py`
starts (or reuses) `mongodb/mongodb-atlas-local:preview`, this script sets
`MONGODB_URI` for the child commands, runs `hybrid-search index-create` so the
indexes are READY, then runs `pytest src/hybrid_search/integration`.

Pass extra arguments through to pytest, for example `just integration-test -k not_ready`.

`atlas-local-lib-py` 1.0.0 forwards only `VOYAGE_API_KEY` and the `MONGODB_*`
variables, so when `EMBEDDING_PROVIDER_ENDPOINT` is set this script creates the
container with `docker run` instead, then hands it to the library for the
connection string. mongot needs the full embeddings path, so a host-only value
such as `https://ai-stage.mongodb.com` gets `/v1/embeddings` appended.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Annotated

import typer
from atlas_local import (
    DeleteDeploymentError,
    DockerConnectionError,
    GetDeploymentError,
    LocalDeployment,
)

DEPLOYMENT_NAME = "hybrid-search-integration"
TEST_DATABASE = "hybrid_search_integration"
IMAGE_REPOSITORY = "quay.io/mongodb/mongodb-atlas-local"
EMBEDDINGS_PATH = "/v1/embeddings"
HEALTH_TIMEOUT_S = 180
HEALTH_INTERVAL_S = 3
REPO_ROOT = Path(__file__).resolve().parent.parent

app = typer.Typer(
    add_completion=False,
    context_settings={"allow_extra_args": True, "ignore_unknown_options": True},
    help=__doc__,
)


def child_env(uri: str) -> dict[str, str]:
    env = os.environ.copy()
    env.update(
        {
            "MONGODB_URI": uri,
            "MONGODB_TLS": "false",
            "MONGODB_DATABASE": TEST_DATABASE,
            "ENABLE_LLM": "false",
            "SKIP_INGEST": "false",
        }
    )
    return env


def embedding_endpoint() -> str | None:
    endpoint = os.environ.get("EMBEDDING_PROVIDER_ENDPOINT", "").rstrip("/")
    if not endpoint:
        return None
    if endpoint.endswith(EMBEDDINGS_PATH):
        return endpoint
    return f"{endpoint}{EMBEDDINGS_PATH}"


def cli_command() -> list[str]:
    script = Path(sys.executable).with_name("hybrid-search")
    if script.exists():
        return [str(script)]
    found = shutil.which("hybrid-search")
    if found:
        return [found]
    msg = "hybrid-search console script not found; run this inside the app environment"
    raise SystemExit(msg)


def run(command: list[str], *, env: dict[str, str]) -> None:
    typer.echo(f"+ {' '.join(command)}")
    completed = subprocess.run(command, cwd=REPO_ROOT, env=env, check=False)
    if completed.returncode != 0:
        raise typer.Exit(completed.returncode)


def _docker(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["docker", *args], capture_output=True, text=True, check=False)


def _wait_until_healthy() -> None:
    deadline = time.monotonic() + HEALTH_TIMEOUT_S
    while time.monotonic() < deadline:
        status = _docker("inspect", "-f", "{{.State.Health.Status}}", DEPLOYMENT_NAME)
        if status.stdout.strip() == "healthy":
            return
        time.sleep(HEALTH_INTERVAL_S)
    msg = f"deployment {DEPLOYMENT_NAME} did not become healthy in {HEALTH_TIMEOUT_S}s"
    raise SystemExit(msg)


def _start_with_endpoint(endpoint: str) -> LocalDeployment:
    # The library cannot forward the endpoint, so create the container directly.
    _docker("rm", "-f", DEPLOYMENT_NAME)
    created = _docker(
        "run",
        "-d",
        "--name",
        DEPLOYMENT_NAME,
        "-p",
        "127.0.0.1:0:27017",
        "-e",
        "VOYAGE_API_KEY",
        "-e",
        f"EMBEDDING_PROVIDER_ENDPOINT={endpoint}",
        f"{IMAGE_REPOSITORY}:preview",
    )
    if created.returncode != 0:
        msg = f"docker run failed: {created.stderr.strip()}"
        raise SystemExit(msg)
    _wait_until_healthy()
    return LocalDeployment.get(DEPLOYMENT_NAME)


def start_deployment() -> LocalDeployment:
    endpoint = embedding_endpoint()
    if endpoint:
        typer.echo(f"using EMBEDDING_PROVIDER_ENDPOINT={endpoint}")
        return _start_with_endpoint(endpoint)
    try:
        return LocalDeployment.get_or_create(
            name=DEPLOYMENT_NAME,
            image_tag="preview",
            voyage_api_key=os.environ.get("VOYAGE_API_KEY"),
            wait_until_healthy=True,
        )
    except DockerConnectionError as exc:
        msg = f"Docker is not running; start it and retry. {exc}"
        raise SystemExit(msg) from exc


def teardown() -> None:
    try:
        LocalDeployment.delete_deployment(DEPLOYMENT_NAME)
    except (GetDeploymentError, DeleteDeploymentError) as exc:
        # Already gone is the desired end state, so this is success, not an error.
        typer.echo(f"no running deployment named {DEPLOYMENT_NAME} ({exc})")
        return
    typer.echo(f"deleted {DEPLOYMENT_NAME}")


@app.command()
def main(
    ctx: typer.Context,
    teardown_deployment: Annotated[
        bool,
        typer.Option("--teardown", help="Delete the local deployment instead of running the tier."),
    ] = False,
) -> None:
    if teardown_deployment:
        teardown()
        return

    if not os.environ.get("VOYAGE_API_KEY"):
        typer.echo(
            "warning: VOYAGE_API_KEY is unset; autoEmbed index creation and vector "
            "search will fail. Set it before running the integration tier.",
            err=True,
        )

    deployment = start_deployment()
    uri = deployment.connection_string()
    env = child_env(uri)
    cli = cli_command()
    run([*cli, "index-create"], env=env)
    run(
        [sys.executable, "-m", "pytest", "src/hybrid_search/integration", *ctx.args],
        env=env,
    )


if __name__ == "__main__":
    app()
