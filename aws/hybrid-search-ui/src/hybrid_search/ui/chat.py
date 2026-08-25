from __future__ import annotations

import logging
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
from hybrid_search.search_modes import DEFAULT
from hybrid_search.settings import apply_log_level, get_settings
from hybrid_search.ui.delete_logic import format_ingested_file_list, resolve_delete_selection
from hybrid_search.ui.demo import (
    CANCEL_ACTION,
    DELETE_ALL_ACTION,
    DELETE_COMMAND,
    DELETE_FILE_ACTION,
    DELETE_STARTER,
    DEMO_ACTION_NAME,
    DEMO_COMMAND,
    DEMO_STARTERS,
    INGEST_COMMAND,
    UPLOAD_STARTER,
    Mode,
)
from hybrid_search.ui.ingest_progress import FileProgress, render_ingest_batch
from hybrid_search.ui.mode_router import (
    PENDING_FILE_ASK_KEY,
    UiMode,
    get_ui_mode,
    resolve_mode,
    set_ui_mode,
)
from hybrid_search.ui.query_steps import run_query_with_steps
from hybrid_search.ui.search_settings import (
    SEARCH_MODES_KEY,
    confirmation_message,
    modes_from_settings,
    send_default_settings,
)

logger = logging.getLogger(__name__)
ALLOWED_SUFFIXES = {".pdf", ".txt", ".md"}
_ASK_ACCEPT = ["application/pdf", "text/plain", "text/markdown", "text/x-markdown"]
INGEST_MAX_FILES = 10
INGEST_MAX_SIZE_MB = 100
INGEST_ASK_PROMPT = (
    f"Choose pdf, txt, or md to ingest (up to {INGEST_MAX_FILES} files, "
    f"{INGEST_MAX_SIZE_MB} MB per batch)."
)


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
    apply_log_level(settings.log_level)
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
        logger.exception("Startup failed")
        await cl.Message(
            content=(f"Startup failed. Check MONGODB_URI, VOYAGE_API_KEY, and Atlas access: {exc}")
        ).send()
        return
    set_ui_mode(UiMode.QUERY)
    await cl.context.emitter.set_commands([INGEST_COMMAND, DELETE_COMMAND, DEMO_COMMAND])
    await send_default_settings()


@cl.on_settings_update
async def on_settings_update(settings: dict):
    try:
        modes = modes_from_settings(settings)
    except ValueError as exc:
        await cl.Message(content=str(exc)).send()
        return
    cl.user_session.set(SEARCH_MODES_KEY, modes)
    await cl.Message(content=confirmation_message(modes)).send()


def _mode_to_ui_mode(mode: Mode) -> UiMode:
    match mode:
        case Mode.INGEST:
            return UiMode.INGEST
        case Mode.DELETE:
            return UiMode.DELETE
        case Mode.DEMO:
            return UiMode.QUERY


async def _run_mode(mode: Mode) -> None:
    match mode:
        case Mode.INGEST:
            await _ingest_interactive()
        case Mode.DELETE:
            await _delete_ingested_files()
        case Mode.DEMO:
            await _show_demo_questions()


@cl.on_message
async def on_message(message: cl.Message):
    mode = resolve_mode(command=message.command, content=message.content)
    if mode:
        set_ui_mode(_mode_to_ui_mode(mode))
        await _run_mode(mode)
        return
    uploads = [
        (element.name or Path(element.path).name, Path(element.path))
        for element in message.elements or []
        if element.path
    ]
    if uploads:
        await _ingest_named_paths(uploads)
        set_ui_mode(UiMode.QUERY)
        return
    if get_ui_mode() == UiMode.DELETE:
        await _handle_delete_text_fallback(message.content)
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
    modes = cl.user_session.get(SEARCH_MODES_KEY, DEFAULT)
    result = await run_query_with_steps(
        query, settings=settings, collection=collection, voyage=voyage, modes=modes
    )
    if not result.answer:
        return
    if result.source_files:
        sources = "\n".join(f"- {name}" for name in result.source_files)
        footer = f"### Sources\n{sources}"
    else:
        footer = "### Sources\nNo sources retrieved"
    await cl.Message(content=f"{result.answer}\n\n{footer}").send()


