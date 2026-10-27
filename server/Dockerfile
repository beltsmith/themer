# Build from the repository root: docker build -f server/Dockerfile -t reader-site .
FROM python:3.13-slim
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
WORKDIR /app/server
COPY server/pyproject.toml server/uv.lock ./
RUN uv sync --frozen --no-dev
COPY server/app.py ./
COPY research /app/research
ENV PATH="/app/server/.venv/bin:$PATH"
EXPOSE 8000
USER nobody
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
