#!/usr/bin/env python3
"""BSLB visual-quality experiment: reversible, profile-preserving texture variants."""
import argparse, hashlib, io, json, pathlib, uuid, zipfile
from PIL import Image

SKY_HINTS = ("cubemap", "skybox", "sky/", "skies/")
def sky_candidate(name, image):
    p = name.lower().replace("\\", "/")
    return image.width == 2048 and image.height == 2048 and any(h in p for h in SKY_HINTS)

def shard(original, output, index):
    output = pathlib.Path(output)
    counts = {"processed": 0, "sky": 0, "lossless": 0}
    with zipfile.ZipFile(original) as z:
        for info in z.infolist():
            name = info.filename
            if not name.lower().endswith(".png"):
                continue
            if int(hashlib.sha256(name.encode()).hexdigest(), 16) % 20 != index:
                continue
            with Image.open(io.BytesIO(z.read(info))) as im:
                im.load()
                is_sky = sky_candidate(name, im)
                for mode in ("performance", "4k-test"):
                    target = im
                    if is_sky:
                        dim = 1024 if mode == "performance" else 4096
                        target = im.resize((dim, dim), Image.Resampling.LANCZOS)
                    data = io.BytesIO()
                    target.save(data, format="PNG", optimize=True)
                    dest = output / mode / name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(data.getvalue())
                counts["processed"] += 1
                counts["sky"] += int(is_sky)
                counts["lossless"] += int(not is_sky)
    print(json.dumps({"shard": index, **counts}))

def assemble(original, overlay, output, mode):
    output = pathlib.Path(output)
    overlay = pathlib.Path(overlay) / mode
    output.parent.mkdir(parents=True, exist_ok=True)
    altered = 0
    with zipfile.ZipFile(original) as source, zipfile.ZipFile(output, "w") as dest:
        for entry in source.infolist():
            if entry.is_dir():
                dest.writestr(entry, b"")
                continue
            data = source.read(entry)
            replacement = overlay / entry.filename
            if replacement.is_file():
                data = replacement.read_bytes()
                altered += 1
            if entry.filename.endswith("manifest.json"):
                try:
                    manifest = json.loads(data)
                    manifest["header"]["name"] = manifest["header"].get("name", "BSLB") + " - " + mode
                    manifest["header"]["uuid"] = str(uuid.uuid5(uuid.NAMESPACE_URL, "bslb-test-" + mode))
                    for i, module in enumerate(manifest.get("modules", [])):
                        module["uuid"] = str(uuid.uuid5(uuid.NAMESPACE_URL, "bslb-test-" + mode + "-module-" + str(i)))
                    data = json.dumps(manifest, indent=2).encode()
                except (ValueError, KeyError, TypeError):
                    pass
            dest.writestr(entry, data)
    with zipfile.ZipFile(output) as check:
        assert check.testzip() is None
    print(mode, "replaced", altered, "files", "output", output, output.stat().st_size)

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("command", choices=["shard", "assemble"])
    p.add_argument("--original", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--index", type=int)
    p.add_argument("--overlay")
    p.add_argument("--mode", choices=["performance", "4k-test"])
    args = p.parse_args()
    if args.command == "shard":
        assert args.index is not None
        shard(args.original, args.output, args.index)
    else:
        assert args.overlay and args.mode
        assemble(args.original, args.overlay, args.output, args.mode)
