#!/bin/bash
# mytunnel-configure-final-443.sh - pasang arsitektur final 443 (nginx stream -> 9443 / stunnel 4443)
#
# Kenapa skrip ini ada:
#   install.sh lama memasang stunnel4 langsung di 0.0.0.0:443 + nginx 8443.
#   Arsitektur itu membuat gRPC dan XHTTP TLS gagal (stunnel -> mux -> nginx
#   hanya membawa HTTP/1.1), sementara HTTP/2 tidak bisa lewat jalur tersebut.
#   Skrip ini memindahkan terminasi TLS 443 ke nginx (via stream ssl_preread),
#   memindahkan stunnel ke 127.0.0.1:4443 untuk klien legacy (SSH-TLS tanpa ALPN).
#
# Sifat:
#   - idempoten (aman dijalankan 2x, atau setelah patch manual di VPS)
#   - backup bertanggal sebelum setiap perubahan
#   - nginx -t sebelum reload; reload, bukan restart; rollback otomatis jika nginx -t gagal
#   - --dry-run  : tampilkan rencana tanpa mengubah apa pun
#   - --rollback : kembalikan dari backup terakhir
#
# tidak menyentuh Xray config, tidak mengubah install.sh, tidak push apa pun.

set -euo pipefail

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_BASE="/root/mytunnel-443-backup"
BACKUP_DIR="${BACKUP_BASE}/${STAMP}"
NGINX_CONF="/etc/nginx/nginx.conf"
SITE_CONF="/etc/nginx/conf.d/mytunnel.conf"
STUNNEL_CONF="/etc/stunnel/stunnel.conf"
SYSCTL_CONF="/etc/sysctl.d/99-conntrack.conf"

WORKER_CONNECTIONS_VALUE="4096"
WORKER_RLIMIT_VALUE="65535"
CONNTRACK_MAX="65536"
CONNTRACK_TIMEOUT_ESTABLISHED="7200"
NGINX_HTTP_TLS_PORT="9443"
STUNNEL_LEGACY_PORT="4443"

DRY_RUN=0
DO_ROLLBACK=0
CHANGED=0
BACKED_UP=()

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; DIM='\033[2m'; RESET='\033[0m'

say()  { echo -e "$*"; }
ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}!${RESET} $*"; }
die()  { echo -e "${RED}✗${RESET} $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: bash configure-final-443.sh [--dry-run | --rollback] [--help]

  (tanpa opsi)  terapkan konfigurasi final 443
  --dry-run     tampilkan rencana perubahan, tidak mengubah apa pun
  --rollback    kembalikan file dari backup terakhir di ${BACKUP_BASE}
  --help        tampilkan bantuan ini
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --rollback) DO_ROLLBACK=1 ;;
    --help|-h) usage; exit 0 ;;
    *) die "opsi tidak dikenal: $1 (lihat --help)" ;;
  esac
  shift
done

[ "$(id -u)" -eq 0 ] || die "jalankan sebagai root (sudo -i dulu)"

# ---------------------------------------------------------------- prerequisites
check_prereq() {
  command -v nginx >/dev/null 2>&1 || die "nginx tidak terpasang"
  command -v ss >/dev/null 2>&1 || die "iproute2 (ss) tidak tersedia"

  if ! nginx -V 2>&1 | grep -q -- '--with-stream' && [ ! -f /usr/lib/nginx/modules/ngx_stream_module.so ]; then
    die "modul nginx stream tidak ada. Pasang dulu: apt-get install -y libnginx-mod-stream"
  fi
  ok "modul nginx stream tersedia"

  [ -f "$SITE_CONF" ] || die "$SITE_CONF tidak ada (nginx belum dikonfigurasi mytunnel?)"
  [ -f "$STUNNEL_CONF" ] || die "$STUNNEL_CONF tidak ada (stunnel belum terpasang?)"

  if ! grep -qE '^accept[[:space:]]*=[[:space:]]*(0\.0\.0\.0:443|127\.0\.0\.1:443)' "$STUNNEL_CONF" \
     && ! grep -qE '^accept[[:space:]]*=[[:space:]]*127\.0\.0\.1:4443' "$STUNNEL_CONF"; then
    die "stunnel tidak listen di 443 maupun 4443 — arsitektur tidak dikenali, hentikan"
  fi
  ok "stunnel dikenali (443 lama atau 4443 sudah final)"

  if systemctl cat mytunnel-tlsmux.service >/dev/null 2>&1; then
    ok "mytunnel-tlsmux terdaftar"
  elif [ -x /usr/local/bin/mytunnel-tlsmux.py ]; then
    warn "unit mytunnel-tlsmux tidak terdaftar (binary ada) — jalur legacy mungkin perlu diaktifkan manual"
  else
    die "mytunnel-tlsmux tidak ada — jalur legacy 443 tidak bisa dipertahankan, hentikan"
  fi
}

