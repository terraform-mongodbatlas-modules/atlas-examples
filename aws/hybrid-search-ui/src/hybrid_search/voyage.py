from __future__ import annotations

from dataclasses import dataclass

import voyageai

from hybrid_search.settings import HybridSearchSettings


@dataclass(frozen=True)
class DocumentEmbedResult:
    chunk_texts: list[str]
    embeddings: list[list[float]]


def is_zero_vector(vector: list[float]) -> bool:
    return not vector or all(value == 0.0 for value in vector)


def assert_nonzero_embeddings(
    embed: DocumentEmbedResult,
    *,
    voyage_base_url: str | None,
) -> None:
    if not embed.embeddings or not all(is_zero_vector(vector) for vector in embed.embeddings):
        return
    base = voyage_base_url or "https://api.voyageai.com/v1"
    msg = (
        "Voyage returned zero embeddings. "
        f"Check VOYAGE_API_KEY and VOYAGE_BASE_URL ({base}). "
        "Atlas AI staging (ai-stage.mongodb.com) has returned all-zero vectors in lab tests."
    )
    raise RuntimeError(msg)


def build_voyage_client(settings: HybridSearchSettings) -> voyageai.AsyncClient:
    kwargs: dict[str, str] = {"api_key": settings.voyage_api_key.get_secret_value()}
    if settings.voyage_base_url:
        kwargs["base_url"] = settings.voyage_base_url
    return voyageai.AsyncClient(**kwargs)


async def embed_document(
    text: str,
    *,
    client: voyageai.AsyncClient,
    settings: HybridSearchSettings,
) -> DocumentEmbedResult:
    result = await client.contextualized_embed(
        inputs=[text],
        model=settings.voyage_model,
        input_type="document",
        enable_auto_chunking=True,
        chunk_size=settings.voyage_chunk_size,
        output_dimension=settings.voyage_output_dimension,
    )
    first = result.results[0]
    return DocumentEmbedResult(
        chunk_texts=list(first.chunk_texts), embeddings=list(first.embeddings)
    )


async def embed_query(
    text: str,
    *,
    client: voyageai.AsyncClient,
    settings: HybridSearchSettings,
) -> list[float]:
    result = await client.contextualized_embed(
        inputs=[text],
        model=settings.voyage_model,
        input_type="query",
        enable_auto_chunking=False,
        output_dimension=settings.voyage_output_dimension,
    )
    return list(result.results[0].embeddings[0])
