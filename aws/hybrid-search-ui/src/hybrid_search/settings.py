from __future__ import annotations

import logging
import sys
from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

LlmProvider = Literal["anthropic", "bedrock", "openai", "gemini", "grove"]
LogLevel = Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

# Atlas Automated Embedding truncates text past the model context window silently, with
# no error at index time. voyage-4-lite and the other supported models share this window.
# https://www.mongodb.com/docs/vector-search/crud-embeddings/automated-embedding/models
AUTOEMBED_CONTEXT_TOKENS = 32_000
# Chunk-size envelope from the Atlas Search Playground chunking UI.
# https://www.mongodb.com/docs/vector-search/query/vector-search-playground/
MIN_CHUNK_MAX_TOKENS = 40
MAX_CHUNK_MAX_TOKENS = 1500


class HybridSearchSettings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    mongodb_uri: SecretStr
    mongodb_database: str = "hybrid_search"
    autoembed_model: str = "voyage-4-lite"
    # 512 tokens matches the Voyage auto-chunking default.
    # https://www.mongodb.com/docs/api/doc/atlas-embedding-and-reranking-api/voyage-context-4/operation/operation-createcontextualizedembedding
    chunk_max_tokens: int = 512
    top_k: int = 20
    vector_index_name: str = "autoembed_idx"
    text_index_name: str = "text_idx"
    chunks_collection: str = "chunks"
    vector_weight: float = 0.6
    text_weight: float = 0.4
    enable_llm: bool = True
    llm_provider: LlmProvider = "anthropic"
    anthropic_api_key: SecretStr | None = None
    anthropic_model: str = "claude-sonnet-4-20250514"
    bedrock_model: str = "amazon.nova-lite-v1:0"
    openai_api_key: SecretStr | None = None
    openai_model: str = "gpt-4o"
    openai_base_url: str = "https://api.openai.com/v1"
    gemini_api_key: SecretStr | None = None
    gemini_model: str = "gemini-2.0-flash"
    grove_api_key: SecretStr | None = None
    grove_model: str = "gpt-4o"
    grove_base_url: str | None = None
    skip_index_creation: bool = False
    log_level: LogLevel = "INFO"
    demo_queries_path: Path = Path("demo_queries.yaml")

    @field_validator("log_level", mode="before")
    @classmethod
    def normalize_log_level(cls, value: object) -> object:
        match value:
            case str():
                return value.upper()
            case _:
                return value

    @field_validator("chunk_max_tokens")
    @classmethod
    def validate_chunk_max_tokens(cls, value: int) -> int:
        if not MIN_CHUNK_MAX_TOKENS <= value <= MAX_CHUNK_MAX_TOKENS:
            msg = (
                f"chunk_max_tokens must be between {MIN_CHUNK_MAX_TOKENS} and "
                f"{MAX_CHUNK_MAX_TOKENS}, got {value}"
            )
            raise ValueError(msg)
        if value > AUTOEMBED_CONTEXT_TOKENS:
            msg = (
                f"chunk_max_tokens must not exceed the autoEmbed context window of "
                f"{AUTOEMBED_CONTEXT_TOKENS} tokens, got {value}"
            )
            raise ValueError(msg)
        return value

    @field_validator("mongodb_uri")
    @classmethod
    def validate_mongodb_uri(cls, value: SecretStr) -> SecretStr:
        uri = value.get_secret_value()
        if uri.startswith(("mongodb://", "mongodb+srv://")):
            return value
        msg = "mongodb_uri must start with mongodb:// or mongodb+srv://"
        raise ValueError(msg)


@lru_cache
def get_settings() -> HybridSearchSettings:
    return HybridSearchSettings()


def clear_settings_cache() -> None:
    get_settings.cache_clear()


def apply_log_level(level: str) -> None:
    logging.basicConfig(
        level=level,
        stream=sys.stdout,
        format="%(asctime)s - %(levelname)s - %(name)s - %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
