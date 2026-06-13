#!/usr/bin/env bash
# mock-llm-server.sh – lightweight Python-stdlib HTTP server that mimics an
# OpenAI-compatible API.  Used in CI so tests run without real secrets.
#
# Usage:
#   bash tests/mock-llm-server.sh &   # starts in background
#   curl http://localhost:4000/health  # verify it is up
#   kill %1                           # stop it

set -euo pipefail

PORT="${PORT:-4000}"

python3 - "$PORT" <<'PYTHON_SCRIPT'
import sys, json, time
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1])

class MockHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        print(f"[mock-llm] {args[0]}", file=sys.stderr, flush=True)

    def _send_json(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    # ── health ────────────────────────────────────────────────────────
    def do_GET(self):
        if self.path == "/health":
            self._send_json(200, {"status": "OK"})
        elif self.path == "/v1/models":
            self._send_json(200, {
                "object": "list",
                "data": [{"id": "mock-model", "object": "model", "owned_by": "mock"}],
            })
        else:
            self._send_json(404, {"error": "not found"})

    # ── chat completions (streaming + non-streaming) ──────────────────
    def do_POST(self):
        if self.path.startswith("/v1/chat/completions"):
            # Read body (may be empty for some clients)
            length = int(self.headers.get("Content-Length", 0))
            raw = self.rfile.read(length) if length else b""
            try:
                body = json.loads(raw) if raw else {}
            except json.JSONDecodeError:
                body = {}

            model = body.get("model", "mock-model")
            stream = body.get("stream", False)
            request_id = f"chatcmpl-mock-{int(time.time())}"
            created = int(time.time())

            if stream:
                # SSE streaming response
                chunk = {
                    "id": request_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "delta": {"role": "assistant", "content": "Mock LLM response"},
                        "finish_reason": None,
                    }],
                }
                final = {
                    "id": request_id,
                    "object": "chat.completion.chunk",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "delta": {},
                        "finish_reason": "stop",
                    }],
                }
                payload = (
                    f"data: {json.dumps(chunk)}\n\n"
                    f"data: {json.dumps(final)}\n\n"
                    "data: [DONE]\n\n"
                ).encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
            else:
                # Non-streaming response
                self._send_json(200, {
                    "id": request_id,
                    "object": "chat.completion",
                    "created": created,
                    "model": model,
                    "choices": [{
                        "index": 0,
                        "message": {"role": "assistant", "content": "Mock LLM response"},
                        "finish_reason": "stop",
                    }],
                    "usage": {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15},
                })
        else:
            self._send_json(404, {"error": "not found"})

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", PORT), MockHandler)
    print(f"[mock-llm] listening on 0.0.0.0:{PORT}", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
PYTHON_SCRIPT
