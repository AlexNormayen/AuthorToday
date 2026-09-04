#!/usr/bin/env bash
# Publish one IPA as a new version on the VPS install page (keeps history).
#
# Usage:
#   ./scripts/publish-ipa-version.sh --app chitalnya /path/to/AuthorToday.ipa
#   ./scripts/publish-ipa-version.sh --app tubevault /path/to/TubeVault.ipa
#
# Optional flags:
#   --id VERSION_ID          default: b{BUILD}-{shortCommit} or manual-{timestamp}
#   --label "human label"
#   --sync-page              also upload docs/chitalnya-install/index.html (AuthorToday repo)
#   --no-latest              do not overwrite root AuthorToday.ipa / TubeVault.ipa
#
# Env:
#   CHITALNYA_VPS_HOST=root@185.125.103.168
#   CHITALNYA_SSH_KEY=~/.ssh/id_ed25519_aeza   (path to key; optional if ssh-agent has it)
#   PROJECT_BUILD_NUMBER, CM_COMMIT, CM_BRANCH  (CodeMagic)

set -euo pipefail

HOST="${CHITALNYA_VPS_HOST:-root@185.125.103.168}"
KEY_PATH="${CHITALNYA_SSH_KEY:-${HOME}/.ssh/id_ed25519_aeza}"
REMOTE_DIR="/opt/chitalnya"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCAL_HTML=""
if [[ -f "$ROOT/docs/chitalnya-install/index.html" ]]; then
  LOCAL_HTML="$ROOT/docs/chitalnya-install/index.html"
fi

APP=""
IPA=""
VERSION_ID=""
LABEL=""
SYNC_PAGE=0
UPDATE_LATEST=1

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes)
if [[ -f "$KEY_PATH" ]]; then
  SSH_OPTS+=(-i "$KEY_PATH")
fi

remote_name() {
  case "$1" in
    chitalnya) echo AuthorToday.ipa ;;
    tubevault) echo TubeVault.ipa ;;
    *) return 1 ;;
  esac
}

app_title() {
  case "$1" in
    chitalnya) echo "Читальня" ;;
    tubevault) echo "TubeVault" ;;
    *) echo "$1" ;;
  esac
}

short_commit() {
  local c="${CM_COMMIT:-}"
  if [[ -z "$c" ]] && command -v git >/dev/null 2>&1; then
    c="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  if [[ -n "$c" ]]; then
    echo "${c:0:7}"
  else
    echo ""
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="${2:-}"; shift 2 ;;
    --id) VERSION_ID="${2:-}"; shift 2 ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    --sync-page) SYNC_PAGE=1; shift ;;
    --no-latest) UPDATE_LATEST=0; shift ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      if [[ -z "$IPA" ]]; then
        IPA="$1"
        shift
      else
        echo "Unexpected arg: $1" >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -z "$APP" || -z "$IPA" ]]; then
  echo "Usage: $0 --app chitalnya|tubevault /path/to/App.ipa" >&2
  exit 1
fi
if [[ "$APP" != "chitalnya" && "$APP" != "tubevault" ]]; then
  echo "Unknown app: $APP (expected chitalnya|tubevault)" >&2
  exit 1
fi
if [[ ! -f "$IPA" ]]; then
  echo "IPA not found: $IPA" >&2
  exit 1
fi

RNAME="$(remote_name "$APP")"
TITLE="$(app_title "$APP")"
SIZE="$(wc -c < "$IPA" | tr -d ' ')"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
COMMIT="$(short_commit)"
BRANCH="${CM_BRANCH:-}"
BUILD_NUM="${PROJECT_BUILD_NUMBER:-}"

if [[ -z "$VERSION_ID" ]]; then
  if [[ -n "$BUILD_NUM" && -n "$COMMIT" ]]; then
    VERSION_ID="b${BUILD_NUM}-${COMMIT}"
  elif [[ -n "$BUILD_NUM" ]]; then
    VERSION_ID="b${BUILD_NUM}"
  elif [[ -n "$COMMIT" ]]; then
    VERSION_ID="manual-${COMMIT}-$(date -u +%Y%m%d%H%M%S)"
  else
    VERSION_ID="manual-$(date -u +%Y%m%d%H%M%S)"
  fi
fi

