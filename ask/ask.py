"""The `ask` endpoint for Caddy's on-demand TLS.

Caddy calls GET /check?domain=<name> before it asks a CA for a certificate for a
name it has never seen. 200 means "go ahead", anything else means "refuse".

Modes (env ASK_MODE):
  allowlist  200 only for names listed in the tenants file (default, the safe one)
  open       200 for every well-formed name: shown in the drill to demonstrate
             why this is dangerous against a real CA with rate limits
"""
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

TENANTS_FILE = os.environ.get("TENANTS_FILE", "/data/tenants.txt")
MODE = os.environ.get("ASK_MODE", "allowlist")
HOSTNAME = re.compile(r"^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")


def load_tenants(path=TENANTS_FILE):
    """Re-read on every call: adding a tenant must not need a restart."""
    try:
        with open(path) as f:
            return {line.strip().lower() for line in f if line.strip() and not line.startswith("#")}
    except FileNotFoundError:
        return set()  # fail closed


def allowed(domain, mode=MODE, tenants=None):
    domain = (domain or "").strip().lower()
    if not HOSTNAME.match(domain):
        return False
    if mode == "open":
        return True
    return domain in (load_tenants() if tenants is None else tenants)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = urlparse(self.path)
        if url.path != "/check":
            self.send_error(404)
            return
        domain = parse_qs(url.query).get("domain", [""])[0]
        ok = allowed(domain)
        self.send_response(200 if ok else 403)
        self.end_headers()
        print(f"ask domain={domain!r} mode={MODE} answer={200 if ok else 403}", flush=True)

    def log_message(self, *args):
        pass  # one structured line per decision is printed above


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 9000), Handler).serve_forever()
