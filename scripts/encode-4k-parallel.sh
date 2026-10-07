#!/usr/bin/env bash
set -euo pipefail
MODE="${1:?mode required: encode|merge}"
SOURCE="${SOURCE:-/tmp/source.mp4}"
PARTS_DIR="${PARTS_DIR:-/tmp/parts}"
FINAL_FILE="${FINAL_FILE:-/tmp/Die_Monster_AG_4K_FFV1.mkv}"
PART_COUNT="${PART_COUNT:-20}"
mkdir -p "$PARTS_DIR"
if [[ "$MODE" == "encode" ]]; then
  PART="${PART:?PART required}"
  DURATION="${DURATION:-$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SOURCE")}"
  SEG=$(awk -v d="$DURATION" -v n="$PART_COUNT" 'BEGIN {printf "%.6f", d/n}')
  START=$(awk -v p="$PART" -v s="$SEG" 'BEGIN {printf "%.6f", p*s}')
  LENGTH="$SEG"
  if [[ "$PART" -eq $((PART_COUNT-1)) ]]; then LENGTH=$(awk -v d="$DURATION" -v s="$START" 'BEGIN {printf "%.6f", d-s}'); fi
  printf -v PN "%02d" "$PART"
  OUT="$PARTS_DIR/part_${PN}.mkv"
  ffmpeg -hide_banner -y -ss "$START" -i "$SOURCE" -t "$LENGTH"     -map 0:v:0 -map 0:a:0?     -vf "scale=3840:2160:force_original_aspect_ratio=decrease:flags=lanczos,pad=3840:2160:(ow-iw)/2:(oh-ih)/2,setsar=1"     -fps_mode passthrough -c:v ffv1 -level 3 -coder 1 -context 1 -g 1 -slicecrc 1     -c:a flac "$OUT"
  echo "$OUT"
elif [[ "$MODE" == "merge" ]]; then
  LIST=/tmp/concat-4k.txt
  : > "$LIST"
  for i in $(seq 0 $((PART_COUNT-1))); do
    printf -v PN "%02d" "$i"
    test -s "$PARTS_DIR/part_${PN}.mkv"
    printf "file '%s'\n" "$PARTS_DIR/part_${PN}.mkv" >> "$LIST"
  done
  ffmpeg -hide_banner -y -f concat -safe 0 -i "$LIST" -c copy "$FINAL_FILE"
  SIZE=$(stat -c%s "$FINAL_FILE")
  echo "final_bytes=$SIZE"
else
  echo "unknown mode: $MODE" >&2
  exit 2
fi
