#!/usr/bin/env python3
"""Read a user's own ATS TAR from Google Drive and publish metadata-only inventory.

Never uploads original game files, extracted DLC resources, or OAuth credentials.
"""
import io
import json
import os
import re
import tarfile
import time
import zipfile
from pathlib import Path

import requests
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials

FILE_ID = os.environ.get("ATS_DRIVE_FILE_ID", "1Wy4wO6NDJadF7EvZqiu-0zTU-tdiswAq")
OUT = Path("ats-analysis")
OUT.mkdir(exist_ok=True)
RESULT = {"file_id": FILE_ID, "status": "starting", "tar_entries": 0,
          "matching_entries": [], "scs_archives": [], "warnings": []}
INTERESTING = re.compile(r"ford|road.?trip|car.?mode|physics|vehicle|chassis|suspension", re.I)
MAX_NESTED_SIZE = 600 * 1024 * 1024
MAX_SCS_COPIES = 6


def credentials():
    mapping = {"client_id": "GOOGLE_CLIENT_ID", "client_secret": "GOOGLE_CLIENT_SECRET",
               "refresh_token": "GOOGLE_REFRESH_TOKEN"}
    missing = [name for name in mapping.values() if not os.getenv(name)]
    if missing:
        raise RuntimeError("Missing GitHub secrets: " + ", ".join(missing))
    token = Credentials(
        token=None,
        refresh_token=os.environ["GOOGLE_REFRESH_TOKEN"],
        token_uri="https://oauth2.googleapis.com/token",
        client_id=os.environ["GOOGLE_CLIENT_ID"],
        client_secret=os.environ["GOOGLE_CLIENT_SECRET"])
    token.refresh(Request())
    return token.token


def metadata_only_zip(path, result):
    try:
        with zipfile.ZipFile(path) as archive:
            names = archive.namelist()
            result["format"] = "zip"
            result["contained_paths"] = len(names)
            result["relevant_paths"] = [name[:260] for name in names
                                        if INTERESTING.search(name) or name.lower().startswith("def/")][:400]
            keys = set()
            for name in names:
                if not name.lower().endswith((".sii", ".sui")):
                    continue
                info = archive.getinfo(name)
                if info.file_size > 2000000:
                    continue
                with archive.open(name) as fh:
                    for line in fh.read().decode("utf-8", "replace").splitlines():
                        line = line.partition("#")[0].strip()
                        if ":" in line:
                            keys.add(line.split(":", 1)[0].strip()[:100])
            result["definition_keys"] = sorted(keys)[:400]
    except Exception as exc:
        result["warning"] = "ZIP listing failed: " + str(exc)[:220]


def inspect_archive(member, source, count):
    entry = {"path": member.name[:350], "size": member.size}
    RESULT["scs_archives"].append(entry)
    if count >= MAX_SCS_COPIES or member.size > MAX_NESTED_SIZE:
        entry["note"] = "not copied to runner: size/count limit"
        return
    handle = source.extractfile(member)
    if handle is None:
        entry["note"] = "not a regular readable file"
        return
    # Temporary local-only file. Do not include it in uploaded artifacts.
    target = Path("/tmp") / ("ats-inspect-" + str(count) + ".scs")
    remaining = member.size
    with target.open("wb") as output:
        while remaining:
            buf = handle.read(min(1024 * 1024, remaining))
            if not buf:
                raise RuntimeError("Truncated nested SCS: " + member.name)
            output.write(buf)
            remaining -= len(buf)
    with target.open("rb") as fh:
        header = fh.read(8)
    entry["header"] = header[:4].hex()
    entry["format"] = "zip" if header.startswith(b"PK") else "SCS HashFS" if header.startswith(b"SCS#") else "unknown"
    if entry["format"] == "zip":
        metadata_only_zip(target, entry)
    # HashFS needs an SCS-aware unpacker; do not guess at its entries.
    elif entry["format"] == "SCS HashFS":
        entry["note"] = "HashFS archive: SCS-aware extractor needed for internal definitions"
    target.unlink(missing_ok=True)


def main():
    access_token = credentials()
    base = "https://www.googleapis.com/drive/v3/files/" + FILE_ID
    head = {"Authorization": "Bearer " + access_token, "Accept-Encoding": "identity"}
    with requests.Session() as session:
        info = session.get(base, headers=head, params={"fields": "id,name,size,mimeType"}, timeout=90)
        info.raise_for_status()
        RESULT["drive_file"] = info.json()
        print("Drive authenticated:", RESULT["drive_file"].get("name"), flush=True)
        with session.get(base, headers=head, params={"alt": "media"}, stream=True,
                         timeout=(40, 180)) as response:
            response.raise_for_status()
            ctype = response.headers.get("Content-Type", "")
            if "text/html" in ctype:
                raise RuntimeError("Drive returned HTML, not TAR bytes")
            response.raw.decode_content = True
            selected = 0
            tick = time.monotonic()
            RESULT["status"] = "streaming_tar"
            with tarfile.open(fileobj=response.raw, mode="r|*") as archive:
                for member in archive:
                    RESULT["tar_entries"] += 1
                    name = member.name
                    basename = name.rsplit("/", 1)[-1].lower()
                    if (INTERESTING.search(name) or basename in ("def.scs", "core.scs")) and len(RESULT["matching_entries"]) < 4000:
                        RESULT["matching_entries"].append({"path": name[:350], "size": member.size})
                    is_scs = basename.endswith(".scs")
                    relevant = (("ford" in name.lower() or "roadtrip" in name.lower()
                                or "road_trip" in name.lower()) or basename in ("def.scs", "core.scs"))
                    if member.isfile() and is_scs and relevant:
                        inspect_archive(member, archive, selected)
                        selected += 1
                    if time.monotonic() - tick > 30:
                        print("Scanned TAR entries:", RESULT["tar_entries"], "SCS candidates:", selected, flush=True)
                        tick = time.monotonic()
            RESULT["status"] = "complete"
    print("ATS_TAR_SCAN_COMPLETE entries=" + str(RESULT["tar_entries"]), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        RESULT["status"] = "failed"
        RESULT["warnings"].append(type(exc).__name__ + ": " + str(exc)[:500])
        print("ATS_TAR_SCAN_ERROR:", RESULT["warnings"][-1], flush=True)
    finally:
        (OUT / "inventory.json").write_text(json.dumps(RESULT, indent=2), encoding="utf-8")
        print("ATS_TAR_SCAN_RESULT:", RESULT["status"], flush=True)
    if RESULT["status"] != "complete":
        raise SystemExit(1)