# ------------------------------------------------------------------- backup/plan
backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    say "  ${DIM}[dry-run] backup ${f} -> ${BACKUP_DIR}/$(echo "$f" | tr '/' '_')${RESET}"
    return 0
  fi
  for entry in "${BACKED_UP[@]}"; do
    [ "${entry%%|*}" = "$f" ] && return 0
  done
  mkdir -p "$BACKUP_DIR"
  local dest="${BACKUP_DIR}/$(echo "$f" | tr '/' '_')"
  cp -a "$f" "$dest"
  BACKED_UP+=("$f|$dest")
  say "  ${DIM}backup ${f} -> ${dest}${RESET}"
}

plan_change() { say "  ${CYAN}ubah${RESET} $1"; }

nginx_test_or_rollback() {
  if nginx -t >/tmp/final443-nginxtest.log 2>&1; then
    ok "nginx -t lulus"
    return 0
  fi
  warn "nginx -t GAGAL — rollback otomatis"
  sed 's/^/    /' /tmp/final443-nginxtest.log || true
  for entry in "${BACKED_UP[@]}"; do
    local src="${entry%%|*}" dst="${entry##*|}"
    [ -f "$dst" ] && cp -a "$dst" "$src" && warn "dipulihkan: $src"
  done
  nginx -t >/dev/null 2>&1 && nginx -s reload >/dev/null 2>&1 || true
  rm -f /tmp/final443-nginxtest.log
  die "perubahan dibatalkan, sistem kembali ke kondisi sebelumnya"
}

# ------------------------------------------------------------------ transformasi
apply_nginx_stream() {
  if grep -qE '^[[:space:]]*stream[[:space:]]*\{' "$NGINX_CONF"; then
    ok "blok stream sudah ada di $NGINX_CONF (skip)"
    return 1
  fi
  plan_change "$NGINX_CONF: tambah blok stream (443 -> 9443 / 4443)"
  [ "$DRY_RUN" -eq 1 ] && return 0
  backup_file "$NGINX_CONF"
  cat >>"$NGINX_CONF" <<EOF

stream {
    map \$ssl_preread_alpn_protocols \$tls443_backend {
        ~\bh2\b        127.0.0.1:${NGINX_HTTP_TLS_PORT};
        ~\bhttp/1\.1\b 127.0.0.1:${NGINX_HTTP_TLS_PORT};
        default         127.0.0.1:${STUNNEL_LEGACY_PORT};
    }
    server {
        listen 443;
        ssl_preread on;
        proxy_pass \$tls443_backend;
        proxy_timeout 1h;
        proxy_connect_timeout 10s;
    }
}
EOF
  CHANGED=1
  return 0
}

apply_worker_limits() {
  local touched=0
  if ! grep -qE '^[[:space:]]*worker_rlimit_nofile[[:space:]]+65535;' "$NGINX_CONF"; then
    plan_change "$NGINX_CONF: worker_rlimit_nofile ${WORKER_RLIMIT_VALUE}"
    [ "$DRY_RUN" -eq 0 ] && { backup_file "$NGINX_CONF"; }
    touched=1
  fi
  if ! grep -qE 'worker_connections[[:space:]]+'"${WORKER_CONNECTIONS_VALUE}"';' "$NGINX_CONF"; then
    plan_change "$NGINX_CONF: worker_connections ${WORKER_CONNECTIONS_VALUE}"
    touched=1
  fi
  [ "$touched" -eq 0 ] && { ok "worker_connections/worker_rlimit_nofile sudah final (skip)"; return 0; }
  [ "$DRY_RUN" -eq 1 ] && return 0
  python3 - "$NGINX_CONF" "$WORKER_RLIMIT_VALUE" "$WORKER_CONNECTIONS_VALUE" <<'PY'
import re, sys
path, rlimit, conns = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
if not re.search(r'^\s*worker_rlimit_nofile\s+\d+;', s, re.M):
    m = re.search(r'^events\s*\{', s, re.M)
    anchor = m.start() if m else 0
    s = s[:anchor] + f'worker_rlimit_nofile {rlimit};\n\n' + s[anchor:]
s = re.sub(r'^\s*worker_rlimit_nofile\s+\d+;', f'worker_rlimit_nofile {rlimit};', s, count=1, flags=re.M)
if re.search(r'worker_connections\s+\d+;', s):
    s = re.sub(r'worker_connections\s+\d+;', f'worker_connections {conns};', s, count=1)
else:
    s = re.sub(r'(^events\s*\{[^\n]*\n)', r'\1    ' + f'worker_connections {conns};\n', s, count=1, flags=re.M)
open(path, 'w').write(s)
PY
  CHANGED=1
  return 0
}

