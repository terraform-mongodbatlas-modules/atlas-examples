from __future__ import annotations

import asyncio
import logging

from pydantic import BaseModel, Field

from hybrid_search.indexes import (
    create_chunks_indexes_if_missing,
    format_index_ready_line,
    wait_chunks_indexes_ready,
)
from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.settings import HybridSearchSettings

logger = logging.getLogger(__name__)


class IndexCreateInput(BaseModel):
    settings: HybridSearchSettings


class IndexCreateResult(BaseModel):
    exit_code: int = 0
    ready_lines: list[str] = Field(default_factory=list)


def index_create(input: IndexCreateInput) -> IndexCreateResult:
    return asyncio.run(_index_create_async(input))


async def _index_create_async(input: IndexCreateInput) -> IndexCreateResult:
    settings = input.settings
    client = get_client(settings)
    try:
        collection = chunks_collection(client, settings)
        await create_chunks_indexes_if_missing(collection, settings)
        ready = await wait_chunks_indexes_ready(collection, settings)
        lines = [format_index_ready_line(coll, name) for coll, name, _ in ready]
        for line in lines:
            logger.info(line)
        return IndexCreateResult(ready_lines=lines)
    except (TimeoutError, RuntimeError):
        return IndexCreateResult(exit_code=1)
    finally:
        client.close()
