from __future__ import annotations

from hybrid_search.health import build_health_payload
from hybrid_search.indexes import index_states
from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.settings import get_settings

# Sits inside the ALB probe timeout (AWS default 5s for ip targets), so a down
# Atlas returns 503 in about 2s instead of holding the handler for the full probe.
HEALTH_SERVER_SELECTION_TIMEOUT_MS = 2_000
UNAVAILABLE_PAYLOAD = {"indexes_ready": False, "data_ingested": False, "indexes": []}


async def health_payload() -> dict:
    settings = get_settings()
    client = get_client(settings, server_selection_timeout_ms=HEALTH_SERVER_SELECTION_TIMEOUT_MS)
    try:
        collection = chunks_collection(client, settings)
        states = await index_states(collection, settings)
        has_chunks = bool(await collection.count_documents({}, limit=1))
        return build_health_payload(index_states=states, has_chunks=has_chunks)
    finally:
        client.close()
