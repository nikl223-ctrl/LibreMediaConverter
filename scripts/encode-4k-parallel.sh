#!/usr/bin/env bash
set -euo pipefail

MODE="${1:?mode required: encode|merge}"
SOURCE="${SOURCE:-/tmp/source.mp4}"
PARTS_DIR="${PARTS_DIR:-/tmp/parts}"
FINAL_FILE="${FINAL_FILE:-/tmp/final-4k.mp4}"
PART_COUNT="${PART_COUNT:-20}"
TARGET_BYTES="${TARGET_BYTES:-28500000000}"

mkdir -p "$PARTS_DIR"

if [[ "$MODE" == "encode" ]]; then
  PART="${PART:?PART required}"
  DURATION="${DURATION:-$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SOURCE")}"
  SEG=$(awk -v d="$DURATION" -v n="$PART_COUNT" 'BEGIN {printf "%.6f", d/n}')
  START=$(awk -v p="$PART" -v s="$SEG" 'BEGIN {printf "%.6f", p*s}')
  LENGTH="$SEG"
  if [[ "$PART" -eq $((PART_COUNT-1)) ]]; then
    LENGTH=$(awk -v d="$DURATION" -v s="$START" 'BEGIN {printf "%.6f", d-s}')
  fi
  AUDIO_KBPS=384
  VIDEO_KBPS=$(awk -v b="$TARGET_BYTES" -v d="$DURATION" -v a="$AUDIO_KBPS" 'BEGIN {t=(b*8/1000)/d; v=int(t-a-500); if(v<1000)v=1000; print v}')
  printf -v PN "%02d" "$PART"
  OUT="$PARTS_DIR/part_${PN}.mp4"
  ffmpeg -hide_banner -y -ss "$START" -i "$SOURCE" -t "$LENGTH"     -map 0:v:0 -map 0:a:0?     -vf "scale=3840:2160:force_original_aspect_ratio=decrease:flags=lanczos,pad=3840:2160:(ow-iw)/2:(oh-ih)/2,setsar=1"     -fps_mode passthrough -c:v libx264 -preset ultrafast -profile:v high -pix_fmt yuv420p     -b:v "${VIDEO_KBPS}k" -maxrate "${VIDEO_KBPS}k" -bufsize "$((VIDEO_KBPS*2))k"     -c:a aac -b:a 384k -ar 48000 -movflags +faststart "$OUT"
  echo "$OUT"
elif [[ "$MODE" == "merge" ]]; then
  LIST=/tmp/concat-4k.txt
  : > "$LIST"
  for i in $(seq 0 $((PART_COUNT-1))); do
    printf -v PN "%02d" "$i"
    test -s "$PARTS_DIR/part_${PN}.mp4"
    printf "file '%s'\n" "$PARTS_DIR/part_${PN}.mp4" >> "$LIST"
  done
  ffmpeg -hide_banner -y -f concat -safe 0 -i "$LIST" -c copy -movflags +faststart "$FINAL_FILE"
  SIZE=$(stat -c%s "$FINAL_FILE")
  echo "final_bytes=$SIZE"
  test "$SIZE" -le 30000000000
else
  echo "unknown mode: $MODE" >&2
  exit 2
fi
