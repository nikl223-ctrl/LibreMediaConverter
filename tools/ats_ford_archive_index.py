#!/usr/bin/env python3
"""Index a user-owned ATS TAR from Drive via authenticated byte ranges.
Outputs only archive metadata and selected numeric physics values, never game assets.
"""
import json
import os
import re
import sys
import time
from pathlib import Path
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import AuthorizedSession

FILE_ID = os.getenv("ATS_DRIVE_FILE_ID", "1Wy4wO6NDJadF7EvZqiu-0zTU-tdiswAq")
WORKER = int(os.getenv("ATS_WORKER", "0"))
WORKERS = int(os.getenv("ATS_WORKERS", "10"))
CHUNK = 16 * 1024 * 1024
OUTPUT = Path("ats-reports")
OUTPUT.mkdir(exist_ok=True)
TARGET_WORDS = ("ford", "road_trip", "roadtrip", "physics", "vehicle", "chassis", "wheel", "tire", "car", "dlc", "def.scs", "base.scs")
PHYSICS_KEYS = ("kerb_weight", "residual_travel", "suspension", "steering", "torque", "friction", "stiffness", "spring", "damping", "mass", "weight", "center_of_mass", "anti_roll", "brake")
BASE = "https://www.googleapis.com/drive/v3/files/" + FILE_ID
report = {"worker": WORKER, "workers": WORKERS, "status": "starting", "archive": {}, "scanned_bytes": 0, "headers": 0, "entries": [], "archive_formats": [], "physics_values": [], "errors": []}

def save():
    (OUTPUT / ("worker-%02d.json" % WORKER)).write_text(json.dumps(report, indent=2), encoding="utf-8")

def auth():
    keys = ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REFRESH_TOKEN")
    if not all(os.getenv(k) for k in keys):
        raise RuntimeError("Existing video-converter Google OAuth secrets are missing")
    creds = Credentials(
        token=None,
        refresh_token=os.environ["GOOGLE_REFRESH_TOKEN"],
        token_uri="https://oauth2.googleapis.com/token",
        client_id=os.environ["GOOGLE_CLIENT_ID"],
        client_secret=os.environ["GOOGLE_CLIENT_SECRET"],
    )
    return AuthorizedSession(creds)

def part(session, start, end):
    last_error = None
    for attempt in range(4):
        try:
            response = session.get(BASE, params={"alt": "media"}, headers={"Range": "bytes=%d-%d" % (start, end)}, timeout=(30, 150))
            if response.status_code != 206:
                raise RuntimeError("Drive range request returned HTTP %s; content-type=%s" % (response.status_code, response.headers.get("Content-Type", "?")))
            content_range = response.headers.get("Content-Range", "")
            if not content_range.startswith("bytes %d-%d/" % (start, end)):
                raise RuntimeError("Unexpected Content-Range: " + content_range[:120])
            if len(response.content) != end - start + 1:
                raise RuntimeError("Partial Drive download: %d of %d bytes" % (len(response.content), end-start+1))
            return response.content
        except Exception as e:
            last_error = e
            if attempt < 3:
                time.sleep(2 ** attempt)
    raise RuntimeError(str(last_error))

def tar_header(block):
    if block[257:262] != b"ustar":
        return None
    try:
        expected = int(block[148:156].strip(b" \\0") or b"0", 8)
        actual = sum(block[:148]) + 8 * 32 + sum(block[156:])
        if actual != expected:
            return None
        size = int(block[124:136].strip(b" \\0") or b"0", 8)
        prefix = block[345:500].split(b"\\0", 1)[0]
        name = block[:100].split(b"\\0", 1)[0]
        if prefix:
            name = prefix + b"/" + name
        return name.decode("utf-8", "replace")[:400], size
    except (ValueError, OverflowError):
        return None

def analyze_small_text(session, name, size, offset):
    if size > 131072 or size == 0 or not name.lower().endswith((".sii", ".sui")):
        return
    content = part(session, offset + 512, offset + 511 + size).decode("utf-8", "replace")
    for line in content.splitlines():
        stripped = line.strip()
        if ":" not in stripped or stripped.startswith("#"):
            continue
        key, value = stripped.split(":", 1)
        if any(k in key.lower() for k in PHYSICS_KEYS):
            value = value.strip().split("#",1)[0].strip()
            if re.fullmatch(r"[0-9eE+\\-. ,()]+", value) and len(report["physics_values"]) < 200:
                report["physics_values"].append({"file": name, "key": key.strip()[:90], "value": value[:110]})

try:
    session = auth()
    resp = session.get(BASE, params={"fields": "id,name,size,mimeType"}, timeout=50)
    resp.raise_for_status()
    metadata = resp.json()
    total = int(metadata["size"])
    report["archive"] = metadata
    if WORKER < 0 or WORKER >= WORKERS or total < 512:
        raise RuntimeError("Invalid worker or archive metadata")
    segment = ((total + WORKERS - 1) // WORKERS + 511) // 512 * 512
    lo = min(WORKER * segment, total)
    hi = min((WORKER + 1) * segment, total)
    report["segment"] = {"begin": lo, "end_exclusive": hi}
    probe = part(session, lo, min(lo+511, hi-1))
    report["status"] = "scanning"
    start_time = time.monotonic()
    position = lo
    while position < hi:
        end = min(position + CHUNK, hi) - 1
        data = part(session, position, end)
        for rel in range(0, len(data)-511, 512):
            header = tar_header(data[rel:rel+512])
            if header is None:
                continue
            name, size = header
            offset = position + rel
            report["headers"] += 1
            if len(report["entries"]) < 40000:
                report["entries"].append({"path": name, "size": size, "tar_offset": offset})
            low = name.lower()
            if any(word in low for word in TARGET_WORDS):
                if name.lower().endswith((".sii", ".sui")):
                    try:
                        analyze_small_text(session, name, size, offset)
                    except Exception as e:
                        report["errors"].append("Text read %s: %s" % (name[:70], str(e)[:90]))
                if name.lower().endswith(".scs") and len(report["archive_formats"]) < 500:
                    try:
                        signature = part(session, offset+512, offset+519)
                        magic = "SCS#" if signature.startswith(b"SCS#") else "ZIP" if signature.startswith(b"PK") else signature.hex()
                        report["archive_formats"].append({"path": name, "format": magic, "size": size, "tar_offset": offset})
                    except Exception as e:
                        report["errors"].append("SCS probe %s: %s" % (name[:70], str(e)[:90]))
        report["scanned_bytes"] += len(data)
        position = end + 1
        if (position - lo) // CHUNK % 12 == 0:
            print("Worker %d: %.1f/%.1f GiB, %d TAR headers" % (WORKER, report["scanned_bytes"]/1073741824, (hi-lo)/1073741824, report["headers"]), flush=True)
        if time.monotonic() - start_time > 4.8 * 3600:
            raise RuntimeError("Worker timeout budget exceeded")
    report["status"] = "complete"
except Exception as e:
    report["status"] = "failed"
    report["errors"].append(str(e)[:500])
finally:
    save()
    print("ATS_SCAN_RESULT " + json.dumps({k: report[k] for k in ("worker","status","scanned_bytes","headers","errors")}, ensure_ascii=False), flush=True)
sys.exit(0 if report["status"] == "complete" else 1)
