#!/usr/bin/env python3
"""Faithful high-resolution BSLB PBR texture upscale with vanilla Minecraft clouds.

This is a resolution upscale of source artwork, not invented native 4K source detail.
Square block/material tiles get edge-preserving processing; animation strips, UI,
water animation, sky, colormaps, and non-texture metadata stay unchanged.
"""
import argparse
import hashlib
import io
import json
import pathlib
import uuid
import zipfile

from PIL import Image, ImageFilter

SHARDS = 20
QUALITY_KEYWORDS = (
    "stone", "grass", "dirt", "sand", "brick", "log", "plank", "leaves",
    "wood", "ore", "deepslate", "cobble", "netherrack", "concrete",
    "moss", "mud", "snow", "ice", "wool", "copper", "iron", "gold",
    "diamond", "emerald", "quartz", "glass",
)


def is_cloud_or_static_sky(name):
    p = name.lower().replace("\\", "/")
    return (
        p == "textures/environment/clouds.png"
        or p.endswith("/textures/environment/clouds.png")
        or "/textures/environment/overworld_cubemap/" in p
        or p == "cubemaps/default_cubemap.json"
    )


def is_block_texture(name):
    n = name.lower().replace("\\", "/")
    return (
        n.startswith("subpacks/")
        and "/textures/blocks/" in n
        and n.endswith((".png", ".tga"))
    )


def upscaled_tile(name, raw):
    with Image.open(io.BytesIO(raw)) as original:
        original.load()
        # Non-square sprite sheets are animations: scaling them may break frames
        # and cause serious VRAM overhead. Preserve their exact original layout.
        if original.size not in ((16, 16), (32, 32)):
            return None, None
        high = any(k in pathlib.PurePosixPath(name.lower()).stem for k in QUALITY_KEYWORDS)
        side = 256 if high else 128
        mode = original.mode
        if mode in ("1", "P"):
            original = original.convert("RGBA")
        elif mode not in ("RGB", "RGBA", "L", "LA"):
            original = original.convert("RGBA")
        basename = name.lower()
        material = (
            "_heightmap." in basename
            or "_mers." in basename
            or "_normal." in basename
            or "_normal_" in basename
        )
        if "_mers." in basename:
            method = Image.Resampling.NEAREST  # Preserve PBR channel semantics.
        elif material:
            method = Image.Resampling.BICUBIC
        else:
            method = Image.Resampling.LANCZOS
        image = original.resize((side, side), method)
        if not material:
            # Restore edge definition after scaling without changing the base palette.
            if image.mode == "RGBA":
                alpha = image.getchannel("A")
                rgb = image.convert("RGB").filter(
                    ImageFilter.UnsharpMask(radius=1.2, percent=90, threshold=2)
                )
                image = rgb.convert("RGBA")
                image.putalpha(alpha)
            elif image.mode in ("RGB", "L"):
                image = image.filter(
                    ImageFilter.UnsharpMask(radius=1.2, percent=90, threshold=2)
                )
        buf = io.BytesIO()
        ext = pathlib.PurePosixPath(name).suffix.lower()
        if ext == ".png":
            image.save(buf, format="PNG", compress_level=6)
        else:
            image.save(buf, format="TGA", rle=True)
        return buf.getvalue(), side


def shard(source, output, index):
    out = pathlib.Path(output)
    counts = {"processed": 0, "upscaled128": 0, "upscaled256": 0,
              "skipped_animated_or_nonsquare": 0, "total_output_bytes": 0}
    with zipfile.ZipFile(source) as original:
        for info in original.infolist():
            name = info.filename
            if not is_block_texture(name):
                continue
            if int(hashlib.sha256(name.encode("utf-8")).hexdigest(), 16) % SHARDS != index:
                continue
            data, size = upscaled_tile(name, original.read(info))
            if data is None:
                counts["skipped_animated_or_nonsquare"] += 1
                continue
            target = out / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            counts["processed"] += 1
            counts["upscaled256" if size == 256 else "upscaled128"] += 1
            counts["total_output_bytes"] += len(data)
    print("TEXTURE_SHARD_STATS " + json.dumps({"shard": index, **counts}, sort_keys=True))


def assemble(source, overlay, output):
    output = pathlib.Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    overlay = pathlib.Path(overlay)
    stats = {"upscaled": 0, "removed_static_sky_files": 0, "preserved": 0,
             "entries": 0, "upscaled_128": 0, "upscaled_256": 0}
    with zipfile.ZipFile(source) as original, zipfile.ZipFile(
        output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True
    ) as target:
        for entry in original.infolist():
            name = entry.filename
            if is_cloud_or_static_sky(name):
                stats["removed_static_sky_files"] += 1
                continue
            if entry.is_dir():
                continue
            replacement = overlay / name
            if replacement.is_file():
                data = replacement.read_bytes()
                stats["upscaled"] += 1
                with Image.open(io.BytesIO(data)) as img:
                    stats["upscaled_256" if img.width == 256 else "upscaled_128"] += 1
            else:
                data = original.read(entry)
                stats["preserved"] += 1
            if name == "manifest.json":
                manifest = json.loads(data)
                manifest["header"]["name"] = "BSLB Xbox Quality 4K - Vanilla Clouds"
                manifest["header"]["uuid"] = str(uuid.uuid5(
                    uuid.NAMESPACE_URL, "bslb-quality-vanilla-clouds-v2-header"))
                for i, module in enumerate(manifest.get("modules", [])):
                    module["uuid"] = str(uuid.uuid5(
                        uuid.NAMESPACE_URL, f"bslb-quality-vanilla-clouds-v2-module-{i}"))
                data = json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8")
            target.writestr(name, data)
            stats["entries"] += 1
    with zipfile.ZipFile(output) as result:
        if result.testzip() is not None:
            raise RuntimeError("ZIP verification failed")
        names = result.namelist()
        if "manifest.json" not in names:
            raise RuntimeError("Minecraft manifest missing")
        if any(is_cloud_or_static_sky(n) for n in names):
            raise RuntimeError("Static sky or cloud override remains")
    if stats["upscaled"] < 3000:
        raise RuntimeError("Too few high-resolution textures: missing render shards?")
    stats["bytes"] = output.stat().st_size
    report = output.with_suffix(".report.json")
    report.write_text(json.dumps(stats, indent=2) + "\n", encoding="utf-8")
    print("TEXTURE_FINAL_STATS " + json.dumps(stats, sort_keys=True))
    print("PACK_RENDERED_OK", str(output), output.stat().st_size, "bytes")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["shard", "assemble"])
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--index", type=int)
    parser.add_argument("--overlay")
    args = parser.parse_args()
    if args.command == "shard":
        if args.index is None or not 0 <= args.index < SHARDS:
            parser.error("shard requires --index 0..19")
        shard(args.source, args.output, args.index)
    else:
        if not args.overlay:
            parser.error("assemble requires --overlay")
        assemble(args.source, args.overlay, args.output)
