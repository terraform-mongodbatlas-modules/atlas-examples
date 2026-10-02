"""Run the hybrid_search integration tier against a local Atlas deployment.

The process that creates the container also owns the test run, because a justfile
target cannot export an environment into a later `just` call. `atlas-local-lib-py`
starts (or reuses) `mongodb/mongodb-atlas-local:preview`, this script sets
`MONGODB_URI` for the child commands, runs `hybrid-search index-create` so the
indexes are READY, then runs `pytest src/hybrid_search/integration`.

Pass extra arguments through to pytest, for example `just integration-test -k not_ready`.

This script creates the container with `docker run` rather than the library's
`get_or_create`, because that call is a blocking native call that prints nothing,
so a pull or a slow start looks like a freeze and ignores an interrupt. It also
cannot forward `EMBEDDING_PROVIDER_ENDPOINT`.

The container is kept between runs, so the Atlas Search indexes stay READY and a
re-run skips the index build. Pass `--force-new` to remove and re-create it, which
is what a changed `VOYAGE_API_KEY` or `EMBEDDING_PROVIDER_ENDPOINT` needs: mongot
reads both from the container environment, fixed at creation time.

Both `VOYAGE_API_KEY` and `EMBEDDING_PROVIDER_ENDPOINT` are required. Without the
endpoint mongot cannot register the autoEmbed model, so index creation stays
PENDING until the 600s wait times out. The script fails before starting the
container instead. mongot needs the full embeddings path, so a host-only value
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
    GetDeploymentError,
    LocalDeployment,
)

DEPLOYMENT_NAME = "hybrid-search-integration"
TEST_DATABASE = "hybrid_search_integration"
IMAGE_REPOSITORY = "quay.io/mongodb/mongodb-atlas-local"
EMBEDDINGS_PATH = "/v1/embeddings"
HEALTH_TIMEOUT_S = 180
HEALTH_INTERVAL_S = 3
# A cold container start is about 30s locally; a first-time image pull adds more.
HEALTH_ECHO_INTERVAL_S = 15
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


def embedding_endpoint() -> str:
    endpoint = os.environ.get("EMBEDDING_PROVIDER_ENDPOINT", "").rstrip("/")
    if endpoint.endswith(EMBEDDINGS_PATH):
        return endpoint
    return f"{endpoint}{EMBEDDINGS_PATH}"


def require_voyage_env() -> tuple[str, str]:
    """Fail before touching Docker when the embedding configuration is incomplete."""
    missing = [
        name
        for name in ("VOYAGE_API_KEY", "EMBEDDING_PROVIDER_ENDPOINT")
        if not os.environ.get(name)
    ]
    if missing:
        msg = (
            f"missing required environment: {', '.join(missing)}. "
            "Source the Voyage env file first:\n"
            "  set -a; source /Users/espen.albert/code/z/atlas_init/profiles/default/.env-voyage; set +a"
        )
        raise SystemExit(msg)
    return os.environ["VOYAGE_API_KEY"], embedding_endpoint()


def cli_command() -> list[str]:
    script = Path(sys.executable).with_name("hybrid-search")
    if script.exists():
        return [str(script)]
    found = shutil.which("hybrid-search")
    if found:
        return [found]
    msg = "hybrid-search console script not found; run this inside the app environment"
    raise SystemExit(msg)


def _echo(message: str) -> None:
    # Flush so progress streams when stdout is piped, not only on a TTY.
    print(message, flush=True)


def run(command: list[str], *, env: dict[str, str]) -> None:
    _echo(f"+ {' '.join(command)}")
    # Same process group, so a terminal interrupt reaches the child too. A new session
    # would shield the child and leave it running after this script exits.
    completed = subprocess.run(command, cwd=REPO_ROOT, env=env, check=False)
    if completed.returncode != 0:
        raise typer.Exit(completed.returncode)


def _docker(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["docker", *args], capture_output=True, text=True, check=False)


def _container_state() -> str:
    """Return the container's state, or empty when it does not exist."""
    inspected = _docker("inspect", "-f", "{{.State.Status}}", DEPLOYMENT_NAME)
    return inspected.stdout.strip() if inspected.returncode == 0 else ""


