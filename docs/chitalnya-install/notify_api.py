#!/usr/bin/env python3
"""Читальня — VPS relay for Author.Today notifications + optional APNs.

Stores opt-in AT bearer tokens, polls api.author.today, exposes a cheap delta
endpoint, and can push via Apple APNs when .p8 credentials are configured.

Auth for all routes: Authorization: Bearer <BOOK_VAULT_TOKEN>

Listen: 127.0.0.1:8793
Env: /opt/chitalnya/.notify_env
DB:  /opt/chitalnya/notify.db
"""
from __future__ import annotations

import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

ROOT = Path(os.environ.get("CHITALNYA_ROOT", "/opt/chitalnya"))
ENV_PATH = ROOT / ".notify_env"
DB_PATH = ROOT / "notify.db"
HOST = os.environ.get("NOTIFY_API_HOST", "127.0.0.1")
PORT = int(os.environ.get("NOTIFY_API_PORT", "8793"))

AT_API = "https://api.author.today"
UA = (
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Chitalnya/7.2.0"
)
DEFAULT_TOKEN = "4db49ebc4117e7a44602e94dc5ea43bb"
DEFAULT_BUNDLE = "ru.chitalnya.reader"


def load_env_file(path: Path) -> None:
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value


load_env_file(ENV_PATH)

BOOK_VAULT_TOKEN = (os.environ.get("BOOK_VAULT_TOKEN") or DEFAULT_TOKEN).strip()
POLL_SECONDS = max(30, int(os.environ.get("NOTIFY_POLL_SECONDS") or "45"))

APNS_KEY_ID = (os.environ.get("APNS_KEY_ID") or "").strip()
APNS_TEAM_ID = (os.environ.get("APNS_TEAM_ID") or "57FVB8DUWX").strip()
APNS_BUNDLE_ID = (os.environ.get("APNS_BUNDLE_ID") or DEFAULT_BUNDLE).strip()
APNS_KEY_PATH = Path(os.environ.get("APNS_KEY_PATH") or str(ROOT / "AuthKey_APNs.p8"))
APNS_USE_SANDBOX_DEFAULT = (os.environ.get("APNS_USE_SANDBOX") or "").strip().lower() in {
    "1",
    "true",
    "yes",
}

