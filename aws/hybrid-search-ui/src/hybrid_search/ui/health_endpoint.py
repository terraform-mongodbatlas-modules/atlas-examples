from __future__ import annotations

import logging

from chainlit.server import app
from fastapi.responses import JSONResponse

from hybrid_search.health import build_health_payload
from hybrid_search.indexes import index_states
from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.settings import get_settings

logger = logging.getLogger(__name__)

# Sits inside the ALB probe timeout (AWS default 5s for ip targets), so a down
# Atlas returns 503 in about 2s instead of holding the handler for the full probe.
HEALTH_SERVER_SELECTION_TIMEOUT_MS = 2_000
_UNAVAILABLE_PAYLOAD = {"indexes_ready": False, "data_ingested": False, "indexes": []}


async def _health_payload() -> dict:
    settings = get_settings()
    client = get_client(settings, server_selection_timeout_ms=HEALTH_SERVER_SELECTION_TIMEOUT_MS)
    try:
        collection = chunks_collection(client, settings)
        states = await index_states(collection, settings)
        has_chunks = bool(await collection.count_documents({}, limit=1))
        return build_health_payload(index_states=states, has_chunks=has_chunks)
    finally:
        client.close()


class HealthEndpointMiddleware:
    """Raw ASGI middleware: answer GET /health, pass every other request through.

    Raw ASGI (not BaseHTTPMiddleware) so the handler runs on the request's event
    loop without a task group. BaseHTTPMiddleware crashes under the Chainlit CLI
    event loop in this environment (starlette 1.6.0 + anyio), which would also
    take down the `/` UI route.
    """

    def __init__(self, asgi_app):
        self.asgi_app = asgi_app

    async def __call__(self, scope, receive, send) -> None:
        is_health = (
            scope["type"] == "http" and scope["method"] == "GET" and scope["path"] == "/health"
        )
        if not is_health:
            await self.asgi_app(scope, receive, send)
            return
        try:
            payload = await _health_payload()
            status_code = 200
        except Exception as exc:  # noqa: BLE001  any Mongo failure must become a 503
            logger.warning("Health check failed: %s", exc)
            payload = _UNAVAILABLE_PAYLOAD
            status_code = 503
        response = JSONResponse(payload, status_code=status_code)
        await response(scope, receive, send)


def register_health_endpoint() -> None:
    app.add_middleware(HealthEndpointMiddleware)
