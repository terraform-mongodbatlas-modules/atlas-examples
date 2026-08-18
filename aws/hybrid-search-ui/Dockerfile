FROM python:3.13-slim

COPY --from=ghcr.io/astral-sh/uv:0.9.21 /uv /uvx /bin/

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev --no-install-project --extra ui --extra aws

COPY src/ ./src/
RUN uv sync --frozen --no-dev --extra ui --extra aws

COPY chainlit.md ./
RUN mkdir -p .chainlit
COPY docker/chainlit-config.toml .chainlit/config.toml
RUN .venv/bin/python -c "from chainlit.config import init_config; init_config()" \
    && cp chainlit.md chainlit_en-US.md

RUN useradd --create-home --shell /bin/bash appuser \
    && chown -R appuser:appuser /app
USER appuser

EXPOSE 8001

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/')"

CMD [".venv/bin/chainlit", "run", "src/hybrid_search/ui/chat.py", "--port", "8001", "--host", "0.0.0.0"]
