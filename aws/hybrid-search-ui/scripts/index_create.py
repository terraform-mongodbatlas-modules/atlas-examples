"""One-shot ECS RunTask: hybrid-search index create. Blocks until the task exits 0."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections.abc import Callable
from pathlib import Path
from subprocess import CompletedProcess
from typing import Any

_READY_RE = re.compile(r"(\S+\.\S+)\s+READY\b")

DEFAULT_APP_DIR = Path(__file__).resolve().parent.parent / "app"
INDEX_CMD = ["hybrid-search", "index", "create"]
Run = Callable[..., CompletedProcess[str]]


class IndexCreateError(RuntimeError):
    def __init__(self, message: str, *, exit_code: int = 1) -> None:
        super().__init__(message)
        self.exit_code = exit_code


def index_create(app_dir: Path, *, run: Run = subprocess.run) -> None:
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
    run(
        [
            "aws",
            "ecs",
            "wait",
            "tasks-stopped",
            "--region",
            region,
            "--cluster",
            cluster,
            "--tasks",
            task_arn,
        ],
        check=True,
        capture_output=True,
        text=True,
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
    args = parser.parse_args(argv)
    try:
        index_create(args.app_dir)
    except IndexCreateError as exc:
        print(exc, file=sys.stderr)
        return exc.exit_code
    return 0


if __name__ == "__main__":
    sys.exit(main())
