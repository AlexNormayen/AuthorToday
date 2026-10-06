#!/usr/bin/env python3
"""Читальня Pro — checkout (YooKassa) + webhook auto-grant + status API.

Env file: /opt/chitalnya/.pro_env
  YOOKASSA_SHOP_ID=...
  YOOKASSA_SECRET_KEY=...
  PRO_PUBLIC_BASE=https://at.theinquisitor.ru
  PRO_VAT_CODE=1          # optional, 54-FZ receipt (1 = без НДС)
  PRO_TAX_SYSTEM_CODE=1   # optional

Listen: 127.0.0.1:8792
"""
from __future__ import annotations

import json
import os
import sqlite3
import uuid
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(os.environ.get("CHITALNYA_ROOT", "/opt/chitalnya"))
ENV_PATH = ROOT / ".pro_env"
DB_PATH = ROOT / "pro.db"
HOST = os.environ.get("PRO_API_HOST", "127.0.0.1")
PORT = int(os.environ.get("PRO_API_PORT", "8792"))

PLANS: dict[str, dict] = {
    "week": {"days": 7, "amount": "149.00", "title": "Читальня Pro — 7 дней"},
    "month": {"days": 30, "amount": "349.00", "title": "Читальня Pro — 30 дней"},
    "year": {"days": 365, "amount": "2990.00", "title": "Читальня Pro — 365 дней"},
}

# https://yookassa.ru/developers/using-api/webhooks#ip
YOOKASSA_IPS = {
    "185.71.76.0/27",
    "185.71.77.0/27",
    "77.75.153.0/25",
    "77.75.156.11",
    "77.75.156.35",
    "2a02:5180::/32",
}


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

SHOP_ID = (os.environ.get("YOOKASSA_SHOP_ID") or "").strip()
SECRET_KEY = (os.environ.get("YOOKASSA_SECRET_KEY") or "").strip()
PUBLIC_BASE = (os.environ.get("PRO_PUBLIC_BASE") or "https://at.theinquisitor.ru").rstrip("/")
VAT_CODE = int(os.environ.get("PRO_VAT_CODE") or "1")
TAX_SYSTEM = os.environ.get("PRO_TAX_SYSTEM_CODE")  # optional


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def iso(dt: datetime | None) -> str | None:
    if not dt:
        return None
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(raw: str | None) -> datetime | None:
    if not raw:
        return None
    text = raw.strip().replace("Z", "+00:00")
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def normalize(raw: str | None) -> str | None:
    if not raw:
        return None
    value = raw.strip().lower()
    return value or None


