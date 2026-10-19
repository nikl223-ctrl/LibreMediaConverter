"""Optional CPU simulation for GPU-free browser gaming proof.

The Linux server advances only a tiny car model. It transmits small numeric
position updates, not pixels, GPU buffers, Steam processes, or video frames.
The browser renders a locally cached 3D world with WebGL/WebGPU.
"""
import math
import threading
import time

import low_bandwidth

_LOCK = threading.RLock()
_ACTIVE = {}
_MAX_SESSIONS = 500
_EXPIRE_SECONDS = 600


def _control_float(value):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError("Invalid steering value")
    n = float(value)
    if not math.isfinite(n) or n < -1 or n > 1:
        raise ValueError("Steering outside supported range")
    return n


def step(token, action):
    if not isinstance(action, dict) or set(action) != {"steer", "gas", "brake"}:
        raise ValueError("Unexpected remote physics command")
    steer = _control_float(action["steer"])
    if not isinstance(action["gas"], bool) or not isinstance(action["brake"], bool):
        raise ValueError("Invalid throttle or brake input")
    # Check the actual server-side session file. A browser cannot pick arbitrary
    # session names; the unguessable opaque token must already exist.
    persisted = low_bandwidth.read_save(token)
    key = low_bandwidth._name_for(token)
    now = time.monotonic()
    with _LOCK:
        if len(_ACTIVE) > _MAX_SESSIONS:
            for k, v in tuple(_ACTIVE.items()):
                if now - v["last"] > _EXPIRE_SECONDS:
                    del _ACTIVE[k]
            if len(_ACTIVE) > _MAX_SESSIONS:
                raise RuntimeError("Too many active demo sessions")
        unit = _ACTIVE.get(key)
        if unit is None:
            state = persisted or {"x": 0.0, "z": 0.0, "velocity": 17.0, "distance": 0.0}
            unit = {"state": dict(state), "last": now - 0.1}
            _ACTIVE[key] = unit
        dt = min(0.15, max(0.005, now - unit["last"]))
        unit["last"] = now
        s = unit["state"]
        speed = min(190 / 3.6, max(0.0, s["velocity"] + (11 if action["gas"] else 0) * dt - (26 if action["brake"] else 0) * dt - 0.4 * dt))
        s["velocity"] = round(speed, 4)
        s["x"] = round(max(-4.8, min(4.8, s["x"] + steer * speed * .30 * dt)), 4)
        s["z"] = round(s["z"] + speed * dt, 4)
        s["distance"] = round(s["distance"] + speed * dt, 4)
        if s["z"] > 2350:
            s["z"] = 0.0
        # Return only numeric state; the renderer is exclusively the client.
        return dict(s)


def disconnect(token):
    key = low_bandwidth._name_for(token)
    with _LOCK:
        _ACTIVE.pop(key, None)
