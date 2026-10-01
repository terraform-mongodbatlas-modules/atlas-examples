from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable

from motor.motor_asyncio import AsyncIOMotorClient
from pymongo.errors import PyMongoError

from hybrid_search.cli.ingest_logic import INGEST_ERRORS, ingest_dirs
from hybrid_search.indexes import create_chunks_indexes_if_missing, wait_chunks_indexes_ready
from hybrid_search.mongo import chunks_collection, get_client, ingest_state_collection
from hybrid_search.settings import HybridSearchSettings

logger = logging.getLogger(__name__)

# Short enough that a failed ping is fast; the retry loop owns the total wait.
_CONNECT_TIMEOUT_MS = 5000

Sleep = Callable[[float], Awaitable[None]]


async def connect_with_retry(
    settings: HybridSearchSettings,
    *,
    base_delay_s: float = 1.0,
    max_delay_s: float = 30.0,
    max_attempts: int | None = None,
    sleep: Sleep = asyncio.sleep,
) -> AsyncIOMotorClient:
    attempt = 0
    while max_attempts is None or attempt < max_attempts:
        client = get_client(settings, server_selection_timeout_ms=_CONNECT_TIMEOUT_MS)
        try:
            await client.admin.command("ping")
            return client
        except PyMongoError as exc:
            logger.warning(f"Mongo connect attempt {attempt + 1} failed: {exc}")
            client.close()
            delay = min(max_delay_s, base_delay_s * 2**attempt)
            attempt += 1
            await sleep(delay)
    msg = f"could not connect to Mongo after {max_attempts} attempts"
    raise RuntimeError(msg)


async def run_startup_task(settings: HybridSearchSettings) -> None:
    client = await connect_with_retry(settings)
    try:
        collection = chunks_collection(client, settings)
        state_collection = ingest_state_collection(client, settings)
        await create_chunks_indexes_if_missing(collection, settings)
        await wait_chunks_indexes_ready(collection, settings)
        await ingest_dirs(
            settings,
            collection,
            state_collection,
            settings.document_dirs,
        )
    except INGEST_ERRORS as exc:
        # A background task that raises is invisible and must not take the
        # container down. CancelledError is the one exception that propagates.
        logger.error(f"startup task failed: {exc}")
        return
    finally:
        client.close()
