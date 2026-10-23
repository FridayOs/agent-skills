#!/usr/bin/env bash
# YouTube Data API v3 helper (read-only, API key).
#
#   yt.sh get <resource> [param=value ...]                one request, raw JSON
#   yt.sh all <resource> [--max-pages N] [param=value ...] follow nextPageToken (default 5 pages)
#   yt.sh video-id <url|id>                               extract a video id (no API call)
#   yt.sh channel <@handle|channel URL|UC… id> [parts]    resolve a channel (1 unit)
#   yt.sh uploads <@handle|channel URL|UC… id> [max]      latest uploads of a channel (2+ units)
#
# Examples:
#   yt.sh get videos part=snippet,statistics id=dQw4w9WgXcQ
#   yt.sh all commentThreads --max-pages 3 part=snippet videoId=dQw4w9WgXcQ textFormat=plainText maxResults=100
#
# Env:
#   YOUTUBE_API_KEY   Google API key with YouTube Data API v3 enabled. Never print it.
#   YOUTUBE_API_URL   default https://www.googleapis.com/youtube/v3
# Inside a Paperclip run where YOUTUBE_API_KEY is unset, the key is read from
# the agent's granted secret `YOUTUBE_API_KEY` (or `youtube_api_key`).
#
# The key is sent as the `x-goog-api-key` header through curl's config on
# stdin, so it never appears in URLs, logs or the process list.
#
# Exit codes: 0 ok, 1 API error (`HTTP <status> <reason>: <message>` on stderr), 2 usage/config error.
set -euo pipefail

API_URL="${YOUTUBE_API_URL:-https://www.googleapis.com/youtube/v3}"
API_URL="${API_URL%/}"

die() { echo "yt: $1" >&2; exit "${2:-2}"; }
usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; }

load_key() {
  if [[ -n "${YOUTUBE_API_KEY:-}" ]]; then return; fi
  if [[ -n "${PAPERCLIP_API_URL:-}" && -n "${PAPERCLIP_API_KEY:-}" ]]; then
    local base="${PAPERCLIP_API_URL%/}"; base="${base%/api}"
    local name
    for name in YOUTUBE_API_KEY youtube_api_key; do
      YOUTUBE_API_KEY="$(curl -sf -X POST -H "Authorization: Bearer $PAPERCLIP_API_KEY" \
        "$base/api/agents/me/secrets/$name/value" 2>/dev/null | jq -r '.value // empty' 2>/dev/null || true)"
      [[ -n "$YOUTUBE_API_KEY" ]] && return
    done
  fi
  die "YOUTUBE_API_KEY is not set (Google Cloud Console → enable YouTube Data API v3 → Credentials → API key)"
}

# GET <resource> with param=value args; prints the JSON body or fails with the API reason.
request() {
  local resource="$1"; shift
  local args=() param response status
  for param in "$@"; do
    [[ "$param" == *=* ]] || die "parameter must be name=value: $param"
    [[ "${param%%=*}" == "key" ]] && die "do not pass key=…; the key is sent as a header from YOUTUBE_API_KEY"
    args+=(--data-urlencode "$param")
  done
  response="$(printf 'header = "x-goog-api-key: %s"\n' "$YOUTUBE_API_KEY" |
    curl -sS -G -K - -w '\n%{http_code}' "${args[@]}" "$API_URL/$resource")" || die "cannot reach $API_URL" 1
  status="${response##*$'\n'}"; response="${response%$'\n'*}"
  if [[ "$status" != 2* ]]; then
    local reason message
    reason="$(jq -r '.error.errors[0].reason // .error.status // empty' 2>/dev/null <<<"$response" || true)"
    message="$(jq -r '.error.message // empty' 2>/dev/null <<<"$response" || true)"
    die "HTTP $status ${reason:-error}: ${message:-$response}" 1
  fi
  printf '%s\n' "$response"
}

