"""Point Chainlit at the app's assets directory.

Chainlit reads ``.chainlit/config.toml`` and ``chainlit.md`` from
``CHAINLIT_APP_ROOT``, and captures that path when ``chainlit.config`` is first
imported. Everything a user can edit lives under ``assets/``, so this module
sets the variable before anything imports Chainlit.

The image sets ``CHAINLIT_APP_ROOT=/app/assets`` in the Dockerfile. This
fallback covers local ``uvicorn`` from the example root.
"""

from __future__ import annotations

import os
from pathlib import Path

_ASSETS_DIR = Path(__file__).resolve().parents[2] / "assets"


def ensure_chainlit_app_root() -> None:
    """Default ``CHAINLIT_APP_ROOT`` to the app's assets directory."""
    os.environ.setdefault("CHAINLIT_APP_ROOT", str(_ASSETS_DIR))
