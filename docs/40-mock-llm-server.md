# 40 — Mock LLM Server (CI Only)

## What

`lib/mock-llm-server.sh` provides `start_mock_llm()` that starts a lightweight Python HTTP server on port 4000 responding to OpenAI-compatible endpoints. Used exclusively in CI/testing.

## Why

- Enables full entrypoint pipeline in CI without real provider credentials
- Returns fixed mock models and chat completions
- Self-contained Python heredoc, no deps beyond stdlib

## API Endpoints

| Method | Path | Response |
|--------|------|----------|
| GET | `/v1/models` | `mock-gpt-4o`, `mock-gpt-4o-mini` |
| POST | `/v1/chat/completions` | Mock completion |
| Other | — | 404 |
