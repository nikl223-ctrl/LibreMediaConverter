#!/usr/bin/env python3
"""Download only the two verified SCS payloads from the user's Drive TAR.

Uses exact offsets reported by the authenticated ten-worker inventory.
Files stay inside the GitHub runner and are NOT uploaded as build artifacts.
"""
import hashlib
import json
import os
from pathlib import Path
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import AuthorizedSession

FILE_ID = "1Wy4wO6NDJadF7EvZqiu-0zTU-tdiswAq"
BASE = "https://www.googleapis.com/drive/v3/files/" + FILE_ID
TARGETS = [
    ("ford.scs", 9792216064, 142133824),
    ("def.scs", 9627129856, 11310024),
]
root = Path("game-assets")
root.mkdir(exist_ok=True)
secrets = ("GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET", "GOOGLE_REFRESH_TOKEN")
missing = [key for key in secrets if not os.environ.get(key)]
if missing:
    raise SystemExit("Missing GitHub video converter OAuth secrets: " + ", ".join(missing))
cred = Credentials(
    token=None,
    refresh_token=os.environ["GOOGLE_REFRESH_TOKEN"],
    token_uri="https://oauth2.googleapis.com/token",
    client_id=os.environ["GOOGLE_CLIENT_ID"],
    client_secret=os.environ["GOOGLE_CLIENT_SECRET"],
)
session = AuthorizedSession(cred)
m = session.get(BASE, params={"fields":"size,name,mimeType"}, timeout=40)
m.raise_for_status()
meta = m.json()
if int(meta["size"]) != 34745364480:
    raise SystemExit("ATS TAR size changed; refusing obsolete byte offsets")
result = []
for name, tar_offset, size in TARGETS:
    start = tar_offset + 512
    end = start + size - 1
    dest = root / name
    response = session.get(BASE, params={"alt":"media"}, headers={"Range":f"bytes={start}-{end}"}, stream=True, timeout=(30,180))
    if response.status_code != 206 or not response.headers.get("Content-Range","").startswith(f"bytes {start}-{end}/"):
        raise SystemExit(f"{name}: authenticated byte-range request failed: HTTP {response.status_code}")
    h = hashlib.sha256()
    length = 0
    with dest.open("wb") as f:
        for chunk in response.iter_content(chunk_size=1024*1024):
            if chunk:
                f.write(chunk)
                length += len(chunk)
                h.update(chunk)
    response.close()
    if length != size:
        dest.unlink(missing_ok=True)
        raise SystemExit(f"{name}: expected {size} bytes, got {length}")
    with dest.open("rb") as f:
        signature = f.read(4)
    if signature not in (b"SCS#", b"PK\x03\x04"):
        raise SystemExit(f"{name}: unexpected SCS signature {signature.hex()}")
    entry = {"name": name, "size":size, "sha256":h.hexdigest(),"signature":signature.hex()}
    result.append(entry)
    print("TARGET_VERIFIED",json.dumps(entry),flush=True)
Path("target-metadata.json").write_text(json.dumps(result,indent=2),encoding="utf-8")
