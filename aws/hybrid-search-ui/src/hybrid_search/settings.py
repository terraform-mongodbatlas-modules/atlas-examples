from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

LlmProvider = Literal["anthropic", "openai", "gemini", "grove"]


class HybridSearchSettings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore")

    mongodb_uri: SecretStr
    mongodb_database: str = "hybrid_search"
    voyage_api_key: SecretStr
    voyage_base_url: str | None = None
    voyage_model: str = "voyage-context-4"
    voyage_output_dimension: int = 1024
    voyage_chunk_size: int = 512
    top_k: int = 20
    vector_index_name: str = "vector_idx"
    text_index_name: str = "text_idx"
    chunks_collection: str = "chunks"
    vector_weight: float = 0.6
    text_weight: float = 0.4
    enable_llm: bool = True
    llm_provider: LlmProvider = "anthropic"
    anthropic_api_key: SecretStr | None = None
    anthropic_model: str = "claude-sonnet-4-20250514"
    openai_api_key: SecretStr | None = None
    openai_model: str = "gpt-4o"
    openai_base_url: str = "https://api.openai.com/v1"
    gemini_api_key: SecretStr | None = None
    gemini_model: str = "gemini-2.0-flash"
    grove_api_key: SecretStr | None = None
    grove_model: str = "gpt-4o"
    grove_base_url: str | None = None

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
