from __future__ import annotations

DEMO_STARTERS = [
    {
        "label": "AI RMF functions",
        "message": "What are the four functions of the AI RMF?",
    },
    {
        "label": "Measure GenAI risk",
        "message": "How should we measure generative AI risk?",
    },
    {
        "label": "Prompt injection",
        "message": "What is prompt injection and how do we mitigate it?",
    },
]

INGEST_COMMAND_ID = "Ingest"

INGEST_COMMAND = {
    "id": INGEST_COMMAND_ID,
    "icon": "upload",
    "description": "Ingest pdf, txt, or md",
    "button": True,
}

UPLOAD_STARTER = {
    "label": "Upload documents",
    "message": "Ingest files",
    "command": INGEST_COMMAND_ID,
}