paginate() {
  local resource="$1"; shift
  local max_pages=5
  if [[ "${1:-}" == "--max-pages" ]]; then
    [[ "${2:-}" =~ ^[1-9][0-9]*$ ]] || die "--max-pages needs a positive number"
    max_pages="$2"; shift 2
  fi
  PAGE_DIR="$(mktemp -d)"
  trap 'rm -rf "${PAGE_DIR:-}"' EXIT
  local tmp="$PAGE_DIR"
  local token="" page=0
  while (( page < max_pages )); do
    local params=("$@")
    [[ -n "$token" ]] && params+=("pageToken=$token")
    page=$((page + 1))
    request "$resource" "${params[@]}" > "$tmp/$page.json"
    token="$(jq -r '.nextPageToken // empty' "$tmp/$page.json")"
    [[ -z "$token" ]] && break
  done
  jq -s --arg next "$token" '{items: (map(.items // []) | add), pages: length, nextPageToken: (if $next == "" then null else $next end)}' \
    $(for ((i = 1; i <= page; i++)); do printf '%s ' "$tmp/$i.json"; done)
}

video_id() {
  local input="$1" id=""
  if [[ "$input" =~ ^[A-Za-z0-9_-]{11}$ ]]; then id="$input"
  elif [[ "$input" =~ [?\&]v=([A-Za-z0-9_-]{11}) ]]; then id="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtu\.be/([A-Za-z0-9_-]{11}) ]]; then id="${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtube(-nocookie)?\.com/(shorts|embed|live|v)/([A-Za-z0-9_-]{11}) ]]; then id="${BASH_REMATCH[3]}"
  fi
  [[ -n "$id" ]] || die "no video id in: $input"
  printf '%s\n' "$id"
}

# channels.list filter for a handle, channel URL or id.
channel_filter() {
  local input="$1"
  if [[ "$input" =~ ^UC[A-Za-z0-9_-]{22}$ ]]; then echo "id=$input"
  elif [[ "$input" =~ youtube\.com/channel/(UC[A-Za-z0-9_-]{22}) ]]; then echo "id=${BASH_REMATCH[1]}"
  elif [[ "$input" =~ youtube\.com/(@[^/?#]+) ]]; then echo "forHandle=${BASH_REMATCH[1]}"
  elif [[ "$input" =~ ^@[^/?#[:space:]]+$ ]]; then echo "forHandle=$input"
  elif [[ "$input" =~ youtube\.com/user/([^/?#]+) ]]; then echo "forUsername=${BASH_REMATCH[1]}"
  else
    die "cannot resolve '$input' without a search: use a @handle, a youtube.com/channel/UC… URL or a UC… id (or search type=channel, 100 units)"
  fi
}

get_channel() {
  local filter parts="${2:-snippet,statistics,contentDetails}" body
  filter="$(channel_filter "$1")"
  body="$(request channels "part=$parts" "$filter")"
  jq -e '.items | length > 0' >/dev/null <<<"$body" || die "channel not found: $1" 1
  jq '.items[0]' <<<"$body"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  get)
    [[ $# -ge 1 ]] || die "usage: yt.sh get <resource> [param=value ...]"
    load_key; request "$@" | jq .
    ;;
  all)
    [[ $# -ge 1 ]] || die "usage: yt.sh all <resource> [--max-pages N] [param=value ...]"
    load_key; paginate "$@"
    ;;
  video-id)
    [[ $# -eq 1 ]] || die "usage: yt.sh video-id <url|id>"
    video_id "$1"
    ;;
  channel)
    [[ $# -ge 1 ]] || die "usage: yt.sh channel <@handle|channel URL|UC… id> [parts]"
    load_key; get_channel "$@"
    ;;
  uploads)
    [[ $# -ge 1 ]] || die "usage: yt.sh uploads <@handle|channel URL|UC… id> [max]"
    max="${2:-10}"
    [[ "$max" =~ ^[1-9][0-9]*$ ]] || die "max must be a positive number"
    load_key
    playlist="$(get_channel "$1" contentDetails | jq -r '.contentDetails.relatedPlaylists.uploads // empty')"
    [[ -n "$playlist" ]] || die "channel has no uploads playlist: $1" 1
    pages=$(( (max + 49) / 50 ))
    paginate playlistItems --max-pages "$pages" part=snippet,contentDetails "playlistId=$playlist" "maxResults=$(( max < 50 ? max : 50 ))" |
      jq --argjson max "$max" '.items[:$max] | map({videoId: .contentDetails.videoId, title: .snippet.title, publishedAt: (.contentDetails.videoPublishedAt // .snippet.publishedAt)})'
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    usage >&2; exit 2
    ;;
esac
