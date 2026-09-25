from __future__ import annotations

import json
import subprocess
from pathlib import Path
from subprocess import CompletedProcess

import pytest
from index_create import IndexCreateError, index_create, ready_index_names

APP = Path("/tmp/hybrid-search-ui/app")
INDEX_RUN = {
    "aws_region": "us-east-1",
    "cluster": "hybrid-search-ui",
    "service": "hybrid-search-ui",
}
TASK_ARN = "arn:aws:ecs:us-east-1:1:task/hybrid-search-ui/abc123"
TASK_DEF = "arn:aws:ecs:us-east-1:1:task-definition/ui:1"

ACTIVE_SERVICE = {
    "services": [
        {
            "status": "ACTIVE",
            "taskDefinition": TASK_DEF,
            "networkConfiguration": {
                "awsvpcConfiguration": {
                    "subnets": ["subnet-1"],
                    "securityGroups": ["sg-1"],
                }
            },
        }
    ]
}

TASK_DEFINITION = {
    "taskDefinition": {
        "containerDefinitions": [
            {
                "name": "ui",
                "logConfiguration": {"options": {"awslogs-group": "/ecs/hybrid-search-ui"}},
            }
        ]
    }
}


class ScriptedRun:
    def __init__(self, by_kind: dict[str, object]) -> None:
        self.by_kind = by_kind
        self.calls: list[list[str]] = []

    def __call__(self, args, **kwargs):
        del kwargs
        argv = list(args)
        self.calls.append(argv)
        kind = _kind(argv)
        result = self.by_kind[kind]
        # A list is a scripted sequence consumed one per call; the last entry repeats.
        if isinstance(result, list):
            result = result.pop(0) if len(result) > 1 else result[0]
        if isinstance(result, BaseException):
            raise result
        if isinstance(result, CompletedProcess):
            return result
        return CompletedProcess(argv, 0, stdout=json.dumps(result), stderr="")


def _kind(args: list[str]) -> str:
    if args[0] == "terraform":
        return "terraform"
    if "describe-services" in args:
        return "describe-services"
    if "describe-task-definition" in args:
        return "describe-task-definition"
    if "run-task" in args:
        return "run-task"
    if "describe-tasks" in args:
        return "describe-tasks"
    if "get-log-events" in args:
        return "get-log-events"
    if "logs" in args:
        return "logs"
    raise AssertionError(" ".join(args))


def _happy(**overrides: object) -> ScriptedRun:
    by_kind: dict[str, object] = {
        "terraform": INDEX_RUN,
        "describe-services": ACTIVE_SERVICE,
        "describe-task-definition": TASK_DEFINITION,
        "run-task": {"tasks": [{"taskArn": TASK_ARN}]},
        "describe-tasks": {
            "tasks": [{"lastStatus": "STOPPED", "containers": [{"exitCode": 0}]}],
        },
        "logs": CompletedProcess(["aws"], 0, stdout="", stderr=""),
        "get-log-events": {"events": []},
    }
    by_kind.update(overrides)
    return ScriptedRun(by_kind)


def test_exits_when_terraform_output_fails():
    run = _happy(terraform=subprocess.CalledProcessError(1, ["terraform"]))
    with pytest.raises(IndexCreateError, match="apply app first"):
        index_create(APP, run=run)


def test_exits_when_service_is_not_active():
    run = _happy(**{"describe-services": {"services": [{"status": "INACTIVE"}]}})
    with pytest.raises(IndexCreateError, match="apply app first"):
        index_create(APP, run=run)


def test_exits_when_run_task_returns_no_task():
    run = _happy(**{"run-task": {"tasks": []}})
    with pytest.raises(IndexCreateError, match="ecs run-task returned no task"):
        index_create(APP, run=run)


