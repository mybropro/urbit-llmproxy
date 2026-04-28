#!/usr/bin/env python3
"""
welcome-llm: a tiny OpenAI-compatible HTTP server that hardcodes a single
model and a fixed response. Lets ~datryn-ribdun (and anyone else) host a
zero-cost demo backend so a fresh %llmproxy install gets a "hello" working
out of the box, even without a GPU.

Endpoints:
  GET  /v1/models               -> {welcome-model}
  POST /v1/chat/completions     -> "welcome to LLM hosting on urbit"

Default port: 11434 (matches Ollama's default so urbit's stock backend URL
works without configuration).

stdlib-only — no pip install.
"""

import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

WELCOME = (
    "Hey — your ship just reached across the Urbit network and connected to "
    "~datryn-ribdun, who then reached out to a locally hosted LLM (that "
    "always returns this welcome message).\n\n"
    "If you have any friends who self-host LLMs, this same setup can be used "
    "to connect to theirs.\n\n"
    "~sarlev/v3p046tv is a great group to chat about \"Sovereign Compute\" in."
)
MODEL_ID = "welcome-model"
PORT = int(os.environ.get("PORT", "11434"))


class Handler(BaseHTTPRequestHandler):
    def _ok(self, body):
        body_bytes = json.dumps(body).encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def _404(self):
        self.send_response(404)
        self.send_header("content-length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            return self._ok(
                {
                    "object": "list",
                    "data": [
                        {
                            "id": MODEL_ID,
                            "object": "model",
                            "owned_by": "datryn-ribdun",
                        }
                    ],
                }
            )
        return self._404()

    def do_POST(self):
        if self.path.rstrip("/") == "/v1/chat/completions":
            length = int(self.headers.get("content-length", 0))
            _ = self.rfile.read(length)
            return self._ok(
                {
                    "id": "welcome-completion",
                    "object": "chat.completion",
                    "created": 0,
                    "model": MODEL_ID,
                    "choices": [
                        {
                            "index": 0,
                            "message": {"role": "assistant", "content": WELCOME},
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {
                        "prompt_tokens": 0,
                        "completion_tokens": 0,
                        "total_tokens": 0,
                    },
                }
            )
        return self._404()

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"welcome-llm listening on :{PORT}", flush=True)
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