_apns_jwt: str | None = None
_apns_jwt_at = 0.0
_apns_lock = threading.Lock()
_httpx_client = None


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime | None = None) -> str:
    dt = dt or utc_now()
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db() -> None:
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS subscribers (
              user_id INTEGER PRIMARY KEY,
              at_token TEXT NOT NULL,
              enabled INTEGER NOT NULL DEFAULT 1,
              last_check_at TEXT,
              last_unread INTEGER,
              last_error TEXT,
              registered_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id INTEGER NOT NULL,
              notification_id TEXT NOT NULL,
              title TEXT,
              body TEXT,
              work_id INTEGER,
              post_id INTEGER,
              created_at TEXT,
              seen_at TEXT NOT NULL,
              UNIQUE(user_id, notification_id)
            );
            CREATE INDEX IF NOT EXISTS idx_events_user_seen
              ON events(user_id, seen_at);
            CREATE TABLE IF NOT EXISTS device_tokens (
              device_token TEXT PRIMARY KEY,
              user_id INTEGER NOT NULL,
              environment TEXT NOT NULL DEFAULT 'production',
              bundle_id TEXT,
              updated_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_device_user ON device_tokens(user_id);
            """
        )


def apns_configured() -> bool:
    return bool(APNS_KEY_ID and APNS_TEAM_ID and APNS_KEY_PATH.is_file())


def apns_jwt() -> str | None:
    global _apns_jwt, _apns_jwt_at
    if not apns_configured():
        return None
    with _apns_lock:
        if _apns_jwt and (time.time() - _apns_jwt_at) < 3000:
            return _apns_jwt
        try:
            import jwt  # PyJWT
        except ImportError:
            print("notify: PyJWT missing — pip install PyJWT cryptography httpx[http2]", flush=True)
            return None
        key = APNS_KEY_PATH.read_text(encoding="utf-8")
        token = jwt.encode(
            {"iss": APNS_TEAM_ID, "iat": int(time.time())},
            key,
            algorithm="ES256",
            headers={"alg": "ES256", "kid": APNS_KEY_ID},
        )
        if isinstance(token, bytes):
            token = token.decode("ascii")
        _apns_jwt = token
        _apns_jwt_at = time.time()
        return _apns_jwt


def httpx_client():
    global _httpx_client
    if _httpx_client is not None:
        return _httpx_client
    try:
        import httpx
    except ImportError:
        print("notify: httpx missing — pip install 'httpx[http2]'", flush=True)
        return None
    _httpx_client = httpx.Client(http2=True, timeout=20.0)
    return _httpx_client


def send_apns(
    device_token: str,
    *,
    title: str,
    body: str,
    environment: str,
    bundle_id: str | None,
    work_id: int | None = None,
    post_id: int | None = None,
) -> tuple[bool, str]:
    token = apns_jwt()
    if not token:
        return False, "apns not configured"
    client = httpx_client()
    if client is None:
        return False, "httpx unavailable"
    topic = (bundle_id or APNS_BUNDLE_ID).strip() or APNS_BUNDLE_ID
    host = (
        "api.sandbox.push.apple.com"
        if environment == "sandbox" or APNS_USE_SANDBOX_DEFAULT
        else "api.push.apple.com"
    )
    url = f"https://{host}/3/device/{device_token}"
    payload: dict[str, Any] = {
        "aps": {
            "alert": {"title": title[:80] or "Читальня", "body": (body or "")[:240]},
            "sound": "default",
        }
    }
    if work_id:
        payload["workId"] = work_id
    if post_id:
        payload["postId"] = post_id
    headers = {
        "authorization": f"bearer {token}",
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
    }
    try:
        resp = client.post(url, headers=headers, content=json.dumps(payload).encode("utf-8"))
    except Exception as exc:
        return False, str(exc)
    if resp.status_code == 200:
        return True, "ok"
    detail = resp.text[:200]
    if resp.status_code == 410:
        with db() as conn:
            conn.execute("DELETE FROM device_tokens WHERE device_token = ?", (device_token,))
        return False, f"410 unregistered: {detail}"
    return False, f"{resp.status_code}: {detail}"


def push_event_to_user(user_id: int, event: dict[str, Any]) -> None:
    if not apns_configured():
        return
    with db() as conn:
        rows = conn.execute(
            "SELECT device_token, environment, bundle_id FROM device_tokens WHERE user_id = ?",
            (user_id,),
        ).fetchall()
    if not rows:
        return
    title = event.get("title") or "Читальня"
    body = event.get("body") or "Новое уведомление Author.Today"
    for row in rows:
        ok, msg = send_apns(
            row["device_token"],
            title=title,
            body=body,
            environment=(row["environment"] or "production"),
            bundle_id=row["bundle_id"],
            work_id=event.get("workId"),
            post_id=event.get("postId"),
        )
        print(f"notify: apns user={user_id} ok={ok} {msg}", flush=True)


def require_bearer(handler: BaseHTTPRequestHandler) -> bool:
    auth = handler.headers.get("Authorization") or ""
    token = handler.headers.get("X-Vault-Token") or ""
    ok = auth == f"Bearer {BOOK_VAULT_TOKEN}" or token == BOOK_VAULT_TOKEN
    if not ok:
        handler.send_error(401, "Unauthorized")
    return ok


def read_json(handler: BaseHTTPRequestHandler) -> dict[str, Any]:
    length = int(handler.headers.get("Content-Length") or "0")
    raw = handler.rfile.read(length) if length > 0 else b"{}"
    try:
        data = json.loads(raw.decode("utf-8") or "{}")
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def write_json(handler: BaseHTTPRequestHandler, code: int, payload: dict[str, Any]) -> None:
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(body)


def at_get(path: str, token: str, query: dict[str, str] | None = None) -> tuple[int, Any]:
    qs = f"?{urllib.parse.urlencode(query)}" if query else ""
    url = f"{AT_API}{path}{qs}"
    req = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": UA,
            "App-Version": "7.2.0",
        },
        method="GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=25) as resp:
            raw = resp.read()
            try:
                return resp.status, json.loads(raw.decode("utf-8"))
            except json.JSONDecodeError:
                return resp.status, None
    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", "replace")[:200]
        except Exception:
            detail = str(exc)
        return exc.code, {"error": detail}
    except Exception as exc:
        return 0, {"error": str(exc)}


def extract_unread(check: Any) -> int | None:
    if not isinstance(check, dict):
        return None
    for key in ("count", "unreadCount", "unread", "totalUnread", "Count"):
        val = check.get(key)
        if isinstance(val, bool):
            continue
        if isinstance(val, (int, float)):
            return int(val)
        if isinstance(val, str) and val.isdigit():
            return int(val)
    # Nested wrappers
    for key in ("data", "result", "notificationCheck"):
        nested = check.get(key)
        if isinstance(nested, dict):
            got = extract_unread(nested)
            if got is not None:
                return got
    has = check.get("hasUnread") or check.get("HasUnread")
    if isinstance(has, bool):
        return 1 if has else 0
    return None


def normalize_entry(entry: dict[str, Any]) -> dict[str, Any] | None:
    nid = entry.get("notificationId") or entry.get("NotificationId")
    if nid is None:
        # Fallback synthetic id
        item = entry.get("itemId") or entry.get("id") or entry.get("workId")
        created = entry.get("creationTime") or entry.get("publishTime") or ""
        if item is None:
            return None
        nid = f"{item}:{created}"
    nid = str(nid)
    title = entry.get("title") or entry.get("chapterTitle") or ""
    preview = entry.get("previewText") or entry.get("text") or entry.get("message") or ""
    body = title
    if preview and preview != title:
        body = f"{title}\n{preview}".strip() if title else preview
    work_id = entry.get("workId") or entry.get("workID") or entry.get("id")
    post_id = None
    type_name = str(entry.get("type") or entry.get("actionType") or "").lower()
    if "post" in type_name or "blog" in type_name:
        post_id = entry.get("itemId") or entry.get("id")
        work_id = None
    try:
        work_id_i = int(work_id) if work_id is not None else None
    except (TypeError, ValueError):
        work_id_i = None
    try:
        post_id_i = int(post_id) if post_id is not None else None
    except (TypeError, ValueError):
        post_id_i = None
    return {
        "notificationId": nid,
        "title": (title or "Читальня")[:180],
        "body": (body or "Новое уведомление Author.Today")[:500],
        "workId": work_id_i,
        "postId": post_id_i,
        "createdAt": entry.get("creationTime") or entry.get("publishTime"),
    }


def poll_user(user_id: int, token: str) -> tuple[int, str | None]:
    """Returns (inserted_count, error)."""
    code, check = at_get("/v1/notification/check", token)
    if code == 401 or code == 403:
        return 0, f"AT auth {code}"
    if code != 200:
        return 0, f"check HTTP {code}: {check}"

    unread = extract_unread(check)
    with db() as conn:
        row = conn.execute(
            "SELECT last_unread FROM subscribers WHERE user_id = ?",
            (user_id,),
        ).fetchone()
        prev = row["last_unread"] if row else None

    # Always refresh feed lightly; cheap when nothing new, catches first-run.
    should_fetch = prev is None or (unread is not None and unread != prev) or (unread or 0) > 0
    inserted = 0
    if should_fetch:
        code2, page = at_get(
            "/v1/notification/get",
            token,
            {"take": "30"},
        )
        if code2 != 200 or not isinstance(page, dict):
            with db() as conn:
                conn.execute(
                    """
                    UPDATE subscribers
                    SET last_check_at = ?, last_error = ?, updated_at = ?
                    WHERE user_id = ?
                    """,
                    (iso(), f"get HTTP {code2}", iso(), user_id),
                )
            return 0, f"get HTTP {code2}"

        items = page.get("items") or page.get("Notifications") or page.get("data") or []
        if not isinstance(items, list):
            items = []
        now = iso()
        new_events: list[dict[str, Any]] = []
        with db() as conn:
            for raw in items:
                if not isinstance(raw, dict):
                    continue
                norm = normalize_entry(raw)
                if not norm:
                    continue
                cur = conn.execute(
                    """
                    INSERT OR IGNORE INTO events
                      (user_id, notification_id, title, body, work_id, post_id, created_at, seen_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        user_id,
                        norm["notificationId"],
                        norm["title"],
                        norm["body"],
                        norm["workId"],
                        norm["postId"],
                        norm["createdAt"],
                        now,
                    ),
                )
                if cur.rowcount:
                    inserted += 1
                    new_events.append(norm)

        # First seed after register: do not spam APNs for the whole backlog.
        with db() as conn:
            row = conn.execute(
                "SELECT registered_at, last_check_at FROM subscribers WHERE user_id = ?",
                (user_id,),
            ).fetchone()
        first_poll = bool(row and row["last_check_at"] is None)
        if not first_poll:
            for ev in new_events:
                push_event_to_user(user_id, ev)

    with db() as conn:
        conn.execute(
            """
            UPDATE subscribers
            SET last_check_at = ?, last_unread = COALESCE(?, last_unread),
                last_error = NULL, updated_at = ?
            WHERE user_id = ?
            """,
            (iso(), unread, iso(), user_id),
        )
    return inserted, None


