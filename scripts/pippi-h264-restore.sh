#!/usr/bin/env bash
# Restore noisy/compressed SD TV episodes to 4K H.264 on GitHub-hosted runners.
# Source and encoded chunks are staged in Drive; final MKV is streamed as it is assembled.
set -euo pipefail
SOURCE_ID=1MBBuUaVvFnetqgSer-Qs4lIAGnfoTR2p
PART_FOLDER="Video Converter/Fertig/.pippi-4k-$GITHUB_RUN_ID"
OUTPUT="Video Converter/Fertig/Pippi_Langstrumpf_Folgen_09-13_4K_H264_5.1_Restauriert.mkv"
export RCLONE_CONFIG="$RUNNER_TEMP/pippi-rclone.conf"

setup() {
  if ! command -v ffmpeg >/dev/null || ! command -v jq >/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends ffmpeg jq ca-certificates curl
  fi
  if ! command -v rclone >/dev/null; then
    curl -fsSL --retry 3 https://rclone.org/install.sh | sudo bash
  fi
  for secret in GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN; do
    test -n "$(printenv "$secret")" || { echo "::error::Missing secret $secret"; exit 1; }
  done
  project="$(printf '%s' "$GOOGLE_CLIENT_ID" | cut -d- -f1)"
  test "$project" = "160241343420" || { echo "::error::Incorrect OAuth client project"; exit 1; }
  response="$(curl -fsS --retry 4 -X POST \
    --data-urlencode "client_id=$GOOGLE_CLIENT_ID" \
    --data-urlencode "client_secret=$GOOGLE_CLIENT_SECRET" \
    --data-urlencode "refresh_token=$GOOGLE_REFRESH_TOKEN" \
    --data-urlencode "grant_type=refresh_token" \
    https://oauth2.googleapis.com/token)"
  token="$(printf '%s' "$response" | jq -r '.access_token // empty')"
  test -n "$token" || { echo "::error::Google Drive token refresh failed"; exit 1; }
  echo "::add-mask::$token"
  expires="$(date -u -d '+3500 seconds' '+%Y-%m-%dT%H:%M:%SZ')"
  json="$(jq -cn --arg a "$token" --arg r "$GOOGLE_REFRESH_TOKEN" --arg e "$expires" \
    '{access_token:$a, token_type:"Bearer", refresh_token:$r, expiry:$e}')"
  rclone config create drive drive client_id "$GOOGLE_CLIENT_ID" \
    client_secret "$GOOGLE_CLIENT_SECRET" scope drive token "$json" --non-interactive >/dev/null
}

prepare() {
  setup
  free="$(df -Pk "$RUNNER_TEMP" | awk 'NR==2 {printf "%.0f", $4*1024}')"
  if [ "$free" -lt 9500000000 ]; then
    sudo rm -rf /usr/share/dotnet /usr/local/lib/android /usr/local/share/powershell /opt/hostedtoolcache/CodeQL || true
  fi
  df -h "$RUNNER_TEMP"
  rclone mkdir "drive:$PART_FOLDER/input"
  rclone mkdir "drive:$PART_FOLDER/encoded"
  printf 'probe\n' | rclone rcat "drive:$PART_FOLDER/probe.txt" --retries 5
  rclone deletefile "drive:$PART_FOLDER/probe.txt" || true

  mkdir -p "$RUNNER_TEMP/pippi-input" "$RUNNER_TEMP/pippi-parts"
  rclone backend copyid drive: "$SOURCE_ID" "$RUNNER_TEMP/pippi-input/" \
    --stats 15s --retries 10 --low-level-retries 30
  input="$(find "$RUNNER_TEMP/pippi-input" -maxdepth 1 -type f -size +0c | head -1)"
  test -s "$input"
  duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input" | head -1)"
  segment_seconds="$(python3 -c 'import sys,math; d=float(sys.argv[1]); assert math.isfinite(d) and d>0; print(max(30,d/16))' "$duration")"
  echo "Input duration $duration seconds, target per segment $segment_seconds seconds"
  ffmpeg -hide_banner -loglevel warning -stats_period 15 -i "$input" \
    -map 0:v:0 -map 0:a:0 -c copy -f segment -segment_format matroska \
    -segment_time "$segment_seconds" -reset_timestamps 1 \
    "$RUNNER_TEMP/pippi-parts/part_%03d.mkv"

  ids="$(find "$RUNNER_TEMP/pippi-parts" -maxdepth 1 -type f -name 'part_*.mkv' \
    -printf '%f\n' | sed -E 's/^part_([0-9]+)\.mkv$/\1/' | sort)"
  count="$(printf '%s\n' "$ids" | wc -l)"
  test "$count" -ge 2 && test "$count" -le 40 || { echo "::error::Unexpected number of slices: $count"; exit 1; }
  rclone copy "$RUNNER_TEMP/pippi-parts" "drive:$PART_FOLDER/input" \
    --transfers 4 --stats 15s --retries 10 --low-level-retries 30
  ids_json="$(printf '%s\n' "$ids" | jq -R . | jq -sc .)"
  printf 'parts=%s\n' "$ids_json" >> "$GITHUB_OUTPUT"
  echo "## Lossless source divided into $count segments, uploaded to Drive" >> "$GITHUB_STEP_SUMMARY"
}

