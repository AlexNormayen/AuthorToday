#!/usr/bin/env bash
set -euo pipefail
chmod 755 /opt/chitalnya/notify_api.py
CONF=/etc/nginx/vhosts/at.theinquisitor.ru/chitalnya.conf
if [ -f "$CONF" ] && ! grep -q 'location ^~ /chitalnya/api/notify-' "$CONF"; then
  python3 <<'PY'
from pathlib import Path
path = Path("/etc/nginx/vhosts/at.theinquisitor.ru/chitalnya.conf")
text = path.read_text()
for marker in (
    "    location ^~ /chitalnya/api/pro-",
    "    location /chitalnya/api/",
):
    if marker in text:
        break
else:
    raise SystemExit("nginx marker not found")
block = """    location ^~ /chitalnya/api/notify- {
        proxy_pass http://127.0.0.1:8793;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
    }

"""
path.write_text(text.replace(marker, block + marker, 1))
print("nginx: inserted notify location before", marker.strip())
PY
else
  echo "nginx: notify location already present or conf missing"
fi

cat > /etc/systemd/system/chitalnya-notify.service <<'EOF'
[Unit]
Description=Chitalnya Author.Today notification relay
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/chitalnya
Environment=CHITALNYA_ROOT=/opt/chitalnya
ExecStart=/usr/bin/python3 /opt/chitalnya/notify_api.py
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable chitalnya-notify
systemctl restart chitalnya-notify
nginx -t
systemctl reload nginx
sleep 1
systemctl is-active chitalnya-notify
curl -sS http://127.0.0.1:8793/chitalnya/api/notify-health || curl -sS http://127.0.0.1:8793/notify-health
echo
curl -sS -o /dev/null -w "public:%{http_code}\n" https://at.theinquisitor.ru/chitalnya/api/notify-health
