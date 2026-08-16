from __future__ import annotations

from openai import AsyncOpenAI
from pydantic_ai import Agent
from pydantic_ai.models.anthropic import AnthropicModel
from pydantic_ai.models.google import GoogleModel
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.anthropic import AnthropicProvider
from pydantic_ai.providers.google import GoogleProvider
from pydantic_ai.providers.openai import OpenAIProvider

from hybrid_search.settings import HybridSearchSettings

RAG_SYSTEM_PROMPT = (
    "Answer the question using only the context snippets provided in the user message. "
    "If the context is insufficient, say so briefly."
)


def build_agent(settings: HybridSearchSettings) -> Agent[None, str]:
    return Agent(_build_model(settings), system_prompt=RAG_SYSTEM_PROMPT, output_type=str)


async def run_rag_prompt(prompt: str, *, settings: HybridSearchSettings) -> str:
    result = await build_agent(settings).run(prompt)
    return result.output


def _build_model(settings: HybridSearchSettings):
    match settings.llm_provider:
        case "anthropic":
            return _anthropic_model(settings)
        case "openai":
            return _openai_model(settings)
        case "grove":
            return _grove_model(settings)
        case "gemini":
            return _gemini_model(settings)
    msg = f"unsupported llm_provider: {settings.llm_provider}"
    raise ValueError(msg)


def _anthropic_model(settings: HybridSearchSettings) -> AnthropicModel:
    if settings.anthropic_api_key is None:
        msg = "ANTHROPIC_API_KEY is required when llm_provider=anthropic"
        raise ValueError(msg)
    provider = AnthropicProvider(api_key=settings.anthropic_api_key.get_secret_value())
    return AnthropicModel(settings.anthropic_model, provider=provider)


def _openai_model(settings: HybridSearchSettings) -> OpenAIChatModel:
    if settings.openai_api_key is None:
        msg = "OPENAI_API_KEY is required when llm_provider=openai"
        raise ValueError(msg)
    provider = OpenAIProvider(
        api_key=settings.openai_api_key.get_secret_value(),
        base_url=settings.openai_base_url,
    )
    return OpenAIChatModel(settings.openai_model, provider=provider)


def _grove_model(settings: HybridSearchSettings) -> OpenAIChatModel:
    if settings.grove_api_key is None or settings.grove_base_url is None:
        msg = "GROVE_API_KEY and GROVE_BASE_URL are required when llm_provider=grove"
        raise ValueError(msg)
    api_key = settings.grove_api_key.get_secret_value()
    client = AsyncOpenAI(
        api_key=api_key,
        base_url=settings.grove_base_url,
        default_headers={"api-key": api_key},
    )
    return OpenAIChatModel(settings.grove_model, provider=OpenAIProvider(openai_client=client))


def _gemini_model(settings: HybridSearchSettings) -> GoogleModel:
    if settings.gemini_api_key is None:
        msg = "GEMINI_API_KEY is required when llm_provider=gemini"
        raise ValueError(msg)
    provider = GoogleProvider(api_key=settings.gemini_api_key.get_secret_value())
    return GoogleModel(settings.gemini_model, provider=provider)
