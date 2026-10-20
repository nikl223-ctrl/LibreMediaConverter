#!/usr/bin/env python3
"""Convert one of 20 disjoint batches of *owned* LEGO TCS PC standalone DDS assets.
No game asset is ever committed to GitHub or uploaded as an Actions artifact.
Produces private Drive-ready per-worker ZIP and JSON manifest only.
"""
import argparse
import hashlib
import io
import json
import os
import sys
import zipfile
from pathlib import Path

from PIL import Image, UnidentifiedImageError

Image.MAX_IMAGE_PIXELS = 45_000_000

def digest(data):
    return hashlib.sha256(data).hexdigest()

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--source", required=True, help="the owner's GAME.DAT")
    p.add_argument("--output", required=True, help="local temporary chunk ZIP")
    p.add_argument("--worker", type=int, required=True)
    p.add_argument("--workers", type=int, default=20)
    p.add_argument("--max-dimension", type=int, default=4096)
    p.add_argument("--scale", type=int, default=4)
    args = p.parse_args()
    if not (1 <= args.workers <= 100 and 0 <= args.worker < args.workers):
        p.error("invalid worker index/count")
    if not (512 <= args.max_dimension <= 4096 and args.scale in (2,4)):
        p.error("invalid upscale options")
    from ttdat import DatArchive
    arc=DatArchive(args.source)
    dds=sorted((e for e in arc.entries if e.path.lower().endswith(".dds")),key=lambda e:e.path.casefold())
    selected=[(index,e) for index,e in enumerate(dds) if index%args.workers==args.worker]
    report={"worker":args.worker,"workers":args.workers,"source":"GAME.DAT",
            "source_index_version":arc.version,
            "source_total_standalone_dds":len(dds),
            "max_dimension":args.max_dimension,"upscale_factor":args.scale,
            "pipeline":"RGBA-aware Pillow Lanczos CPU; offline preparation; NOT AI and NOT live rendering",
            "files":[],"errors":[]}
    output=Path(args.output)
    output.parent.mkdir(parents=True,exist_ok=True)
    with zipfile.ZipFile(output,"w",compression=zipfile.ZIP_STORED,allowZip64=True) as z:
        for index,entry in selected:
            try:
                raw=arc.read(entry)
                with Image.open(io.BytesIO(raw)) as original:
                    original.load()
                    if original.width>8192 or original.height>8192:
                        raise ValueError("source exceeds resource guard")
                    w,h=original.size
                    # Preserve intentional transparency including UI cutouts.
                    rgba=original.convert("RGBA")
                dest_w=min(args.max_dimension,w*args.scale)
                dest_h=min(args.max_dimension,h*args.scale)
                ratio=min(dest_w/w,dest_h/h)
                dest_w=max(1,round(w*ratio));dest_h=max(1,round(h*ratio))
                if (dest_w,dest_h)!=(w,h):
                    rgba=rgba.resize((dest_w,dest_h),resample=Image.Resampling.LANCZOS)
                buffer=io.BytesIO()
                rgba.save(buffer,format="PNG",optimize=True)
                png=buffer.getvalue()
                name=f"textures/asset_{index:05d}.png"
                z.writestr(name,png)
                report["files"].append({"source_path":entry.path,"id":index,"output":name,
                    "source_size":[w,h],"output_size":[dest_w,dest_h],"alpha":True,
                    "source_sha256":digest(raw),"output_sha256":digest(png)})
                del rgba,png,buffer,raw
            except (OSError,ValueError,RuntimeError,UnidentifiedImageError) as error:
                report["errors"].append({"source_path":entry.path,"error":str(error)[:180]})
        # Self-contained, verified mapping: later engine import can map every texture.
        report["converted"]=len(report["files"])
        report["failed"]=len(report["errors"])
        z.writestr("manifest.json",json.dumps(report,indent=2,ensure_ascii=False))
    # Fail on empty/unsupported batches so the merge job will not pretend success.
    print(f"WORKER_INDEX={args.worker}")
    print(f"GAME_ARCHIVE_STANDALONE_DDS={len(dds)}")
    print(f"WORKER_SOURCE_COUNT={len(selected)}")
    print(f"WORKER_CONVERTED={report['converted']}")
    print(f"WORKER_FAILED={report['failed']}")
    print(f"OUTPUT_CHUNK_BYTES={output.stat().st_size}")
    print("OFFLINE_CPU_UPSCALE_ONLY=yes; NATIVE_GAME_MOD_READY=no")
    if report["converted"]==0: raise RuntimeError("No valid textures were converted")
    if report["failed"]: print("WARNING: Some DDS files require special-format fallback",file=sys.stderr)
    return 0

if __name__=="__main__":
    sys.exit(main())
