#!/bin/bash
# mytunnel verify.sh — cek kesehatan tunnel (nginx/xray/stream/gRPC/WS/SSH/cert).
#
# Dipanggil di akhir install.sh, atau manual:
#   bash verify.sh            # auto-deteksi domain & IP VPS
#   bash verify.sh --quiet    # ringkas (hanya FAIL + ringkasan)
#   DOMAIN=example.com IP=1.2.3.4 bash verify.sh
#
# Exit 0 = SEMUA LULUS, exit 1 = ada yang gagal (daftar + perintah perbaikan).
set -uo pipefail

QUIET=0
[ "${1:-}" = "--quiet" ] && QUIET=1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; RESET='\033[0m'
PASS=0; FAIL=0; FAILED_ITEMS=(); FIXES=()

_r() { [ "$QUIET" = "1" ] || printf '  %b\n' "$1"; }
p() { PASS=$((PASS+1)); _r "${GREEN}PASS${RESET}  $1"; }
f() { FAIL=$((FAIL+1)); FAILED_ITEMS+=("$1"); _r "${RED}FAIL${RESET}  $1"; [ -n "${2:-}" ] && FIXES+=("$1 -> $2"); }

NGINX_CONF="/etc/nginx/nginx.conf"
SITE_CONF="/etc/nginx/conf.d/mytunnel.conf"
ETC="${MYTUNNEL_PREFIX:-}/etc/mytunnel"
CERT="${ETC}/cert/fullchain.crt"

# domain & IP
DOMAIN="${DOMAIN:-$(cat "${ETC}/config/domain.txt" 2>/dev/null)}"
[ -z "$DOMAIN" ] || [ "$DOMAIN" = "-" ] && DOMAIN="$(cat /etc/mytunnel/domain.txt 2>/dev/null)"
IP="${IP:-$(curl -fsS --max-time 6 https://api.ipify.org 2>/dev/null || echo "")}"
[ -z "$IP" ] && IP="$(hostname -I 2>/dev/null | awk '{print $1}')"

printf '%b\n' "${CYAN}=== mytunnel verify ===${RESET}"
_r "domain: ${DOMAIN:-(-)}  ip: ${IP:-(-)}"
echo

# 1. nginx -t
if nginx -t >/tmp/verify-nginxt.log 2>&1; then p "nginx -t lulus"
else f "nginx -t GAGAL" "lihat /tmp/verify-nginxt.log; perbaiki config lalu: nginx -t && systemctl reload nginx"; fi

# 2. service
for svc in nginx xray; do
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$svc" 2>/dev/null; then p "$svc active"
    else f "$svc tidak active" "systemctl status $svc; systemctl restart $svc"; fi
  fi
done

# 3. map stream: urutan & target
if [ -f "$NGINX_CONF" ]; then
  # posisi relatif: ~^h2$ dan ~^h2,http/1\.1$ harus sebelum ~\bh2\b
  L_H2=$(grep -nE '^[[:space:]]*~\^h2\$' "$NGINX_CONF" | head -1 | cut -d: -f1)
  L_H2H1=$(grep -nE '^[[:space:]]*~\^h2,http/1\\\.1\$' "$NGINX_CONF" | head -1 | cut -d: -f1)
  L_H2GEN=$(grep -nE '^[[:space:]]*~\\bh2\\b' "$NGINX_CONF" | head -1 | cut -d: -f1)
  if grep -qE '^[[:space:]]*~\^h2\$[[:space:]]+127\.0\.0\.1:8444;' "$NGINX_CONF" \
     && grep -qE '^[[:space:]]*~\^h2,http/1\\\.1\$[[:space:]]+127\.0\.0\.1:8444;' "$NGINX_CONF"; then
    p "map stream: ~^h2\$ & ~^h2,http/1\\.1\$ -> 8444"
  else
    f "map stream: entri h2 -> 8444 tidak lengkap" "bash /root/configure-final-443.sh  # pasang ulang route 8444"
  fi
  if [ -n "${L_H2:-}" ] && [ -n "${L_H2H1:-}" ] && [ -n "${L_H2GEN:-}" ] \
     && [ "$L_H2" -lt "$L_H2GEN" ] && [ "$L_H2H1" -lt "$L_H2GEN" ]; then
    p "map urutan: h2/h2,http/1.1 di atas ~\\bh2\\b"
  else
    f "map urutan salah (h2 harus paling atas)" "edit $NGINX_CONF: pindahkan ~^h2\$ & ~^h2,http/1\\.1\$ ke paling atas blok map"
  fi
