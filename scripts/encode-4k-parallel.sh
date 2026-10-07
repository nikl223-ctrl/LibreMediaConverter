#!/usr/bin/env bash
set -euo pipefail
MODE="${1:?mode required: encode|merge}"
SOURCE="${SOURCE:-/tmp/source.mp4}"
PARTS_DIR="${PARTS_DIR:-/tmp/parts}"
PART_COUNT="${PART_COUNT:-20}"
WIDTH="${WIDTH:-800000}"
HEIGHT="${HEIGHT:-450000}"
VIDEO_BITRATE="${VIDEO_BITRATE:-20M}"
mkdir -p "$PARTS_DIR"
if [[ "$MODE" == "encode" ]]; then
  PART="${PART:?PART required}"
  DURATION="${DURATION:-$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SOURCE")}"
  SEG=$(awk -v d="$DURATION" -v n="$PART_COUNT" 'BEGIN {printf "%.6f", d/n}')
  START=$(awk -v p="$PART" -v s="$SEG" 'BEGIN {printf "%.6f", p*s}')
  LENGTH="$SEG"
  if [[ "$PART" -eq $((PART_COUNT-1)) ]]; then LENGTH=$(awk -v d="$DURATION" -v s="$START" 'BEGIN {printf "%.6f", d-s}'); fi
  printf -v PN "%02d" "$PART"
  OUT="$PARTS_DIR/part_${PN}.mp4"
  ffmpeg -hide_banner -y -ss "$START" -i "$SOURCE" -t "$LENGTH" \
    -map 0:v:0 -map 0:a:0? \
    -vf "scale=${WIDTH}:${HEIGHT}:force_original_aspect_ratio=decrease:flags=fast_bilinear,pad=${WIDTH}:${HEIGHT}:(ow-iw)/2:(oh-ih)/2,setsar=1" \
    -fps_mode passthrough -c:v libx264 -preset ultrafast -pix_fmt yuv420p \
    -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_BITRATE" -bufsize 40M \
    -c:a aac -b:a 192k -ar 48000 -movflags +faststart "$OUT"
  SIZE=$(stat -c%s "$OUT")
  test "$SIZE" -le 5000000000
  echo "$OUT"
else
  echo "Merge is handled by the streaming merge workflow."
fi