apply_http_tls_listen() {
  if grep -qE "listen[[:space:]]+127\.0\.0\.1:${NGINX_HTTP_TLS_PORT}[[:space:]]+ssl" "$SITE_CONF"; then
    ok "server http ${NGINX_HTTP_TLS_PORT} ssl http2 sudah ada (skip)"
    return 1
  fi
  plan_change "$SITE_CONF: tambah listen 127.0.0.1:${NGINX_HTTP_TLS_PORT} ssl http2"
  [ "$DRY_RUN" -eq 1 ] && return 0
  grep -qE 'listen[[:space:]]+8443[[:space:]]+ssl' "$SITE_CONF" \
    || die "listen 8443 ssl tidak ditemukan di $SITE_CONF — struktur tidak dikenali, hentikan"
  backup_file "$SITE_CONF"
  python3 - "$SITE_CONF" "$NGINX_HTTP_TLS_PORT" <<'PY'
import re, sys
path, port = sys.argv[1], sys.argv[2]
s = open(path).read()
m = re.search(r'^([ \t]*)listen[ \t]+8443[ \t]+ssl[^\n]*\n', s, re.M)
if not m:
    sys.exit('listen 8443 ssl tidak ditemukan')
indent = m.group(1)
s = s[:m.end()] + f'{indent}listen 127.0.0.1:{port} ssl http2;\n' + s[m.end():]
open(path, 'w').write(s)
PY
  CHANGED=1
  return 0
}

apply_stunnel_port() {
  if grep -qE '^accept[[:space:]]*=[[:space:]]*127\.0\.0\.1:4443' "$STUNNEL_CONF"; then
    ok "stunnel sudah di 127.0.0.1:${STUNNEL_LEGACY_PORT} (skip)"
    return 1
  fi
  plan_change "$STUNNEL_CONF: accept 0.0.0.0:443 -> 127.0.0.1:${STUNNEL_LEGACY_PORT}"
  [ "$DRY_RUN" -eq 1 ] && return 0
  backup_file "$STUNNEL_CONF"
  sed -i -E "s|^accept[[:space:]]*=[[:space:]]*0\.0\.0\.0:443|accept = 127.0.0.1:${STUNNEL_LEGACY_PORT}|" "$STUNNEL_CONF"
  grep -qE "^accept[[:space:]]*=[[:space:]]*127\.0\.0\.1:${STUNNEL_LEGACY_PORT}" "$STUNNEL_CONF" \
    || die "gagal mengubah accept stunnel"
  CHANGED=1
  return 0
}

apply_sysctl_conntrack() {
  if [ -f "$SYSCTL_CONF" ] \
     && grep -qE "nf_conntrack_max[[:space:]]*=[[:space:]]*${CONNTRACK_MAX}" "$SYSCTL_CONF" \
     && grep -qE "nf_conntrack_tcp_timeout_established[[:space:]]*=[[:space:]]*${CONNTRACK_TIMEOUT_ESTABLISHED}" "$SYSCTL_CONF"; then
    ok "sysctl conntrack sudah final (skip)"
    return 1
  fi
  plan_change "$SYSCTL_CONF: nf_conntrack_max=${CONNTRACK_MAX}, tcp_timeout_established=${CONNTRACK_TIMEOUT_ESTABLISHED}"
  [ "$DRY_RUN" -eq 1 ] && return 0
  backup_file "$SYSCTL_CONF"
  cat >"$SYSCTL_CONF" <<EOF
# mytunnel: tabel conntrack penuh (7679/7680) membuat kernel drop packet,
# sehingga koneksi keluar (mis. Google TCP/443) timeout. Naikkan max dan
# perpanjang timeout established agar tabel tidak cepat penuh.
net.netfilter.nf_conntrack_max = ${CONNTRACK_MAX}
net.netfilter.nf_conntrack_tcp_timeout_established = ${CONNTRACK_TIMEOUT_ESTABLISHED}
EOF
  chmod 644 "$SYSCTL_CONF"
  CHANGED=1
  return 0
}

