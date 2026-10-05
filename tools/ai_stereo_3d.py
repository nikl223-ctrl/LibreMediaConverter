#!/usr/bin/env python3
import argparse
import os
import subprocess
import sys
import time

import cv2
import numpy as np
import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModelForDepthEstimation


def read_exact(stream, size):
    chunks = []
    remaining = size
    while remaining:
        chunk = stream.read(remaining)
        if not chunk:
            return None
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def make_stereo(frame_rgb, depth, strength_px, prev_depth=None, prev_frame=None):
    h, w = frame_rgb.shape[:2]

    # Depth Anything V2 relative depth: larger values are nearer.
    lo, hi = np.percentile(depth, (2.0, 98.0))
    denom = max(float(hi - lo), 1e-6)
    near = np.clip((depth - lo) / denom, 0.0, 1.0).astype(np.float32)

    # Temporal smoothing reduces depth shimmer, but reset on a hard scene cut.
    if prev_depth is not None and prev_frame is not None:
        small_a = cv2.resize(frame_rgb, (160, 90), interpolation=cv2.INTER_AREA)
        small_b = cv2.resize(prev_frame, (160, 90), interpolation=cv2.INTER_AREA)
        scene_delta = float(np.mean(np.abs(small_a.astype(np.float32) - small_b.astype(np.float32))))
        if scene_delta < 35.0:
            near = 0.72 * prev_depth + 0.28 * near

    # Smooth the disparity field to avoid tearing around fine depth noise.
    near = cv2.GaussianBlur(near, (0, 0), 1.6)

    # Put the median scene depth close to the virtual screen plane.
    zero = float(np.median(near))
    disparity = (near - zero) * (2.0 * strength_px)
    disparity = np.clip(disparity, -strength_px, strength_px)
    disparity = cv2.GaussianBlur(disparity, (0, 0), 0.9)

    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)

    # Backward warping. Near objects receive crossed disparity and appear forward;
    # far objects receive uncrossed disparity and appear behind the screen.
    left_map_x = xx + disparity * 0.5
    right_map_x = xx - disparity * 0.5

    left = cv2.remap(
        frame_rgb, left_map_x, yy, cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REFLECT101
    )
    right = cv2.remap(
        frame_rgb, right_map_x, yy, cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REFLECT101
    )

    stereo = np.concatenate((left, right), axis=1)
    return stereo, near


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--start", type=float, default=300.0)
    p.add_argument("--duration", type=float, default=45.0)
    p.add_argument("--width", type=int, default=1280)
    p.add_argument("--height", type=int, default=720)
    p.add_argument("--fps", type=int, default=30)
    p.add_argument("--strength", type=float, default=0.018,
                   help="Maximum disparity as fraction of one-eye width")
    args = p.parse_args()

    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")

    device = (
        "mps" if torch.backends.mps.is_available()
        else "cuda" if torch.cuda.is_available()
        else "cpu"
    )
    print(f"DEPTH_DEVICE={device}", flush=True)

    model_id = "depth-anything/Depth-Anything-V2-Small-hf"
    processor = AutoImageProcessor.from_pretrained(model_id)
    model = AutoModelForDepthEstimation.from_pretrained(model_id)
    model.to(device)
    model.eval()

    vf = (
        f"scale={args.width}:{args.height}:"
        "force_original_aspect_ratio=decrease,"
        f"pad={args.width}:{args.height}:(ow-iw)/2:(oh-ih)/2,"
        "setsar=1"
    )

    decode = subprocess.Popen([
        "ffmpeg", "-hide_banner", "-loglevel", "error",
        "-ss", str(args.start), "-t", str(args.duration),
        "-i", args.input,
        "-vf", vf,
        "-r", str(args.fps),
        "-an",
        "-pix_fmt", "rgb24",
        "-f", "rawvideo", "pipe:1"
    ], stdout=subprocess.PIPE)

    out_w = args.width * 2
    encode_cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "warning",
        "-f", "rawvideo", "-pix_fmt", "rgb24",
        "-s", f"{out_w}x{args.height}",
        "-r", str(args.fps), "-i", "pipe:0",
        "-ss", str(args.start), "-t", str(args.duration),
        "-i", args.input,
        "-map", "0:v:0", "-map", "1:a:0?",
        "-c:v", "h264_videotoolbox",
        "-profile:v", "high",
        "-b:v", "18M", "-maxrate", "22M", "-bufsize", "36M",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "256k",
        "-metadata:s:v:0", "stereo_mode=left_right",
        "-movflags", "+faststart",
        "-shortest",
        args.output
    ]
    encode = subprocess.Popen(encode_cmd, stdin=subprocess.PIPE)

    frame_bytes = args.width * args.height * 3
    total_expected = max(1, int(args.duration * args.fps))
    strength_px = args.width * args.strength

    prev_depth = None
    prev_frame = None
    frame_no = 0
    started = time.time()

    try:
        while True:
            raw = read_exact(decode.stdout, frame_bytes)
            if raw is None:
                break

            frame = np.frombuffer(raw, dtype=np.uint8).reshape(args.height, args.width, 3).copy()
            image = Image.fromarray(frame)

            inputs = processor(images=image, return_tensors="pt")
            inputs = {k: v.to(device) for k, v in inputs.items()}

            with torch.inference_mode():
                outputs = model(**inputs)
                pred = outputs.predicted_depth.unsqueeze(1)
                pred = torch.nn.functional.interpolate(
                    pred,
                    size=(args.height, args.width),
                    mode="bicubic",
                    align_corners=False,
                )
                depth = pred.squeeze().float().cpu().numpy()

            stereo, smooth_depth = make_stereo(
                frame, depth, strength_px,
                prev_depth=prev_depth,
                prev_frame=prev_frame
            )

            encode.stdin.write(stereo.tobytes())
            prev_depth = smooth_depth
            prev_frame = frame
            frame_no += 1

            if frame_no == 1 or frame_no % 30 == 0:
                elapsed = max(time.time() - started, 1e-6)
                fps = frame_no / elapsed
                pct = min(frame_no / total_expected * 100.0, 100.0)
                eta = max(total_expected - frame_no, 0) / max(fps, 1e-6)
                print(
                    f"LIVE | {pct:5.1f}% | AI_FPS={fps:.2f} | "
                    f"FRAME={frame_no}/{total_expected} | ETA={eta:.0f}s",
                    flush=True,
                )

    finally:
        if decode.stdout:
            decode.stdout.close()
        if encode.stdin:
            encode.stdin.close()

    dec_rc = decode.wait()
    enc_rc = encode.wait()
    if dec_rc != 0:
        raise SystemExit(f"ffmpeg decoder failed: {dec_rc}")
    if enc_rc != 0:
        raise SystemExit(f"ffmpeg VideoToolbox encoder failed: {enc_rc}")
    if frame_no == 0:
        raise SystemExit("No frames decoded")

    print(f"DONE_FRAMES={frame_no}", flush=True)
    print(f"OUTPUT={args.output}", flush=True)


if __name__ == "__main__":
    main()
