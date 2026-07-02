#!/usr/bin/env bash
# ── Mock LLM server (CI only) ──────────────────────────────────────────────
# Starts a tiny Python HTTP server on port 4000 that responds to OpenAI-
# compatible endpoints.  Used only when OPENAI_BASE_URL points at localhost:4000
# (the CI fallback value when the secret is not configured).

start_mock_llm() {
    python3 - "$@" <<'PYEOF' &
import sys, json, threading
from http.server import HTTPServer, BaseHTTPRequestHandler

class MockLLM(BaseHTTPRequestHandler):
    MODELS = {"object":"list","data":[
        {"id":"mock-gpt-4o","object":"model","owned_by":"mock"},
        {"id":"mock-gpt-4o-mini","object":"model","owned_by":"mock"}]}

    def _json(self, code, body):
        payload = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type","application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.rstrip("/") in ("/models","/v1/models"):
            self._json(200, self.MODELS)
        else:
            self._json(404, {"error":"not found"})

    def do_POST(self):
        if self.path.rstrip("/").startswith("/v1/chat/completions"):
            self._json(200, {
                "id":"mock-cmpl","object":"chat.completion",
                "choices":[{"index":0,"message":{"role":"assistant","content":"mock"},"finish_reason":"stop"}],
                "model":"mock-gpt-4o","usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}})
        else:
            self._json(404, {"error":"not found"})

    def log_message(self, fmt, *args):
        pass  # silence per-request logs

if __name__ == "__main__":
    httpd = HTTPServer(("0.0.0.0", 4000), MockLLM)
    print("[mock-llm] Mock LLM server on :4000", flush=True)
    httpd.serve_forever()
PYEOF
}