reload_services() {
  [ "$DRY_RUN" -eq 1 ] && { say "${DIM}[dry-run] skip nginx -t / reload / stunnel restart / sysctl${RESET}"; return 0; }
  nginx_test_or_rollback
  systemctl reload nginx
  ok "nginx reload"

  if systemctl list-unit-files 2>/dev/null | grep -q '^stunnel4'; then
    systemctl restart stunnel4
    ok "stunnel4 restart"
  fi
  if [ -f "$SYSCTL_CONF" ]; then
    sysctl --system >/dev/null 2>&1 || true
    ok "sysctl dimuat"
  fi
}

verify_state() {
  [ "$DRY_RUN" -eq 1 ] && return 0
  say ""
  say "${CYAN}=== verifikasi ===${RESET}"
  nginx -T 2>/dev/null | grep -E 'worker_connections|worker_rlimit_nofile' | sed 's/^/  /' || true
  say "  port 443  : $(ss -tlnp 2>/dev/null | grep -c ':443 ' ) listener"
  ss -tlnp 2>/dev/null | grep -E ":443 |:${STUNNEL_LEGACY_PORT} |:${NGINX_HTTP_TLS_PORT} " | sed 's/^/  /' || true
  local cnt max
  cnt=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo '?')
  max=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo '?')
  say "  conntrack : ${cnt}/${max}"
  systemctl is-active nginx stunnel4 2>/dev/null | sed 's/^/  /' || true
}

do_rollback() {
  [ -d "$BACKUP_BASE" ] || die "tidak ada backup di $BACKUP_BASE"
  local latest
  latest="$(ls -1d "${BACKUP_BASE}"/*/ 2>/dev/null | sort | tail -1)"
  [ -n "$latest" ] || die "folder backup kosong"
  say "${CYAN}Rollback dari ${latest}${RESET}"
  local restored=0
  for f in "$NGINX_CONF" "$SITE_CONF" "$STUNNEL_CONF" "$SYSCTL_CONF"; do
    local src="${latest}$(echo "$f" | tr '/' '_')"
    if [ -f "$src" ]; then
      mkdir -p "$(dirname "$f")"
      cp -a "$src" "$f"
      say "  dipulihkan: $f"
      restored=1
    fi
  done
  [ "$restored" -eq 1 ] || die "tidak ada file backup yang cocok"
  if [ -f "$SYSCTL_CONF" ]; then sysctl --system >/dev/null 2>&1 || true; else
    sysctl -w net.netfilter.nf_conntrack_max="$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 65536)" >/dev/null 2>&1 || true
  fi
  nginx -t >/dev/null 2>&1 && systemctl reload nginx && ok "nginx reload setelah rollback" \
    || warn "nginx -t gagal setelah rollback, periksa manual"
  systemctl restart stunnel4 2>/dev/null && ok "stunnel4 restart" || true
  say "${GREEN}Rollback selesai.${RESET} Hapus $SYSCTL_CONF manual jika ingin reset conntrack."
}

# ------------------------------------------------------------------------ driver
say "${CYAN}mytunnel — konfigurasi final 443${RESET}"
if [ "$DRY_RUN" -eq 1 ]; then
  say "${YELLOW}MODE DRY-RUN: tidak ada perubahan yang ditulis${RESET}"
fi
say ""
say "${CYAN}=== prasyarat ===${RESET}"
check_prereq

if [ "$DO_ROLLBACK" -eq 1 ]; then
  do_rollback
  exit 0
fi

say ""
say "${CYAN}=== rencana perubahan ===${RESET}"
apply_nginx_stream || true
apply_worker_limits || true
apply_http_tls_listen || true
apply_stunnel_port || true
apply_sysctl_conntrack || true

if [ "$DRY_RUN" -eq 1 ]; then
  say ""
  say "${GREEN}Dry-run selesai. Tidak ada perubahan.${RESET}"
  exit 0
fi

say ""
say "${CYAN}=== menerapkan ===${RESET}"
if [ "$CHANGED" -eq 0 ]; then
  ok "sistem sudah memakai konfigurasi final — tidak ada yang diubah"
else
  reload_services
  ok "selesai"
fi

say ""
say "  backup: ${BACKUP_DIR}"
say "  rollback: bash $0 --rollback"
verify_state
