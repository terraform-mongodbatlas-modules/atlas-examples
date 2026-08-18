from __future__ import annotations

import os
import time
from dataclasses import replace
from pathlib import Path

import chainlit as cl
from pymongo.errors import PyMongoError

from hybrid_search import voyage as voyage_module
from hybrid_search.indexes import create_chunks_indexes_if_missing
from hybrid_search.ingest import (
    delete_all_chunks,
    delete_by_file_path,
    ingest_file,
    ingested_display_names,
    list_ingested_files,
    skip_reason_for_filename,
)
from hybrid_search.mongo import chunks_collection, get_client
from hybrid_search.settings import get_settings
from hybrid_search.ui.delete_logic import format_ingested_file_list, resolve_delete_selection
from hybrid_search.ui.demo import (
    DELETE_COMMAND,
    DELETE_COMMAND_ID,
    DELETE_STARTER,
    DEMO_ACTION_NAME,
    DEMO_COMMAND,
    DEMO_COMMAND_ID,
    DEMO_STARTERS,
    INGEST_COMMAND,
    INGEST_COMMAND_ID,
    UPLOAD_STARTER,
)
from hybrid_search.ui.ingest_progress import FileProgress, render_ingest_batch
from hybrid_search.ui.query_logic import answer_query

ALLOWED_SUFFIXES = {".pdf", ".txt", ".md"}
_ASK_ACCEPT = ["application/pdf", "text/plain", "text/markdown", "text/x-markdown"]
INGEST_MAX_FILES = 10
INGEST_MAX_SIZE_MB = 100
INGEST_ASK_PROMPT = (
    f"Choose pdf, txt, or md to ingest (up to {INGEST_MAX_FILES} files, "
    f"{INGEST_MAX_SIZE_MB} MB per batch)."
)
INGEST_CONTINUE_PROMPT = "Upload another batch or finish ingesting?"
INGEST_ACTION_NAME = "ingest"
INGEST_MORE_CHOICE = "more"
INGEST_DONE_CHOICE = "done"


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
    return [
        cl.Starter(**UPLOAD_STARTER),
        cl.Starter(**DELETE_STARTER),
        *[cl.Starter(**item) for item in DEMO_STARTERS],
    ]


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
        return
    await cl.context.emitter.set_commands([INGEST_COMMAND, DELETE_COMMAND, DEMO_COMMAND])


@cl.on_message
async def on_message(message: cl.Message):
    if message.command == INGEST_COMMAND_ID or message.content == UPLOAD_STARTER["message"]:
        await _ingest_interactive()
        return
    if message.command == DELETE_COMMAND_ID or message.content == DELETE_STARTER["message"]:
        await _delete_ingested_files()
        return
    if message.command == DEMO_COMMAND_ID:
        await _show_demo_questions()
        return
    uploads = [
        (element.name or Path(element.path).name, Path(element.path))
        for element in message.elements or []
        if element.path
    ]
    if uploads:
        await _ingest_named_paths(uploads)
        return
    await _handle_query(message.content)


async def _show_demo_questions() -> None:
    actions = [
        cl.Action(
            name=DEMO_ACTION_NAME,
            payload={"message": item["message"]},
            label=item["label"],
        )
        for item in DEMO_STARTERS
    ]
    ask = cl.AskActionMessage(
        content="Try a demo question:",
        actions=actions,
        timeout=300,
        raise_on_timeout=False,
    )
    response = await ask.send()
    if response is None:
        return
    query = response.get("payload", {}).get("message")
    if not query:
        return
    await ask.remove()
    await cl.Message(content=query, type="user_message").send()
    await _handle_query(query)


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


async def _pick_ingest_files():
    return await cl.AskFileMessage(
        content=INGEST_ASK_PROMPT,
        accept=_ASK_ACCEPT,
        max_files=INGEST_MAX_FILES,
        max_size_mb=INGEST_MAX_SIZE_MB,
        timeout=300,
        raise_on_timeout=False,
    ).send()