encode() {
  setup
  part="$PART_ID"
  test -n "$part"
  file="$RUNNER_TEMP/part_$part.mkv"
  rclone copyto "drive:$PART_FOLDER/input/part_$part.mkv" "$file" \
    --stats 15s --retries 10 --low-level-retries 30
  test -s "$file"
  channels="$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of csv=p=0 "$file" | head -1)"
  test -n "$channels" && test "$channels" -ge 1

  # First remove blocking and grain, then upscale. Moderate sharpening avoids ringing halos.
  vf="deblock=filter=strong:block=8:alpha=0.1:beta=0.1,hqdn3d=4:3:6:4.5,scale=3840:2160:force_original_aspect_ratio=decrease:flags=lanczos,pad=3840:2160:(ow-iw)/2:(oh-ih)/2,setsar=1,unsharp=5:5:0.18:3:3:0.0"
  if [ "$channels" -lt 6 ]; then
    echo "Upmixing stereo soundfield to AC-3 5.1; source has no discrete surround information."
    af="aformat=channel_layouts=stereo,surround=chl_out=5.1:level_in=1:level_out=0.8:smooth=0.25,alimiter=limit=0.95"
  else
    af="alimiter=limit=0.95"
  fi
  # Direct pipeline: encoded bytes go to Google Drive immediately, no local full output.
  ffmpeg -hide_banner -loglevel warning -stats_period 15 -i "$file" \
    -map 0:v:0 -map 0:a:0 -vf "$vf" -fps_mode passthrough \
    -c:v libx264 -preset veryfast -crf 17 -maxrate 45000k -bufsize 90000k \
    -profile:v high -pix_fmt yuv420p -threads 4 \
    -af "$af" -c:a ac3 -ac 6 -ar 48000 -b:a 640k \
    -f matroska pipe:1 \
    | rclone rcat "drive:$PART_FOLDER/encoded/part_$part.mkv" \
      --drive-chunk-size 128M --stats 15s --retries 12 --low-level-retries 50
  bytes="$(rclone size "drive:$PART_FOLDER/encoded/part_$part.mkv" --json | jq -r '.bytes // 0')"
  test "$bytes" -gt 1000000
  echo "Part $part 4K H264/AC3 uploaded: $bytes bytes" >> "$GITHUB_STEP_SUMMARY"
}

merge() {
  setup
  ids="$(printf '%s' "$PARTS_JSON" | jq -r '.[]')"
  test -n "$ids"
  dir="$RUNNER_TEMP/pippi-concat-fifos"
  mkdir -p "$dir"
  list="$dir/list.txt"
  printf 'ffconcat version 1.0\n' > "$list"
  for id in $ids; do
    remote="drive:$PART_FOLDER/encoded/part_$id.mkv"
    bytes="$(rclone size "$remote" --json | jq -r '.bytes // 0')"
    test "$bytes" -gt 1000000 || { echo "::error::Missing chunk $id"; exit 1; }
    mkfifo "$dir/part_$id.mkv"
    printf "file '%s'\n" "$dir/part_$id.mkv" >> "$list"
  done
  producers=""
  for id in $ids; do
    (rclone cat "drive:$PART_FOLDER/encoded/part_$id.mkv" \
      --retries 12 --low-level-retries 40 > "$dir/part_$id.mkv") &
    producers="$producers $!"
  done
  # FFmpeg concat demuxer adjusts segment timestamps; FIFO pipes keep disk space low.
  ffmpeg -hide_banner -loglevel warning -stats_period 15 -f concat -safe 0 \
    -i "$list" -map 0:v:0 -map 0:a:0 -c copy -f matroska pipe:1 \
    | rclone rcat "drive:$OUTPUT" --drive-chunk-size 128M \
      --stats 15s --retries 12 --low-level-retries 50
  for pid in $producers; do wait "$pid"; done
  bytes="$(rclone size "drive:$OUTPUT" --json | jq -r '.bytes // 0')"
  test "$bytes" -gt 1000000
  echo "## Complete: 4K H.264 + Dolby Digital AC-3 5.1" >> "$GITHUB_STEP_SUMMARY"
  echo "- Drive: $OUTPUT" >> "$GITHUB_STEP_SUMMARY"
  echo "- Output size: $bytes bytes" >> "$GITHUB_STEP_SUMMARY"
  rclone purge "drive:$PART_FOLDER" --retries 10 || echo "::warning::Temporary shards remain in Drive"
}

case "$1" in
  prepare) prepare ;;
  encode) encode ;;
  merge) merge ;;
  *) echo "Call with prepare, encode, or merge"; exit 2 ;;
esac
