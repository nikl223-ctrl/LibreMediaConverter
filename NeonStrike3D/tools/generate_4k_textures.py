#!/usr/bin/env python3
"""RIVERLANDS 4K graphics worker.

Generates original, tileable-looking 4096x4096 photographic-inspired diffuse
textures. Also produces 2048x2048 mobile variants for reasonable GPU memory use.
Runs as a separate GitHub Actions job, before the Android APK worker.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import numpy as np
from PIL import Image, ImageFilter

NAMES = ("grass", "soil", "bark", "rock", "water")
SEEDS = {"grass": 402, "soil": 223, "bark": 619, "rock": 720, "water": 826}

def cloud_noise(size: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Smoothed multilayer noise, generated without third-party texture files."""
    array = rng.integers(0, 256, (cells, cells), dtype=np.uint8)
    im = Image.fromarray(array, "L").resize((size, size), Image.Resampling.BICUBIC)
    return np.asarray(im, dtype=np.float32) / 255.0

def make_map(name: str, size: int) -> Image.Image:
    rng = np.random.default_rng(SEEDS[name])
    print(f"Rendering {name} at {size}x{size}", flush=True)
    coarse = cloud_noise(size, 18, rng)
    middle = cloud_noise(size, 76, rng)
    detail = cloud_noise(size, 310, rng)
    micro = rng.random((size, size), dtype=np.float32)
    noise = 0.39 * coarse + 0.28 * middle + 0.19 * detail + 0.14 * micro
    del coarse, middle, detail, micro
    yy, xx = np.ogrid[:size, :size]
    x = np.asarray(xx / size, dtype=np.float32)
    y = np.asarray(yy / size, dtype=np.float32)
    if name == "grass":
        wave = np.sin((x * 680 + y * 155) * (2.0 * np.pi)) * 0.022
        value = np.clip(noise * 0.91 + wave, 0.0, 1.0)
        r = 26 + 74 * value
        g = 49 + 112 * value
        b = 21 + 61 * value
    elif name == "soil":
        pebbles = np.where(noise > 0.72, 29, 0)
        r = 58 + 112 * noise + pebbles
        g = 53 + 91 * noise + pebbles
        b = 39 + 67 * noise + pebbles
    elif name == "bark":
        grain = np.sin((x * 109 + noise * 8.0) * np.pi) * 0.16
        fissure = np.where(grain < -0.10, -0.22, 0.0)
        value = np.clip(noise + grain + fissure, 0.0, 1.0)
        r = 46 + 101 * value
        g = 35 + 76 * value
        b = 24 + 60 * value
    elif name == "rock":
        seam = np.sin(y * 52.0 * np.pi + noise * 12.0) * 0.075
        value = np.clip(noise + seam, 0.0, 1.0)
        r = 61 + 115 * value
        g = 66 + 111 * value
        b = 65 + 104 * value
    else:
        ripples = np.sin((y * 172.0 + noise * 5.0 + x * 6.0) * np.pi) * 0.095
        value = np.clip(noise * 0.78 + ripples, 0.0, 1.0)
        r = 66 + 127 * value
        g = 70 + 123 * value
        b = 66 + 105 * value
    rgb = np.empty((size, size, 3), dtype=np.uint8)
    rgb[:, :, 0] = np.clip(r, 0, 255).astype(np.uint8)
    rgb[:, :, 1] = np.clip(g, 0, 255).astype(np.uint8)
    rgb[:, :, 2] = np.clip(b, 0, 255).astype(np.uint8)
    del noise
    return Image.fromarray(rgb, "RGB")

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("NeonStrike3D/assets/generated"))
    parser.add_argument("--master", type=Path, default=Path("master_textures"))
    parser.add_argument("--size", type=int, default=4096)
    parser.add_argument("--mobile-size", type=int, default=2048)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    args.master.mkdir(parents=True, exist_ok=True)
    if args.size != 4096:
        raise SystemExit("4K texture worker requires 4096x4096 masters")
    for name in NAMES:
        image = make_map(name, args.size)
        master = args.master / f"{name}_4k.jpg"
        image.save(master, "JPEG", quality=89, optimize=True, subsampling=0)
        mobile = image.resize((args.mobile_size, args.mobile_size), Image.Resampling.LANCZOS)
        mobile_path = args.out / f"{name}_mobile.jpg"
        mobile.save(mobile_path, "JPEG", quality=87, optimize=True, subsampling=0)
        print(f"{master}: {master.stat().st_size // 1024} KiB; "
              f"{mobile_path}: {mobile_path.stat().st_size // 1024} KiB", flush=True)
        del image, mobile
    assert len(list(args.master.glob("*_4k.jpg"))) == 5
    assert len(list(args.out.glob("*_mobile.jpg"))) == 5
    print("4K texture worker completed 5 master materials and 5 mobile textures")

if __name__ == "__main__":
    main()