else
  f "$NGINX_CONF tidak ada" "jalankan install.sh"
fi

# 4. 9443 TANPA http2, 8444 ssl http2
if grep -qE 'listen[[:space:]]+127\.0\.0\.1:9443[[:space:]]+ssl([^;]*)' "$SITE_CONF" 2>/dev/null; then
  if grep -qE 'listen[[:space:]]+127\.0\.0\.1:9443[[:space:]]+ssl[^;]*http2' "$SITE_CONF" 2>/dev/null; then
    f "9443 memakai http2 (harus TANPA)" "hapus 'http2' pada baris 'listen 127.0.0.1:9443 ssl;' di $SITE_CONF"
  else
    p "9443 tanpa http2"
  fi
else
  f "listener 9443 tidak ada di $SITE_CONF" "bash /root/configure-final-443.sh"
fi
if grep -qE 'listen[[:space:]]+127\.0\.0\.1:8444[[:space:]]+ssl[^;]*http2' "$SITE_CONF" 2>/dev/null; then
  p "8444 ssl http2"
else
  f "8444 tidak 'ssl http2' di $SITE_CONF" "bash /root/configure-final-443.sh  # tambah server 8444"
fi

# 5. listener 8444 & 9443 hidup
if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)8444$'; then p "listener 8444 ada"
else f "listener 8444 tidak listen" "systemctl restart nginx; ss -tlnp | grep :8444"; fi
if ss -tln 2>/dev/null | awk '{print $4}' | grep -qE '(^|:)9443$'; then p "listener 9443 ada"
else f "listener 9443 tidak listen" "systemctl restart nginx; ss -tlnp | grep :9443"; fi

# 6. ALPN: h2 -> :443 dan h2,http/1.1 mendarat di 8444
CONNECT="${DOMAIN:-$IP}"
if [ -n "$CONNECT" ] && command -v openssl >/dev/null 2>&1; then
  ALPN_H2=$(echo | timeout 8 openssl s_client -alpn h2 -connect "${CONNECT}:443" -servername "${DOMAIN:-$CONNECT}" 2>/dev/null | grep -i 'ALPN protocol' | awk -F': ' '{print $2}' | tr -d '\r')
  if [ "$ALPN_H2" = "h2" ]; then p "ALPN h2 ke :443 = h2"
  else f "ALPN h2 ke :443 = '${ALPN_H2:-none}' (harus h2)" "cek: map stream h2 -> 8444 & 8444 ssl http2"; fi
  # h2,http/1.1 mendarat di 8444: tahan koneksi (sleep|openssl), cek ss, lalu tutup.
  _found=0
  ( sleep 12 | timeout 12 openssl s_client -alpn h2,http/1.1 -connect "127.0.0.1:443" -servername "${DOMAIN:-$CONNECT}" >/dev/null 2>&1 ) &
  _pid=$!
  for _try in $(seq 1 15); do
    if ss -tn state established 2>/dev/null | awk '{print $3, $4}' | grep -qE '127\.0\.0\.1:8444'; then _found=1; break; fi
    sleep 0.6
  done
  kill "$_pid" 2>/dev/null || true
  wait "$_pid" 2>/dev/null || true
  if [ "$_found" = "1" ]; then
    p "ALPN h2,http/1.1 mendarat di 8444"
  else
    _r "${YELLOW}SKIP${RESET}  ALPN h2,http/1.1 -> 8444 (tak ada koneksi terdeteksi saat cek)"
  fi
