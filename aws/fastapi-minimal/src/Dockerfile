# Use AWS Lambda Python base image (includes runtime interface client)
FROM public.ecr.aws/lambda/python:3.13 AS base

FROM base AS builder
# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.4.9 /uv /bin/uv
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

# Install dependencies
COPY pyproject.toml ${LAMBDA_TASK_ROOT}/
COPY uv.lock ${LAMBDA_TASK_ROOT}/
WORKDIR ${LAMBDA_TASK_ROOT}
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM base
# Copy the virtual environment
COPY --from=builder ${LAMBDA_TASK_ROOT}/.venv ${LAMBDA_TASK_ROOT}/.venv

# Copy application code
COPY main.py ${LAMBDA_TASK_ROOT}
COPY handler.py ${LAMBDA_TASK_ROOT}
COPY __init__.py ${LAMBDA_TASK_ROOT}

# Set the path to include our virtual environment
ENV PATH="${LAMBDA_TASK_ROOT}/.venv/bin:$PATH"
ENV PYTHONPATH="${LAMBDA_TASK_ROOT}:${LAMBDA_TASK_ROOT}/.venv/lib/python3.13/site-packages"
# Set the Lambda handler
CMD ["handler.handler"]
