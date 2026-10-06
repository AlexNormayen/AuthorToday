#!/usr/bin/env bash
set -euo pipefail

cat > /etc/systemd/system/chitalnya-pro.service << 'EOF'
[Unit]
Description=Chitalnya Pro payment API (YooKassa)
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/chitalnya
Environment=CHITALNYA_ROOT=/opt/chitalnya
ExecStart=/usr/bin/python3 /opt/chitalnya/pro_api.py
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

chmod +x /opt/chitalnya/pro_api.py
chmod 644 /opt/chitalnya/pro.html /opt/chitalnya/pro-return.html

if [ ! -f /opt/chitalnya/.pro_env ]; then
  cp /opt/chitalnya/pro_env.example /opt/chitalnya/.pro_env
  chmod 600 /opt/chitalnya/.pro_env
fi

CONF=/etc/nginx/vhosts/at.theinquisitor.ru/chitalnya.conf
if ! grep -q 'location ^~ /chitalnya/api/pro-' "$CONF"; then
  python3 -c '
from pathlib import Path
path = Path("/etc/nginx/vhosts/at.theinquisitor.ru/chitalnya.conf")
text = path.read_text()
marker = "    location /chitalnya/api/ {"
block = """    location ^~ /chitalnya/api/pro- {
        proxy_pass http://127.0.0.1:8792;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }

"""
# Fix escaped dollars for real nginx file
block = block.replace("\\$", "$")
if marker not in text:
    raise SystemExit("nginx marker not found")
path.write_text(text.replace(marker, block + marker, 1))
print("nginx: inserted pro location")
'
else
  echo "nginx: pro location already present"
fi

nginx -t
systemctl daemon-reload
systemctl enable chitalnya-pro
systemctl restart chitalnya-pro
systemctl reload nginx
sleep 1
systemctl is-active chitalnya-pro
echo "local:"
curl -sS http://127.0.0.1:8792/chitalnya/api/pro-config
echo
echo "public:"
curl -sS https://at.theinquisitor.ru/chitalnya/api/pro-config
echo
curl -sS -o /dev/null -w "pro.html:%{http_code}\n" https://at.theinquisitor.ru/chitalnya/pro.html
curl -sS -o /dev/null -w "pro-return:%{http_code}\n" https://at.theinquisitor.ru/chitalnya/pro-return.html
