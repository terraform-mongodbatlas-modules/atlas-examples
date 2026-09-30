from __future__ import annotations

import asyncio
import contextlib
import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from pathlib import Path

from chainlit.utils import mount_chainlit
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from hybrid_search.settings import get_settings
from hybrid_search.startup import run_startup_task
from hybrid_search.ui.health_endpoint import UNAVAILABLE_PAYLOAD, health_payload

logger = logging.getLogger(__name__)

# Resolve the Chainlit entrypoint from this file so the app runs from any working
# directory (the workspace root under pytest, /app in the image).
_CHAINLIT_TARGET = str(Path(__file__).parent / "ui" / "chat.py")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    # create_task returns immediately, so uvicorn serves /health and the UI
    # while the task connects and builds indexes.
    task = asyncio.create_task(run_startup_task(get_settings()))
    try:
        yield
    finally:
        task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await task


app = FastAPI(lifespan=lifespan)


@app.get("/health", response_model=None)
async def health() -> dict | JSONResponse:
    try:
        return await health_payload()
    except Exception as exc:  # any Mongo failure must become a 503
        logger.warning(f"Health check failed: {exc}")
        return JSONResponse(UNAVAILABLE_PAYLOAD, status_code=503)


# Registered after /health so the parent route wins over the mounted catch-all.
mount_chainlit(app=app, target=_CHAINLIT_TARGET, path="/")
