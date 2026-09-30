from __future__ import annotations

import asyncio
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock

import pytest
from pydantic import SecretStr
from pymongo.errors import ServerSelectionTimeoutError

import hybrid_search.app as app_module
import hybrid_search.startup as startup_module
from hybrid_search.settings import HybridSearchSettings


def _settings(**overrides: object) -> HybridSearchSettings:
    base: dict[str, object] = {"mongodb_uri": SecretStr("mongodb://localhost")}
    base.update(overrides)
    return HybridSearchSettings(**base)


def _fake_client(ping: AsyncMock) -> MagicMock:
    client = MagicMock()
    client.close = MagicMock()
    client.admin.command = ping
    return client


@pytest.mark.asyncio
async def test_connect_with_retry_retries_until_success(monkeypatch):
    ping = AsyncMock(
        side_effect=[ServerSelectionTimeoutError("no"), ServerSelectionTimeoutError("no"), None]
    )
    clients = [_fake_client(ping) for _ in range(3)]
    monkeypatch.setattr(startup_module, "get_client", MagicMock(side_effect=clients))
    sleep = AsyncMock()

    client = await startup_module.connect_with_retry(_settings(), sleep=sleep)

    assert client is clients[2]
    assert sleep.await_count == 2


@pytest.mark.asyncio
async def test_connect_with_retry_retries_forever(monkeypatch):
    ping = AsyncMock(side_effect=ServerSelectionTimeoutError("no"))
    monkeypatch.setattr(
        startup_module, "get_client", MagicMock(side_effect=lambda *_a, **_k: _fake_client(ping))
    )
    calls = {"n": 0}

    async def stop_after_five(_delay: float) -> None:
        calls["n"] += 1
        if calls["n"] == 5:
            raise RuntimeError("stop")

    with pytest.raises(RuntimeError, match="stop"):
        await startup_module.connect_with_retry(
            _settings(), max_attempts=None, sleep=stop_after_five
        )

    assert calls["n"] == 5  # kept retrying past any ceiling, not a max-attempt stop


@pytest.mark.asyncio
async def test_run_startup_task_creates_then_waits_then_ingests(monkeypatch):
    settings = _settings(document_dirs=[Path("/data")], seed_dir=Path("seed"))
    client = _fake_client(AsyncMock())
    monkeypatch.setattr(startup_module, "connect_with_retry", AsyncMock(return_value=client))
    collection = MagicMock()
    state_collection = MagicMock()
    monkeypatch.setattr(startup_module, "chunks_collection", lambda _c, _s: collection)
    monkeypatch.setattr(startup_module, "ingest_state_collection", lambda _c, _s: state_collection)
    order: list[str] = []
    monkeypatch.setattr(
        startup_module,
        "create_chunks_indexes_if_missing",
        AsyncMock(side_effect=lambda *_a, **_k: order.append("create")),
    )
    monkeypatch.setattr(
        startup_module,
        "wait_chunks_indexes_ready",
        AsyncMock(side_effect=lambda *_a, **_k: order.append("wait")),
    )
    ingest_dirs = AsyncMock(side_effect=lambda *_a, **_k: order.append("ingest"))
    monkeypatch.setattr(startup_module, "ingest_dirs", ingest_dirs)

    await startup_module.run_startup_task(settings)

    assert order == ["create", "wait", "ingest"]
    assert ingest_dirs.await_args.args[3] == [Path("/data"), Path("seed")]
    client.close.assert_called_once()


@pytest.mark.asyncio
async def test_run_startup_task_logs_and_returns_on_ingest_error(monkeypatch, caplog):
    client = _fake_client(AsyncMock())
    monkeypatch.setattr(startup_module, "connect_with_retry", AsyncMock(return_value=client))
    monkeypatch.setattr(startup_module, "chunks_collection", lambda _c, _s: MagicMock())
    monkeypatch.setattr(startup_module, "ingest_state_collection", lambda _c, _s: MagicMock())
    monkeypatch.setattr(startup_module, "create_chunks_indexes_if_missing", AsyncMock())
    monkeypatch.setattr(startup_module, "wait_chunks_indexes_ready", AsyncMock())
    monkeypatch.setattr(startup_module, "ingest_dirs", AsyncMock(side_effect=RuntimeError("boom")))

    await startup_module.run_startup_task(_settings())

    assert "startup task failed" in caplog.text
    client.close.assert_called_once()


@pytest.mark.asyncio
async def test_run_startup_task_is_cancellable_while_retrying(monkeypatch):
    ping = AsyncMock(side_effect=ServerSelectionTimeoutError("no"))
    monkeypatch.setattr(
        startup_module, "get_client", MagicMock(side_effect=lambda *_a, **_k: _fake_client(ping))
    )
    never = asyncio.Event()

    async def blocking_sleep(_delay: float) -> None:
        await never.wait()

    task = asyncio.create_task(startup_module.connect_with_retry(_settings(), sleep=blocking_sleep))
    await asyncio.sleep(0.05)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert task.done()


@pytest.mark.asyncio
async def test_lifespan_starts_and_cancels_the_task(monkeypatch):
    settings = _settings()
    started = asyncio.Event()
    cancelled = asyncio.Event()
    never = asyncio.Event()

    async def fake_run(_settings):
        started.set()
        try:
            await never.wait()
        except asyncio.CancelledError:
            cancelled.set()
            raise

    monkeypatch.setattr(app_module, "run_startup_task", fake_run)
    monkeypatch.setattr(app_module, "get_settings", lambda: settings)

    async with app_module.lifespan(app_module.app):
        await asyncio.wait_for(started.wait(), timeout=1)

    assert cancelled.is_set()
