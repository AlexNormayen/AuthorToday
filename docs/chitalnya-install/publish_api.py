#!/usr/bin/env python3
"""Accept IPA uploads from Codemagic and publish versioned builds."""
from __future__ import annotations

import json
import os
import re
import shutil
from datetime import datetime, timezone
from email import message_from_bytes
from email.policy import default as email_default
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path("/opt/chitalnya")
TOKEN_PATH = ROOT / ".publish_token"
MAX_BYTES = 120 * 1024 * 1024  # 120 MB


def load_token() -> str:
    return TOKEN_PATH.read_text(encoding="utf-8").strip()


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def remote_name(app: str) -> str:
    return "AuthorToday.ipa" if app == "chitalnya" else "TubeVault.ipa"


def app_title(app: str) -> str:
    return "Читальня" if app == "chitalnya" else "TubeVault"


def safe_id(raw: str) -> str:
    raw = (raw or "").strip()
    raw = re.sub(r"[^A-Za-z0-9._-]+", "-", raw)
    return raw[:80] or f"manual-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"


def merge_meta(app: str, version: dict, update_latest: bool = True) -> None:
    meta_path = ROOT / "meta.json"
    try:
        data = json.loads(meta_path.read_text(encoding="utf-8"))
    except Exception:
        data = {}
    apps = data.get("apps") or {}
    defaults = {
        "chitalnya": {"title": "Читальня", "file": "AuthorToday.ipa"},
        "tubevault": {"title": "TubeVault", "file": "TubeVault.ipa"},
    }
    entry = dict(defaults.get(app, {"title": app_title(app), "file": remote_name(app)}))
    entry.update(apps.get(app, {}))
    entry["title"] = entry.get("title") or app_title(app)
    entry["file"] = remote_name(app)
    versions = [v for v in (entry.get("versions") or []) if v.get("id") != version["id"]]
    versions.insert(0, version)
    entry["versions"] = versions
    if update_latest:
        entry["latestId"] = version["id"]
        entry["sizeBytes"] = version["sizeBytes"]
        entry["updatedAt"] = version["updatedAt"]
    apps[app] = entry
    meta_path.write_text(json.dumps({"apps": apps}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(meta_path, 0o644)


def parse_multipart(content_type: str, raw: bytes) -> tuple[dict[str, str], dict[str, bytes]]:
    headers = f"Content-Type: {content_type}\r\nMIME-Version: 1.0\r\n\r\n".encode("utf-8")
    msg = message_from_bytes(headers + raw, policy=email_default)
    fields: dict[str, str] = {}
    files: dict[str, bytes] = {}
    if not msg.is_multipart():
        return fields, files
    for part in msg.iter_parts():
        name = part.get_param("name", header="content-disposition")
        if not name:
            continue
        payload = part.get_payload(decode=True) or b""
        filename = part.get_filename()
        if filename is not None:
            files[name] = payload
        else:
            charset = part.get_content_charset() or "utf-8"
            fields[name] = payload.decode(charset, "replace")
    return fields, files


class Handler(BaseHTTPRequestHandler):
    server_version = "ChitalnyaPublish/1.0"

    def log_message(self, fmt: str, *args) -> None:
        print("[%s] %s" % (self.log_date_time_string(), fmt % args), flush=True)

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path.split("?", 1)[0].rstrip("/") in ("/health", "/chitalnya/api/health"):
            self._send(200, {"ok": True})
            return
        self._send(404, {"error": "not found"})

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0].rstrip("/")
        if path not in ("/publish", "/chitalnya/api/publish"):
            self._send(404, {"error": "not found"})
            return

        auth = self.headers.get("Authorization", "")
        token = load_token()
        if auth != f"Bearer {token}":
            self._send(401, {"error": "unauthorized"})
            return

        ctype = self.headers.get("Content-Type", "")
        length = int(self.headers.get("Content-Length", "0") or 0)
        if length <= 0 or length > MAX_BYTES:
            self._send(400, {"error": "invalid content length"})
            return
        if "multipart/form-data" not in ctype:
            self._send(400, {"error": "expected multipart/form-data"})
            return

        raw = self.rfile.read(length)
        fields, files = parse_multipart(ctype, raw)

        app = (fields.get("app") or "").strip()
        if app not in ("chitalnya", "tubevault"):
            self._send(400, {"error": "app must be chitalnya|tubevault"})
            return
        ipa = files.get("ipa")
        if not ipa or len(ipa) < 100:
            self._send(400, {"error": "ipa missing or too small"})
            return
        if ipa[:2] != b"PK":
            self._send(400, {"error": "not an IPA/zip"})
            return

        build_num = (fields.get("buildNumber") or "").strip()
        commit = (fields.get("commit") or "").strip()[:40]
        branch = (fields.get("branch") or "").strip()[:80]
        raw_vid = (fields.get("versionId") or "").strip()
        version_id = safe_id(raw_vid) if raw_vid else ""
        if not version_id:
            if build_num and commit:
                version_id = safe_id(f"b{build_num}-{commit[:7]}")
            elif build_num:
                version_id = safe_id(f"b{build_num}")
            elif commit:
                version_id = safe_id(
                    f"manual-{commit[:7]}-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"
                )
            else:
                version_id = safe_id(f"manual-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}")

        label_parts = []
        if build_num:
            label_parts.append(f"build {build_num}")
        if commit:
            label_parts.append(commit[:7])
        if branch:
            label_parts.append(branch)
        label = (fields.get("label") or "").strip() or (
            " · ".join(label_parts) if label_parts else version_id
        )

        rname = remote_name(app)
        dest_dir = ROOT / "builds" / app / version_id
        dest_dir.mkdir(parents=True, exist_ok=True)
        dest = dest_dir / rname
        dest.write_bytes(ipa)
        os.chmod(dest, 0o644)
        latest = ROOT / rname
        shutil.copy2(dest, latest)
        os.chmod(latest, 0o644)

        now = utc_now()
        version = {
            "id": version_id,
            "label": label,
            "file": f"builds/{app}/{version_id}/{rname}",
            "sizeBytes": len(ipa),
            "updatedAt": now,
        }
        if commit:
            version["commit"] = commit[:7]
        if branch:
            version["branch"] = branch
        if build_num:
            version["buildNumber"] = build_num
        merge_meta(app, version, update_latest=True)

        self._send(
            200,
            {
                "ok": True,
                "app": app,
                "versionId": version_id,
                "label": label,
                "sizeBytes": len(ipa),
                "url": f"https://tv.theinquisitor.ru/chitalnya/{version['file']}",
            },
        )


def main() -> None:
    if not TOKEN_PATH.is_file():
        raise SystemExit(f"missing token file: {TOKEN_PATH}")
    host = os.environ.get("PUBLISH_HOST", "127.0.0.1")
    port = int(os.environ.get("PUBLISH_PORT", "8791"))
    httpd = ThreadingHTTPServer((host, port), Handler)
    print(f"listening on {host}:{port}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