def test_tails_logs_when_container_exits_nonzero():
    run = _happy(
        **{
            "describe-tasks": {
                "tasks": [
                    {
                        "lastStatus": "STOPPED",
                        "containers": [{"exitCode": 2, "reason": "Error"}],
                        "stoppedReason": "Essential container exited",
                    }
                ]
            },
        }
    )
    with pytest.raises(IndexCreateError, match="index create failed \\(exit 2, Error\\)"):
        index_create(APP, run=run)
    assert any(call[:3] == ["aws", "logs", "tail"] for call in run.calls)
    assert any("/ecs/hybrid-search-ui" in call for call in run.calls)


def test_polls_until_task_stops():
    run = _happy(
        **{
            "describe-tasks": [
                {"tasks": [{"lastStatus": "RUNNING"}]},
                {"tasks": [{"lastStatus": "STOPPED", "containers": [{"exitCode": 1}]}]},
            ],
        }
    )
    with pytest.raises(IndexCreateError, match="index create failed \\(exit 1"):
        index_create(APP, run=run, poll_interval_s=0)
    # Three describes: two polls during the wait, then the exit-code read.
    assert sum("describe-tasks" in call for call in run.calls) == 3


def test_timeout_still_reads_exit_code():
    run = _happy(
        **{
            "describe-tasks": [
                {"tasks": [{"lastStatus": "RUNNING"}]},
                {"tasks": [{"lastStatus": "RUNNING", "containers": [{"exitCode": None}]}]},
            ],
        }
    )
    with pytest.raises(IndexCreateError, match="index create failed \\(exit None"):
        index_create(APP, run=run, wait_timeout_s=0, poll_interval_s=0)


def test_ready_index_names_parses_log_lines():
    output = (
        "2026-08-14 chunks.vector_idx READY\n"
        "2026-08-14 chunks.text_idx READY\n"
        "2026-08-14 chunks.vector_idx READY\n"
    )
    assert ready_index_names(output) == ["chunks.vector_idx", "chunks.text_idx"]


def test_returns_after_successful_run_task(capsys):
    log_lines = "2026-08-14 chunks.vector_idx READY\n2026-08-14 chunks.text_idx READY\n"
    run = _happy(logs=CompletedProcess(["aws"], 0, stdout=log_lines, stderr=""))
    index_create(APP, run=run)
    run_task = next(call for call in run.calls if "run-task" in call)
    assert "--overrides" in run_task
    overrides = json.loads(run_task[run_task.index("--overrides") + 1])
    assert overrides["containerOverrides"][0]["command"] == [
        ".venv/bin/hybrid-search",
        "index",
        "create",
    ]
    assert any(call[:3] == ["aws", "logs", "tail"] for call in run.calls)
    captured = capsys.readouterr()
    assert "Started task" in captured.out
    assert "chunks.vector_idx READY" in captured.out
    assert "index create succeeded (2 indexes READY)" in captured.out


def test_streams_log_events_during_wait(capsys):
    run = _happy(
        **{
            "logs": CompletedProcess(["aws"], 0, stdout="", stderr=""),
            "get-log-events": {
                "events": [
                    {"timestamp": 1, "message": "2026-08-14 chunks.vector_idx BUILDING\n"},
                    {"timestamp": 2, "message": "2026-08-14 chunks.vector_idx READY\n"},
                ]
            },
        }
    )
    index_create(APP, run=run)
    assert any(call[:3] == ["aws", "logs", "get-log-events"] for call in run.calls)
    captured = capsys.readouterr()
    assert "chunks.vector_idx BUILDING" in captured.out
    assert "index create succeeded (1 indexes READY)" in captured.out


def test_missing_log_stream_is_tolerated(capsys):
    run = _happy(
        **{
            "get-log-events": subprocess.CompletedProcess(
                ["aws"], 1, stdout="", stderr="ResourceNotFoundException"
            ),
        }
    )
    index_create(APP, run=run)
    captured = capsys.readouterr()
    assert "index create succeeded" in captured.out
