#!/usr/bin/env bash
# Upload IPA(s) + landing page to the VPS.
# Usage:
#   ./scripts/upload-ipa-to-vps.sh /path/to/AuthorToday.ipa [/path/to/TubeVault.ipa]
#   ./scripts/upload-ipa-to-vps.sh --app tubevault /path/to/TubeVault.ipa
# Env:
#   CHITALNYA_VPS_HOST=root@185.125.103.168
#   CHITALNYA_SSH_KEY=~/.ssh/id_ed25519_aeza

set -euo pipefail

HOST="${CHITALNYA_VPS_HOST:-root@185.125.103.168}"
KEY="${CHITALNYA_SSH_KEY:-$HOME/.ssh/id_ed25519_aeza}"
REMOTE_DIR="/opt/chitalnya"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCAL_HTML_DIR="$ROOT/docs/chitalnya-install"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

guess_app() {
  local base
  base="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
    *tubevault*) echo tubevault ;;
    *authortoday*|*chitalnya*) echo chitalnya ;;
    *) echo "" ;;
  esac
}

remote_name() {
  case "$1" in
    chitalnya) echo AuthorToday.ipa ;;
    tubevault) echo TubeVault.ipa ;;
    *) return 1 ;;
  esac
}

APP_OVERRIDE=""
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_OVERRIDE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "Usage: $0 [--app chitalnya|tubevault] /path/to/App.ipa [...]" >&2
  exit 1
fi

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" "mkdir -p '$REMOTE_DIR'"

if [[ -f "$LOCAL_HTML_DIR/index.html" ]]; then
  scp -i "$KEY" -o StrictHostKeyChecking=accept-new \
    "$LOCAL_HTML_DIR/index.html" "$HOST:$REMOTE_DIR/index.html"
fi

TMP="$(mktemp)"
# Start from remote meta if present, else empty
ssh -i "$KEY" "$HOST" "cat '$REMOTE_DIR/meta.json' 2>/dev/null || echo '{}'" > "$TMP" || echo '{}' > "$TMP"

for IPA in "${FILES[@]}"; do
  [[ -f "$IPA" ]] || { echo "Not found: $IPA" >&2; exit 1; }
  APP="${APP_OVERRIDE:-$(guess_app "$IPA")}"
  [[ -n "$APP" ]] || { echo "Pass --app chitalnya|tubevault for $IPA" >&2; exit 1; }
  RNAME="$(remote_name "$APP")"
  SIZE="$(wc -c < "$IPA" | tr -d ' ')"
  echo "Uploading $IPA → $RNAME ($SIZE bytes)"
  scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$IPA" "$HOST:$REMOTE_DIR/$RNAME"
  ssh -i "$KEY" "$HOST" "chmod 644 '$REMOTE_DIR/$RNAME'"
  python3 - "$TMP" "$APP" "$RNAME" "$SIZE" "$NOW" <<'PY'
import json, sys
path, app, fname, size, now = sys.argv[1:6]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception:
    data = {}
apps = data.get("apps") or {}
# legacy flat → chitalnya
if "sizeBytes" in data and "chitalnya" not in apps:
    apps["chitalnya"] = {
        "file": "AuthorToday.ipa",
        "title": "Читальня",
        "version": data.get("version") or "1.0",
        "build": data.get("build") or "manual",
        "updatedAt": data.get("updatedAt"),
        "sizeBytes": data.get("sizeBytes"),
    }
defaults = {
    "chitalnya": {"file": "AuthorToday.ipa", "title": "Читальня", "version": "1.0", "build": "manual"},
    "tubevault": {"file": "TubeVault.ipa", "title": "TubeVault", "version": "1.0", "build": "manual"},
}
entry = dict(defaults.get(app, {"file": fname, "title": app, "version": "1.0", "build": "manual"}))
entry.update(apps.get(app, {}))
entry.update({"file": fname, "sizeBytes": int(size), "updatedAt": now, "build": "manual"})
apps[app] = entry
json.dump({"apps": apps}, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
open(path, "a", encoding="utf-8").write("\n")
PY
done

scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$TMP" "$HOST:$REMOTE_DIR/meta.json"
ssh -i "$KEY" "$HOST" "chmod 644 '$REMOTE_DIR/meta.json' '$REMOTE_DIR/index.html'; ls -lh '$REMOTE_DIR'/*.ipa '$REMOTE_DIR'/index.html '$REMOTE_DIR'/meta.json"
rm -f "$TMP"
echo "Done: https://tv.theinquisitor.ru/chitalnya/"
