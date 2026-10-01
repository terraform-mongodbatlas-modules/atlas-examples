# Base images come from Amazon ECR Public (Docker's official mirror) rather than
# Docker Hub. CodeBuild hosts are anonymous Docker Hub pulls, which hit
# "429 Too Many Requests" under load; ECR Public has no such rate limit.
# ---- Builder: resolve and install the virtualenv, keep the uv cache here ----
FROM public.ecr.aws/docker/library/python:3.13-slim AS builder

COPY --from=ghcr.io/astral-sh/uv:0.9.21 /uv /uvx /bin/

WORKDIR /app

# Dependencies only. Cached until pyproject.toml or uv.lock change.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project --extra ui --extra aws

# Project source, then install the project into the environment created above.
COPY src/ ./src/
RUN uv sync --frozen --no-dev --extra ui --extra aws

# ---- Runtime: fresh base, only the virtualenv and the sources it points at ----
FROM public.ecr.aws/docker/library/python:3.13-slim

WORKDIR /app

# Create the unprivileged user and hand over the still-empty /app directory
# before any large layer lands. A recursive chown after the install layers
# copies the whole virtualenv into a second layer (252MB) and, because it sits
# after `COPY assets/`, re-pushes that layer on every dataset-only change.
RUN useradd --create-home --shell /bin/bash appuser \
    && chown appuser:appuser /app
USER appuser

# The venv installs the project in editable mode, so site-packages holds a .pth
# pointing at /app/src. Copy both or the import fails with ModuleNotFoundError.
COPY --from=builder --chown=appuser:appuser /app/.venv /app/.venv
COPY --chown=appuser:appuser src/ ./src/

# Static assets last: edits here keep the venv layer cached. Everything a user
# can edit lives under assets/ (see assets/README.md). Chainlit reads its config
# and welcome file from CHAINLIT_APP_ROOT, which points at assets/.
COPY --chown=appuser:appuser assets/ ./assets/

# app.py also defaults this for local uvicorn; the ENV keeps it explicit here.
ENV CHAINLIT_APP_ROOT=/app/assets

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')"

CMD [".venv/bin/uvicorn", "hybrid_search.app:app", "--host", "0.0.0.0", "--port", "8001"]