def _wait_until_healthy() -> None:
    started = time.monotonic()
    deadline = started + HEALTH_TIMEOUT_S
    next_echo = started + HEALTH_ECHO_INTERVAL_S
    while time.monotonic() < deadline:
        status = _docker("inspect", "-f", "{{.State.Health.Status}}", DEPLOYMENT_NAME)
        if status.stdout.strip() == "healthy":
            _echo(f"container healthy after {int(time.monotonic() - started)}s")
            return
        if time.monotonic() >= next_echo:
            elapsed = int(time.monotonic() - started)
            _echo(f"waiting for {DEPLOYMENT_NAME} to be healthy ({elapsed}s)")
            next_echo = time.monotonic() + HEALTH_ECHO_INTERVAL_S
        time.sleep(HEALTH_INTERVAL_S)
    msg = f"deployment {DEPLOYMENT_NAME} did not become healthy in {HEALTH_TIMEOUT_S}s"
    raise SystemExit(msg)


def _create_container(voyage_api_key: str, endpoint: str) -> None:
    _echo(
        f"starting container {DEPLOYMENT_NAME} from {IMAGE_REPOSITORY}:preview "
        "(a first-time image pull can take a few minutes)"
    )
    created = _docker(
        "run",
        "-d",
        "--name",
        DEPLOYMENT_NAME,
        "-p",
        "127.0.0.1:0:27017",
        "-e",
        f"VOYAGE_API_KEY={voyage_api_key}",
        "-e",
        f"EMBEDDING_PROVIDER_ENDPOINT={endpoint}",
        f"{IMAGE_REPOSITORY}:preview",
    )
    if created.returncode != 0:
        msg = f"docker run failed: {created.stderr.strip()}"
        raise SystemExit(msg)


def start_deployment(*, force_new: bool) -> LocalDeployment:
    voyage_api_key, endpoint = require_voyage_env()
    _echo(f"using EMBEDDING_PROVIDER_ENDPOINT={endpoint}")
    state = _container_state()
    if force_new and state:
        _echo(f"removing {DEPLOYMENT_NAME} (--force-new)")
        _docker("rm", "-f", DEPLOYMENT_NAME)
        state = ""
    if not state:
        _create_container(voyage_api_key, endpoint)
    elif state != "running":
        _echo(f"starting existing container {DEPLOYMENT_NAME} (was {state})")
        started = _docker("start", DEPLOYMENT_NAME)
        if started.returncode != 0:
            msg = f"docker start failed: {started.stderr.strip()}"
            raise SystemExit(msg)
    else:
        # Reuse keeps the indexes READY, so a re-run skips the index build.
        _echo(f"reusing running container {DEPLOYMENT_NAME} (--force-new to re-create)")
    _wait_until_healthy()
    return LocalDeployment.get(DEPLOYMENT_NAME)


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
    force_new: Annotated[
        bool,
        typer.Option(
            "--force-new",
            help="Remove and re-create the container instead of reusing it.",
        ),
    ] = False,
    clean: Annotated[
        bool,
        typer.Option(
            "--clean",
            help="Drop the test database before pytest, forcing a full re-ingest.",
        ),
    ] = False,
) -> None:
    if teardown_deployment:
        teardown()
        return

    deployment = start_deployment(force_new=force_new)
    uri = deployment.connection_string()
    env = child_env(uri)
    if clean:
        # pytest drops the database at the end of a run, so this is only needed after a
        # failure or a --teardown of the container.
        _echo(f"dropping {TEST_DATABASE} (--clean)")
        dropped = _docker(
            "exec",
            DEPLOYMENT_NAME,
            "mongosh",
            "--quiet",
            "--eval",
            f"db.getSiblingDB('{TEST_DATABASE}').dropDatabase()",
        )
        if dropped.returncode != 0:
            msg = f"failed to drop {TEST_DATABASE}: {dropped.stderr.strip()}"
            raise SystemExit(msg)
    cli = cli_command()
    run([*cli, "index-create"], env=env)
    run(
        [sys.executable, "-m", "pytest", "src/hybrid_search/integration", *ctx.args],
        env=env,
    )


if __name__ == "__main__":
    app()