if [[ -z "$LABEL" ]]; then
  parts=()
  [[ -n "$BUILD_NUM" ]] && parts+=("build ${BUILD_NUM}")
  [[ -n "$COMMIT" ]] && parts+=("$COMMIT")
  [[ -n "$BRANCH" ]] && parts+=("$BRANCH")
  if [[ ${#parts[@]} -gt 0 ]]; then
    LABEL="$(IFS=' · '; echo "${parts[*]}")"
  else
    LABEL="$VERSION_ID"
  fi
fi

REL_PATH="builds/${APP}/${VERSION_ID}/${RNAME}"
REMOTE_VERSION_DIR="${REMOTE_DIR}/builds/${APP}/${VERSION_ID}"

echo "Publishing $APP → $REL_PATH ($SIZE bytes, id=$VERSION_ID)"

ssh "${SSH_OPTS[@]}" "$HOST" "mkdir -p '$REMOTE_VERSION_DIR' '$REMOTE_DIR'"

if [[ "$SYNC_PAGE" -eq 1 && -n "$LOCAL_HTML" ]]; then
  scp "${SSH_OPTS[@]}" "$LOCAL_HTML" "$HOST:$REMOTE_DIR/index.html"
fi

scp "${SSH_OPTS[@]}" "$IPA" "$HOST:$REMOTE_VERSION_DIR/$RNAME"
ssh "${SSH_OPTS[@]}" "$HOST" "chmod 644 '$REMOTE_VERSION_DIR/$RNAME'"

if [[ "$UPDATE_LATEST" -eq 1 ]]; then
  ssh "${SSH_OPTS[@]}" "$HOST" "cp -f '$REMOTE_VERSION_DIR/$RNAME' '$REMOTE_DIR/$RNAME' && chmod 644 '$REMOTE_DIR/$RNAME'"
fi

# Merge meta.json on the server
ssh "${SSH_OPTS[@]}" "$HOST" "python3 - <<'PY'
import json, os
from pathlib import Path

remote_dir = Path('${REMOTE_DIR}')
meta_path = remote_dir / 'meta.json'
app = '${APP}'
title = '''${TITLE}'''
rname = '${RNAME}'
vid = '''${VERSION_ID}'''
label = '''${LABEL}'''
rel = '''${REL_PATH}'''
size = int('${SIZE}')
now = '''${NOW}'''
commit = '''${COMMIT}'''
branch = '''${BRANCH}'''
build_num = '''${BUILD_NUM}'''
update_latest = ${UPDATE_LATEST}

try:
    data = json.loads(meta_path.read_text(encoding='utf-8'))
except Exception:
    data = {}

apps = data.get('apps') or {}
# Legacy flat meta → chitalnya shell
if 'sizeBytes' in data and 'chitalnya' not in apps:
    apps['chitalnya'] = {
        'title': 'Читальня',
        'file': 'AuthorToday.ipa',
        'latestId': None,
        'versions': [],
    }

defaults = {
    'chitalnya': {'title': 'Читальня', 'file': 'AuthorToday.ipa'},
    'tubevault': {'title': 'TubeVault', 'file': 'TubeVault.ipa'},
}
entry = dict(defaults.get(app, {'title': title, 'file': rname}))
entry.update(apps.get(app, {}))
entry['title'] = entry.get('title') or title
entry['file'] = rname
versions = list(entry.get('versions') or [])

# Drop duplicate id if re-publishing same build
versions = [v for v in versions if v.get('id') != vid]
new_ver = {
    'id': vid,
    'label': label,
    'file': rel,
    'sizeBytes': size,
    'updatedAt': now,
}
if commit:
    new_ver['commit'] = commit
if branch:
    new_ver['branch'] = branch
if build_num:
    new_ver['buildNumber'] = str(build_num)
versions.insert(0, new_ver)
entry['versions'] = versions
if update_latest:
    entry['latestId'] = vid
    entry['sizeBytes'] = size
    entry['updatedAt'] = now
apps[app] = entry
meta_path.write_text(json.dumps({'apps': apps}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
os.chmod(meta_path, 0o644)
print(meta_path.read_text(encoding='utf-8'))
PY
"

echo "Done: https://tv.theinquisitor.ru/chitalnya/  ($APP $VERSION_ID)"