def db() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def init_db() -> None:
    with db() as conn:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS payments (
              payment_id TEXT PRIMARY KEY,
              plan TEXT NOT NULL,
              amount TEXT NOT NULL,
              email TEXT,
              user_name TEXT,
              status TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS grants (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              email TEXT,
              user_name TEXT,
              expires_at TEXT,
              payment_id TEXT UNIQUE,
              plan TEXT,
              created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_grants_email ON grants(email);
            CREATE INDEX IF NOT EXISTS idx_grants_user ON grants(user_name);
            """
        )


def yookassa_configured() -> bool:
    return bool(SHOP_ID and SECRET_KEY)


def yookassa_request(method: str, path: str, payload: dict | None = None) -> dict:
    if not yookassa_configured():
        raise RuntimeError("YooKassa credentials missing (.pro_env)")
    url = "https://api.yookassa.ru/v3" + path
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    token = f"{SHOP_ID}:{SECRET_KEY}".encode("utf-8")
    import base64

    req.add_header("Authorization", "Basic " + base64.b64encode(token).decode("ascii"))
    req.add_header("Content-Type", "application/json")
    if method == "POST":
        req.add_header("Idempotence-Key", str(uuid.uuid4()))
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = resp.read().decode("utf-8")
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"YooKassa HTTP {exc.code}: {detail}") from exc


def create_payment(plan_id: str, email: str | None, user_name: str | None) -> dict:
    plan = PLANS[plan_id]
    if not email and not user_name:
        raise ValueError("укажите email или логин Author.Today")
    return_url = f"{PUBLIC_BASE}/chitalnya/pro-return.html"
    metadata = {
        "plan": plan_id,
        "email": email or "",
        "user": user_name or "",
        "product": "chitalnya_pro",
    }
    payload: dict = {
        "amount": {"value": plan["amount"], "currency": "RUB"},
        "capture": True,
        "confirmation": {"type": "redirect", "return_url": return_url},
        "description": plan["title"],
        "metadata": metadata,
    }
    # 54-FZ receipt when shop requires it
    customer: dict = {}
    if email and "@" in email:
        customer["email"] = email
    if customer:
        payload["receipt"] = {
            "customer": customer,
            "items": [
                {
                    "description": plan["title"][:128],
                    "quantity": "1.00",
                    "amount": {"value": plan["amount"], "currency": "RUB"},
                    "vat_code": VAT_CODE,
                    "payment_mode": "full_payment",
                    "payment_subject": "service",
                }
            ],
        }
        if TAX_SYSTEM:
            payload["receipt"]["tax_system_code"] = int(TAX_SYSTEM)

    payment = yookassa_request("POST", "/payments", payload)
    payment_id = payment.get("id")
    confirm = (payment.get("confirmation") or {}).get("confirmation_url")
    if not payment_id or not confirm:
        raise RuntimeError(f"unexpected YooKassa response: {payment}")

    now = iso(utc_now()) or ""
    with db() as conn:
        conn.execute(
            """
            INSERT OR REPLACE INTO payments
              (payment_id, plan, amount, email, user_name, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                payment_id,
                plan_id,
                plan["amount"],
                email,
                user_name,
                payment.get("status") or "pending",
                now,
                now,
            ),
        )
    return {"paymentId": payment_id, "confirmationUrl": confirm}


def extend_expiry(current: datetime | None, days: int) -> datetime:
    base = current if current and current > utc_now() else utc_now()
    return base + timedelta(days=days)


def apply_succeeded_payment(payment: dict) -> bool:
    """Grant Pro from a succeeded YooKassa payment object. Idempotent."""
    if payment.get("status") != "succeeded":
        return False
    payment_id = payment.get("id")
    if not payment_id:
        return False
    meta = payment.get("metadata") or {}
    plan_id = normalize(str(meta.get("plan") or "")) or ""
    if plan_id not in PLANS:
        # fall back to local payments row
        with db() as conn:
            row = conn.execute(
                "SELECT plan, email, user_name FROM payments WHERE payment_id = ?",
                (payment_id,),
            ).fetchone()
        if not row:
            return False
        plan_id = row["plan"]
        email = normalize(row["email"])
        user_name = normalize(row["user_name"])
    else:
        email = normalize(str(meta.get("email") or "")) or None
        user_name = normalize(str(meta.get("user") or "")) or None
        with db() as conn:
            row = conn.execute(
                "SELECT email, user_name FROM payments WHERE payment_id = ?",
                (payment_id,),
            ).fetchone()
            if row:
                email = email or normalize(row["email"])
                user_name = user_name or normalize(row["user_name"])

    if plan_id not in PLANS:
        return False
    if not email and not user_name:
        return False

    days = int(PLANS[plan_id]["days"])
    now = utc_now()
    with db() as conn:
        existing = conn.execute(
            "SELECT payment_id FROM grants WHERE payment_id = ?",
            (payment_id,),
        ).fetchone()
        if existing:
            conn.execute(
                "UPDATE payments SET status = ?, updated_at = ? WHERE payment_id = ?",
                ("succeeded", iso(now), payment_id),
            )
            return True

        # Find current active grant for same identity to stack days
        clauses = []
        args: list[str] = []
        if email:
            clauses.append("email = ?")
            args.append(email)
        if user_name:
            clauses.append("user_name = ?")
            args.append(user_name)
        current_exp: datetime | None = None
        if clauses:
            q = (
                f"SELECT expires_at FROM grants WHERE ({' OR '.join(clauses)}) "
                "ORDER BY expires_at DESC LIMIT 1"
            )
            row = conn.execute(q, args).fetchone()
            if row:
                current_exp = parse_iso(row["expires_at"])

        expires = extend_expiry(current_exp, days)
        conn.execute(
            """
            INSERT INTO grants (email, user_name, expires_at, payment_id, plan, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (email, user_name, iso(expires), payment_id, plan_id, iso(now)),
        )
        conn.execute(
            "UPDATE payments SET status = ?, updated_at = ? WHERE payment_id = ?",
            ("succeeded", iso(now), payment_id),
        )
    return True


def fetch_and_apply(payment_id: str) -> bool:
    payment = yookassa_request("GET", f"/payments/{payment_id}")
    return apply_succeeded_payment(payment)


def active_grant(email: str | None, user: str | None) -> tuple[bool, str | None]:
    if not email and not user:
        return False, None
    now = utc_now()
    with db() as conn:
        rows = conn.execute(
            "SELECT email, user_name, expires_at FROM grants"
        ).fetchall()
    best: datetime | None = None
    for row in rows:
        g_email = normalize(row["email"])
        g_user = normalize(row["user_name"])
        hit = (email and g_email and email == g_email) or (
            user and g_user and user == g_user
        )
        if not hit and user and g_email and user == g_email:
            hit = True
        if not hit:
            continue
        exp = parse_iso(row["expires_at"])
        if exp and exp <= now:
            continue
        if exp is None:
            return True, None
        if best is None or exp > best:
            best = exp
    if best:
        return True, iso(best)
    return False, None


def read_json(handler: BaseHTTPRequestHandler) -> dict:
    length = int(handler.headers.get("Content-Length") or "0")
    if length <= 0:
        return {}
    if length > 1_000_000:
        raise ValueError("body too large")
    raw = handler.rfile.read(length)
    return json.loads(raw.decode("utf-8"))


def client_ip(handler: BaseHTTPRequestHandler) -> str:
    forwarded = handler.headers.get("X-Real-IP") or handler.headers.get("X-Forwarded-For")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return handler.client_address[0]


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        sys_stderr = __import__("sys").stderr
        sys_stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", PUBLIC_BASE)
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _send(self, code: int, payload: dict) -> None:
        body = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        qs = urllib.parse.parse_qs(parsed.query)

        if path in {"/chitalnya/api/pro-status", "/pro-status"}:
            email = normalize((qs.get("email") or [None])[0])
            user = normalize((qs.get("user") or [None])[0])
            active, expires = active_grant(email, user)
            payload: dict = {"active": active}
            if expires:
                payload["expiresAt"] = expires
            self._send(200, payload)
            return

        if path in {"/chitalnya/api/pro-config", "/pro-config"}:
            self._send(
                200,
                {
                    "paymentsEnabled": yookassa_configured(),
                    "plans": {
                        key: {
                            "days": val["days"],
                            "amountRub": val["amount"],
                            "title": val["title"],
                        }
                        for key, val in PLANS.items()
                    },
                },
            )
            return

        if path in {"/chitalnya/api/pro-sync", "/pro-sync"}:
            # After return_url: client can force-check payment by id
            payment_id = (qs.get("paymentId") or [None])[0]
            if not payment_id:
                self._send(400, {"error": "paymentId_required"})
                return
            try:
                ok = fetch_and_apply(payment_id)
                self._send(200, {"applied": ok})
            except Exception as exc:  # noqa: BLE001
                self._send(502, {"error": str(exc)})
            return

        self._send(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path in {"/chitalnya/api/pro-checkout", "/pro-checkout"}:
            if not yookassa_configured():
                self._send(503, {"error": "payments_not_configured"})
                return
            try:
                body = read_json(self)
            except Exception:  # noqa: BLE001
                self._send(400, {"error": "invalid_json"})
                return
            plan_id = normalize(str(body.get("plan") or "")) or ""
            email = normalize(str(body.get("email") or ""))
            user_name = normalize(str(body.get("user") or body.get("userName") or ""))
            # Prefer AT login email for receipt; username alone is ok for grant
            if plan_id not in PLANS:
                self._send(400, {"error": "invalid_plan"})
                return
            try:
                result = create_payment(plan_id, email, user_name)
                self._send(200, result)
            except ValueError as exc:
                self._send(400, {"error": str(exc)})
            except Exception as exc:  # noqa: BLE001
                self._send(502, {"error": str(exc)})
            return

        if path in {"/chitalnya/api/pro-webhook", "/pro-webhook"}:
            try:
                body = read_json(self)
            except Exception:  # noqa: BLE001
                self._send(400, {"error": "invalid_json"})
                return
            event = body.get("event")
            obj = body.get("object") or {}
            payment_id = obj.get("id")
            # Always verify with API (do not trust payload alone)
            if event == "payment.succeeded" and payment_id:
                try:
                    fetch_and_apply(str(payment_id))
                except Exception as exc:  # noqa: BLE001
                    self.log_message("webhook apply failed: %s", exc)
                    self._send(500, {"error": "apply_failed"})
                    return
            # YooKassa only checks HTTP 200
            self._send(200, {"ok": True})
            return

        self._send(404, {"error": "not_found"})


def main() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    init_db()
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    status = "configured" if yookassa_configured() else "MISSING credentials in .pro_env"
    print(f"pro_api on http://{HOST}:{PORT} · YooKassa {status}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
