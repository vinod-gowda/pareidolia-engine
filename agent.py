#!/usr/bin/env python3
"""Runs inside the pod: a private command channel so the pod can be repaired in place instead of rebuilt.
POST /<token>  with a shell command as the body -> its output. The token is a random secret known only to
the lab that started the pod; without it every request gets 404. The pod is disposable and lives 1-5 hours."""
import os, subprocess, sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
TOKEN = os.environ["AGENT_TOKEN"]

class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        if self.path.strip("/") != TOKEN:
            self.send_response(404); self.end_headers(); return
        cmd = self.rfile.read(int(self.headers.get("Content-Length") or 0)).decode()
        try:
            r = subprocess.run(["bash", "-lc", cmd], capture_output=True, text=True, timeout=int(self.headers.get("X-Timeout") or 900))
            out = (r.stdout + r.stderr)[-20000:] + f"\n[exit {r.returncode}]"
        except subprocess.TimeoutExpired:
            out = "[timed out]"
        data = out.encode()
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)

ThreadingHTTPServer(("0.0.0.0", 8189), H).serve_forever()
