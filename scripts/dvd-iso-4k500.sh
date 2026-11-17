#!/usr/bin/env bash
# DVD-ISO -> streamable mezzanine -> 20 one-minute workers -> Drive merge.
# No complete output movie or minute segment is written to a runner disk.
set -Eeuo pipefail

MODE="${1:?Usage: dvd-iso-4k500.sh prepare|encode|merge}"
: "${GITHUB_RUN_ID:?Must run in GitHub Actions}"
: "${RUNNER_TEMP:?RUNNER_TEMP required}"

STAGE="Video Converter/Fertig/.dragon-iso-4k500-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT:-1}"
OUTPUT="Video Converter/Fertig/How_To_Train_Your_Dragon_4K_HEVC_500Mbps_${GITHUB_RUN_ID}.mkv"
CHUNK=60
MOUNT="$RUNNER_TEMP/drive-mount"

auth_drive() {
  : "${GOOGLE_CLIENT_ID:?Missing GOOGLE_CLIENT_ID secret}"
  : "${GOOGLE_CLIENT_SECRET:?Missing GOOGLE_CLIENT_SECRET secret}"
  : "${GOOGLE_REFRESH_TOKEN:?Missing GOOGLE_REFRESH_TOKEN secret}"
  mkdir -p "$(dirname "$RCLONE_CONFIG")"
  local response access expiry token
  response=$(curl -fsS --retry 3 --request POST \
    --data-urlencode "client_id=$GOOGLE_CLIENT_ID" \
    --data-urlencode "client_secret=$GOOGLE_CLIENT_SECRET" \
    --data-urlencode "refresh_token=$GOOGLE_REFRESH_TOKEN" \
    --data-urlencode "grant_type=refresh_token" \
    https://oauth2.googleapis.com/token)
  access=$(jq -er '.access_token' <<<"$response")
  echo "::add-mask::$access"
  expiry=$(date -u -d '+3500 seconds' '+%Y-%m-%dT%H:%M:%SZ')
  token=$(jq -cn --arg a "$access" --arg r "$GOOGLE_REFRESH_TOKEN" --arg e "$expiry" \
    '{access_token:$a,token_type:"Bearer",refresh_token:$r,expiry:$e}')
  rclone config create drive drive client_id "$GOOGLE_CLIENT_ID" \
    client_secret "$GOOGLE_CLIENT_SECRET" scope drive token "$token" \
    --non-interactive >/dev/null
  DRIVE_ACCESS_TOKEN="$access"
}

mount_remote() {
  local remote="$1" target="$2"
  mkdir -p "$target"
  rclone mount "$remote" "$target" --read-only --vfs-cache-mode off \
    --vfs-read-chunk-size 16M --vfs-read-chunk-size-limit 128M \
    --daemon --daemon-wait 45s
  mountpoint -q "$target"
}

verify_remote() {
  local file="$1" minimum="$2" size
  size=$(rclone size --json "drive:$file" --retries 8 | jq -er '.bytes')
  if (( size < minimum )); then
    echo "::error::Drive object too small: $file ($size bytes)"
    return 1
  fi
  printf '%s bytes: %s\n' "$size" "$file"
}

prepare() {
  : "${ISO_FILE_ID:?Pass the ISO file ID through workflow_dispatch}"
  # Use the Drive file ID to find the real parent, without putting the ISO
  # or a public access token into the repository.
  local meta iso_name parent dvd_path vobs count duration_us
  meta=$(curl -fsS --retry 3 -H "Authorization: Bearer $DRIVE_ACCESS_TOKEN" \
    "https://www.googleapis.com/drive/v3/files/$ISO_FILE_ID?fields=id,name,size,parents,mimeType&supportsAllDrives=true")
  iso_name=$(jq -er '.name' <<<"$meta")
  parent=$(jq -er '.parents[0]' <<<"$meta")
  [[ "$iso_name" == *.iso || "$iso_name" == *.ISO ]] || { echo "::error::Not an ISO: $iso_name"; exit 1; }
  echo "ISO found: $iso_name"

  # Both the 6.8 GB ISO input and the remuxed DVD output are streamed:
  # rclone FUSE -> fuseiso FUSE -> FFmpeg -> rclone rcat.
  mount_remote "drive,root_folder_id=$parent:" "$MOUNT"
  local iso_path="$MOUNT/$iso_name"
  [[ -r "$iso_path" ]] || { echo "::error::ISO cannot be opened through Drive FUSE"; exit 1; }
  dvd_path="$RUNNER_TEMP/dvd-video"
  mkdir -p "$dvd_path"
  fuseiso "$iso_path" "$dvd_path"
  mountpoint -q "$dvd_path" || { echo "::error::fuseiso mount failed"; exit 1; }
  local vob_dir
  vob_dir=$(find "$dvd_path" -maxdepth 2 -type d -iname VIDEO_TS -print -quit)
  [[ -n "$vob_dir" ]] || { echo "::error::VIDEO_TS not found: this may not be a readable DVD-Video ISO"; exit 1; }

  # Main feature is normally the VTS group with the largest total VOB size.
  # Disc menus or multiple titles require a different title-selection policy.
  vobs=$(python3 - "$vob_dir" <<'PY'
import os, re, sys
directory=sys.argv[1]
groups={}
for name in os.listdir(directory):
    match=re.fullmatch(r'VTS_(\d{2})_([1-9])\.VOB', name, flags=re.I)
    if match:
        groups.setdefault(match.group(1), []).append((int(match.group(2)), os.path.join(directory,name)))
if not groups:
    raise SystemExit("No VTS_*_1.VOB movie groups found")
best=max(groups.values(), key=lambda items:sum(os.stat(p).st_size for _,p in items))
best.sort()
print('concat:'+'|'.join(p for _,p in best))
PY
)
  rclone mkdir "drive:$STAGE"
  echo "Remuxing longest DVD title to cloud source (stream only)"
  ffmpeg -nostdin -hide_banner -loglevel warning -fflags +genpts \
    -progress "$RUNNER_TEMP/dvd-progress.log" \
    -i "$vobs" -map 0:v:0 -map 0:a? -c copy \
    -avoid_negative_ts make_zero -f matroska pipe:1 \
    | rclone rcat "drive:$STAGE/source.mkv" --drive-chunk-size 64M \
      --retries 8 --low-level-retries 30 --stats 30s
  verify_remote "$STAGE/source.mkv" 100000000
  duration_us=$(awk -F= '$1=="out_time_us" {t=$2} END {print t+0}' "$RUNNER_TEMP/dvd-progress.log")
  read -r count duration_us < <(python3 - "$duration_us" <<'PY'
import math,sys
us=int(float(sys.argv[1]))
assert 60*1000000 < us < 6*3600*1000000, f"Unreasonable DVD feature duration: {us}"
print(math.ceil(us / 60000000), us)
PY
)
  echo "DVD length: $duration_us microseconds; $count minute parts"
  {
    echo "segments=$count"
    echo "duration_us=$duration_us"
  } >> "$GITHUB_OUTPUT"
  echo "Prepared DVD: $count segments, Drive: $STAGE/source.mkv" >> "$GITHUB_STEP_SUMMARY"
}

encode() {
  : "${SEGMENTS:?Missing segments from prepare}"
  : "${DURATION_US:?Missing duration from prepare}"
  : "${WORKER:?Missing matrix worker index}"
  mount_remote "drive:" "$MOUNT"
  local src="$MOUNT/$STAGE/source.mkv" part start duration name size
  [[ -r "$src" ]] || { echo "::error::Mezzanine not yet visible on Google Drive"; exit 1; }
  for (( part=WORKER; part<SEGMENTS; part+=20 )); do
    start=$((part*CHUNK))
    duration=$(python3 - "$DURATION_US" "$start" <<'PY'
import sys
left=int(sys.argv[1])/1000000-int(sys.argv[2])
print(f"{min(60.0,left):.6f}")
PY
)
    name=$(printf "segment_%04d.mkv" "$part")
    echo "Worker $WORKER: rendering minute $part at t=$start length=$duration"
    # Audio is recoded per segment so timestamps at join points are reliable.
    # 500M is the target video bitrate, not a guarantee of a constant file rate.
    ffmpeg -nostdin -hide_banner -loglevel warning -ss "$start" -i "$src" \
      -t "$duration" -map 0:v:0 -map 0:a? \
      -vf "scale=3840:2160:force_original_aspect_ratio=decrease:flags=lanczos,pad=3840:2160:(ow-iw)/2:(oh-ih)/2,setsar=1" \
      -c:v libx265 -preset ultrafast -threads 2 -pix_fmt yuv420p \
      -b:v 500M -maxrate 500M -bufsize 1000M \
      -x265-params "pools=2:frame-threads=2:log-level=error" \
      -c:a aac -b:a 384k -ar 48000 -avoid_negative_ts make_zero \
      -f matroska pipe:1 \
      | rclone rcat "drive:$STAGE/$name" --drive-chunk-size 64M \
        --retries 8 --low-level-retries 30 --stats 30s
    verify_remote "$STAGE/$name" 1000000
  done
  echo "Worker $WORKER completed its minute queue" >> "$GITHUB_STEP_SUMMARY"
}

merge() {
  : "${SEGMENTS:?Missing segments}"
  : "${DURATION_US:?Missing duration}"
  mount_remote "drive:" "$MOUNT"
  local playlist="$RUNNER_TEMP/concat.txt" part name length
  : > "$playlist"
  for ((part=0; part<SEGMENTS; part++)); do
    name=$(printf "segment_%04d.mkv" "$part")
    verify_remote "$STAGE/$name" 1000000
    length=$(python3 - "$DURATION_US" "$part" <<'PY'
import sys
left=int(sys.argv[1])/1000000 - 60*int(sys.argv[2])
print(f"{min(60.0,left):.6f}")
PY
)
    printf "file '%s'\nduration %s\n" "$MOUNT/$STAGE/$name" "$length" >> "$playlist"
  done
  echo "Merging $SEGMENTS remote segments without downloading to SSD"
  ffmpeg -nostdin -hide_banner -loglevel warning -f concat -safe 0 -i "$playlist" \
    -map 0 -c copy -f matroska pipe:1 \
    | rclone rcat "drive:$OUTPUT" --drive-chunk-size 64M \
      --retries 8 --low-level-retries 30 --stats 30s
  verify_remote "$OUTPUT" 100000000
  echo "SUCCESS: drive:$OUTPUT" >> "$GITHUB_STEP_SUMMARY"
  # Keep temporary input/parts until the final Drive file has passed size checks.
  rclone purge "drive:$STAGE" --retries 8 || \
    echo "::warning::Output saved, but temporary Drive files remain."
}

auth_drive
case "$MODE" in
  prepare) prepare;;
  encode) encode;;
  merge) merge;;
  *) echo "::error::Invalid operation $MODE"; exit 2;;
esac
