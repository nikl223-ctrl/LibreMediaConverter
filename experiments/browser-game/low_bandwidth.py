"""Small, CPU-only asset-cache and save-state helpers for the browser demo.

No Steam integration and no native-game execution. Sessions are anonymous demo
bearer tokens, NOT suitable as production user authentication.
"""
import hashlib
import json
import math
import os
import re
import secrets
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA_ROOT = Path(os.getenv("BROWSER_GAME_DATA_DIR", str(ROOT / ".runtime")))
SAVE_ROOT = DATA_ROOT / "saves"
CACHE_ROOT = DATA_ROOT / "drive"
SESSION_RE = re.compile(r"^[A-Za-z0-9_-]{30,128}$")
MAX_SAVE_BYTES = 2048
MAX_LEVEL_BYTES = 2 * 1024 * 1024


def _atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(prefix=".pending-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.chmod(name, 0o600)
        os.replace(name, path)
    finally:
        try:
            os.unlink(name)
        except FileNotFoundError:
            pass


def _name_for(token):
    if not token or not SESSION_RE.fullmatch(token):
        raise ValueError("Invalid session token")
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def create_session():
    token = secrets.token_urlsafe(32)
    key = _name_for(token)
    _atomic_write(SAVE_ROOT / (key + ".session"), b"browser-demo-session")
    return token


def _verified_path(token):
    key = _name_for(token)
    if not (SAVE_ROOT / (key + ".session")).is_file():
        raise PermissionError("Unknown session")
    return SAVE_ROOT / (key + ".json")


def clean_state(value):
    if not isinstance(value, dict) or set(value) != {"x", "z", "velocity", "distance"}:
        raise ValueError("Invalid game state schema")
    limits = {"x": (-100, 100), "z": (0, 1000000), "velocity": (0, 200), "distance": (0, 100000000)}
    result = {}
    for key, (lo, hi) in limits.items():
        n = value[key]
        if isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) or not lo <= n <= hi:
            raise ValueError("Game state outside valid range")
        result[key] = round(float(n), 4)
    return result


def write_save(token, raw):
    path = _verified_path(token)
    if len(raw) > MAX_SAVE_BYTES:
        raise ValueError("Save payload too large")
    state = clean_state(json.loads(raw))
    _atomic_write(path, json.dumps(state, separators=(",", ":")).encode("utf-8"))
    return state


def read_save(token):
    path = _verified_path(token)
    if not path.is_file():
        return None
    return clean_state(json.loads(path.read_bytes()))


def _drive_cache_path(file_id):
    if not re.fullmatch(r"[A-Za-z0-9_-]{10,128}", file_id):
        raise ValueError("Invalid Drive file ID")
    return CACHE_ROOT / (hashlib.sha256(file_id.encode()).hexdigest() + ".json")


def cached_level(file_id, ttl):
    path = _drive_cache_path(file_id)
    try:
        if time.time() - path.stat().st_mtime > ttl:
            return None
        data = path.read_bytes()
        if len(data) > MAX_LEVEL_BYTES:
            return None
        item = json.loads(data)
        if isinstance(item, dict) and isinstance(item.get("track"), dict):
            return data
    except (OSError, ValueError, json.JSONDecodeError):
        pass
    return None


def save_level_cache(file_id, data):
    if len(data) > MAX_LEVEL_BYTES:
        raise ValueError("Too much game data")
    item = json.loads(data)
    if not isinstance(item, dict) or not isinstance(item.get("track"), dict):
        raise ValueError("Not a valid browser demo level")
    _atomic_write(_drive_cache_path(file_id), data)
