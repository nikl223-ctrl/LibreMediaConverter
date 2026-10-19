#!/usr/bin/env python3
"""GPU-free HTTP asset server for a client-rendered truck game proof of concept.

Optional: DRIVE_LEVEL_FILE_ID and GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
GOOGLE_REFRESH_TOKEN, to fetch only the explicitly configured level JSON.
Tokens never leave this server. The in-memory Drive cache expires by TTL.
"""
import hashlib
import json
import low_bandwidth
import mimetypes
import os
import re
import threading
import time
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ALLOWED_STATIC = {"/": "index.html", "/index.html": "index.html", "/game.js": "game.js", "/styles.css": "styles.css", "/assets/world.json": "assets/world.json"}
MAX_LEVEL_BYTES = 2 * 1024 * 1024
CACHE_TTL = max(1, int(os.getenv("DRIVE_CACHE_SECONDS", "600")))
_lock = threading.RLock()
_cache = {"data": None, "until": 0, "from": "none"}
_stats = {"responses": 0, "response_bytes": 0, "drive_fetches": 0, "client_probes": 0, "save_writes": 0}


def get_drive_level():
    file_id = os.getenv("DRIVE_LEVEL_FILE_ID", "").strip()
    if not file_id:
        return (ROOT / "assets" / "world.json").read_bytes(), "local"
    if not re.fullmatch(r"[A-Za-z0-9_-]{10,128}", file_id):
        raise ValueError("Invalid Drive level file ID")
    now = time.monotonic()
    with _lock:
        if _cache["data"] is not None and now < _cache["until"]:
            return _cache["data"], "drive-memory-cache"
    disk_data = low_bandwidth.cached_level(file_id, CACHE_TTL)
    if disk_data is not None:
        with _lock:
            _cache.update(data=disk_data, until=time.monotonic() + CACHE_TTL, **{"from": "drive-disk-cache"})
        return disk_data, "drive-disk-cache"
    required = ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REFRESH_TOKEN")
    if any(not os.getenv(key) for key in required):
        raise RuntimeError("Missing Drive credentials on server")
    fields = urllib.parse.urlencode({"client_id": os.environ["GOOGLE_CLIENT_ID"],
                                     "client_secret": os.environ["GOOGLE_CLIENT_SECRET"],
                                     "refresh_token": os.environ["GOOGLE_REFRESH_TOKEN"],
                                     "grant_type": "refresh_token"}).encode()
    with urllib.request.urlopen(urllib.request.Request("https://oauth2.googleapis.com/token", data=fields), timeout=15) as r:
        token = json.load(r)["access_token"]
    url = f"https://www.googleapis.com/drive/v3/files/{file_id}?alt=media"
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = r.read(MAX_LEVEL_BYTES + 1)
    if len(data) > MAX_LEVEL_BYTES:
        raise ValueError("Level exceeds the 2 MiB browser-demo limit")
    level = json.loads(data)
    if not isinstance(level, dict) or not isinstance(level.get("track"), dict):
        raise ValueError("Google Drive file is not a supported demo level")
    low_bandwidth.save_level_cache(file_id, data)
    with _lock:
        _cache.update(data=data, until=time.monotonic() + CACHE_TTL, **{"from": "drive"})
        _stats["drive_fetches"] += 1
    return data, "drive"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_HEAD(self):
        self.handle_request(head_only=True)

    def do_GET(self):
        self.handle_request(head_only=False)

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            length = -1
        if path not in ("/api/session", "/api/client", "/api/save"):
            return self.send_bytes(404, b"Not Found", "text/plain")
        if length < 0 or length > low_bandwidth.MAX_SAVE_BYTES:
            return self.send_bytes(413, b'{"error":"request too large"}', "application/json")
        body = self.rfile.read(length)
        try:
            if path == "/api/session":
                if length != 0:
                    raise ValueError("Session request must be empty")
                token = low_bandwidth.create_session()
                return self.send_bytes(200, json.dumps({"token": token}).encode(), "application/json")
            if path == "/api/client":
                fields = json.loads(body)
                if not isinstance(fields, dict):
                    raise ValueError("Invalid capabilities")
                # Browser-provided declarations, not a physical GPU inventory.
                webgpu = fields.get("webgpu") is True
                webgl2 = fields.get("webgl2") is True
                chosen = ("WebGPU" if webgpu else "WebGL2" if webgl2 else "Canvas2D")
                with _lock:
                    _stats["client_probes"] += 1
                return self.send_bytes(200, json.dumps({
                    "render_mode": chosen, "client_rendering": True,
                    "server_gpu": False, "native_steam_supported": False
                }).encode(), "application/json")
            token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
            low_bandwidth.write_save(token, body)
            with _lock:
                _stats["save_writes"] += 1
            return self.send_bytes(200, b'{"saved":true}', "application/json")
        except (ValueError, PermissionError, OSError):
            return self.send_bytes(400, b'{"error":"invalid request or session"}', "application/json")

    def handle_request(self, head_only=False):
        path = urllib.parse.urlsplit(self.path).path
        try:
            if path == "/health":
                return self.send_bytes(200, b'{"ok":true,"server_gpu":false}', "application/json", head_only=head_only)
            if path == "/api/capabilities":
                value = {"server_gpu": False, "native_windows_exe_in_browser": False,
                         "rendering": "client", "webgpu_or_webgl2": "browser-dependent",
                         "drive_level_configured": bool(os.getenv("DRIVE_LEVEL_FILE_ID")),
                         "cache_seconds": CACHE_TTL}
                return self.send_bytes(200, json.dumps(value).encode(), "application/json", head_only=head_only)
            if path == "/api/save":
                token = self.headers.get("Authorization", "").removeprefix("Bearer ").strip()
                try:
                    state = low_bandwidth.read_save(token)
                except (ValueError, PermissionError):
                    return self.send_bytes(401, b'{"error":"unknown session"}', "application/json", head_only=head_only)
                if state is None:
                    return self.send_bytes(404, b'{"error":"no save yet"}', "application/json", head_only=head_only)
                return self.send_bytes(200, json.dumps(state).encode(), "application/json", head_only=head_only)
            if path == "/api/stats":
                with _lock:
                    value = dict(_stats)
                    value["drive_cached"] = _cache["data"] is not None and time.monotonic() < _cache["until"]
                return self.send_bytes(200, json.dumps(value).encode(), "application/json", head_only=head_only)
            if path == "/api/world":
                data, source = get_drive_level()
                etag = '"sha256-' + hashlib.sha256(data).hexdigest() + '"'
                return self.send_bytes(200, data, "application/json", {"X-Asset-Source": source, "Cache-Control": "private, max-age=300", "ETag": etag}, head_only=head_only, allow_range=True)
            local_name = ALLOWED_STATIC.get(path)
            if local_name is None:
                return self.send_bytes(404, b"Not Found", "text/plain", head_only=head_only)
            f = ROOT / local_name
            data = f.read_bytes()
            content_type = "text/html" if path == "/" else mimetypes.guess_type(str(f))[0] or "application/octet-stream"
            digest = hashlib.sha256(data).hexdigest()
            cache_control = "no-cache" if path in ("/", "/index.html") else "public, max-age=3600"
            return self.send_bytes(200, data, content_type,
                                   headers={"ETag": '"sha256-' + digest + '"',
                                            "Cache-Control": cache_control},
                                   head_only=head_only, allow_range=True)
        except (OSError, ValueError, RuntimeError) as exc:
            # Deliberately avoid sending OAuth or URL details to clients.
            self.log_error("Backend asset unavailable: %s", type(exc).__name__)
            return self.send_bytes(503, b'{"error":"asset unavailable"}', "application/json", head_only=head_only)

    def send_bytes(self, status, payload, ctype, headers=None, head_only=False, allow_range=False):
        extra = dict(headers or {})
        range_hdr = self.headers.get("Range", "") if allow_range else ""
        if range_hdr:
            m = re.fullmatch(r"bytes=(\d+)-(\d*)", range_hdr)
            if not m:
                return self.send_bytes(416, b"Invalid Range", "text/plain", head_only=head_only)
            first = int(m.group(1))
            last = min(int(m.group(2)), len(payload) - 1) if m.group(2) else len(payload) - 1
            if first >= len(payload) or last < first:
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(payload)}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            extra["Content-Range"] = f"bytes {first}-{last}/{len(payload)}"
            payload = payload[first:last + 1]
            status = 206
        etag = extra.get("ETag")
        if status == 200 and not range_hdr and etag and self.headers.get("If-None-Match") == etag:
            status = 304
            payload = b""
        self.send_response(status)
        self.send_header("Content-Type", ctype + ("; charset=utf-8" if ctype.startswith("text/") or ctype == "application/json" else ""))
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Cache-Control", extra.pop("Cache-Control", "no-store"))
        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'")
        if allow_range:
            self.send_header("Accept-Ranges", "bytes")
        for key, value in extra.items():
            self.send_header(key, value)
        self.end_headers()
        if not head_only:
            self.wfile.write(payload)
            with _lock:
                _stats["response_bytes"] += len(payload)
                _stats["responses"] += 1

    def log_message(self, fmt, *args):
        if os.getenv("QUIET", "0") != "1":
            super().log_message(fmt, *args)


def main():
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8765"))
    with ThreadingHTTPServer((host, port), Handler) as srv:
        print(f"Browser-only renderer demo: http://{host}:{port} (server GPU: none)", flush=True)
        srv.serve_forever(poll_interval=0.2)


if __name__ == "__main__":
    main()