else
  _r "${YELLOW}SKIP${RESET}  uji ALPN (domain/IP atau openssl tidak tersedia)"
fi

# 7. WS 101 untuk /vmess /vless /trojan (HTTP/1.1)
if command -v curl >/dev/null 2>&1 && [ -n "$CONNECT" ]; then
  for path in vmess vless trojan; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --http1.1 -m 8 -k \
      -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
      -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
      "https://${CONNECT}:443/${path}" 2>/dev/null)
    if [ "$code" = "101" ]; then p "WS /${path} @443 = 101"
    else f "WS /${path} @443 = ${code:-none} (harus 101)" "cek listener 9443 & blok WS di $SITE_CONF"; fi
  done
else
  _r "${YELLOW}SKIP${RESET}  uji WS (curl/alamat tidak tersedia)"
fi

# 8. SSH-WS + SSH-TLS
if command -v curl >/dev/null 2>&1 && [ -n "$CONNECT" ]; then
  code=$(curl -s -o /dev/null -w '%{http_code}' --http1.1 -m 8 -k \
    -H 'Connection: Upgrade' -H 'Upgrade: websocket' \
    -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' \
    "https://${CONNECT}:443/ssh-ws" 2>/dev/null)
  if [ "$code" = "101" ]; then p "SSH-WS /ssh-ws = 101"
  else f "SSH-WS /ssh-ws = ${code:-none} (harus 101)" "cek location /ssh-ws di mytunnel-locations.inc + 10004"; fi
fi
SSH_TLS_PORT="${SSH_TLS_PORT:-444}"
if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/${SSH_TLS_PORT}" 2>/dev/null; then p "SSH-TLS :${SSH_TLS_PORT} terbuka"
else f "SSH-TLS :${SSH_TLS_PORT} tertutup" "systemctl status stunnel4; systemctl restart stunnel4"; fi
if timeout 5 bash -c "echo > /dev/tcp/127.0.0.1/22" 2>/dev/null; then p "SSH :22 terbuka"
else _r "${YELLOW}SKIP${RESET}  SSH :22 (open-ssh mungkin di port lain)"; fi

# 9. sertifikat valid (tanggal expired)
if [ -f "$CERT" ] && command -v openssl >/dev/null 2>&1; then
  END=$(openssl x509 -enddate -noout -in "$CERT" 2>/dev/null | cut -d= -f2)
  if [ -n "$END" ]; then
    END_EPOCH=$(date -d "$END" +%s 2>/dev/null || echo 0)
    NOW=$(date +%s)
    DAYS=$(( (END_EPOCH - NOW) / 86400 ))
    if [ "$END_EPOCH" -gt "$NOW" ]; then p "sertifikat valid (expired: $END, ${DAYS} hari lagi)"
    else f "sertifikat EXPIRED ($END)" "bash /etc/mytunnel/setup/cert.sh  # atau renew acme.sh"; fi
  else
    f "tidak bisa membaca tanggal expired cert" "openssl x509 -enddate -noout -in $CERT"
  fi
else
  _r "${YELLOW}SKIP${RESET}  sertifikat ($CERT tidak ada)"
fi

# ------------------------------------------------------------- ringkasan
echo
if [ "$FAIL" -eq 0 ]; then
  printf '%b\n' "${GREEN}SEMUA LULUS${RESET}  (${PASS} PASS, 0 FAIL)"
  exit 0
else
  printf '%b\n' "${RED}GAGAL: ${FAIL} item${RESET}  (${PASS} PASS, ${FAIL} FAIL)"
  printf '%b\n' "${YELLOW}Item gagal:${RESET}"
  for it in "${FAILED_ITEMS[@]}"; do echo "  - $it"; done
  echo -e "${YELLOW}Perintah perbaikan:${RESET}"
  for fx in "${FIXES[@]}"; do echo "  - $fx"; done
  exit 1
fi
