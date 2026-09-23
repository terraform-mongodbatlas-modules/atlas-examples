FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:0.9.21 /uv /uvx /bin/

WORKDIR /app

# Dependencies only. Cached until pyproject.toml or uv.lock change.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project --extra ui --extra aws

# Project source, then install the project into the environment created above.
COPY src/ ./src/
RUN uv sync --frozen --no-dev --extra ui --extra aws

# Static assets last: edits here keep the install layers cached.
COPY chainlit.md ./
COPY chainlit.md chainlit_en-US.md
COPY docker/chainlit/ .chainlit/
COPY demo_queries.yaml ./

RUN useradd --create-home --shell /bin/bash appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/')"

CMD [".venv/bin/chainlit", "run", "src/hybrid_search/ui/chat.py", "--port", "8001", "--host", "0.0.0.0"]