def worker_loop() -> None:
    while True:
        try:
            with db() as conn:
                rows = conn.execute(
                    "SELECT user_id, at_token FROM subscribers WHERE enabled = 1"
                ).fetchall()
            for row in rows:
                uid = int(row["user_id"])
                token = row["at_token"]
                try:
                    inserted, err = poll_user(uid, token)
                    if err:
                        with db() as conn:
                            conn.execute(
                                """
                                UPDATE subscribers
                                SET last_error = ?, last_check_at = ?, updated_at = ?
                                WHERE user_id = ?
                                """,
                                (err[:300], iso(), iso(), uid),
                            )
                            if "AT auth" in err:
                                conn.execute(
                                    "UPDATE subscribers SET enabled = 0 WHERE user_id = ?",
                                    (uid,),
                                )
                    elif inserted:
                        print(f"notify: user {uid} +{inserted} events", flush=True)
                except Exception as exc:
                    print(f"notify: user {uid} error {exc}", flush=True)
                time.sleep(0.4)
        except Exception as exc:
            print(f"notify: worker {exc}", flush=True)
        time.sleep(POLL_SECONDS)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"notify_api: {self.address_string()} {fmt % args}", flush=True)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        qs = urllib.parse.parse_qs(parsed.query)

        if path.endswith("/notify-health") or path.endswith("/health"):
            write_json(
                self,
                200,
                {
                    "ok": True,
                    "pollSeconds": POLL_SECONDS,
                    "apnsConfigured": apns_configured(),
                },
            )
            return

        if not require_bearer(self):
            return

        if path.endswith("/notify-status"):
            try:
                user_id = int((qs.get("userId") or qs.get("user_id") or ["0"])[0])
            except ValueError:
                write_json(self, 400, {"error": "userId required"})
                return
            with db() as conn:
                row = conn.execute(
                    "SELECT * FROM subscribers WHERE user_id = ?",
                    (user_id,),
                ).fetchone()
                count = conn.execute(
                    "SELECT COUNT(*) AS c FROM events WHERE user_id = ?",
                    (user_id,),
                ).fetchone()["c"]
            if not row:
                write_json(self, 200, {"registered": False, "enabled": False})
                return
            write_json(
                self,
                200,
                {
                    "registered": True,
                    "enabled": bool(row["enabled"]),
                    "lastCheckAt": row["last_check_at"],
                    "lastUnread": row["last_unread"],
                    "lastError": row["last_error"],
                    "eventCount": count,
                    "pollSeconds": POLL_SECONDS,
                },
            )
            return

        if path.endswith("/notify-delta"):
            try:
                user_id = int((qs.get("userId") or qs.get("user_id") or ["0"])[0])
            except ValueError:
                write_json(self, 400, {"error": "userId required"})
                return
            since = (qs.get("since") or [""])[0].strip()
            with db() as conn:
                if since:
                    rows = conn.execute(
                        """
                        SELECT notification_id, title, body, work_id, post_id, created_at, seen_at
                        FROM events
                        WHERE user_id = ? AND seen_at > ?
                        ORDER BY seen_at ASC
                        LIMIT 50
                        """,
                        (user_id, since),
                    ).fetchall()
                else:
                    rows = conn.execute(
                        """
                        SELECT notification_id, title, body, work_id, post_id, created_at, seen_at
                        FROM events
                        WHERE user_id = ?
                        ORDER BY seen_at DESC
                        LIMIT 20
                        """,
                        (user_id,),
                    ).fetchall()
                sub = conn.execute(
                    "SELECT enabled, last_check_at, last_error FROM subscribers WHERE user_id = ?",
                    (user_id,),
                ).fetchone()
            items = [
                {
                    "id": r["notification_id"],
                    "title": r["title"],
                    "body": r["body"],
                    "workId": r["work_id"],
                    "postId": r["post_id"],
                    "createdAt": r["created_at"],
                    "seenAt": r["seen_at"],
                }
                for r in rows
            ]
            # For since= empty we returned newest-first; delta consumers expect chrono.
            if not since:
                items.reverse()
            write_json(
                self,
                200,
                {
                    "items": items,
                    "serverTime": iso(),
                    "enabled": bool(sub["enabled"]) if sub else False,
                    "lastCheckAt": sub["last_check_at"] if sub else None,
                    "lastError": sub["last_error"] if sub else None,
                },
            )
            return

        self.send_error(404, "Not found")

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if not require_bearer(self):
            return
        data = read_json(self)

        if path.endswith("/notify-register"):
            try:
                user_id = int(data.get("userId") or data.get("user_id") or 0)
            except (TypeError, ValueError):
                user_id = 0
            token = (data.get("atToken") or data.get("token") or "").strip()
            enabled = bool(data.get("enabled", True))
            if user_id <= 0 or not token or token == "guest":
                write_json(self, 400, {"error": "userId and atToken required"})
                return
            now = iso()
            with db() as conn:
                conn.execute(
                    """
                    INSERT INTO subscribers
                      (user_id, at_token, enabled, registered_at, updated_at, last_error)
                    VALUES (?, ?, ?, ?, ?, NULL)
                    ON CONFLICT(user_id) DO UPDATE SET
                      at_token = excluded.at_token,
                      enabled = excluded.enabled,
                      updated_at = excluded.updated_at,
                      last_error = NULL
                    """,
                    (user_id, token, 1 if enabled else 0, now, now),
                )
            # Immediate first poll so delta is useful right away.
            inserted, err = poll_user(user_id, token)
            write_json(
                self,
                200,
                {
                    "ok": True,
                    "userId": user_id,
                    "enabled": enabled,
                    "seeded": inserted,
                    "error": err,
                    "pollSeconds": POLL_SECONDS,
                },
            )
            return

        if path.endswith("/notify-unregister"):
            try:
                user_id = int(data.get("userId") or data.get("user_id") or 0)
            except (TypeError, ValueError):
                user_id = 0
            if user_id <= 0:
                write_json(self, 400, {"error": "userId required"})
                return
            with db() as conn:
                conn.execute("UPDATE subscribers SET enabled = 0, updated_at = ? WHERE user_id = ?", (iso(), user_id))
                # Keep events; drop token for privacy when fully unregistering.
                if data.get("forgetToken"):
                    conn.execute(
                        "UPDATE subscribers SET at_token = '', updated_at = ? WHERE user_id = ?",
                        (iso(), user_id),
                    )
            write_json(self, 200, {"ok": True})
            return

        if path.endswith("/notify-poll-now"):
            try:
                user_id = int(data.get("userId") or data.get("user_id") or 0)
            except (TypeError, ValueError):
                user_id = 0
            with db() as conn:
                row = conn.execute(
                    "SELECT at_token, enabled FROM subscribers WHERE user_id = ?",
                    (user_id,),
                ).fetchone()
            if not row or not row["enabled"] or not row["at_token"]:
                write_json(self, 404, {"error": "not registered"})
                return
            inserted, err = poll_user(user_id, row["at_token"])
            write_json(self, 200, {"ok": err is None, "inserted": inserted, "error": err})
            return

        if path.endswith("/notify-device"):
            try:
                user_id = int(data.get("userId") or data.get("user_id") or 0)
            except (TypeError, ValueError):
                user_id = 0
            device_token = (data.get("deviceToken") or data.get("token") or "").strip().lower()
            if user_id <= 0 or not device_token:
                write_json(self, 400, {"error": "userId and deviceToken required"})
                return
            if data.get("forget"):
                with db() as conn:
                    conn.execute(
                        "DELETE FROM device_tokens WHERE device_token = ? AND user_id = ?",
                        (device_token, user_id),
                    )
                write_json(self, 200, {"ok": True, "removed": True})
                return
            environment = (data.get("environment") or "production").strip().lower()
            if environment not in ("production", "sandbox"):
                environment = "production"
            bundle_id = (data.get("bundleId") or APNS_BUNDLE_ID).strip()
            with db() as conn:
                conn.execute(
                    """
                    INSERT INTO device_tokens (device_token, user_id, environment, bundle_id, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(device_token) DO UPDATE SET
                      user_id = excluded.user_id,
                      environment = excluded.environment,
                      bundle_id = excluded.bundle_id,
                      updated_at = excluded.updated_at
                    """,
                    (device_token, user_id, environment, bundle_id, iso()),
                )
            write_json(
                self,
                200,
                {
                    "ok": True,
                    "apnsConfigured": apns_configured(),
                    "environment": environment,
                },
            )
            return

        self.send_error(404, "Not found")


def main() -> None:
    init_db()
    t = threading.Thread(target=worker_loop, name="notify-worker", daemon=True)
    t.start()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(
        f"notify_api on http://{HOST}:{PORT} · poll every {POLL_SECONDS}s · apns={apns_configured()}",
        flush=True,
    )
    httpd.serve_forever()


if __name__ == "__main__":
    main()
