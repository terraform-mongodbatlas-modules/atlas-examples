from __future__ import annotations

import os
import time
from pathlib import Path

import chainlit as cl
from pymongo.errors import PyMongoError

from hybrid_search import voyage as voyage_module
from hybrid_search.indexes import create_chunks_indexes_if_missing
from hybrid_search.ingest import ingest_file
from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.settings import get_settings
from hybrid_search.ui.demo import DEMO_STARTERS
from hybrid_search.ui.ingest_progress import render_ingest_progress
from hybrid_search.ui.query_logic import answer_query

ALLOWED_SUFFIXES = {".pdf", ".txt", ".md"}


def is_allowed_upload(path: Path) -> bool:
    return path.suffix.lower() in ALLOWED_SUFFIXES


def _password_auth_callback(username: str, password: str):
    expected_user = os.getenv("CHAINLIT_DEMO_USERNAME")
    expected_pass = os.getenv("CHAINLIT_DEMO_PASSWORD")
    if username == expected_user and password == expected_pass:
        return cl.User(identifier=username)
    return None


if (
    os.getenv("CHAINLIT_AUTH_SECRET")
    and os.getenv("CHAINLIT_DEMO_USERNAME")
    and os.getenv("CHAINLIT_DEMO_PASSWORD")
):
    cl.password_auth_callback(_password_auth_callback)


@cl.set_starters
async def set_starters():
    return [cl.Starter(label=item["label"], message=item["message"]) for item in DEMO_STARTERS]


@cl.on_chat_start
async def on_chat_start():
    settings = get_settings()
    try:
        client = get_client(settings)
        collection = chunks_collection(client, settings)
        voyage = voyage_module.build_voyage_client(settings)
        if not settings.skip_index_creation:
            await create_chunks_indexes_if_missing(collection, settings)
        cl.user_session.set("settings", settings)
        cl.user_session.set("client", client)
        cl.user_session.set("collection", collection)
        cl.user_session.set("voyage", voyage)
    except (OSError, ValueError, RuntimeError, TypeError, PyMongoError) as exc:
        await cl.Message(
            content=(f"Startup failed. Check MONGODB_URI, VOYAGE_API_KEY, and Atlas access: {exc}")
        ).send()


@cl.on_message
async def on_message(message: cl.Message):
    if message.elements:
        await _handle_uploads(message.elements)
        return
    await _handle_query(message.content)


async def _handle_query(query: str):
    settings = cl.user_session.get("settings")
    collection = cl.user_session.get("collection")
    voyage = cl.user_session.get("voyage")
    result = await answer_query(query, settings=settings, collection=collection, voyage=voyage)
    if result.source_files:
        sources = "\n".join(f"- {name}" for name in result.source_files)
        footer = f"### Sources\n{sources}"
    else:
        footer = "### Sources\nNo sources retrieved"
    await cl.Message(content=f"{result.answer}\n\n{footer}").send()


async def _handle_uploads(elements: list[cl.Element]):
    uploads = [element for element in elements if element.path]
    total = len(uploads)
    rejected: list[str] = []
    for file_idx, element in enumerate(uploads):
        path = Path(element.path)
        if not is_allowed_upload(path):
            rejected.append(path.name)
            continue
        display_name = element.name or path.name
        await _ingest_upload(path, display_name, file_idx, total)
    if rejected:
        names = ", ".join(rejected)
        await cl.Message(content=f"Unsupported file type: {names}. Use pdf, txt, or md.").send()


async def _ingest_upload(path: Path, display_name: str, file_idx: int, total_files: int):
    settings = cl.user_session.get("settings")
    collection = cl.user_session.get("collection")
    voyage = cl.user_session.get("voyage")
    start = time.monotonic()
    msg = cl.Message(content="")
    await msg.send()

    async def on_progress(step: str):
        msg.content = render_ingest_progress(
            file_name=display_name,
            file_idx=file_idx,
            total_files=total_files,
            elapsed_s=time.monotonic() - start,
            step=step,
        )
        await msg.update()

    result = await ingest_file(
        path,
        settings=settings,
        collection=collection,
        voyage=voyage,
        on_progress=on_progress,
    )
    await cl.Message(
        content=f"Finished `{display_name}` ({result.chunk_count} chunks stored)."
    ).send()
