import logging
import os
import urllib.parse
from datetime import datetime
from typing import TypedDict

from fastapi import FastAPI
from fastapi.requests import Request
from pydantic_settings import BaseSettings
from pymongo import MongoClient
from pymongo.errors import ConnectionFailure
from pymongo.uri_parser import parse_uri

logger = logging.getLogger(__name__)

app = FastAPI()


class PymongoParsedUrl(TypedDict):
    nodelist: list[tuple[str, int]]
    username: str | None
    password: str | None
    database: str | None
    collection: str | None
    options: dict
    fqdn: str | None


class Settings(BaseSettings):
    mongo_url: str = (
        "mongodb://user:pass@localhost:27017?retryWrites=true&w=majority&authSource=admin"
    )
    db_name: str = "test"
    collection_name: str = "test"
    record_id: str = "my-static-record-id"
    use_iam_auth: bool = False

    @property
    def pymongo_parsed_url(self) -> PymongoParsedUrl:
        return parse_uri(self.mongo_url)  # type: ignore


settings = Settings()


def get_mongodb_client() -> MongoClient:
    if settings.use_iam_auth and os.getenv("AWS_EXECUTION_ENV"):
        parsed = settings.pymongo_parsed_url
        hosts = ",".join([f"{host}:{port}" for host, port in parsed["nodelist"]])
        params = {
            "authSource": "$external",
            "authMechanism": "MONGODB-AWS",
            "tls": "true",
        }
        if parsed["options"].get("loadBalanced"):
            params["loadBalanced"] = "true"
        elif replica_set := parsed["options"].get("replicaset"):
            params["replicaSet"] = replica_set

        iam_url = f"mongodb://{hosts}/?{urllib.parse.urlencode(params)}"
        logger.info("Using IAM authentication for MongoDB Atlas")
        return MongoClient(iam_url, serverSelectionTimeoutMS=5000)

    logger.info("Using regular MongoDB authentication")
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
