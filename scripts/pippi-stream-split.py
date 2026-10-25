#!/usr/bin/env python3
"""Split a Google Drive video directly to Google Drive using FIFOs (no source or chunk files on disk).

A single GitHub-hosted runner downloads via Google Drive's authenticated streaming API.
ffmpeg performs lossless packet-copy segmentation into named pipes. Each pipe is
simultaneously uploaded through rclone rcat with upload backpressure. Only tiny
FIFO paths and a metadata manifest occupy local disk.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import threading

SOURCE_ID = "1MBBuUaVvFnetqgSer-Qs4lIAGnfoTR2p"
MAX_SEGMENTS = 80
SEGMENT_SECONDS = 600

def main():
    token = os.environ["ACCESS_TOKEN"]
    folder = os.environ["PART_FOLDER"]
    tempdir = Path(tempfile.mkdtemp(prefix="pippi-fifo-", dir=os.environ["RUNNER_TEMP"]))
    manifest = tempdir / "segments.txt"

    done = set()
    started = set()
    failures = []
    lock = threading.Lock()
    upload_threads = []

    def upload(index):
        path = tempdir / ("part_%03d.mkv" % index)
        # Blocks until ffmpeg writes the named pipe. Never creates an on-disk video.
        try:
            with path.open("rb", buffering=0) as reader:
                with lock:
                    started.add(index)
                remote = "drive:%s/input/part_%03d.mkv" % (folder, index)
                rc = subprocess.run(
                    ["rclone", "rcat", remote, "--drive-chunk-size", "32M",
                     "--stats", "30s", "--retries", "8", "--low-level-retries", "20"],
                    stdin=reader,
                    check=False,
                ).returncode
                if rc:
                    raise RuntimeError("Upload segment %03d returned %d" % (index, rc))
                with lock:
                    done.add(index)
        except Exception as exc:
            with lock:
                failures.append(str(exc))

    for index in range(MAX_SEGMENTS):
        os.mkfifo(tempdir / ("part_%03d.mkv" % index), 0o600)
        t = threading.Thread(target=upload, args=(index,), daemon=True)
        t.start()
        upload_threads.append(t)

    url = "https://www.googleapis.com/drive/v3/files/%s?alt=media" % SOURCE_ID
    curl = subprocess.Popen(
        ["curl", "--fail", "--location", "--silent", "--show-error",
         "--header", "Authorization: Bearer " + token, url],
        stdout=subprocess.PIPE,
    )
    try:
        cmd = [
            "ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "warning",
            "-stats_period", "30", "-i", "pipe:0",
            "-map", "0:v:0", "-map", "0:a:0", "-c", "copy",
            "-f", "segment", "-segment_time", str(SEGMENT_SECONDS),
            "-segment_format", "matroska", "-segment_format_options", "live=1",
            "-segment_list", str(manifest), "-segment_list_type", "flat",
            "-reset_timestamps", "1",
            str(tempdir / "part_%03d.mkv")
        ]
        print("Input: streamed Google Drive API -> ffmpeg copy split -> FIFO -> live rclone upload", flush=True)
        ffmpeg_rc = subprocess.run(cmd, stdin=curl.stdout, check=False).returncode
    finally:
        if curl.stdout:
            curl.stdout.close()
    curl_rc = curl.wait()
    if curl_rc or ffmpeg_rc:
        raise RuntimeError("Source stream/split failed (curl=%d, ffmpeg=%d)" %
                           (curl_rc, ffmpeg_rc))

    if not manifest.exists():
        raise RuntimeError("Segment manifest not created")
    names = [line.strip() for line in manifest.read_text().splitlines() if line.strip()]
    ids = []
    for name in names:
        match = re.fullmatch(r"part_(\d{3})\.mkv", Path(name).name)
        if not match:
            raise RuntimeError("Unexpected ffmpeg manifest entry: %s" % name)
        ids.append(int(match.group(1)))
    if not ids or ids != list(range(len(ids))):
        raise RuntimeError("Segments missing or out of order: %s" % ids)

    # ffmpeg has closed every produced pipe. Wait for all of its uploads to finish.
    for index in ids:
        upload_threads[index].join(timeout=1800)
    with lock:
        completed = set(done)
        errors = list(failures)
    if errors or completed != set(ids):
        raise RuntimeError("Some stream uploads did not finish: %s; finished=%s; expected=%s" %
                           (errors, sorted(completed), ids))

    json_ids = json.dumps(["%03d" % i for i in ids], separators=(",", ":"))
    with open(os.environ["GITHUB_OUTPUT"], "a") as f:
        f.write("parts=" + json_ids + "\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
        f.write("## Original read and split without local video storage\n")
        f.write("- Source streamed from Google Drive; %d FIFO parts uploaded while split\n" % len(ids))
        f.write("- Video data on local disk: 0 bytes (OS buffers and tiny manifest only)\n")
    print("Uploaded %d lossless source segments: %s" % (len(ids), json_ids), flush=True)

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("::error::" + str(exc), file=sys.stderr, flush=True)
        sys.exit(1)
