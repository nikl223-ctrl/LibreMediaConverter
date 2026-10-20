#!/usr/bin/env bash
# Private Google Drive OAuth on GitHub-hosted workers.
# Never print tokens, credentials, configs, or commercial game contents.
set -euo pipefail
for key in GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REFRESH_TOKEN; do
  if [[ -z "${!key:-}" ]]; then echo "::error::Missing Google Drive OAuth secret: $key"; exit 1; fi
done
test "${GOOGLE_CLIENT_ID%%-*}" = "160241343420" ||
 { echo "::error::Refusing to use an unexpected OAuth client"; exit 1; }
command -v rclone >/dev/null || { sudo apt-get update -qq; sudo apt-get install -y -qq rclone; }
command -v jq >/dev/null || { sudo apt-get update -qq; sudo apt-get install -y -qq jq; }
auth_response=$(curl -fsS --request POST \
  --data-urlencode "client_id=$GOOGLE_CLIENT_ID" \
  --data-urlencode "client_secret=$GOOGLE_CLIENT_SECRET" \
  --data-urlencode "refresh_token=$GOOGLE_REFRESH_TOKEN" \
  --data-urlencode "grant_type=refresh_token" https://oauth2.googleapis.com/token)
access_token=$(jq -r '.access_token // empty' <<<"$auth_response")
test -n "$access_token" || { echo "::error::Could not acquire Drive access token"; exit 1; }
echo "::add-mask::$access_token"
unset auth_response
expiry=$(date -u -d '+3500 seconds' '+%Y-%m-%dT%H:%M:%SZ')
token_json=$(jq -cn --arg at "$access_token" --arg rt "$GOOGLE_REFRESH_TOKEN" --arg ex "$expiry" \
 '{access_token:$at,token_type:"Bearer",refresh_token:$rt,expiry:$ex}')
secret_dir="$RUNNER_TEMP/lego-drive-auth"
install -d -m 700 "$secret_dir"
export RCLONE_CONFIG="$secret_dir/rclone.conf"
echo "RCLONE_CONFIG=$RCLONE_CONFIG" >> "$GITHUB_ENV"
rclone config create drive drive \
  client_id "$GOOGLE_CLIENT_ID" client_secret "$GOOGLE_CLIENT_SECRET" \
  scope drive token "$token_json" --non-interactive >/dev/null
chmod 600 "$RCLONE_CONFIG"
unset token_json access_token
echo "PRIVATE_DRIVE_AUTH_READY=yes"
