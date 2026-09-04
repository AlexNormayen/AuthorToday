#!/usr/bin/env bash
# Upload AuthorToday.ipa to the VPS install page.
# Usage:
#   ./scripts/upload-ipa-to-vps.sh /path/to/AuthorToday.ipa
# Env:
#   CHITALNYA_VPS_HOST=root@185.125.103.168
#   CHITALNYA_SSH_KEY=~/.ssh/id_ed25519_aeza

set -euo pipefail

IPA="${1:-}"
if [[ -z "$IPA" || ! -f "$IPA" ]]; then
  echo "Usage: $0 /path/to/AuthorToday.ipa" >&2
  exit 1
fi

HOST="${CHITALNYA_VPS_HOST:-root@185.125.103.168}"
KEY="${CHITALNYA_SSH_KEY:-$HOME/.ssh/id_ed25519_aeza}"
REMOTE_DIR="/opt/chitalnya"
SIZE="$(wc -c < "$IPA" | tr -d ' ')"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "$HOST" "mkdir -p '$REMOTE_DIR'"
scp -i "$KEY" -o StrictHostKeyChecking=accept-new "$IPA" "$HOST:$REMOTE_DIR/AuthorToday.ipa"
ssh -i "$KEY" "$HOST" "cat > '$REMOTE_DIR/meta.json' <<EOF
{\"version\":\"1.0\",\"build\":\"manual\",\"updatedAt\":\"$NOW\",\"sizeBytes\":$SIZE}
EOF
chmod 644 '$REMOTE_DIR/AuthorToday.ipa' '$REMOTE_DIR/meta.json'
ls -lh '$REMOTE_DIR/AuthorToday.ipa'"

echo "Done: https://tv.theinquisitor.ru/chitalnya/"
