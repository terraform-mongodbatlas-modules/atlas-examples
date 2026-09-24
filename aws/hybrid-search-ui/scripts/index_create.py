"""One-shot ECS RunTask: hybrid-search index create. Blocks until the task exits 0."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path
from subprocess import CompletedProcess
from typing import Any

_READY_RE = re.compile(r"(\S+\.\S+)\s+READY\b")

DEFAULT_APP_DIR = Path(__file__).resolve().parent.parent / "app"
INDEX_CMD = [".venv/bin/hybrid-search", "index", "create"]
# The in-container wait (wait_chunks_indexes_ready) defaults to 600s before the app
# exits 1. Poll past that so the app's own exit code and logs are always read. Do not
# use `aws ecs wait tasks-stopped`: its botocore ceiling is fixed at 600s (6s x 100)
# and it would race the app to the same deadline.
DEFAULT_WAIT_TIMEOUT_S = 900.0
DEFAULT_POLL_INTERVAL_S = 6.0
Run = Callable[..., CompletedProcess[str]]


class IndexCreateError(RuntimeError):
    def __init__(self, message: str, *, exit_code: int = 1) -> None:
        super().__init__(message)
        self.exit_code = exit_code


def index_create(
    app_dir: Path,
    *,
    run: Run = subprocess.run,
    wait_timeout_s: float = DEFAULT_WAIT_TIMEOUT_S,
    poll_interval_s: float = DEFAULT_POLL_INTERVAL_S,
) -> None:
    loc = _terraform_index_run(app_dir, run)
    region, cluster, service = loc["aws_region"], loc["cluster"], loc["service"]
    svc = _aws_json(
        run,
        [
            "ecs",
            "describe-services",
            "--region",
            region,
            "--cluster",
            cluster,
            "--services",
            service,
        ],
    )
    services = svc.get("services") or []
    if not services or services[0].get("status") != "ACTIVE":
        raise IndexCreateError("apply app first")

    first = services[0]
    task_def = first["taskDefinition"]
    net = first["networkConfiguration"]["awsvpcConfiguration"]
    subnet = net["subnets"][0]
    sg = net["securityGroups"][0]
    td = _aws_json(
        run,
        ["ecs", "describe-task-definition", "--region", region, "--task-definition", task_def],
    )
    container_def = td["taskDefinition"]["containerDefinitions"][0]
    log_opts = container_def.get("logConfiguration", {}).get("options", {})
    container_name = container_def["name"]
    log_group = log_opts.get("awslogs-group", "")
    log_stream_prefix = log_opts.get("awslogs-stream-prefix", "ecs")
    run_payload = _aws_json(
        run,
        [
            "ecs",
            "run-task",
            "--region",
            region,
            "--cluster",
            cluster,
            "--task-definition",
            task_def,
            "--launch-type",
            "FARGATE",
            "--network-configuration",
            f"awsvpcConfiguration={{subnets=[{subnet}],securityGroups=[{sg}],assignPublicIp=DISABLED}}",
            "--overrides",
            json.dumps({"containerOverrides": [{"name": container_name, "command": INDEX_CMD}]}),
        ],
    )
    tasks = run_payload.get("tasks") or []
    task_arn = tasks[0].get("taskArn", "") if tasks else ""
    if not task_arn:
        print(json.dumps(run_payload), file=sys.stderr)
        raise IndexCreateError("ecs run-task returned no task")

    print(f"Started task {task_arn}")
    print("Waiting for task to stop...")
    _wait_for_task_stopped(
        run,
        region=region,
        cluster=cluster,
        task_arn=task_arn,
        timeout_s=wait_timeout_s,
        poll_interval_s=poll_interval_s,
    )
    desc = _aws_json(
        run,
        ["ecs", "describe-tasks", "--region", region, "--cluster", cluster, "--tasks", task_arn],
    )
    task = desc["tasks"][0]
    container_status = task["containers"][0]
    exit_code = container_status.get("exitCode")
    log_output = _tail_task_logs(
        run,
        log_group=log_group,
        region=region,
        task_arn=task_arn,
        container_name=container_name,
        log_stream_prefix=log_stream_prefix,
    )
    if exit_code != 0:
        detail = container_status.get("reason") or task.get("stoppedReason") or "unknown"
        raise IndexCreateError(f"index create failed (exit {exit_code}, {detail})")
    ready = ready_index_names(log_output)
    if ready:
        print(f"index create succeeded ({len(ready)} indexes READY)")
    else:
        print(
            "index create succeeded (no READY lines in task logs; check CloudWatch if search fails)"
        )


def ready_index_names(log_output: str) -> list[str]:
    """Return collection.index names that reached READY in index create logs."""
    seen: set[str] = set()
    ready: list[str] = []
    for line in log_output.splitlines():
        match = _READY_RE.search(line)
        if match and match.group(1) not in seen:
            seen.add(match.group(1))
            ready.append(match.group(1))
    return ready


def _wait_for_task_stopped(
    run: Run,
    *,
    region: str,
    cluster: str,
    task_arn: str,
    timeout_s: float,
    poll_interval_s: float,
) -> None:
    """Poll describe-tasks until the task stops or timeout_s elapses.

    A timeout is not fatal here: the caller reads the exit code and logs to report
    the real outcome. This replaces `aws ecs wait tasks-stopped`, whose fixed 600s
    ceiling made the wait race the app's own 600s index wait.
    """
    deadline = time.monotonic() + timeout_s
    while True:
        desc = _aws_json(
            run,
            [
                "ecs",
                "describe-tasks",
                "--region",
                region,
                "--cluster",
                cluster,
                "--tasks",
                task_arn,
            ],
        )
        tasks = desc.get("tasks") or []
        if not tasks or tasks[0].get("lastStatus") == "STOPPED":
            return
        if time.monotonic() >= deadline:
            print(
                f"timed out after {timeout_s:.0f}s waiting for task to stop; reading exit code anyway",
                file=sys.stderr,
            )
            return
        time.sleep(poll_interval_s)


def _ecs_log_stream_name(*, log_stream_prefix: str, container_name: str, task_arn: str) -> str:
    task_id = task_arn.rsplit("/", 1)[-1]
    return f"{log_stream_prefix}/{container_name}/{task_id}"


def _tail_task_logs(
    run: Run,
    *,
    log_group: str,
    region: str,
    task_arn: str,
    container_name: str,
    log_stream_prefix: str,
) -> str:
    if not log_group:
        return ""
    log_stream = _ecs_log_stream_name(
        log_stream_prefix=log_stream_prefix,
        container_name=container_name,
        task_arn=task_arn,
    )
    completed = run(
        [
            "aws",
            "logs",
            "tail",
            log_group,
            "--region",
            region,
            "--log-stream-names",
            log_stream,
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    output = completed.stdout or ""
    if output:
        end = "" if output.endswith("\n") else "\n"
        print(output, end=end)
    return output


def _terraform_index_run(app_dir: Path, run: Run) -> dict[str, Any]:
    try:
        completed = run(
            ["terraform", f"-chdir={app_dir}", "output", "-json", "index_run"],
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(completed.stdout)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        raise IndexCreateError("apply app first") from exc


def _aws_json(run: Run, args: list[str]) -> dict[str, Any]:
    completed = run(["aws", *args], check=True, capture_output=True, text=True)
    return json.loads(completed.stdout)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Run hybrid-search index create as a one-shot ECS task."
    )
    parser.add_argument(
        "app_dir",
        nargs="?",
        type=Path,
        default=DEFAULT_APP_DIR,
        help="App Terraform directory (default: ../app).",
    )
    parser.add_argument(
        "--wait-timeout",
        type=float,
        default=DEFAULT_WAIT_TIMEOUT_S,
        help=(
            "Seconds to poll describe-tasks for the one-shot task to stop "
            f"(default: {DEFAULT_WAIT_TIMEOUT_S:.0f}; must exceed the in-container index wait)."
        ),
    )
    args = parser.parse_args(argv)
    try:
        index_create(args.app_dir, wait_timeout_s=args.wait_timeout)
    except IndexCreateError as exc:
        print(exc, file=sys.stderr)
        return exc.exit_code
    return 0


if __name__ == "__main__":
    sys.exit(main())