async def _prompt_file_pick() -> list[cl.AskFileResponse] | None:
    ask = cl.AskFileMessage(
        content=INGEST_ASK_PROMPT,
        accept=_ASK_ACCEPT,
        max_files=INGEST_MAX_FILES,
        max_size_mb=INGEST_MAX_SIZE_MB,
        timeout=300,
        raise_on_timeout=False,
    )
    cl.user_session.set(PENDING_FILE_ASK_KEY, ask)
    try:
        return await ask.send()
    finally:
        cl.user_session.set(PENDING_FILE_ASK_KEY, None)


async def _ingest_interactive() -> None:
    set_ui_mode(UiMode.INGEST)
    cancel_msg = await cl.Message(
        content="Cancel returns to search without uploading.",
        actions=[cl.Action(name=CANCEL_ACTION, payload={}, label="Cancel upload")],
    ).send()
    files = await _prompt_file_pick()
    await cancel_msg.remove()
    set_ui_mode(UiMode.QUERY)
    if not files:
        return
    await _ingest_named_paths([(item.name, Path(item.path)) for item in files])


async def _cancel_pending_file_ask() -> None:
    ask = cl.user_session.get(PENDING_FILE_ASK_KEY)
    if ask is not None:
        await ask.remove()


async def _delete_ingested_files() -> None:
    collection = cl.user_session.get("collection")
    files = await list_ingested_files(collection)
    listing = format_ingested_file_list(files)
    if not files:
        await cl.Message(content=listing).send()
        set_ui_mode(UiMode.QUERY)
        return
    actions = [
        cl.Action(
            name=DELETE_FILE_ACTION,
            payload={"index": index},
            label=f"Delete {item.display_name}",
        )
        for index, item in enumerate(files, start=1)
    ]
    actions.extend(
        [
            cl.Action(name=DELETE_ALL_ACTION, payload={}, label="Delete all"),
            cl.Action(name=CANCEL_ACTION, payload={}, label="Cancel"),
        ]
    )
    await cl.Message(content=listing, actions=actions).send()


async def _perform_delete(*, collection, file_paths: list[str], delete_all: bool) -> None:
    async with cl.Step(name="Delete", type="tool", default_open=True) as step:
        if delete_all:
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


async def _handle_delete_text_fallback(selection: str) -> None:
    collection = cl.user_session.get("collection")
    files = await list_ingested_files(collection)
    file_paths = resolve_delete_selection(selection, files)
    if file_paths is None:
        await cl.Message(content="Could not match that selection. Try a number or filename.").send()
        return
    await _perform_delete(
        collection=collection,
        file_paths=file_paths,
        delete_all=selection.strip().lower() == "all",
    )
    set_ui_mode(UiMode.QUERY)


@cl.action_callback(DELETE_FILE_ACTION)
async def on_delete_file(action: cl.Action):
    index = action.payload.get("index")
    if not isinstance(index, int):
        return
    collection = cl.user_session.get("collection")
    files = await list_ingested_files(collection)
    if not 1 <= index <= len(files):
        await cl.Message(content="That file is no longer available.").send()
        set_ui_mode(UiMode.QUERY)
        return
    await _perform_delete(
        collection=collection, file_paths=[files[index - 1].file_path], delete_all=False
    )
    set_ui_mode(UiMode.QUERY)


@cl.action_callback(DELETE_ALL_ACTION)
async def on_delete_all(_action: cl.Action):
    collection = cl.user_session.get("collection")
    await _perform_delete(collection=collection, file_paths=[], delete_all=True)
    set_ui_mode(UiMode.QUERY)


@cl.action_callback(CANCEL_ACTION)
async def on_cancel(_action: cl.Action):
    await _cancel_pending_file_ask()
    set_ui_mode(UiMode.QUERY)


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
