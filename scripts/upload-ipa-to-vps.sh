#!/usr/bin/env bash
# Upload IPA(s) + landing page to the VPS (versioned history via publish-ipa-version.sh).
# Usage:
#   ./scripts/upload-ipa-to-vps.sh /path/to/AuthorToday.ipa [/path/to/TubeVault.ipa]
#   ./scripts/upload-ipa-to-vps.sh --app tubevault /path/to/TubeVault.ipa
# Env:
#   CHITALNYA_VPS_HOST=root@185.125.103.168
#   CHITALNYA_SSH_KEY=~/.ssh/id_ed25519_aeza

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PUBLISH="$SCRIPT_DIR/publish-ipa-version.sh"

guess_app() {
  local base
  base="$(basename "$1" | tr '[:upper:]' '[:lower:]')"
  case "$base" in
    *tubevault*) echo tubevault ;;
    *authortoday*|*chitalnya*) echo chitalnya ;;
    *) echo "" ;;
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

SYNCED=0
for IPA in "${FILES[@]}"; do
  [[ -f "$IPA" ]] || { echo "Not found: $IPA" >&2; exit 1; }
  APP="${APP_OVERRIDE:-$(guess_app "$IPA")}"
  [[ -n "$APP" ]] || { echo "Pass --app chitalnya|tubevault for $IPA" >&2; exit 1; }
  EXTRA=()
  if [[ "$SYNCED" -eq 0 ]]; then
    EXTRA+=(--sync-page)
    SYNCED=1
  fi
  "$PUBLISH" --app "$APP" "${EXTRA[@]}" "$IPA"
done

echo "All uploads done: https://tv.theinquisitor.ru/chitalnya/"