async def _ask_upload_more() -> bool:
    ask = cl.AskActionMessage(
        content=INGEST_CONTINUE_PROMPT,
        actions=[
            cl.Action(
                name=INGEST_ACTION_NAME,
                payload={"choice": INGEST_MORE_CHOICE},
                label="Upload another batch",
            ),
            cl.Action(
                name=INGEST_ACTION_NAME,
                payload={"choice": INGEST_DONE_CHOICE},
                label="Done uploading",
            ),
        ],
        timeout=300,
        raise_on_timeout=False,
    )
    response = await ask.send()
    if response is None:
        return False
    await ask.remove()
    return response.get("payload", {}).get("choice") == INGEST_MORE_CHOICE


async def _ingest_interactive() -> None:
    while True:
        files = await _pick_ingest_files()
        if files is None:
            return
        await _ingest_named_paths([(item.name, Path(item.path)) for item in files])
        if not await _ask_upload_more():
            return


async def _delete_ingested_files() -> None:
    collection = cl.user_session.get("collection")
    files = await list_ingested_files(collection)
    listing = format_ingested_file_list(files)
    if not files:
        await cl.Message(content=listing).send()
        return
    response = await cl.AskUserMessage(
        content=listing,
        timeout=300,
        raise_on_timeout=False,
    ).send()
    if response is None:
        return
    selection = response.get("output", "")
    file_paths = resolve_delete_selection(selection, files)
    if file_paths is None:
        await cl.Message(content="Could not match that selection. Try a number or filename.").send()
        return
    async with cl.Step(name="Delete", type="tool", default_open=True) as step:
        if selection.strip().lower() == "all":
            deleted = await delete_all_chunks(collection=collection)
            step.output = f"Deleted all ingested chunks ({deleted} total)."
        else:
            lines: list[str] = []
            for file_path in file_paths:
                result = await delete_by_file_path(file_path, collection=collection)
                name = Path(file_path).name
                lines.append(f"- {name}: {result.chunk_count} chunks")
            step.output = "**Deleted**\n\n" + "\n".join(lines)
        await step.update()


async def _ingest_named_paths(named_paths: list[tuple[str, Path]]) -> None:
    settings = cl.user_session.get("settings")
    collection = cl.user_session.get("collection")
    voyage = cl.user_session.get("voyage")
    ingested_names = await ingested_display_names(collection)
    batch_names: set[str] = set()
    progress: list[FileProgress] = []
    for name, path in named_paths:
        if not is_allowed_upload(path):
            progress.append(FileProgress(name=name, status="skipped", detail="unsupported type"))
            continue
        skip_reason = skip_reason_for_filename(name, ingested=ingested_names, batch=batch_names)
        if skip_reason:
            progress.append(FileProgress(name=name, status="skipped", detail=skip_reason))
            continue
        batch_names.add(name)
        progress.append(FileProgress(name=name, status="waiting"))
    async with cl.Step(name="Ingest", type="tool", default_open=True) as step:

        async def paint() -> None:
            step.output = render_ingest_batch(progress)
            await step.update()

        await paint()
        for i, (name, path) in enumerate(named_paths):
            if progress[i].status == "skipped":
                continue
            start = time.monotonic()
            progress[i] = replace(progress[i], status="running")
            await paint()

            async def on_progress(step_name: str, idx: int = i, started: float = start) -> None:
                progress[idx] = replace(
                    progress[idx],
                    status="running",
                    step=step_name,
                    elapsed_s=time.monotonic() - started,
                )
                await paint()

            try:
                result = await ingest_file(
                    path,
                    settings=settings,
                    collection=collection,
                    voyage=voyage,
                    source_name=name,
                    on_progress=on_progress,
                )
            except Exception as exc:  # noqa: BLE001  one file must not abort the batch
                progress[i] = replace(
                    progress[i],
                    status="error",
                    elapsed_s=time.monotonic() - start,
                    detail=str(exc),
                )
                await paint()
                continue
            progress[i] = replace(
                progress[i],
                status="done",
                elapsed_s=time.monotonic() - start,
                chunk_count=result.chunk_count,
                step="",
            )
            await paint()
