"""Server-authoritative physics for the original browser demo.

The Linux CPU updates movement and sends only tiny state records; 3D
meshes, shaders, frame pacing and GPU execution stay in the browser.
No arbitrary Steam/Windows executables are executed.
"""
import json
import math
import re
import secrets
import threading
import time

from low_bandwidth import clean_state

MAX_SESSIONS = 16
TOKEN_RE = re.compile(r"^[A-Za-z0-9_-]{30,128}$")
TICK_SECONDS = 0.2             # 5 physics state updates per second over SSE
INACTIVITY_SECONDS = 120
SESSION_LIFETIME = 3600
_lock = threading.RLock()
_sessions = {}
_metrics = {"created": 0, "sse_messages": 0, "sse_bytes": 0, "input_messages": 0}


def _cleanup(now):
    for key, sess in list(_sessions.items()):
        if now - sess["activity"] > INACTIVITY_SECONDS or now - sess["created"] > SESSION_LIFETIME:
            _sessions.pop(key, None)


def _require(token):
    if not isinstance(token, str) or not TOKEN_RE.fullmatch(token):
        raise ValueError("Invalid remote session")
    obj = _sessions.get(token)
    if obj is None:
        raise KeyError("Unknown/expired remote session")
    return obj


def _configuration(world):
    track = world["track"]
    vehicle = world["vehicle"]
    road_width = float(track["roadWidth"])
    length = float(track["length"])
    max_speed = float(vehicle["maxSpeedKmh"]) / 3.6
    acceleration = float(vehicle["acceleration"])
    braking = float(vehicle["braking"])
    if not (4 <= road_width <= 100 and 200 <= length <= 100000 and 1 <= max_speed <= 200
            and 0 <= acceleration <= 100 and 0 <= braking <= 200):
        raise ValueError("Invalid world configuration")
    return {"width": road_width, "length": length, "max": max_speed,
            "accel": acceleration, "braking": braking}


def start(initial, world):
    initial = clean_state(initial)
    config = _configuration(world)
    now = time.monotonic()
    with _lock:
        _cleanup(now)
        if len(_sessions) >= MAX_SESSIONS:
            raise RuntimeError("Remote session capacity reached")
        token = secrets.token_urlsafe(32)
        _sessions[token] = {
            "state": initial, "config": config, "steer": 0.0,
            "gas": False, "brake": False, "last_input": now,
            "last_tick": now, "activity": now, "created": now
        }
        _metrics["created"] += 1
        return token


def input_controls(token, value):
    if not isinstance(value, dict):
        raise ValueError("Controls must be an object")
    steer = value.get("steer", 0)
    gas = value.get("gas", False)
    brake = value.get("brake", False)
    if (isinstance(steer, bool) or not isinstance(steer, (int, float))
            or not math.isfinite(steer) or not -1 <= steer <= 1):
        raise ValueError("Steering must be numeric between -1 and +1")
    if not isinstance(gas, bool) or not isinstance(brake, bool):
        raise ValueError("Gas/brake must be boolean")
    now = time.monotonic()
    with _lock:
        s = _require(token)
        s.update(steer=float(steer), gas=gas, brake=brake,
                 last_input=now, activity=now)
        _metrics["input_messages"] += 1


def sample(token):
    """Advance game physics on the Linux CPU; return rounded state numbers."""
    now = time.monotonic()
    with _lock:
        s = _require(token)
        dt = min(0.4, max(0.0, now - s["last_tick"]))
        s["last_tick"] = now
        s["activity"] = now
        v = s["state"]
        conf = s["config"]
        # Stop acting on stale input if a client has lost its connection.
        valid = now - s["last_input"] < 1
        gas = s["gas"] if valid else False
        brake = s["brake"] if valid else False
        steer = s["steer"] if valid else 0.0
        speed = max(0.0, min(conf["max"], v["velocity"] +
                             dt * (conf["accel"] * gas - conf["braking"] * brake - 0.4)))
        x = max(-conf["width"] / 2 + 1.2, min(conf["width"] / 2 - 1.2,
                                             v["x"] + steer * speed * 0.30 * dt))
        z = v["z"] + speed * dt
        if z > conf["length"] - 50:
            z = 0.0
        v.update(x=round(x, 4), z=round(z, 4), velocity=round(speed, 4),
                 distance=round(v["distance"] + speed * dt, 4))
        return dict(v)


def stop(token):
    with _lock:
        if not isinstance(token, str) or not TOKEN_RE.fullmatch(token):
            raise ValueError("Invalid remote session")
        return _sessions.pop(token, None) is not None


def sse_sent(size):
    with _lock:
        _metrics["sse_bytes"] += size
        _metrics["sse_messages"] += 1


def metrics():
    with _lock:
        return dict(_metrics, active_sessions=len(_sessions), server_gpu=False,
                    server_video_frames=0, state_rate_hz=5)
