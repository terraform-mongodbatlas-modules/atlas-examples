import logging
from datetime import datetime

from fastapi import FastAPI
from fastapi.requests import Request
from pydantic_settings import BaseSettings
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure

logger = logging.getLogger(__name__)

app = FastAPI()


class Settings(BaseSettings):
    mongo_url: str = (
        "mongodb://user:pass@localhost:27017?retryWrites=true&w=majority&authSource=admin"
    )
    db_name: str = "test"
    collection_name: str = "test"
    record_id: str = "my-static-record-id"


settings = Settings()


def get_mongodb_client() -> MongoClient:
    return MongoClient(settings.mongo_url, serverSelectionTimeoutMS=5000)


ALL_METHODS = ["GET", "PUT", "POST", "DELETE", "OPTIONS", "HEAD", "PATCH", "TRACE"]


@app.api_route("/{path:path}", methods=ALL_METHODS)
def health_check(request: Request, path: str = "") -> dict:
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)-7s %(threadName)-s %(name)-s %(lineno)-s %(message)-s",
        force=True,
    )
    logger.info(f"health check for {request.url}")
    client = get_mongodb_client()
    db_ok = False
    error_msg = ""
    read_record = {}
    timestamp_str = datetime.now().isoformat()
    try:
        # Ping the app DB (readWrite on `test` only); admin.ping fails under that privilege.
        db = client.get_database(settings.db_name)
        db.command("ping")
        db_ok = True
        collection = db.get_collection(settings.collection_name)
        if write_value := request.query_params.get("write"):
            collection.replace_one(
                {"_id": settings.record_id},
                {
                    "id": settings.record_id,
                    "value": write_value,
                    "timestamp": timestamp_str,
                },
                upsert=True,
            )
        read_record = collection.find_one({"id": settings.record_id})
    except ConnectionFailure as e:
        error_msg = f"Server not available: {e!r}"
        logger.warning(error_msg)
    except Exception as e:
        error_msg = f"Unexpected error: {e!r}"
        logger.error(error_msg)
    return {
        "db": db_ok,
        "error": error_msg,
        "timestamp": timestamp_str,
        "read_record": read_record,
    }
