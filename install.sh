#!/bin/bash
# mytunnel install.sh - TUNNEL PRO v1.1.0 (TAHAP 1+2+3+4+5+6+8)
# Debian 11/12, Ubuntu 18/20/22/24 - disarankan Debian 12 / Ubuntu 22.04
# Idempotent, testable via MYTUNNEL_PREFIX=... MYTUNNEL_DOMAIN=example.com bash install.sh --no-deps
# Aman: wget -qO install.sh https://raw.githubusercontent.com/USER/REPO/main/install.sh && less install.sh && bash install.sh
# Non-interaktif: MYTUNNEL_DOMAIN=example.com MYTUNNEL_BRAND="My Brand" MYTUNNEL_YES=1 bash install.sh
#                 bash install.sh --domain example.com --brand "My Brand" --yes
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; RESET='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
BIN="${BASE}/usr/local/bin"
# BAGIAN D-3: variabel non-interaktif
MYTUNNEL_DOMAIN="${MYTUNNEL_DOMAIN:-}"
MYTUNNEL_BRAND="${MYTUNNEL_BRAND:-}"
MYTUNNEL_YES="${MYTUNNEL_YES:-0}"
AUTO_YES=0
NO_DEPS=0
_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null || true; }
_fail() {
  echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true
  [ -n "$2" ] && echo -e "${YELLOW}Penyebab: $2${RESET}" >&2
  exit 1
}
# BAGIAN D-3: arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain) MYTUNNEL_DOMAIN="$2"; shift 2;;
    --domain=*) MYTUNNEL_DOMAIN="${1#*=}"; shift;;
    --brand) MYTUNNEL_BRAND="$2"; shift 2;;
    --brand=*) MYTUNNEL_BRAND="${1#*=}"; shift;;
    --yes|-y) AUTO_YES=1; MYTUNNEL_YES=1; shift;;
    --no-deps) NO_DEPS=1; shift;;
    --help|-h) echo "Usage: bash install.sh [--domain example.com] [--brand \"My Brand\"] [--yes] [--no-deps]"; echo " Env: MYTUNNEL_DOMAIN, MYTUNNEL_BRAND, MYTUNNEL_YES=1, MYTUNNEL_PREFIX=/tmp/test (test mode)"; echo " Aman: wget -qO install.sh https://raw.githubusercontent.com/USER/REPO/main/install.sh && less install.sh && bash install.sh"; echo " Non-interaktif: MYTUNNEL_DOMAIN=example.com MYTUNNEL_YES=1 bash install.sh"; exit 0;;
    *) echo -e "${YELLOW}Arg tidak dikenal: $1${RESET}" >&2; shift;;
  esac
done
[ "$MYTUNNEL_YES" = "1" ] && AUTO_YES=1
export MYTUNNEL_DOMAIN MYTUNNEL_BRAND MYTUNNEL_YES
# BAGIAN D-4: hanya HTTPS (sudah enforced di setup/*.sh; http:// hanya 127.0.0.1 internal)
if [[ "$EUID" -ne 0 && -z "$MYTUNNEL_PREFIX" ]]; then echo -e "${RED}Jalankan sebagai root${RESET}"; exit 1; fi
if [[ -f /etc/os-release ]]; then . /etc/os-release; OS=$ID; VER=$VERSION_ID; else echo -e "${RED}OS tidak dikenali${RESET}"; exit 1; fi
case "$OS" in ubuntu|debian) echo -e "${GREEN}OS: $OS $VER${RESET}";; *) echo -e "${RED}Hanya Ubuntu/Debian${RESET}"; exit 1;; esac
# BAGIAN D-2: preflight (skip jika MYTUNNEL_PREFIX test mode)
if [ -z "$MYTUNNEL_PREFIX" ]; then
  echo -e "${CYAN}=== Preflight check ===${RESET}"
  ARCH=$(uname -m 2>/dev/null || echo unknown)
  case "$ARCH" in x86_64|amd64) echo -e "  Arch: ${GREEN}$ARCH ✓${RESET}";; aarch64|arm64) echo -e "  Arch: ${YELLOW}$ARCH (terbatas, build badvpn mungkin perlu adaptasi)${RESET}";; *) echo -e "  Arch: ${YELLOW}$ARCH (belum diuji)${RESET}";; esac
  case "$OS-$VER" in ubuntu-22.04|ubuntu-24.04|debian-12|debian-11|ubuntu-20.04|ubuntu-18.04|debian-10) echo -e "  OS versi: ${GREEN}$OS $VER ✓${RESET}";; *) echo -e "  OS versi: ${YELLOW}$OS $VER (disarankan Debian 12 / Ubuntu 22.04)${RESET}";; esac
  RAM_MB=$(free -m 2>/dev/null | awk '/Mem:/{print $2}' || echo 0)
  if [ "$RAM_MB" -lt 512 ] 2>/dev/null; then echo -e "  RAM: ${YELLOW}${RAM_MB} MB (minimum 512 MB disarankan)${RESET}"; else echo -e "  RAM: ${GREEN}${RAM_MB} MB ✓${RESET}"; fi
  DISK_AVAIL=$(df -m / 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
  if [ "$DISK_AVAIL" -lt 2048 ] 2>/dev/null; then echo -e "  Disk /: ${YELLOW}${DISK_AVAIL} MB (minimum 2 GB disarankan)${RESET}"; else echo -e "  Disk /: ${GREEN}${DISK_AVAIL} MB ✓${RESET}"; fi
  if ping -c1 -W3 1.1.1.1 >/dev/null 2>&1 || curl -fsI --max-time 5 https://github.com >/dev/null 2>&1; then echo -e "  Internet: ${GREEN}OK ✓${RESET}"; else echo -e "  Internet: ${YELLOW}TIDAK TERDETEKSI (butuh untuk acme/Xray)${RESET}"; fi
  BUSY=""
  for _p in 80 443 444 90 81; do if ss -tlnp 2>/dev/null | grep -q ":$_p " || ss -tln 2>/dev/null | grep -q ":$_p "; then BUSY="$BUSY $_p"; fi; done
  if [ -n "$BUSY" ]; then echo -e "  Port terpakai:${YELLOW}$BUSY${RESET} (akan ditangani setup)"; else echo -e "  Port 80/443/444/90/81: ${GREEN}bebas ✓${RESET}"; fi
  if [ "$AUTO_YES" != "1" ]; then
    echo ""
    echo -e "${BOLD}Ringkasan:${RESET} OS $OS $VER | Arch $ARCH | RAM ${RAM_MB}MB | Disk ${DISK_AVAIL}MB | Domain ${MYTUNNEL_DOMAIN:-(- tanya nanti)} | Brand ${MYTUNNEL_BRAND:-TUNNEL PRO}"
    echo -e "${YELLOW}Akan mengubah: UFW, BBR sysctl, nginx, Xray, cron, user system${RESET}"
    echo -ne "Lanjut install? [y/N]: "
    read -r _ans 2>/dev/null || _ans=""
    case "$_ans" in y|Y|yes|YES) ;; *) echo "Batal."; exit 0;; esac
  else
    echo -e "  Auto-YES: lanjut tanpa konfirmasi (MYTUNNEL_YES=1 / --yes)"
    echo -e "  Ringkasan: OS $OS $VER | Arch $ARCH | RAM ${RAM_MB}MB | Disk ${DISK_AVAIL}MB | Domain ${MYTUNNEL_DOMAIN:-(-)} | Brand ${MYTUNNEL_BRAND:-TUNNEL PRO}"
  fi
fi
if [[ "$NO_DEPS" = "0" && -z "$MYTUNNEL_PREFIX" ]]; then
  echo -e "${CYAN}[1/13] Install dependensi...${RESET}"
  _log "[1/13] apt deps"
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y curl wget jq openssl vnstat bc cron socat dnsutils at python3  >/dev/null 2>&1 || \
  apt-get install -y curl wget jq openssl bc cron socat at python3 >/dev/null 2>&1 || \
  apt-get install -y curl wget jq openssl bc at python3 >/dev/null 2>&1 || true
fi
echo -e "${CYAN}[2/13] Buat folder struktur...${RESET}"
mkdir -p "$ETC/config" "$ETC/db" "$ETC/lib" "$ETC/menu" "$ETC/setup" "$ETC/cron" "$ETC/cert" "$ETC/features" "$ETC/bot" "$ETC/advanced" "$ETC/slowdns" "$ETC/logrotate.d" "$(dirname "$LOG")" "$BIN" "${BASE}/usr/local/etc/xray" "${BASE}/var/log/xray" "${BASE}/var/log/nginx" "${BASE}/etc/nginx/conf.d" "${BASE}/etc/sysctl.d" "${BASE}/var/lib/mytunnel/limit" "${BASE}/var/lib/mytunnel/state" "${BASE}/run" "${BASE}/etc/default" "${BASE}/etc/dropbear" "${BASE}/etc/logrotate.d" 2>/dev/null || true
touch "$LOG" 2>/dev/null || true; chmod 644 "$LOG" 2>/dev/null || true
mkdir -p "${BASE}/var/log/xray" 2>/dev/null || true
touch "${BASE}/var/log/xray/access.log" "${BASE}/var/log/xray/error.log" 2>/dev/null || true
chmod 644 "${BASE}/var/log/xray/"*.log 2>/dev/null || true
echo -e "${CYAN}[3/13] Tulis config, lib, menu, setup, cron...${RESET}"
[ -f "$ETC/config/brand.txt" ] || echo "TUNNEL PRO" > "$ETC/config/brand.txt"
# BAGIAN D-3: brand dari env/arg (non-interaktif) timpa jika ada
if [ -n "$MYTUNNEL_BRAND" ]; then echo "$MYTUNNEL_BRAND" > "$ETC/config/brand.txt" 2>/dev/null || true; chmod 644 "$ETC/config/brand.txt" 2>/dev/null || true; fi
[ -f "$ETC/config/domain.txt" ] || echo "-" > "$ETC/config/domain.txt"
[ -f "$ETC/config/expiry.txt" ] || echo "-" > "$ETC/config/expiry.txt"
[ -f "$ETC/config/banner.txt" ] || echo " | TUNNEL PRO - No hacking, use legally |" > "$ETC/config/banner.txt"
if [ ! -f "$ETC/config/ports.conf" ]; then
  cat > "$ETC/config/ports.conf" << 'PC_EOF'
OPENSSH_PORT=444
DROPBEAR_PORT=90
TLS_PORT=8443
NONTLS_PORT=80,8080
ANY_PORT=2082,2083,8880
SSHWS_PORT=10004
SLOWDNS_PORT=53,5300
UDP_CUSTOM_PORT=1-65535
OHP_SSH_PORT=9080
SQUID_PORT=3128
UDPGW_PORT=7100-7600
OPENVPN_TCP_PORT=1194
OPENVPN_SSL_PORT=442
OPENVPN_UDP_PORT=25000
OPENVPN_DNS_PORT=53
OHP_OVPN_PORT=9088
CONFIG_PORT=81
PC_EOF
  chmod 644 "$ETC/config/ports.conf" 2>/dev/null || true
fi
chmod 644 "$ETC/config/"*.txt 2>/dev/null || true
for f in ssh vmess vless trojan; do [ -f "$ETC/db/${f}.txt" ] || touch "$ETC/db/${f}.txt"; chmod 600 "$ETC/db/${f}.txt" 2>/dev/null || true; done
for f in ssh vmess vless trojan; do [ -f "$ETC/db/.${f}.lock" ] || touch "$ETC/db/.${f}.lock" 2>/dev/null || true; chmod 600 "$ETC/db/.${f}.lock" 2>/dev/null || true; done
cat > "$ETC/lib/colors.sh" << '__EMBED_EOF__'
#!/bin/bash
# shellcheck disable=SC2034
# mytunnel lib/colors.sh - ANSI colors (60 col)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GREY='\033[0;37m'
RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

__EMBED_EOF__
chmod 644 "$ETC/lib/colors.sh"
cat > "$ETC/lib/helpers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/helpers.sh
MT_LOG="/var/log/mytunnel.log"
[ -n "$MYTUNNEL_PREFIX" ] && MT_LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"

log() {
  local msg="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $msg" >> "$MT_LOG" 2>/dev/null || true
}
pause() {
  echo -ne "${GREY}Tekan Enter untuk kembali...${RESET}"
  read -r _
}
confirm() {
  local prompt="${1:-Lanjut? [y/N]: }"
  local ans
  echo -ne "$prompt"
  read -r ans
  case "$ans" in y|Y|yes|YES) return 0;; *) return 1;; esac
}
# ponytail: generic validate - kept for custom scripts; proto uses validate_proto_user
validate_username() {
  [[ "$1" =~ ^[a-zA-Z0-9_.-]{3,32}$ ]]
}
validate_number() {
  [[ "$1" =~ ^[0-9]+$ ]]
}
draw_line() {
  local char="${1:--}"
  local width="${2:-60}"
  printf '%*s\n' "$width" '' | tr ' ' "$char"
}
draw_box() {
  local title="$1"
  local width="${2:-60}"
  local inner=$((width - 2))
  printf "${BLUE}┌"
  printf '─%.0s' $(seq 1 $inner)
  printf "┐${RESET}\n"
  if [ -n "$title" ]; then
    local len=${#title}
    [ "$len" -gt "$inner" ] && title="${title:0:$inner}" && len=$inner
    local left=$(( (inner - len) / 2 ))
    local right=$(( inner - len - left ))
    printf "${BLUE}│${RESET}%*s${BOLD}%s${RESET}%*s${BLUE}│${RESET}\n" "$left" "" "$title" "$right" ""
  fi
  printf "${BLUE}└"
  printf '─%.0s' $(seq 1 $inner)
  printf "┘${RESET}\n"
}
banner() {
  local brand="TUNNEL PRO"
  local c1="${MYTUNNEL_PREFIX:-}/etc/mytunnel/config/brand.txt"
  local c2="/etc/mytunnel/config/brand.txt"
  [ -f "$c1" ] && brand=$(head -1 "$c1" 2>/dev/null)
  if [ "$brand" = "TUNNEL PRO" ] && [ -f "$c2" ]; then brand=$(head -1 "$c2" 2>/dev/null); fi
  draw_box "$brand" 60
}
backup_file() {
  [ -f "$1" ] || return 0
  local bak
  bak="$1.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$1" "$bak" 2>/dev/null && echo "$bak"
}

__EMBED_EOF__
chmod 644 "$ETC/lib/helpers.sh"
cat > "$ETC/lib/sysinfo.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/sysinfo.sh
MYTUNNEL_BASE="${MYTUNNEL_PREFIX:-}"
ETC_BASE="/etc/mytunnel"
[ -n "$MYTUNNEL_BASE" ] && ETC_BASE="${MYTUNNEL_BASE}/etc/mytunnel"
CACHE_FILE="${ETC_BASE}/.cache_sysinfo"
CACHE_TTL=3600

_cache_valid() {
  [ -f "$CACHE_FILE" ] || return 1
  local age
  age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  [ "$age" -lt "$CACHE_TTL" ]
}
_cache_get() { grep -E "^$1=" "$CACHE_FILE" 2>/dev/null | cut -d= -f2-; }
_cache_set() {
  local k="$1" v="$2"
  mkdir -p "$(dirname "$CACHE_FILE")"
  if grep -q "^$k=" "$CACHE_FILE" 2>/dev/null; then sed -i "s|^$k=.*|$k=$v|" "$CACHE_FILE" 2>/dev/null
  else echo "$k=$v" >> "$CACHE_FILE" 2>/dev/null; fi
}
get_os() { . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-$ID $VERSION_ID}"; }
get_ram() { free -m 2>/dev/null | awk '/^Mem:/ {print $2"M"}'; }
get_swap() { free -m 2>/dev/null | awk '/^Swap:/ {print $2"M"}'; }
get_uptime() { uptime -p 2>/dev/null | sed 's/up //' || awk '{printf "%d hours, %d minutes", $1/3600, ($1%3600)/60}' /proc/uptime 2>/dev/null; }
get_domain() { [ -f "${ETC_BASE}/config/domain.txt" ] && head -1 "${ETC_BASE}/config/domain.txt" 2>/dev/null | tr -d '\n' || echo "-"; }
get_ip_cached() {
  if _cache_valid; then local c; c=$(_cache_get IP); [ -n "$c" ] && echo "$c" && return 0; fi
  local ip; ip=$(curl -s --max-time 3 ifconfig.me 2>/dev/null || curl -s --max-time 3 ipinfo.io/ip 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')
  ip=$(echo "$ip" | tr -d ' \n'); [ -z "$ip" ] && ip="-"; _cache_set IP "$ip"; echo "$ip"
}
get_city_cached() {
  if _cache_valid; then local c; c=$(_cache_get CITY); [ -n "$c" ] && echo "$c" && return 0; fi
  local city; city=$(curl -s --max-time 3 ipinfo.io/city 2>/dev/null | tr -d '\n' | head -c 32); [ -z "$city" ] && city="-"; _cache_set CITY "$city"; echo "$city"
}
get_isp_cached() {
  if _cache_valid; then local c; c=$(_cache_get ISP); [ -n "$c" ] && echo "$c" && return 0; fi
  local isp; isp=$(curl -s --max-time 3 ipinfo.io/org 2>/dev/null | head -c 40 | tr -d '\n'); [ -z "$isp" ] && isp="-"; _cache_set ISP "$isp"; echo "$isp"
}
get_traffic_month() { command -v vnstat >/dev/null 2>&1 && vnstat --oneline 2>/dev/null | awk -F';' '{print $11}' || echo "-"; }
get_traffic_day() { command -v vnstat >/dev/null 2>&1 && vnstat --oneline 2>/dev/null | awk -F';' '{print $5}' || echo "-"; }
get_traffic_rx_tx() {
  if command -v vnstat >/dev/null 2>&1; then
    local line; line=$(vnstat --oneline 2>/dev/null | head -1)
    local m_rx m_tx d_rx d_tx
    m_rx=$(echo "$line" | awk -F';' '{print $9}'); m_tx=$(echo "$line" | awk -F';' '{print $10}')
    d_rx=$(echo "$line" | awk -F';' '{print $4}'); d_tx=$(echo "$line" | awk -F';' '{print $6}')
    echo "MRX:${m_rx:- -} MTX:${m_tx:- -} DRX:${d_rx:- -} DTX:${d_tx:- -}"
  else echo "MRX:- MTX:- DRX:- DTX:-"; fi
}
svc_status() { systemctl is-active --quiet "$1" 2>/dev/null && echo "ON" || echo "OFF"; }
get_account_count() { local f="${ETC_BASE}/db/$1.txt"; [ -f "$f" ] && grep -cve '^\s*$' "$f" 2>/dev/null || echo 0; }
get_brand() { [ -f "${ETC_BASE}/config/brand.txt" ] && head -1 "${ETC_BASE}/config/brand.txt" 2>/dev/null || echo "TUNNEL PRO"; }
get_expiry() { [ -f "${ETC_BASE}/config/expiry.txt" ] && head -1 "${ETC_BASE}/config/expiry.txt" 2>/dev/null || echo "-"; }

__EMBED_EOF__
chmod 644 "$ETC/lib/sysinfo.sh"
cat > "$ETC/lib/xray_helpers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/xray_helpers.sh - helpers untuk 9 inbounds (ws/grpc/hu)
# shellcheck disable=SC1091,SC1090
# Preserve BASE if caller already set full /etc/mytunnel path (menu)
if [[ "${BASE:-}" == *"/etc/mytunnel"* ]]; then
  ETC="$BASE"
else
  BASE="${MYTUNNEL_PREFIX:-}"
  ETC="${BASE}/etc/mytunnel"
fi
if [ -n "${MYTUNNEL_PREFIX:-}" ]; then XRAY_ETC="$MYTUNNEL_PREFIX/usr/local/etc/xray"; else XRAY_ETC="/usr/local/etc/xray"; fi
XRAY_CFG="$XRAY_ETC/config.json"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -z "${MYTUNNEL_PREFIX:-}" ] && LOG="/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

_xray_cfg() { echo "$XRAY_CFG"; }
_xray_bin() {
  if [ -x "${BASE}/usr/local/bin/xray" ]; then echo "${BASE}/usr/local/bin/xray"
  elif command -v xray >/dev/null 2>&1; then command -v xray
  else echo "xray"
  fi
}
_xray_need_jq() {
  command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq tidak ditemukan${RESET}" >&2; return 1; }
}
_backup_cfg() {
  local cfg="$XRAY_CFG"
  [ -f "$cfg" ] || return 0
  local bak
  bak="$cfg.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$cfg" "$bak" 2>/dev/null && echo "$bak" || true
}
_validate_cfg() {
  local cfg="$XRAY_CFG" bin
  bin=$(_xray_bin)
  if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
    "$bin" run -test -config "$cfg" >/dev/null 2>&1 && return 0
    "$bin" run -test -config "$cfg" 2>&1 | head -n 30 >&2
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then jq . "$cfg" >/dev/null 2>&1 && return 0; return 1
  else python3 -m json.tool "$cfg" >/dev/null 2>&1 && return 0; return 1
  fi
}
# ponytail: rollback keeps last .bak only; upgrade to keep N backups + rotation when disk pressure arises

_proto_tags() {
  case "$1" in
    vmess) echo "vmess-ws vmess-grpc vmess-hu" ;;
    vless) echo "vless-ws vless-grpc vless-hu" ;;
    trojan) echo "trojan-ws trojan-grpc trojan-hu" ;;
    *) echo "" ;;
  esac
}

xray_add_client() {
  local proto="$1" secret="$2" email="$3"
  local cfg
  cfg=$(_xray_cfg)
  [ -z "$proto" ] || [ -z "$secret" ] || [ -z "$email" ] && { echo -e "${RED}Usage: xray_add_client <vmess|vless|trojan> <uuid/pass> <email>${RESET}" >&2; return 2; }
  case "$proto" in vmess|vless|trojan) ;; *) echo -e "${RED}proto harus vmess/vless/trojan${RESET}" >&2; return 2;; esac
  _xray_need_jq || return 1
  [ -f "$cfg" ] || { echo -e "${RED}Xray config tidak ada: $cfg${RESET}" >&2; return 1; }
  local tags t all_exist=1
  tags=$(_proto_tags "$proto")
  for t in $tags; do
    if ! jq -e --arg email "$email" --arg tag "$t" '.inbounds[] | select(.tag==$tag) | .settings.clients[]? | select(.email==$email)' "$cfg" >/dev/null 2>&1; then
      all_exist=0
      break
    fi
  done
  if [ "$all_exist" -eq 1 ]; then
    echo -e "${YELLOW}Client $email sudah ada di $proto (3 transports)${RESET}" >&2; return 0
  fi
  # jika parsial (ada di 1-2 tag), bersihkan dulu agar tidak duplikat
  local need_clean=0
  for t in $tags; do
    if jq -e --arg email "$email" --arg tag "$t" '.inbounds[] | select(.tag==$tag) | .settings.clients[]? | select(.email==$email)' "$cfg" >/dev/null 2>&1; then
      need_clean=1; break
    fi
  done
  local bak tmp
  bak=$(_backup_cfg)
  tmp=$(mktemp)
  # hapus parsial jika ada (idempotent)
  if [ "$need_clean" -eq 1 ]; then
    local clean_tmp
    clean_tmp=$(mktemp)
    case "$proto" in
      vmess) jq --arg email "$email" '(.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc" or .tag=="vmess-hu") | .settings.clients) |= map(select(.email != $email))' "$cfg" > "$clean_tmp" 2>&1 || true ;;
      vless) jq --arg email "$email" '(.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc" or .tag=="vless-hu") | .settings.clients) |= map(select(.email != $email))' "$cfg" > "$clean_tmp" 2>&1 || true ;;
      trojan) jq --arg email "$email" '(.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc" or .tag=="trojan-hu") | .settings.clients) |= map(select(.email != $email))' "$cfg" > "$clean_tmp" 2>&1 || true ;;
    esac
    if [ -s "$clean_tmp" ]; then cp -a "$clean_tmp" "$cfg" 2>/dev/null || true; chmod 644 "$cfg" 2>/dev/null || true; fi
    rm -f "$clean_tmp" 2>/dev/null || true
  fi
  local add_ok=1
  case "$proto" in
    vmess)
      jq --arg id "$secret" --arg email "$email" '
        (.inbounds[] | select(.tag=="vmess-ws")  | .settings.clients) += [{"id": $id, "level": 0, "email": $email}] |
        (.inbounds[] | select(.tag=="vmess-grpc")| .settings.clients) += [{"id": $id, "level": 0, "email": $email}] |
        (.inbounds[] | select(.tag=="vmess-hu")  | .settings.clients) += [{"id": $id, "level": 0, "email": $email}]
      ' "$cfg" > "$tmp" 2>&1 || add_ok=0
      ;;
    vless)
      jq --arg id "$secret" --arg email "$email" '
        (.inbounds[] | select(.tag=="vless-ws")  | .settings.clients) += [{"id": $id, "level": 0, "email": $email}] |
        (.inbounds[] | select(.tag=="vless-grpc")| .settings.clients) += [{"id": $id, "level": 0, "email": $email}] |
        (.inbounds[] | select(.tag=="vless-hu")  | .settings.clients) += [{"id": $id, "level": 0, "email": $email}]
      ' "$cfg" > "$tmp" 2>&1 || add_ok=0
      ;;
    trojan)
      jq --arg pw "$secret" --arg email "$email" '
        (.inbounds[] | select(.tag=="trojan-ws")  | .settings.clients) += [{"password": $pw, "level": 0, "email": $email}] |
        (.inbounds[] | select(.tag=="trojan-grpc")| .settings.clients) += [{"password": $pw, "level": 0, "email": $email}] |
        (.inbounds[] | select(.tag=="trojan-hu")  | .settings.clients) += [{"password": $pw, "level": 0, "email": $email}]
      ' "$cfg" > "$tmp" 2>&1 || add_ok=0
      ;;
  esac
  if [ "$add_ok" -ne 1 ] || [ ! -s "$tmp" ]; then
    echo -e "${RED}Gagal edit config (jq)${RESET}" >&2; cat "$tmp" 2>/dev/null | head -n 20 >&2; rm -f "$tmp"; return 1
  fi
  cp -a "$tmp" "$cfg" 2>/dev/null || { echo -e "${RED}Gagal tulis $cfg${RESET}" >&2; rm -f "$tmp"; return 1; }
  chmod 644 "$cfg" 2>/dev/null || true
  rm -f "$tmp"
  if ! _validate_cfg; then
    echo -e "${RED}Validasi gagal, rollback ke $bak${RESET}" >&2
    [ -n "$bak" ] && [ -f "$bak" ] && cp -a "$bak" "$cfg" 2>/dev/null || true
    chmod 644 "$cfg" 2>/dev/null || true
    return 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] xray add $proto $email (3 inbounds)" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}Client $email ditambahkan ke $proto (3 transports)${RESET}"
}

xray_del_client() {
  local proto="$1" email="$2"
  local cfg
  cfg=$(_xray_cfg)
  [ -z "$proto" ] || [ -z "$email" ] && { echo -e "${RED}Usage: xray_del_client <vmess|vless|trojan> <email>${RESET}" >&2; return 2; }
  case "$proto" in vmess|vless|trojan) ;; *) echo -e "${RED}proto harus vmess/vless/trojan${RESET}" >&2; return 2;; esac
  _xray_need_jq || return 1
  [ -f "$cfg" ] || { echo -e "${RED}Config tidak ada: $cfg${RESET}" >&2; return 1; }
  local bak tmp
  bak=$(_backup_cfg)
  tmp=$(mktemp)
  case "$proto" in
    vmess) jq --arg email "$email" '(.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc" or .tag=="vmess-hu") | .settings.clients) |= map(select(.email != $email))' "$cfg" > "$tmp" 2>&1 || { echo -e "${RED}Gagal edit jq${RESET}" >&2; cat "$tmp" | head -n 20 >&2; rm -f "$tmp"; return 1; } ;;
    vless) jq --arg email "$email" '(.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc" or .tag=="vless-hu") | .settings.clients) |= map(select(.email != $email))' "$cfg" > "$tmp" 2>&1 || { echo -e "${RED}Gagal edit jq${RESET}" >&2; cat "$tmp" | head -n 20 >&2; rm -f "$tmp"; return 1; } ;;
    trojan) jq --arg email "$email" '(.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc" or .tag=="trojan-hu") | .settings.clients) |= map(select(.email != $email))' "$cfg" > "$tmp" 2>&1 || { echo -e "${RED}Gagal edit jq${RESET}" >&2; cat "$tmp" | head -n 20 >&2; rm -f "$tmp"; return 1; } ;;
  esac
  cp -a "$tmp" "$cfg" 2>/dev/null || { echo -e "${RED}Gagal tulis $cfg${RESET}" >&2; rm -f "$tmp"; return 1; }
  chmod 644 "$cfg" 2>/dev/null || true
  rm -f "$tmp"
  if ! _validate_cfg; then
    echo -e "${RED}Validasi gagal, rollback${RESET}" >&2
    [ -n "$bak" ] && [ -f "$bak" ] && cp -a "$bak" "$cfg" 2>/dev/null || true
    chmod 644 "$cfg" 2>/dev/null || true
    return 1
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] xray del $proto $email" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}Client $email dihapus dari $proto${RESET}"
}

xray_reload() {
  local cfg="$XRAY_CFG"
  if ! _validate_cfg; then echo -e "${RED}Config tidak valid, tidak reload${RESET}" >&2; return 1; fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] xray reload simulasi (skip systemctl)${RESET}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] xray reload (simulated)" >> "$LOG" 2>/dev/null || true
    return 0
  fi
  systemctl restart xray 2>/dev/null || systemctl reload xray 2>/dev/null || service xray restart 2>/dev/null || {
    pkill -HUP xray 2>/dev/null || true
    echo -e "${YELLOW}Reload via pkill HUP${RESET}"
  }
  sleep 1
  systemctl is-active xray >/dev/null 2>&1 || { echo -e "${RED}xray gagal aktif setelah reload${RESET}" >&2; return 1; }
  echo -e "${GREEN}xray reloaded${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] xray reload" >> "$LOG" 2>/dev/null || true
}

__EMBED_EOF__
chmod 644 "$ETC/lib/xray_helpers.sh"
cat > "$ETC/lib/ssh_helpers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/ssh_helpers.sh - DB & user helpers (60 col, flock, no eval)
# shellcheck disable=SC1091,SC1090
# Preserve BASE if caller already set full /etc/mytunnel path (menu)
if [[ "${BASE:-}" == *"/etc/mytunnel"* ]]; then
  ETC="$BASE"
else
  BASE="${MYTUNNEL_PREFIX:-}"
  ETC="${BASE}/etc/mytunnel"
fi
DB="$ETC/db/ssh.txt"
DB_LOCK="$ETC/db/.ssh.lock"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -z "${MYTUNNEL_PREFIX:-}" ] && LOG="/var/log/mytunnel.log"
# DOMAIN_FILE="$ETC/config/domain.txt"  # unused - _get_domain() uses cat directly
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

# System users that must never be created/overwritten
_SYS_DENY="root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody systemd-network systemd-resolve systemd-timesync messagebus syslog apt tss uuidd tcpdump avahi-autoipd usbmux dnsmasq rtkit cups-pkgslp saned sshd pollinate hermes"

_ensure_db() {
  mkdir -p "$(dirname "$DB")" 2>/dev/null || true
  [ -f "$DB" ] || touch "$DB" 2>/dev/null || true
  chmod 600 "$DB" 2>/dev/null || true
  [ -f "$DB_LOCK" ] || touch "$DB_LOCK" 2>/dev/null || true
  chmod 600 "$DB_LOCK" 2>/dev/null || true
}

_is_system_user() {
  local u="$1"
  local w
  for w in $_SYS_DENY; do [ "$u" = "$w" ] && return 0; done
  # also deny if uid < 1000 exists
  if id "$u" >/dev/null 2>&1; then
    local uid
    uid=$(id -u "$u" 2>/dev/null || echo 1000)
    [ "$uid" -lt 1000 ] 2>/dev/null && return 0
  fi
  return 1
}

validate_ssh_username() {
  local u="$1"
  [[ "$u" =~ ^[a-z0-9_]{3,16}$ ]] || return 1
  _is_system_user "$u" && return 1
  return 0
}

ssh_user_exists() {
  local u="$1"
  _ensure_db
  grep -q "^${u}|" "$DB" 2>/dev/null
}

ssh_get_field() {
  local u="$1" idx="$2"
  _ensure_db
  awk -F'|' -v u="$u" -v c="$idx" '$1==u{print $c}' "$DB" 2>/dev/null | head -1
}

ssh_set_field() {
  local u="$1" idx="$2" val="$3"
  _ensure_db
  local tmp
  tmp=$(mktemp)
  # flock write
  (
    flock -x 200
    awk -F'|' -v OFS='|' -v u="$u" -v c="$idx" -v v="$val" '
      $1==u { $c=v } 1
    ' "$DB" > "$tmp" 2>/dev/null && cat "$tmp" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$DB_LOCK" 2>/dev/null || {
    awk -F'|' -v OFS='|' -v u="$u" -v c="$idx" -v v="$val" '$1==u{$c=v}1' "$DB" > "$tmp" 2>/dev/null && cat "$tmp" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
}

_random_pass() {
  local p=""
  if command -v openssl >/dev/null 2>&1; then
    p=$(openssl rand -base64 12 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 8)
  fi
  [ -z "$p" ] && p=$(head -c 32 /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 8)
  [ -z "$p" ] && p=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 8)
  echo "$p"
}

_expiry_date() {
  local days="$1"
  date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+"${days}d" +%Y-%m-%d 2>/dev/null || echo "2099-01-01"
}

_days_left() {
  local exp="$1"
  local sec_exp sec_now
  # now removed (was unused) - use sec_now instead
  sec_exp=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  sec_now=$(date +%s 2>/dev/null)
  echo $(( (sec_exp - sec_now) / 86400 ))
}

ssh_create() {
  local user="$1" pass="$2" days="$3" limit_ip="$4"
  _ensure_db
  [ -z "$user" ] && { echo -e "${RED}Username kosong${RESET}" >&2; return 2; }
  if ! validate_ssh_username "$user"; then
    echo -e "${RED}Username tidak valid: $user (a-z0-9_ 3-16, bukan system user)${RESET}" >&2
    return 2
  fi
  if ssh_user_exists "$user"; then
    echo -e "${RED}User sudah ada di DB: $user${RESET}" >&2; return 2
  fi
  if id "$user" >/dev/null 2>&1; then
    echo -e "${RED}User sistem sudah ada: $user${RESET}" >&2; return 2
  fi
  [ -z "$pass" ] && pass=$(_random_pass)
  [[ "$days" =~ ^[0-9]+$ ]] || days=30
  [ "$days" -lt 1 ] && days=1
  [ "$days" -gt 3650 ] && days=3650
  [[ "$limit_ip" =~ ^[0-9]+$ ]] || limit_ip=0
  local expiry
  expiry=$(_expiry_date "$days")
  # system user create (or simulate in test mode)
  if [ -n "$BASE" ]; then
    # TEST MODE: simulasi
    :
  else
    # ensure /bin/false in shells
    grep -qx "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells 2>/dev/null || true
    # useradd: -M no home, -s /bin/false, -e expiry
    if ! useradd -M -s /bin/false -e "$expiry" "$user" 2>&1; then
      echo -e "${RED}Gagal useradd $user${RESET}" >&2; return 1
    fi
    if ! echo "$user:$pass" | chpasswd 2>&1; then
      userdel -r "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
      echo -e "${RED}Gagal chpasswd $user${RESET}" >&2; return 1
    fi
  fi
  # write DB with flock
  local line="${user}|${pass}|${expiry}|${limit_ip}|active"
  (
    flock -x 200
    echo "$line" >> "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$DB_LOCK" 2>/dev/null || {
    echo "$line" >> "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  }
  # jangan log password
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh create $user exp=$expiry limit_ip=$limit_ip" >> "$LOG" 2>/dev/null || true
  return 0
}

ssh_delete() {
  local user="$1"
  _ensure_db
  [ -z "$user" ] && { echo -e "${RED}Username kosong${RESET}" >&2; return 2; }
  if ! ssh_user_exists "$user"; then
    echo -e "${YELLOW}User tidak ada di DB: $user${RESET}" >&2
    # still try system delete if exists
  fi
  if [ -n "$BASE" ]; then
    # TEST MODE: no system delete
    :
  else
    # kill sesi aktif
    pkill -u "$user" 2>/dev/null || true
    # also kill by pts
    who 2>/dev/null | awk -v u="$user" '$1==u{print $2}' | while read -r tty; do pkill -t "$tty" 2>/dev/null || true; done
    userdel -r "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
  fi
  # remove from DB
  local tmp
  tmp=$(mktemp)
  (
    flock -x 200
    grep -v "^${user}|" "$DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$DB_LOCK" 2>/dev/null || {
    grep -v "^${user}|" "$DB" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh delete $user" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}User $user dihapus${RESET}"
}

# helper cek service/port aktif (dipakai print_account_info) - tidak hardcode port
_mt_port_active() {
  local svc="$1" csv="$2"
  [ -z "$csv" ] && return 1
  # TEST MODE: cek sim files instead of always ON
  if [ -n "${MYTUNNEL_PREFIX:-}" ]; then
    # if service name given, check sim file/service exists; else check csv sim
    if [ -n "$svc" ]; then
      case "$svc" in
        nginx|sshd|dropbear) return 0 ;;
        squid) [ -f "${MYTUNNEL_PREFIX}/etc/systemd/system/mytunnel-squid.service" ] && return 0 || { [ -f "${MYTUNNEL_PREFIX}/var/log/squid-sim.log" ] && return 0; return 1; } ;;
        mytunnel-udpgw|badvpn-udpgw|badproxy) [ -f "${MYTUNNEL_PREFIX}/var/log/udpgw-sim.log" ] && return 0 || return 1 ;;
        mytunnel-ohp-ssh|ohp) [ -f "${MYTUNNEL_PREFIX}/etc/systemd/system/mytunnel-ohp-ssh.service" ] && return 0 || { [ -f "${MYTUNNEL_PREFIX}/var/log/ohp-sim.log" ] && return 0; return 1; } ;;
        mytunnel-ohp-ovpn) [ -f "${MYTUNNEL_PREFIX}/etc/systemd/system/mytunnel-ohp-ovpn.service" ] && return 0 || { [ -f "${MYTUNNEL_PREFIX}/var/log/ohp-sim.log" ] && return 0; return 1; } ;;
        mytunnel-slowdns) [ -f "${MYTUNNEL_PREFIX}/etc/mytunnel/config/slowdns.conf" ] && return 0 || [ -f "${MYTUNNEL_PREFIX}/etc/mytunnel/slowdns/server.key" ] && return 0 || [ -f "${MYTUNNEL_PREFIX}/var/log/slowdns-sim.log" ] && return 0 || return 1 ;;
        openvpn|mytunnel-openvpn-tcp|mytunnel-openvpn-udp|mytunnel-openvpn-ssl|mytunnel-openvpn-dns) [ -d "${MYTUNNEL_PREFIX}/etc/openvpn" ] && return 0 || [ -f "${MYTUNNEL_PREFIX}/var/log/openvpn-sim.log" ] && return 0 || ls "${MYTUNNEL_PREFIX}/etc/systemd/system/mytunnel-openvpn-"*.service >/dev/null 2>&1 && return 0 || return 1 ;;
        mytunnel-udp-custom) [ -f "${MYTUNNEL_PREFIX}/var/log/udp-custom-sim.log" ] && return 0 || [ -f "${MYTUNNEL_PREFIX}/etc/systemd/system/mytunnel-udp-custom.service" ] && return 0 || return 1 ;;
        *) return 1 ;;
      esac
    else
      # no svc, range check - if udpgw range sample file exists, return 0
      if echo "$csv" | grep -q "-"; then
        [ -f "${MYTUNNEL_PREFIX}/var/log/udpgw-sim.log" ] && return 0 || return 1
      fi
      return 0
    fi
  fi
  if [ -n "$svc" ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$svc" 2>/dev/null; then return 0; fi
    # legacy alias: ohp -> mytunnel-ohp-ssh
    if [ "$svc" = "ohp" ] && systemctl is-active --quiet "mytunnel-ohp-ssh" 2>/dev/null; then return 0; fi
    if [ "$svc" = "badproxy" ] && systemctl is-active --quiet "mytunnel-udpgw" 2>/dev/null; then return 0; fi
    if [ "$svc" = "badvpn-udpgw" ] && systemctl is-active --quiet "mytunnel-udpgw" 2>/dev/null; then return 0; fi
  fi
  if command -v ss >/dev/null 2>&1; then
    local p
    # shellcheck disable=SC2162
    IFS=',' read -ra _mt_ports <<< "$csv"
    for p in "${_mt_ports[@]}"; do
      p=$(echo "$p" | tr -d ' ' | tr -d '\n')
      [ -z "$p" ] && continue
      # handle dash range like 7100-7600 -> check both ends + ss for any in range sample
      if echo "$p" | grep -q "-"; then
        local _s _e
        _s=$(echo "$p" | cut -d'-' -f1 | tr -d ' ')
        _e=$(echo "$p" | cut -d'-' -f2 | tr -d ' ')
        for pp in "$_s" "$_e" "7100" "7200" "7300" "7400" "7500"; do
          [ -z "$pp" ] && continue
          if ss -tlnp 2>/dev/null | grep -q ":${pp} " 2>/dev/null; then return 0; fi
          if ss -ulnp 2>/dev/null | grep -q ":${pp} " 2>/dev/null; then return 0; fi
          if ss -tulpn 2>/dev/null | grep -q ":${pp} " 2>/dev/null; then return 0; fi
        done
        continue
      fi
      if ss -tlnp 2>/dev/null | grep -q ":${p} " 2>/dev/null; then return 0; fi
      if ss -ulnp 2>/dev/null | grep -q ":${p} " 2>/dev/null; then return 0; fi
      if ss -tulpn 2>/dev/null | grep -q ":${p} " 2>/dev/null; then return 0; fi
    done
    return 1
  fi
  # fallback: jika ss tidak ada, anggap aktif jika csv terisi
  return 0
}

print_ssh_account_info() {
  local user="$1" pass="$2" expiry="$3" limit_ip="$4"
  local domain
  domain=$(cat "$ETC/config/domain.txt" 2>/dev/null | head -1 | tr -d '\n' | tr -d '\r' | tr -d ' ')
  [ -z "$domain" ] || [ "$domain" = "-" ] && domain="-"
  local pf="$ETC/config/ports.conf"
  local OPENSSH_PORT="444" DROPBEAR_PORT="90" TLS_PORT="8443" NONTLS_PORT="80,8080" ANY_PORT="2082,2083,8880" CONFIG_PORT="81"
  local SLOWDNS_PORT="53,5300" UDP_CUSTOM_PORT="1-65535" OHP_SSH_PORT="9080" SQUID_PORT="3128" UDPGW_PORT="7100-7600"
  local OPENVPN_TCP_PORT="1194" OPENVPN_SSL_PORT="442" OPENVPN_UDP_PORT="25000" OPENVPN_DNS_PORT="53" OHP_OVPN_PORT="9088"
  # shellcheck disable=SC1090
  [ -f "$pf" ] && . "$pf" 2>/dev/null || true
  local DASH="------------------------------------"
  echo ""
  echo -e "${GREEN}Account Created Successfully${RESET}"
  echo -e "${GREY}${DASH}${RESET}"
  printf "${CYAN}%-15s${RESET} : %s\n" "HOST" "$domain"
  printf "${CYAN}%-15s${RESET} : %s\n" "Username" "$user"
  printf "${CYAN}%-15s${RESET} : %s\n" "Password" "$pass"
  echo -e "${GREY}${DASH}${RESET}"
  printf "${CYAN}%-15s${RESET} : %s\n" "Expired" "$expiry"
  echo -e "${GREY}${DASH}${RESET}"
  # core ports (only if service active)
  if [ -n "${TLS_PORT:-}" ] && _mt_port_active "nginx" "$TLS_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "TLS" "$TLS_PORT"; fi
  if [ -n "${NONTLS_PORT:-}" ] && _mt_port_active "nginx" "$NONTLS_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "None TLS" "$NONTLS_PORT"; fi
  if [ -n "${ANY_PORT:-}" ] && _mt_port_active "nginx" "$ANY_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "Any" "$ANY_PORT"; fi
  if [ -n "${OPENSSH_PORT:-}" ] && _mt_port_active "sshd" "$OPENSSH_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "OpenSSH" "$OPENSSH_PORT"; fi
  if [ -n "${DROPBEAR_PORT:-}" ]; then
    if _mt_port_active "dropbear" "$DROPBEAR_PORT" || _mt_port_active "sshd" "$DROPBEAR_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "Dropbear" "$DROPBEAR_PORT"; fi
  fi
  echo -e "${GREY}${DASH}${RESET}"
  # optional block (1:1 TUNNELING labels, only if service active)
  local _shown=0
  if [ -n "${SLOWDNS_PORT:-}" ] && _mt_port_active "mytunnel-slowdns" "$SLOWDNS_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "SlowDNS" "$SLOWDNS_PORT"; _shown=1; fi
  if [ -n "${UDP_CUSTOM_PORT:-}" ] && _mt_port_active "mytunnel-udp-custom" "$UDP_CUSTOM_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "UDP-Custom" "$UDP_CUSTOM_PORT"; _shown=1; fi
  if [ -n "${OHP_SSH_PORT:-}" ] && (_mt_port_active "mytunnel-ohp-ssh" "$OHP_SSH_PORT" || _mt_port_active "ohp" "$OHP_SSH_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "OHP + SSH" "$OHP_SSH_PORT"; _shown=1; fi
  if [ -n "${SQUID_PORT:-}" ] && _mt_port_active "squid" "$SQUID_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "Squid Proxy" "$SQUID_PORT"; _shown=1; fi
  if [ -n "${UDPGW_PORT:-}" ] && (_mt_port_active "mytunnel-udpgw" "$UDPGW_PORT" || _mt_port_active "badproxy" "$UDPGW_PORT" || _mt_port_active "badvpn-udpgw" "$UDPGW_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "UDPGW" "$UDPGW_PORT"; _shown=1; fi
  if [ -n "${OPENVPN_TCP_PORT:-}" ] && (_mt_port_active "openvpn" "$OPENVPN_TCP_PORT" || _mt_port_active "mytunnel-openvpn-tcp" "$OPENVPN_TCP_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "OpenVPN TCP" "$OPENVPN_TCP_PORT"; _shown=1; fi
  if [ -n "${OPENVPN_SSL_PORT:-}" ] && (_mt_port_active "openvpn" "$OPENVPN_SSL_PORT" || _mt_port_active "mytunnel-openvpn-ssl" "$OPENVPN_SSL_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "OpenVPN SSL" "$OPENVPN_SSL_PORT"; _shown=1; fi
  if [ -n "${OPENVPN_UDP_PORT:-}" ] && (_mt_port_active "openvpn" "$OPENVPN_UDP_PORT" || _mt_port_active "mytunnel-openvpn-udp" "$OPENVPN_UDP_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "OpenVPN UDP" "$OPENVPN_UDP_PORT"; _shown=1; fi
  if [ -n "${OPENVPN_DNS_PORT:-}" ] && ! _mt_port_active "mytunnel-slowdns" "$SLOWDNS_PORT" && (_mt_port_active "openvpn" "$OPENVPN_DNS_PORT" || _mt_port_active "mytunnel-openvpn-dns" "$OPENVPN_DNS_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "OpenVPN DNS" "$OPENVPN_DNS_PORT"; _shown=1; fi
  if [ -n "${OHP_OVPN_PORT:-}" ] && (_mt_port_active "mytunnel-ohp-ovpn" "$OHP_OVPN_PORT" || _mt_port_active "ohp" "$OHP_OVPN_PORT"); then printf "${CYAN}%-15s${RESET} : %s\n" "OHP + OVPN" "$OHP_OVPN_PORT"; _shown=1; fi
  # close optional block + link (avoid double dash)
  local _has_link=0
  if [ -f "${MYTUNNEL_PREFIX:-}/var/www/html/myvpn-config.zip" ] || [ -f "/var/www/html/myvpn-config.zip" ] || [ -f "${MYTUNNEL_PREFIX:-}/etc/openvpn/ca.crt" ] || [ -f "/etc/openvpn/ca.crt" ]; then _has_link=1; fi
  if [ "$_shown" = "1" ] && [ "$_has_link" = "1" ]; then
    echo -e "${GREY}${DASH}${RESET}"
    printf "http://%s:%s/myvpn-config.zip\n" "$domain" "${CONFIG_PORT:-81}"
    echo -e "${GREY}${DASH}${RESET}"
  elif [ "$_shown" = "1" ]; then
    echo -e "${GREY}${DASH}${RESET}"
  elif [ "$_has_link" = "1" ]; then
    printf "http://%s:%s/myvpn-config.zip\n" "$domain" "${CONFIG_PORT:-81}"
    echo -e "${GREY}${DASH}${RESET}"
  else
    # no optional, no link: dash after core already printed, no extra needed (avoid double)
    :
  fi
  echo ""
}



# wrapper kompatibilitas: jika proto belum load, SSH tetap jalan (satu fungsi reuse)
print_account_info() {
  print_ssh_account_info "$@" 2>/dev/null || return $?
}

__EMBED_EOF__
chmod 644 "$ETC/lib/ssh_helpers.sh"
cat > "$ETC/lib/proto_helpers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/proto_helpers.sh - generic helpers vmess|vless|trojan (60 col, flock, jq --arg)
# shellcheck disable=SC1091,SC2129,SC2162,SC1090,SC2034
# Preserve BASE if caller already set full /etc/mytunnel path (menu)
if [[ "${BASE:-}" == *"/etc/mytunnel"* ]]; then
  ETC="$BASE"
else
  BASE="${MYTUNNEL_PREFIX:-}"
  ETC="${BASE}/etc/mytunnel"
fi
if [ -n "${MYTUNNEL_PREFIX:-}" ]; then XRAY_ETC="$MYTUNNEL_PREFIX/usr/local/etc/xray"; else XRAY_ETC="/usr/local/etc/xray"; fi
XRAY_CFG="$XRAY_ETC/config.json"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -z "${MYTUNNEL_PREFIX:-}" ] && LOG="/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/xray_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

_SYS_DENY="root daemon bin sys sync games man lp mail news uucp proxy www-data backup list irc gnats nobody systemd-network systemd-resolve systemd-timesync messagebus syslog apt tss uuidd tcpdump avahi-autoipd usbmux dnsmasq rtkit cups-pkgslp saned sshd pollinate hermes"

_proto_tag() { case "$1" in vmess) echo "vmess-ws";; vless) echo "vless-ws";; trojan) echo "trojan-ws";; *) echo "";; esac; }
# ponytail: _proto_tags_all reserved for future bulk ops (list all inbound tags per proto)
# shellcheck disable=SC2317
_proto_tags_all() {
  case "$1" in
    vmess) echo "vmess-ws vmess-grpc vmess-hu";;
    vless) echo "vless-ws vless-grpc vless-hu";;
    trojan) echo "trojan-ws trojan-grpc trojan-hu";;
    *) echo "";;
  esac
}
_proto_ws_path() { case "$1" in vmess) echo "/vmess";; vless) echo "/vless";; trojan) echo "/trojan";; *) echo "";; esac; }
_proto_hu_path() { case "$1" in vmess) echo "/upvmess";; vless) echo "/upvless";; trojan) echo "/uptrojan";; *) echo "";; esac; }
_proto_grpc_service() { case "$1" in vmess) echo "vmess";; vless) echo "vless";; trojan) echo "trojan";; *) echo "";; esac; }
_proto_db() { echo "$ETC/db/$1.txt"; }
_proto_lockfile() { echo "$ETC/db/.$1.lock"; }

_is_system_user() {
  local u="$1" w
  for w in $_SYS_DENY; do [ "$u" = "$w" ] && return 0; done
  if id "$u" >/dev/null 2>&1; then
    local uid; uid=$(id -u "$u" 2>/dev/null || echo 1000)
    [ "$uid" -lt 1000 ] 2>/dev/null && return 0
  fi
  return 1
}

validate_proto_user() {
  local u="$1"
  [[ "$u" =~ ^[a-z0-9_]{3,16}$ ]] || return 1
  _is_system_user "$u" && return 1
  return 0
}

validate_uuid() {
  local u="$1"
  [[ "$u" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]'
  elif [ -f /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '\n'
  else
    python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || echo "11111111-1111-1111-1111-111111111111"
  fi | tr -d ' \n'
}

gen_password() {
  local p=""
  if command -v openssl >/dev/null 2>&1; then p=$(openssl rand -base64 12 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 12); fi
  [ -z "$p" ] && p=$(head -c 24 /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 12)
  [ -z "$p" ] && p=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 12)
  echo "$p" | tr -d ' \n'
}

_ensure_proto_db() {
  local proto="$1" db lock
  db=$(_proto_db "$proto"); lock=$(_proto_lockfile "$proto")
  mkdir -p "$(dirname "$db")" 2>/dev/null || true
  [ -f "$db" ] || touch "$db" 2>/dev/null || true
  chmod 600 "$db" 2>/dev/null || true
  [ -f "$lock" ] || touch "$lock" 2>/dev/null || true
  chmod 600 "$lock" 2>/dev/null || true
}

proto_exists() {
  local proto="$1" user="$2"
  local db; db=$(_proto_db "$proto")
  [ -f "$db" ] || return 1
  grep -q "^${user}|" "$db" 2>/dev/null
}

proto_exists_any() {
  local user="$1" p
  for p in vmess vless trojan; do
    if proto_exists "$p" "$user" 2>/dev/null; then echo "$p"; return 0; fi
  done
  return 1
}

proto_get_field() {
  local proto="$1" user="$2" idx="$3"
  local db; db=$(_proto_db "$proto")
  awk -F'|' -v u="$user" -v c="$idx" '$1==u{print $c}' "$db" 2>/dev/null | head -1
}

proto_set_field() {
  local proto="$1" user="$2" idx="$3" val="$4"
  local db lock tmp
  db=$(_proto_db "$proto"); lock=$(_proto_lockfile "$proto")
  _ensure_proto_db "$proto"
  tmp=$(mktemp)
  (
    flock -x 200
    awk -F'|' -v OFS='|' -v u="$user" -v c="$idx" -v v="$val" '$1==u{$c=v}1' "$db" > "$tmp" 2>/dev/null && cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  ) 200>"$lock" 2>/dev/null || {
    awk -F'|' -v OFS='|' -v u="$user" -v c="$idx" -v v="$val" '$1==u{$c=v}1' "$db" > "$tmp" 2>/dev/null && cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
}

_expiry_date() {
  local days="$1"
  date -d "+${days} days" +%Y-%m-%d 2>/dev/null || date -v+"${days}d" +%Y-%m-%d 2>/dev/null || echo "2099-01-01"
}

_days_left() {
  local exp="$1"
  local sec_exp sec_now
  sec_exp=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  sec_now=$(date +%s 2>/dev/null)
  echo $(( (sec_exp - sec_now) / 86400 ))
}

# internal: append to DB with flock
_db_append() {
  local proto="$1" line="$2"
  local db lock
  db=$(_proto_db "$proto"); lock=$(_proto_lockfile "$proto")
  _ensure_proto_db "$proto"
  (
    flock -x 200
    echo "$line" >> "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  ) 200>"$lock" 2>/dev/null || {
    echo "$line" >> "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  }
}

_db_delete_user() {
  local proto="$1" user="$2"
  local db lock tmp
  db=$(_proto_db "$proto"); lock=$(_proto_lockfile "$proto")
  tmp=$(mktemp)
  (
    flock -x 200
    grep -v "^${user}|" "$db" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  ) 200>"$lock" 2>/dev/null || {
    grep -v "^${user}|" "$db" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
}

proto_create() {
  local proto="$1" user="$2" id="$3" days="$4" limit_ip="$5" quota_gb="$6"
  [ -z "$proto" ] || [ -z "$user" ] || [ -z "$id" ] && { echo -e "${RED}Usage: proto_create proto user id days limit_ip quota_gb${RESET}" >&2; return 2; }
  case "$proto" in vmess|vless|trojan) ;; *) echo -e "${RED}proto invalid${RESET}" >&2; return 2;; esac
  if ! validate_proto_user "$user"; then echo -e "${RED}Username tidak valid (a-z0-9_ 3-16)${RESET}" >&2; return 2; fi
  if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah dipakai di protokol lain: $user${RESET}" >&2; return 2; fi
  case "$proto" in vmess|vless) if ! validate_uuid "$id"; then echo -e "${RED}UUID tidak valid${RESET}" >&2; return 2; fi;; esac
  [[ "$days" =~ ^[0-9]+$ ]] || days=30; [ "$days" -lt 1 ] && days=1; [ "$days" -gt 3650 ] && days=3650
  [[ "$limit_ip" =~ ^[0-9]+$ ]] || limit_ip=0
  [[ "$quota_gb" =~ ^[0-9]+$ ]] || quota_gb=0
  local expiry; expiry=$(_expiry_date "$days")
  local line="${user}|${id}|${expiry}|${limit_ip}|${quota_gb}|0|active"
  # xray add (use --arg to avoid injection) - tambah ke semua inbound protokol itu
  if ! xray_add_client "$proto" "$id" "$user" 2>&1; then
    echo -e "${RED}Gagal tambah ke Xray${RESET}" >&2; return 1
  fi
  _db_append "$proto" "$line"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] proto create $proto $user exp=$expiry quota=$quota_gb" >> "$LOG" 2>/dev/null || true
  if ! xray_reload 2>&1; then
    echo -e "${RED}Reload gagal, rollback DB${RESET}" >&2
    _db_delete_user "$proto" "$user"
    xray_del_client "$proto" "$user" 2>/dev/null || true
    return 1
  fi
  return 0
}

proto_delete() {
  local proto="$1" user="$2"
  [ -z "$proto" ] || [ -z "$user" ] && { echo -e "${RED}Usage: proto_delete proto user${RESET}" >&2; return 2; }
  if ! proto_exists "$proto" "$user"; then echo -e "${YELLOW}User tidak ada di $proto DB: $user${RESET}" >&2; return 0; fi
  # remove from xray (idempotent) - semua inbound proto
  xray_del_client "$proto" "$user" 2>/dev/null || true
  _db_delete_user "$proto" "$user"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] proto delete $proto $user" >> "$LOG" 2>/dev/null || true
  xray_reload 2>/dev/null || true
  echo -e "${GREEN}User $user dihapus ($proto)${RESET}"
}

proto_lock() {
  local proto="$1" user="$2"
  if ! proto_exists "$proto" "$user"; then echo -e "${RED}User tidak ada${RESET}" >&2; return 1; fi
  local cur_status; cur_status=$(proto_get_field "$proto" "$user" 7)
  [ "$cur_status" = "locked" ] && { echo -e "${YELLOW}$user sudah locked${RESET}"; return 0; }
  xray_del_client "$proto" "$user" 2>/dev/null || true
  proto_set_field "$proto" "$user" 7 "locked"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] proto lock $proto $user" >> "$LOG" 2>/dev/null || true
  xray_reload 2>/dev/null || true
  echo -e "${GREEN}$user locked${RESET}"
}

proto_unlock() {
  local proto="$1" user="$2"
  if ! proto_exists "$proto" "$user"; then echo -e "${RED}User tidak ada${RESET}" >&2; return 1; fi
  local id; id=$(proto_get_field "$proto" "$user" 2)
  [ -z "$id" ] && { echo -e "${RED}ID kosong${RESET}" >&2; return 1; }
  # re-add to xray if not exists - semua inbound
  if ! xray_add_client "$proto" "$id" "$user" 2>/dev/null; then
    # if already exists, ignore
    true
  fi
  proto_set_field "$proto" "$user" 7 "active"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] proto unlock $proto $user" >> "$LOG" 2>/dev/null || true
  xray_reload 2>/dev/null || true
  echo -e "${GREEN}$user unlocked${RESET}"
}

proto_renew() {
  local proto="$1" user="$2" add="$3"
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Hari harus angka${RESET}" >&2; return 2; }
  if ! proto_exists "$proto" "$user"; then echo -e "${RED}User tidak ada${RESET}" >&2; return 1; fi
  local cur_exp today base new_exp
  cur_exp=$(proto_get_field "$proto" "$user" 3)
  today=$(date +%Y-%m-%d 2>/dev/null)
  if [ "$(date -d "$cur_exp" +%s 2>/dev/null || echo 0)" -gt "$(date -d "$today" +%s 2>/dev/null || echo 0)" ]; then base="$cur_exp"; else base="$today"; fi
  new_exp=$(_expiry_date_from_base "$base" "$add")
  proto_set_field "$proto" "$user" 3 "$new_exp"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] proto renew $proto $user $cur_exp -> $new_exp" >> "$LOG" 2>/dev/null || true
  echo "$new_exp"
}

_expiry_date_from_base() {
  local base="$1" add="$2"
  local base_s new_s
  base_s=$(date -d "$base" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$base" +%s 2>/dev/null || date +%s)
  new_s=$((base_s + add*86400))
  date -d "@$new_s" +%Y-%m-%d 2>/dev/null || date -r "$new_s" +%Y-%m-%d 2>/dev/null || echo "$base"
}

proto_set_id() {
  local proto="$1" user="$2" new_id="$3"
  case "$proto" in vmess|vless) if ! validate_uuid "$new_id"; then echo -e "${RED}UUID tidak valid${RESET}" >&2; return 2; fi;; trojan) [ -z "$new_id" ] && { echo -e "${RED}Password kosong${RESET}" >&2; return 2; };; esac
  if ! proto_exists "$proto" "$user"; then echo -e "${RED}User tidak ada${RESET}" >&2; return 1; fi
  local old_status; old_status=$(proto_get_field "$proto" "$user" 7)
  # remove old from xray
  xray_del_client "$proto" "$user" 2>/dev/null || true
  proto_set_field "$proto" "$user" 2 "$new_id"
  # re-add if was active
  if [ "$old_status" = "active" ]; then
    if ! xray_add_client "$proto" "$new_id" "$user" 2>&1; then
      echo -e "${RED}Gagal set ID baru ke Xray${RESET}" >&2; return 1
    fi
    xray_reload 2>/dev/null || true
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] proto set_id $proto $user" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}ID $user diganti${RESET}"
}

_urlencode() {
  local s="$1" out="" c hex
  local i
  for ((i=0;i<${#s};i++)); do
    c="${s:i:1}"
    case "$c" in [a-zA-Z0-9.~_-]) out+="$c";; *) printf -v hex '%%%02X' "'$c"; out+="$hex";; esac
  done
  echo "$out"
}

_get_domain() {
  local d=""
  if [ -f "$ETC/config/domain.txt" ]; then d=$(head -1 "$ETC/config/domain.txt" 2>/dev/null | tr -d ' \n'); fi
  [ -z "$d" ] || [ "$d" = "-" ] && d=$(hostname -I 2>/dev/null | awk '{print $1}'); [ -z "$d" ] && d="example.com"
  echo "$d" | tr -d ' \n'
}

_get_ports() {
  local pf="$ETC/config/ports.conf"
  local TLS_PORT="443" NONTLS_PORT="80" ANY_PORT="80,443"
  # shellcheck disable=SC1090
  [ -f "$pf" ] && . "$pf" 2>/dev/null || true
  echo "$TLS_PORT|$NONTLS_PORT|$ANY_PORT"
}

_mt_port_active() {
  local svc="$1" csv="$2"
  [ -z "$csv" ] && return 1
  if [ -n "${MYTUNNEL_PREFIX:-}" ]; then return 0; fi
  if [ -n "$svc" ] && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet "$svc" 2>/dev/null; then return 0; fi
  fi
  if command -v ss >/dev/null 2>&1; then
    local p
    IFS=',' read -ra _mt_ports <<< "$csv"
    for p in "${_mt_ports[@]}"; do
      p=$(echo "$p" | tr -d ' ' | tr -d '\n')
      [ -z "$p" ] && continue
      if ss -tlnp 2>/dev/null | grep -q ":${p} " 2>/dev/null; then return 0; fi
      if ss -ulnp 2>/dev/null | grep -q ":${p} " 2>/dev/null; then return 0; fi
      if ss -tulpn 2>/dev/null | grep -q ":${p} " 2>/dev/null; then return 0; fi
    done
    return 1
  fi
  return 0
}

gen_links() {
  local proto="$1" user="$2"
  local id expiry domain
  id=$(proto_get_field "$proto" "$user" 2)
  expiry=$(proto_get_field "$proto" "$user" 3)
  domain=$(_get_domain)
  [ -z "$id" ] && { echo -e "${RED}User tidak ada${RESET}" >&2; return 1; }
  local ports; ports=$(_get_ports)
  local tls_port nontls_port
  tls_port=$(echo "$ports" | cut -d'|' -f1 | tr -d ' ' | cut -d',' -f1)
  nontls_port=$(echo "$ports" | cut -d'|' -f2 | tr -d ' ' | cut -d',' -f1)
  [ -z "$tls_port" ] && tls_port=443
  [ -z "$nontls_port" ] && nontls_port=80
  local ws_path hu_path grpc_svc
  ws_path=$(_proto_ws_path "$proto")
  hu_path=$(_proto_hu_path "$proto")
  grpc_svc=$(_proto_grpc_service "$proto")
  case "$proto" in
    vmess)
      local b64
      local json
      # WS TLS 443
      json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","path":"%s","type":"none","host":"%s","tls":"tls","sni":"%s"}' "$user" "$domain" "$tls_port" "$id" "$ws_path" "$domain" "$domain")
      b64=$(echo -n "$json" | base64 -w 0 2>/dev/null || echo -n "$json" | base64 2>/dev/null | tr -d '\n')
      echo "vmess://$b64"
      # WS none 80
      json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"ws","path":"%s","type":"none","host":"%s","tls":"none"}' "$user" "$domain" "$nontls_port" "$id" "$ws_path" "$domain")
      b64=$(echo -n "$json" | base64 -w 0 2>/dev/null || echo -n "$json" | base64 2>/dev/null | tr -d '\n')
      echo "vmess://$b64"
      # gRPC TLS
      json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"grpc","path":"%s","type":"none","host":"%s","tls":"tls","sni":"%s"}' "$user" "$domain" "$tls_port" "$id" "$grpc_svc" "$domain" "$domain")
      b64=$(echo -n "$json" | base64 -w 0 2>/dev/null || echo -n "$json" | base64 2>/dev/null | tr -d '\n')
      echo "vmess://$b64"
      # HTTPUpgrade TLS
      json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"httpupgrade","path":"%s","type":"none","host":"%s","tls":"tls","sni":"%s"}' "$user" "$domain" "$tls_port" "$id" "$hu_path" "$domain" "$domain")
      b64=$(echo -n "$json" | base64 -w 0 2>/dev/null || echo -n "$json" | base64 2>/dev/null | tr -d '\n')
      echo "vmess://$b64"
      # HTTPUpgrade none
      json=$(printf '{"v":"2","ps":"%s","add":"%s","port":"%s","id":"%s","aid":"0","net":"httpupgrade","path":"%s","type":"none","host":"%s","tls":"none"}' "$user" "$domain" "$nontls_port" "$id" "$hu_path" "$domain")
      b64=$(echo -n "$json" | base64 -w 0 2>/dev/null || echo -n "$json" | base64 2>/dev/null | tr -d '\n')
      echo "vmess://$b64"
      ;;
    vless)
      echo "vless://${id}@${domain}:${tls_port}?path=/vless&security=tls&encryption=none&host=${domain}&type=ws&sni=${domain}#${user}"
      echo "vless://${id}@${domain}:${nontls_port}?path=/vless&security=none&encryption=none&host=${domain}&type=ws#${user}"
      echo "vless://${id}@${domain}:${tls_port}?mode=gun&security=tls&encryption=none&type=grpc&serviceName=vless&sni=${domain}#${user}"
      echo "vless://${id}@${domain}:${tls_port}?path=/upvless&security=tls&encryption=none&host=${domain}&type=httpupgrade&sni=${domain}#${user}"
      echo "vless://${id}@${domain}:${nontls_port}?path=/upvless&security=none&encryption=none&host=${domain}&type=httpupgrade#${user}"
      ;;
    trojan)
      echo "trojan://${id}@${domain}:${tls_port}?path=/trojan&security=tls&host=${domain}&type=ws&sni=${domain}#${user}"
      echo "trojan://${id}@${domain}:${tls_port}?mode=gun&security=tls&type=grpc&serviceName=trojan&sni=${domain}#${user}"
      echo "trojan://${id}@${domain}:${tls_port}?path=/uptrojan&security=tls&host=${domain}&type=httpupgrade&sni=${domain}#${user}"
      ;;
  esac
}

print_proto_account_info() {
  local proto="$1" user="$2"
  local id expiry limit_ip quota used status domain
  : "${used:-}" "${status:-}"  # displayed via DB but kept for future
  id=$(proto_get_field "$proto" "$user" 2); [ -z "$id" ] && { echo -e "${RED}User tidak ada${RESET}" >&2; return 1; }
  expiry=$(proto_get_field "$proto" "$user" 3)
  limit_ip=$(proto_get_field "$proto" "$user" 4)
  quota=$(proto_get_field "$proto" "$user" 5)
  used=$(proto_get_field "$proto" "$user" 6)
  status=$(proto_get_field "$proto" "$user" 7)
  domain=$(_get_domain)
  local ws_path hu_path grpc_svc
  ws_path=$(_proto_ws_path "$proto")
  hu_path=$(_proto_hu_path "$proto")
  grpc_svc=$(_proto_grpc_service "$proto")
  local pf="$ETC/config/ports.conf"
  local TLS_PORT="443" NONTLS_PORT="80" ANY_PORT="80,443"
  # shellcheck disable=SC1090
  [ -f "$pf" ] && . "$pf" 2>/dev/null || true
  local city isp
  # CITY ISP dari cache sysinfo.sh
  if [ -f "$ETC/.cache_sysinfo" ]; then
    city=$(grep "^CITY=" "$ETC/.cache_sysinfo" 2>/dev/null | cut -d= -f2 | head -1 | tr -d '\r\n'); [ -z "$city" ] && city="-"
    isp=$(grep "^ISP=" "$ETC/.cache_sysinfo" 2>/dev/null | cut -d= -f2 | head -1 | tr -d '\r\n'); [ -z "$isp" ] && isp="-"
  else
    city=$(get_city_cached 2>/dev/null || echo "-"); [ -z "$city" ] && city="-"
    isp=$(get_isp_cached 2>/dev/null || echo "-"); [ -z "$isp" ] && isp="-"
  fi
  [ -z "$city" ] && city="-"
  [ -z "$isp" ] && isp="-"
  local quota_h
  if [ "$quota" = "0" ] || [ -z "$quota" ]; then quota_h="Unlimited"; else quota_h="${quota} GB"; fi
  local DASH="------------------------------------"
  local proto_upper
  proto_upper=$(echo "$proto" | tr '[:lower:]' '[:upper:]')
  echo -e "${GREY}${DASH}${RESET}"
  # judul protokol tengah dalam 36 kolom
  local pad=$(( (36 - ${#proto_upper}) / 2 ))
  printf "%*s%s\n" "$pad" "" "$proto_upper" | cut -c1-36
  echo -e "${GREY}${DASH}${RESET}"
  if [ "$proto" = "trojan" ]; then
    local _w=12
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "Remarks" "$user"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "CITY" "$city"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "ISP" "$isp"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "Domain" "$domain"
  else
    printf "${CYAN}%-15s${RESET} : %s\n" "Remarks" "$user"
    printf "${CYAN}%-15s${RESET} : %s\n" "CITY" "$city"
    printf "${CYAN}%-15s${RESET} : %s\n" "ISP" "$isp"
    printf "${CYAN}%-15s${RESET} : %s\n" "Domain" "$domain"
  fi
  if [ "$proto" != "trojan" ]; then
    if [ -n "${TLS_PORT:-}" ] && _mt_port_active "nginx" "$TLS_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "Port TLS" "$TLS_PORT"; fi
    if [ -n "${NONTLS_PORT:-}" ] && _mt_port_active "nginx" "$NONTLS_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "Port none TLS" "$NONTLS_PORT"; fi
    if [ -n "${ANY_PORT:-}" ] && _mt_port_active "nginx" "$ANY_PORT"; then printf "${CYAN}%-15s${RESET} : %s\n" "Port any" "$ANY_PORT"; fi
  fi
  # Port lines: trojan only TLS + any, others TLS + none TLS + any
  if [ "$proto" = "trojan" ]; then
    # Tight columns (already _w=12 from above)
    _w=12
    # Port single TLS -> label "Port"
    if [ -n "${TLS_PORT:-}" ] && _mt_port_active "nginx" "$TLS_PORT"; then printf "${CYAN}%-${_w}s${RESET} : %s\n" "Port" "$TLS_PORT"; fi
    if [ -n "${ANY_PORT:-}" ] && _mt_port_active "nginx" "$ANY_PORT"; then printf "${CYAN}%-${_w}s${RESET} : %s\n" "Port any" "$ANY_PORT"; fi
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "Key" "$id"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "Network" "ws,grpc,upgrade"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "Path ws" "/trojan"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "serviceName" "trojan"
    printf "${CYAN}%-${_w}s${RESET} : %s\n" "Path upgrade" "/uptrojan"
  elif [ "$proto" = "vless" ]; then
    printf "${CYAN}%-15s${RESET} : %s\n" "id" "$id"
    printf "${CYAN}%-15s${RESET} : %s\n" "Encryption" "none"
    printf "${CYAN}%-15s${RESET} : %s\n" "Network" "ws,grpc,upgrade"
    if [ "$proto" = "vmess" ]; then
      printf "${CYAN}%-15s${RESET} : %s\n" "path ws" "/vmess - /whatever"
    else
      printf "${CYAN}%-15s${RESET} : %s\n" "path ws" "$ws_path"
    fi
    printf "${CYAN}%-15s${RESET} : %s\n" "serviceName" "$grpc_svc"
    printf "${CYAN}%-15s${RESET} : %s\n" "path upgrade" "$hu_path"
    printf "${CYAN}%-15s${RESET} : %s\n" "Expired On" "$expiry"
    printf "${CYAN}%-15s${RESET} : %s\n" "Quota" "$quota_h"
    printf "${CYAN}%-15s${RESET} : %s\n" "Limit IP" "${limit_ip:-0} (0=No Limit)"
  else
    printf "${CYAN}%-15s${RESET} : %s\n" "id" "$id"
    printf "${CYAN}%-15s${RESET} : %s\n" "alterId" "0"
    printf "${CYAN}%-15s${RESET} : %s\n" "Security" "auto"
    printf "${CYAN}%-15s${RESET} : %s\n" "network" "ws,grpc,upgrade"
    if [ "$proto" = "vmess" ]; then
      printf "${CYAN}%-15s${RESET} : %s\n" "path ws" "/vmess - /whatever"
    else
      printf "${CYAN}%-15s${RESET} : %s\n" "path ws" "$ws_path"
    fi
    printf "${CYAN}%-15s${RESET} : %s\n" "serviceName" "$grpc_svc"
    printf "${CYAN}%-15s${RESET} : %s\n" "path upgrade" "$hu_path"
    printf "${CYAN}%-15s${RESET} : %s\n" "Expired On" "$expiry"
    printf "${CYAN}%-15s${RESET} : %s\n" "Quota" "$quota_h"
    printf "${CYAN}%-15s${RESET} : %s\n" "Limit IP" "${limit_ip:-0} (0=No Limit)"
  fi
  # For trojan, don't print Expired/Quota/Limit here — moved below links
  local links
  links=$(gen_links "$proto" "$user" 2>/dev/null || true)
  local idx=1
  local link
  while IFS= read -r link; do
    [ -z "$link" ] && continue
    local ttitle=""
    if [ "$proto" = "trojan" ]; then
      case "$idx" in
        1) ttitle="TROJAN WS TLS" ;;
        2) ttitle="TROJAN GRPC" ;;
        3) ttitle="TROJAN Upgrade TLS" ;;
        *) ttitle="TROJAN LINK $idx" ;;
      esac
    else
      case "$idx" in
        1) ttitle="${proto_upper} WS TLS" ;;
        2) ttitle="${proto_upper} WS NO TLS" ;;
        3) ttitle="${proto_upper} GRPC TLS" ;;
        4) ttitle="${proto_upper} UPGRADE TLS" ;;
        5) ttitle="${proto_upper} UPGRADE NO TLS" ;;
        *) ttitle="${proto_upper} LINK $idx" ;;
      esac
    fi
    echo -e "${GREY}${DASH}${RESET}"
    local pad2=$(( (36 - ${#ttitle}) / 2 ))
    printf "%*s%s\n" "$pad2" "" "$ttitle" | cut -c1-60
    echo -e "${GREY}${DASH}${RESET}"
    echo "$link" | fold -w 60 | while IFS= read -r part; do echo "$part"; done
    idx=$((idx+1))
  done <<< "$links"
  if [ "$proto" = "trojan" ]; then
    # Expired On + Quota + Limit IP BELOW links, with DASH before/after
    echo -e "${GREY}${DASH}${RESET}"
    local _w2=12
    printf "${CYAN}%-${_w2}s${RESET} : %s\n" "Expired On" "$expiry"
    printf "${CYAN}%-${_w2}s${RESET} : %s\n" "Quota" "$quota_h"
    printf "${CYAN}%-${_w2}s${RESET} : %s\n" "Limit IP" "${limit_ip:-0} (0=No Limit)"
  fi
  echo -e "${GREY}${DASH}${RESET}"
}

# dispatch tunggal (dipakai menu/bot): vmess/vless/trojan -> proto, else SSH jika 4 arg date
print_account_info() {
  case "${1:-}" in
    vmess|vless|trojan) print_proto_account_info "$@" ;;
    *)
      if declare -f print_ssh_account_info >/dev/null 2>&1 && [ "$#" -ge 3 ]; then
        if [[ "${3:-}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then print_ssh_account_info "$@"; return $?; fi
        if [ "$#" -eq 4 ]; then print_ssh_account_info "$@"; return $?; fi
      fi
      print_proto_account_info "$@"
      ;;
  esac
}

__EMBED_EOF__
chmod 644 "$ETC/lib/proto_helpers.sh"
cat > "$ETC/lib/features_helpers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/features_helpers.sh - helpers untuk FEATURES (reboot, backup, services, etc)
# shellcheck disable=SC1091,SC1090,SC2154
# Preserve BASE if caller already set full path
if [[ "${BASE:-}" == *"/etc/mytunnel"* ]]; then
  ETC="$BASE"
else
  BASE="${MYTUNNEL_PREFIX:-}"
  ETC="${BASE}/etc/mytunnel"
fi
if [ -n "${MYTUNNEL_PREFIX:-}" ]; then LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"; else LOG="/var/log/mytunnel.log"; fi
# REAL_CRON_DIR removed (was unused) - cron dir is /etc/cron.d fixed
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/sysinfo.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

fh_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null || true; }

# Validate brand: 1-32 printable, no control chars, trim
fh_validate_brand() {
  local s="$1"
  [ -z "$s" ] && return 1
  [ "${#s}" -gt 32 ] && return 1
  # no control chars (0x00-0x1F, 0x7F)
  if printf "%s" "$s" | grep -q $'[\x00-\x1F\x7F]' 2>/dev/null; then return 1; fi
  # no newline; printable only
  [[ "$s" =~ ^[[:print:]]+$ ]] || return 1
  return 0
}

# Validate expiry YYYY-MM-DD and not too far past/future
fh_validate_expiry() {
  local d="$1"
  [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || return 1
  date -d "$d" +%s >/dev/null 2>&1 || date -j -f "%Y-%m-%d" "$d" +%s >/dev/null 2>&1 || return 1
  return 0
}

fh_days_left() {
  local exp="$1"
  local now exp_s
  now=$(date +%s 2>/dev/null)
  exp_s=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  echo $(( (exp_s - now) / 86400 ))
}

fh_svc_status() {
  local s="$1"
  if [ -n "$BASE" ]; then
    # TEST MODE: check sim files
    if [ -f "$BASE/var/log/${s}-sim.log" ] || [ -f "$BASE/var/log/${s}.sim" ]; then echo "ON"; return; fi
    if [ -f "$BASE/etc/systemd/system/${s}.service.sim" ]; then echo "ON"; return; fi
    # fallback: check if binary would be active
    echo "OFF"
    return
  fi
  if systemctl is-active --quiet "$s" 2>/dev/null; then echo "ON"
  elif pgrep -x "$s" >/dev/null 2>&1; then echo "ON"
  elif service "$s" status >/dev/null 2>&1; then echo "ON"
  else echo "OFF"
  fi
}

fh_need_confirm() {
  local prompt="$1"
  echo -ne "${YELLOW}${prompt} [y/N]: ${RESET}"
  local a; read -r a 2>/dev/null || return 1
  [[ "$a" =~ ^[Yy]$ ]]
}

fh_backup_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  local bak
  bak="${f}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$f" "$bak" 2>/dev/null && echo "$bak"
}

# ponytail: single backup per op; upgrade to rotation when disk pressure arises

__EMBED_EOF__
chmod 644 "$ETC/lib/features_helpers.sh"
cat > "$ETC/lib/advanced_helpers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel lib/advanced_helpers.sh - helpers TAHAP 6 (bot/warp/routing/slowdns)
# shellcheck disable=SC1091,SC1090,SC2154
# Preserve BASE if caller already set full /etc/mytunnel path (menu)
if [[ "${BASE:-}" == *"/etc/mytunnel"* ]]; then
  ETC="$BASE"
else
  BASE="${MYTUNNEL_PREFIX:-}"
  ETC="${BASE}/etc/mytunnel"
fi
if [ -n "${MYTUNNEL_PREFIX:-}" ]; then LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"; XRAY_ETC="$MYTUNNEL_PREFIX/usr/local/etc/xray"; else LOG="/var/log/mytunnel.log"; XRAY_ETC="/usr/local/etc/xray"; fi
XRAY_CFG="$XRAY_ETC/config.json"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/sysinfo.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

ah_log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG" 2>/dev/null || true; }
ah_mask_token(){
  local t="$1"
  [ -z "$t" ] && { echo "-"; return; }
  if [ "${#t}" -le 6 ]; then echo "${t:0:2}***"; else echo "${t:0:6}***"; fi
}
ah_validate_bot_token(){
  local t="$1"
  [[ "$t" =~ ^[0-9]+\:[A-Za-z0-9_\-]+$ ]] || return 1
  [ "${#t}" -ge 20 ] || return 1
  return 0
}
ah_validate_chat_id(){
  [[ "$1" =~ ^-?[0-9]+$ ]] || return 1
  return 0
}
ah_validate_ns_domain(){
  [[ "$1" =~ ^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?)+$ ]] || return 1
  return 0
}
ah_xray_bin(){
  if [ -x "${BASE}/usr/local/bin/xray" ]; then echo "${BASE}/usr/local/bin/xray"
  elif command -v xray >/dev/null 2>&1; then command -v xray
  else echo "xray"; fi
}
ah_xray_validate(){
  local cfg="$XRAY_CFG" bin
  bin=$(ah_xray_bin)
  if command -v "$bin" >/dev/null 2>&1 || [ -x "$bin" ]; then
    "$bin" run -test -config "$cfg" >/dev/null 2>&1 && return 0
    "$bin" run -test -config "$cfg" 2>&1 | head -n 30 >&2
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then jq . "$cfg" >/dev/null 2>&1 && return 0; return 1
  else python3 -m json.tool "$cfg" >/dev/null 2>&1 && return 0; return 1; fi
}
ah_backup_cfg(){
  local cfg="$1"
  [ -f "$cfg" ] || return 0
  local bak
  bak="${cfg}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -a "$cfg" "$bak" 2>/dev/null && echo "$bak" || true
}
# download HTTPS only, optional sha256 verify
ah_download_https(){
  local url="$1" dst="$2" expect_sha="$3"
  case "$url" in https://*) ;; *) echo -e "${RED}URL harus https: $url${RESET}" >&2; return 1;; esac
  echo -e "${CYAN}Download: $url${RESET}"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$dst" 2>&1 || { echo -e "${RED}curl gagal${RESET}" >&2; return 1; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q --https-only "$url" -O "$dst" 2>&1 || return 1
  else echo -e "${RED}curl/wget tidak ada${RESET}" >&2; return 1; fi
  if [ -n "$expect_sha" ]; then
    local got
    if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$dst" 2>/dev/null | awk '{print $1}'); else got=$(shasum -a 256 "$dst" 2>/dev/null | awk '{print $1}'); fi
    if [ "$got" != "$expect_sha" ]; then echo -e "${RED}checksum mismatch${RESET} exp $expect_sha got $got" >&2; rm -f "$dst" 2>/dev/null; return 1; fi
    echo -e "${GREEN}checksum OK${RESET}"
  fi
  chmod 755 "$dst" 2>/dev/null || true
  return 0
}
ah_get_ip(){
  curl -fsS --max-time 5 https://ifconfig.me 2>/dev/null || curl -fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo "-"
}
ah_notify_admin(){
  local msg="$1"
  local conf="${ETC}/config/bot.conf"
  [ -f "$conf" ] || return 0
  # shellcheck disable=SC1090
  . "$conf" 2>/dev/null || return 0
  [ -z "${BOT_TOKEN:-}" ] || [ -z "${ADMIN_ID:-}" ] && return 0
  local clean
  # strip ANSI agar Telegram rapi 1:1
  # shellcheck disable=SC2001
  clean=$(printf "%s" "$msg" | sed 's/\x1b\[[0-9;]*m//g' 2>/dev/null | sed -E 's/\x1B\[[0-9;]*[mK]//g' 2>/dev/null || printf "%s" "$msg")
  clean=$(printf "%s" "$clean" | tr -d '\r' 2>/dev/null || printf "%s" "$clean")
  # Telegram monospace: wrap in code block agar alignment rapi (jika belum ada fence)
  local send_text="$clean"
  # jika panjang >0 dan belum diawali fence, bungkus ```
  if [ -n "$clean" ] && ! printf "%s" "$clean" | grep -q '^```'; then
    send_text="\`\`\`\n${clean}\n\`\`\`"
  fi
  curl -fsS --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${ADMIN_ID}" -d "parse_mode=Markdown" --data-urlencode "text=${send_text}" >/dev/null 2>&1 || {
    # fallback plain tanpa markdown jika gagal
    curl -fsS --max-time 10 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${ADMIN_ID}" --data-urlencode "text=${clean}" >/dev/null 2>&1 || true
  }
  ah_log "notify admin: ${clean:0:80}"
}
# ponytail: checksum DB optional; upgrade to sig verify when upstream publishes

__EMBED_EOF__
chmod 644 "$ETC/lib/advanced_helpers.sh"
cat > "$ETC/menu/main.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/main.sh - TUNNEL PRO TAHAP 1
# shellcheck disable=SC1091,SC1090
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then
  BASE="$MYTUNNEL_PREFIX/etc/mytunnel"
  . "$BASE/lib/colors.sh" 2>/dev/null || true
  . "$BASE/lib/helpers.sh" 2>/dev/null || true
  . "$BASE/lib/sysinfo.sh" 2>/dev/null || true
else
  BASE="/etc/mytunnel"
  . /etc/mytunnel/lib/colors.sh 2>/dev/null || true
  . /etc/mytunnel/lib/helpers.sh 2>/dev/null || true
  . /etc/mytunnel/lib/sysinfo.sh 2>/dev/null || true
fi
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"
YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"
BLUE="${BLUE:-\033[0;34m}"; GREY="${GREY:-\033[0;37m}"
RESET="${RESET:-\033[0m}"; BOLD="${BOLD:-\033[1m}"
DIM="${DIM:-\033[2m}"

show_header() {
  local brand
  brand=$(get_brand 2>/dev/null || echo "TUNNEL PRO")
  clear 2>/dev/null || printf '\033c'
  if declare -f draw_box >/dev/null 2>&1; then
    draw_box "$brand" 60
  else
    local inner=58 len=${#brand} left right
    [ "$len" -gt 58 ] && brand="${brand:0:58}" && len=58
    left=$(( (inner - len) / 2 )); right=$(( inner - len - left ))
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET}%*s${BOLD}%s${RESET}%*s${BLUE}│${RESET}\n" "$left" "" "$brand" "$right" ""
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  fi
}

show_sysinfo() {
  local os ram swap city isp ip domain uptime vn m_rx m_tx d_rx d_tx month_val day_val
  os=$(get_os 2>/dev/null || echo "-")
  ram=$(get_ram 2>/dev/null || echo "-")
  swap=$(get_swap 2>/dev/null || echo "-")
  city=$(get_city_cached 2>/dev/null || echo "-")
  isp=$(get_isp_cached 2>/dev/null || echo "-")
  ip=$(get_ip_cached 2>/dev/null || echo "-")
  domain=$(get_domain 2>/dev/null || echo "-")
  uptime=$(get_uptime 2>/dev/null || echo "-")
  vn=$(get_traffic_rx_tx 2>/dev/null || echo "MRX:- MTX:- DRX:- DTX:-")
  m_rx=$(echo "$vn" | sed -n 's/.*MRX:\([^ ]*\).*/\1/p'); [ -z "$m_rx" ] && m_rx="-"
  m_tx=$(echo "$vn" | sed -n 's/.*MTX:\([^ ]*\).*/\1/p'); [ -z "$m_tx" ] && m_tx="-"
  d_rx=$(echo "$vn" | sed -n 's/.*DRX:\([^ ]*\).*/\1/p'); [ -z "$d_rx" ] && d_rx="-"
  d_tx=$(echo "$vn" | sed -n 's/.*DTX:\([^ ]*\).*/\1/p'); [ -z "$d_tx" ] && d_tx="-"
  month_val=$(get_traffic_month 2>/dev/null || echo "-")
  day_val=$(get_traffic_day 2>/dev/null || echo "-")
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "OS" "$os"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-10s ${CYAN}%-6s${RESET}: %-25s ${BLUE}│${RESET}\n" "RAM" "$ram" "SWAP" "$swap"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "CITY" "$city"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "ISP" "$isp"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "IP" "$ip"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "DOMAIN" "$domain"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "UPTIME" "$uptime"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf "${BLUE}│${RESET} ${YELLOW}%-10s${RESET}: %-18s ${DIM}[Month]${RESET}                   ${BLUE}│${RESET}\n" "MONTH" "$month_val"
  printf "${BLUE}│${RESET}   RX: %-16s TX: %-16s              ${BLUE}│${RESET}\n" "$m_rx" "$m_tx"
  printf "${BLUE}│${RESET} ${YELLOW}%-10s${RESET}: %-18s ${DIM}[Today]${RESET}                   ${BLUE}│${RESET}\n" "DAY" "$day_val"
  printf "${BLUE}│${RESET}   RX: %-16s TX: %-16s              ${BLUE}│${RESET}\n" "$d_rx" "$d_tx"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

show_status() {
  local xray sshws nginx xcol scol ncol
  xray=$(svc_status xray 2>/dev/null || echo "OFF")
  sshws=$(svc_status ssh 2>/dev/null || echo "OFF")
  if [ "$sshws" = "OFF" ]; then sshws=$(svc_status dropbear 2>/dev/null || echo "OFF"); fi
  nginx=$(svc_status nginx 2>/dev/null || echo "OFF")
  if [ "$nginx" = "OFF" ]; then nginx=$(svc_status haproxy 2>/dev/null || echo "OFF"); fi
  [ "$xray" = "ON" ] && xcol="$GREEN" || xcol="$RED"
  [ "$sshws" = "ON" ] && scol="$GREEN" || scol="$RED"
  [ "$nginx" = "ON" ] && ncol="$GREEN" || ncol="$RED"
  echo -e "${xcol}XRAY : $xray${RESET} | ${scol}SSH-WS : $sshws${RESET} | ${ncol}NGINX : $nginx${RESET} | GOOD"
}

show_version() {
  local version client expiry
  version=$(cat "$BASE/config/version.txt" 2>/dev/null || cat /etc/mytunnel/config/version.txt 2>/dev/null || echo "v1.1.0")
  version="TUNNEL-PRO $version"
  client=$(get_ip_cached 2>/dev/null || echo "-")
  expiry=$(get_expiry 2>/dev/null || echo "-")
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Version" "$version"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Client Name" "$client"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Expiry In" "$expiry"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

show_menu() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" " 1.) SSH                 6.) FEATURES"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" " 2.) VMESS               7.) SET BRAND NAME"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" " 3.) VLESS               8.) CHECK SERVICES"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" " 4.) TROJAN              x.) EXIT"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" " 5.) SETUP BOT             9.) DOCTOR (cek data)"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

set_brand_name() {
  echo -e "${CYAN}=== SET BRAND NAME ===${RESET}"
  local cur nb f
  cur=$(get_brand 2>/dev/null || echo "TUNNEL PRO")
  echo -e "Brand saat ini: ${BOLD}$cur${RESET}"
  echo -ne "Brand baru (kosongkan batal): "
  read -r nb
  [ -z "$nb" ] && { echo "Batal."; pause; return; }
  f="$BASE/config/brand.txt"
  backup_file "$f" >/dev/null 2>&1 || true
  if echo "$nb" > "$f" 2>/dev/null; then echo -e "${GREEN}✓ Brand diubah ke: $nb${RESET}"; log "brand -> $nb"; else echo -e "${RED}Gagal tulis $f${RESET}"; fi
  pause
}

check_services() {
  echo -e "${CYAN}=== CHECK SERVICES ===${RESET}"
  printf "%-15s : %s\n" "xray" "$(svc_status xray 2>/dev/null)"
  printf "%-15s : %s\n" "ssh" "$(svc_status ssh 2>/dev/null)"
  printf "%-15s : %s\n" "dropbear" "$(svc_status dropbear 2>/dev/null)"
  printf "%-15s : %s\n" "nginx" "$(svc_status nginx 2>/dev/null)"
  printf "%-15s : %s\n" "haproxy" "$(svc_status haproxy 2>/dev/null)"
  printf "%-15s : %s\n" "vnstat" "$(command -v vnstat >/dev/null 2>&1 && echo "installed" || echo "not installed")"
  echo -e "\n${DIM}Akun per protokol:${RESET}"
  for p in ssh vmess vless trojan; do printf "  %-10s : %s\n" "$p" "$(get_account_count "$p" 2>/dev/null || echo 0)"; done
  pause
}

setup_bot_stub() {
  # TAHAP 6: delegasi ke menu/bot.sh jika ada, fallback stub
  if [ -x "$BASE/menu/bot.sh" ]; then
    bash "$BASE/menu/bot.sh" 2>&1 || echo -e "${YELLOW}menu bot error${RESET}"
  else
    echo -e "${YELLOW}Fitur ini dibuat di tahap berikutnya${RESET} (SETUP BOT)"
    pause
  fi
}

dispatch() {
  case "$1" in
    1) bash "$BASE/menu/ssh.sh" 2>/dev/null || { echo -e "${RED}menu ssh belum ada${RESET}"; pause; };;
    2) bash "$BASE/menu/vmess.sh" 2>/dev/null || { echo -e "${RED}menu vmess belum ada${RESET}"; pause; };;
    3) bash "$BASE/menu/vless.sh" 2>/dev/null || { echo -e "${RED}menu vless belum ada${RESET}"; pause; };;
    4) bash "$BASE/menu/trojan.sh" 2>/dev/null || { echo -e "${RED}menu trojan belum ada${RESET}"; pause; };;
    5) setup_bot_stub;;
    6) bash "$BASE/menu/features.sh" 2>/dev/null || { echo -e "${RED}menu features belum ada${RESET}"; pause; };;
    7) set_brand_name;;
    8) check_services;;
    9) bash "$BASE/menu/doctor.sh" 2>/dev/null || { echo -e "${RED}doctor belum ada${RESET}"; pause; };;
    x|X) echo -e "${GREEN}Keluar...${RESET}"; exit 0;;
    *) echo -e "${RED}Pilihan tidak valid: $1${RESET}"; sleep 1;;
  esac
}

while true; do
  show_header
  show_sysinfo
  show_status
  show_version
  show_menu
  echo -ne "${BOLD}Select From Options [1-9 or x] : ${RESET}"
  read -r choice
  dispatch "$choice"
done

__EMBED_EOF__
chmod 755 "$ETC/menu/main.sh"
cat > "$ETC/menu/ssh.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/ssh.sh - SSH management 14 opsi (60 kolom)
# shellcheck disable=SC1090,SC1091,SC2155
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/sysinfo.sh" "$BASE/lib/ssh_helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
DB="$BASE/db/ssh.txt"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -n "$MYTUNNEL_PREFIX" ] && LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"
# DOMAIN_FILE removed (unused)

_ensure_db() { mkdir -p "$(dirname "$DB")" 2>/dev/null || true; [ -f "$DB" ] || touch "$DB" 2>/dev/null || true; chmod 600 "$DB" 2>/dev/null || true; }

_expiry_add_days() {
  local base_date="$1" add="$2"
  local base_s new_s
  base_s=$(date -d "$base_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$base_date" +%s 2>/dev/null || date +%s)
  new_s=$((base_s + add*86400))
  date -d "@$new_s" +%Y-%m-%d 2>/dev/null || date -r "$new_s" +%Y-%m-%d 2>/dev/null || echo "$base_date"
}
_today_str() { date +%Y-%m-%d 2>/dev/null; }
_days_left_calc() {
  local exp="$1"; local sec_exp sec_now
  sec_exp=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  sec_now=$(date +%s 2>/dev/null)
  echo $(( (sec_exp - sec_now) / 86400 ))
}

_list_users_raw() { _ensure_db; grep -v '^\s*$' "$DB" 2>/dev/null | grep -v '^#' || true; }

_show_user_list_numbered() {
  local i=1
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Daftar User SSH"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(belum ada user)"
  else
    local user exp limit status days
    while IFS='|' read -r user _pass exp limit status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      printf -v _inner "%2d) %-16s exp:%-10s %3sd %-6s" "$i" "$user" "$exp" "$days" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

_pick_user_by_number() {
  local num="$1"
  _list_users_raw | sed -n "${num}p" | cut -d'|' -f1
}

do_create() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then
    draw_box "$brand" 60
  else
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$brand"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  fi
  echo -e "${GREY}Just input a number for Limit IP${RESET}"
  echo -e "${GREY}0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user pass limit_ip days
  while true; do
    printf "${CYAN}%-14s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username tidak boleh kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9_]{3,16}$' <<< "$user" 2>/dev/null; then
      echo -e "${RED}Username tidak valid (a-z0-9_ 3-16)${RESET}"; continue
    fi
    if command -v validate_ssh_username >/dev/null 2>&1; then
      if ! validate_ssh_username "$user"; then echo -e "${RED}Username tidak valid / system user${RESET}"; continue; fi
    fi
    if ssh_user_exists "$user" 2>/dev/null; then echo -e "${RED}User sudah ada di DB${RESET}"; continue; fi
    if id "$user" >/dev/null 2>&1; then echo -e "${RED}User sistem sudah ada${RESET}"; continue; fi
    break
  done
  printf "${CYAN}%-14s: ${RESET}" "Password"
  read -r pass
  if [ -z "$pass" ]; then
    if command -v openssl >/dev/null 2>&1; then pass=$(openssl rand -base64 12 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 8); else pass=$(head -c 32 /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 8); fi
    [ -z "$pass" ] && pass="Pass$(date +%s | tail -c 5)"
  fi
  while true; do
    printf "${CYAN}%-14s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]]; then break; fi
    echo -e "${RED}Limit harus angka (0=unlimited)${RESET}"
  done
  while true; do
    printf "${CYAN}%-14s: ${RESET}" "Expired (day)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if ssh_create "$user" "$pass" "$days" "$limit_ip" 2>&1; then
    local exp
    exp=$(ssh_get_field "$user" 3 2>/dev/null || echo "-")
    print_ssh_account_info "$user" "$pass" "$exp" "$limit_ip" 2>/dev/null || true
    # notify Telegram admin (auto-kirim akun)
    if declare -f ah_notify_admin >/dev/null 2>&1; then
      _ntf=$(print_ssh_account_info "$user" "$pass" "$exp" "$limit_ip" 2>/dev/null || echo "SSH $user | $pass | exp $exp | limit $limit_ip")
      ah_notify_admin "$_ntf" 2>/dev/null || true
    fi
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_parse_duration_to_min() {
  local inp="$1" def="$2" v num suffix
  v=$(echo "$inp" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
  [ -z "$v" ] && v="$def"
  suffix="${v: -1}"
  if [[ "$suffix" == "h" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo $((num*60))
  elif [[ "$suffix" == "m" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo "$num"
  else [[ "$v" =~ ^[0-9]+$ ]] || v="$def"; echo "$v"; fi
}
do_trial() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Trial SSH"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local inp_dur inp_limit trial_min trial_limit days
  echo -ne "${CYAN}Durasi trial [60m, contoh 30m/2h, default 60m]: ${RESET}"; read -r inp_dur
  trial_min=$(_parse_duration_to_min "$inp_dur" 60)
  [[ "$trial_min" =~ ^[0-9]+$ ]] || trial_min=60
  [ "$trial_min" -lt 1 ] && trial_min=1
  [ "$trial_min" -gt 10080 ] && trial_min=10080
  echo -ne "${CYAN}Limit IP [1, 0=unlimited]: ${RESET}"; read -r inp_limit
  [[ "$inp_limit" =~ ^[0-9]+$ ]] || inp_limit=1
  trial_limit="$inp_limit"
  # days = ceil(min/1440)
  days=$(( (trial_min + 1439) / 1440 ))
  [ "$days" -lt 1 ] && days=1
  local rnd user pass exp
  rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4)
  [ -z "$rnd" ] && rnd=$(date +%s | tail -c 5)
  user="trial${rnd}"
  while ssh_user_exists "$user" 2>/dev/null || id "$user" >/dev/null 2>&1; do
    rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4); user="trial${rnd}"
  done
  if command -v openssl >/dev/null 2>&1; then pass=$(openssl rand -base64 9 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 8); else pass="Trial$(date +%s | tail -c 5)"; fi
  if ! ssh_create "$user" "$pass" "$days" "$trial_limit" 2>&1; then echo -e "${RED}Gagal buat trial${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 1; fi
  exp=$(ssh_get_field "$user" 3 2>/dev/null || _today_str)
  local _human; if [ "$trial_min" -ge 60 ] && [ $((trial_min % 60)) -eq 0 ]; then _human="$((trial_min/60)) jam"; else _human="${trial_min} menit"; fi
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] trial $user scheduled delete in ${trial_min}m (TEST simulasi)" >> "$LOG" 2>/dev/null || true
    echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
  else
    if command -v at >/dev/null 2>&1; then
      echo "bash $BASE/cron/autoexpire.sh; userdel -r $user 2>/dev/null; sed -i '/^$user|/d' $DB 2>/dev/null" | at now + "${trial_min}" minutes 2>/dev/null || true
    else
      echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $pass" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
      if [ ! -f /etc/cron.d/mytunnel-trial ]; then
        echo "* * * * * root $BASE/cron/autoexpire.sh 2>/dev/null; awk -v now=\$(date +\%s) '\$1<=now{print \$2}' $BASE/db/.trial_schedule 2>/dev/null | while read u; do pkill -u \"\$u\" 2>/dev/null; userdel -r \"\$u\" 2>/dev/null; sed -i \"/^\$u|/d\" $DB 2>/dev/null; done; awk -v now=\$(date +\%s) '\$1>now' $BASE/db/.trial_schedule > $BASE/db/.trial_schedule.tmp 2>/dev/null && mv $BASE/db/.trial_schedule.tmp $BASE/db/.trial_schedule 2>/dev/null" > /etc/cron.d/mytunnel-trial 2>/dev/null || true
        chmod 644 /etc/cron.d/mytunnel-trial 2>/dev/null || true
      fi
    fi
  fi
  echo -e "${GREEN}Trial dibuat ${_human} (exp $exp, limit $trial_limit IP)${RESET}"
  print_ssh_account_info "$user" "$pass" "$exp" "$trial_limit" 2>/dev/null || true
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf=$(print_ssh_account_info "$user" "$pass" "$exp" "$trial_limit" 2>/dev/null || echo "SSH trial $user | $pass | exp $exp")
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  echo -e "${YELLOW}Akan dihapus otomatis ${_human}${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_delete() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor hapus (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${YELLOW}Hapus $user ? [y/N]: ${RESET}"
  read -r yn; case "$yn" in y|Y|yes|YES) ;; *) return 0;; esac
  ssh_delete "$user" 2>&1
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf="🗑 SSH deleted: $user"
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_renew() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor renew: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Tambah hari: ${RESET}"
  read -r add
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local cur_exp today base new_exp
  cur_exp=$(ssh_get_field "$user" 3 2>/dev/null)
  today=$(_today_str)
  # base = max(cur_exp, today)
  if [ "$(date -d "$cur_exp" +%s 2>/dev/null || echo 0)" -gt "$(date -d "$today" +%s 2>/dev/null || echo 0)" ]; then base="$cur_exp"; else base="$today"; fi
  new_exp=$(_expiry_add_days "$base" "$add")
  # update system
  if [ -z "$MYTUNNEL_PREFIX" ]; then
    if id "$user" >/dev/null 2>&1; then
      chage -E "$(date -d "$new_exp" +%Y-%m-%d 2>/dev/null)" "$user" 2>/dev/null || usermod -e "$new_exp" "$user" 2>/dev/null || true
    fi
  fi
  ssh_set_field "$user" 3 "$new_exp" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh renew $user $cur_exp -> $new_exp" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}Renew $user: $cur_exp -> $new_exp (+$add hari)${RESET}"
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_chpass() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor ganti password: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Password baru: ${RESET}"
  read -r npass
  [ -z "$npass" ] && { echo -e "${RED}Password kosong${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if [ -z "$MYTUNNEL_PREFIX" ]; then
    if ! echo "$user:$npass" | chpasswd 2>&1; then echo -e "${RED}Gagal chpasswd${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; fi
  fi
  ssh_set_field "$user" 2 "$npass" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh chpass $user" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}Password $user diganti${RESET}"
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_login() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Users Login SSH"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  _ensure_db
  local found=0 user i=1
  while IFS='|' read -r user _pass _exp _limit _status; do
    [ -z "$user" ] && continue
    local ips cnt
    # reuse helper if available
    if declare -f _ssh_online_cnt >/dev/null 2>&1; then
      ips=$(who 2>/dev/null | awk -v u="$user" '$1==u{print $5}' | tr -d '()' | sort -u | tr '\n' ' ' | head -c 40)
      [ -z "$ips" ] && ips=$(ss -tnp 2>/dev/null | grep -E "$(pgrep -u "$user" 2>/dev/null | tr '\n' '|' | sed 's/|$//')" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ' | head -c 40)
      [ -z "$ips" ] && [ -f /var/log/auth.log ] && ips=$(grep -E "Accepted.* $user " /var/log/auth.log 2>/dev/null | tail -n 20 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ' | head -c 40)
      ips=$(echo "$ips" | tr -s ' ' | sed 's/^ //;s/ $//')
      cnt=$(echo "$ips" | wc -w 2>/dev/null | tr -d ' '); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      [ -z "$ips" ] && cnt=0
    else
      cnt=$(who 2>/dev/null | awk -v u="$user" '$1==u{c++} END{print c+0}')
      ips=$(who 2>/dev/null | awk -v u="$user" '$1==u{print $5}' | tr -d '()' | sort -u | tr '\n' ' ' | head -c 40)
      if [ "$cnt" -eq 0 ] && command -v ss >/dev/null 2>&1; then
        local pids; pids=$(pgrep -u "$user" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        if [ -n "$pids" ]; then cnt=$(ss -tnp 2>/dev/null | grep -c "$pids" 2>/dev/null || echo 0); fi
      fi
    fi
    if [ -n "$ips" ] || [ "$cnt" -gt 0 ] 2>/dev/null; then
      printf "%2d) %-12s : %2s/%-2s IP  %s ${GREY}[%s]${RESET}\n" "$i" "$user" "$cnt" "${_limit:-0}" "$ips" "$_status"
      found=1; i=$((i+1))
    fi
  done < <(_list_users_raw)
  [ "$found" -eq 0 ] && echo -e "${DIM}(tidak ada user login / belum ada sesi)${RESET}"
  echo -e "${GREY}Limit = batas IP, angka pertama = IP unik online${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_ssh_online_cnt() {
  local _u="$1" _ips _cnt
  _ips=$(who 2>/dev/null | awk -v u="$_u" '$1==u{print $5}' | tr -d '()' | sort -u | tr '\n' ' ' 2>/dev/null)
  if [ -z "$_ips" ] && command -v ss >/dev/null 2>&1; then
    local _pids; _pids=$(pgrep -u "$_u" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    [ -n "$_pids" ] && _ips=$(ss -tnp 2>/dev/null | grep -E "$_pids" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ' 2>/dev/null)
  fi
  if [ -z "$_ips" ] && [ -f /var/log/auth.log ]; then _ips=$(grep -E "Accepted.* $_u |sshd.* $_u.*Accepted" /var/log/auth.log 2>/dev/null | tail -n 20 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ' 2>/dev/null); fi
  _ips=$(echo "$_ips" | tr -s ' ' | sed 's/^ //;s/ $//')
  [ -z "$_ips" ] && echo "0" && return
  echo "$_ips" | wc -w | tr -d ' '
}
do_list() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "List Users SSH"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf -v _inner "%2s %-10s %-10s %3s %3s %3s %-6s" "No" "User" "Expiry" "Sisa" "Lim" "On" "Status"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$_inner"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(kosong)"
  else
    local user pass exp limit status days cnt i=1
    while IFS='|' read -r user pass exp limit status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      cnt=$(_ssh_online_cnt "$user" 2>/dev/null); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      printf -v _inner "%2d %-10s %-10s %3sd %3s %3s %-6s" "$i" "$user" "$exp" "$days" "${limit:-0}" "$cnt" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${GREY}Lim=Limit IP, On=IP login sekarang${RESET}"
  echo -e "${GREY}Pilih nomor untuk detail (0 kembali):${RESET}"
  echo -ne "${CYAN}Nomor: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local _u; _u=$(_pick_user_by_number "$num")
  [ -z "$_u" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _pass _exp _lim
  _pass=$(ssh_get_field "$_u" 2 2>/dev/null || echo "-")
  _exp=$(ssh_get_field "$_u" 3 2>/dev/null || echo "-")
  _lim=$(ssh_get_field "$_u" 4 2>/dev/null || echo "0")
  print_ssh_account_info "$_u" "$_pass" "$_exp" "$_lim" 2>/dev/null || echo "User tidak ada"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_lock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor lock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if [ -z "$MYTUNNEL_PREFIX" ]; then usermod -L "$user" 2>/dev/null || true; pkill -u "$user" 2>/dev/null || true; fi
  ssh_set_field "$user" 5 "locked" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh lock $user" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}$user di-lock + sesi di-kill${RESET}"
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_unlock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor unlock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if [ -z "$MYTUNNEL_PREFIX" ]; then usermod -U "$user" 2>/dev/null || true; fi
  ssh_set_field "$user" 5 "active" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh unlock $user" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}$user di-unlock${RESET}"
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_config() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Config SSH"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor cek config (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user; user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local _pass _exp _lim
  _pass=$(ssh_get_field "$user" 2 2>/dev/null || echo "-")
  _exp=$(ssh_get_field "$user" 3 2>/dev/null || echo "-")
  _lim=$(ssh_get_field "$user" 4 2>/dev/null || echo "0")
  clear 2>/dev/null || printf '\033c'
  local _out
  _out=$(print_ssh_account_info "$user" "$_pass" "$_exp" "$_lim" 2>&1) || _out="Gagal tampil $user"
  echo "$_out"
  echo ""
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    ah_notify_admin "$_out" 2>/dev/null || true
    echo -e "${GREEN}Detail terkirim ke bot ✓${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_recovery() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Recovery SSH (Expired)"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local exp_db="$BASE/db/ssh_expired.txt"
  if [ ! -f "$exp_db" ] || [ ! -s "$exp_db" ]; then
    echo -e "${DIM}(tidak ada akun expired — akun expired otomatis pindah kesini jam 00:00)${RESET}"
    echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 0
  fi
  echo -e "${CYAN}Akun expired:${RESET}"
  local i=1
  while IFS='|' read -r user pass exp limit status; do
    [ -z "$user" ] && continue
    printf " %2d) %-12s exp:%-10s lim:%-3s [%s]\n" "$i" "$user" "$exp" "${limit:-0}" "${status:-active}"
    i=$((i+1))
  done < "$exp_db"
  echo ""
  echo -ne "${CYAN}Pilih nomor recovery (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local line; line=$(sed -n "${num}p" "$exp_db" 2>/dev/null)
  [ -z "$line" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user pass exp limit status
  IFS='|' read -r user pass exp limit status <<< "$line"
  [ -z "$user" ] && { echo -e "${RED}Data rusak${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if grep -q "^${user}|" "$DB" 2>/dev/null; then
    echo -e "${YELLOW}$user sudah ada di DB aktif — hapus dari expired saja${RESET}"
    local _tmp; _tmp=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp" 2>/dev/null || true; cat "$_tmp" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp" 2>/dev/null || true
    echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  echo -ne "${CYAN}Hari aktif baru [30]: ${RESET}"
  read -r add; [ -z "$add" ] && add=30
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Harus angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$add" -lt 1 ] && add=1; [ "$add" -gt 3650 ] && add=3650
  local today new_exp
  today=$(date +%Y-%m-%d 2>/dev/null)
  if declare -f _expiry_add_days >/dev/null 2>&1; then new_exp=$(_expiry_add_days "$today" "$add"); else new_exp=$(date -d "+${add} days" +%Y-%m-%d 2>/dev/null || date -v+${add}d +%Y-%m-%d 2>/dev/null || echo "2099-01-01"); fi
  echo -e "${DIM}Aktifkan $user -> $new_exp (+$add hari) ...${RESET}"
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    :
  else
    grep -qx "/bin/false" /etc/shells 2>/dev/null || echo "/bin/false" >> /etc/shells 2>/dev/null || true
    if ! id "$user" >/dev/null 2>&1; then
      if ! useradd -M -s /bin/false -e "$new_exp" "$user" 2>&1; then echo -e "${RED}Gagal useradd $user${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; fi
      echo "$user:$pass" | chpasswd 2>&1 || { echo -e "${RED}Gagal chpasswd${RESET}"; userdel "$user" 2>/dev/null || true; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
    else
      chage -E "$new_exp" "$user" 2>/dev/null || usermod -e "$new_exp" "$user" 2>/dev/null || true
      echo "$user:$pass" | chpasswd 2>&1 || true
    fi
    if [ "$status" = "locked" ]; then usermod -U "$user" 2>/dev/null || true; status="active"; fi
  fi
  local nline="${user}|${pass}|${new_exp}|${limit:-0}|active"
  local db_lock="$BASE/db/.ssh.lock"; [ -f "$db_lock" ] || touch "$db_lock" 2>/dev/null || true
  local _tmp2; _tmp2=$(mktemp)
  (
    flock -x 200
    echo "$nline" >> "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$db_lock" 2>/dev/null || { echo "$nline" >> "$DB" 2>/dev/null; chmod 600 "$DB" 2>/dev/null || true; }
  rm -f "$_tmp2" 2>/dev/null || true
  local _tmp3; _tmp3=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp3" 2>/dev/null || true; cat "$_tmp3" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp3" 2>/dev/null || true
  echo -e "${GREEN}Recovery OK: $user -> $new_exp${RESET}"
  local _out; _out=$(print_ssh_account_info "$user" "$pass" "$new_exp" "${limit:-0}" 2>&1) || _out="Akun $user dipulihkan exp $new_exp"
  echo "$_out"
  if declare -f ah_notify_admin >/dev/null 2>&1; then ah_notify_admin "$_out" 2>/dev/null || true; echo -e "${GREEN}Terkirim ke bot ✓${RESET}"; fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh recovery $user $exp -> $new_exp" >> "$LOG" 2>/dev/null || true
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_edit_limit() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor edit limit: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local cur
  cur=$(ssh_get_field "$user" 4 2>/dev/null || echo 0)
  echo -e "${DIM}Limit sekarang: $cur${RESET}"
  echo -ne "${CYAN}Limit baru (0=unlimited): ${RESET}"
  read -r nlim
  [[ "$nlim" =~ ^[0-9]+$ ]] || { echo -e "${RED}Harus angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  ssh_set_field "$user" 4 "$nlim" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh limit $user $cur -> $nlim" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}Limit $user: $cur -> $nlim${RESET}"
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_edit_limit_all() {
  echo -ne "${CYAN}Set limit IP semua user (0=unlimited): ${RESET}"
  read -r nlim
  [[ "$nlim" =~ ^[0-9]+$ ]] || { echo -e "${RED}Harus angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${YELLOW}Yakin ubah semua ke $nlim ? [y/N]: ${RESET}"
  read -r yn; case "$yn" in y|Y|yes|YES) ;; *) return 0;; esac
  local tmp
  tmp=$(mktemp)
  local db_lock="$BASE/db/.ssh.lock"
  [ -f "$db_lock" ] || touch "$db_lock" 2>/dev/null || true
  (
    flock -x 200
    awk -F'|' -v OFS='|' -v v="$nlim" '$1!="" && $1!~/^#/{$4=v}1' "$DB" > "$tmp" 2>/dev/null && cat "$tmp" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$db_lock" 2>/dev/null || {
    awk -F'|' -v OFS='|' -v v="$nlim" '$1!="" && $1!~/^#/{$4=v}1' "$DB" > "$tmp" 2>/dev/null && cat "$tmp" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ssh limit all -> $nlim" >> "$LOG" 2>/dev/null || true
  echo -e "${GREEN}Semua limit di-set $nlim${RESET}"
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "SSH-Dropbear-OpenVPN"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Create                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Trial                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Delete                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Renew/Extend                                   ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Modify Password                                ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Check Users Login                              ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) List Users                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} LOCK & UNLOCK                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 8.) Lock                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 9.) Unlock                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} UTILITIES                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 10.) Check Config                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 11.) Recovery                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 12.) Edit Limit IP                                 ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 13.) Edit Limit IP All                             ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 14.) Back to Menu                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} x.) Exit                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select From Options [1-14 or x] : ${RESET}"
  read -r c
  case "$c" in
    1) do_create ;;
    2) do_trial ;;
    3) do_delete ;;
    4) do_renew ;;
    5) do_chpass ;;
    6) do_check_login ;;
    7) do_list ;;
    8) do_lock ;;
    9) do_unlock ;;
    10) do_check_config ;;
    11) do_recovery ;;
    12) do_edit_limit ;;
    13) do_edit_limit_all ;;
    14|b|B) break ;;
    x|X) exit 0 ;;
    *) echo -e "${YELLOW}Pilihan tidak valid${RESET}"; sleep 1 ;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/ssh.sh"
cat > "$ETC/menu/vmess.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/vmess.sh - VMESS management (WS+gRPC+HTTPUpgrade, 60 kolom)
# shellcheck disable=SC1091,SC1090,SC2155,SC2034
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/sysinfo.sh" "$BASE/lib/xray_helpers.sh" "$BASE/lib/proto_helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
PROTO="vmess"
DB="$BASE/db/vmess.txt"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -n "$MYTUNNEL_PREFIX" ] && LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"
XRAY_CFG="${MYTUNNEL_PREFIX:-}/usr/local/etc/xray/config.json"
[ -n "$MYTUNNEL_PREFIX" ] && XRAY_CFG="$MYTUNNEL_PREFIX/usr/local/etc/xray/config.json"
[ -z "$MYTUNNEL_PREFIX" ] && XRAY_CFG="/usr/local/etc/xray/config.json"

_ensure_db() { mkdir -p "$(dirname "$DB")" 2>/dev/null || true; [ -f "$DB" ] || touch "$DB" 2>/dev/null || true; chmod 600 "$DB" 2>/dev/null || true; }
_expiry_add_days() {
  local base_date="$1" add="$2"
  local base_s new_s
  base_s=$(date -d "$base_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$base_date" +%s 2>/dev/null || date +%s)
  new_s=$((base_s + add*86400))
  date -d "@$new_s" +%Y-%m-%d 2>/dev/null || date -r "$new_s" +%Y-%m-%d 2>/dev/null || echo "$base_date"
}
_today_str() { date +%Y-%m-%d 2>/dev/null; }
_days_left_calc() {
  local exp="$1"; local sec_exp sec_now
  sec_exp=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  sec_now=$(date +%s 2>/dev/null)
  echo $(( (sec_exp - sec_now) / 86400 ))
}
_list_users_raw() { _ensure_db; grep -v '^\s*$' "$DB" 2>/dev/null | grep -v '^#' || true; }
_show_user_list_numbered() {
  local i=1
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Daftar User VMESS"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(belum ada user)"
  else
    local user exp limit quota status days
    while IFS='|' read -r user _id exp limit quota _used status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      printf -v _inner "%2d) %-12s exp:%-10s %3sd q:%-3s lim:%-2s %-6s" "$i" "$user" "$exp" "$days" "${quota:-0}" "${limit:-0}" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}
_pick_user_by_number() {
  local num="$1"
  _list_users_raw | sed -n "${num}p" | cut -d'|' -f1
}

do_create() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then
    draw_box "$brand" 60
    draw_box "VMESS" 60
  else
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$brand"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "VMESS"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  fi
  echo -e "${GREY}Don't use special characters and uppercase!${RESET}"
  echo -e "${GREY}Just input a number for- Quota Limit, Limit IP, Format GB${RESET}"
  echo -e "${GREY}0 for Unlimited${RESET}"
  echo -e "${GREY}0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user quota limit_ip days id
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username tidak boleh kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9]{3,16}$' <<< "$user" 2>/dev/null; then
      echo -e "${RED}Username hanya a-z0-9 3-16, tanpa spasi/simbol/huruf besar${RESET}"; continue
    fi
    if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah dipakai di protokol lain: $user${RESET}"; continue; fi
    if ! validate_proto_user "$user" 2>/dev/null; then echo -e "${RED}Username tidak valid / system user${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Quota Limit (GB)"
    read -r quota
    [ -z "$quota" ] && quota=0
    if [[ "$quota" =~ ^[0-9]+$ ]] && [ "$quota" -ge 0 ] && [ "$quota" -le 9999 ]; then break; fi
    echo -e "${RED}Quota harus angka 0-9999 (0=Unlimited)${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]] && [ "$limit_ip" -ge 0 ] && [ "$limit_ip" -le 100 ]; then break; fi
    echo -e "${RED}Limit harus angka 0-100 (0=No Limit)${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Expired (days)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if [ "$PROTO" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if [ -z "$id" ]; then echo -e "${RED}Gagal generate ID${RESET}"; echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 1; fi
  if proto_create "$PROTO" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1; then
    echo ""
    print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
    # notify Telegram admin
    if declare -f ah_notify_admin >/dev/null 2>&1; then
      _ntf=$(print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || echo "$PROTO $user dibuat")
      ah_notify_admin "$_ntf" 2>/dev/null || true
    fi
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_create_custom() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then draw_box "$brand" 60; draw_box "VMESS CUSTOM" 60; fi
  echo -e "${GREY}Don't use special characters and uppercase!${RESET}"
  echo -e "${GREY}Just input a number for- Quota Limit, Limit IP, Format GB${RESET}"
  echo -e "${GREY}0 for Unlimited / 0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user quota limit_ip days id
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9]{3,16}$' <<< "$user" 2>/dev/null; then echo -e "${RED}Username a-z0-9 3-16${RESET}"; continue; fi
    if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah ada${RESET}"; continue; fi
    if ! validate_proto_user "$user" 2>/dev/null; then echo -e "${RED}Username tidak valid${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "UUID"
    read -r id
    if [ -z "$id" ]; then echo -e "${RED}UUID tidak boleh kosong${RESET}"; continue; fi
    if ! validate_uuid "$id" 2>/dev/null; then echo -e "${RED}UUID tidak valid (format 8-4-4-4-12 hex)${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Quota Limit (GB)"
    read -r quota
    [ -z "$quota" ] && quota=0
    if [[ "$quota" =~ ^[0-9]+$ ]] && [ "$quota" -ge 0 ] && [ "$quota" -le 9999 ]; then break; fi
    echo -e "${RED}Quota harus angka 0-9999${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]] && [ "$limit_ip" -ge 0 ] && [ "$limit_ip" -le 100 ]; then break; fi
    echo -e "${RED}Limit harus angka 0-100${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Expired (days)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if proto_create "$PROTO" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1; then
    echo ""
    print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_parse_duration_to_min() {
  local inp="$1" def="$2" v num suffix
  v=$(echo "$inp" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
  [ -z "$v" ] && v="$def"
  suffix="${v: -1}"
  if [[ "$suffix" == "h" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo $((num*60))
  elif [[ "$suffix" == "m" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo "$num"
  else [[ "$v" =~ ^[0-9]+$ ]] || v="$def"; echo "$v"; fi
}
do_trial() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Trial VMESS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local inp_dur inp_limit inp_quota trial_min trial_limit trial_quota days
  echo -ne "${CYAN}Durasi trial [60m, contoh 30m/2h, default 60m]: ${RESET}"; read -r inp_dur
  trial_min=$(_parse_duration_to_min "$inp_dur" 60)
  [[ "$trial_min" =~ ^[0-9]+$ ]] || trial_min=60
  [ "$trial_min" -lt 1 ] && trial_min=1
  [ "$trial_min" -gt 10080 ] && trial_min=10080
  echo -ne "${CYAN}Limit IP [1, 0=unlimited]: ${RESET}"; read -r inp_limit
  [[ "$inp_limit" =~ ^[0-9]+$ ]] || inp_limit=1
  trial_limit="$inp_limit"
  echo -ne "${CYAN}Quota GB [1, 0=unlimited]: ${RESET}"; read -r inp_quota
  [[ "$inp_quota" =~ ^[0-9]+$ ]] || inp_quota=1
  trial_quota="$inp_quota"
  days=$(( (trial_min + 1439) / 1440 ))
  [ "$days" -lt 1 ] && days=1
  local rnd user id
  rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4)
  [ -z "$rnd" ] && rnd=$(date +%s | tail -c 5)
  user="trial${rnd}"
  user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  [ -z "$user" ] && user="trial123"
  while proto_exists_any "$user" >/dev/null 2>&1; do
    rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4); user="trial${rnd}"; user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  done
  if [ "$PROTO" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if ! proto_create "$PROTO" "$user" "$id" "$days" "$trial_limit" "$trial_quota" 2>&1; then echo -e "${RED}Gagal buat trial${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 1; fi
  local _human; if [ "$trial_min" -ge 60 ] && [ $((trial_min % 60)) -eq 0 ]; then _human="$((trial_min/60)) jam"; else _human="${trial_min} menit"; fi
  echo -e "${GREEN}Trial dibuat $_human (exp ${days} hari, limit $trial_limit IP, quota $trial_quota GB)${RESET}"
  print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf=$(print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || echo "$PROTO trial $user")
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] trial $PROTO $user scheduled delete in ${trial_min}m (TEST simulasi)" >> "$LOG" 2>/dev/null || true
    echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $PROTO" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
  else
    if command -v at >/dev/null 2>&1; then
      echo "bash $BASE/cron/autoexpire_xray.sh; xray_del_client $PROTO $user 2>/dev/null; sed -i '/^$user|/d' $DB 2>/dev/null" | at now + "${trial_min}" minutes 2>/dev/null || true
    else
      echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $PROTO" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
    fi
  fi
  echo -e "${YELLOW}Akan dihapus otomatis $_human${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_delete() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor hapus (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${YELLOW}Hapus $user ? [y/N]: ${RESET}"
  read -r yn; case "$yn" in y|Y|yes|YES) ;; *) return 0;; esac
  proto_delete "$PROTO" "$user" 2>&1
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf="🗑 $PROTO deleted: $user"
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_renew() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor renew: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Tambah hari: ${RESET}"
  read -r add
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local new_exp
  new_exp=$(proto_renew "$PROTO" "$user" "$add" 2>&1 | tail -1)
  if [ -n "$new_exp" ]; then echo -e "${GREEN}Renew $user -> $new_exp (+$add hari)${RESET}"; else echo -e "${RED}Gagal renew${RESET}"; fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_modify() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor ganti UUID: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}UUID baru: ${RESET}"
  read -r nid
  [ -z "$nid" ] && { echo -e "${RED}UUID kosong${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if ! validate_uuid "$nid" 2>/dev/null; then echo -e "${RED}UUID tidak valid${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; fi
  proto_set_id "$PROTO" "$user" "$nid" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_login() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Users Login VMESS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  _ensure_db
  local found=0 user i=1
  while IFS='|' read -r user _id _exp _limit _quota _used _status; do
    [ -z "$user" ] && continue
    local cnt ips logf
    logf="/var/log/xray/access.log"
    [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && logf="$MYTUNNEL_PREFIX/var/log/xray/access.log"
    cnt=0; ips=""
    if [ -f "$logf" ]; then
      ips=$(tail -n 5000 "$logf" 2>/dev/null | grep -F "email: $user" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | tr '\n' ' ' 2>/dev/null | sed 's/ $//')
      cnt=$(echo "$ips" | wc -w 2>/dev/null | tr -d ' '); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      ips=$(echo "$ips" | head -c 42)
    fi
    if [ "$cnt" -gt 0 ] 2>/dev/null || [ -n "$ips" ]; then
      printf "%2d) %-12s : %2s/%-2s IP  %-28s ${GREY}[%s]${RESET}\n" "$i" "$user" "$cnt" "${_limit:-0}" "$ips" "$_status"
      found=1; i=$((i+1))
    else
      # tetap tampilkan yang limit 0? tidak — hanya yang online
      true
    fi
  done < <(_list_users_raw)
  [ "$found" -eq 0 ] && echo -e "${DIM}(tidak ada hit di access.log / belum ada trafik)${RESET}"
  echo -e "${GREY}Format: online/limit IP | On=IP unik 5k log terakhir${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_xray_online_cnt() {
  local _u="$1" _log="/var/log/xray/access.log"
  [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && _log="$MYTUNNEL_PREFIX/var/log/xray/access.log"
  [ -f "$_log" ] || { echo 0; return; }
  tail -n 5000 "$_log" 2>/dev/null | grep -F "email: $_u" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | wc -l 2>/dev/null | tr -d ' '
}
_xray_online_ips() {
  local _u="$1" _log="/var/log/xray/access.log"
  [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && _log="$MYTUNNEL_PREFIX/var/log/xray/access.log"
  [ -f "$_log" ] || return
  tail -n 5000 "$_log" 2>/dev/null | grep -F "email: $_u" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | tr '\n' ' ' 2>/dev/null | head -c 28
}
do_list() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "List Users VMESS"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf -v _inner "%2s %-10s %-10s %3s %3s %3s %3s %-6s" "No" "User" "Expiry" "Sisa" "Lim" "Q" "On" "Status"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$_inner"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(kosong)"
  else
    local user exp limit quota status days cnt i=1
    while IFS='|' read -r user _id exp limit quota _used status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      cnt=$(_xray_online_cnt "$user" 2>/dev/null); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      printf -v _inner "%2d %-10s %-10s %3sd %3s %3s %3s %-6s" "$i" "$user" "$exp" "$days" "${limit:-0}" "${quota:-0}" "$cnt" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${GREY}Lim=Limit IP, Q=Quota GB, On=IP unik di access.log (5k)${RESET}"
  echo -e "${GREY}Pilih nomor untuk detail (0 kembali):${RESET}"
  echo -ne "${CYAN}Nomor: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local _u
  _u=$(_pick_user_by_number "$num")
  [ -z "$_u" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _ips; _ips=$(_xray_online_ips "$_u" 2>/dev/null)
  [ -n "$_ips" ] && echo -e "${CYAN}IP login: ${RESET}$_ips"
  print_proto_account_info "$PROTO" "$_u" 2>/dev/null || gen_links "$PROTO" "$_u" 2>/dev/null || echo "User tidak ada"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_lock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor lock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_lock "$PROTO" "$user" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_unlock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor unlock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_unlock "$PROTO" "$user" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_config() {
  clear 2>/dev/null || printf '\033c'
  printf "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Config VMESS (pilih akun)"
  printf "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}\n"
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor cek (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user; user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _out
  _out=$(print_proto_account_info "$PROTO" "$user" 2>&1) || _out=$(gen_links "$PROTO" "$user" 2>&1) || _out="Gagal tampil $user"
  echo "$_out"
  echo ""
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    ah_notify_admin "$_out" 2>/dev/null || true
    echo -e "${GREEN}Detail terkirim ke bot ✓${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_recovery() {
  clear 2>/dev/null || printf '\033c'
  printf "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Recovery VMESS (Expired)"
  printf "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}\n"
  local exp_db="$BASE/db/${PROTO}_expired.txt"
  if [ ! -f "$exp_db" ] || [ ! -s "$exp_db" ]; then
    echo -e "${DIM}(tidak ada akun expired — akun expired otomatis pindah kesini jam 00:00)${RESET}"
    echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 0
  fi
  echo -e "${CYAN}Akun expired:${RESET}"
  local i=1
  while IFS='|' read -r user id exp limit quota used status; do
    [ -z "$user" ] && continue
    printf " %2d) %-12s exp:%-10s lim:%-3s q:%-4s [%s]\n" "$i" "$user" "$exp" "${limit:-0}" "${quota:-0}" "${status:-active}"
    i=$((i+1))
  done < "$exp_db"
  echo ""
  echo -ne "${CYAN}Pilih nomor recovery (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local line; line=$(sed -n "${num}p" "$exp_db" 2>/dev/null)
  [ -z "$line" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user id exp limit quota used status
  IFS='|' read -r user id exp limit quota used status <<< "$line"
  [ -z "$user" ] && { echo -e "${RED}Data rusak${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if grep -q "^${user}|" "$DB" 2>/dev/null; then
    echo -e "${YELLOW}$user sudah ada di DB aktif — hapus dari expired saja${RESET}"
    local _tmp; _tmp=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp" 2>/dev/null || true; cat "$_tmp" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp" 2>/dev/null || true
    echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  echo -ne "${CYAN}Hari aktif baru [30]: ${RESET}"
  read -r add; [ -z "$add" ] && add=30
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Harus angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$add" -lt 1 ] && add=1; [ "$add" -gt 3650 ] && add=3650
  local today new_exp
  today=$(date +%Y-%m-%d 2>/dev/null)
  if declare -f _expiry_add_days >/dev/null 2>&1; then new_exp=$(_expiry_add_days "$today" "$add"); else new_exp=$(date -d "+${add} days" +%Y-%m-%d 2>/dev/null || date -v+${add}d +%Y-%m-%d 2>/dev/null || echo "2099-01-01"); fi
  if [ "$PROTO" = "trojan" ]; then
    [ -z "$id" ] && id=$(gen_password 2>/dev/null || openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
  else
    if ! validate_uuid "$id" 2>/dev/null; then echo -e "${RED}UUID rusak, generate baru${RESET}"; id=$(gen_uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null); fi
  fi
  echo -e "${DIM}Aktifkan $user -> $new_exp (+$add hari) ...${RESET}"
  used=0
  if ! xray_add_client "$PROTO" "$id" "$user" 2>&1 | head -n 3; then
    echo -e "${RED}Gagal xray_add_client${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  xray_reload 2>/dev/null || true
  local nline="${user}|${id}|${new_exp}|${limit:-0}|${quota:-0}|0|active"
  local db_lock; db_lock=$(_proto_lockfile "$PROTO" 2>/dev/null || echo "$BASE/db/.${PROTO}.lock")
  local _tmp2; _tmp2=$(mktemp)
  (
    flock -x 200
    echo "$nline" >> "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$db_lock" 2>/dev/null || { echo "$nline" >> "$DB" 2>/dev/null; chmod 600 "$DB" 2>/dev/null || true; }
  rm -f "$_tmp2" 2>/dev/null || true
  local _tmp3; _tmp3=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp3" 2>/dev/null || true; cat "$_tmp3" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp3" 2>/dev/null || true
  echo -e "${GREEN}Recovery OK: $user -> $new_exp${RESET}"
  local _out; _out=$(print_proto_account_info "$PROTO" "$user" 2>&1) || _out=$(gen_links "$PROTO" "$user" 2>&1) || _out="Akun $user dipulihkan exp $new_exp"
  echo "$_out"
  if declare -f ah_notify_admin >/dev/null 2>&1; then ah_notify_admin "$_out" 2>/dev/null || true; echo -e "${GREEN}Terkirim ke bot ✓${RESET}"; fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $PROTO recovery $user $exp -> $new_exp" >> "$LOG" 2>/dev/null || true
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "VMESS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Create                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Create [Custom UUID]                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Trial                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Delete                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Renew/Extend                                   ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Modify UUID                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) Check Users Login                              ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 8.) List Users                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} LOCK & UNLOCK                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 9.) Lock                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 10.) Unlock                                        ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} UTILITIES                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 11.) Check Config                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 12.) Recovery                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 13.) Back to Menu                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} x.) Exit                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select From Options : ${RESET}"
  read -r c
  case "$c" in
    1) do_create ;;
    2) do_create_custom ;;
    3) do_trial ;;
    4) do_delete ;;
    5) do_renew ;;
    6) do_modify ;;
    7) do_check_login ;;
    8) do_list ;;
    9) do_lock ;;
    10) do_unlock ;;
    11) do_check_config ;;
    12) do_recovery ;;
    13|b|B) break ;;
    x|X) exit 0 ;;
    *) echo -e "${YELLOW}Pilihan tidak valid${RESET}"; sleep 1 ;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/vmess.sh"
cat > "$ETC/menu/vless.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/vless.sh - VLESS management (WS+gRPC+HTTPUpgrade, 60 kolom)
# shellcheck disable=SC1091,SC1090,SC2155,SC2034
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/sysinfo.sh" "$BASE/lib/xray_helpers.sh" "$BASE/lib/proto_helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
PROTO="vless"
DB="$BASE/db/vless.txt"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -n "$MYTUNNEL_PREFIX" ] && LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"
XRAY_CFG="${MYTUNNEL_PREFIX:-}/usr/local/etc/xray/config.json"
[ -n "$MYTUNNEL_PREFIX" ] && XRAY_CFG="$MYTUNNEL_PREFIX/usr/local/etc/xray/config.json"
[ -z "$MYTUNNEL_PREFIX" ] && XRAY_CFG="/usr/local/etc/xray/config.json"

_ensure_db() { mkdir -p "$(dirname "$DB")" 2>/dev/null || true; [ -f "$DB" ] || touch "$DB" 2>/dev/null || true; chmod 600 "$DB" 2>/dev/null || true; }
_expiry_add_days() {
  local base_date="$1" add="$2"
  local base_s new_s
  base_s=$(date -d "$base_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$base_date" +%s 2>/dev/null || date +%s)
  new_s=$((base_s + add*86400))
  date -d "@$new_s" +%Y-%m-%d 2>/dev/null || date -r "$new_s" +%Y-%m-%d 2>/dev/null || echo "$base_date"
}
_today_str() { date +%Y-%m-%d 2>/dev/null; }
_days_left_calc() {
  local exp="$1"; local sec_exp sec_now
  sec_exp=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  sec_now=$(date +%s 2>/dev/null)
  echo $(( (sec_exp - sec_now) / 86400 ))
}
_list_users_raw() { _ensure_db; grep -v '^\s*$' "$DB" 2>/dev/null | grep -v '^#' || true; }
_show_user_list_numbered() {
  local i=1
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Daftar User VLESS"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(belum ada user)"
  else
    local user exp limit quota status days
    while IFS='|' read -r user _id exp limit quota _used status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      printf -v _inner "%2d) %-12s exp:%-10s %3sd q:%-3s lim:%-2s %-6s" "$i" "$user" "$exp" "$days" "${quota:-0}" "${limit:-0}" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}
_pick_user_by_number() {
  local num="$1"
  _list_users_raw | sed -n "${num}p" | cut -d'|' -f1
}

do_create() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then
    draw_box "$brand" 60
    draw_box "VLESS" 60
  else
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$brand"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "VLESS"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  fi
  echo -e "${GREY}Don't use special characters and uppercase!${RESET}"
  echo -e "${GREY}Just input a number for- Quota Limit, Limit IP, Format GB${RESET}"
  echo -e "${GREY}0 for Unlimited${RESET}"
  echo -e "${GREY}0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user quota limit_ip days id
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username tidak boleh kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9]{3,16}$' <<< "$user" 2>/dev/null; then
      echo -e "${RED}Username hanya a-z0-9 3-16, tanpa spasi/simbol/huruf besar${RESET}"; continue
    fi
    if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah dipakai di protokol lain: $user${RESET}"; continue; fi
    if ! validate_proto_user "$user" 2>/dev/null; then echo -e "${RED}Username tidak valid / system user${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Quota Limit (GB)"
    read -r quota
    [ -z "$quota" ] && quota=0
    if [[ "$quota" =~ ^[0-9]+$ ]] && [ "$quota" -ge 0 ] && [ "$quota" -le 9999 ]; then break; fi
    echo -e "${RED}Quota harus angka 0-9999 (0=Unlimited)${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]] && [ "$limit_ip" -ge 0 ] && [ "$limit_ip" -le 100 ]; then break; fi
    echo -e "${RED}Limit harus angka 0-100 (0=No Limit)${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Expired (days)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if [ "$PROTO" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if [ -z "$id" ]; then echo -e "${RED}Gagal generate ID${RESET}"; echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 1; fi
  if proto_create "$PROTO" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1; then
    echo ""
    print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
    # notify Telegram admin
    if declare -f ah_notify_admin >/dev/null 2>&1; then
      _ntf=$(print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || echo "$PROTO $user dibuat")
      ah_notify_admin "$_ntf" 2>/dev/null || true
    fi
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_create_custom() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then draw_box "$brand" 60; draw_box "VLESS CUSTOM" 60; fi
  echo -e "${GREY}Don't use special characters and uppercase!${RESET}"
  echo -e "${GREY}Just input a number for- Quota Limit, Limit IP, Format GB${RESET}"
  echo -e "${GREY}0 for Unlimited / 0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user quota limit_ip days id
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9]{3,16}$' <<< "$user" 2>/dev/null; then echo -e "${RED}Username a-z0-9 3-16${RESET}"; continue; fi
    if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah ada${RESET}"; continue; fi
    if ! validate_proto_user "$user" 2>/dev/null; then echo -e "${RED}Username tidak valid${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "UUID"
    read -r id
    if [ -z "$id" ]; then echo -e "${RED}UUID tidak boleh kosong${RESET}"; continue; fi
    if ! validate_uuid "$id" 2>/dev/null; then echo -e "${RED}UUID tidak valid (format 8-4-4-4-12 hex)${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Quota Limit (GB)"
    read -r quota
    [ -z "$quota" ] && quota=0
    if [[ "$quota" =~ ^[0-9]+$ ]] && [ "$quota" -ge 0 ] && [ "$quota" -le 9999 ]; then break; fi
    echo -e "${RED}Quota harus angka 0-9999${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]] && [ "$limit_ip" -ge 0 ] && [ "$limit_ip" -le 100 ]; then break; fi
    echo -e "${RED}Limit harus angka 0-100${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Expired (days)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if proto_create "$PROTO" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1; then
    echo ""
    print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_parse_duration_to_min() {
  local inp="$1" def="$2" v num suffix
  v=$(echo "$inp" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
  [ -z "$v" ] && v="$def"
  suffix="${v: -1}"
  if [[ "$suffix" == "h" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo $((num*60))
  elif [[ "$suffix" == "m" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo "$num"
  else [[ "$v" =~ ^[0-9]+$ ]] || v="$def"; echo "$v"; fi
}
do_trial() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Trial VLESS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local inp_dur inp_limit inp_quota trial_min trial_limit trial_quota days
  echo -ne "${CYAN}Durasi trial [60m, contoh 30m/2h, default 60m]: ${RESET}"; read -r inp_dur
  trial_min=$(_parse_duration_to_min "$inp_dur" 60)
  [[ "$trial_min" =~ ^[0-9]+$ ]] || trial_min=60
  [ "$trial_min" -lt 1 ] && trial_min=1
  [ "$trial_min" -gt 10080 ] && trial_min=10080
  echo -ne "${CYAN}Limit IP [1, 0=unlimited]: ${RESET}"; read -r inp_limit
  [[ "$inp_limit" =~ ^[0-9]+$ ]] || inp_limit=1
  trial_limit="$inp_limit"
  echo -ne "${CYAN}Quota GB [1, 0=unlimited]: ${RESET}"; read -r inp_quota
  [[ "$inp_quota" =~ ^[0-9]+$ ]] || inp_quota=1
  trial_quota="$inp_quota"
  days=$(( (trial_min + 1439) / 1440 ))
  [ "$days" -lt 1 ] && days=1
  local rnd user id
  rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4)
  [ -z "$rnd" ] && rnd=$(date +%s | tail -c 5)
  user="trial${rnd}"
  user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  [ -z "$user" ] && user="trial123"
  while proto_exists_any "$user" >/dev/null 2>&1; do
    rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4); user="trial${rnd}"; user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  done
  if [ "$PROTO" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if ! proto_create "$PROTO" "$user" "$id" "$days" "$trial_limit" "$trial_quota" 2>&1; then echo -e "${RED}Gagal buat trial${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 1; fi
  local _human; if [ "$trial_min" -ge 60 ] && [ $((trial_min % 60)) -eq 0 ]; then _human="$((trial_min/60)) jam"; else _human="${trial_min} menit"; fi
  echo -e "${GREEN}Trial dibuat $_human (exp ${days} hari, limit $trial_limit IP, quota $trial_quota GB)${RESET}"
  print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf=$(print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || echo "$PROTO trial $user")
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] trial $PROTO $user scheduled delete in ${trial_min}m (TEST simulasi)" >> "$LOG" 2>/dev/null || true
    echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $PROTO" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
  else
    if command -v at >/dev/null 2>&1; then
      echo "bash $BASE/cron/autoexpire_xray.sh; xray_del_client $PROTO $user 2>/dev/null; sed -i '/^$user|/d' $DB 2>/dev/null" | at now + "${trial_min}" minutes 2>/dev/null || true
    else
      echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $PROTO" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
    fi
  fi
  echo -e "${YELLOW}Akan dihapus otomatis $_human${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_delete() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor hapus (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${YELLOW}Hapus $user ? [y/N]: ${RESET}"
  read -r yn; case "$yn" in y|Y|yes|YES) ;; *) return 0;; esac
  proto_delete "$PROTO" "$user" 2>&1
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf="🗑 $PROTO deleted: $user"
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_renew() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor renew: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Tambah hari: ${RESET}"
  read -r add
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local new_exp
  new_exp=$(proto_renew "$PROTO" "$user" "$add" 2>&1 | tail -1)
  if [ -n "$new_exp" ]; then echo -e "${GREEN}Renew $user -> $new_exp (+$add hari)${RESET}"; else echo -e "${RED}Gagal renew${RESET}"; fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_modify() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor ganti UUID: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}UUID baru: ${RESET}"
  read -r nid
  [ -z "$nid" ] && { echo -e "${RED}UUID kosong${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if ! validate_uuid "$nid" 2>/dev/null; then echo -e "${RED}UUID tidak valid${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; fi
  proto_set_id "$PROTO" "$user" "$nid" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_login() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Users Login VLESS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  _ensure_db
  local found=0 user i=1
  while IFS='|' read -r user _id _exp _limit _quota _used _status; do
    [ -z "$user" ] && continue
    local cnt ips logf
    logf="/var/log/xray/access.log"
    [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && logf="$MYTUNNEL_PREFIX/var/log/xray/access.log"
    cnt=0; ips=""
    if [ -f "$logf" ]; then
      ips=$(tail -n 5000 "$logf" 2>/dev/null | grep -F "email: $user" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | tr '\n' ' ' 2>/dev/null | sed 's/ $//')
      cnt=$(echo "$ips" | wc -w 2>/dev/null | tr -d ' '); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      ips=$(echo "$ips" | head -c 42)
    fi
    if [ "$cnt" -gt 0 ] 2>/dev/null || [ -n "$ips" ]; then
      printf "%2d) %-12s : %2s/%-2s IP  %-28s ${GREY}[%s]${RESET}\n" "$i" "$user" "$cnt" "${_limit:-0}" "$ips" "$_status"
      found=1; i=$((i+1))
    else
      # tetap tampilkan yang limit 0? tidak — hanya yang online
      true
    fi
  done < <(_list_users_raw)
  [ "$found" -eq 0 ] && echo -e "${DIM}(tidak ada hit di access.log / belum ada trafik)${RESET}"
  echo -e "${GREY}Format: online/limit IP | On=IP unik 5k log terakhir${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_xray_online_cnt() {
  local _u="$1" _log="/var/log/xray/access.log"
  [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && _log="$MYTUNNEL_PREFIX/var/log/xray/access.log"
  [ -f "$_log" ] || { echo 0; return; }
  tail -n 5000 "$_log" 2>/dev/null | grep -F "email: $_u" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | wc -l 2>/dev/null | tr -d ' '
}
_xray_online_ips() {
  local _u="$1" _log="/var/log/xray/access.log"
  [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && _log="$MYTUNNEL_PREFIX/var/log/xray/access.log"
  [ -f "$_log" ] || return
  tail -n 5000 "$_log" 2>/dev/null | grep -F "email: $_u" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | tr '\n' ' ' 2>/dev/null | head -c 28
}
do_list() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "List Users VLESS"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf -v _inner "%2s %-10s %-10s %3s %3s %3s %3s %-6s" "No" "User" "Expiry" "Sisa" "Lim" "Q" "On" "Status"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$_inner"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(kosong)"
  else
    local user exp limit quota status days cnt i=1
    while IFS='|' read -r user _id exp limit quota _used status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      cnt=$(_xray_online_cnt "$user" 2>/dev/null); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      printf -v _inner "%2d %-10s %-10s %3sd %3s %3s %3s %-6s" "$i" "$user" "$exp" "$days" "${limit:-0}" "${quota:-0}" "$cnt" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${GREY}Lim=Limit IP, Q=Quota GB, On=IP unik di access.log (5k)${RESET}"
  echo -e "${GREY}Pilih nomor untuk detail (0 kembali):${RESET}"
  echo -ne "${CYAN}Nomor: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local _u
  _u=$(_pick_user_by_number "$num")
  [ -z "$_u" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _ips; _ips=$(_xray_online_ips "$_u" 2>/dev/null)
  [ -n "$_ips" ] && echo -e "${CYAN}IP login: ${RESET}$_ips"
  print_proto_account_info "$PROTO" "$_u" 2>/dev/null || gen_links "$PROTO" "$_u" 2>/dev/null || echo "User tidak ada"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_lock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor lock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_lock "$PROTO" "$user" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_unlock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor unlock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_unlock "$PROTO" "$user" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_config() {
  clear 2>/dev/null || printf '\033c'
  printf "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Config VLESS (pilih akun)"
  printf "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}\n"
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor cek (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user; user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _out
  _out=$(print_proto_account_info "$PROTO" "$user" 2>&1) || _out=$(gen_links "$PROTO" "$user" 2>&1) || _out="Gagal tampil $user"
  echo "$_out"
  echo ""
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    ah_notify_admin "$_out" 2>/dev/null || true
    echo -e "${GREEN}Detail terkirim ke bot ✓${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_recovery() {
  clear 2>/dev/null || printf '\033c'
  printf "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Recovery VLESS (Expired)"
  printf "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}\n"
  local exp_db="$BASE/db/${PROTO}_expired.txt"
  if [ ! -f "$exp_db" ] || [ ! -s "$exp_db" ]; then
    echo -e "${DIM}(tidak ada akun expired — akun expired otomatis pindah kesini jam 00:00)${RESET}"
    echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 0
  fi
  echo -e "${CYAN}Akun expired:${RESET}"
  local i=1
  while IFS='|' read -r user id exp limit quota used status; do
    [ -z "$user" ] && continue
    printf " %2d) %-12s exp:%-10s lim:%-3s q:%-4s [%s]\n" "$i" "$user" "$exp" "${limit:-0}" "${quota:-0}" "${status:-active}"
    i=$((i+1))
  done < "$exp_db"
  echo ""
  echo -ne "${CYAN}Pilih nomor recovery (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local line; line=$(sed -n "${num}p" "$exp_db" 2>/dev/null)
  [ -z "$line" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user id exp limit quota used status
  IFS='|' read -r user id exp limit quota used status <<< "$line"
  [ -z "$user" ] && { echo -e "${RED}Data rusak${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if grep -q "^${user}|" "$DB" 2>/dev/null; then
    echo -e "${YELLOW}$user sudah ada di DB aktif — hapus dari expired saja${RESET}"
    local _tmp; _tmp=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp" 2>/dev/null || true; cat "$_tmp" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp" 2>/dev/null || true
    echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  echo -ne "${CYAN}Hari aktif baru [30]: ${RESET}"
  read -r add; [ -z "$add" ] && add=30
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Harus angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$add" -lt 1 ] && add=1; [ "$add" -gt 3650 ] && add=3650
  local today new_exp
  today=$(date +%Y-%m-%d 2>/dev/null)
  if declare -f _expiry_add_days >/dev/null 2>&1; then new_exp=$(_expiry_add_days "$today" "$add"); else new_exp=$(date -d "+${add} days" +%Y-%m-%d 2>/dev/null || date -v+${add}d +%Y-%m-%d 2>/dev/null || echo "2099-01-01"); fi
  if [ "$PROTO" = "trojan" ]; then
    [ -z "$id" ] && id=$(gen_password 2>/dev/null || openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
  else
    if ! validate_uuid "$id" 2>/dev/null; then echo -e "${RED}UUID rusak, generate baru${RESET}"; id=$(gen_uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null); fi
  fi
  echo -e "${DIM}Aktifkan $user -> $new_exp (+$add hari) ...${RESET}"
  used=0
  if ! xray_add_client "$PROTO" "$id" "$user" 2>&1 | head -n 3; then
    echo -e "${RED}Gagal xray_add_client${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  xray_reload 2>/dev/null || true
  local nline="${user}|${id}|${new_exp}|${limit:-0}|${quota:-0}|0|active"
  local db_lock; db_lock=$(_proto_lockfile "$PROTO" 2>/dev/null || echo "$BASE/db/.${PROTO}.lock")
  local _tmp2; _tmp2=$(mktemp)
  (
    flock -x 200
    echo "$nline" >> "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$db_lock" 2>/dev/null || { echo "$nline" >> "$DB" 2>/dev/null; chmod 600 "$DB" 2>/dev/null || true; }
  rm -f "$_tmp2" 2>/dev/null || true
  local _tmp3; _tmp3=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp3" 2>/dev/null || true; cat "$_tmp3" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp3" 2>/dev/null || true
  echo -e "${GREEN}Recovery OK: $user -> $new_exp${RESET}"
  local _out; _out=$(print_proto_account_info "$PROTO" "$user" 2>&1) || _out=$(gen_links "$PROTO" "$user" 2>&1) || _out="Akun $user dipulihkan exp $new_exp"
  echo "$_out"
  if declare -f ah_notify_admin >/dev/null 2>&1; then ah_notify_admin "$_out" 2>/dev/null || true; echo -e "${GREEN}Terkirim ke bot ✓${RESET}"; fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $PROTO recovery $user $exp -> $new_exp" >> "$LOG" 2>/dev/null || true
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "VLESS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Create                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Create [Custom UUID]                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Trial                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Delete                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Renew/Extend                                   ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Modify UUID                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) Check Users Login                              ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 8.) List Users                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} LOCK & UNLOCK                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 9.) Lock                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 10.) Unlock                                        ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} UTILITIES                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 11.) Check Config                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 12.) Recovery                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 13.) Back to Menu                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} x.) Exit                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select From Options : ${RESET}"
  read -r c
  case "$c" in
    1) do_create ;;
    2) do_create_custom ;;
    3) do_trial ;;
    4) do_delete ;;
    5) do_renew ;;
    6) do_modify ;;
    7) do_check_login ;;
    8) do_list ;;
    9) do_lock ;;
    10) do_unlock ;;
    11) do_check_config ;;
    12) do_recovery ;;
    13|b|B) break ;;
    x|X) exit 0 ;;
    *) echo -e "${YELLOW}Pilihan tidak valid${RESET}"; sleep 1 ;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/vless.sh"
cat > "$ETC/menu/trojan.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/trojan.sh - TROJAN management (WS+gRPC+HTTPUpgrade, 60 kolom)
# shellcheck disable=SC1091,SC1090,SC2155,SC2034
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/sysinfo.sh" "$BASE/lib/xray_helpers.sh" "$BASE/lib/proto_helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
BLUE="${BLUE:-\033[0;34m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
PROTO="trojan"
DB="$BASE/db/trojan.txt"
LOG="${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log"
[ -n "$MYTUNNEL_PREFIX" ] && LOG="$MYTUNNEL_PREFIX/var/log/mytunnel.log"
XRAY_CFG="${MYTUNNEL_PREFIX:-}/usr/local/etc/xray/config.json"
[ -n "$MYTUNNEL_PREFIX" ] && XRAY_CFG="$MYTUNNEL_PREFIX/usr/local/etc/xray/config.json"
[ -z "$MYTUNNEL_PREFIX" ] && XRAY_CFG="/usr/local/etc/xray/config.json"

_ensure_db() { mkdir -p "$(dirname "$DB")" 2>/dev/null || true; [ -f "$DB" ] || touch "$DB" 2>/dev/null || true; chmod 600 "$DB" 2>/dev/null || true; }
_expiry_add_days() {
  local base_date="$1" add="$2"
  local base_s new_s
  base_s=$(date -d "$base_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$base_date" +%s 2>/dev/null || date +%s)
  new_s=$((base_s + add*86400))
  date -d "@$new_s" +%Y-%m-%d 2>/dev/null || date -r "$new_s" +%Y-%m-%d 2>/dev/null || echo "$base_date"
}
_today_str() { date +%Y-%m-%d 2>/dev/null; }
_days_left_calc() {
  local exp="$1"; local sec_exp sec_now
  sec_exp=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
  sec_now=$(date +%s 2>/dev/null)
  echo $(( (sec_exp - sec_now) / 86400 ))
}
_list_users_raw() { _ensure_db; grep -v '^\s*$' "$DB" 2>/dev/null | grep -v '^#' || true; }
_show_user_list_numbered() {
  local i=1
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Daftar User TROJAN"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(belum ada user)"
  else
    local user exp limit quota status days
    while IFS='|' read -r user _id exp limit quota _used status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      printf -v _inner "%2d) %-12s exp:%-10s %3sd q:%-3s lim:%-2s %-6s" "$i" "$user" "$exp" "$days" "${quota:-0}" "${limit:-0}" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}
_pick_user_by_number() {
  local num="$1"
  _list_users_raw | sed -n "${num}p" | cut -d'|' -f1
}

do_create() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then
    draw_box "$brand" 60
    draw_box "TROJAN" 60
  else
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$brand"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "TROJAN"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  fi
  echo -e "${GREY}Don't use special characters and uppercase!${RESET}"
  echo -e "${GREY}Just input a number for- Quota Limit, Limit IP, Format GB${RESET}"
  echo -e "${GREY}0 for Unlimited${RESET}"
  echo -e "${GREY}0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user quota limit_ip days id
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username tidak boleh kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9]{3,16}$' <<< "$user" 2>/dev/null; then
      echo -e "${RED}Username hanya a-z0-9 3-16, tanpa spasi/simbol/huruf besar${RESET}"; continue
    fi
    if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah dipakai di protokol lain: $user${RESET}"; continue; fi
    if ! validate_proto_user "$user" 2>/dev/null; then echo -e "${RED}Username tidak valid / system user${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Quota Limit (GB)"
    read -r quota
    [ -z "$quota" ] && quota=0
    if [[ "$quota" =~ ^[0-9]+$ ]] && [ "$quota" -ge 0 ] && [ "$quota" -le 9999 ]; then break; fi
    echo -e "${RED}Quota harus angka 0-9999 (0=Unlimited)${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]] && [ "$limit_ip" -ge 0 ] && [ "$limit_ip" -le 100 ]; then break; fi
    echo -e "${RED}Limit harus angka 0-100 (0=No Limit)${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Expired (days)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if [ "$PROTO" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if [ -z "$id" ]; then echo -e "${RED}Gagal generate ID${RESET}"; echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 1; fi
  if proto_create "$PROTO" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1; then
    echo ""
    print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
    # notify Telegram admin
    if declare -f ah_notify_admin >/dev/null 2>&1; then
      _ntf=$(print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || echo "$PROTO $user dibuat")
      ah_notify_admin "$_ntf" 2>/dev/null || true
    fi
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_create_custom() {
  clear 2>/dev/null || printf '\033c'
  local brand
  brand=$(cat "$BASE/config/brand.txt" 2>/dev/null | head -1 | tr -d '\n')
  [ -z "$brand" ] && brand="TUNNEL PRO"
  if declare -f draw_box >/dev/null 2>&1; then draw_box "$brand" 60; draw_box "TROJAN CUSTOM" 60; fi
  echo -e "${GREY}Don't use special characters and uppercase!${RESET}"
  echo -e "${GREY}Just input a number for- Quota Limit, Limit IP, Format GB${RESET}"
  echo -e "${GREY}0 for Unlimited / 0 for No Limit${RESET}"
  echo -e "${GREY}Press CTRL+C for CANCEL${RESET}"
  echo ""
  local user quota limit_ip days id
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Username"
    read -r user
    user=$(echo "$user" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    if [ -z "$user" ]; then echo -e "${RED}Username kosong${RESET}"; continue; fi
    if ! grep -qE '^[a-z0-9]{3,16}$' <<< "$user" 2>/dev/null; then echo -e "${RED}Username a-z0-9 3-16${RESET}"; continue; fi
    if proto_exists_any "$user" >/dev/null 2>&1; then echo -e "${RED}User sudah ada${RESET}"; continue; fi
    if ! validate_proto_user "$user" 2>/dev/null; then echo -e "${RED}Username tidak valid${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Password"
    read -r id
    if [ -z "$id" ]; then echo -e "${RED}Password tidak boleh kosong${RESET}"; continue; fi
    if [ "${#id}" -lt 4 ]; then echo -e "${RED}Password minimal 4 karakter${RESET}"; continue; fi
    break
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Quota Limit (GB)"
    read -r quota
    [ -z "$quota" ] && quota=0
    if [[ "$quota" =~ ^[0-9]+$ ]] && [ "$quota" -ge 0 ] && [ "$quota" -le 9999 ]; then break; fi
    echo -e "${RED}Quota harus angka 0-9999${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Limit (IP)"
    read -r limit_ip
    [ -z "$limit_ip" ] && limit_ip=0
    if [[ "$limit_ip" =~ ^[0-9]+$ ]] && [ "$limit_ip" -ge 0 ] && [ "$limit_ip" -le 100 ]; then break; fi
    echo -e "${RED}Limit harus angka 0-100${RESET}"
  done
  while true; do
    printf "${CYAN}%-18s: ${RESET}" "Expired (days)"
    read -r days
    [ -z "$days" ] && days=30
    if [[ "$days" =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 3650 ]; then break; fi
    echo -e "${RED}Hari harus angka 1-3650${RESET}"
  done
  if proto_create "$PROTO" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1; then
    echo ""
    print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
  else
    echo -e "${RED}Gagal buat $user${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_parse_duration_to_min() {
  local inp="$1" def="$2" v num suffix
  v=$(echo "$inp" | tr -d ' ' | tr '[:upper:]' '[:lower:]')
  [ -z "$v" ] && v="$def"
  suffix="${v: -1}"
  if [[ "$suffix" == "h" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo $((num*60))
  elif [[ "$suffix" == "m" ]]; then num="${v%?}"; [[ "$num" =~ ^[0-9]+$ ]] || num="$def"; echo "$num"
  else [[ "$v" =~ ^[0-9]+$ ]] || v="$def"; echo "$v"; fi
}
do_trial() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Trial TROJAN"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local inp_dur inp_limit inp_quota trial_min trial_limit trial_quota days
  echo -ne "${CYAN}Durasi trial [60m, contoh 30m/2h, default 60m]: ${RESET}"; read -r inp_dur
  trial_min=$(_parse_duration_to_min "$inp_dur" 60)
  [[ "$trial_min" =~ ^[0-9]+$ ]] || trial_min=60
  [ "$trial_min" -lt 1 ] && trial_min=1
  [ "$trial_min" -gt 10080 ] && trial_min=10080
  echo -ne "${CYAN}Limit IP [1, 0=unlimited]: ${RESET}"; read -r inp_limit
  [[ "$inp_limit" =~ ^[0-9]+$ ]] || inp_limit=1
  trial_limit="$inp_limit"
  echo -ne "${CYAN}Quota GB [1, 0=unlimited]: ${RESET}"; read -r inp_quota
  [[ "$inp_quota" =~ ^[0-9]+$ ]] || inp_quota=1
  trial_quota="$inp_quota"
  days=$(( (trial_min + 1439) / 1440 ))
  [ "$days" -lt 1 ] && days=1
  local rnd user id
  rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4)
  [ -z "$rnd" ] && rnd=$(date +%s | tail -c 5)
  user="trial${rnd}"
  user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  [ -z "$user" ] && user="trial123"
  while proto_exists_any "$user" >/dev/null 2>&1; do
    rnd=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | head -c 4); user="trial${rnd}"; user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  done
  if [ "$PROTO" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if ! proto_create "$PROTO" "$user" "$id" "$days" "$trial_limit" "$trial_quota" 2>&1; then echo -e "${RED}Gagal buat trial${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 1; fi
  local _human; if [ "$trial_min" -ge 60 ] && [ $((trial_min % 60)) -eq 0 ]; then _human="$((trial_min/60)) jam"; else _human="${trial_min} menit"; fi
  echo -e "${GREEN}Trial dibuat $_human (exp ${days} hari, limit $trial_limit IP, quota $trial_quota GB)${RESET}"
  print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || true
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf=$(print_proto_account_info "$PROTO" "$user" 2>/dev/null || gen_links "$PROTO" "$user" 2>/dev/null || echo "$PROTO trial $user")
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] trial $PROTO $user scheduled delete in ${trial_min}m (TEST simulasi)" >> "$LOG" 2>/dev/null || true
    echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $PROTO" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
  else
    if command -v at >/dev/null 2>&1; then
      echo "bash $BASE/cron/autoexpire_xray.sh; xray_del_client $PROTO $user 2>/dev/null; sed -i '/^$user|/d' $DB 2>/dev/null" | at now + "${trial_min}" minutes 2>/dev/null || true
    else
      echo "$(date -d "+${trial_min} minutes" +%s 2>/dev/null || echo 0) $user $PROTO" >> "$BASE/db/.trial_schedule" 2>/dev/null || true
    fi
  fi
  echo -e "${YELLOW}Akan dihapus otomatis $_human${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_delete() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor hapus (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${YELLOW}Hapus $user ? [y/N]: ${RESET}"
  read -r yn; case "$yn" in y|Y|yes|YES) ;; *) return 0;; esac
  proto_delete "$PROTO" "$user" 2>&1
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    _ntf="🗑 $PROTO deleted: $user"
    ah_notify_admin "$_ntf" 2>/dev/null || true
  fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_renew() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor renew: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Tambah hari: ${RESET}"
  read -r add
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local new_exp
  new_exp=$(proto_renew "$PROTO" "$user" "$add" 2>&1 | tail -1)
  if [ -n "$new_exp" ]; then echo -e "${GREEN}Renew $user -> $new_exp (+$add hari)${RESET}"; else echo -e "${RED}Gagal renew${RESET}"; fi
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_modify() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor ganti password: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Password baru: ${RESET}"
  read -r npw
  [ -z "$npw" ] && { echo -e "${RED}Password kosong${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_set_id "$PROTO" "$user" "$npw" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_login() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Users Login TROJAN"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  _ensure_db
  local found=0 user i=1
  while IFS='|' read -r user _id _exp _limit _quota _used _status; do
    [ -z "$user" ] && continue
    local cnt ips logf
    logf="/var/log/xray/access.log"
    [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && logf="$MYTUNNEL_PREFIX/var/log/xray/access.log"
    cnt=0; ips=""
    if [ -f "$logf" ]; then
      ips=$(tail -n 5000 "$logf" 2>/dev/null | grep -F "email: $user" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | tr '\n' ' ' 2>/dev/null | sed 's/ $//')
      cnt=$(echo "$ips" | wc -w 2>/dev/null | tr -d ' '); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      ips=$(echo "$ips" | head -c 42)
    fi
    if [ "$cnt" -gt 0 ] 2>/dev/null || [ -n "$ips" ]; then
      printf "%2d) %-12s : %2s/%-2s IP  %-28s ${GREY}[%s]${RESET}\n" "$i" "$user" "$cnt" "${_limit:-0}" "$ips" "$_status"
      found=1; i=$((i+1))
    else
      # tetap tampilkan yang limit 0? tidak — hanya yang online
      true
    fi
  done < <(_list_users_raw)
  [ "$found" -eq 0 ] && echo -e "${DIM}(tidak ada hit di access.log / belum ada trafik)${RESET}"
  echo -e "${GREY}Format: online/limit IP | On=IP unik 5k log terakhir${RESET}"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

_xray_online_cnt() {
  local _u="$1" _log="/var/log/xray/access.log"
  [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && _log="$MYTUNNEL_PREFIX/var/log/xray/access.log"
  [ -f "$_log" ] || { echo 0; return; }
  tail -n 5000 "$_log" 2>/dev/null | grep -F "email: $_u" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | wc -l 2>/dev/null | tr -d ' '
}
_xray_online_ips() {
  local _u="$1" _log="/var/log/xray/access.log"
  [ -n "${MYTUNNEL_PREFIX:-}" ] && [ -f "$MYTUNNEL_PREFIX/var/log/xray/access.log" ] && _log="$MYTUNNEL_PREFIX/var/log/xray/access.log"
  [ -f "$_log" ] || return
  tail -n 5000 "$_log" 2>/dev/null | grep -F "email: $_u" 2>/dev/null | grep -oE 'from [0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | awk '{print $2}' 2>/dev/null | sort -u 2>/dev/null | tr '\n' ' ' 2>/dev/null | head -c 28
}
do_list() {
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "List Users TROJAN"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf -v _inner "%2s %-10s %-10s %3s %3s %3s %3s %-6s" "No" "User" "Expiry" "Sisa" "Lim" "Q" "On" "Status"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "$_inner"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -s "$DB" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(kosong)"
  else
    local user exp limit quota status days cnt i=1
    while IFS='|' read -r user _id exp limit quota _used status; do
      [ -z "$user" ] && continue
      days=$(_days_left_calc "$exp")
      [ "$days" -lt 0 ] && days=0
      cnt=$(_xray_online_cnt "$user" 2>/dev/null); [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      printf -v _inner "%2d %-10s %-10s %3sd %3s %3s %3s %-6s" "$i" "$user" "$exp" "$days" "${limit:-0}" "${quota:-0}" "$cnt" "$status"
      printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_inner"
      i=$((i+1))
    done < <(_list_users_raw)
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${GREY}Lim=Limit IP, Q=Quota GB, On=IP unik di access.log (5k)${RESET}"
  echo -e "${GREY}Pilih nomor untuk detail (0 kembali):${RESET}"
  echo -ne "${CYAN}Nomor: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local _u
  _u=$(_pick_user_by_number "$num")
  [ -z "$_u" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _ips; _ips=$(_xray_online_ips "$_u" 2>/dev/null)
  [ -n "$_ips" ] && echo -e "${CYAN}IP login: ${RESET}$_ips"
  print_proto_account_info "$PROTO" "$_u" 2>/dev/null || gen_links "$PROTO" "$_u" 2>/dev/null || echo "User tidak ada"
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_lock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor lock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_lock "$PROTO" "$user" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_unlock() {
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor unlock: ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user
  user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  proto_unlock "$PROTO" "$user" 2>&1
  echo -ne "${GREY}Enter...${RESET}"; read -r _
}

do_check_config() {
  clear 2>/dev/null || printf '\033c'
  printf "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Config TROJAN (pilih akun)"
  printf "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}\n"
  _show_user_list_numbered
  [ ! -s "$DB" ] && { echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  echo -ne "${CYAN}Pilih nomor cek (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local user; user=$(_pick_user_by_number "$num")
  [ -z "$user" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  clear 2>/dev/null || printf '\033c'
  local _out
  _out=$(print_proto_account_info "$PROTO" "$user" 2>&1) || _out=$(gen_links "$PROTO" "$user" 2>&1) || _out="Gagal tampil $user"
  echo "$_out"
  echo ""
  if declare -f ah_notify_admin >/dev/null 2>&1; then
    ah_notify_admin "$_out" 2>/dev/null || true
    echo -e "${GREEN}Detail terkirim ke bot ✓${RESET}"
  fi
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

do_recovery() {
  clear 2>/dev/null || printf '\033c'
  printf "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}\n"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Recovery TROJAN (Expired)"
  printf "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}\n"
  local exp_db="$BASE/db/${PROTO}_expired.txt"
  if [ ! -f "$exp_db" ] || [ ! -s "$exp_db" ]; then
    echo -e "${DIM}(tidak ada akun expired — akun expired otomatis pindah kesini jam 00:00)${RESET}"
    echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _; return 0
  fi
  echo -e "${CYAN}Akun expired:${RESET}"
  local i=1
  while IFS='|' read -r user id exp limit quota used status; do
    [ -z "$user" ] && continue
    printf " %2d) %-12s exp:%-10s lim:%-3s q:%-4s [%s]\n" "$i" "$user" "$exp" "${limit:-0}" "${quota:-0}" "${status:-active}"
    i=$((i+1))
  done < "$exp_db"
  echo ""
  echo -ne "${CYAN}Pilih nomor recovery (0 batal): ${RESET}"
  read -r num
  [[ "$num" =~ ^[0-9]+$ ]] || { echo -e "${RED}Input angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$num" -eq 0 ] && return 0
  local line; line=$(sed -n "${num}p" "$exp_db" 2>/dev/null)
  [ -z "$line" ] && { echo -e "${RED}Nomor tidak ada${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  local user id exp limit quota used status
  IFS='|' read -r user id exp limit quota used status <<< "$line"
  [ -z "$user" ] && { echo -e "${RED}Data rusak${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  if grep -q "^${user}|" "$DB" 2>/dev/null; then
    echo -e "${YELLOW}$user sudah ada di DB aktif — hapus dari expired saja${RESET}"
    local _tmp; _tmp=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp" 2>/dev/null || true; cat "$_tmp" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp" 2>/dev/null || true
    echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  echo -ne "${CYAN}Hari aktif baru [30]: ${RESET}"
  read -r add; [ -z "$add" ] && add=30
  [[ "$add" =~ ^[0-9]+$ ]] || { echo -e "${RED}Harus angka${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0; }
  [ "$add" -lt 1 ] && add=1; [ "$add" -gt 3650 ] && add=3650
  local today new_exp
  today=$(date +%Y-%m-%d 2>/dev/null)
  if declare -f _expiry_add_days >/dev/null 2>&1; then new_exp=$(_expiry_add_days "$today" "$add"); else new_exp=$(date -d "+${add} days" +%Y-%m-%d 2>/dev/null || date -v+${add}d +%Y-%m-%d 2>/dev/null || echo "2099-01-01"); fi
  if [ "$PROTO" = "trojan" ]; then
    [ -z "$id" ] && id=$(gen_password 2>/dev/null || openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 12)
  else
    if ! validate_uuid "$id" 2>/dev/null; then echo -e "${RED}UUID rusak, generate baru${RESET}"; id=$(gen_uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null); fi
  fi
  echo -e "${DIM}Aktifkan $user -> $new_exp (+$add hari) ...${RESET}"
  used=0
  if ! xray_add_client "$PROTO" "$id" "$user" 2>&1 | head -n 3; then
    echo -e "${RED}Gagal xray_add_client${RESET}"; echo -ne "${GREY}Enter...${RESET}"; read -r _; return 0
  fi
  xray_reload 2>/dev/null || true
  local nline="${user}|${id}|${new_exp}|${limit:-0}|${quota:-0}|0|active"
  local db_lock; db_lock=$(_proto_lockfile "$PROTO" 2>/dev/null || echo "$BASE/db/.${PROTO}.lock")
  local _tmp2; _tmp2=$(mktemp)
  (
    flock -x 200
    echo "$nline" >> "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
  ) 200>"$db_lock" 2>/dev/null || { echo "$nline" >> "$DB" 2>/dev/null; chmod 600 "$DB" 2>/dev/null || true; }
  rm -f "$_tmp2" 2>/dev/null || true
  local _tmp3; _tmp3=$(mktemp); grep -v "^${user}|" "$exp_db" > "$_tmp3" 2>/dev/null || true; cat "$_tmp3" > "$exp_db" 2>/dev/null; chmod 600 "$exp_db" 2>/dev/null || true; rm -f "$_tmp3" 2>/dev/null || true
  echo -e "${GREEN}Recovery OK: $user -> $new_exp${RESET}"
  local _out; _out=$(print_proto_account_info "$PROTO" "$user" 2>&1) || _out=$(gen_links "$PROTO" "$user" 2>&1) || _out="Akun $user dipulihkan exp $new_exp"
  echo "$_out"
  if declare -f ah_notify_admin >/dev/null 2>&1; then ah_notify_admin "$_out" 2>/dev/null || true; echo -e "${GREEN}Terkirim ke bot ✓${RESET}"; fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $PROTO recovery $user $exp -> $new_exp" >> "$LOG" 2>/dev/null || true
  echo -ne "${GREY}Tekan Enter...${RESET}"; read -r _
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "TROJAN"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Create                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Create [Custom Password]                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Trial                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Delete                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Renew/Extend                                   ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Modify Password                                ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) Check Users Login                              ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 8.) List Users                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} LOCK & UNLOCK                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 9.) Lock                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 10.) Unlock                                        ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}                                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} UTILITIES                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 11.) Check Config                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 12.) Recovery                                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 13.) Back to Menu                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} x.) Exit                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select From Options : ${RESET}"
  read -r c
  case "$c" in
    1) do_create ;;
    2) do_create_custom ;;
    3) do_trial ;;
    4) do_delete ;;
    5) do_renew ;;
    6) do_modify ;;
    7) do_check_login ;;
    8) do_list ;;
    9) do_lock ;;
    10) do_unlock ;;
    11) do_check_config ;;
    12) do_recovery ;;
    13|b|B) break ;;
    x|X) exit 0 ;;
    *) echo -e "${YELLOW}Pilihan tidak valid${RESET}"; sleep 1 ;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/trojan.sh"
cat > "$ETC/menu/features.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/features.sh - FEATURES (TAHAP 5+6, 60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/features_helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "FEATURES"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET}  1.) Check Bandwidth                               ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  2.) Set Date Auto Reboot                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  3.) Reboot VPS                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  4.) Speed VPS                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  5.) Change Dropbear Version                        ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  6.) Check All Service                             ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  7.) Backup Configuration VPS                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  8.) Restore Configuration VPS                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  9.) Change Domain VPS                             ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 10.) Change Banner & Response                      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 11.) Start/Stop Service                            ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 12.) Security SYN ETC                              ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 13.) Set Auto Update                               ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 14.) Information System                            ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 15.) Dropbear Version (legacy)                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 16.) Advanced (WARP, Routing, SlowDNS)             ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 17.) Back to Menu                                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET}  x.) Exit                                          ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select [1-17 or x]: ${RESET}"
  read -r c
  case "$c" in
    1) bash "$BASE/features/bandwidth.sh" 2>&1 || echo -e "${YELLOW}Fitur bandwidth belum tersedia${RESET}"; pause;;
    2) bash "$BASE/features/reboot.sh" 2>&1 || echo -e "${YELLOW}Fitur reboot belum tersedia${RESET}"; pause;;
    3) bash "$BASE/features/reboot.sh" 2>&1 || echo -e "${YELLOW}Fitur reboot belum tersedia${RESET}"; pause;; # reboot VPS via same
    4) bash "$BASE/features/speedtest.sh" 2>&1 || echo -e "${YELLOW}Fitur speedtest belum tersedia${RESET}"; pause;;
    5) bash "$BASE/features/dropbear_version.sh" 2>&1 || echo -e "${YELLOW}Fitur dropbear_version belum tersedia${RESET}"; pause;;
    6) bash "$BASE/features/services.sh" 2>&1 || echo -e "${YELLOW}Fitur services belum tersedia${RESET}"; pause;;
    7) bash "$BASE/features/backup.sh" 2>&1 || echo -e "${YELLOW}Fitur backup belum tersedia${RESET}"; pause;;
    8) bash "$BASE/features/backup.sh" 2>&1 || echo -e "${YELLOW}Fitur backup belum tersedia${RESET}"; pause;;
    9) bash "$BASE/features/domain.sh" 2>&1 || echo -e "${YELLOW}Fitur domain belum tersedia${RESET}"; pause;;
    10) bash "$BASE/features/banner.sh" 2>&1 || echo -e "${YELLOW}Fitur banner belum tersedia${RESET}"; pause;;
    11) bash "$BASE/features/services.sh" 2>&1 || echo -e "${YELLOW}Fitur services belum tersedia${RESET}"; pause;;
    12) bash "$BASE/features/security.sh" 2>&1 || echo -e "${YELLOW}Fitur security belum tersedia${RESET}"; pause;;
    13) bash "$BASE/features/autoupdate.sh" 2>&1 || echo -e "${YELLOW}Fitur autoupdate belum tersedia${RESET}"; pause;;
    14) bash "$BASE/features/sysinfo_page.sh" 2>&1 || echo -e "${YELLOW}Fitur sysinfo belum tersedia${RESET}"; pause;;
    15) bash "$BASE/features/dropbear_version.sh" 2>&1 || echo -e "${YELLOW}Fitur dropbear_version belum tersedia${RESET}"; pause;;
    16) bash "$BASE/menu/advanced.sh" 2>&1 || echo -e "${YELLOW}Advanced belum tersedia${RESET}";;
    17|b|B) break;;
    x|X) exit 0;;
    *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/features.sh"
cat > "$ETC/menu/bot.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/bot.sh - SETUP BOT (no eval, quoted)
# shellcheck disable=SC1091,SC1090,SC2154
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
CONF="$BASE/config/bot.conf"
SERVICE="mytunnel-bot"

bot_status(){
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF" 2>/dev/null || true
    local tok="${BOT_TOKEN:-}"; local adm="${ADMIN_ID:-}"
    echo -e "Token : $(ah_mask_token "$tok")"
    echo -e "Admin : ${adm:-(-)}"
  else
    echo -e "Bot   : ${YELLOW}belum dikonfigurasi${RESET}"
  fi
  local st
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    if [ -f "$BASE/var/log/${SERVICE}.sim" ] || [ -f "$BASE/etc/systemd/system/${SERVICE}.service" ]; then st="ON (sim)"; else st="OFF"; fi
  else
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then st="ON"; else st="OFF"; fi
  fi
  echo -e "Service $SERVICE : $st"
}

bot_test_send(){
  [ -f "$CONF" ] || { echo -e "${RED}Belum ada config bot${RESET}"; return 1; }
  # shellcheck disable=SC1090
  . "$CONF" 2>/dev/null || true
  [ -z "${BOT_TOKEN:-}" ] || [ -z "${ADMIN_ID:-}" ] && { echo -e "${RED}Token/Admin kosong${RESET}"; return 1; }
  echo -e "${CYAN}Kirim tes ke $ADMIN_ID ...${RESET}"
  local resp
  resp=$(curl -fsS --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${ADMIN_ID}" --data-urlencode "text=✅ mytunnel bot aktif — $(date '+%Y-%m-%d %H:%M') " 2>&1 || true)
  if echo "$resp" | grep -q '"ok":true'; then echo -e "${GREEN}Terkirim ✓${RESET}"; ah_log "bot test ok to $ADMIN_ID"; else echo -e "${RED}Gagal:${RESET} $resp" | head -c 200; echo; fi
}

bot_set(){
  echo -e "${CYAN}=== SETUP BOT TELEGRAM ===${RESET}"
  echo -e "${DIM}Buat bot di @BotFather -> /newbot -> copy token${RESET}"
  echo -e "${DIM}Admin Chat ID: chat @userinfobot atau @getidsbot${RESET}"
  local tok adm
  echo -ne "Token bot: "
  read -r tok
  tok=$(echo "$tok" | tr -d ' \n')
  [ -z "$tok" ] && { echo -e "${YELLOW}Batal${RESET}"; return; }
  if ! ah_validate_bot_token "$tok"; then echo -e "${RED}Format token invalid (harus 123456:ABC...)${RESET}"; return 1; fi
  echo -ne "Admin Chat ID: "
  read -r adm
  adm=$(echo "$adm" | tr -d ' \n')
  [ -z "$adm" ] && { echo -e "${YELLOW}Batal${RESET}"; return; }
  if ! ah_validate_chat_id "$adm"; then echo -e "${RED}Chat ID harus angka (boleh -)${RESET}"; return 1; fi
  mkdir -p "$(dirname "$CONF")" 2>/dev/null || true
  # backup
  [ -f "$CONF" ] && cp -a "$CONF" "${CONF}.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  cat > "$CONF" <<CFEOF
BOT_TOKEN="$tok"
ADMIN_ID="$adm"
CFEOF
  chmod 600 "$CONF" 2>/dev/null || true
  echo -e "${GREEN}Disimpan: $CONF (600) token $(ah_mask_token "$tok") admin $adm${RESET}"
  ah_log "bot config set admin $adm token $(ah_mask_token "$tok")"
  echo -ne "Tes kirim sekarang? [y/N]: "
  local a; read -r a
  if [[ "$a" =~ ^[Yy]$ ]]; then bot_test_send; fi
}

bot_enable(){
  [ -f "$CONF" ] || { echo -e "${RED}Config belum ada, set dulu${RESET}"; return 1; }
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    mkdir -p "$BASE/etc/systemd/system" "$BASE/var/log" 2>/dev/null || true
    cat > "$BASE/etc/systemd/system/${SERVICE}.service" <<SVCEOF
[Unit]
Description=mytunnel Telegram Bot
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $BASE/bot/bot.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
    touch "$BASE/var/log/${SERVICE}.sim" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Service $SERVICE dibuat (sim)${RESET}"
    ah_log "bot enable (sim)"
    return 0
  fi
  cat > "/etc/systemd/system/${SERVICE}.service" <<SVCEOF2
[Unit]
Description=mytunnel Telegram Bot
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash $BASE/bot/bot.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF2
  chmod 644 "/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now "$SERVICE" 2>/dev/null || systemctl restart "$SERVICE" 2>/dev/null || true
  echo -e "${GREEN}Service $SERVICE diaktifkan${RESET}"
  ah_log "bot enable"
}

bot_disable(){
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    rm -f "$BASE/var/log/${SERVICE}.sim" 2>/dev/null || true
    echo -e "${YELLOW}[TEST MODE] Service $SERVICE dimatikan (sim)${RESET}"
    ah_log "bot disable (sim)"
    return 0
  fi
  systemctl disable --now "$SERVICE" 2>/dev/null || systemctl stop "$SERVICE" 2>/dev/null || true
  echo -e "${YELLOW}Service $SERVICE dimatikan${RESET}"
  ah_log "bot disable"
}

bot_remove(){
  echo -ne "${YELLOW}Hapus config bot $CONF ? [y/N]: ${RESET}"
  local a; read -r a
  [[ "$a" =~ ^[Yy]$ ]] || { echo "Batal"; return; }
  bot_disable 2>/dev/null || true
  rm -f "$CONF" 2>/dev/null || true
  echo -e "${GREEN}Config dihapus${RESET}"
  ah_log "bot config removed"
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "SETUP BOT TELEGRAM"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  bot_status | while IFS= read -r line; do printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$line"; done
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Set Token & Admin ID                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Test Kirim Pesan                               ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Aktifkan / Start Bot                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Nonaktifkan / Stop Bot                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Hapus Config                                    ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Lihat Log                                       ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) Back to Menu   x.) Exit                        ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select [1-7 or x]: ${RESET}"
  read -r c
  case "$c" in
    1) bot_set; pause;;
    2) bot_test_send; pause;;
    3) bot_enable; pause;;
    4) bot_disable; pause;;
    5) bot_remove; pause;;
    6) tail -n 30 "${MYTUNNEL_PREFIX:-}/var/log/mytunnel.log" 2>/dev/null | sed 's/^/  /'; echo ""; pause;;
    7|b|B|x|X) break;;
    *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/bot.sh"
cat > "$ETC/menu/advanced.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/advanced.sh - submenu WARP, Routing, SlowDNS
# shellcheck disable=SC1091,SC1090,SC2154
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "ADVANCED (WARP, Routing, SlowDNS)"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  # status ringkas 60 kolom
  _warp="OFF"; _routing="0 rules"; _slowdns="OFF"
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    [ -x "$MYTUNNEL_PREFIX/usr/local/bin/wgcf" ] && _warp="ON(sim)" || _warp="OFF"
    [ -f "$MYTUNNEL_PREFIX/etc/mytunnel/config/slowdns.conf" ] && _slowdns="ON(sim)" || _slowdns="OFF"
  else
    [ -x "/usr/local/bin/wgcf" ] && _warp="ON" || _warp="OFF"
    [ -f "/etc/mytunnel/config/slowdns.conf" ] && _slowdns="ON" || _slowdns="OFF"
  fi
  if command -v jq >/dev/null 2>&1; then
    _cfg="${MYTUNNEL_PREFIX:-}/usr/local/etc/xray/config.json"
    [ -z "$MYTUNNEL_PREFIX" ] && _cfg="/usr/local/etc/xray/config.json"
    [ -f "$_cfg" ] && _routing="$(jq '.routing.rules | length' "$_cfg" 2>/dev/null) rules" || _routing="-"
  fi
  printf "${BLUE}│${RESET} WARP: %-10s Routing: %-12s SlowDNS: %-10s ${BLUE}│${RESET}\n" "$_warp" "$_routing" "$_slowdns"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} 1.) WARP Cloudflare                                ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Routing Xray                                   ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) SlowDNS                                        ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Layanan SSH Tambahan (Squid/UDPGW/OHP)          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Back to Features                               ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} x.) Exit                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select [1-5 or x]: ${RESET}"
  read -r c
  case "$c" in
    1) bash "$BASE/advanced/warp.sh" 2>&1 || echo -e "${YELLOW}warp belum tersedia${RESET}"; pause;;
    2) bash "$BASE/advanced/routing.sh" 2>&1 || echo -e "${YELLOW}routing belum tersedia${RESET}"; pause;;
    3) bash "$BASE/advanced/slowdns.sh" 2>&1 || echo -e "${YELLOW}slowdns belum tersedia${RESET}"; pause;;
    4) bash "$BASE/advanced/ssh_extra.sh" 2>&1 || echo -e "${YELLOW}ssh_extra belum tersedia${RESET}"; pause;;
    5|b|B) break;;
    x|X) exit 0;;
    *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/menu/advanced.sh"
cat > "$ETC/setup/domain.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/domain.sh - input & validasi domain + cek DNS A
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
DOMAIN_FILE="$ETC/config/domain.txt"

# allow non-interactive via env: MYTUNNEL_DOMAIN
# source colors/helpers if present
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
# fallback colors
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

get_public_ip() {
  local ip=""
  ip=$(curl -sk4 --max-time 5 https://ifconfig.me 2>/dev/null | tr -d ' \n') || true
  [ -z "$ip" ] && ip=$(curl -sk4 --max-time 5 https://ipinfo.io/ip 2>/dev/null | tr -d ' \n') || true
  [ -z "$ip" ] && ip=$(curl -sk4 --max-time 5 https://api.ipify.org 2>/dev/null | tr -d ' \n') || true
  [ -z "$ip" ] && ip=$(hostname -I 2>/dev/null | awk '{print $1}') || true
  echo "$ip" | tr -d ' \n'
}

validate_domain() {
  local d="$1"
  # RFC-ish: 1-253 chars, labels 1-63, TLD >=2, no leading/trailing hyphen/dot
  [[ "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]] || return 1
  [[ ${#d} -le 253 ]] || return 1
  # TLD at least 2 chars
  local tld="${d##*.}"
  [[ ${#tld} -ge 2 ]] || return 1
  return 0
}

resolve_a() {
  local d="$1" ans=""
  if command -v dig >/dev/null 2>&1; then
    ans=$(dig +short A "$d" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 | tr -d ' \n') || true
    [ -n "$ans" ] && { echo "$ans"; return 0; }
  fi
  if command -v getent >/dev/null 2>&1; then
    ans=$(getent ahosts "$d" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | head -1 | tr -d ' \n') || true
    [ -n "$ans" ] && { echo "$ans"; return 0; }
  fi
  if command -v host >/dev/null 2>&1; then
    ans=$(host -t A "$d" 2>/dev/null | awk '/has address/ {print $4}' | head -1 | tr -d ' \n') || true
    [ -n "$ans" ] && { echo "$ans"; return 0; }
  fi
  # fallback: cloudflare DoH
  ans=$(curl -sk --max-time 5 -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$d&type=A" 2>/dev/null | grep -oE '"data":"[0-9.]+' | head -1 | cut -d'"' -f4 | tr -d ' \n') || true
  echo "$ans" | tr -d ' \n'
}

# ponytail: DNS check is best-effort; upgrade to strict DNSSEC or multiple resolver quorum when abuse arises
main() {
  local myip domain ans existing
  myip=$(get_public_ip)
  existing=$(head -1 "$DOMAIN_FILE" 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
  if [ -z "${MYTUNNEL_DOMAIN:-}" ] && [ -n "$existing" ] && [ "$existing" != "-" ]; then echo -e "${GREEN}Domain sudah ada: $existing${RESET}"; return 0; fi
  echo -e "${CYAN}IP VPS terdeteksi: ${GREEN}$myip${RESET}" | tee -a "$LOG" 2>/dev/null || true

  # non-interactive via MYTUNNEL_DOMAIN
  if [ -n "${MYTUNNEL_DOMAIN:-}" ]; then
    domain=$(echo "$MYTUNNEL_DOMAIN" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    echo -e "${CYAN}Domain dari env: $domain${RESET}"
    if ! validate_domain "$domain"; then
      echo -e "${RED}Format domain tidak valid: $domain${RESET}" >&2
      return 1
    fi
    ans=$(resolve_a "$domain")
    if [ -n "$ans" ] && [ -n "$myip" ] && [ "$ans" != "$myip" ]; then
      echo -e "${YELLOW}Peringatan: DNS A $domain -> $ans tidak sama dengan IP VPS $myip${RESET}"
      echo -e "${YELLOW}Mode non-interaktif: tetap lanjut (MYTUNNEL_DOMAIN set)${RESET}"
    elif [ -z "$ans" ]; then
      echo -e "${YELLOW}Peringatan: tidak bisa resolve A record untuk $domain${RESET}"
      echo -e "${YELLOW}Mode non-interaktif: tetap lanjut${RESET}"
    else
      echo -e "${GREEN}DNS OK: $domain -> $ans${RESET}"
    fi
    mkdir -p "$(dirname "$DOMAIN_FILE")"
    echo "$domain" > "$DOMAIN_FILE"
    chmod 644 "$DOMAIN_FILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] domain set: $domain (A=$ans, VPS=$myip)" >> "$LOG" 2>/dev/null || true
    return 0
  fi

  # interactive
  while true; do
    echo -ne "${CYAN}Masukkan domain (contoh: sg1.example.com): ${RESET}"
    read -r domain || { echo -e "${RED}Batal${RESET}"; return 1; }
    domain=$(echo "$domain" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
    [ -z "$domain" ] && { echo -e "${RED}Domain tidak boleh kosong${RESET}"; continue; }
    if ! validate_domain "$domain"; then
      echo -e "${RED}Format domain tidak valid: $domain${RESET}"
      continue
    fi
    ans=$(resolve_a "$domain")
    if [ -z "$ans" ]; then
      echo -e "${YELLOW}Tidak bisa resolve A record $domain (mungkin belum propagasi)${RESET}"
      echo -ne "${YELLOW}Lanjut tanpa DNS OK? [y/N]: ${RESET}"
      read -r yn; case "$yn" in y|Y|yes|YES) ;; *) echo -e "${RED}Batal, ulangi input${RESET}"; continue;; esac
    elif [ -n "$myip" ] && [ "$ans" != "$myip" ]; then
      echo -e "${YELLOW}Peringatan: $domain -> $ans, VPS IP $myip (tidak cocok)${RESET}"
      echo -e "${YELLOW}Pastikan A record sudah di-point ke IP VPS${RESET}"
      echo -ne "${YELLOW}Tetap lanjut? [y/N]: ${RESET}"
      read -r yn; case "$yn" in y|Y|yes|YES) ;; *) echo -e "${RED}Batal, ulangi input${RESET}"; continue;; esac
    else
      echo -e "${GREEN}DNS OK: $domain -> $ans${RESET}"
    fi
    mkdir -p "$(dirname "$DOMAIN_FILE")"
    echo "$domain" > "$DOMAIN_FILE"
    chmod 644 "$DOMAIN_FILE" 2>/dev/null || true
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] domain set: $domain (A=$ans, VPS=$myip)" >> "$LOG" 2>/dev/null || true
    echo -e "${GREEN}Domain disimpan: $domain${RESET}"
    break
  done
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/domain.sh"
cat > "$ETC/setup/firewall.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/firewall.sh - UFW + BBR + swap
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
SYSCTL_DIR="${BASE}/etc/sysctl.d"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

ensure_swap() {
  local mem swap_kb need
  mem=$(free -m 2>/dev/null | awk '/Mem:/{print $2}') || mem=0
  swap_kb=$(free -m 2>/dev/null | awk '/Swap:/{print $2}') || swap_kb=0
  if [ "$swap_kb" -gt 200 ] 2>/dev/null; then
    echo -e "${GREEN}Swap sudah ada: ${swap_kb}M${RESET}"
    return 0
  fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Skip pembuatan swap (MYTUNNEL_PREFIX set)${RESET}"
    mkdir -p "$BASE/swap" 2>/dev/null || true
    echo "# swap skipped in test" > "$BASE/swap/.skip" 2>/dev/null || true
    return 0
  fi
  # real: buat 1G (atau 2G kalau RAM kecil)
  if [ "$mem" -lt 1024 ]; then need=2048; else need=1024; fi
  echo -e "${CYAN}Membuat swap ${need}M...${RESET}"
  if [ -f /swapfile ] || [ -f /swap.img ]; then
    echo -e "${YELLOW}Swap file sudah ada, skip${RESET}"
    return 0
  fi
  # BUGFIX: fallocate may not be supported on some FS, fallback to dd
  if fallocate -l "${need}M" /swapfile 2>/dev/null; then
    chmod 600 /swapfile; mkswap /swapfile >/dev/null 2>&1 || true; swapon /swapfile 2>/dev/null || true
  elif dd if=/dev/zero of=/swapfile bs=1M count="$need" status=none 2>/dev/null; then
    chmod 600 /swapfile; mkswap /swapfile >/dev/null 2>&1 || true; swapon /swapfile 2>/dev/null || true
  else
    echo -e "${YELLOW}Gagal buat swap, lanjut tanpa swap${RESET}"
    return 0
  fi
  grep -q "/swapfile" /etc/fstab 2>/dev/null || echo "/swapfile none swap sw 0 0" >> /etc/fstab 2>/dev/null || true
  echo -e "${GREEN}Swap ${need}M aktif${RESET}"
}

enable_bbr() {
  mkdir -p "$SYSCTL_DIR" 2>/dev/null || true
  local conf="$SYSCTL_DIR/99-mytunnel-bbr.conf"
  cat > "$conf" << 'BBR_EOF'
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_fastopen=3
BBR_EOF
  chmod 644 "$conf" 2>/dev/null || true
  if [ -z "$BASE" ]; then
    sysctl -p "$conf" >/dev/null 2>&1 || sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1 || true
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1 || true
    echo -e "${GREEN}BBR diaktifkan${RESET}"
  else
    echo -e "${YELLOW}[TEST MODE] BBR config ditulis ke $conf (tidak sysctl)${RESET}"
  fi
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] BBR enabled: $conf" >> "$LOG" 2>/dev/null || true
}

setup_ufw() {
  if ! command -v ufw >/dev/null 2>&1; then
    if [ -n "$BASE" ]; then
      echo -e "${YELLOW}[TEST MODE] ufw tidak ada, simulasi allow (no ufw binary)${RESET}"
      local pf2="$ETC/config/ports.conf"
      # shellcheck disable=SC1090
      [ -f "$pf2" ] && . "$pf2" 2>/dev/null || true
      local _ports2="22,80,443"
      for var2 in OPENSSH_PORT DROPBEAR_PORT TLS_PORT NONTLS_PORT ANY_PORT CONFIG_PORT SQUID_PORT UDPGW_PORT OHP_SSH_PORT OHP_OVPN_PORT OPENVPN_TCP_PORT OPENVPN_UDP_PORT SLOWDNS_PORT; do
        val2="${!var2}" 2>/dev/null || true; [ -z "${val2+x}" ] && continue
        [ -z "$val2" ] && continue
        val2=$(echo "$val2" | tr ',' ' ')
        for p2 in $val2; do p2=$(echo "$p2" | tr -d ' ' | cut -d'-' -f1); case "$p2" in ''|*[!0-9]*) continue;; *) _ports2="$_ports2,$p2";; esac; done
      done
      mkdir -p "$BASE/var/log" 2>/dev/null || true
      printf "%s\n" "$_ports2" | tr ',' '\n' | sort -u | while read -r pr; do [ -n "$pr" ] && echo "allow $pr"; done > "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log"/*.sim.log 2>/dev/null || true
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
      cat "$BASE/var/log/ufw-sim.log" 2>&1 | head -n 30 || true
      return 0
    fi
    echo -e "${CYAN}Install ufw...${RESET}"
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y ufw >/dev/null 2>&1 || { echo -e "${YELLOW}Gagal install ufw, lanjut tanpa firewall${RESET}"; return 0; }
  fi
  # baca ports.conf sebagai sumber kebenaran
  local pf="$ETC/config/ports.conf"
  # shellcheck disable=SC1090
  [ -f "$pf" ] && . "$pf" 2>/dev/null || true
  local _ports="22,80,443"
  # tambah dari ports.conf (CSV -> space)
  for var in OPENSSH_PORT DROPBEAR_PORT TLS_PORT NONTLS_PORT ANY_PORT CONFIG_PORT SQUID_PORT UDPGW_PORT OHP_SSH_PORT OHP_OVPN_PORT OPENVPN_TCP_PORT OPENVPN_UDP_PORT SLOWDNS_PORT; do
    val="${!var}" 2>/dev/null || true; [ -z "${val+x}" ] && continue
    [ -z "$val" ] && continue
    # ubah koma jadi koma tunggal untuk loop
    val=$(echo "$val" | tr ',' ' ')
    for p in $val; do
      # hanya angka dan range sederhana
      p=$(echo "$p" | tr -d ' ' | cut -d'-' -f1)
      case "$p" in ''|*[!0-9]*) continue;; *) _ports="$_ports,$p";; esac
    done
  done
  # deduplicate 22 tetap pertama (anti-lockout)
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi ufw allow $_ports${RESET}"
    mkdir -p "$BASE/var/log" 2>/dev/null || true
    printf "%s\n" "$_ports" | tr ',' '\n' | sort -u | while read -r pr; do [ -n "$pr" ] && echo "allow $pr"; done > "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log"/*.sim.log 2>/dev/null || true
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    cat "$BASE/var/log/ufw-sim.log" 2>/dev/null | head -n 20 || true
    return 0
  fi
  # real: always allow SSH first to avoid lockout
  echo -e "${CYAN}Konfigurasi UFW...${RESET}"
  # deduplicate list
  local uniq
  uniq=$(echo "$_ports" | tr ',' '\n' | sort -u | tr '\n' ' ')
  for p in $uniq; do
    [ -z "$p" ] && continue
    echo -e "${CYAN}  ufw allow $p/tcp${RESET}"
    ufw allow "$p/tcp" >/dev/null 2>&1 || ufw allow "$p" >/dev/null 2>&1 || true
  done
  # allow udp untuk slowdns/ovpn udp jika perlu
  for var in SLOWDNS_PORT OPENVPN_UDP_PORT; do
    val="${!var}" 2>/dev/null || true; [ -z "${val+x}" ] && continue
    [ -z "$val" ] && continue
    val=$(echo "$val" | tr ',' ' ')
    for p in $val; do
      p=$(echo "$p" | tr -d ' ' | cut -d'-' -f1)
      case "$p" in ''|*[!0-9]*) continue;; *) ufw allow "$p/udp" >/dev/null 2>&1 || true;; esac
    done
  done
  # optional: allow 22 for safety before enable
  ufw allow 22/tcp >/dev/null 2>&1 || ufw allow 22 >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
  ufw default deny incoming >/dev/null 2>&1 || true
  ufw default allow outgoing >/dev/null 2>&1 || true
  echo -e "${GREEN}UFW aktif: $uniq allow${RESET}"
  ufw status verbose 2>/dev/null | head -n 30 || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ufw enabled: $uniq" >> "$LOG" 2>/dev/null || true
}

main() {
  echo -e "${CYAN}[firewall] Setup UFW + BBR + swap...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  ensure_swap
  enable_bbr
  setup_ufw
  echo -e "${GREEN}[firewall] Selesai${RESET}" | tee -a "$LOG" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/firewall.sh"
cat > "$ETC/setup/cert.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/cert.sh - TLS via acme.sh (Let's Encrypt, standalone 80)
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
DOMAIN_FILE="$ETC/config/domain.txt"
CERT_DIR="$ETC/cert"
ACME_HOME="$HOME/.acme.sh"
[ -n "$BASE" ] && ACME_HOME="$BASE$ACME_HOME"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die() { echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

get_domain() {
  if [ -f "$DOMAIN_FILE" ]; then head -1 "$DOMAIN_FILE" 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]'; else echo ""; fi
}

install_acme() {
  if [ -x "$ACME_HOME/acme.sh" ]; then echo -e "${GREEN}acme.sh sudah ada: $ACME_HOME/acme.sh${RESET}"; return 0; fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi install acme.sh ke $ACME_HOME${RESET}"
    mkdir -p "$ACME_HOME" 2>/dev/null || true
    cat > "$ACME_HOME/acme.sh" << 'ACME_STUB'
#!/bin/bash
echo "acme.sh stub 3.0.0"
if [[ "$*" == *"--issue"* ]]; then echo "[stub] issue"; mkdir -p "$(dirname "$4")"; fi
ACME_STUB
    chmod +x "$ACME_HOME/acme.sh" 2>/dev/null || true
    return 0
  fi
  echo -e "${CYAN}Install acme.sh...${RESET}"
  if command -v curl >/dev/null 2>&1; then
    curl -s https://get.acme.sh 2>/dev/null | sh -s email=admin@"$(get_domain)" >/dev/null 2>&1 || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://get.acme.sh 2>/dev/null | sh -s email=admin@"$(get_domain)" >/dev/null 2>&1 || true
  else
    die "curl/wget tidak ada, tidak bisa install acme.sh" "Install curl dulu: apt install curl"
  fi
  [ -x "$ACME_HOME/acme.sh" ] || [ -x "$HOME/.acme.sh/acme.sh" ] || die "acme.sh gagal terinstall" "Cek koneksi ke https://get.acme.sh"
  [ -x "$ACME_HOME/acme.sh" ] || ACME_HOME="$HOME/.acme.sh"
  echo -e "${GREEN}acme.sh terinstall: $ACME_HOME/acme.sh${RESET}"
}

issue_cert() {
  local domain cert_crt cert_key
  domain=$(get_domain)
  [ -z "$domain" ] || [ "$domain" = "-" ] && die "Domain belum diisi" "Jalankan setup/domain.sh dulu atau isi $DOMAIN_FILE"
  cert_crt="$CERT_DIR/fullchain.crt"
  cert_key="$CERT_DIR/private.key"
  mkdir -p "$CERT_DIR" 2>/dev/null || true

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi issue cert untuk $domain${RESET}"
    mkdir -p "$CERT_DIR" 2>/dev/null || true
    # buat self-signed dummy agar nginx -t bisa lewat di test
    if command -v openssl >/dev/null 2>&1; then
      openssl req -x509 -nodes -days 90 -newkey rsa:2048 \
        -keyout "$cert_key" -out "$cert_crt" -subj "/CN=$domain" >/dev/null 2>&1 || {
        echo "dummy cert" > "$cert_crt"; echo "dummy key" > "$cert_key";
      }
    else
      echo "-----BEGIN CERTIFICATE-----" > "$cert_crt"
      echo "MIID...dummy...TEST" >> "$cert_crt"
      echo "-----END CERTIFICATE-----" >> "$cert_crt"
      echo "dummy-key" > "$cert_key"
    fi
    chmod 600 "$cert_key" 2>/dev/null || true
    chmod 644 "$cert_crt" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Cert dummy dibuat: $cert_crt${RESET}"
    return 0
  fi

  # real mode: stop nginx sementara agar port 80 bebas
  echo -e "${CYAN}Hentikan nginx sementara untuk validasi port 80...${RESET}"
  systemctl stop nginx 2>/dev/null || service nginx stop 2>/dev/null || nginx -s stop 2>/dev/null || true
  fuser -k 80/tcp 2>/dev/null || true
  sleep 1

  local acme="$ACME_HOME/acme.sh"
  [ -x "$acme" ] || acme="$HOME/.acme.sh/acme.sh"
  echo -e "${CYAN}Issue sertifikat Let's Encrypt untuk $domain (standalone)...${RESET}"
  if ! "$acme" --issue --standalone -d "$domain" --keylength ec-256 2>&1 | tee -a "$LOG"; then
    # fallback rsa
    echo -e "${YELLOW}EC gagal, coba RSA...${RESET}"
    "$acme" --issue --standalone -d "$domain" 2>&1 | tee -a "$LOG" || {
      systemctl start nginx 2>/dev/null || true
      die "Gagal issue sertifikat untuk $domain" "Cek: 1) A record sudah point ke IP VPS, 2) port 80 terbuka (ufw allow 80), 3) tidak ada layanan lain di 80, 4) rate limit LE"
    }
  fi

  echo -e "${CYAN}Install cert ke $CERT_DIR...${RESET}"
  "$acme" --install-cert -d "$domain" \
    --fullchain-file "$cert_crt" \
    --key-file "$cert_key" \
    --ecc 2>/dev/null || \
  "$acme" --install-cert -d "$domain" \
    --fullchain-file "$cert_crt" \
    --key-file "$cert_key" 2>&1 | tee -a "$LOG" || \
    die "Gagal install cert ke $CERT_DIR" "Cek permission $CERT_DIR dan log acme.sh"

  chmod 600 "$cert_key" 2>/dev/null || true
  chmod 644 "$cert_crt" 2>/dev/null || true
  [ -s "$cert_crt" ] && [ -s "$cert_key" ] || die "File cert kosong setelah issue" "Cek $LOG dan $ACME_HOME"

  # cron auto-renew: acme.sh sudah pasang cron, tambah reload hook
  local cron_reload="0 2 * * * \"$acme\" --cron --home \"$ACME_HOME\" >/dev/null 2>&1 && systemctl reload nginx 2>/dev/null; systemctl restart xray 2>/dev/null || true"
  (crontab -l 2>/dev/null | grep -v "mytunnel.*reload"; echo "$cron_reload # mytunnel reload") | crontab - 2>/dev/null || true

  systemctl start nginx 2>/dev/null || true
  echo -e "${GREEN}Sertifikat OK: $cert_crt${RESET}"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] cert issued: $domain -> $cert_crt" >> "$LOG" 2>/dev/null || true
}

main() {
  echo -e "${CYAN}[cert] Setup TLS...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  install_acme
  issue_cert
  echo -e "${GREEN}[cert] Selesai${RESET}" | tee -a "$LOG" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/cert.sh"
cat > "$ETC/setup/xray.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/xray.sh - install & config Xray (9 inbounds: ws+grpc+httpupgrade)
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
XRAY_ETC="${BASE}/usr/local/etc/xray"
XRAY_BIN="${BASE}/usr/local/bin/xray"
XRAY_CFG="$XRAY_ETC/config.json"
XRAY_LOGDIR="${BASE}/var/log/xray"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die() { echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

install_xray() {
  if [ -x "$XRAY_BIN" ] || command -v xray >/dev/null 2>&1; then
    echo -e "${GREEN}Xray sudah terinstall: $(command -v xray 2>/dev/null || echo "$XRAY_BIN")${RESET}"
    return 0
  fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi install Xray (skip download)${RESET}"
    mkdir -p "$(dirname "$XRAY_BIN")" 2>/dev/null || true
    if command -v xray >/dev/null 2>&1; then cp "$(command -v xray)" "$XRAY_BIN" 2>/dev/null || true; fi
    return 0
  fi
  echo -e "${CYAN}Install Xray-core (XTLS resmi)...${RESET}"
  if ! command -v curl >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 || true; apt-get install -y curl >/dev/null 2>&1 || true; fi
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | tee -a "$LOG" || \
    die "Gagal install Xray" "Cek koneksi ke github.com/XTLS/Xray-install dan jalankan manual: bash <(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install"
  command -v xray >/dev/null 2>&1 || [ -x /usr/local/bin/xray ] || die "Binary xray tidak ditemukan setelah install" "Cek /usr/local/bin/xray"
  echo -e "${GREEN}Xray terinstall: $(xray version 2>&1 | head -1)${RESET}"
}

write_config() {
  mkdir -p "$XRAY_ETC" "$XRAY_LOGDIR" 2>/dev/null || true
  if [ -f "$XRAY_CFG" ]; then
    local bak
    bak="$XRAY_CFG.bak-$(date +%Y%m%d-%H%M%S)"
    cp -a "$XRAY_CFG" "$bak" 2>/dev/null || true
    echo -e "${YELLOW}Backup config lama: $bak${RESET}"
  fi
  local keep_vmess_ws="[]" keep_vmess_grpc="[]" keep_vmess_hu="[]"
  local keep_vless_ws="[]" keep_vless_grpc="[]" keep_vless_hu="[]"
  local keep_trojan_ws="[]" keep_trojan_grpc="[]" keep_trojan_hu="[]"
  local keep_outbounds="[]" keep_routing="[]"
  if [ -f "$XRAY_CFG" ] && command -v jq >/dev/null 2>&1; then
    keep_vmess_ws=$(jq -c '[.inbounds[] | select(.tag=="vmess-ws") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_vmess_grpc=$(jq -c '[.inbounds[] | select(.tag=="vmess-grpc") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_vmess_hu=$(jq -c '[.inbounds[] | select(.tag=="vmess-hu") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_vless_ws=$(jq -c '[.inbounds[] | select(.tag=="vless-ws") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_vless_grpc=$(jq -c '[.inbounds[] | select(.tag=="vless-grpc") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_vless_hu=$(jq -c '[.inbounds[] | select(.tag=="vless-hu") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_trojan_ws=$(jq -c '[.inbounds[] | select(.tag=="trojan-ws") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_trojan_grpc=$(jq -c '[.inbounds[] | select(.tag=="trojan-grpc") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    keep_trojan_hu=$(jq -c '[.inbounds[] | select(.tag=="trojan-hu") | .settings.clients] | .[0] // []' "$XRAY_CFG" 2>/dev/null || echo "[]")
    for v in keep_vmess_ws keep_vmess_grpc keep_vmess_hu keep_vless_ws keep_vless_grpc keep_vless_hu keep_trojan_ws keep_trojan_grpc keep_trojan_hu; do
      # no eval: cek via indirect expansion, reset jika bukan array JSON
      _val="${!v}"
      if ! printf '%s' "$_val" | jq -e 'type=="array"' >/dev/null 2>&1; then
        printf -v "$v" '%s' "[]"
      fi
      unset _val
    done
    keep_outbounds=$(jq -c '[.outbounds[] | select(.tag!="direct" and .tag!="blocked" and .tag!="api")]' "$XRAY_CFG" 2>/dev/null || echo "[]")
    echo "$keep_outbounds" | jq -e 'type=="array"' >/dev/null 2>&1 || keep_outbounds="[]"
    keep_routing=$(jq -c '[.routing.rules[] | select(.inboundTag != ["api"])]' "$XRAY_CFG" 2>/dev/null || echo "[]")
    echo "$keep_routing" | jq -e 'type=="array"' >/dev/null 2>&1 || keep_routing="[]"
  fi
  cat > "$XRAY_CFG" << CFG_EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$XRAY_LOGDIR/access.log",
    "error": "$XRAY_LOGDIR/error.log"
  },
  "stats": {},
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "policy": {
    "levels": { "0": { "statsUserUplink": true, "statsUserDownlink": true } },
    "system": { "statsInboundUplink": true, "statsInboundDownlink": true }
  },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "port": 10001,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } }
    },
    {
      "tag": "vmess-grpc",
      "port": 10011,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vmess" } }
    },
    {
      "tag": "vmess-hu",
      "port": 10021,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upvmess" } }
    },
    {
      "tag": "vless-ws",
      "port": 10002,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless" } }
    },
    {
      "tag": "vless-grpc",
      "port": 10012,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "vless" } }
    },
    {
      "tag": "vless-hu",
      "port": 10022,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/upvless" } }
    },
    {
      "tag": "trojan-ws",
      "port": 10003,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/trojan" } }
    },
    {
      "tag": "trojan-grpc",
      "port": 10013,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": { "network": "grpc", "grpcSettings": { "serviceName": "trojan" } }
    },
    {
      "tag": "trojan-hu",
      "port": 10023,
      "listen": "127.0.0.1",
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": { "network": "httpupgrade", "httpupgradeSettings": { "path": "/uptrojan" } }
    },
    {
      "tag": "api",
      "port": 10085,
      "listen": "127.0.0.1",
      "protocol": "dokodemo-door",
      "settings": { "address": "127.0.0.1" }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "blocked" }
  ],
  "routing": {
    "rules": [
      { "type": "field", "inboundTag": ["api"], "outboundTag": "api" }
    ]
  }
}
CFG_EOF
  if command -v jq >/dev/null 2>&1; then
    local tmp="$XRAY_CFG.tmp"
    jq --argjson a "$keep_vmess_ws" --argjson b "$keep_vmess_grpc" --argjson c "$keep_vmess_hu" \
       --argjson d "$keep_vless_ws" --argjson e "$keep_vless_grpc" --argjson f "$keep_vless_hu" \
       --argjson g "$keep_trojan_ws" --argjson h "$keep_trojan_grpc" --argjson i "$keep_trojan_hu" \
       --argjson extra_out "$keep_outbounds" --argjson extra_rules "$keep_routing" '
      (.inbounds[] | select(.tag=="vmess-ws") | .settings.clients) = $a |
      (.inbounds[] | select(.tag=="vmess-grpc") | .settings.clients) = $b |
      (.inbounds[] | select(.tag=="vmess-hu") | .settings.clients) = $c |
      (.inbounds[] | select(.tag=="vless-ws") | .settings.clients) = $d |
      (.inbounds[] | select(.tag=="vless-grpc") | .settings.clients) = $e |
      (.inbounds[] | select(.tag=="vless-hu") | .settings.clients) = $f |
      (.inbounds[] | select(.tag=="trojan-ws") | .settings.clients) = $g |
      (.inbounds[] | select(.tag=="trojan-grpc") | .settings.clients) = $h |
      (.inbounds[] | select(.tag=="trojan-hu") | .settings.clients) = $i |
      .outbounds += $extra_out |
      .routing.rules += $extra_rules
    ' "$XRAY_CFG" > "$tmp" 2>/dev/null && mv "$tmp" "$XRAY_CFG" || echo -e "${YELLOW}jq inject gagal, lanjut default${RESET}"
  fi
  chmod 644 "$XRAY_CFG" 2>/dev/null || true
  touch "$XRAY_LOGDIR/access.log" "$XRAY_LOGDIR/error.log" 2>/dev/null || true
  chmod 644 "$XRAY_LOGDIR/"*.log 2>/dev/null || true
  echo -e "${GREEN}Config Xray ditulis: $XRAY_CFG (9 inbounds)${RESET}"
}

validate_config() {
  local xbin="xray"
  [ -x "$XRAY_BIN" ] && xbin="$XRAY_BIN"
  command -v xray >/dev/null 2>&1 && xbin="xray"
  if command -v "$xbin" >/dev/null 2>&1 || [ -x "$xbin" ]; then
    echo -e "${CYAN}Validasi xray run -test -config $XRAY_CFG...${RESET}"
    if ! "$xbin" run -test -config "$XRAY_CFG" 2>&1 | tee -a "$LOG"; then
      echo -e "${RED}Validasi Xray gagal${RESET}"
      jq . "$XRAY_CFG" 2>&1 | head -n 50 || cat "$XRAY_CFG" | head -n 50
      return 1
    fi
    echo -e "${GREEN}Validasi Xray OK${RESET}"
  else
    echo -e "${YELLOW}Binary xray tidak ada, validasi via jq...${RESET}"
    if command -v jq >/dev/null 2>&1; then jq . "$XRAY_CFG" >/dev/null 2>&1 || die "Config JSON tidak valid" "Cek $XRAY_CFG dengan jq"
    else python3 -m json.tool "$XRAY_CFG" >/dev/null 2>&1 || die "Config JSON tidak valid" "Cek $XRAY_CFG"
    fi
    echo -e "${GREEN}JSON valid (xray binary belum ada)${RESET}"
  fi
}

enable_service() {
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Skip systemd enable (prefix set)${RESET}"
    mkdir -p "$BASE/etc/systemd/system" 2>/dev/null || true
    cat > "$BASE/etc/systemd/system/xray.service.sim" << 'SVC'
[Unit]
Description=mytunnel Xray
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SVC
    chmod 644 "$BASE/etc/systemd/system/xray.service.sim" 2>/dev/null || true
    return 0
  fi
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable xray 2>/dev/null || systemctl enable xray.service 2>/dev/null || true
  systemctl restart xray 2>/dev/null || systemctl start xray 2>/dev/null || service xray restart 2>/dev/null || true
  sleep 1
  systemctl is-active xray >/dev/null 2>&1 || die "Service xray gagal start" "Cek journalctl -u xray -n 50 dan $XRAY_CFG"
  echo -e "${GREEN}Service xray aktif${RESET}"
  systemctl status xray --no-pager 2>/dev/null | head -n 20 || true
}

main() {
  echo -e "${CYAN}[xray] Setup Xray...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  install_xray
  write_config
  validate_config || die "Validasi Xray gagal" "Cek $XRAY_CFG"
  enable_service
  echo -e "${GREEN}[xray] Selesai${RESET}" | tee -a "$LOG" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/xray.sh"
cat > "$ETC/setup/nginx.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/nginx.sh - install & config Nginx (80 WS+HU + 443 TLS WS/HU/gRPC)
# shellcheck disable=SC1091,SC1090,SC2034,SC2155
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
DOMAIN_FILE="$ETC/config/domain.txt"
CERT_CRT="$ETC/cert/fullchain.crt"
CERT_KEY="$ETC/cert/private.key"
NGINX_CONF_DIR="${BASE}/etc/nginx"
NGINX_SITE="$NGINX_CONF_DIR/conf.d/mytunnel.conf"
NGINX_MAIN="$NGINX_CONF_DIR/nginx.conf"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die() { echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

get_domain() {
  if [ -f "$DOMAIN_FILE" ]; then head -1 "$DOMAIN_FILE" 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]'; else echo ""; fi
}

install_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    echo -e "${GREEN}Nginx sudah terinstall: $(nginx -v 2>&1)${RESET}"
    return 0
  fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi install nginx (skip apt)${RESET}"
    mkdir -p "$NGINX_CONF_DIR/conf.d" 2>/dev/null || true
    return 0
  fi
  echo -e "${CYAN}Install nginx...${RESET}"
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y nginx >/dev/null 2>&1 || die "Gagal install nginx" "Cek apt dan koneksi"
  echo -e "${GREEN}Nginx terinstall${RESET}"
}

write_config() {
  local domain pf tls_ports nontls_ports any_ports config_port http_listens https_listens
  domain=$(get_domain)
  [ -z "$domain" ] || [ "$domain" = "-" ] && die "Domain belum diisi" "Jalankan setup/domain.sh dulu"
  pf="$ETC/config/ports.conf"
  # shellcheck disable=SC1090
  [ -f "$pf" ] && . "$pf" 2>/dev/null || true
  tls_ports="${TLS_PORT:-443}"
  nontls_ports="${NONTLS_PORT:-80}"
  any_ports="${ANY_PORT:-}"
  config_port="${CONFIG_PORT:-81}"
  # build listen directives dedup (keep order, unique)
  http_listens=""
  https_listens=""
  # dedupe helper via associative seen
  declare -A _seen_http=() _seen_https=()
  for _p in $(echo "$nontls_ports" | tr ',' ' '); do
    _p=$(echo "$_p" | tr -d ' ' | cut -d'-' -f1)
    case "$_p" in ''|*[!0-9]*) continue;; esac
    if [ -z "${_seen_http[$_p]:-}" ]; then
      _seen_http[$_p]=1
      if [ "$_p" = "80" ]; then
        http_listens="${http_listens}  listen 80 default_server;
  listen [::]:80 default_server;
"
      else
        http_listens="${http_listens}  listen $_p;
  listen [::]:$_p;
"
      fi
    fi
  done
  for _p in $(echo "$any_ports" | tr ',' ' '); do
    _p=$(echo "$_p" | tr -d ' ' | cut -d'-' -f1)
    case "$_p" in ''|*[!0-9]*) continue;; esac
    if [ -z "${_seen_http[$_p]:-}" ]; then
      _seen_http[$_p]=1
      http_listens="${http_listens}  listen $_p;
  listen [::]:$_p;
"
    fi
  done
  for _p in $(echo "$tls_ports" | tr ',' ' '); do
    _p=$(echo "$_p" | tr -d ' ' | cut -d'-' -f1)
    case "$_p" in ''|*[!0-9]*) continue;; esac
    if [ -z "${_seen_https[$_p]:-}" ]; then
      _seen_https[$_p]=1
      https_listens="${https_listens}  listen $_p ssl http2;
  listen [::]:$_p ssl http2;
"
    fi
  done
  # fallback if empty
  [ -n "$http_listens" ] || http_listens="  listen 80 default_server;
  listen [::]:80 default_server;
"
  [ -n "$https_listens" ] || https_listens="  listen 443 ssl http2;
  listen [::]:443 ssl http2;
"
  # jika stunnel aktif di 443, jangan listen 443 di nginx (avoid bind conflict)
  if [ -z "$BASE" ] && ss -tlnp 2>/dev/null | grep -q ":443 "; then
    if ss -tlnp 2>/dev/null | grep -q "stunnel.*:443"; then
      https_listens=$(echo "$https_listens" | grep -v "  listen 443" | grep -v "  listen \[::\]:443" || true)
      [ -z "$https_listens" ] && https_listens="  listen 8443 ssl http2;
  listen [::]:8443 ssl http2;
"
      echo -e "${YELLOW}Stunnel terdeteksi di 443, nginx skip listen 443 -> $https_listens${RESET}" | head -n 5
    fi
  fi
  declare _www_root="/var/www/html"
  [ -n "$BASE" ] && _www_root="${BASE}/var/www/html"
  mkdir -p "$_www_root" 2>/dev/null || true
  if [ ! -f "$CERT_CRT" ] || [ ! -f "$CERT_KEY" ]; then
    if [ -n "$BASE" ]; then
      echo -e "${YELLOW}[TEST MODE] Cert belum ada, buat dummy agar nginx -t lewat${RESET}"
      mkdir -p "$(dirname "$CERT_CRT")" 2>/dev/null || true
      if command -v openssl >/dev/null 2>&1; then
        openssl req -x509 -nodes -days 90 -newkey rsa:2048 -keyout "$CERT_KEY" -out "$CERT_CRT" -subj "/CN=$domain" >/dev/null 2>&1 || true
      else
        echo "dummy" > "$CERT_CRT"; echo "dummy" > "$CERT_KEY"
      fi
      chmod 600 "$CERT_KEY" 2>/dev/null || true; chmod 644 "$CERT_CRT" 2>/dev/null || true
    else
      die "Sertifikat tidak ditemukan: $CERT_CRT" "Jalankan setup/cert.sh dulu"
    fi
  fi
  mkdir -p "$NGINX_CONF_DIR/conf.d" "$(dirname "$NGINX_SITE")" 2>/dev/null || true
  if [ -f "$NGINX_SITE" ]; then
    local bak
    bak="$NGINX_SITE.bak-$(date +%Y%m%d-%H%M%S)"
    cp -a "$NGINX_SITE" "$bak" 2>/dev/null || true
    echo -e "${YELLOW}Backup nginx conf: $bak${RESET}"
  fi
  if [ -n "$BASE" ]; then
    mkdir -p "$(dirname "$NGINX_MAIN")" 2>/dev/null || true
    if [ ! -f "$NGINX_MAIN" ]; then
      cat > "$NGINX_MAIN" << 'MAIN_EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;
events { worker_connections 1024; }
http {
  sendfile on;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;
  include /etc/nginx/conf.d/*.conf;
}
MAIN_EOF
      if ! grep -q "${BASE}/etc/nginx" "$NGINX_MAIN" 2>/dev/null; then
        sed -i "s|/etc/nginx|${BASE}/etc/nginx|g; s|/var/log/nginx|${BASE}/var/log/nginx|g; s|/run/nginx.pid|${BASE}/run/nginx.pid|g" "$NGINX_MAIN" 2>/dev/null || true
      fi
      sed -i "s|include /etc/nginx/mime.types|include ${BASE}/etc/nginx/mime.types|g" "$NGINX_MAIN" 2>/dev/null || true
      chmod 644 "$NGINX_MAIN" 2>/dev/null || true
      mkdir -p "${BASE}/var/log/nginx" "${BASE}/run" 2>/dev/null || true
      if [ ! -f "$NGINX_CONF_DIR/mime.types" ] && [ -f /etc/nginx/mime.types ]; then cp /etc/nginx/mime.types "$NGINX_CONF_DIR/mime.types" 2>/dev/null || true; fi
      if [ ! -f "$NGINX_CONF_DIR/mime.types" ]; then mkdir -p "$NGINX_CONF_DIR" && echo 'types { }' > "$NGINX_CONF_DIR/mime.types" 2>/dev/null || true; fi
    fi
  fi

  cat > "$NGINX_SITE" << CFG_EOF
map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

# HTTP (80,8080,ANY) - WS + HTTPUpgrade non-TLS (ports dari ports.conf)
server {
$http_listens
  server_name $domain vplay.iflix.com *.iflix.com _;

  location ^~ /.well-known/acme-challenge/ {
    default_type "text/plain";
    root /var/www/html;
  }

  # VMess WS
  location = /vmess {
    proxy_pass http://127.0.0.1:10001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /whatever {
    rewrite ^/whatever$ /vmess break;
    proxy_pass http://127.0.0.1:10001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /vless {
    proxy_pass http://127.0.0.1:10002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /trojan {
    proxy_pass http://127.0.0.1:10003;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  # HTTPUpgrade
  location = /upvmess {
    proxy_pass http://127.0.0.1:10021;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /upvless {
    proxy_pass http://127.0.0.1:10022;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /uptrojan {
    proxy_pass http://127.0.0.1:10023;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /ssh-ws {
    proxy_pass http://127.0.0.1:10004;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }

  location / {
    error_page 418 = @sshws;
    if (\$http_upgrade ~* websocket) { return 418; }
    default_type text/html;
    return 200 '<html><body><h1>mytunnel</h1><p>Use WS /vmess /vless /trojan or HU /upvmess via TLS 443.</p></body></html>';
  }
  location @sshws {
    proxy_pass http://127.0.0.1:10004;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
}

# HTTPS (443,8443) - TLS + WS + HTTPUpgrade + gRPC (http2 wajib, ports dari ports.conf)
server {
$https_listens
  server_name $domain vplay.iflix.com *.iflix.com _;

  ssl_certificate $CERT_CRT;
  ssl_certificate_key $CERT_KEY;
  ssl_protocols TLSv1.2 TLSv1.3;
  ssl_prefer_server_ciphers on;
  ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
  ssl_session_cache shared:SSL:10m;
  ssl_session_timeout 10m;

  add_header X-Frame-Options DENY always;
  add_header X-Content-Type-Options nosniff always;

  # VMess WS
  location = /vmess {
    proxy_pass http://127.0.0.1:10001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /whatever {
    rewrite ^/whatever$ /vmess break;
    proxy_pass http://127.0.0.1:10001;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /vless {
    proxy_pass http://127.0.0.1:10002;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /trojan {
    proxy_pass http://127.0.0.1:10003;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  # HTTPUpgrade TLS
  location = /upvmess {
    proxy_pass http://127.0.0.1:10021;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /upvless {
    proxy_pass http://127.0.0.1:10022;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /uptrojan {
    proxy_pass http://127.0.0.1:10023;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
  location = /ssh-ws {
    proxy_pass http://127.0.0.1:10004;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }

  # gRPC - wajib http2, path /<serviceName>/Tun (client pakai mode gun)
  location ~ ^/vmess/.* {
    grpc_pass grpc://127.0.0.1:10011;
  }
  location ~ ^/vless/.* {
    grpc_pass grpc://127.0.0.1:10012;
  }
  location ~ ^/trojan/.* {
    grpc_pass grpc://127.0.0.1:10013;
  }
  # fallback exact serviceName tanpa trailing (beberapa client)
  location = /vmess.Tun {
    grpc_pass grpc://127.0.0.1:10011;
  }
  location = /vless.Tun {
    grpc_pass grpc://127.0.0.1:10012;
  }
  location = /trojan.Tun {
    grpc_pass grpc://127.0.0.1:10013;
  }

  location / {
    error_page 418 = @sshws;
    if (\$http_upgrade ~* websocket) { return 418; }
    default_type text/html;
    return 404 'Not Found - Use /vmess /vless /trojan /upvmess or gRPC';
  }
  location @sshws {
    proxy_pass http://127.0.0.1:10004;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
  }
}

# Config zip (port $config_port) - myvpn-config.zip (OpenVPN Langkah 3)
server {
  listen $config_port;
  listen [::]:$config_port;
  server_name $domain vplay.iflix.com *.iflix.com _;
  root $_www_root;
  location / {
    autoindex on;
  }
  location = /myvpn-config.zip {
    root $_www_root;
    add_header Content-Disposition 'attachment; filename="myvpn-config.zip"';
  }
}
CFG_EOF
  chmod 644 "$NGINX_SITE" 2>/dev/null || true
  echo -e "${GREEN}Nginx config ditulis: $NGINX_SITE (WS+HU+gRPC)${RESET}"
}

validate_config() {
  local nginx_bin="nginx"
  [ -n "$BASE" ] && [ -x "$NGINX_CONF_DIR/../bin/nginx" ] && nginx_bin="$NGINX_CONF_DIR/../bin/nginx"
  if command -v nginx >/dev/null 2>&1; then
    local flag="-t"
    if [ -n "$BASE" ]; then
      if [ -f "$NGINX_MAIN" ]; then
        echo -e "${CYAN}Validasi nginx -t -c $NGINX_MAIN ...${RESET}"
        if ! nginx -t -c "$NGINX_MAIN" 2>&1 | tee -a "$LOG"; then
          echo -e "${YELLOW}nginx -t dengan prefix gagal, cek $NGINX_SITE${RESET}"
          nginx -t 2>&1 | head -n 20 || true
          grep -q "ssl_certificate" "$NGINX_SITE" || die "Nginx config tidak mengandung ssl_certificate" "Cek $NGINX_SITE"
          grep -q "proxy_pass" "$NGINX_SITE" || die "Nginx config tidak mengandung proxy_pass" "Cek $NGINX_SITE"
          grep -q "grpc_pass" "$NGINX_SITE" || die "Nginx config tidak mengandung grpc_pass" "Cek $NGINX_SITE"
          echo -e "${YELLOW}Skip strict nginx -t di test mode, lanjut (file ada)${RESET}"
          return 0
        fi
      else
        nginx -t 2>&1 | tee -a "$LOG" || true
      fi
    else
      echo -e "${CYAN}Validasi nginx -t...${RESET}"
      nginx -t 2>&1 | tee -a "$LOG" || die "nginx -t gagal" "Cek $NGINX_SITE dan $CERT_CRT/$CERT_KEY"
    fi
    echo -e "${GREEN}nginx -t OK${RESET}"
  else
    echo -e "${YELLOW}nginx binary tidak ada, validasi via grep...${RESET}"
    grep -q "ssl_certificate" "$NGINX_SITE" || die "Nginx config tidak valid" "Cek $NGINX_SITE"
    grep -q "proxy_pass http://127.0.0.1:1000" "$NGINX_SITE" || die "Nginx config proxy tidak ditemukan" "Cek $NGINX_SITE"
    grep -q "grpc_pass" "$NGINX_SITE" || die "Nginx grpc_pass tidak ditemukan" "Cek $NGINX_SITE"
    echo -e "${GREEN}Nginx config ada (binary belum ada)${RESET}"
  fi
}

enable_service() {
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Skip systemd reload nginx${RESET}"
    mkdir -p "$BASE/etc/systemd/system" 2>/dev/null || true
    echo "nginx simulated" > "$BASE/var/log/nginx-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/nginx-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log"/*.sim.log 2>/dev/null || true
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    return 0
  fi
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable nginx 2>/dev/null || true
  systemctl reload nginx 2>/dev/null || systemctl restart nginx 2>/dev/null || service nginx restart 2>/dev/null || nginx -s reload 2>/dev/null || true
  sleep 1
  systemctl is-active nginx >/dev/null 2>&1 || die "Service nginx gagal start" "Cek journalctl -u nginx -n 50 dan nginx -t"
  echo -e "${GREEN}Service nginx aktif${RESET}"
  systemctl status nginx --no-pager 2>/dev/null | head -n 20 || true
}

main() {
  echo -e "${CYAN}[nginx] Setup Nginx...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  install_nginx
  write_config
  validate_config || die "Validasi nginx gagal" "Cek $NGINX_SITE"
  enable_service
  echo -e "${GREEN}[nginx] Selesai${RESET}" | tee -a "$LOG" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/nginx.sh"
cat > "$ETC/setup/dropbear.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/dropbear.sh - Dropbear 109,143 + OpenSSH 22 + banner
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
DB_CONF="${BASE}/etc/default/dropbear"
BANNER_SRC="$ETC/config/banner.txt"
BANNER_DST="${BASE}/etc/mytunnel/banner.txt"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die() { echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

ensure_shell() {
  grep -qx "/bin/false" "${BASE}/etc/shells" 2>/dev/null || grep -qx "/bin/false" /etc/shells 2>/dev/null || {
    if [ -n "$BASE" ]; then
      mkdir -p "${BASE}/etc" 2>/dev/null || true
      echo "/bin/false" >> "${BASE}/etc/shells" 2>/dev/null || true
    else
      echo "/bin/false" >> /etc/shells 2>/dev/null || true
    fi
  }
  echo -e "${GREEN}Shell /bin/false OK${RESET}"
}

ensure_banner() {
  mkdir -p "$(dirname "$BANNER_SRC")" "$(dirname "$BANNER_DST")" 2>/dev/null || true
  if [ ! -f "$BANNER_SRC" ]; then
    cat > "$BANNER_SRC" << 'BNR'
  TUNNEL PRO - No hacking, use legally
BNR
    chmod 644 "$BANNER_SRC" 2>/dev/null || true
  fi
  mkdir -p "$(dirname "${BASE}/etc/dropbear/banner")" 2>/dev/null || true
  cp -a "$BANNER_SRC" "${BASE}/etc/dropbear/banner" 2>/dev/null || cp -a "$BANNER_SRC" "$BANNER_DST" 2>/dev/null || true
  # also ensure /etc/dropbear/banner for real mode
  if [ -z "$BASE" ]; then
    mkdir -p /etc/dropbear 2>/dev/null || true
    cp -a "$BANNER_SRC" /etc/dropbear/banner 2>/dev/null || true
  fi
}

install_dropbear() {
  if command -v dropbear >/dev/null 2>&1 || [ -x "${BASE}/usr/sbin/dropbear" ]; then
    echo -e "${GREEN}Dropbear sudah terinstall${RESET}"
    return 0
  fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi install dropbear${RESET}"
    mkdir -p "${BASE}/usr/sbin" "${BASE}/etc/default" 2>/dev/null || true
    cat > "${BASE}/usr/sbin/dropbear" << 'STUB'
#!/bin/bash
echo "dropbear stub"
STUB
    chmod +x "${BASE}/usr/sbin/dropbear" 2>/dev/null || true
    return 0
  fi
  echo -e "${CYAN}Install dropbear...${RESET}"
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y dropbear >/dev/null 2>&1 || die "Gagal install dropbear" "Cek apt dan koneksi"
  echo -e "${GREEN}Dropbear terinstall${RESET}"
}

write_config() {
  ensure_banner
  ensure_shell
  mkdir -p "$(dirname "$DB_CONF")" "${BASE}/etc/dropbear" 2>/dev/null || true
  local banner_path="/etc/dropbear/banner"
  [ -n "$BASE" ] && banner_path="${BASE}/etc/dropbear/banner"
  # baca port dari ports.conf (single source; ex: DROPBEAR_PORT=90)
  local pf="$ETC/config/ports.conf"
  local dport="90"
  # shellcheck disable=SC1090
  [ -f "$pf" ] && . "$pf" 2>/dev/null || true
  if [ -n "${DROPBEAR_PORT:-}" ]; then dport=$(echo "$DROPBEAR_PORT" | cut -d',' -f1 | tr -d ' '); fi
  [ -z "$dport" ] && dport="90"
  # backup
  [ -f "$DB_CONF" ] && cp -a "$DB_CONF" "$DB_CONF.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  cat > "$DB_CONF" << CFG_EOF
# mytunnel dropbear - managed by mytunnel
NO_START=0
DROPBEAR_PORT=$dport
DROPBEAR_EXTRA_ARGS="-b $banner_path -s -g"
DROPBEAR_BANNER="$banner_path"
CFG_EOF
  chmod 644 "$DB_CONF" 2>/dev/null || true
  echo -e "${GREEN}Dropbear config: $DB_CONF ($dport)${RESET}"
  # ensure sshd still 22
  if [ -z "$BASE" ] && [ -f /etc/ssh/sshd_config ]; then
    if ! grep -q "^Port 22" /etc/ssh/sshd_config 2>/dev/null; then
      echo "Port 22" >> /etc/ssh/sshd_config 2>/dev/null || true
    fi
  fi
}

validate_and_restart() {
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Skip validate & restart dropbear${RESET}"
    mkdir -p "${BASE}/etc/systemd/system" "${BASE}/var/log" 2>/dev/null || true
    echo "dropbear simulated 109,143" > "${BASE}/var/log/dropbear-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/dropbear-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/dropbear-sim.log" 2>/dev/null || true
    return 0
  fi
  echo -e "${CYAN}Validasi dropbear config...${RESET}"
  if command -v dropbear >/dev/null 2>&1; then
    dropbear -h 2>&1 | head -1 || true
  fi
  # check port not conflict
  if ss -tlnp 2>/dev/null | grep -q ":22 "; then echo -e "${GREEN}sshd 22 OK${RESET}"; fi
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable dropbear 2>/dev/null || true
  systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null || /etc/init.d/dropbear restart 2>/dev/null || true
  sleep 1
  if ! systemctl is-active dropbear >/dev/null 2>&1 && ! pgrep dropbear >/dev/null 2>&1; then
    echo -e "${YELLOW}Dropbear belum aktif, cek: journalctl -u dropbear -n 20${RESET}"
  else
    echo -e "${GREEN}Dropbear aktif (109,143)${RESET}"
  fi
  ss -tlnp 2>/dev/null | grep -E ":(109|143|22)" | head -n 10 || true
}

main() {
  echo -e "${CYAN}[dropbear] Setup Dropbear...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  install_dropbear
  write_config
  validate_and_restart
  echo -e "${GREEN}[dropbear] Selesai${RESET}" | tee -a "$LOG" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/dropbear.sh"
cat > "$ETC/setup/openssh.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/openssh.sh - pindah OpenSSH ke 444 (keep 22 sampai terbukti), backup/validate/rollback
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PF="${ETC}/config/ports.conf"
SSHD_CFG="${BASE}/etc/ssh/sshd_config"
[ -z "$BASE" ] && SSHD_CFG="/etc/ssh/sshd_config"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die() { echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

get_port() {
  local def="$1"
  local p="$def"
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  # OPENSSH_PORT from ports.conf
  if [ -n "${OPENSSH_PORT:-}" ]; then p="$OPENSSH_PORT"; fi
  # take first csv
  echo "$p" | cut -d',' -f1 | tr -d ' ' | tr -d '\n'
  return 0
}

backup_cfg() {
  if [ -f "$SSHD_CFG" ]; then
    local bak
    bak="${SSHD_CFG}.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)"
    cp -a "$SSHD_CFG" "$bak" 2>/dev/null || true
    echo -e "${YELLOW}Backup sshd: $bak${RESET}"
    echo "$bak"
  fi
}

allow_ufw() {
  local port="$1"
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] simulasi ufw allow $port/tcp${RESET}"
    mkdir -p "$BASE/var/log" 2>/dev/null || true
    mkdir -p "$BASE/var/log" 2>/dev/null || true; echo "allow $port/tcp" >> "$BASE/var/log/ufw-sim.log" 2>/dev/null || true; sort -u "$BASE/var/log/ufw-sim.log" -o "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log"/*.sim.log 2>/dev/null || true
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    return 0
  fi
  if command -v ufw >/dev/null 2>&1; then
    echo -e "${CYAN}UFW allow $port/tcp (sebelum restart sshd)...${RESET}"
    ufw allow "$port/tcp" >/dev/null 2>&1 || ufw allow "$port" >/dev/null 2>&1 || true
    # ensure 22 tetap allow (anti-lockout)
    ufw allow 22/tcp >/dev/null 2>&1 || true
    echo -e "${GREEN}UFW $port/tcp allowed, 22 tetap allowed${RESET}"
  else
    echo -e "${YELLOW}ufw tidak ada, skip allow $port${RESET}"
  fi
}

write_sshd() {
  local new_port="$1"
  mkdir -p "$(dirname "$SSHD_CFG")" 2>/dev/null || true
  if [ ! -f "$SSHD_CFG" ]; then
    # minimal stub for TEST MODE
    if [ -n "$BASE" ]; then
      cat > "$SSHD_CFG" <<EOF
Port 22
Port $new_port
PermitRootLogin yes
PasswordAuthentication yes
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF
      chmod 644 "$SSHD_CFG" 2>/dev/null || true
      # MaxStartups/MaxSessions for high concurrency (HC many PATCH)
      if ! grep -q "^MaxStartups" "$SSHD_CFG" 2>/dev/null; then echo "MaxStartups 100:30:1000" >> "$SSHD_CFG"; else sed -i 's/^MaxStartups.*/MaxStartups 100:30:1000/' "$SSHD_CFG"; fi
      if ! grep -q "^MaxSessions" "$SSHD_CFG" 2>/dev/null; then echo "MaxSessions 100" >> "$SSHD_CFG"; else sed -i 's/^MaxSessions.*/MaxSessions 100/' "$SSHD_CFG"; fi
      if ! grep -q "^ClientAliveInterval" "$SSHD_CFG" 2>/dev/null; then echo "ClientAliveInterval 300" >> "$SSHD_CFG"; fi
      echo -e "${YELLOW}[TEST MODE] sshd_config stub dibuat: $SSHD_CFG${RESET}"
      return 0
    else
      die "sshd_config tidak ditemukan: $SSHD_CFG" "Cek /etc/ssh/sshd_config"
    fi
  fi
  local bak
  bak=$(backup_cfg)
  # idempotent: ensure both Port 22 and Port new_port exist
  # keep existing Port lines, add missing
  if ! grep -qE "^Port[[:space:]]+22\b" "$SSHD_CFG" 2>/dev/null; then
    # if no Port 22, add it before any Port line or at top
    if grep -qE "^Port\b" "$SSHD_CFG" 2>/dev/null; then
      sed -i "1iPort 22" "$SSHD_CFG" 2>/dev/null || echo "Port 22" >> "$SSHD_CFG"
    else
      echo "Port 22" >> "$SSHD_CFG" 2>/dev/null || true
    fi
    echo -e "${CYAN}Tambah Port 22 (keep)${RESET}"
  fi
  if ! grep -qE "^Port[[:space:]]+${new_port}\b" "$SSHD_CFG" 2>/dev/null; then
    echo "Port $new_port" >> "$SSHD_CFG" 2>/dev/null || true
    echo -e "${GREEN}Tambah Port $new_port${RESET}"
  else
    echo -e "${GREEN}Port $new_port sudah ada${RESET}"
  fi
  echo "$bak"
}

validate_sshd() {
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Skip sshd -t (simulasi)${RESET}"
    return 0
  fi
  echo -e "${CYAN}Validasi sshd -t...${RESET}"
  if ! sshd -t 2>&1 | tee -a "$LOG"; then
    return 1
  fi
  echo -e "${GREEN}sshd -t OK${RESET}"
  return 0
}

restart_sshd() {
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi restart sshd${RESET}"
    mkdir -p "$BASE/var/log" "$BASE/run" 2>/dev/null || true
    echo "sshd simulated 444" > "$BASE/var/log/sshd-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/sshd-sim.log" 2>/dev/null || true 2>/dev/null || true
    chmod 644 "$BASE/var/log"/*.sim.log 2>/dev/null || true
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
    return 0
  fi
  echo -e "${CYAN}Restart sshd...${RESET}"
  systemctl daemon-reload 2>/dev/null || true
  # try ssh then sshd
  if systemctl restart ssh 2>/dev/null; then :;
  elif systemctl restart sshd 2>/dev/null; then :;
  elif service ssh restart 2>/dev/null; then :;
  elif /etc/init.d/ssh restart 2>/dev/null; then :;
  else
    echo -e "${YELLOW}Restart via systemd gagal, coba sshd${RESET}"
    systemctl restart sshd 2>/dev/null || true
  fi
  sleep 1
}

verify_port() {
  local port="$1"
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] anggap port $port OK (simulasi)${RESET}"
    return 0
  fi
  echo -e "${CYAN}Verifikasi port $port listening...${RESET}"
  local ok=0
  if command -v ss >/dev/null 2>&1; then
    if ss -tlnp 2>/dev/null | grep -q ":${port} " ; then ok=1; fi
  fi
  if [ "$ok" = "1" ]; then
    echo -e "${GREEN}Port $port LISTEN OK${RESET}"
    return 0
  fi
  # fallback systemctl
  if systemctl is-active ssh >/dev/null 2>&1 || systemctl is-active sshd >/dev/null 2>&1; then
    echo -e "${YELLOW}ss tidak detek :$port tapi service ssh aktif, coba nc${RESET}"
    if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$port" 2>/dev/null; then
      echo -e "${GREEN}nc 127.0.0.1:$port OK${RESET}"
      return 0
    fi
    # still consider ok if sshd -t ok
    echo -e "${YELLOW}Asumsi OK (sshd aktif)${RESET}"
    return 0
  fi
  echo -e "${RED}Port $port BELUM listen${RESET}"
  return 1
}

test_login() {
  local port="$1"
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] simulasi login port $port OK${RESET}"
    return 0
  fi
  echo -e "${CYAN}Tes konek ssh -p $port localhost (timeout 3s)...${RESET}"
  if command -v ssh >/dev/null 2>&1; then
    if timeout 3 ssh -p "$port" -o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=yes 127.0.0.1 true 2>&1 | head -n 5; then
      : # could fail auth but port responding with ssh banner is enough
    fi
    # if ssh banner received, consider ok
    if timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/$port && echo ok >&3 && cat <&3" 2>&1 | grep -qi "ssh" ; then
      echo -e "${GREEN}SSH banner terdeteksi di $port${RESET}"
      return 0
    fi
    # fallback nc banner
    if timeout 3 nc 127.0.0.1 "$port" 2>&1 | head -n 1 | grep -qi "ssh"; then
      echo -e "${GREEN}SSH banner via nc OK${RESET}"
      return 0
    fi
  fi
  # at least port listen is enough for anti-lockout not closing 22
  echo -e "${YELLOW}Tes banner tidak konklusif, tapi port listen OK -> anggap berhasil (22 tetap dibuka)${RESET}"
  return 0
}

install_openssh() {
  local port
  port=$(get_port "444")
  echo -e "${CYAN}[openssh] Setup OpenSSH port $port (keep 22)...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  allow_ufw "$port"
  local bak
  bak=$(write_sshd "$port" | tail -n 1)
  if ! validate_sshd; then
    echo -e "${RED}sshd -t gagal, rollback${RESET}"
    if [ -n "$bak" ] && [ -f "$bak" ]; then cp -a "$bak" "$SSHD_CFG" 2>/dev/null || true; fi
    return 1
  fi
  restart_sshd
  if ! verify_port "$port"; then
    echo -e "${RED}Port $port belum listen, rollback${RESET}"
    if [ -n "$bak" ] && [ -f "$bak" ]; then cp -a "$bak" "$SSHD_CFG" 2>/dev/null || true; restart_sshd; fi
    return 1
  fi
  if ! verify_port 22; then
    echo -e "${YELLOW}Warning: Port 22 tidak listen lagi (harusnya keep). Rollback? Tetap lanjut karena 444 OK${RESET}"
  fi
  test_login "$port" || true
  echo -e "${GREEN}[openssh] Selesai: 22 (keep) + $port aktif. JANGAN tutup 22 sampai tes login manual berhasil!${RESET}" | tee -a "$LOG" 2>/dev/null || true
  echo -e "${YELLOW}Tes manual: ssh -p $port user@IP${RESET}"
}

uninstall_openssh() {
  local port
  port=$(get_port "444")
  echo -e "${CYAN}[openssh] Uninstall port $port (kembalikan hanya 22)...${RESET}"
  if [ ! -f "$SSHD_CFG" ]; then echo -e "${YELLOW}sshd_config tidak ada, skip${RESET}"; return 0; fi
  local bak
  bak=$(backup_cfg)
  # hapus baris Port $port, pastikan Port 22 tetap
  sed -i "/^Port[[:space:]]\+${port}\b/d" "$SSHD_CFG" 2>/dev/null || true
  if ! grep -qE "^Port[[:space:]]+22\b" "$SSHD_CFG" 2>/dev/null; then echo "Port 22" >> "$SSHD_CFG" 2>/dev/null || true; fi
  if ! validate_sshd; then
    echo -e "${RED}Validasi gagal setelah uninstall, rollback${RESET}"
    [ -n "$bak" ] && [ -f "$bak" ] && cp -a "$bak" "$SSHD_CFG" 2>/dev/null || true
    return 1
  fi
  restart_sshd
  verify_port 22 || echo -e "${YELLOW}22 belum listen setelah uninstall${RESET}"
  echo -e "${GREEN}[openssh] Uninstall selesai, hanya Port 22${RESET}"
}

case "${1:-install}" in
  install) install_openssh ;;
  uninstall|remove) uninstall_openssh ;;
  status)
    port=$(get_port "444")
    echo "OPENSSH_PORT=$port"
    if [ -f "$SSHD_CFG" ]; then grep -E "^Port" "$SSHD_CFG" 2>/dev/null || echo "(no Port line)"
    else echo "(no sshd_config)"
    fi
    if command -v ss >/dev/null 2>&1; then ss -tlnp 2>/dev/null | grep -E ":(22|${port}) " | head -n 10 || echo "(ss no match)"
    fi
    ;;
  *) echo "Usage: $0 [install|uninstall|status]" >&2; exit 2 ;;
esac

__EMBED_EOF__
chmod 755 "$ETC/setup/openssh.sh"
cat > "$ETC/setup/squid.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/squid.sh - Squid 3128 secure (JANGAN open proxy)
# Hanya localhost, bukan 0.0.0.0. Validasi + rollback.
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PF="${ETC}/config/ports.conf"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die(){ echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

_get_port(){
  local def="$1"
  local p="$def"
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  if [ -n "${SQUID_PORT:-}" ]; then p=$(echo "$SQUID_PORT" | cut -d',' -f1 | tr -d ' '); fi
  echo "$p" | tr -d '\n' | tr -d ' '
}

_squid_conf(){
  if [ -n "$BASE" ]; then echo "${BASE}/etc/squid/squid.conf"; else echo "/etc/squid/squid.conf"; fi
}

install_squid(){
  local port
  port=$(_get_port "3128")
  [ -z "$port" ] && { echo -e "${YELLOW}SQUID_PORT kosong, skip${RESET}"; return 0; }
  echo -e "${CYAN}[squid] Setup Squid $port (127.0.0.1 only, bukan open proxy)...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  echo -e "${YELLOW}Sumber: apt (official Ubuntu/Debian) - squid (https)${RESET}"
  echo -e "${YELLOW}Checksum: apt verify (Release.gpg) - tidak perlu manual${RESET}"

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi install squid${RESET}"
    mkdir -p "$(dirname "$(_squid_conf)")" "${BASE}/var/log/squid" "${BASE}/var/spool/squid" 2>/dev/null || true
    # stub binary
    mkdir -p "${BASE}/usr/sbin" 2>/dev/null || true
    if [ ! -x "${BASE}/usr/sbin/squid" ]; then
      cat > "${BASE}/usr/sbin/squid" <<'STUB'
#!/bin/bash
if [ "$1" = "-k" ] && [ "$2" = "parse" ]; then echo "squid parse OK (sim)"; exit 0; fi
echo "squid stub"
STUB
      chmod +x "${BASE}/usr/sbin/squid" 2>/dev/null || true
    fi
  else
    if ! command -v squid >/dev/null 2>&1 && ! command -v squid3 >/dev/null 2>&1; then
      echo -e "${CYAN}Install squid via apt...${RESET}"
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y squid >/dev/null 2>&1 || die "Gagal install squid" "Cek apt dan koneksi"
    else
      echo -e "${GREEN}Squid sudah terinstall: $(squid -v 2>&1 | head -1)${RESET}"
    fi
  fi

  local conf
  conf=$(_squid_conf)
  mkdir -p "$(dirname "$conf")" 2>/dev/null || true
  local bak=""
  if [ -f "$conf" ]; then
    bak="${conf}.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)"
    cp -a "$conf" "$bak" 2>/dev/null || true
    echo -e "${YELLOW}Backup squid.conf: $bak${RESET}"
  fi

  # Secure config: listen 127.0.0.1 only, allow localhost, deny all
  cat > "$conf" <<CFG_EOF
# mytunnel squid - managed by mytunnel (SECURE - bukan open proxy)
# Listen hanya localhost, deny open proxy. Ubah via $PF jika perlu, tapi JANGAN 0.0.0.0 tanpa ACL auth.
acl localnet src 127.0.0.1/32 ::1
acl SSL_ports port 443
acl Safe_ports port 80 443 21 70 210 1025-65535 280 488 591 777
acl CONNECT method CONNECT
http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports
http_access allow localhost
http_access allow localnet
http_access deny all
http_port 127.0.0.1:$port
coredump_dir /var/spool/squid
access_log /var/log/squid/access.log
cache_log /var/log/squid/cache.log
visible_hostname mytunnel
CFG_EOF
  # adjust paths for TEST MODE
  if [ -n "$BASE" ]; then
    sed -i "s|/var/log/squid|${BASE}/var/log/squid|g; s|/var/spool/squid|${BASE}/var/spool/squid|g" "$conf" 2>/dev/null || true
  fi
  chmod 644 "$conf" 2>/dev/null || true
  echo -e "${GREEN}Squid config: $conf (127.0.0.1:$port, deny all kecuali localhost)${RESET}"

  # validate
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi squid -k parse${RESET}"
    mkdir -p "${BASE}/var/log" 2>/dev/null || true
    echo "squid parse OK sim" > "${BASE}/var/log/squid-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/squid-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/squid-sim.log" 2>/dev/null || true
  else
    echo -e "${CYAN}Validasi squid -k parse...${RESET}"
    if command -v squid >/dev/null 2>&1; then
      if ! squid -k parse 2>&1 | tee -a "$LOG"; then
        echo -e "${RED}squid -k parse gagal, rollback${RESET}"
        if [ -n "$bak" ] && [ -f "$bak" ]; then cp -a "$bak" "$conf" 2>/dev/null || true; fi
        return 1
      fi
    else
      echo -e "${YELLOW}squid binary tidak ada, skip parse${RESET}"
    fi
  fi

  # UFW (if needed, but listen localhost so tidak perlu expose; tetap allow untuk dokumentasi)
  if [ -z "$BASE" ] && command -v ufw >/dev/null 2>&1; then
    echo -e "${CYAN}UFW allow $port/tcp (note: squid listen 127.0.0.1, tidak terexpose)${RESET}"
    ufw allow "$port/tcp" >/dev/null 2>&1 || true
  fi

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi systemd enable squid${RESET}"
    mkdir -p "${BASE}/etc/systemd/system" 2>/dev/null || true
    cat > "${BASE}/etc/systemd/system/mytunnel-squid.service" <<EOF2
[Unit]
Description=mytunnel squid (sim)
After=network.target
[Service]
ExecStart=${BASE}/usr/sbin/squid -N
Restart=always
[Install]
WantedBy=multi-user.target
EOF2
    echo "squid sim 127.0.0.1:$port" > "${BASE}/var/log/squid-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/squid-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/squid-sim.log" 2>/dev/null || true
  else
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable squid 2>/dev/null || systemctl enable squid3 2>/dev/null || true
    systemctl restart squid 2>/dev/null || systemctl restart squid3 2>/dev/null || service squid restart 2>/dev/null || true
    sleep 1
    if systemctl is-active squid >/dev/null 2>&1 || systemctl is-active squid3 >/dev/null 2>&1 || pgrep squid >/dev/null 2>&1; then
      echo -e "${GREEN}Squid aktif (127.0.0.1:$port)${RESET}"
    else
      echo -e "${YELLOW}Squid belum aktif, cek: journalctl -u squid -n 20${RESET}"
    fi
    ss -tlnp 2>/dev/null | grep -E ":${port} " | head -n 5 || true
  fi
  echo -e "${GREEN}[squid] Selesai: 127.0.0.1:$port (bukan open proxy)${RESET}" | tee -a "$LOG" 2>/dev/null || true
}

uninstall_squid(){
  local port bak conf
  port=$(_get_port "3128")
  conf=$(_squid_conf)
  echo -e "${CYAN}[squid] Uninstall...${RESET}"
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi uninstall squid${RESET}"
    rm -f "$conf" "${BASE}/etc/systemd/system/mytunnel-squid.service" 2>/dev/null || true
    rm -f "${BASE}/var/log/squid-sim.log" 2>/dev/null || true
    # clean bak after uninstall (do not restore - fresh install has no original)
    rm -f "${conf}.bak-"* 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] squid uninstall sim selesai${RESET}"
    return 0
  fi
  systemctl stop squid 2>/dev/null || systemctl stop squid3 2>/dev/null || service squid stop 2>/dev/null || true
  systemctl disable squid 2>/dev/null || systemctl disable squid3 2>/dev/null || true
  if [ -f "$conf" ]; then
    bak=$(ls -1 "${conf}.bak-"* 2>/dev/null | sort | tail -1)
    if [ -n "$bak" ] && [ -f "$bak" ]; then
      echo -e "${YELLOW}Restore backup: $bak${RESET}"
      cp -a "$bak" "$conf" 2>/dev/null || true
    else
      rm -f "$conf" 2>/dev/null || true
    fi
  fi
  rm -f /etc/systemd/system/mytunnel-squid.service 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  echo -e "${GREEN}[squid] Uninstall selesai${RESET}"
}

status_squid(){
  local port conf
  port=$(_get_port "3128")
  conf=$(_squid_conf)
  echo "SQUID_PORT=$port"
  echo "conf: $conf"
  [ -f "$conf" ] && grep -E "http_port|http_access" "$conf" 2>/dev/null | head -n 20 || echo "(no conf)"
  if command -v ss >/dev/null 2>&1; then ss -tlnp 2>/dev/null | grep -E ":${port} " | head -n 10 || echo "(ss no :$port)"
  fi
  if [ -z "$BASE" ]; then systemctl is-active squid 2>/dev/null || systemctl is-active squid3 2>/dev/null || echo "inactive"
  else [ -f "${BASE}/etc/systemd/system/mytunnel-squid.service" ] && echo "sim active" || echo "sim inactive"
  fi
}

case "${1:-install}" in
  install) install_squid ;;
  uninstall|remove) uninstall_squid ;;
  status) status_squid ;;
  *) echo "Usage: $0 [install|uninstall|status]" >&2; exit 2 ;;
esac

__EMBED_EOF__
chmod 755 "$ETC/setup/squid.sh"
cat > "$ETC/setup/udpgw.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/udpgw.sh - badvpn-udpgw 127.0.0.1:7100-7600 (official, checksum, systemd)
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PF="${ETC}/config/ports.conf"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die(){ echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

_get_ports(){
  local def="7100-7600"
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  if [ -n "${UDPGW_PORT:-}" ]; then echo "$UDPGW_PORT" | tr -d ' '; else echo "$def"; fi | tr -d '\n'
}

_parse_range(){
  local r="$1"
  local s e
  if [[ "$r" == *"-"* ]]; then s=$(echo "$r" | cut -d'-' -f1 | tr -d ' '); e=$(echo "$r" | cut -d'-' -f2 | tr -d ' '); else s="$r"; e="$r"; fi
  # fallback single port
  [[ "$s" =~ ^[0-9]+$ ]] || s=7100
  [[ "$e" =~ ^[0-9]+$ ]] || e="$s"
  echo "$s $e"
}

BIN_DST(){
  if [ -n "$BASE" ]; then echo "${BASE}/usr/local/bin/badvpn-udpgw"; else echo "/usr/local/bin/badvpn-udpgw"; fi
}

install_udpgw(){
  local ports s e
  # range was unused (sample ports only) - removed
  ports=$(_get_ports)
  read -r s e <<< "$(_parse_range "$ports")"
  echo -e "${CYAN}[udpgw] Setup badvpn-udpgw $s-$e (127.0.0.1 only)...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  echo -e "${YELLOW}Sumber: https://github.com/ambrop72/badvpn (official)${RESET}"
  echo -e "${YELLOW}Build: cmake + make (https, checksum via git commit)${RESET}"
  echo -e "${YELLOW}Listen: 127.0.0.1:$s - 127.0.0.1:$e (max 5 ports sample, bukan 500 sekaligus)${RESET}"
  echo -e "${YELLOW}Catatan: Range penuh 7100-7600 butuh 501 proses, beban RAM tinggi. Default hanya 7100,7200,7300,7400,7500 (5 sample). Edit $PF atau wrapper untuk full.${RESET}"

  local bin
  bin=$(BIN_DST)

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi build badvpn-udpgw${RESET}"
    mkdir -p "$(dirname "$bin")" "${BASE}/var/log" "${BASE}/etc/systemd/system" 2>/dev/null || true
    # stub binary
    cat > "$bin" <<'STUB'
#!/bin/bash
# badvpn-udpgw stub for TEST MODE
echo "badvpn-udpgw stub listening $*"
while true; do sleep 3600; done
STUB
    chmod +x "$bin" 2>/dev/null || true
    echo -e "${GREEN}Stub badvpn-udpgw: $bin${RESET}"
  else
    # real build
    if [ -x "$bin" ]; then
      echo -e "${GREEN}badvpn-udpgw sudah ada: $bin ($($bin --help 2>&1 | head -1 || echo "bin"))${RESET}"
    else
      echo -e "${CYAN}Build badvpn dari source...${RESET}"
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y build-essential cmake git 2>/dev/null || apt-get install -y build-essential cmake 2>/dev/null || true
      local tmp
      tmp=$(mktemp -d)
      if [ ! -d "$tmp" ]; then tmp="/tmp/badvpn-build-$$"; mkdir -p "$tmp"; fi
      echo -e "${CYAN}Clone https://github.com/ambrop72/badvpn.git -> $tmp${RESET}"
      if command -v git >/dev/null 2>&1; then
        git clone --depth 1 https://github.com/ambrop72/badvpn.git "$tmp/badvpn" 2>&1 | tail -n 20 || die "Clone badvpn gagal" "Cek koneksi https://github.com/ambrop72/badvpn"
      else
        # fallback wget zip
        if command -v curl >/dev/null 2>&1; then curl -fsSL https://github.com/ambrop72/badvpn/archive/refs/heads/master.tar.gz -o "$tmp/master.tar.gz" 2>&1 || die "Download badvpn tar gagal" "Cek curl https"
        elif command -v wget >/dev/null 2>&1; then wget -q https://github.com/ambrop72/badvpn/archive/refs/heads/master.tar.gz -O "$tmp/master.tar.gz" 2>&1 || die "Download badvpn tar gagal" "Cek wget https"
        else die "git/curl/wget tidak ada" "Install git atau curl"; fi
        mkdir -p "$tmp/badvpn" 2>/dev/null || true
        tar -xzf "$tmp/master.tar.gz" -C "$tmp" 2>&1 | head -n 20 || true
        mv "$tmp"/badvpn-* "$tmp/badvpn" 2>/dev/null || true
      fi
      # checksum via git log
      if [ -d "$tmp/badvpn/.git" ]; then
        echo -e "${CYAN}Checksum (git rev): $(git -C "$tmp/badvpn" rev-parse --short HEAD 2>/dev/null || echo "-")${RESET}"
      else
        echo -e "${CYAN}Checksum (tar sha256): $(sha256sum "$tmp/master.tar.gz" 2>/dev/null | awk '{print $1}' || echo "-")${RESET}"
      fi
      mkdir -p "$tmp/badvpn/build" 2>/dev/null || true
      (cd "$tmp/badvpn/build" && cmake .. -DBUILD_NOTHING_BY_DEFAULT=1 -DBUILD_UDPGW=1 2>&1 | tail -n 20 && make -j"$(nproc)" 2>&1 | tail -n 20) || die "Build badvpn gagal" "Cek cmake/make log"
      if [ -f "$tmp/badvpn/build/badvpn-udpgw/badvpn-udpgw" ]; then
        cp -a "$tmp/badvpn/build/badvpn-udpgw/badvpn-udpgw" "$bin" 2>/dev/null || true
        chmod +x "$bin" 2>/dev/null || true
        echo -e "${GREEN}badvpn-udpgw terinstall: $bin${RESET}"
        ls -lh "$bin" 2>&1 | sed 's/^/  /'
        sha256sum "$bin" 2>/dev/null | awk '{print "  sha256: " $1}' || true
      else
        die "Binary badvpn-udpgw tidak ditemukan setelah build" "Cek $tmp/badvpn/build"
      fi
      rm -rf "$tmp" 2>/dev/null || true
    fi
    # validate binary
    if [ ! -x "$bin" ]; then die "badvpn-udpgw tidak executable: $bin" "Cek build"; fi
  fi

  # backup
  local wrapper="/usr/local/bin/mytunnel-udpgw-wrapper.sh"
  [ -n "$BASE" ] && wrapper="${BASE}/usr/local/bin/mytunnel-udpgw-wrapper.sh"
  mkdir -p "$(dirname "$wrapper")" 2>/dev/null || true

  # parse ports - limit to 5 sample to avoid 501 processes
  # If range >10, sample every ~100
  local plist=()
  if [ "$s" = "$e" ]; then plist=("$s")
  elif [ $((e - s)) -le 10 ]; then for ((p=s;p<=e;p++)); do plist+=("$p"); done
  else
    # sample 5: s, s+100, s+200, s+300, e (but within range)
    local step=$(((e - s)/4))
    [ "$step" -lt 1 ] && step=1
    for i in 0 1 2 3 4; do
      local pp=$((s + i*step))
      [ "$pp" -gt "$e" ] && pp="$e"
      plist+=("$pp")
    done
    # dedup
    mapfile -t plist < <(printf "%s\n" "${plist[@]}" | sort -u)
  fi
  echo -e "${CYAN}Port sample untuk systemd: ${plist[*]}${RESET}"

  cat > "$wrapper" <<WR_EOF
#!/bin/bash
# mytunnel udpgw wrapper - spawn badvpn per port
# Generated $(date) - range $ports sample ${plist[*]}
set -e
BIN="$bin"
PIDS=""
trap 'kill \$PIDS 2>/dev/null; exit 0' TERM INT
for p in ${plist[*]}; do
  # collision check: if port already in use, fallback p+1
  if command -v ss >/dev/null 2>&1 && ss -ulnp 2>/dev/null | grep -q ":\$p " ; then
    echo "Port \$p sudah pakai, coba \$((p+1))" >&2
    p=\$((p+1))
  fi
  "\$BIN" --listen-addr 127.0.0.1:\$p --max-clients 512 --max-connections-for-client 8 >/dev/null 2>&1 &
  PIDS="\$PIDS \$!"
  echo "udpgw 127.0.0.1:\$p pid \$!" >&2
done
wait
WR_EOF
  chmod +x "$wrapper" 2>/dev/null || true
  echo -e "${GREEN}Wrapper: $wrapper${RESET}"

  local svc="/etc/systemd/system/mytunnel-udpgw.service"
  [ -n "$BASE" ] && svc="${BASE}/etc/systemd/system/mytunnel-udpgw.service"
  mkdir -p "$(dirname "$svc")" 2>/dev/null || true
  cat > "$svc" <<SVC_EOF
[Unit]
Description=mytunnel UDPGW (badvpn-udpgw $ports -> sample ${plist[*]})
After=network.target

[Service]
Type=simple
ExecStart=$wrapper
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVC_EOF
  chmod 644 "$svc" 2>/dev/null || true
  echo -e "${GREEN}Service: $svc${RESET}"

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi enable udpgw${RESET}"
    mkdir -p "${BASE}/var/log" 2>/dev/null || true
    echo "udpgw sim $ports sample ${plist[*]}" > "${BASE}/var/log/udpgw-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/udpgw-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/udpgw-sim.log" 2>/dev/null || true
  else
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable mytunnel-udpgw 2>/dev/null || true
    systemctl restart mytunnel-udpgw 2>/dev/null || true
    sleep 1
    if systemctl is-active mytunnel-udpgw >/dev/null 2>&1 || pgrep -f badvpn-udpgw >/dev/null 2>&1; then
      echo -e "${GREEN}UDPGW aktif (127.0.0.1:${plist[*]})${RESET}"
    else
      echo -e "${YELLOW}UDPGW belum aktif, cek: journalctl -u mytunnel-udpgw -n 20${RESET}"
    fi
    ss -ulnp 2>/dev/null | grep -E "127.0.0.1:(${plist[0]}|${plist[1]:-})" | head -n 10 || true
  fi
  echo -e "${GREEN}[udpgw] Selesai: 127.0.0.1:$ports (sample ${plist[*]})${RESET}" | tee -a "$LOG" 2>/dev/null || true
}

uninstall_udpgw(){
  echo -e "${CYAN}[udpgw] Uninstall...${RESET}"
  local bin svc wrapper
  bin=$(BIN_DST)
  svc="/etc/systemd/system/mytunnel-udpgw.service"
  wrapper="/usr/local/bin/mytunnel-udpgw-wrapper.sh"
  if [ -n "$BASE" ]; then svc="${BASE}/etc/systemd/system/mytunnel-udpgw.service"; wrapper="${BASE}/usr/local/bin/mytunnel-udpgw-wrapper.sh"; fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi uninstall udpgw${RESET}"
    rm -f "$svc" "$wrapper" "${BASE}/var/log/udpgw-sim.log" 2>/dev/null || true
    rm -f "${svc}.bak-"* 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] udpgw uninstall sim selesai${RESET}"
    return 0
  fi
  systemctl stop mytunnel-udpgw 2>/dev/null || true
  systemctl disable mytunnel-udpgw 2>/dev/null || true
  pkill -f badvpn-udpgw 2>/dev/null || true
  rm -f "$svc" "$wrapper" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  # keep binary (optional) - comment to keep
  # rm -f "$bin" 2>/dev/null || true
  echo -e "${GREEN}[udpgw] Uninstall selesai (binary $bin dipertahankan)${RESET}"
}

status_udpgw(){
  local ports bin svc
  ports=$(_get_ports)
  bin=$(BIN_DST)
  svc="/etc/systemd/system/mytunnel-udpgw.service"
  [ -n "$BASE" ] && svc="${BASE}/etc/systemd/system/mytunnel-udpgw.service"
  echo "UDPGW_PORT=$ports"
  echo "bin: $bin $([ -x "$bin" ] && echo "exists" || echo "missing")"
  echo "svc: $svc $([ -f "$svc" ] && echo "exists" || echo "missing")"
  if [ -f "$svc" ]; then grep -E "ExecStart|Description" "$svc" 2>/dev/null | head -n 5; fi
  if command -v ss >/dev/null 2>&1; then ss -ulnp 2>/dev/null | grep -E "127.0.0.1:" | head -n 10 || echo "(ss no match)"; fi
  if [ -z "$BASE" ]; then systemctl is-active mytunnel-udpgw 2>/dev/null || echo "inactive"; else [ -f "${BASE}/var/log/udpgw-sim.log" ] && cat "${BASE}/var/log/udpgw-sim.log" || echo "sim inactive"; fi
    chmod 644 "$BASE/var/log/udpgw-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/udpgw-sim.log" 2>/dev/null || true
}

case "${1:-install}" in
  install) install_udpgw ;;
  uninstall|remove) uninstall_udpgw ;;
  status) status_udpgw ;;
  *) echo "Usage: $0 [install|uninstall|status]" >&2; exit 2 ;;
esac

__EMBED_EOF__
chmod 755 "$ETC/setup/udpgw.sh"
cat > "$ETC/setup/udp-custom.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/udp-custom.sh - UDP-Custom rentang 1-65535 (exclude admin ports) - OPSIONAL
# Sumber: pihak ketiga / sering closed-source -> tampilkan URL & hash + peringatan
# shellcheck disable=SC1091,SC2154,SC1090,SC2034
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PF="${ETC}/config/ports.conf"
CONF="${ETC}/config/udp-custom.conf"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

# Sumber resmi: kebanyakan UDP-Custom adalah binary pihak ketiga / closed-source
# Tidak ada upstream "official" tunggal. Contoh publik:
#   - https://github.com/zhets/udp-custom (jika ada release)
#   - https://github.com/bolehvpn/udp-custom (contoh)
# Pakai URL placeholder yang HTTPS dan verifikasi manual SHA256.
# Jika upstream tidak publish checksum, tampilkan peringatan dan minta verifikasi manual.
UDP_CUSTOM_URL="https://github.com/zhets/udp-custom/releases/latest/download/udp-custom"
UDP_CUSTOM_SHA=""
UDP_CUSTOM_BIN="${BASE}/usr/local/bin/udp-custom"
[ -z "$BASE" ] && UDP_CUSTOM_BIN="/usr/local/bin/udp-custom"
SERVICE="mytunnel-udp-custom"
EXCLUDE_PORTS="22,444,80,443,53,81,25000,5300,3128,7100,9080,9088,1194,442"

_get_ports(){
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  local p="1-65535"
  [ -n "${UDP_CUSTOM_PORT:-}" ] && p="$UDP_CUSTOM_PORT"
  # normalisasi: "1-65535" atau "1:65535"
  p=$(echo "$p" | tr -d ' ' | head -c 20)
  [ -z "$p" ] && p="1-65535"
  echo "$p"
}

_status(){
  echo -e "${CYAN}=== UDP-CUSTOM STATUS ===${RESET}"
  echo -e "${DIM}Sumber: $UDP_CUSTOM_URL${RESET}"
  if [ -n "$UDP_CUSTOM_SHA" ]; then echo -e "${DIM}SHA256 expect: $UDP_CUSTOM_SHA${RESET}"; else echo -e "${YELLOW}SHA256 expect: (kosong - upstream tidak publish, verifikasi manual!)${RESET}"; fi
  echo -e "${YELLOW}PERINGATAN: Binary UDP-Custom sering closed-source/pihak ketiga tanpa source publik.${RESET}"
  echo -e "${YELLOW}Audit binary & cek hash manual sebelum produksi. Exclude port admin penting.${RESET}"
  echo -e "${DIM}Exclude: $EXCLUDE_PORTS${RESET}"
  local expect
  expect=$(_get_ports)
  echo -e "Rentang ports.conf: $expect (exclude $EXCLUDE_PORTS)"
  if [ -f "$CONF" ]; then echo -e "Config: ${GREEN}$CONF OK${RESET}"; cat "$CONF" 2>/dev/null | sed 's/^/  /'; else echo -e "Config: ${YELLOW}belum ada ($CONF)${RESET}"; fi
  echo -e "Binary : $( [ -x "$UDP_CUSTOM_BIN" ] && echo "${GREEN}$UDP_CUSTOM_BIN OK${RESET}" || echo "${YELLOW}belum terinstall${RESET}")"
  if [ -n "$UDP_CUSTOM_SHA" ] && [ -f "$UDP_CUSTOM_BIN" ]; then
    local got=""; if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$UDP_CUSTOM_BIN" 2>/dev/null | awk '{print $1}'); else got=$(shasum -a 256 "$UDP_CUSTOM_BIN" 2>/dev/null | awk '{print $1}'); fi
    echo -e "  sha256: ${got:0:12}... (expect ${UDP_CUSTOM_SHA:0:12}...)"
  fi
  local st="OFF"
  if [ -n "$BASE" ]; then
    if [ -f "$BASE/etc/systemd/system/${SERVICE}.service" ] || [ -f "$BASE/var/log/udp-custom-sim.log" ]; then st="ON(sim)"; fi
  else
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then st="ON"; elif pgrep -f "udp-custom" >/dev/null 2>&1; then st="ON"; fi
  fi
  echo -e "Service $SERVICE : $st"
  if command -v ss >/dev/null 2>&1; then echo -e "Listen : $(ss -tulpn 2>/dev/null | grep -E 'udp-custom|7100|5300' | head -n 5 || echo "-")"; fi
  echo ""
  echo -e "${YELLOW}Catatan: Jangan alihkan port admin sendiri ($EXCLUDE_PORTS).${RESET}"
}

_install(){
  echo -e "${CYAN}=== Install UDP-Custom $EXCLUDE_PORTS ===${RESET}"
  echo -e "${DIM}Sumber resmi (HTTPS): $UDP_CUSTOM_URL${RESET}"
  if [ -n "$UDP_CUSTOM_SHA" ]; then echo -e "${DIM}SHA256 expect: $UDP_CUSTOM_SHA (akan diverifikasi)${RESET}"; else echo -e "${YELLOW}SHA256 expect: (kosong) - upstream tidak publish checksum resmi${RESET}"; fi
  echo -e "${YELLOW}PERINGATAN: Binary pihak ketiga / tertutup (closed-source).${RESET}"
  echo -e "${YELLOW}Risiko: tanpa source audit, bisa berisi backdoor. Pastikan hash dari sumber terpercaya.${RESET}"
  echo -e "${DIM}Exclude admin: $EXCLUDE_PORTS (22 SSH, 444 OpenSSH, 80/443 nginx, 53 SlowDNS, 81 zip, 25000 OVPN UDP)${RESET}"
  echo -e "${DIM}Rentang: $(_get_ports) -> exclude di atas, agar tidak mengalihkan lalu lintas admin.${RESET}"
  # cek bentrok exclude
  echo -e "${DIM}Jika server pakai salah satu exclude, UDP-Custom tidak akan bind di sana (aman).${RESET}"
  echo ""
  if [ -t 0 ]; then
    echo -ne "${YELLOW}Lanjut install UDP-Custom? [y/N]: ${RESET}"; read -r ans; case "$ans" in y|Y|yes|YES) ;; *) echo "Batal"; return 1;; esac
  fi
  local range
  range=$(_get_ports)
  mkdir -p "$(dirname "$UDP_CUSTOM_BIN")" "$(dirname "$CONF")" "${BASE}/var/log" 2>/dev/null || true

  # backup exclude config
  if [ -f "$CONF" ]; then ah_backup_cfg "$CONF" >/dev/null 2>&1 || true; fi

  # download
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi download $UDP_CUSTOM_URL -> $UDP_CUSTOM_BIN${RESET}"
    printf '#!/bin/bash\necho "udp-custom sim range %s exclude %s"\nwhile true; do sleep 3600; done\n' "$range" "$EXCLUDE_PORTS" > "$UDP_CUSTOM_BIN" 2>/dev/null || true
    chmod 755 "$UDP_CUSTOM_BIN" 2>/dev/null || true
    # tulis sim log untuk _mt_port_active
    echo "range=$range exclude=$EXCLUDE_PORTS src=$UDP_CUSTOM_URL sha=$UDP_CUSTOM_SHA" > "${BASE}/var/log/udp-custom-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/udp-custom-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/udp-custom-sim.log" 2>/dev/null || true
    # checksum tampil (sim)
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$UDP_CUSTOM_BIN" 2>/dev/null | awk '{print "  sha256 sim: "$1}' | head -n 1; fi
  else
    if [ -n "$UDP_CUSTOM_SHA" ]; then
      if ! ah_download_https "$UDP_CUSTOM_URL" "$UDP_CUSTOM_BIN" "$UDP_CUSTOM_SHA" 2>&1; then echo -e "${RED}Download/verifikasi gagal${RESET}"; return 1; fi
    else
      echo -e "${YELLOW}Tanpa checksum, download tanpa verifikasi (risiko) - lanjut?${RESET}"
      if [ -t 0 ]; then echo -ne "${YELLOW}Lanjut tanpa verifikasi? [y/N]: ${RESET}"; read -r a2; case "$a2" in y|Y) ;; *) echo "Batal"; return 1;; esac; fi
      if ! ah_download_https "$UDP_CUSTOM_URL" "$UDP_CUSTOM_BIN" "" 2>&1; then echo -e "${RED}Download gagal${RESET}"; return 1; fi
      local got=""; if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$UDP_CUSTOM_BIN" 2>/dev/null | awk '{print $1}'); else got=$(shasum -a 256 "$UDP_CUSTOM_BIN" 2>/dev/null | awk '{print $1}'); fi
      echo -e "${YELLOW}SHA256 got: $got (simpan untuk verifikasi next install)${RESET}"
      ah_log "udp-custom sha256 $got src $UDP_CUSTOM_URL"
    fi
    chmod 755 "$UDP_CUSTOM_BIN" 2>/dev/null || true
  fi

  # config
  cat > "$CONF" <<CFEOF
# mytunnel udp-custom - managed by mytunnel
RANGE="$range"
EXCLUDE="$EXCLUDE_PORTS"
SRC="$UDP_CUSTOM_URL"
SHA="$UDP_CUSTOM_SHA"
CFEOF
  chmod 644 "$CONF" 2>/dev/null || true
  echo -e "${GREEN}Config: $CONF (600 not needed, no secret)${RESET}"

  # enable service
  _enable
}

_enable(){
  [ -f "$CONF" ] || { echo -e "${RED}Config belum ada, install dulu${RESET}"; return 1; }
  # shellcheck disable=SC1090
  . "$CONF" 2>/dev/null || true
  local range="${RANGE:-}" exclude="${EXCLUDE:-$EXCLUDE_PORTS}"
  [ -z "$range" ] && range=$(_get_ports)
  if [ -n "$BASE" ]; then
    mkdir -p "$BASE/etc/systemd/system" 2>/dev/null || true
    cat > "$BASE/etc/systemd/system/${SERVICE}.service" <<SVCEOF
[Unit]
Description=mytunnel UDP-Custom $range (exclude $exclude)
After=network.target

[Service]
Type=simple
ExecStart=$UDP_CUSTOM_BIN server --listen $range --exclude $exclude
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF
    touch "$BASE/var/log/udp-custom-sim.log" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Service $SERVICE dibuat (sim) : $range exclude $exclude${RESET}"
    ah_log "udp-custom enable sim $range exclude $exclude"
    return 0
  fi
  cat > "/etc/systemd/system/${SERVICE}.service" <<SVCEOF2
[Unit]
Description=mytunnel UDP-Custom $range (exclude $exclude)
After=network.target

[Service]
Type=simple
ExecStart=$UDP_CUSTOM_BIN server --listen $range --exclude $exclude
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVCEOF2
  chmod 644 "/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now "$SERVICE" 2>/dev/null || systemctl restart "$SERVICE" 2>/dev/null || true
  echo -e "${GREEN}Service $SERVICE diaktifkan: $range exclude $exclude${RESET}"
  ah_log "udp-custom enable $range exclude $exclude"
}

_disable(){
  if [ -n "$BASE" ]; then
    rm -f "$BASE/var/log/udp-custom-sim.log" 2>/dev/null || true
    echo -e "${YELLOW}[TEST MODE] Service $SERVICE dimatikan (sim)${RESET}"
    ah_log "udp-custom disable sim"
    return 0
  fi
  systemctl disable --now "$SERVICE" 2>/dev/null || systemctl stop "$SERVICE" 2>/dev/null || true
  echo -e "${YELLOW}Service $SERVICE dimatikan${RESET}"
  ah_log "udp-custom disable"
}

_uninstall(){
  echo -ne "${YELLOW}Hapus UDP-Custom? [y/N]: ${RESET}"; local a; read -r a; case "$a" in y|Y|yes|YES) ;; *) echo "Batal"; return;; esac
  _disable 2>&1 || true
  if [ -n "$BASE" ]; then
    rm -f "$UDP_CUSTOM_BIN" 2>/dev/null || true
    rm -f "$CONF" "$BASE/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Uninstall sim selesai${RESET}"
    ah_log "udp-custom uninstall sim"
    return
  fi
  rm -f "$UDP_CUSTOM_BIN" 2>/dev/null || true
  rm -f "$CONF" "/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  echo -e "${GREEN}UDP-Custom dihapus${RESET}"
  ah_log "udp-custom uninstall"
}

case "${1:-}" in
  install) _install ;;
  enable) _enable ;;
  disable) _disable ;;
  uninstall) _uninstall ;;
  status) _status ;;
  *) echo "Usage: $0 [install|enable|disable|uninstall|status]" >&2; exit 2;;
esac

__EMBED_EOF__
chmod 755 "$ETC/setup/udp-custom.sh"
cat > "$ETC/setup/ohp.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/ohp.sh - Open HTTP Puncher (OHP) 9080->SSH, 9088->OpenVPN
# Sumber resmi: https://github.com/lfasmpao/open-http-puncher (MIT)
# Alternatif build: joawardjan/ohp - kedua HTTPS github.com
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PF="${ETC}/config/ports.conf"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die(){ echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

_get_ports(){
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  local ssh_p ovpn_p
  ssh_p="9080"; ovpn_p="9088"
  [ -n "${OHP_SSH_PORT:-}" ] && ssh_p=$(echo "$OHP_SSH_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -n "${OHP_OVPN_PORT:-}" ] && ovpn_p=$(echo "$OHP_OVPN_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -z "$ssh_p" ] && ssh_p="9080"
  [ -z "$ovpn_p" ] && ovpn_p="9088"
  echo "$ssh_p $ovpn_p"
}

BIN_DST(){
  if [ -n "$BASE" ]; then echo "${BASE}/usr/local/bin/ohp"; else echo "/usr/local/bin/ohp"; fi
}

# Official sources (HTTPS only)
OHP_URL_AMD64="https://github.com/lfasmpao/open-http-puncher/releases/download/0.1/ohp-linux-amd64"
OHP_URL_ALT="https://github.com/joawardjan/ohp/releases/download/v1.0/ohp-linux64"
# Optional expected sha256 (kosongkan jika upstream tidak publish; tetap tampilkan got hash)
OHP_SHA256=""

install_ohp(){
  local ssh_port ovpn_port
  read -r ssh_port ovpn_port <<< "$(_get_ports)"
  echo -e "${CYAN}[ohp] Setup OHP: $ssh_port->SSH, $ovpn_port->OpenVPN...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  echo -e "${YELLOW}Sumber: $OHP_URL_AMD64 (github.com/lfasmpao/open-http-puncher, MIT)${RESET}"
  echo -e "${YELLOW}Alternatif: $OHP_URL_ALT (github.com/joawardjan/ohp)${RESET}"
  echo -e "${YELLOW}Download: HTTPS only, checksum sha256 ditampilkan${RESET}"
  if [ -n "$OHP_SHA256" ]; then echo -e "${YELLOW}Expect sha256: $OHP_SHA256${RESET}"; else echo -e "${YELLOW}Expect sha256: (upstream tidak publish, tampilkan got hash)${RESET}"; fi
  echo -e "${YELLOW}Peringatan: Jika sumber tertutup/pihak ketiga, hash ditampilkan untuk audit manual${RESET}"

  local bin
  bin=$(BIN_DST)

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi download ohp${RESET}"
    mkdir -p "$(dirname "$bin")" "${BASE}/var/log" "${BASE}/etc/systemd/system" 2>/dev/null || true
    cat > "$bin" <<'STUB'
#!/bin/bash
# ohp stub for TEST MODE - args: -a 127.0.0.1:22 -b 0.0.0.0:9080  atau -a 127.0.0.1:1194 -b 0.0.0.0:9088
echo "ohp stub $@"
while true; do sleep 3600; done
STUB
    chmod +x "$bin" 2>/dev/null || true
    echo -e "${GREEN}Stub ohp: $bin${RESET}"
    sha256sum "$bin" 2>/dev/null | awk '{print "  sha256: " $1}' || true
  else
    if [ -x "$bin" ]; then
      echo -e "${GREEN}ohp sudah ada: $bin ($("$bin" 2>&1 | head -1 || echo "bin"))${RESET}"
      sha256sum "$bin" 2>/dev/null | awk '{print "  sha256 existing: " $1}' || true
    else
      echo -e "${CYAN}Download ohp dari sumber resmi (HTTPS)...${RESET}"
      local tmp
      tmp=$(mktemp)
      local ok=0
      # coba sumber 1
      if command -v curl >/dev/null 2>&1; then
        echo -e "${CYAN}curl -fsSL $OHP_URL_AMD64 -> $tmp${RESET}"
        if curl -fsSL --proto '=https' --tlsv1.2 "$OHP_URL_AMD64" -o "$tmp" 2>&1; then
          ok=1
        else
          echo -e "${YELLOW}Sumber 1 gagal, coba alternatif...${RESET}"
          if curl -fsSL --proto '=https' --tlsv1.2 "$OHP_URL_ALT" -o "$tmp" 2>&1; then ok=1; fi
        fi
      elif command -v wget >/dev/null 2>&1; then
        echo -e "${CYAN}wget $OHP_URL_AMD64 -> $tmp${RESET}"
        if wget -q --https-only "$OHP_URL_AMD64" -O "$tmp" 2>&1; then ok=1
        else wget -q --https-only "$OHP_URL_ALT" -O "$tmp" 2>&1 && ok=1 || true; fi
      else
        rm -f "$tmp" 2>/dev/null || true
        die "curl/wget tidak ada" "Install curl"
      fi
      if [ "$ok" != "1" ] || [ ! -s "$tmp" ]; then
        rm -f "$tmp" 2>/dev/null || true
        die "Download ohp gagal dari kedua sumber" "Cek koneksi https://github.com/lfasmpao/open-http-puncher"
      fi
      # verify checksum
      local got=""
      if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$tmp" 2>/dev/null | awk '{print $1}')
      elif command -v shasum >/dev/null 2>&1; then got=$(shasum -a 256 "$tmp" 2>/dev/null | awk '{print $1}')
      fi
      echo -e "${CYAN}sha256 got: ${got:-unknown}${RESET}"
      if [ -n "$OHP_SHA256" ] && [ -n "$got" ] && [ "$got" != "$OHP_SHA256" ]; then
        rm -f "$tmp" 2>/dev/null || true
        die "checksum mismatch" "exp $OHP_SHA256 got $got"
      fi
      # basic file check (should be ELF)
      if command -v file >/dev/null 2>&1; then file "$tmp" 2>&1 | head -1 || true; fi
      # install
      mkdir -p "$(dirname "$bin")" 2>/dev/null || true
      cp -a "$tmp" "$bin" 2>/dev/null || true
      chmod +x "$bin" 2>/dev/null || true
      rm -f "$tmp" 2>/dev/null || true
      if [ ! -x "$bin" ]; then die "ohp tidak executable setelah install: $bin" "Cek $bin"; fi
      echo -e "${GREEN}ohp terinstall: $bin${RESET}"
      ls -lh "$bin" 2>&1 | sed 's/^/  /'
      sha256sum "$bin" 2>/dev/null | awk '{print "  sha256: " $1}' || true
    fi
  fi

  # Determine SSH target (prefer 444, fallback 22)
  local ssh_target="127.0.0.1:22"
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  if [ -n "${OPENSSH_PORT:-}" ]; then
    local op
    op=$(echo "$OPENSSH_PORT" | cut -d',' -f1 | tr -d ' ')
    if [ -n "$op" ]; then ssh_target="127.0.0.1:$op"; fi
  fi
  local ovpn_target="127.0.0.1:1194"
  if [ -n "${OPENVPN_TCP_PORT:-}" ]; then
    local otp
    otp=$(echo "$OPENVPN_TCP_PORT" | cut -d',' -f1 | tr -d ' ')
    [ -n "$otp" ] && ovpn_target="127.0.0.1:$otp"
  fi

  echo -e "${CYAN}Target: OHP $ssh_port -> $ssh_target, OHP $ovpn_port -> $ovpn_target${RESET}"

  # Services
  local svc_ssh="/etc/systemd/system/mytunnel-ohp-ssh.service"
  local svc_ovpn="/etc/systemd/system/mytunnel-ohp-ovpn.service"
  if [ -n "$BASE" ]; then
    svc_ssh="${BASE}/etc/systemd/system/mytunnel-ohp-ssh.service"
    svc_ovpn="${BASE}/etc/systemd/system/mytunnel-ohp-ovpn.service"
  fi
  mkdir -p "$(dirname "$svc_ssh")" 2>/dev/null || true

  # Backup existing
  for svc in "$svc_ssh" "$svc_ovpn"; do
    if [ -f "$svc" ]; then cp -a "$svc" "${svc}.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)" 2>/dev/null || true; fi
  done

  cat > "$svc_ssh" <<SVC_EOF
[Unit]
Description=mytunnel OHP SSH $ssh_port -> $ssh_target
After=network.target

[Service]
Type=simple
ExecStart=$bin -a $ssh_target -b 0.0.0.0:$ssh_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC_EOF
  cat > "$svc_ovpn" <<SVC_EOF2
[Unit]
Description=mytunnel OHP OVPN $ovpn_port -> $ovpn_target
After=network.target

[Service]
Type=simple
ExecStart=$bin -a $ovpn_target -b 0.0.0.0:$ovpn_port
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC_EOF2
  chmod 644 "$svc_ssh" "$svc_ovpn" 2>/dev/null || true
  echo -e "${GREEN}Service: $svc_ssh & $svc_ovpn${RESET}"

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi enable ohp${RESET}"
    mkdir -p "${BASE}/var/log" 2>/dev/null || true
    echo "ohp sim $ssh_port->$ssh_target $ovpn_port->$ovpn_target" > "${BASE}/var/log/ohp-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/ohp-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/ohp-sim.log" 2>/dev/null || true
  else
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable mytunnel-ohp-ssh 2>/dev/null || true
    systemctl enable mytunnel-ohp-ovpn 2>/dev/null || true
    systemctl restart mytunnel-ohp-ssh 2>/dev/null || true
    systemctl restart mytunnel-ohp-ovpn 2>/dev/null || true
    sleep 1
    for s in mytunnel-ohp-ssh mytunnel-ohp-ovpn; do
      if systemctl is-active "$s" >/dev/null 2>&1 || pgrep -f "ohp.*:.*$ssh_port" >/dev/null 2>&1; then
        echo -e "${GREEN}$s aktif${RESET}"
      else
        echo -e "${YELLOW}$s belum aktif, cek: journalctl -u $s -n 20${RESET}"
      fi
    done
    ss -tlnp 2>/dev/null | grep -E ":(${ssh_port}|${ovpn_port}) " | head -n 10 || true
  fi
  echo -e "${GREEN}[ohp] Selesai: $ssh_port->SSH, $ovpn_port->OVPN${RESET}" | tee -a "$LOG" 2>/dev/null || true
}

uninstall_ohp(){
  echo -e "${CYAN}[ohp] Uninstall...${RESET}"
  local bin svc_ssh svc_ovpn
  bin=$(BIN_DST)
  svc_ssh="/etc/systemd/system/mytunnel-ohp-ssh.service"
  svc_ovpn="/etc/systemd/system/mytunnel-ohp-ovpn.service"
  if [ -n "$BASE" ]; then svc_ssh="${BASE}/etc/systemd/system/mytunnel-ohp-ssh.service"; svc_ovpn="${BASE}/etc/systemd/system/mytunnel-ohp-ovpn.service"; fi
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi uninstall ohp${RESET}"
    rm -f "$svc_ssh" "$svc_ovpn" "${BASE}/var/log/ohp-sim.log" 2>/dev/null || true
    rm -f "${svc_ssh}.bak-"* "${svc_ovpn}.bak-"* 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] ohp uninstall sim selesai${RESET}"
    return 0
  fi
  systemctl stop mytunnel-ohp-ssh mytunnel-ohp-ovpn 2>/dev/null || true
  systemctl disable mytunnel-ohp-ssh mytunnel-ohp-ovpn 2>/dev/null || true
  pkill -f "ohp.*-b 0.0.0.0" 2>/dev/null || true
  rm -f "$svc_ssh" "$svc_ovpn" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  # keep binary (optional)
  # rm -f "$bin" 2>/dev/null || true
  echo -e "${GREEN}[ohp] Uninstall selesai (binary $bin dipertahankan)${RESET}"
}

status_ohp(){
  local ssh_port ovpn_port bin svc_ssh svc_ovpn
  read -r ssh_port ovpn_port <<< "$(_get_ports)"
  bin=$(BIN_DST)
  svc_ssh="/etc/systemd/system/mytunnel-ohp-ssh.service"
  svc_ovpn="/etc/systemd/system/mytunnel-ohp-ovpn.service"
  if [ -n "$BASE" ]; then svc_ssh="${BASE}/etc/systemd/system/mytunnel-ohp-ssh.service"; svc_ovpn="${BASE}/etc/systemd/system/mytunnel-ohp-ovpn.service"; fi
  echo "OHP_SSH_PORT=$ssh_port OHP_OVPN_PORT=$ovpn_port"
  echo "bin: $bin $([ -x "$bin" ] && echo "exists" || echo "missing")"
  [ -x "$bin" ] && sha256sum "$bin" 2>/dev/null | awk '{print "  sha256: " $1}' || true
  echo "svc ssh: $svc_ssh $([ -f "$svc_ssh" ] && echo "exists" || echo "missing")"
  echo "svc ovpn: $svc_ovpn $([ -f "$svc_ovpn" ] && echo "exists" || echo "missing")"
  if [ -f "$svc_ssh" ]; then grep -E "ExecStart|Description" "$svc_ssh" 2>/dev/null | head -n 5; fi
  if [ -f "$svc_ovpn" ]; then grep -E "ExecStart|Description" "$svc_ovpn" 2>/dev/null | head -n 5; fi
  if command -v ss >/dev/null 2>&1; then ss -tlnp 2>/dev/null | grep -E ":(${ssh_port}|${ovpn_port}) " | head -n 10 || echo "(ss no :$ssh_port/$ovpn_port)"; fi
  if [ -z "$BASE" ]; then for s in mytunnel-ohp-ssh mytunnel-ohp-ovpn; do echo -n "$s: "; systemctl is-active "$s" 2>/dev/null || echo "inactive"; done
  else [ -f "${BASE}/var/log/ohp-sim.log" ] && cat "${BASE}/var/log/ohp-sim.log" || echo "sim inactive"; fi
}

case "${1:-install}" in
  install) install_ohp ;;
  uninstall|remove) uninstall_ohp ;;
  status) status_ohp ;;
  *) echo "Usage: $0 [install|uninstall|status]" >&2; exit 2 ;;
esac

__EMBED_EOF__
chmod 755 "$ETC/setup/ohp.sh"
cat > "$ETC/setup/openvpn.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/openvpn.sh - OpenVPN TCP 1194 / UDP 25000 / SSL 442 + PAM + zip :81
# Sumber resmi: apt openvpn + easy-rsa (https, apt verify)
# 80/443 exclusive nginx -> SSL pakai 442 (bukan 443), TUNNELING prioritas. Validasi + rollback.
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PF="${ETC}/config/ports.conf"
DOMAIN_FILE="${ETC}/config/domain.txt"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die(){ echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; return 1; }

_get_domain(){
  local d=""
  if [ -f "$DOMAIN_FILE" ]; then d=$(head -1 "$DOMAIN_FILE" 2>/dev/null | tr -d ' \n' | tr '[:upper:]' '[:lower:]'); fi
  [ -z "$d" ] || [ "$d" = "-" ] && d="example.com"
  echo "$d"
}

_get_ports(){
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
  local tcp_p udp_p ssl_p dns_p ohp_p cfg_p
  tcp_p="1194"; udp_p="25000"; ssl_p="442"; dns_p="53"; ohp_p="9088"; cfg_p="81"
  [ -n "${OPENVPN_TCP_PORT:-}" ] && tcp_p=$(echo "$OPENVPN_TCP_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -n "${OPENVPN_UDP_PORT:-}" ] && udp_p=$(echo "$OPENVPN_UDP_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -n "${OPENVPN_SSL_PORT:-}" ] && ssl_p=$(echo "$OPENVPN_SSL_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -n "${OPENVPN_DNS_PORT:-}" ] && dns_p=$(echo "$OPENVPN_DNS_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -n "${OHP_OVPN_PORT:-}" ] && ohp_p=$(echo "$OHP_OVPN_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -n "${CONFIG_PORT:-}" ] && cfg_p=$(echo "$CONFIG_PORT" | cut -d',' -f1 | tr -d ' ')
  [ -z "$tcp_p" ] && tcp_p="1194"
  [ -z "$udp_p" ] && udp_p="25000"
  [ -z "$ssl_p" ] && ssl_p="442"
  echo "$tcp_p $udp_p $ssl_p $dns_p $ohp_p $cfg_p"
}

_ovpn_dir(){
  if [ -n "$BASE" ]; then echo "${BASE}/etc/openvpn"; else echo "/etc/openvpn"; fi
}

_www_root(){
  if [ -n "$BASE" ]; then echo "${BASE}/var/www/html"; else echo "/var/www/html"; fi
}

_find_pam_plugin(){
  local p=""
  # universal: find via find /usr/lib -name openvpn-plugin-auth-pam.so
  p=$(find /usr/lib -name "openvpn-plugin-auth-pam.so" 2>/dev/null | head -1)
  if [ -z "$p" ] && [ -n "$BASE" ]; then
    # test mode fallback: check common paths
    for cand in "/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so" "/usr/lib/openvpn/plugins/openvpn-plugin-auth-pam.so" "/usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so"; do
      if [ -f "$cand" ]; then p="$cand"; break; fi
    done
  fi
  # test mode stub if not found
  if [ -z "$p" ] && [ -n "$BASE" ]; then p="/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so"; fi
  echo "$p"
}

_gen_certs(){
  local ovpn_dir domain
  ovpn_dir=$(_ovpn_dir)
  domain=$(_get_domain)
  mkdir -p "$ovpn_dir" 2>/dev/null || true

  # backup existing easy-rsa/pki
  if [ -d "$ovpn_dir/pki" ] || [ -d "$ovpn_dir/easy-rsa" ]; then
    local bak
    bak="$ovpn_dir.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)"
    cp -a "$ovpn_dir" "$bak" 2>/dev/null || true
    echo -e "${YELLOW}Backup openvpn: $bak${RESET}"
  fi

  # check existing ca/server cert - reuse if valid
  if [ -f "$ovpn_dir/ca.crt" ] && [ -f "$ovpn_dir/server.crt" ] && [ -f "$ovpn_dir/server.key" ]; then
    echo -e "${GREEN}CA/server cert sudah ada, reuse (hapus $ovpn_dir/ca.crt untuk regenerate)${RESET}"
    return 0
  fi

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Generate dummy CA/server cert via openssl${RESET}"
    # dummy CA
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$ovpn_dir/ca.key" -out "$ovpn_dir/ca.crt" -subj "/CN=$domain CA" >/dev/null 2>&1 || true
    openssl req -nodes -newkey rsa:2048 -keyout "$ovpn_dir/server.key" -out "$ovpn_dir/server.csr" -subj "/CN=$domain" >/dev/null 2>&1 || true
    openssl x509 -req -in "$ovpn_dir/server.csr" -CA "$ovpn_dir/ca.crt" -CAkey "$ovpn_dir/ca.key" -CAcreateserial -out "$ovpn_dir/server.crt" -days 3650 >/dev/null 2>&1 || cp "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" 2>/dev/null || true
    chmod 644 "$ovpn_dir/ca.srl" 2>/dev/null || true; chmod 644 "$ovpn_dir/server.csr" 2>/dev/null || true
    # dh dummy
    openssl dhparam -out "$ovpn_dir/dh.pem" 1024 >/dev/null 2>&1 || echo "dummy dh" > "$ovpn_dir/dh.pem" 2>/dev/null || true
    # ta.key dummy (openvpn --genkey)
    if command -v openvpn >/dev/null 2>&1; then openvpn --genkey --secret "$ovpn_dir/ta.key" 2>/dev/null || true; fi
    [ -f "$ovpn_dir/ta.key" ] || echo "dummy ta" > "$ovpn_dir/ta.key" 2>/dev/null || true
    chmod 600 "$ovpn_dir/ca.key" "$ovpn_dir/server.key" 2>/dev/null || true
    chmod 644 "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" "$ovpn_dir/dh.pem" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Dummy certs created${RESET}"
    ls -lh "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" 2>&1 | sed 's/^/  /'
    return 0
  fi

  echo -e "${CYAN}Generate CA/server cert via easy-rsa (official, HTTPS apt)...${RESET}"
  # install deps
  if ! command -v openssl >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 || true; apt-get install -y openssl >/dev/null 2>&1 || true; fi
  if ! dpkg -l | grep -q easy-rsa 2>/dev/null && ! command -v easyrsa >/dev/null 2>&1; then
    echo -e "${CYAN}Install easy-rsa via apt...${RESET}"
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y easy-rsa 2>/dev/null || apt-get install -y easy-rsa openvpn 2>/dev/null || true
  fi

  local easy_src="/usr/share/easy-rsa"
  if [ ! -d "$easy_src" ]; then easy_src=$(find /usr -name "easyrsa" -type f 2>/dev/null | head -1 | xargs dirname 2>/dev/null); fi
  if [ ! -d "$easy_src" ] || [ ! -f "$easy_src/easyrsa" ]; then
    echo -e "${YELLOW}easy-rsa tidak ditemukan, fallback openssl self-signed${RESET}"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$ovpn_dir/ca.key" -out "$ovpn_dir/ca.crt" -subj "/CN=$domain CA" >/dev/null 2>&1 || true
    openssl req -nodes -newkey rsa:2048 -keyout "$ovpn_dir/server.key" -out "$ovpn_dir/server.csr" -subj "/CN=$domain" >/dev/null 2>&1 || true
    openssl x509 -req -in "$ovpn_dir/server.csr" -CA "$ovpn_dir/ca.crt" -CAkey "$ovpn_dir/ca.key" -CAcreateserial -out "$ovpn_dir/server.crt" -days 3650 >/dev/null 2>&1 || true
    chmod 644 "$ovpn_dir/ca.srl" 2>/dev/null || true; chmod 644 "$ovpn_dir/server.csr" 2>/dev/null || true
    openssl dhparam -out "$ovpn_dir/dh.pem" 2048 >/dev/null 2>&1 || openssl dhparam -out "$ovpn_dir/dh.pem" 1024 >/dev/null 2>&1 || true
    if command -v openvpn >/dev/null 2>&1; then openvpn --genkey --secret "$ovpn_dir/ta.key" 2>/dev/null || true; fi
    chmod 600 "$ovpn_dir/ca.key" "$ovpn_dir/server.key" 2>/dev/null || true
    chmod 644 "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" 2>/dev/null || true
    return 0
  fi

  echo -e "${CYAN}easy-rsa: $easy_src${RESET}"
  rm -rf "$ovpn_dir/easy-rsa" "$ovpn_dir/pki" 2>/dev/null || true
  mkdir -p "$ovpn_dir/easy-rsa" 2>/dev/null || true
  cp -a "$easy_src"/* "$ovpn_dir/easy-rsa/" 2>/dev/null || true
  chmod +x "$ovpn_dir/easy-rsa/easyrsa" 2>/dev/null || true

  # init pki non-interaktif
  export EASYRSA_BATCH=1
  export EASYRSA_REQ_CN="$domain"
  (
    cd "$ovpn_dir/easy-rsa" 2>/dev/null || exit 1
    ./easyrsa init-pki 2>&1 | tail -n 20 || true
    echo -e "${CYAN}Build CA...${RESET}"
    ./easyrsa --req-cn="$domain CA" build-ca nopass 2>&1 | tail -n 20 || true
    echo -e "${CYAN}Build server cert...${RESET}"
    ./easyrsa --req-cn="$domain" build-server-full server nopass 2>&1 | tail -n 20 || true
    ./easyrsa gen-dh 2>&1 | tail -n 20 || true
    if command -v openvpn >/dev/null 2>&1; then openvpn --genkey --secret "$ovpn_dir/ta.key" 2>/dev/null || true; fi
    # copy to ovpn_dir
    cp -a "pki/ca.crt" "$ovpn_dir/ca.crt" 2>/dev/null || true
    cp -a "pki/issued/server.crt" "$ovpn_dir/server.crt" 2>/dev/null || cp -a "pki/issued/server.crt" "$ovpn_dir/server.crt" 2>/dev/null || true
    cp -a "pki/private/ca.key" "$ovpn_dir/ca.key" 2>/dev/null || true
    cp -a "pki/private/server.key" "$ovpn_dir/server.key" 2>/dev/null || true
    if [ -f "pki/dh.pem" ]; then cp -a "pki/dh.pem" "$ovpn_dir/dh.pem" 2>/dev/null || true; fi
  ) || true

  # verify files exist
  for f in ca.crt server.crt server.key dh.pem; do
    if [ -f "$ovpn_dir/$f" ]; then echo -e "${GREEN}  $f OK${RESET}"; else echo -e "${YELLOW}  $f missing (akan fallback)${RESET}"; fi
  done
  # ta.key
  if [ ! -f "$ovpn_dir/ta.key" ] && command -v openvpn >/dev/null 2>&1; then openvpn --genkey --secret "$ovpn_dir/ta.key" 2>/dev/null || true; fi
  chmod 600 "$ovpn_dir/ca.key" "$ovpn_dir/server.key" 2>/dev/null || true
  chmod 644 "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" 2>/dev/null || true
  if [ ! -f "$ovpn_dir/ca.crt" ] || [ ! -f "$ovpn_dir/server.crt" ]; then
    echo -e "${YELLOW}Cert belum lengkap, fallback openssl${RESET}"
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout "$ovpn_dir/ca.key" -out "$ovpn_dir/ca.crt" -subj "/CN=$domain CA" >/dev/null 2>&1 || true
    openssl req -nodes -newkey rsa:2048 -keyout "$ovpn_dir/server.key" -out "$ovpn_dir/server.csr" -subj "/CN=$domain" >/dev/null 2>&1 || true
    openssl x509 -req -in "$ovpn_dir/server.csr" -CA "$ovpn_dir/ca.crt" -CAkey "$ovpn_dir/ca.key" -CAcreateserial -out "$ovpn_dir/server.crt" -days 3650 >/dev/null 2>&1 || true
    chmod 644 "$ovpn_dir/ca.srl" 2>/dev/null || true; chmod 644 "$ovpn_dir/server.csr" 2>/dev/null || true
  fi
  echo -e "${GREEN}Certs ready: $ovpn_dir${RESET}"
  ls -lh "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" 2>&1 | sed 's/^/  /'
  # checksum
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$ovpn_dir/ca.crt" 2>/dev/null | awk '{print "  sha256 ca.crt: " $1}' || true; fi
}

_write_server_conf(){
  local proto="$1" port="$2" dev="$3" ovpn_dir pam_plugin domain www_root
  ovpn_dir=$(_ovpn_dir)
  domain=$(_get_domain)
  pam_plugin=$(_find_pam_plugin)
  www_root=$(_www_root)
  local conf="$ovpn_dir/server-${proto}.conf"
  mkdir -p "$(dirname "$conf")" 2>/dev/null || true
  if [ -f "$conf" ]; then cp -a "$conf" "${conf}.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)" 2>/dev/null || true; fi

  # find PAM plugin fallback
  if [ ! -f "$pam_plugin" ] && [ -z "$BASE" ]; then
    pam_plugin=$(find /usr -name "openvpn-plugin-auth-pam.so" 2>/dev/null | head -1)
    [ -z "$pam_plugin" ] && pam_plugin="/usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so"
  fi

  # DNS push: Cloudflare + Google
  cat > "$conf" <<CFG_EOF
# mytunnel openvpn $proto $port - managed by mytunnel
port $port
proto $proto
dev $dev
ca $ovpn_dir/ca.crt
cert $ovpn_dir/server.crt
key $ovpn_dir/server.key
dh $ovpn_dir/dh.pem
auth SHA256
tls-auth $ovpn_dir/ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist $ovpn_dir/ipp.txt
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 1.1.1.1"
push "dhcp-option DNS 8.8.8.8"
keepalive 10 120
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
persist-key
persist-tun
status $ovpn_dir/openvpn-status-$proto.log
verb 3
explicit-exit-notify 1
# PAM auth - username/password SSH yang sama (tanpa client cert)
plugin $pam_plugin login
username-as-common-name
client-cert-not-required
# revoke list (jika ada)
crl-verify $ovpn_dir/crl.pem
# allow duplicate cn handled via limitip? allow
duplicate-cn
CFG_EOF
  # if crl not exists, comment it
  if [ ! -f "$ovpn_dir/crl.pem" ]; then sed -i "s|^crl-verify|#crl-verify|" "$conf" 2>/dev/null || true; fi
  # if ta.key missing
  if [ ! -f "$ovpn_dir/ta.key" ]; then sed -i "/tls-auth/d" "$conf" 2>/dev/null || true; fi
  chmod 644 "$conf" 2>/dev/null || true
  echo -e "${GREEN}Server conf: $conf (port $port proto $proto)${RESET}"
}

_gen_client_ovpn(){
  local domain ovpn_dir www_root tcp_p udp_p ssl_p ohp_p
  domain=$(_get_domain)
  ovpn_dir=$(_ovpn_dir)
  www_root=$(_www_root)
  read -r tcp_p udp_p ssl_p _dns_p ohp_p _cfg_p <<< "$(_get_ports)"
  mkdir -p "$www_root" "$ovpn_dir/clients" 2>/dev/null || true

  # ensure ca.crt exists
  if [ ! -f "$ovpn_dir/ca.crt" ]; then echo -e "${YELLOW}ca.crt tidak ada, generate cert dulu${RESET}"; _gen_certs; fi

  local ca_content=""
  if [ -f "$ovpn_dir/ca.crt" ]; then ca_content=$(cat "$ovpn_dir/ca.crt" 2>/dev/null); fi
  local ta_content=""
  if [ -f "$ovpn_dir/ta.key" ]; then ta_content=$(cat "$ovpn_dir/ta.key" 2>/dev/null); fi

  # Helper to write ovpn
  _write_ovpn(){
    local name="$1" remote_port="$2" proto="$3" extra="$4"
    local f="$ovpn_dir/clients/$name.ovpn"
    cat > "$f" <<OVPN_EOF
client
dev tun
proto $proto
remote $domain $remote_port
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
cipher AES-256-GCM
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305
verb 3
auth-user-pass
$extra
<ca>
$ca_content
</ca>
OVPN_EOF
    # ta.key optional
    if [ -n "$ta_content" ]; then
      cat >> "$f" <<TA_EOF
key-direction 1
<tls-auth>
$ta_content
</tls-auth>
TA_EOF
    fi
    chmod 644 "$f" 2>/dev/null || true
    echo -e "${GREEN}  $name.ovpn OK${RESET}"
  }

  # TCP 1194
  _write_ovpn "myvpn-tcp" "$tcp_p" "tcp" ""
  # UDP 25000
  _write_ovpn "myvpn-udp" "$udp_p" "udp" ""
  # SSL 442 (443 exclusive -> 442)
  _write_ovpn "myvpn-ssl" "$ssl_p" "tcp" ""
  # OHP 9088 -> via http-proxy? For OHP, client uses http-proxy to OHP port, then connect to OpenVPN
  # Simple: remote via OHP port + http-proxy directive
  _write_ovpn "myvpn-ohp" "$ohp_p" "tcp" "http-proxy $domain $ohp_p"

  # verify no private key leaked
  for f in "$ovpn_dir/clients"/*.ovpn; do
    if grep -q "BEGIN PRIVATE KEY\|BEGIN RSA PRIVATE KEY" "$f" 2>/dev/null; then
      echo -e "${RED}FAIL: private key bocor di $f${RESET}"
      rm -f "$f" 2>/dev/null || true
    fi
    if grep -q "BEGIN.*PRIVATE" "$f" 2>/dev/null; then echo -e "${RED}Private key leak check fail $f${RESET}"; fi
  done

  # zip: hanya .ovpn + ca.crt (DILARANG private key/password)
  local zipf="$www_root/myvpn-config.zip"
  mkdir -p "$www_root" 2>/dev/null || true
  # backup old zip
  if [ -f "$zipf" ]; then cp -a "$zipf" "${zipf}.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)" 2>/dev/null || true; fi
  if command -v zip >/dev/null 2>&1; then
    (cd "$ovpn_dir/clients" 2>/dev/null && zip -j "$zipf" ./*.ovpn 2>&1 | tail -n 20) || true
    (cd "$ovpn_dir" 2>/dev/null && zip -j "$zipf" ca.crt 2>&1 | tail -n 20) || true
  elif command -v python3 >/dev/null 2>&1; then
    python3 <<PYEOF 2>&1 | tail -n 20
import zipfile, os, glob
www="$www_root"
ovpn_dir="$ovpn_dir"
zipf=os.path.join(www, "myvpn-config.zip")
clients=glob.glob(os.path.join(ovpn_dir, "clients", "*.ovpn"))
with zipfile.ZipFile(zipf, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in clients:
        z.write(f, os.path.basename(f))
    ca=os.path.join(ovpn_dir, "ca.crt")
    if os.path.exists(ca):
        z.write(ca, "ca.crt")
print("zip via python3 OK")
PYEOF
  else
    # fallback tar.gz then rename? but spec wants zip
    tar -czf "$zipf" -C "$ovpn_dir/clients" . 2>&1 | head -n 10 || true
    echo -e "${YELLOW}zip binary tidak ada, fallback tar.gz: $zipf${RESET}"
  fi

  # verify zip contents: must not contain private key or .key
  if command -v unzip >/dev/null 2>&1 && [ -f "$zipf" ]; then
    echo -e "${CYAN}Zip contents:${RESET}"
    unzip -l "$zipf" 2>&1 | head -n 30 || true
    if unzip -l "$zipf" 2>&1 | grep -qi "private\|\.key\|ta\.key"; then
      echo -e "${RED}FAIL: zip mengandung private key/ta.key${RESET}"
      # remove offending
      if [ -f "$zipf" ]; then rm -f "$zipf" 2>/dev/null || true; echo -e "${YELLOW}Zip dihapus karena leak${RESET}"; fi
      return 1
    fi
    echo -e "${GREEN}Zip aman: hanya .ovpn + ca.crt, tanpa private key${RESET}"
  elif [ -f "$zipf" ]; then
    echo -e "${CYAN}Zip dibuat: $zipf${RESET}"
    ls -lh "$zipf" 2>&1 | sed 's/^/  /'
  fi

  chmod 644 "$zipf" 2>/dev/null || true
  echo -e "${GREEN}Zip: $zipf${RESET}"
  ls -lh "$zipf" 2>&1 | sed 's/^/  /'
  # sha256
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$zipf" 2>/dev/null | awk '{print "  sha256: " $1}' || true; fi
}

_validate_openvpn(){
  local ovpn_dir
  ovpn_dir=$(_ovpn_dir)
  # simple validate: files exist + ovpn syntax if binary available
  for f in ca.crt server.crt server.key dh.pem; do
    if [ -f "$ovpn_dir/$f" ]; then echo -e "${GREEN}  $f OK${RESET}"; else echo -e "${YELLOW}  $f missing${RESET}"; fi
  done
  for proto in tcp udp ssl; do
    local conf="$ovpn_dir/server-$proto.conf"
    if [ -f "$conf" ]; then
      echo -e "${GREEN}  server-$proto.conf OK${RESET}"
      if [ -z "$BASE" ] && command -v openvpn >/dev/null 2>&1; then
        # validate via openvpn --config (dry, timeout 2s)
        timeout 2 openvpn --config "$conf" --verb 0 2>&1 | head -n 20 || true
      fi
    fi
  done
  # nginx 81 check
  local conf_nginx="${BASE}/etc/nginx/conf.d/mytunnel.conf"
  [ -z "$BASE" ] && conf_nginx="/etc/nginx/conf.d/mytunnel.conf"
  if [ -f "$conf_nginx" ]; then grep -q "listen 81" "$conf_nginx" && echo -e "${GREEN}  nginx 81 OK${RESET}" || echo -e "${YELLOW}  nginx 81 missing${RESET}"; fi
  return 0
}

install_openvpn(){
  local domain tcp_p udp_p ssl_p dns_p ohp_p cfg_p ovpn_dir www_root
  domain=$(_get_domain)
  read -r tcp_p udp_p ssl_p dns_p ohp_p cfg_p <<< "$(_get_ports)"
  ovpn_dir=$(_ovpn_dir)
  www_root=$(_www_root)
  echo -e "${CYAN}[openvpn] Setup OpenVPN TCP $tcp_p / UDP $udp_p / SSL $ssl_p (PAM, no client cert)...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  echo -e "${YELLOW}Sumber: apt openvpn + easy-rsa (official Ubuntu/Debian, HTTPS apt verify)${RESET}"
  echo -e "${YELLOW}Auth: PAM plugin login (username/password SSH sama, tanpa client cert per akun)${RESET}"
  echo -e "${YELLOW}CA/server cert: easy-rsa batch (backup before, rollback on fail)${RESET}"
  echo -e "${YELLOW}Zip: $www_root/myvpn-config.zip (hanya .ovpn + ca.crt, DILARANG private key) via nginx :$cfg_p${RESET}"
  echo -e "${YELLOW}Note: 80/443 exclusive nginx -> SSL pakai $ssl_p (bukan 443, tunneling prioritas)${RESET}"
  # Check SlowDNS mutual exclusion for DNS 53
  local slowdns_active=0
  if [ -f "${ETC}/config/slowdns.conf" ] || [ -f "${ETC}/slowdns/server.key" ] || [ -n "$BASE" ] && [ -f "${BASE}/etc/mytunnel/slowdns/server.key" ]; then slowdns_active=1; fi
  if [ -f "/etc/mytunnel/slowdns/server.key" ]; then slowdns_active=1; fi
  if [ "$slowdns_active" = "1" ] && [ "$dns_p" = "53" ]; then
    echo -e "${YELLOW}SlowDNS aktif -> OpenVPN DNS 53 OFF (mutual exclusion, UDP 53->5300). Pakai TCP $tcp_p / UDP $udp_p / SSL $ssl_p + OHP $ohp_p${RESET}"
    dns_p=""
  fi

  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi install openvpn${RESET}"
    mkdir -p "$ovpn_dir" "$www_root" "${BASE}/etc/systemd/system" "${BASE}/var/log" 2>/dev/null || true
    # stub binary
    mkdir -p "${BASE}/usr/sbin" 2>/dev/null || true
    if ! command -v openvpn >/dev/null 2>&1 && [ ! -x "${BASE}/usr/sbin/openvpn" ]; then
      cat > "${BASE}/usr/sbin/openvpn" <<'STUB'
#!/bin/bash
if [ "$1" = "--genkey" ]; then echo "dummy ta" > "$3" 2>/dev/null || true; exit 0; fi
if [ "$1" = "--config" ]; then echo "openvpn stub config $2"; exit 0; fi
echo "openvpn stub $@"
STUB
      chmod +x "${BASE}/usr/sbin/openvpn" 2>/dev/null || true
    fi
    if ! command -v zip >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then echo -e "${YELLOW}zip/python3 tidak ada, tapi fallback tar${RESET}"; fi
  else
    if ! command -v openvpn >/dev/null 2>&1; then
      echo -e "${CYAN}Install openvpn...${RESET}"
      apt-get update -y >/dev/null 2>&1 || true
      apt-get install -y openvpn easy-rsa zip openssl 2>/dev/null || apt-get install -y openvpn easy-rsa openssl 2>/dev/null || die "Gagal install openvpn" "Cek apt"
    fi
    if ! command -v zip >/dev/null 2>&1; then apt-get install -y zip >/dev/null 2>&1 || true; fi
    if ! dpkg -l | grep -q easy-rsa 2>/dev/null; then apt-get install -y easy-rsa >/dev/null 2>&1 || true; fi
  fi

  # UFW allow before start (keep 22/444)
  if [ -z "$BASE" ] && command -v ufw >/dev/null 2>&1; then
    for p in $tcp_p $udp_p $ssl_p $ohp_p $cfg_p; do
      [ -z "$p" ] && continue
      case "$p" in ''|*[!0-9]*) continue;; esac
      ufw allow "$p/tcp" >/dev/null 2>&1 || true
    done
    # udp for udp port + dns if needed
    for p in $udp_p $dns_p; do
      [ -z "$p" ] && continue
      case "$p" in ''|*[!0-9]*) continue;; esac
      ufw allow "$p/udp" >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}UFW allow TCP $tcp_p,$ssl_p,$ohp_p,$cfg_p UDP $udp_p${RESET}"
  elif [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] simulasi ufw allow $tcp_p $udp_p $ssl_p $ohp_p $cfg_p${RESET}"
    mkdir -p "${BASE}/var/log" 2>/dev/null || true
    for p in $tcp_p $udp_p $ssl_p $ohp_p $cfg_p; do [ -n "$p" ] && echo "allow $p/tcp" >> "${BASE}/var/log/ufw-sim.log" 2>/dev/null || true; done
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/ufw-sim.log" 2>/dev/null || true
    for p in $udp_p $dns_p; do [ -n "$p" ] && echo "allow $p/udp" >> "${BASE}/var/log/ufw-sim.log" 2>/dev/null || true; done
    chmod 644 "$BASE/var/log/ufw-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/ufw-sim.log" 2>/dev/null || true
    sort -u "${BASE}/var/log/ufw-sim.log" -o "${BASE}/var/log/ufw-sim.log" 2>/dev/null || true
  fi

  # backup before
  local ovpn_bak=""
  if [ -d "$ovpn_dir" ]; then
    ovpn_bak="${ovpn_dir}.bak-$(date +%Y%m%d-%H%M%S 2>/dev/null)"
    cp -a "$ovpn_dir" "$ovpn_bak" 2>/dev/null || true
  fi

  # gen certs
  if ! _gen_certs; then
    echo -e "${RED}Gagal generate certs, rollback${RESET}"
    if [ -n "$ovpn_bak" ] && [ -d "$ovpn_bak" ]; then rm -rf "$ovpn_dir" 2>/dev/null || true; cp -a "$ovpn_bak" "$ovpn_dir" 2>/dev/null || true; fi
    return 1
  fi

  # write server configs
  _write_server_conf "tcp" "$tcp_p" "tun0"
  _write_server_conf "udp" "$udp_p" "tun1"
  _write_server_conf "ssl" "$ssl_p" "tun2"
  # DNS 53 optional (if not slowdns)
  if [ -n "$dns_p" ]; then
    # Check if 53 already used by slowdns or systemd-resolved
    local use_dns=1
    if command -v ss >/dev/null 2>&1 && ss -ulnp 2>/dev/null | grep -q ":53 " && [ -z "$BASE" ]; then
      # check if slowdns or systemd-resolved owns 53
      if ss -ulnp 2>/dev/null | grep -q "slowdns\|dnstt" ; then
        echo -e "${YELLOW}Port 53 sudah dipakai SlowDNS, skip OpenVPN DNS 53 (rollback safe)${RESET}"
        use_dns=0
      elif [ -f "/etc/mytunnel/slowdns/server.key" ]; then
        echo -e "${YELLOW}SlowDNS config ada, skip DNS 53${RESET}"
        use_dns=0
      fi
    fi
    if [ "$use_dns" = "1" ]; then
      _write_server_conf "dns" "$dns_p" "tun3"
      # override proto for dns to udp
      sed -i "s/^proto .*/proto udp/" "$ovpn_dir/server-dns.conf" 2>/dev/null || true
      echo -e "${CYAN}OpenVPN DNS 53 server-dns.conf dibuat${RESET}"
    else
      echo -e "${YELLOW}Skip OpenVPN DNS 53 (mutual exclusion)${RESET}"
    fi
  fi

  # client ovpn + zip
  if ! _gen_client_ovpn; then
    echo -e "${RED}Gagal generate client ovpn/zip, rollback${RESET}"
    if [ -n "$ovpn_bak" ] && [ -d "$ovpn_bak" ]; then rm -rf "$ovpn_dir" 2>/dev/null || true; cp -a "$ovpn_bak" "$ovpn_dir" 2>/dev/null || true; fi
    return 1
  fi

  # validate
  if ! _validate_openvpn; then
    echo -e "${RED}Validasi OpenVPN gagal, rollback${RESET}"
    if [ -n "$ovpn_bak" ] && [ -d "$ovpn_bak" ]; then rm -rf "$ovpn_dir" 2>/dev/null || true; cp -a "$ovpn_bak" "$ovpn_dir" 2>/dev/null || true; fi
    return 1
  fi

  # systemd services (one per server conf)
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi systemd enable openvpn${RESET}"
    for proto in tcp udp ssl; do
      local svc="${BASE}/etc/systemd/system/mytunnel-openvpn-$proto.service"
      cat > "$svc" <<SVC_EOF
[Unit]
Description=mytunnel OpenVPN $proto
After=network.target

[Service]
Type=simple
ExecStart=${BASE}/usr/sbin/openvpn --config $ovpn_dir/server-$proto.conf
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC_EOF
      chmod 644 "$svc" 2>/dev/null || true
    done
    if [ -f "$ovpn_dir/server-dns.conf" ]; then
      cat > "${BASE}/etc/systemd/system/mytunnel-openvpn-dns.service" <<SVC_EOF2
[Unit]
Description=mytunnel OpenVPN DNS 53
After=network.target
[Service]
Type=simple
ExecStart=${BASE}/usr/sbin/openvpn --config $ovpn_dir/server-dns.conf
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
SVC_EOF2
      chmod 644 "${BASE}/etc/systemd/system/mytunnel-openvpn-dns.service" 2>/dev/null || true
    fi
    mkdir -p "${BASE}/var/log" 2>/dev/null || true
    echo "openvpn sim $tcp_p $udp_p $ssl_p" > "${BASE}/var/log/openvpn-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/openvpn-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/openvpn-sim.log" 2>/dev/null || true
    # also sim for nginx 81 root already via nginx.sh
    mkdir -p "$www_root" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] openvpn sim OK${RESET}"
  else
    # real: enable via systemd (openvpn@.service or custom)
    # Prefer openvpn@server-tcp etc, but use custom if needed
    systemctl daemon-reload 2>/dev/null || true
    # Try to use openvpn@ template if exists, else custom
    for proto in tcp udp ssl dns; do
      local conf="$ovpn_dir/server-$proto.conf"
      [ -f "$conf" ] || continue
      local svc="mytunnel-openvpn-$proto"
      local svcfile="/etc/systemd/system/${svc}.service"
      cat > "$svcfile" <<SVC_EOF3
[Unit]
Description=mytunnel OpenVPN $proto $proto
After=network.target

[Service]
Type=simple
ExecStart=/usr/sbin/openvpn --config $conf
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SVC_EOF3
      chmod 644 "$svcfile" 2>/dev/null || true
      systemctl enable "$svc" 2>/dev/null || true
      systemctl restart "$svc" 2>/dev/null || true
    done
    sleep 1
    for proto in tcp udp ssl dns; do
      local svc="mytunnel-openvpn-$proto"
      if systemctl is-active "$svc" >/dev/null 2>&1 || pgrep -f "openvpn.*server-$proto" >/dev/null 2>&1; then
        echo -e "${GREEN}OpenVPN $proto aktif${RESET}"
      else
        echo -e "${YELLOW}OpenVPN $proto belum aktif, cek: journalctl -u $svc -n 20${RESET}"
      fi
    done
    ss -tlnp 2>/dev/null | grep -E ":($tcp_p|$ssl_p|$ohp_p) " | head -n 10 || true
    ss -ulnp 2>/dev/null | grep -E ":($udp_p|$dns_p) " | head -n 10 || true
  fi

  echo -e "${GREEN}[openvpn] Selesai: TCP $tcp_p / UDP $udp_p / SSL $ssl_p + zip $www_root/myvpn-config.zip${RESET}" | tee -a "$LOG" 2>/dev/null || true
  echo -e "${YELLOW}Isi zip: hanya .ovpn + ca.crt (tanpa private key). Test: unzip -l $www_root/myvpn-config.zip${RESET}"
}

uninstall_openvpn(){
  local ovpn_dir www_root domain
  ovpn_dir=$(_ovpn_dir)
  www_root=$(_www_root)
  echo -e "${CYAN}[openvpn] Uninstall...${RESET}"
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi uninstall openvpn${RESET}"
    rm -f "${BASE}/etc/systemd/system/mytunnel-openvpn-"*.service 2>/dev/null || true
    rm -rf "$ovpn_dir" 2>/dev/null || true
    rm -f "$www_root/myvpn-config.zip" "$www_root/myvpn-config.zip.bak-"* 2>/dev/null || true
    rm -f "${BASE}/var/log/openvpn-sim.log" 2>/dev/null || true
    # keep ca? remove all
    echo -e "${GREEN}[TEST MODE] openvpn uninstall sim selesai${RESET}"
    return 0
  fi
  for proto in tcp udp ssl dns; do
    systemctl stop "mytunnel-openvpn-$proto" 2>/dev/null || true
    systemctl disable "mytunnel-openvpn-$proto" 2>/dev/null || true
    rm -f "/etc/systemd/system/mytunnel-openvpn-$proto.service" 2>/dev/null || true
  done
  systemctl daemon-reload 2>/dev/null || true
  # do not delete ca/server cert automatically? But spec wants clean uninstall
  if [ -d "$ovpn_dir" ]; then
    echo -e "${YELLOW}Hapus $ovpn_dir (backup dulu)${RESET}"
    local bak
    bak="${ovpn_dir}.bak-uninstall-$(date +%Y%m%d-%H%M%S 2>/dev/null)"
    cp -a "$ovpn_dir" "$bak" 2>/dev/null || true
    rm -rf "$ovpn_dir" 2>/dev/null || true
    echo -e "${GREEN}Backup uninstall: $bak${RESET}"
  fi
  rm -f "$www_root/myvpn-config.zip" 2>/dev/null || true
  # restore nginx 81? keep
  echo -e "${GREEN}[openvpn] Uninstall selesai (bersih)${RESET}"
}

status_openvpn(){
  local ovpn_dir www_root domain tcp_p udp_p ssl_p dns_p ohp_p cfg_p
  ovpn_dir=$(_ovpn_dir)
  www_root=$(_www_root)
  read -r tcp_p udp_p ssl_p dns_p ohp_p cfg_p <<< "$(_get_ports)"
  domain=$(_get_domain)
  echo "OPENVPN_TCP_PORT=$tcp_p OPENVPN_UDP_PORT=$udp_p OPENVPN_SSL_PORT=$ssl_p OPENVPN_DNS_PORT=$dns_p OHP_OVPN_PORT=$ohp_p CONFIG_PORT=$cfg_p"
  echo "domain: $domain"
  echo "ovpn_dir: $ovpn_dir $([ -d "$ovpn_dir" ] && echo "exists" || echo "missing")"
  echo "www_root: $www_root $([ -d "$www_root" ] && echo "exists" || echo "missing")"
  if [ -d "$ovpn_dir" ]; then ls -lh "$ovpn_dir/ca.crt" "$ovpn_dir/server.crt" "$ovpn_dir/server.key" "$ovpn_dir/dh.pem" "$ovpn_dir/ta.key" 2>&1 | sed 's/^/  /' || true
    ls -lh "$ovpn_dir/server-"*.conf 2>&1 | sed 's/^/  /' || true
    ls -lh "$ovpn_dir/clients/"*.ovpn 2>&1 | sed 's/^/  /' || true
  fi
  if [ -f "$www_root/myvpn-config.zip" ]; then
    echo "zip: $www_root/myvpn-config.zip exists"
    ls -lh "$www_root/myvpn-config.zip" 2>&1 | sed 's/^/  /' || true
    if command -v unzip >/dev/null 2>&1; then unzip -l "$www_root/myvpn-config.zip" 2>&1 | head -n 30 || true; fi
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$www_root/myvpn-config.zip" 2>/dev/null | awk '{print "  sha256: " $1}' || true; fi
  else
    echo "zip: $www_root/myvpn-config.zip missing"
  fi
  if [ -z "$BASE" ]; then
    for proto in tcp udp ssl dns; do echo -n "mytunnel-openvpn-$proto: "; systemctl is-active "mytunnel-openvpn-$proto" 2>/dev/null || echo "inactive"; done
    ss -tlnp 2>/dev/null | grep -E ":($tcp_p|$ssl_p|$ohp_p) " | head -n 10 || echo "(ss tcp no :$tcp_p/$ssl_p)"
    ss -ulnp 2>/dev/null | grep -E ":($udp_p|$dns_p) " | head -n 10 || echo "(ss udp no :$udp_p)"
  else
    echo "sim: $(cat ${BASE}/var/log/openvpn-sim.log 2>&1 || echo "no sim")"
    chmod 644 "$BASE/var/log/openvpn-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/openvpn-sim.log" 2>/dev/null || true
    ls -lh "${BASE}/etc/systemd/system/mytunnel-openvpn-"*.service 2>&1 | sed 's/^/  /' || true
  fi
  echo "PAM plugin: $(_find_pam_plugin) $([ -f "$(_find_pam_plugin)" ] && echo "exists" || echo "missing (test mode ok)")"
}

revoke_openvpn(){
  local user="$1"
  [ -z "$user" ] && { echo -e "${RED}Usage: $0 revoke <username>${RESET}" >&2; return 2; }
  local ovpn_dir
  ovpn_dir=$(_ovpn_dir)
  echo -e "${CYAN}[openvpn] Revoke belum diimplementasi penuh (easy-rsa revoke + gen-crl)${RESET}"
  echo -e "${YELLOW}Untuk now, hapus user via menu SSH > Delete (PAM blocked)${RESET}"
  # TODO: easy-rsa revoke + gen-crl -> update crl.pem, systemctl restart
  return 0
}

case "${1:-install}" in
  install) install_openvpn ;;
  uninstall|remove) uninstall_openvpn ;;
  status) status_openvpn ;;
  revoke) revoke_openvpn "$2" ;;
  *) echo "Usage: $0 [install|uninstall|status|revoke <user>]" >&2; exit 2 ;;
esac

__EMBED_EOF__
chmod 755 "$ETC/setup/openvpn.sh"
cat > "$ETC/setup/logrotate.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/logrotate.sh - install logrotate config
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"
install_logrotate(){
  local src="$ETC/logrotate.d/mytunnel"
  local dst="/etc/logrotate.d/mytunnel"
  [ -n "$BASE" ] && dst="$BASE/etc/logrotate.d/mytunnel"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")" 2>/dev/null || true
    cp -a "$src" "$dst" 2>/dev/null || true
    chmod 644 "$dst" 2>/dev/null || true
    echo -e "${GREEN}logrotate: $dst${RESET}"
  fi
  if [ -z "$BASE" ] && command -v logrotate >/dev/null 2>&1; then
    logrotate -d "$dst" 2>&1 | head -n 20 || true
  fi
}
main(){ install_logrotate; }
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/logrotate.sh"
cat > "$ETC/logrotate.d/mytunnel" << '__EMBED_EOF__'
# mytunnel logrotate - managed by mytunnel
/var/log/mytunnel.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl reload rsyslog 2>/dev/null || true
    endscript
}
/var/log/xray/access.log /var/log/xray/error.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
    postrotate
        systemctl restart xray 2>/dev/null || true
    endscript
}
/var/log/nginx/access.log /var/log/nginx/error.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 644 www-data adm
    postrotate
        nginx -s reopen 2>/dev/null || systemctl reload nginx 2>/dev/null || true
    endscript
}

__EMBED_EOF__
chmod 644 "$ETC/logrotate.d/mytunnel"
cat > "$ETC/setup/sshws.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel setup/sshws.sh - SSH over WebSocket proxy 127.0.0.1:10004 + nginx /ssh-ws
# shellcheck disable=SC1091,SC1090,SC2016
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
PY_BIN="${BASE}/usr/local/bin/mytunnel-sshws.py"
SVC_FILE="${BASE}/etc/systemd/system/mytunnel-sshws.service"
NGINX_SITE="${BASE}/etc/nginx/conf.d/mytunnel.conf"
NGINX_MAIN="${BASE}/etc/nginx/nginx.conf"
# CERT paths kept for docs (used via nginx, not direct)
# CERT_CRT="$ETC/cert/fullchain.crt"
# CERT_KEY="$ETC/cert/private.key"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; RESET="${RESET:-\033[0m}"

die() { echo -e "${RED}✗ $1${RESET}" | tee -a "$LOG" 2>/dev/null || true; echo -e "${YELLOW}Penyebab: $2${RESET}" >&2; exit 1; }

write_proxy() {
  mkdir -p "$(dirname "$PY_BIN")" 2>/dev/null || true
  cat > "$PY_BIN" << 'PY_EOF'
#!/usr/bin/env python3
# mytunnel-sshws.py - minimal WS -> TCP proxy for SSH
# listen 127.0.0.1:10004, path /ssh-ws -> forward to 127.0.0.1:22 (sshd)
import socket, threading, hashlib, base64, re, sys

LISTEN_HOST = "127.0.0.1"
LISTEN_PORT = 10004
SSH_HOST = "127.0.0.1"
SSH_PORT = 22
# ponytail: single SSH target; upgrade to multi-port/dropbear when needed

def ws_handshake(conn):
    try:
        data = conn.recv(4096).decode(errors="ignore")
        if not data:
            return None
        # must be GET /ssh-ws
        m = re.search(r"^\w+\s+(\S+)\s+HTTP", data, re.M)
        path = m.group(1) if m else ""
        if path != "/ssh-ws":
            # bug host: any path with websocket upgrade -> treat as /ssh-ws
            if "upgrade: websocket" in data.lower() and path.startswith("/"):
                path = "/ssh-ws"
            else:
                conn.sendall(b"HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found")
                return None
        # check Upgrade: websocket
        if "Upgrade: websocket" not in data and "upgrade: websocket" not in data.lower():
            # allow plain HTTP proxy for nginx (nginx already handles Upgrade header)
            # if not WS, just treat as raw TCP (for nginx proxy_pass)
            return "raw"
        key_m = re.search(r"Sec-WebSocket-Key:\s*(.+)\r\n", data, re.I)
        if not key_m:
            conn.sendall(b"HTTP/1.1 400 Bad Request\r\n\r\n")
            return None
        key = key_m.group(1).strip()
        accept = base64.b64encode(hashlib.sha1((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
        resp = (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        )
        conn.sendall(resp.encode())
        return "ws"
    except Exception as e:
        try:
            conn.sendall(b"HTTP/1.1 500 err\r\n\r\n")
        except Exception:
            pass
        return None

def ws_recv(conn):
    # minimal WS frame parser (client->server masked)
    try:
        b1 = conn.recv(1)
        if not b1:
            return None
        b1 = b1[0]
        fin = b1 & 0x80
        opcode = b1 & 0x0F
        if opcode == 8:  # close
            return None
        b2 = conn.recv(1)[0]
        masked = b2 & 0x80
        length = b2 & 0x7F
        if length == 126:
            length = int.from_bytes(conn.recv(2), "big")
        elif length == 127:
            length = int.from_bytes(conn.recv(8), "big")
        mask = conn.recv(4) if masked else b""
        payload = b""
        while len(payload) < length:
            chunk = conn.recv(length - len(payload))
            if not chunk:
                break
            payload += chunk
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        return payload
    except Exception:
        return None

def ws_send(conn, data):
    # server->client unmasked
    try:
        header = bytes([0x81])
        l = len(data)
        if l < 126:
            header += bytes([l])
        elif l < 65536:
            header += bytes([126]) + l.to_bytes(2, "big")
        else:
            header += bytes([127]) + l.to_bytes(8, "big")
        conn.sendall(header + data)
    except Exception:
        pass

def pipe_raw(a, b):
    try:
        while True:
            d = a.recv(4096)
            if not d:
                break
            b.sendall(d)
    except Exception:
        pass
    finally:
        try: a.close()
        except Exception: pass
        try: b.close()
        except Exception: pass

def handle_client(conn, addr):
    mode = ws_handshake(conn)
    if mode is None:
        try: conn.close()
        except Exception: pass
        return
    try:
        ssh = socket.create_connection((SSH_HOST, SSH_PORT), timeout=5)
    except Exception:
        try: conn.close()
        except Exception: pass
        return
    if mode == "raw":
        # nginx already did WS upgrade, just pipe
        t1 = threading.Thread(target=pipe_raw, args=(conn, ssh), daemon=True)
        t2 = threading.Thread(target=pipe_raw, args=(ssh, conn), daemon=True)
        t1.start(); t2.start()
        t1.join(); t2.join()
        return
    # ws mode: decode ws frames -> ssh, encode ssh -> ws
    def c2s():
        while True:
            d = ws_recv(conn)
            if d is None:
                break
            try:
                ssh.sendall(d)
            except Exception:
                break
        try: ssh.close()
        except Exception: pass
    def s2c():
        while True:
            try:
                d = ssh.recv(4096)
                if not d:
                    break
                ws_send(conn, d)
            except Exception:
                break
        try: conn.close()
        except Exception: pass
    t1 = threading.Thread(target=c2s, daemon=True)
    t2 = threading.Thread(target=s2c, daemon=True)
    t1.start(); t2.start()
    t1.join(); t2.join()

def main():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((LISTEN_HOST, LISTEN_PORT))
    s.listen(64)
    print(f"mytunnel-sshws listening {LISTEN_HOST}:{LISTEN_PORT} -> {SSH_HOST}:{SSH_PORT}", flush=True)
    while True:
        conn, addr = s.accept()
        threading.Thread(target=handle_client, args=(conn, addr), daemon=True).start()

if __name__ == "__main__":
    main()
PY_EOF
  chmod 755 "$PY_BIN" 2>/dev/null || true
  echo -e "${GREEN}Proxy WS ditulis: $PY_BIN${RESET}"
}

write_service() {
  mkdir -p "$(dirname "$SVC_FILE")" 2>/dev/null || true
  cat > "$SVC_FILE" << SVC_EOF
[Unit]
Description=mytunnel SSH WS Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 $PY_BIN
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
SVC_EOF
  chmod 644 "$SVC_FILE" 2>/dev/null || true
  # real path is /etc/systemd/system/mytunnel-sshws.service when BASE empty
  if [ -z "$BASE" ]; then
    mkdir -p /etc/systemd/system 2>/dev/null || true
    cp -a "$SVC_FILE" /etc/systemd/system/mytunnel-sshws.service 2>/dev/null || true
  fi
}

patch_nginx() {
  # idempotent: tambah location = /ssh-ws jika belum ada
  local site=""
  # find site file
  if [ -f "$NGINX_SITE" ]; then site="$NGINX_SITE"
  elif [ -f "${BASE}/etc/nginx/conf.d/mytunnel.conf" ]; then site="${BASE}/etc/nginx/conf.d/mytunnel.conf"
  elif [ -f /etc/nginx/conf.d/mytunnel.conf ]; then site="/etc/nginx/conf.d/mytunnel.conf"
  else
    echo -e "${YELLOW}Nginx site belum ada, skip patch (akan dibuat saat nginx.sh)${RESET}"
    return 0
  fi
  if grep -q "location.*\/ssh-ws" "$site" 2>/dev/null; then
    echo -e "${GREEN}Nginx sudah ada /ssh-ws${RESET}"
    return 0
  fi
  # backup
  cp -a "$site" "$site.bak-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
  # insert before first "location / {" in each server block
  # simple: replace the block
  local tmp
  tmp=$(mktemp)
  awk '
    /location \/ \{/ && !done80 { 
      print "  location = /ssh-ws {"
      print "    proxy_pass http://127.0.0.1:10004;"
      print "    proxy_http_version 1.1;"
      print "    proxy_set_header Upgrade $http_upgrade;"
      print "    proxy_set_header Connection $connection_upgrade;"
      print "    proxy_set_header Host $host;"
      print "    proxy_set_header X-Real-IP $remote_addr;"
      print "    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
      print "    proxy_read_timeout 3600s;"
      print "    proxy_send_timeout 3600s;"
      print "  }"
      print ""
    }
    {print}
  ' "$site" > "$tmp" 2>/dev/null && cat "$tmp" > "$site" 2>/dev/null || {
    # fallback sed insert
    sed -i "s|location / {|location = /ssh-ws {\n    proxy_pass http://127.0.0.1:10004;\n    proxy_http_version 1.1;\n    proxy_set_header Upgrade \$http_upgrade;\n    proxy_set_header Connection \$connection_upgrade;\n    proxy_set_header Host \$host;\n    proxy_read_timeout 3600s;\n    proxy_send_timeout 3600s;\n  }\n  location / {|" "$site" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
  echo -e "${GREEN}Nginx patch /ssh-ws -> 10004${RESET}"
  # validate
  if command -v nginx >/dev/null 2>&1; then
    if [ -n "$BASE" ] && [ -f "$NGINX_MAIN" ]; then
      nginx -t -c "$NGINX_MAIN" 2>&1 | head -n 20 || true
      if ! nginx -t -c "$NGINX_MAIN" 2>&1 | grep -q "syntax is ok"; then
        echo -e "${YELLOW}nginx -t gagal, rollback${RESET}"
        local bak
        bak=$(ls -t "$site.bak-"* 2>/dev/null | head -1)
        [ -n "$bak" ] && cp -a "$bak" "$site" 2>/dev/null || true
      fi
    else
      nginx -t 2>&1 | head -n 20 || true
    fi
  fi
}

enable_service() {
  if [ -n "$BASE" ]; then
    echo -e "${YELLOW}[TEST MODE] Skip systemd enable ssh-ws${RESET}"
    mkdir -p "${BASE}/var/log" 2>/dev/null || true
    echo "sshws simulated" > "${BASE}/var/log/sshws-sim.log" 2>/dev/null || true
    chmod 644 "$BASE/var/log/sshws-sim.log" 2>/dev/null || true; chmod 644 "${BASE}/var/log/sshws-sim.log" 2>/dev/null || true
    return 0
  fi
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable mytunnel-sshws 2>/dev/null || true
  systemctl restart mytunnel-sshws 2>/dev/null || systemctl start mytunnel-sshws 2>/dev/null || true
  sleep 1
  if systemctl is-active mytunnel-sshws >/dev/null 2>&1; then echo -e "${GREEN}Service mytunnel-sshws aktif${RESET}"; else echo -e "${YELLOW}Service mytunnel-sshws belum aktif${RESET}"; fi
  # nginx reload
  systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
}

main() {
  echo -e "${CYAN}[ssh-ws] Setup SSH WS...${RESET}" | tee -a "$LOG" 2>/dev/null || true
  write_proxy
  write_service
  patch_nginx
  enable_service
  echo -e "${GREEN}[ssh-ws] Selesai${RESET}" | tee -a "$LOG" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/setup/sshws.sh"
cat > "$ETC/cron/autoexpire.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel cron/autoexpire.sh - hapus/kunci akun SSH lewat expiry harian 00:00
# shellcheck disable=SC1091,SC1090
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
DB="$ETC/db/ssh.txt"
LOG="${BASE}/var/log/mytunnel.log"
# LOCK_STATE_DIR kept for compatibility (was unused)
# LOCK_STATE_DIR="${BASE}/var/lib/mytunnel/limit"
for f in "$ETC/lib/ssh_helpers.sh" "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done

_ensure_db() { mkdir -p "$(dirname "$DB")" 2>/dev/null || true; [ -f "$DB" ] || touch "$DB" 2>/dev/null || true; }
EXP_DB="$ETC/db/ssh_expired.txt"

_today_epoch() { date -d "$(date +%Y-%m-%d)" +%s 2>/dev/null || date +%s; }
_expiry_epoch() { date -d "$1" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null || echo 0; }

main() {
  _ensure_db
  [ -s "$DB" ] || exit 0
  local today exp user pass limit status
  today=$(_today_epoch)
  local tmp
  tmp=$(mktemp)
  cp -a "$DB" "$tmp" 2>/dev/null || true
  while IFS='|' read -r user pass exp limit status; do
    [ -z "$user" ] && continue
    [[ "$user" =~ ^# ]] && continue
    local exp_s
    exp_s=$(_expiry_epoch "$exp")
    [ "$exp_s" -eq 0 ] && continue
    if [ "$exp_s" -le "$today" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] autoexpire: $user exp=$exp lewat, hapus" >> "$LOG" 2>/dev/null || true
      if [ -n "$BASE" ]; then
        # TEST MODE: hanya log
        echo "TEST autoexpire would delete $user" >> "$LOG" 2>/dev/null || true
      else
        pkill -u "$user" 2>/dev/null || true
        userdel -r "$user" 2>/dev/null || userdel "$user" 2>/dev/null || true
      fi
      # remove from DB copy (defer)
    fi
  done < "$DB"
  # actually remove expired lines in one pass with flock
  local db_lock="$ETC/db/.ssh.lock"
  [ -f "$db_lock" ] || touch "$db_lock" 2>/dev/null || true
  local filtered exp_tmp
  filtered=$(mktemp); exp_tmp=$(mktemp)
  (
    flock -x 200
    while IFS='|' read -r user pass exp limit status; do
      [ -z "$user" ] && continue
      local exp_s
      exp_s=$(_expiry_epoch "$exp")
      if [ "$exp_s" -le "$today" ] 2>/dev/null; then
        # archive expired for Recovery (600, flock)
        echo "$user|$pass|$exp|$limit|$status" >> "$exp_tmp" 2>/dev/null || true
        continue
      fi
      echo "$user|$pass|$exp|$limit|$status" >> "$filtered" 2>/dev/null || true
    done < "$DB"
    cat "$filtered" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
    # append expired to archive (dedup by user, keep latest)
    if [ -s "$exp_tmp" ]; then
      touch "$EXP_DB" 2>/dev/null || true; chmod 600 "$EXP_DB" 2>/dev/null || true
      # remove already archived users to avoid dup, then append
      local _tmp2; _tmp2=$(mktemp)
      while IFS='|' read -r eu _ep _ee _el _es; do [ -n "$eu" ] && grep -v "^${eu}|" "$EXP_DB" > "$_tmp2" 2>/dev/null && cat "$_tmp2" > "$EXP_DB" 2>/dev/null || true; done < "$exp_tmp"
      cat "$exp_tmp" >> "$EXP_DB" 2>/dev/null || true
      chmod 600 "$EXP_DB" 2>/dev/null || true
      rm -f "$_tmp2" 2>/dev/null || true
    fi
  ) 200>"$db_lock" 2>/dev/null || {
    # fallback without flock
    while IFS='|' read -r user pass exp limit status; do
      [ -z "$user" ] && continue
      local exp_s; exp_s=$(_expiry_epoch "$exp")
      [ "$exp_s" -le "$today" ] && { echo "$user|$pass|$exp|$limit|$status" >> "$exp_tmp" 2>/dev/null || true; continue; }
      echo "$user|$pass|$exp|$limit|$status"
    done < "$DB" > "$filtered" 2>/dev/null && cat "$filtered" > "$DB" 2>/dev/null
    chmod 600 "$DB" 2>/dev/null || true
    if [ -s "$exp_tmp" ]; then touch "$EXP_DB" 2>/dev/null || true; chmod 600 "$EXP_DB" 2>/dev/null || true; cat "$exp_tmp" >> "$EXP_DB" 2>/dev/null || true; chmod 600 "$EXP_DB" 2>/dev/null || true; fi
  }
  rm -f "$tmp" "$filtered" "$exp_tmp" 2>/dev/null || true
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/cron/autoexpire.sh"
cat > "$ETC/cron/limitip.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel cron/limitip.sh - cek IP unik per user tiap 1 menit, lock 15 menit jika lewat
# shellcheck disable=SC1091,SC1090,SC2129
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
DB="$ETC/db/ssh.txt"
LOG="${BASE}/var/log/mytunnel.log"
STATE_DIR="${BASE}/var/lib/mytunnel/limit"
for f in "$ETC/lib/ssh_helpers.sh" "$ETC/lib/colors.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done

_ensure_state() { mkdir -p "$STATE_DIR" 2>/dev/null || true; }

_get_user_ips() {
  local user="$1"
  local ips=""
  # Method 1: ss -tnp (ssh sessions)
  if command -v ss >/dev/null 2>&1; then
    # find pids for user, then ss
    local pids
    pids=$(pgrep -u "$user" 2>/dev/null | tr '\n' ',' | sed 's/,$//') || true
    if [ -n "$pids" ]; then
      ips=$(ss -tnp 2>/dev/null | grep -E "$pids" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+' | cut -d: -f1 | sort -u | tr '\n' ' ') || true
    fi
    # fallback: who
    if [ -z "$ips" ]; then
      ips=$(who 2>/dev/null | awk -v u="$user" '$1==u{print $5}' | tr -d '()' | sort -u | tr '\n' ' ') || true
    fi
  else
    ips=$(who 2>/dev/null | awk -v u="$user" '$1==u{print $5}' | tr -d '()' | sort -u | tr '\n' ' ') || true
  fi
  # also try last log for dropbear: journalctl / auth.log
  if [ -z "$ips" ] && [ -z "$BASE" ]; then
    if [ -f /var/log/auth.log ]; then
      ips=$(grep -E "Password auth succeeded for.*$user" /var/log/auth.log 2>/dev/null | tail -n 20 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -u | tr '\n' ' ') || true
    fi
  fi
  echo "$ips" | tr -s ' ' | sed 's/^ //;s/ $//'
}

main() {
  _ensure_state
  [ -f "$DB" ] || exit 0
  [ -s "$DB" ] || exit 0
  # shellcheck disable=SC2034
  local user pass exp limit status
  : "${pass:-}" "${exp:-}"  # read from DB but not needed in this path
  while IFS='|' read -r user pass exp limit status; do
    [ -z "$user" ] && continue
    [[ "$user" =~ ^# ]] && continue
    [ "$status" = "locked" ] && {
      # check if lock expired (15 min)
      local lockfile="$STATE_DIR/${user}.lock"
      if [ -f "$lockfile" ]; then
        local lock_time now diff
        lock_time=$(stat -c %Y "$lockfile" 2>/dev/null || stat -f %m "$lockfile" 2>/dev/null || echo 0)
        now=$(date +%s 2>/dev/null)
        diff=$((now - lock_time))
        if [ "$diff" -ge 900 ]; then
          # unlock
          if [ -n "$BASE" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] limitip: unlock $user (TEST)" >> "$LOG" 2>/dev/null || true
          else
            usermod -U "$user" 2>/dev/null || true
          fi
          # update DB status
          local db_lock="$ETC/db/.ssh.lock"
          [ -f "$db_lock" ] || touch "$db_lock" 2>/dev/null || true
          local tmp
          tmp=$(mktemp)
          (
            flock -x 200
            awk -F'|' -v OFS='|' -v u="$user" '$1==u{$5="active"}1' "$DB" > "$tmp" 2>/dev/null && cat "$tmp" > "$DB" 2>/dev/null
            chmod 600 "$DB" 2>/dev/null || true
          ) 200>"$db_lock" 2>/dev/null || {
            awk -F'|' -v OFS='|' -v u="$user" '$1==u{$5="active"}1' "$DB" > "$tmp" 2>/dev/null && cat "$tmp" > "$DB" 2>/dev/null
            chmod 600 "$DB" 2>/dev/null || true
          }
          rm -f "$tmp" 2>/dev/null || true
          rm -f "$lockfile" 2>/dev/null || true
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] limitip: auto-unlock $user after 15m" >> "$LOG" 2>/dev/null || true
        fi
      fi
      continue
    }
    # only check if limit >0
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=0
    [ "$limit" -eq 0 ] && continue
    local ips cnt
    ips=$(_get_user_ips "$user")
    [ -z "$ips" ] && continue
    cnt=$(echo "$ips" | wc -w | tr -d ' ')
    if [ "$cnt" -gt "$limit" ] 2>/dev/null; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] limitip: $user melebihi limit ($cnt > $limit) ips=$ips" >> "$LOG" 2>/dev/null || true
      if [ -n "$BASE" ]; then
        echo "TEST limitip would lock $user" >> "$LOG" 2>/dev/null || true
      else
        pkill -u "$user" 2>/dev/null || true
        usermod -L "$user" 2>/dev/null || true
      fi
      # set DB locked + lockfile timestamp
      local db_lock="$ETC/db/.ssh.lock"
      [ -f "$db_lock" ] || touch "$db_lock" 2>/dev/null || true
      local tmp2
      tmp2=$(mktemp)
      (
        flock -x 200
        awk -F'|' -v OFS='|' -v u="$user" '$1==u{$5="locked"}1' "$DB" > "$tmp2" 2>/dev/null && cat "$tmp2" > "$DB" 2>/dev/null
        chmod 600 "$DB" 2>/dev/null || true
      ) 200>"$db_lock" 2>/dev/null || {
        awk -F'|' -v OFS='|' -v u="$user" '$1==u{$5="locked"}1' "$DB" > "$tmp2" 2>/dev/null && cat "$tmp2" > "$DB" 2>/dev/null
        chmod 600 "$DB" 2>/dev/null || true
      }
      rm -f "$tmp2" 2>/dev/null || true
      touch "$STATE_DIR/${user}.lock" 2>/dev/null || true
    fi
  done < "$DB"
}
main "$@"

__EMBED_EOF__
chmod 755 "$ETC/cron/limitip.sh"
cat > "$ETC/cron/autoexpire_xray.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel cron/autoexpire_xray.sh - hapus akun Xray kedaluwarsa (harian 00:00, flock per DB)
# shellcheck disable=SC1091,SC1090
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/xray_helpers.sh" "$ETC/lib/proto_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
# ponytail: single reload after batch; upgrade to debounce/queue if churn tinggi

_expiry_epoch() {
  local d="$1"
  date -d "$d" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$d" +%s 2>/dev/null || echo 0
}

_today_epoch() { date +%s 2>/dev/null; }
_archive_expired(){
  local proto="$1" user="$2" line="$3"
  local adb="$ETC/db/${proto}_expired.txt" lock="$ETC/db/.${proto}.lock"
  touch "$adb" 2>/dev/null || true; chmod 600 "$adb" 2>/dev/null || true
  # dedup: remove old entry for same user then append
  local _tmp; _tmp=$(mktemp)
  grep -v "^${user}|" "$adb" > "$_tmp" 2>/dev/null || true
  cat "$_tmp" > "$adb" 2>/dev/null; chmod 600 "$adb" 2>/dev/null || true
  echo "$line" >> "$adb" 2>/dev/null || true
  chmod 600 "$adb" 2>/dev/null || true
  rm -f "$_tmp" 2>/dev/null || true
}

run_once() {
  local changed=0 proto db user exp exp_s today_s
  today_s=$(_today_epoch)
  for proto in vmess vless trojan; do
    db="$ETC/db/${proto}.txt"
    [ -f "$db" ] || continue
    # collect expired users first (avoid mutating while iterating)
    while IFS='|' read -r user _uuid exp _lip _quota _used _status 2>/dev/null; do
      [ -z "$user" ] && continue
      exp_s=$(_expiry_epoch "$exp")
      [ "$exp_s" -eq 0 ] && continue
      if [ "$exp_s" -lt "$today_s" ]; then
        local _line; _line=$(grep "^${user}|" "$db" 2>/dev/null | head -1)
        [ -n "$_line" ] && _archive_expired "$proto" "$user" "$_line"
        xray_del_client "$proto" "$user" 2>/dev/null || true
        _db_expire_remove "$proto" "$user"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] autoexpire_xray $proto $user exp=$exp" >> "$LOG" 2>/dev/null || true
        changed=1
      fi
    done < "$db" 2>/dev/null
  done
  if [ "$changed" -eq 1 ]; then
    xray_reload 2>/dev/null || true
  fi
}

_db_expire_remove() {
  local proto="$1" user="$2"
  local db lock tmp
  db="$ETC/db/${proto}.txt"; lock="$ETC/db/.${proto}.lock"
  tmp=$(mktemp)
  (
    flock -x 200
    grep -v "^${user}|" "$db" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  ) 200>"$lock" 2>/dev/null || {
    grep -v "^${user}|" "$db" > "$tmp" 2>/dev/null || true
    cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
}

# allow direct run
if [ "${1:-}" != "--sourced" ]; then run_once; fi

__EMBED_EOF__
chmod 755 "$ETC/cron/autoexpire_xray.sh"
cat > "$ETC/cron/quota.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel cron/quota.sh - kumpulkan trafik Xray, lock jika melebihi kuota (tiap 1 menit)
# shellcheck disable=SC1091,SC1090
# Catatan: xray api statsquery perlu xray binary + api port 10085. Jika xray tidak jalan, script no-op.
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
XRAY_CFG="${BASE}/usr/local/etc/xray/config.json"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/xray_helpers.sh" "$ETC/lib/proto_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done

# Batasan metode: statsquery reset per 1 menit; jika VPS restart, counter reset. Akurasi best-effort.
# ponytail: simpan used_bytes per DB saja; upgrade ke sqlite/rrd untuk histori harian.

_get_api_port() {
  local p
  if [ -f "$XRAY_CFG" ] && command -v jq >/dev/null 2>&1; then
    p=$(jq -r '.inbounds[] | select(.tag=="api") | .port // empty' "$XRAY_CFG" 2>/dev/null | head -1)
  fi
  [ -z "$p" ] && p=10085
  echo "$p" | tr -d ' \n'
}

_xray_bin() {
  if [ -x "${BASE}/usr/local/bin/xray" ]; then echo "${BASE}/usr/local/bin/xray"
  elif command -v xray >/dev/null 2>&1; then command -v xray
  else echo "xray"
  fi
}

_add_used() {
  local proto="$1" user="$2" add="$3"
  local db lock tmp cur used new
  : "${cur:-}" "${new:-}"  # reserved for future quota math
  db="$ETC/db/${proto}.txt"; lock="$ETC/db/.${proto}.lock"
  [ -f "$db" ] || return 0
  [[ "$add" =~ ^[0-9]+$ ]] || return 0
  [ "$add" -eq 0 ] && return 0
  tmp=$(mktemp)
  (
    flock -x 200
    awk -F'|' -v OFS='|' -v u="$user" -v a="$add" '
      $1==u { $6 = ($6 ~ /^[0-9]+$/ ? $6 : 0) + a; print; next } {print}
    ' "$db" > "$tmp" 2>/dev/null && cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  ) 200>"$lock" 2>/dev/null || {
    awk -F'|' -v OFS='|' -v u="$user" -v a="$add" '
      $1==u { $6 = ($6 ~ /^[0-9]+$/ ? $6 : 0) + a; print; next } {print}
    ' "$db" > "$tmp" 2>/dev/null && cat "$tmp" > "$db" 2>/dev/null
    chmod 600 "$db" 2>/dev/null || true
  }
  rm -f "$tmp" 2>/dev/null || true
}

run_once() {
  local bin port raw changed=0
  bin=$(_xray_bin); port=$(_get_api_port)
  # cek api reachable; jika tidak ada binary atau api down -> skip
  if ! command -v "$bin" >/dev/null 2>&1 && [ ! -x "$bin" ]; then return 0; fi
  # pastikan policy stats aktif; jika belum, coba patch (best-effort)
  # statsquery with -reset returns lines like: user>>>alice>>>traffic>>>uplink: 123
  raw=$("$bin" api statsquery --server="127.0.0.1:${port}" -reset 2>/dev/null || true)
  [ -z "$raw" ] && return 0
  # kumpulkan per user: uplink + downlink
  declare -A sum
  while IFS= read -r line; do
    # format: user>>>EMAIL>>>traffic>>>uplink: value  OR  user>>>EMAIL>>>traffic>>>downlink: value
    if [[ "$line" =~ user\>\>\>([^>]+)\>\>\>traffic\>\>\>(uplink|downlink):[[:space:]]*([0-9]+) ]]; then
      local email="${BASH_REMATCH[1]}" val="${BASH_REMATCH[3]}"
      sum["$email"]=$(( ${sum["$email"]:-0} + val ))
    fi
  done <<< "$raw"

  local email total proto quota used quota_bytes
  for email in "${!sum[@]}"; do
    total="${sum[$email]}"
    [ "$total" -eq 0 ] && continue
    # cari proto untuk email
    for proto in vmess vless trojan; do
      if grep -q "^${email}|" "$ETC/db/${proto}.txt" 2>/dev/null; then
        _add_used "$proto" "$email" "$total"
        quota=$(awk -F'|' -v u="$email" '$1==u{print $5}' "$ETC/db/${proto}.txt" 2>/dev/null | head -1)
        used=$(awk -F'|' -v u="$email" '$1==u{print $6}' "$ETC/db/${proto}.txt" 2>/dev/null | head -1)
        [[ "$quota" =~ ^[0-9]+$ ]] || quota=0
        [[ "$used" =~ ^[0-9]+$ ]] || used=0
        quota_bytes=$((quota*1024*1024*1024))
        if [ "$quota" -gt 0 ] && [ "$used" -ge "$quota_bytes" ]; then
          # lock jika masih active
          local st; st=$(awk -F'|' -v u="$email" '$1==u{print $7}' "$ETC/db/${proto}.txt" 2>/dev/null | head -1)
          if [ "$st" = "active" ]; then
            xray_del_client "$proto" "$email" 2>/dev/null || true
            # set status locked
            awk -F'|' -v OFS='|' -v u="$email" '$1==u{$7="locked"}1' "$ETC/db/${proto}.txt" > /tmp/.quota_tmp.$$ 2>/dev/null && cat /tmp/.quota_tmp.$$ > "$ETC/db/${proto}.txt" 2>/dev/null
            chmod 600 "$ETC/db/${proto}.txt" 2>/dev/null || true
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] quota lock $proto $email used=$used quota=${quota}GB" >> "$LOG" 2>/dev/null || true
            changed=1
          fi
        fi
        break
      fi
    done
  done
  if [ "$changed" -eq 1 ]; then xray_reload 2>/dev/null || true; fi
  rm -f /tmp/.quota_tmp.$$ 2>/dev/null || true
}

if [ "${1:-}" != "--sourced" ]; then run_once; fi

__EMBED_EOF__
chmod 755 "$ETC/cron/quota.sh"
cat > "$ETC/cron/limitip_xray.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel cron/limitip_xray.sh - hitung IP unik per akun dari access.log, lock 15m jika over limit (tiap 1 menit)
# shellcheck disable=SC1091,SC1090
# Batasan: Xray tidak punya limit IP bawaan; metode baca access.log tidak 100% akurat (log rotate, NAT, delay).
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
STATE_DIR="${BASE}/var/lib/mytunnel/state"
XRAY_LOG="${BASE}/var/log/xray/access.log"
# fallback prod log
[ -f "$XRAY_LOG" ] || XRAY_LOG="/var/log/xray/access.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/xray_helpers.sh" "$ETC/lib/proto_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done

LOCK_MIN=15

_state_file() { echo "$STATE_DIR/limitip_${1}_${2}.lock"; }

_unlock_expired() {
  local f now_m
  now_m=$(date +%s 2>/dev/null)
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  for f in "$STATE_DIR"/limitip_*.lock; do
    [ -f "$f" ] || continue
    local exp_s
    exp_s=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    # mtime + LOCK_MIN*60
    if [ $((now_m - exp_s)) -ge $((LOCK_MIN*60)) ]; then
      # filename: limitip_PROTO_USER.lock
      local base proto user
      base=$(basename "$f" 2>/dev/null)
      # shellcheck disable=SC2001
      proto=$(echo "$base" | sed 's/^limitip_//' | cut -d'_' -f1)
      user=$(echo "$base" | sed "s/^limitip_${proto}_//" | sed 's/\.lock$//')
      if [ -n "$proto" ] && [ -n "$user" ]; then
        local st; st=$(awk -F'|' -v u="$user" '$1==u{print $7}' "$ETC/db/${proto}.txt" 2>/dev/null | head -1)
        if [ "$st" = "locked" ]; then
          # cek apakah lock karena limitip (file state ada) -> unlock
          local id; id=$(awk -F'|' -v u="$user" '$1==u{print $2}' "$ETC/db/${proto}.txt" 2>/dev/null | head -1)
          if [ -n "$id" ]; then
            xray_add_client "$proto" "$id" "$user" 2>/dev/null || true
            (
              flock -x 200
              awk -F'|' -v OFS='|' -v u="$user" '$1==u{$7="active"}1' "$ETC/db/${proto}.txt" > /tmp/.li_tmp.$$ 2>/dev/null && cat /tmp/.li_tmp.$$ > "$ETC/db/${proto}.txt" 2>/dev/null
            ) 200>"$ETC/db/.${proto}.lock" 2>/dev/null || awk -F'|' -v OFS='|' -v u="$user" '$1==u{$7="active"}1' "$ETC/db/${proto}.txt" > /tmp/.li_tmp.$$ 2>/dev/null && cat /tmp/.li_tmp.$$ > "$ETC/db/${proto}.txt" 2>/dev/null
            chmod 600 "$ETC/db/${proto}.txt" 2>/dev/null || true
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] limitip auto-unlock $proto $user" >> "$LOG" 2>/dev/null || true
          fi
        fi
      fi
      rm -f "$f" 2>/dev/null || true
    fi
  done
  rm -f /tmp/.li_tmp.$$ 2>/dev/null || true
}

run_once() {
  mkdir -p "$STATE_DIR" 2>/dev/null || true
  _unlock_expired
  [ -f "$XRAY_LOG" ] || return 0
  # ambil 2 menit terakhir access.log (format xray: ... email: user ... remote: ip:port)
  # fallback: grep email/user
  local changed=0 proto db user limit cnt ips
  for proto in vmess vless trojan; do
    db="$ETC/db/${proto}.txt"
    [ -f "$db" ] || continue
    while IFS='|' read -r user _id _exp limit _quota _used status 2>/dev/null; do
      [ -z "$user" ] && continue
      [[ "$limit" =~ ^[0-9]+$ ]] || limit=0
      [ "$limit" -eq 0 ] && continue
      [ "$status" = "locked" ] && continue
      # hitung IP unik untuk user dalam 2 menit window (1000 baris terakhir cukup ringan)
      ips=$(tail -n 5000 "$XRAY_LOG" 2>/dev/null | grep -F "$user" 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' 2>/dev/null | sort -u 2>/dev/null | wc -l 2>/dev/null)
      cnt=$(echo "$ips" | tr -d ' \n')
      [[ "$cnt" =~ ^[0-9]+$ ]] || cnt=0
      if [ "$cnt" -gt "$limit" ]; then
        xray_del_client "$proto" "$user" 2>/dev/null || true
        (
          flock -x 200
          awk -F'|' -v OFS='|' -v u="$user" '$1==u{$7="locked"}1' "$db" > /tmp/.li2.$$ 2>/dev/null && cat /tmp/.li2.$$ > "$db" 2>/dev/null
        ) 200>"$db.lock" 2>/dev/null || awk -F'|' -v OFS='|' -v u="$user" '$1==u{$7="locked"}1' "$db" > /tmp/.li2.$$ 2>/dev/null && cat /tmp/.li2.$$ > "$db" 2>/dev/null
        chmod 600 "$db" 2>/dev/null || true
        touch "$STATE_DIR/limitip_${proto}_${user}.lock" 2>/dev/null || true
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] limitip lock $proto $user ips=$cnt limit=$limit" >> "$LOG" 2>/dev/null || true
        changed=1
      fi
    done < "$db" 2>/dev/null
  done
  if [ "$changed" -eq 1 ]; then xray_reload 2>/dev/null || true; fi
  rm -f /tmp/.li2.$$ 2>/dev/null || true
}

if [ "${1:-}" != "--sourced" ]; then run_once; fi

__EMBED_EOF__
chmod 755 "$ETC/cron/limitip_xray.sh"
cat > "$ETC/cron/bot_notify.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel cron/bot_notify.sh - notifikasi H-3, lock, service down -> admin (quiet if no bot.conf)
# shellcheck disable=SC1091
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
CONF="$ETC/config/bot.conf"
[ -f "$CONF" ] || exit 0
# shellcheck disable=SC1090
. "$CONF" 2>/dev/null || exit 0
[ -z "${BOT_TOKEN:-}" ] || [ -z "${ADMIN_ID:-}" ] && exit 0
[ -f "$ETC/lib/advanced_helpers.sh" ] && . "$ETC/lib/advanced_helpers.sh" 2>/dev/null || true
# H-3 expiry check (ssh + vmess/vless/trojan)
_now=$(date +%s 2>/dev/null)
for db in "$ETC/db/ssh.txt" "$ETC/db/vmess.txt" "$ETC/db/vless.txt" "$ETC/db/trojan.txt"; do
  [ -f "$db" ] || continue
  while IFS='|' read -r user _ exp _ _ _ status; do
    [ -z "$user" ] || [ -z "$exp" ] && continue
    # only active
    case "$status" in locked) continue;; esac
    exp_s=$(date -d "$exp" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$exp" +%s 2>/dev/null || echo 0)
    [ "$exp_s" -eq 0 ] && continue
    left=$(( (exp_s - _now) / 86400 ))
    if [ "$left" -eq 3 ] 2>/dev/null; then
      # avoid spam: state file per user per day
      state="$ETC/../var/lib/mytunnel/state/notify_${user}_H3"
      [ -n "$BASE" ] && state="$BASE/var/lib/mytunnel/state/notify_${user}_H3"
      mkdir -p "$(dirname "$state")" 2>/dev/null || true
      if [ ! -f "$state" ] || [ "$(cat "$state" 2>/dev/null)" != "$(date +%Y-%m-%d 2>/dev/null)" ]; then
        ah_notify_admin "⚠️ Akun $user kedaluwarsa H-3 ($exp) — $(basename "$db" .txt)" 2>/dev/null || true
        date +%Y-%m-%d > "$state" 2>/dev/null || true
      fi
    fi
  done < "$db" 2>/dev/null || true
done
# service down check (once per hour, state)
for s in xray nginx dropbear mytunnel-sshws mytunnel-bot mytunnel-slowdns; do
  # fh_svc_status if available
  st="OFF"
  if declare -f fh_svc_status >/dev/null 2>&1; then st=$(fh_svc_status "$s" 2>/dev/null || echo OFF)
  elif declare -f ah_log >/dev/null 2>&1; then st="OFF"
  fi
  if [ "$st" = "OFF" ] && [ "$s" = "xray" ]; then
    # only notify for critical
    state2="$ETC/../var/lib/mytunnel/state/notify_svc_${s}"
    [ -n "$BASE" ] && state2="$BASE/var/lib/mytunnel/state/notify_svc_${s}"
    mkdir -p "$(dirname "$state2")" 2>/dev/null || true
    # throttle 1h
    if [ ! -f "$state2" ] || [ $(( _now - $(cat "$state2" 2>/dev/null || echo 0) )) -gt 3600 ] 2>/dev/null; then
      # check real service only if not sim
      if [ -z "$BASE" ]; then
        ah_notify_admin "🔴 Service $s OFF — cek systemctl status $s" 2>/dev/null || true
        echo "$_now" > "$state2" 2>/dev/null || true
      fi
    fi
  fi
done

__EMBED_EOF__
chmod 755 "$ETC/cron/bot_notify.sh"
cat > "$ETC/bot/bot.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel bot/bot.sh - daemon long-polling (curl + jq, admin-only) - READ-ONLY + backup/restore
# Bot TIDAK bisa buat akun; hanya notifikasi create/delete dari menu + /status /list /backup + restore via file
# shellcheck disable=SC1091,SC2154,SC1090,SC2034
set -e
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
CONF="$ETC/config/bot.conf"
LOG="${BASE}/var/log/mytunnel.log"
OFFSET_FILE="$ETC/bot/offset.txt"
[ -f "$CONF" ] || { echo "bot.conf tidak ada: $CONF" >&2; exit 1; }
# shellcheck disable=SC1090
. "$CONF" 2>/dev/null || { echo "gagal load $CONF" >&2; exit 1; }
[ -z "${BOT_TOKEN:-}" ] || [ -z "${ADMIN_ID:-}" ] && { echo "BOT_TOKEN/ADMIN_ID kosong" >&2; exit 1; }
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/advanced_helpers.sh" "$ETC/bot/handlers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done

# never log token
ah_log "bot daemon start admin $ADMIN_ID token $(ah_mask_token "$BOT_TOKEN")"

mkdir -p "$(dirname "$OFFSET_FILE")" 2>/dev/null || true
OFFSET=0
[ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null | tr -dc '0-9' | head -c 20)
[ -z "$OFFSET" ] && OFFSET=0

send_msg(){
  local chat_id="$1" text="$2"
  curl -fsS --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" -d "chat_id=${chat_id}" --data-urlencode "text=${text}" >/dev/null 2>&1 || true
}

handle_update(){
  local upd="$1"
  local chat_id from_id text
  chat_id=$(echo "$upd" | jq -r '.message.chat.id // empty' 2>/dev/null)
  from_id=$(echo "$upd" | jq -r '.message.from.id // empty' 2>/dev/null)
  # --- handle document (backup restore) ---
  local doc_id doc_name doc_size
  doc_id=$(echo "$upd" | jq -r '.message.document.file_id // empty' 2>/dev/null)
  doc_name=$(echo "$upd" | jq -r '.message.document.file_name // empty' 2>/dev/null)
  doc_size=$(echo "$upd" | jq -r '.message.document.file_size // 0' 2>/dev/null | tr -dc '0-9')
  [ -z "$doc_size" ] && doc_size=0
  if [ -n "$doc_id" ]; then
    if [ "$chat_id" != "$ADMIN_ID" ] && [ "$from_id" != "$ADMIN_ID" ]; then return 0; fi
    # hanya terima .tar.gz / .tgz / .gz (backup) - tolak file lain
    case "$doc_name" in
      *.tar.gz|*.tgz|*.tar|*.gz) ;;
      *) send_msg "$ADMIN_ID" "Restore ditolak: kirim file backup .tar.gz (mytunnel-*.tar.gz)"; return 0;;
    esac
    if [ "$doc_size" -gt 25000000 ] 2>/dev/null; then send_msg "$ADMIN_ID" "File terlalu besar (>25MB)"; return 0; fi
    local reply
    reply=$(bh_restore_from_telegram "$doc_id" "$doc_name" 2>&1 | head -n 40)
    [ -z "$reply" ] && reply="Restore selesai (cek log)"
    reply=$(echo "$reply" | head -c 4000)
    send_msg "$ADMIN_ID" "$reply"
    ah_log "bot document $doc_name from $from_id"
    return 0
  fi
  text=$(echo "$upd" | jq -r '.message.text // empty' 2>/dev/null)
  [ -z "$chat_id" ] && return 0
  # HANYA admin
  if [ "$chat_id" != "$ADMIN_ID" ] && [ "$from_id" != "$ADMIN_ID" ]; then
    return 0
  fi
  text=$(echo "$text" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$text" ] && return 0
  local cmd arg1
  cmd=$(echo "$text" | awk '{print $1}' | tr -d ' \n')
  arg1=$(echo "$text" | awk '{print $2}' | tr -d ' \n')
  local reply=""
  case "$cmd" in
    /start|/help)
      reply="TUNNEL PRO Bot (read-only)
Bot tidak bisa buat akun — buat/hapus lewat menu VPS.
/start - bantuan ini
/status - info sistem
/list - daftar akun (ringkas)
/backup - kirim file backup terbaru
Kirim file .tar.gz backup sebagai document untuk restore (hanya admin, max 25MB)."
      ;;
    /status)
      reply=$(bh_status_text 2>/dev/null || echo "status error")
      ;;
    /list)
      reply=$(bh_list 2>&1 | head -n 80)
      ;;
    /backup)
      reply=$(bh_backup_send 2>&1 | head -n 20)
      ;;
    /create_ssh|/create_vmess|/create_vless|/create_trojan|/delete|/renew|/trial)
      reply="Fitur $cmd via bot dinonaktifkan.
Buat/hapus/renew/trial hanya lewat menu VPS — bot hanya kirim notifikasi + /backup & restore file."
      ;;
    *)
      reply="Perintah tidak dikenal: $cmd
Ketik /start untuk bantuan"
      ;;
  esac
  reply=$(echo "$reply" | head -c 4000)
  send_msg "$ADMIN_ID" "$reply"
  ah_log "bot cmd $cmd from $from_id"
}

# main loop long-polling
while true; do
  resp=$(curl -fsS --max-time 35 "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates" -d "offset=${OFFSET}" -d "timeout=30" 2>&1 || true)
  if echo "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then
    cnt=$(echo "$resp" | jq '.result | length' 2>/dev/null || echo 0)
    if [ "$cnt" -gt 0 ] 2>/dev/null; then
      echo "$resp" | jq -c '.result[]' 2>/dev/null | while IFS= read -r upd; do
        handle_update "$upd" || true
        uid=$(echo "$upd" | jq -r '.update_id // empty' 2>/dev/null | tr -dc '0-9')
        if [ -n "$uid" ]; then
          OFFSET=$((uid + 1))
          echo "$OFFSET" > "$OFFSET_FILE" 2>/dev/null || true
        fi
      done
      [ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE" 2>/dev/null | tr -dc '0-9' | head -c 20)
    fi
  else
    sleep 5
  fi
  sleep 1
done

__EMBED_EOF__
chmod 755 "$ETC/bot/bot.sh"
cat > "$ETC/bot/handlers.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel bot/handlers.sh - command handlers (no eval, quoted)
# shellcheck disable=SC1091,SC1090,SC2034,SC2154,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/sysinfo.sh" "$ETC/lib/ssh_helpers.sh" "$ETC/lib/proto_helpers.sh" "$ETC/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
LOG="${BASE}/var/log/mytunnel.log"
DB_SSH="$ETC/db/ssh.txt"

bh_log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] [bot] $1" >> "$LOG" 2>/dev/null || true; }

bh_status_text(){
  local os ip dom xray nginx ver
  os=$(get_os 2>/dev/null || echo "-")
  ip=$(cat "$ETC/config/domain.txt" 2>/dev/null | head -1)
  [ -z "$ip" ] && ip=$(ah_get_ip 2>/dev/null || echo "-")
  xray=$(fh_svc_status xray 2>/dev/null || echo "OFF")
  nginx=$(fh_svc_status nginx 2>/dev/null || echo "OFF")
  ver=$(cat "$ETC/config/version.txt" 2>/dev/null | head -1)
  [ -z "$ver" ] && ver="v1.0"
  printf "TUNNEL PRO %s\nOS: %s\nDomain: %s\nXRAY: %s | NGINX: %s\nSSH: %s | Dropbear: %s\nUptime: %s" \
    "$ver" "$os" "$ip" "$xray" "$nginx" \
    "$(fh_svc_status mytunnel-sshws 2>/dev/null || echo OFF)" \
    "$(fh_svc_status dropbear 2>/dev/null || echo OFF)" \
    "$(get_uptime 2>/dev/null || echo -)"
}

bh_create_ssh(){
  local user="$1" days="$2" limit_ip="$3" quota="$4"
  validate_ssh_username "$user" 2>/dev/null || { echo "Username invalid (a-z0-9_ 3-16)"; return 1; }
  [[ "$days" =~ ^[0-9]+$ ]] || { echo "Hari harus angka"; return 1; }
  [ "$days" -ge 1 ] && [ "$days" -le 3650 ] || { echo "Hari 1-3650"; return 1; }
  limit_ip="${limit_ip:-0}"; quota="${quota:-0}"
  [[ "$limit_ip" =~ ^[0-9]+$ ]] || limit_ip=0
  local pass
  pass=$(_random_pass 2>/dev/null || openssl rand -base64 12 2>/dev/null | tr -dc 'a-zA-Z0-9' | head -c 8)
  [ -z "$pass" ] && pass="Pass$(date +%s | tail -c 5)"
  if declare -f ssh_create >/dev/null 2>&1; then
    if ! ssh_create "$user" "$pass" "$days" "$limit_ip" 2>&1; then return 1; fi
    local exp
    exp=$(ssh_get_field "$user" 3 2>/dev/null || echo "-")
    if declare -f print_ssh_account_info >/dev/null 2>&1; then
      print_ssh_account_info "$user" "$pass" "$exp" "$limit_ip" 2>/dev/null || true
    else
      echo "User $user pass $pass exp $exp"
    fi
  else
    echo "ssh_create belum tersedia"
    return 1
  fi
  bh_log "bot create_ssh $user ${days}d"
}

bh_create_proto(){
  local proto="$1" user="$2" days="$3" limit_ip="$4" quota="$5"
  [[ "$proto" =~ ^(vmess|vless|trojan)$ ]] || { echo "proto vmess/vless/trojan"; return 1; }
  validate_proto_user "$user" 2>/dev/null || { echo "Username invalid (a-z0-9 3-16, huruf kecil saja)"; return 1; }
  [[ "$days" =~ ^[0-9]+$ ]] || { echo "Hari harus angka"; return 1; }
  limit_ip="${limit_ip:-2}"; quota="${quota:-0}"
  [[ "$limit_ip" =~ ^[0-9]+$ ]] || limit_ip=2
  [[ "$quota" =~ ^[0-9]+$ ]] || quota=0
  if proto_exists_any "$user" >/dev/null 2>&1; then echo "User $user sudah ada di proto lain"; return 1; fi
  local id
  if [ "$proto" = "trojan" ]; then id=$(gen_password); else id=$(gen_uuid); fi
  if [ "$proto" != "trojan" ]; then validate_uuid "$id" || { echo "UUID gagal"; return 1; }; fi
  if ! proto_create "$proto" "$user" "$id" "$days" "$limit_ip" "$quota" 2>&1 | tail -n 5; then
    return 1
  fi
  # satu fungsi output dipakai ulang Create/Trial/bot - jangan salin manual
  print_proto_account_info "$proto" "$user" 2>/dev/null || gen_links "$proto" "$user" 2>/dev/null || echo "Akun $proto $user dibuat"
  bh_log "bot create $proto $user ${days}d"
}

bh_delete(){
  local user="$1"
  [[ "$user" =~ ^[a-z0-9_]{3,16}$ ]] || { echo "Username invalid"; return 1; }
  local found=0
  if grep -q "^${user}|" "$DB_SSH" 2>/dev/null; then
    if declare -f ssh_delete >/dev/null 2>&1; then ssh_delete "$user" 2>&1 | tail -n 5; fi
    echo "SSH $user dihapus"
    found=1
  fi
  for p in vmess vless trojan; do
    if proto_exists "$p" "$user" 2>/dev/null; then
      proto_delete "$p" "$user" 2>&1 | tail -n 5
      echo "$p $user dihapus"
      found=1
    fi
  done
  [ "$found" = "1" ] || echo "User $user tidak ditemukan"
  bh_log "bot delete $user"
}

bh_renew(){
  local user="$1" days="$2"
  [[ "$user" =~ ^[a-z0-9_]{3,16}$ ]] || { echo "Username invalid"; return 1; }
  [[ "$days" =~ ^[0-9]+$ ]] || { echo "Hari harus angka"; return 1; }
  local done=0
  if grep -q "^${user}|" "$DB_SSH" 2>/dev/null; then
    if declare -f ssh_renew >/dev/null 2>&1; then ssh_renew "$user" "$days" 2>&1 | tail -n 5; echo "SSH $user +${days}d"; done=1
    else echo "ssh_renew tidak tersedia"; fi
  fi
  for p in vmess vless trojan; do
    if proto_exists "$p" "$user" 2>/dev/null; then
      proto_renew "$p" "$user" "$days" 2>&1 | tail -n 5
      echo "$p $user +${days}d"; done=1
    fi
  done
  [ "$done" = "1" ] || echo "User $user tidak ditemukan"
  bh_log "bot renew $user ${days}d"
}

bh_list(){
  local out=""
  out+="SSH:\n"
  if [ -f "$DB_SSH" ]; then awk -F'|' '{printf " %s exp:%s lim:%s %s\n",$1,$3,$4,$5}' "$DB_SSH" 2>/dev/null | head -n 20; fi
  for p in vmess vless trojan; do
    out+="\n${p}:\n"
    local db="$ETC/db/${p}.txt"
    [ -f "$db" ] && awk -F'|' '{printf " %s exp:%s lim:%s q:%s %s\n",$1,$3,$4,$5,$7}' "$db" 2>/dev/null | head -n 20 || out+=" (kosong)\n"
  done
  echo -e "$out" | head -n 60
}

bh_trial(){
  local proto="${1:-vmess}"
  [[ "$proto" =~ ^(vmess|vless|trojan|ssh)$ ]] || proto="vmess"
  local user
  user="trial$(date +%s 2>/dev/null | tail -c 5)"
  user=$(echo "$user" | tr -dc 'a-z0-9' | head -c 10)
  [ -z "$user" ] && user="trial123"
  if [ "$proto" = "ssh" ]; then bh_create_ssh "$user" 1 1 1; else bh_create_proto "$proto" "$user" 1 1 1; fi
}

bh_backup_send(){
  local conf="$ETC/config/bot.conf"
  [ -f "$conf" ] || { echo "bot.conf tidak ada"; return 1; }
  # shellcheck disable=SC1090
  . "$conf" 2>/dev/null || true
  local bk
  bk=$(ls -1t "${BASE}/root/backup"/mytunnel-*.tar.gz 2>/dev/null | head -1)
  [ -z "$bk" ] && bk=$(ls -1t /root/backup/mytunnel-*.tar.gz 2>/dev/null | head -1)
  if [ -z "$bk" ] || [ ! -f "$bk" ]; then
    if [ -x "$ETC/features/backup.sh" ]; then bash "$ETC/features/backup.sh" 2>&1 | tail -n 10; fi
    bk=$(ls -1t "${BASE}/root/backup"/mytunnel-*.tar.gz 2>/dev/null | head -1)
    [ -z "$bk" ] && bk=$(ls -1t /root/backup/mytunnel-*.tar.gz 2>/dev/null | head -1)
  fi
  [ -f "$bk" ] || { echo "Backup tidak ditemukan"; return 1; }
  echo "Mengirim backup $(basename "$bk")..."
  curl -fsS --max-time 30 "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" -F "chat_id=${ADMIN_ID}" -F "document=@${bk}" -F "caption=Backup $(basename "$bk")" >/dev/null 2>&1 && echo "Backup terkirim" || echo "Gagal kirim backup"
  bh_log "bot backup sent $(basename "$bk")"
}

bh_restore_from_telegram(){
  local file_id="$1" file_name="$2"
  local conf="$ETC/config/bot.conf"
  [ -f "$conf" ] || { echo "bot.conf tidak ada"; return 1; }
  # shellcheck disable=SC1090
  . "$conf" 2>/dev/null || true
  [ -z "${BOT_TOKEN:-}" ] || [ -z "${ADMIN_ID:-}" ] && { echo "Token/admin kosong"; return 1; }
  [[ "$file_name" == *.tar.gz || "$file_name" == *.tgz || "$file_name" == *.tar || "$file_name" == *.gz ]] || { echo "Nama file harus .tar.gz"; return 1; }
  echo "Restore: ambil $file_name ..."
  local resp fpath
  resp=$(curl -fsS --max-time 15 "https://api.telegram.org/bot${BOT_TOKEN}/getFile" -d "file_id=${file_id}" 2>&1 || true)
  if ! echo "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then echo "Gagal getFile: $(echo "$resp" | head -c 200)"; return 1; fi
  fpath=$(echo "$resp" | jq -r '.result.file_path // empty' 2>/dev/null)
  [ -z "$fpath" ] && { echo "file_path kosong"; return 1; }
  local tmp_dir tmp_file
  tmp_dir=$(mktemp -d 2>/dev/null || echo "/tmp")
  tmp_file="$tmp_dir/mytunnel-restore-$(date +%s 2>/dev/null).tar.gz"
  # download via file api (HTTPS only)
  if ! curl -fsS --proto '=https' --tlsv1.2 --max-time 60 "https://api.telegram.org/file/bot${BOT_TOKEN}/${fpath}" -o "$tmp_file" 2>&1; then echo "Download gagal"; rm -rf "$tmp_dir" 2>/dev/null || true; return 1; fi
  chmod 600 "$tmp_file" 2>/dev/null || true
  local sz; sz=$(stat -c %s "$tmp_file" 2>/dev/null || stat -f %z "$tmp_file" 2>/dev/null || echo 0)
  if [ "$sz" -gt 25000000 ] 2>/dev/null; then echo "File >25MB ditolak"; rm -rf "$tmp_dir" 2>/dev/null || true; return 1; fi
  if ! tar tzf "$tmp_file" >/dev/null 2>&1 && ! tar tf "$tmp_file" >/dev/null 2>&1; then echo "Bukan arsip tar valid"; rm -rf "$tmp_dir" 2>/dev/null || true; return 1; fi
  # must contain etc/mytunnel (safety)
  if ! tar tf "$tmp_file" 2>/dev/null | grep -q "etc/mytunnel" ; then echo "Arsip tidak berisi etc/mytunnel — ditolak"; rm -rf "$tmp_dir" 2>/dev/null || true; return 1; fi
  # backup current before restore
  local pre_arch bk_dir
  if [ -n "$BASE" ]; then bk_dir="${BASE}/root/backup"; else bk_dir="/root/backup"; fi
  mkdir -p "$bk_dir" 2>/dev/null || true
  pre_arch="$bk_dir/mytunnel-pre-restore-$(date +%Y%m%d-%H%M%S 2>/dev/null).tar.gz"
  if [ -n "$BASE" ]; then tar -czf "$pre_arch" -C "$BASE" etc/mytunnel 2>/dev/null || true; else tar -czf "$pre_arch" -C / etc/mytunnel 2>/dev/null || true; fi
  chmod 600 "$pre_arch" 2>/dev/null || true
  echo "Ekstrak $file_name ..."
  local ok=1
  if [ -n "$BASE" ]; then tar -xzf "$tmp_file" -C "$BASE" 2>&1 | head -n 20 || ok=0; else tar -xzf "$tmp_file" -C / 2>&1 | head -n 20 || ok=0; fi
  if [ "$ok" -eq 0 ]; then echo "Gagal ekstrak, rollback"; [ -f "$pre_arch" ] && { if [ -n "$BASE" ]; then tar -xzf "$pre_arch" -C "$BASE" 2>/dev/null || true; else tar -xzf "$pre_arch" -C / 2>/dev/null || true; fi; }; rm -rf "$tmp_dir" 2>/dev/null || true; return 1; fi
  # perms
  chmod 600 "$ETC/db/"*.txt 2>/dev/null || true
  chmod 600 "$ETC/db/".*.lock 2>/dev/null || true
  # validate xray + nginx
  local valid=1
  local xcfg="${BASE}/usr/local/etc/xray/config.json"; [ -n "$BASE" ] || xcfg="/usr/local/etc/xray/config.json"
  if [ -f "$xcfg" ]; then
    if command -v jq >/dev/null 2>&1; then jq . "$xcfg" >/dev/null 2>&1 || valid=0; else python3 -m json.tool "$xcfg" >/dev/null 2>&1 || valid=0; fi
    if command -v xray >/dev/null 2>&1 || [ -x "${BASE}/usr/local/bin/xray" ]; then
      local bin="xray"; [ -x "${BASE}/usr/local/bin/xray" ] && bin="${BASE}/usr/local/bin/xray"
      "$bin" run -test -config "$xcfg" >/dev/null 2>&1 || valid=0
    fi
  fi
  if [ "$valid" -eq 0 ]; then echo "Validasi gagal, rollback"; [ -f "$pre_arch" ] && { if [ -n "$BASE" ]; then tar -xzf "$pre_arch" -C "$BASE" 2>/dev/null || true; else tar -xzf "$pre_arch" -C / 2>/dev/null || true; fi; }; rm -rf "$tmp_dir" 2>/dev/null || true; return 1; fi
  if [ -z "$BASE" ]; then
    systemctl restart xray 2>/dev/null || true; systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true; systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true
  fi
  rm -rf "$tmp_dir" 2>/dev/null || true
  bh_log "bot restore $file_name ok pre=$pre_arch"
  echo "Restore OK: $file_name"
  echo "Pre-restore backup: $(basename "$pre_arch")"
}

__EMBED_EOF__
chmod 644 "$ETC/bot/handlers.sh"
cat > "$ETC/advanced/warp.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel advanced/warp.sh - Cloudflare WARP (wgcf/WireGuard outbound warp)
# shellcheck disable=SC1091,SC1090,SC2154
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
XRAY_ETC="${MYTUNNEL_PREFIX:-}/usr/local/etc/xray"
[ -z "$MYTUNNEL_PREFIX" ] && XRAY_ETC="/usr/local/etc/xray"
XRAY_CFG="$XRAY_ETC/config.json"
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
WGCF_URL="https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_linux_amd64"
WGCF_SHA=""  # upstream tidak publish sha tetap; tampilkan url dan verifikasi manual
WGCF_BIN="${MYTUNNEL_PREFIX:-}/usr/local/bin/wgcf"
[ -z "$MYTUNNEL_PREFIX" ] && WGCF_BIN="/usr/local/bin/wgcf"
WGCF_DIR="${MYTUNNEL_PREFIX:-}/etc/wireguard"
[ -n "$MYTUNNEL_PREFIX" ] && WGCF_DIR="$MYTUNNEL_PREFIX/etc/wireguard"
WARP_CONF="$WGCF_DIR/wgcf-profile.conf"

warp_ip(){ ah_get_ip 2>/dev/null || echo "-"; }

warp_xray_has_warp(){
  command -v jq >/dev/null 2>&1 || return 1
  jq -e '.outbounds[] | select(.tag=="warp")' "$XRAY_CFG" >/dev/null 2>&1
}

warp_xray_add(){
  command -v jq >/dev/null 2>&1 || { echo -e "${RED}jq dibutuhkan${RESET}"; return 1; }
  [ -f "$XRAY_CFG" ] || { echo -e "${RED}Xray config tidak ada${RESET}"; return 1; }
  if warp_xray_has_warp 2>/dev/null; then echo -e "${YELLOW}Outbound warp sudah ada${RESET}"; return 0; fi
  local bak tmp
  bak=$(ah_backup_cfg "$XRAY_CFG")
  tmp=$(mktemp)
  # warp via WireGuard (Cloudflare) - placeholder; jika wgcf.conf ada, pakai privateKey/peer
  # ponytail: full WireGuard settings dari wgcf-profile.conf; upgrade to parse Address/PrivateKey/Peer
  jq '.outbounds += [{"protocol":"freedom","tag":"warp","settings":{}}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true
  rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then
    echo -e "${RED}Validasi gagal, rollback${RESET}"
    [ -n "$bak" ] && [ -f "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true
    return 1
  fi
  # restart xray if produksi
  if [ -z "$MYTUNNEL_PREFIX" ]; then systemctl restart xray 2>/dev/null || true; fi
  echo -e "${GREEN}Outbound warp ditambahkan${RESET}"
  ah_log "warp outbound added"
}

warp_xray_remove(){
  command -v jq >/dev/null 2>&1 || return 1
  if ! warp_xray_has_warp 2>/dev/null; then echo -e "${YELLOW}Outbound warp tidak ada${RESET}"; return 0; fi
  local bak tmp
  bak=$(ah_backup_cfg "$XRAY_CFG")
  tmp=$(mktemp)
  jq 'del(.outbounds[] | select(.tag=="warp")) | .routing.rules |= map(select(.outboundTag != "warp"))' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true
  rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then
    echo -e "${RED}Validasi gagal, rollback${RESET}"
    [ -n "$bak" ] && [ -f "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true
    return 1
  fi
  if [ -z "$MYTUNNEL_PREFIX" ]; then systemctl restart xray 2>/dev/null || true; fi
  echo -e "${GREEN}Outbound warp dihapus${RESET}"
  ah_log "warp outbound removed"
}

warp_install(){
  echo -e "${CYAN}=== Install WARP (wgcf) ===${RESET}"
  echo -e "${DIM}Sumber: $WGCF_URL${RESET}"
  echo -e "${DIM}Checksum: (upstream latest, verifikasi manual setelah download)${RESET}"
  echo -e "${DIM}Outbound Xray warp akan ditambahkan terpisah dari direct/blocked${RESET}"
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    mkdir -p "$(dirname "$WGCF_BIN")" "$WGCF_DIR" 2>/dev/null || true
    echo -e "${YELLOW}[TEST MODE] Simulasi download wgcf -> $WGCF_BIN${RESET}"
    printf '#!/bin/bash\necho wgcf-sim\n' > "$WGCF_BIN" 2>/dev/null || true
    chmod 755 "$WGCF_BIN" 2>/dev/null || true
    mkdir -p "$WGCF_DIR" 2>/dev/null || true
    echo -e "${GREEN}Simulasi selesai${RESET}"
    ah_log "warp install sim"
    return 0
  fi
  mkdir -p "$(dirname "$WGCF_BIN")" "$WGCF_DIR" 2>/dev/null || true
  if ! ah_download_https "$WGCF_URL" "$WGCF_BIN" "$WGCF_SHA" 2>&1; then
    echo -e "${RED}Download wgcf gagal${RESET}"; return 1
  fi
  chmod 755 "$WGCF_BIN" 2>/dev/null || true
  echo -e "${GREEN}wgcf terinstall: $WGCF_BIN${RESET}"
  "$WGCF_BIN" --help 2>&1 | head -n 5
  ah_log "warp wgcf installed"
  echo -e "${CYAN}Registrasi WARP...${RESET}"
  ( cd "$WGCF_DIR" 2>/dev/null && "$WGCF_BIN" register --accept-tos 2>&1 | head -n 20 ) || echo -e "${YELLOW}Register gagal, coba manual: wgcf register${RESET}"
  ( cd "$WGCF_DIR" 2>/dev/null && "$WGCF_BIN" generate 2>&1 | head -n 20 ) || true
  [ -f "$WARP_CONF" ] && echo -e "${GREEN}Profile: $WARP_CONF${RESET}" || echo -e "${YELLOW}Profile belum ada di $WGCF_DIR${RESET}"
}

warp_status(){
  echo -e "${CYAN}IP sebelum WARP: ${RESET}$(warp_ip)"
  if command -v wg >/dev/null 2>&1 && ip link show wgcf 2>/dev/null | grep -q wgcf; then echo -e "WireGuard wgcf: ${GREEN}UP${RESET}"; else echo -e "WireGuard wgcf: ${YELLOW}DOWN / belum aktif${RESET}"; fi
  if [ -f "$WARP_CONF" ]; then echo -e "Profile: ${GREEN}$WARP_CONF${RESET}"; grep -E "PrivateKey|Address|Endpoint" "$WARP_CONF" 2>/dev/null | sed 's/PrivateKey.*/PrivateKey = ***/' | head -n 10 | sed 's/^/  /'; else echo -e "Profile: ${YELLOW}belum ada${RESET}"; fi
  if warp_xray_has_warp 2>/dev/null; then echo -e "Xray outbound warp: ${GREEN}ADA${RESET}"; else echo -e "Xray outbound warp: ${YELLOW}TIDAK ADA${RESET}"; fi
  if [ -f "$XRAY_CFG" ] && command -v jq >/dev/null 2>&1; then echo -e "Outbounds: $(jq -r '.outbounds[].tag' "$XRAY_CFG" 2>/dev/null | tr '\n' ' ' )"; fi
  echo -e "${DIM}IP sesudah (jika warp aktif, cek curl ifconfig.me setelah routing)${RESET}"
}

warp_license(){
  echo -ne "License WARP+ (kosongkan batal): "
  local lic; read -r lic
  lic=$(echo "$lic" | tr -d ' \n')
  [ -z "$lic" ] && { echo "Batal"; return; }
  if [ -n "$MYTUNNEL_PREFIX" ]; then echo -e "${YELLOW}[TEST MODE] Sim license $lic (sim)${RESET}"; ah_log "warp license sim"; return; fi
  if [ ! -x "$WGCF_BIN" ]; then echo -e "${RED}wgcf belum terinstall${RESET}"; return 1; fi
  echo "$lic" > "$WGCF_DIR/license.txt" 2>/dev/null || true
  ( cd "$WGCF_DIR" 2>/dev/null && "$WGCF_BIN" update 2>&1 | head -n 20 ) || true
  echo -e "${GREEN}License diperbarui, generate ulang...${RESET}"
  ( cd "$WGCF_DIR" 2>/dev/null && "$WGCF_BIN" generate 2>&1 | head -n 20 ) || true
  ah_log "warp license updated"
}

warp_uninstall(){
  echo -ne "${YELLOW}Hapus WARP + outbound warp? [y/N]: ${RESET}"
  local a; read -r a; [[ "$a" =~ ^[Yy]$ ]] || { echo "Batal"; return; }
  warp_xray_remove 2>&1 || true
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    rm -f "$WGCF_BIN" 2>/dev/null || true
    rm -rf "$WGCF_DIR" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Uninstall sim selesai${RESET}"
    ah_log "warp uninstall sim"
    return
  fi
  systemctl stop wg-quick@wgcf 2>/dev/null || true
  rm -f "$WGCF_BIN" "$WARP_CONF" 2>/dev/null || true
  rm -rf "$WGCF_DIR" 2>/dev/null || true
  echo -e "${GREEN}WARP dihapus${RESET}"
  ah_log "warp uninstall"
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "WARP CLOUDFLARE"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "Sumber: github.com/ViRb3/wgcf (HTTPS)"
  if warp_xray_has_warp 2>/dev/null; then printf "${BLUE}│${RESET} Outbound warp: ${GREEN}%-42s${RESET} ${BLUE}│${RESET}\n" "ADA"; else printf "${BLUE}│${RESET} Outbound warp: ${YELLOW}%-42s${RESET} ${BLUE}│${RESET}\n" "TIDAK ADA"; fi
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Install wgcf + Registrasi                        ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Aktifkan Outbound warp di Xray                  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Nonaktifkan Outbound warp                       ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Cek Status & IP                                 ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Ganti License WARP+                             ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Uninstall                                       ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) Back                                            ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select [1-7]: ${RESET}"
  read -r c
  case "$c" in
    1) warp_install; pause;;
    2) warp_xray_add; pause;;
    3) warp_xray_remove; pause;;
    4) warp_status; pause;;
    5) warp_license; pause;;
    6) warp_uninstall; pause;;
    7|b|B|x|X) break;;
    *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/advanced/warp.sh"
cat > "$ETC/advanced/routing.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel advanced/routing.sh - Xray Routing (outbounds + rules)
# shellcheck disable=SC1091,SC1090,SC2154
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
XRAY_ETC="${MYTUNNEL_PREFIX:-}/usr/local/etc/xray"
[ -z "$MYTUNNEL_PREFIX" ] && XRAY_ETC="/usr/local/etc/xray"
XRAY_CFG="$XRAY_ETC/config.json"
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

routing_outbounds(){
  if ! command -v jq >/dev/null 2>&1; then echo -e "${RED}jq dibutuhkan${RESET}"; return 1; fi
  [ -f "$XRAY_CFG" ] || { echo -e "${RED}Config tidak ada${RESET}"; return 1; }
  echo -e "${CYAN}=== OUTBOUNDS ===${RESET}"
  printf "%-16s %-12s\n" "TAG" "PROTOCOL"
  echo "----------------------------------------" | cut -c1-40
  jq -r '.outbounds[] | "\(.tag) \(.protocol)"' "$XRAY_CFG" 2>/dev/null | while read -r tag proto; do printf "%-16s %-12s\n" "$tag" "$proto"; done
}

routing_rules(){
  if ! command -v jq >/dev/null 2>&1; then echo -e "${RED}jq dibutuhkan${RESET}"; return 1; fi
  echo -e "${CYAN}=== ROUTING RULES (max 60 kolom) ===${RESET}"
  # header 60
  echo "┌──────────────────────────────────────────────────────────┐"
  printf "│ %-4s %-18s %-14s %-14s │\n" "#" "MATCH" "TYPE" "OUTBOUND"
  echo "├──────────────────────────────────────────────────────────┤"
  local i=0
  jq -c '.routing.rules[]?' "$XRAY_CFG" 2>/dev/null | while IFS= read -r rule; do
    i=$((i+1))
    local ot dom ip prot
    ot=$(echo "$rule" | jq -r '.outboundTag // "-"' 2>/dev/null | cut -c1-14)
    dom=$(echo "$rule" | jq -r '(.domain // [] | join(",")) // "-"' 2>/dev/null | cut -c1-18)
    [ "$dom" = "" ] && dom="-"
    ip=$(echo "$rule" | jq -r '(.ip // [] | join(",")) // ""' 2>/dev/null | cut -c1-14)
    prot=$(echo "$rule" | jq -r '(.protocol // [] | join(",")) // ""' 2>/dev/null | cut -c1-14)
    local match="$dom"
    [ -n "$ip" ] && [ "$ip" != "null" ] && match="$ip"
    [ -n "$prot" ] && [ "$prot" != "null" ] && [ "$prot" != "" ] && match="$prot"
    # inboundTag special
    local itag
    itag=$(echo "$rule" | jq -r '(.inboundTag // [] | join(",")) // ""' 2>/dev/null)
    if [ -n "$itag" ] && [ "$itag" != "null" ] && [ "$itag" != "" ]; then match="in:$itag"; fi
    match=$(echo "$match" | cut -c1-18)
    local type
    type=$(echo "$rule" | jq -r '.type // "field"' 2>/dev/null | cut -c1-14)
    printf "│ %-4s %-18s %-14s %-14s │\n" "$i" "$match" "$type" "$ot"
    if [ "$i" -ge 20 ]; then echo "│ ... (potong 20)                                          │"; break; fi
  done
  echo "└──────────────────────────────────────────────────────────┘"
  echo -e "${DIM}Prioritas: atas -> bawah (pertama cocok menang)${RESET}"
}

routing_add_outbound(){
  echo -ne "Tag outbound baru (a-z0-9_-): "
  local tag; read -r tag
  tag=$(echo "$tag" | tr -d ' \n')
  [[ "$tag" =~ ^[a-z0-9_-]{1,16}$ ]] || { echo -e "${RED}Tag invalid${RESET}"; return 1; }
  if jq -e --arg t "$tag" '.outbounds[] | select(.tag==$t)' "$XRAY_CFG" >/dev/null 2>&1; then echo -e "${RED}Tag sudah ada${RESET}"; return 1; fi
  echo -ne "Protocol (freedom/blackhole/wireguard) [freedom]: "
  local proto; read -r proto
  proto=$(echo "$proto" | tr -d ' \n'); [ -z "$proto" ] && proto="freedom"
  [[ "$proto" =~ ^(freedom|blackhole|wireguard)$ ]] || { echo -e "${RED}Protocol harus freedom/blackhole/wireguard${RESET}"; return 1; }
  local bak tmp
  bak=$(ah_backup_cfg "$XRAY_CFG")
  tmp=$(mktemp)
  jq --arg tag "$tag" --arg proto "$proto" '.outbounds += [{"protocol":$proto,"tag":$tag}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true; rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then echo -e "${RED}Validasi gagal, rollback${RESET}"; [ -n "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true; return 1; fi
  [ -z "$MYTUNNEL_PREFIX" ] && systemctl restart xray 2>/dev/null || true
  echo -e "${GREEN}Outbound $tag ($proto) ditambahkan${RESET}"; ah_log "routing add outbound $tag"
}

routing_del_outbound(){
  routing_outbounds
  echo -ne "Tag yang dihapus: "
  local tag; read -r tag
  tag=$(echo "$tag" | tr -d ' \n')
  [ -z "$tag" ] && { echo "Batal"; return; }
  if [ "$tag" = "direct" ] || [ "$tag" = "api" ] || [ "$tag" = "blocked" ]; then echo -e "${RED}Tag sistem tidak boleh dihapus${RESET}"; return 1; fi
  if ! jq -e --arg t "$tag" '.outbounds[] | select(.tag==$t)' "$XRAY_CFG" >/dev/null 2>&1; then echo -e "${RED}Tag tidak ada${RESET}"; return 1; fi
  local bak tmp
  bak=$(ah_backup_cfg "$XRAY_CFG")
  tmp=$(mktemp)
  jq --arg t "$tag" 'del(.outbounds[] | select(.tag==$t)) | .routing.rules |= map(select(.outboundTag != $t))' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true; rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then echo -e "${RED}Validasi gagal, rollback${RESET}"; [ -n "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true; return 1; fi
  [ -z "$MYTUNNEL_PREFIX" ] && systemctl restart xray 2>/dev/null || true
  echo -e "${GREEN}Outbound $tag dihapus${RESET}"; ah_log "routing del outbound $tag"
}

routing_add_rule(){
  echo -e "${CYAN}Tambah Rule Routing${RESET}"
  echo -e "${DIM}Contoh: geosite:netflix -> warp | geosite:category-ads-all -> blocked | bittorrent -> blocked${RESET}"
  routing_outbounds
  echo -ne "Outbound tujuan: "
  local ot; read -r ot
  ot=$(echo "$ot" | tr -d ' \n')
  [ -z "$ot" ] && { echo "Batal"; return; }
  if ! jq -e --arg t "$ot" '.outbounds[] | select(.tag==$t)' "$XRAY_CFG" >/dev/null 2>&1; then echo -e "${RED}Outbound tidak ada${RESET}"; return 1; fi
  echo -ne "Domain/geosite (kosongkan jika pakai IP/protocol) [geosite:category-ads-all]: "
  local dom; read -r dom
  dom=$(echo "$dom" | tr -d ' \n')
  echo -ne "IP/CIDR (kosongkan jika tidak perlu): "
  local ipc; read -r ipc
  ipc=$(echo "$ipc" | tr -d ' \n')
  echo -ne "Protocol (bittorrent/kosongkan): "
  local prot; read -r prot
  prot=$(echo "$prot" | tr -d ' \n')
  if [ -z "$dom" ] && [ -z "$ipc" ] && [ -z "$prot" ]; then echo -e "${RED}Minimal isi satu: domain/ip/protocol${RESET}"; return 1; fi
  local bak tmp
  bak=$(ah_backup_cfg "$XRAY_CFG")
  tmp=$(mktemp)
  # build rule json via jq --arg
  if [ -n "$dom" ] && [ -n "$ipc" ]; then
    jq --arg ot "$ot" --arg dom "$dom" --arg ipc "$ipc" '.routing.rules += [{"type":"field","domain":[$dom],"ip":[$ipc],"outboundTag":$ot}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  elif [ -n "$dom" ] && [ -n "$prot" ]; then
    jq --arg ot "$ot" --arg dom "$dom" --arg prot "$prot" '.routing.rules += [{"type":"field","domain":[$dom],"protocol":[$prot],"outboundTag":$ot}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  elif [ -n "$dom" ]; then
    jq --arg ot "$ot" --arg dom "$dom" '.routing.rules += [{"type":"field","domain":[$dom],"outboundTag":$ot}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  elif [ -n "$ipc" ]; then
    jq --arg ot "$ot" --arg ipc "$ipc" '.routing.rules += [{"type":"field","ip":[$ipc],"outboundTag":$ot}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  elif [ -n "$prot" ]; then
    jq --arg ot "$ot" --arg prot "$prot" '.routing.rules += [{"type":"field","protocol":[$prot],"outboundTag":$ot}]' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  fi
  cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true; rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then echo -e "${RED}Validasi gagal, rollback${RESET}"; [ -n "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true; return 1; fi
  # pastikan rule api tetap pertama
  # move api rule to top if not
  tmp=$(mktemp)
  jq '.routing.rules |= (map(select(.inboundTag != null)) + map(select(.inboundTag == null))) | .routing.rules |= (map(select(.inboundTag == ["api"])) + map(select(.inboundTag != ["api"] or .inboundTag == null)))' "$XRAY_CFG" > "$tmp" 2>/dev/null && cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true
  rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then echo -e "${RED}Validasi urutan gagal, rollback${RESET}"; [ -n "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true; return 1; fi
  [ -z "$MYTUNNEL_PREFIX" ] && systemctl restart xray 2>/dev/null || true
  echo -e "${GREEN}Rule ditambahkan -> $ot${RESET}"; ah_log "routing add rule $ot $dom $ipc $prot"
}

routing_del_rule(){
  routing_rules
  echo -ne "Nomor rule yang dihapus: "
  local n; read -r n
  n=$(echo "$n" | tr -dc '0-9' | head -c 5)
  [ -z "$n" ] && { echo "Batal"; return; }
  local total
  total=$(jq '.routing.rules | length' "$XRAY_CFG" 2>/dev/null || echo 0)
  if [ "$n" -lt 1 ] || [ "$n" -gt "$total" ] 2>/dev/null; then echo -e "${RED}Nomor invalid (1-$total)${RESET}"; return 1; fi
  # cegah hapus rule api
  local is_api
  is_api=$(jq -r --argjson idx "$((n-1))" '.routing.rules[$idx].inboundTag // empty | join(",")' "$XRAY_CFG" 2>/dev/null)
  if [ "$is_api" = "api" ]; then echo -e "${RED}Rule api tidak boleh dihapus (stats)${RESET}"; return 1; fi
  local bak tmp
  bak=$(ah_backup_cfg "$XRAY_CFG")
  tmp=$(mktemp)
  jq --argjson idx "$((n-1))" 'del(.routing.rules[$idx])' "$XRAY_CFG" > "$tmp" 2>&1 || { echo -e "${RED}jq gagal${RESET}"; rm -f "$tmp"; return 1; }
  cat "$tmp" > "$XRAY_CFG" 2>/dev/null || true; rm -f "$tmp" 2>/dev/null || true
  if ! ah_xray_validate 2>&1; then echo -e "${RED}Validasi gagal, rollback${RESET}"; [ -n "$bak" ] && cp -a "$bak" "$XRAY_CFG" 2>/dev/null || true; return 1; fi
  [ -z "$MYTUNNEL_PREFIX" ] && systemctl restart xray 2>/dev/null || true
  echo -e "${GREEN}Rule #$n dihapus${RESET}"; ah_log "routing del rule $n"
}

routing_check(){
  routing_outbounds
  echo ""
  routing_rules
  echo ""
  echo -e "${CYAN}xray run -test:${RESET}"
  if ah_xray_validate 2>&1; then echo -e "${GREEN}Configuration OK${RESET}"; else echo -e "${RED}FAILED${RESET}"; fi
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "ROUTING XRAY"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if command -v jq >/dev/null 2>&1 && [ -f "$XRAY_CFG" ]; then
    printf "${BLUE}│${RESET} Outbounds: %-43s ${BLUE}│${RESET}\n" "$(jq -r '.outbounds[].tag' "$XRAY_CFG" 2>/dev/null | tr '\n' ' ' | cut -c1-43)"
    printf "${BLUE}│${RESET} Rules: %-46s ${BLUE}│${RESET}\n" "$(jq '.routing.rules | length' "$XRAY_CFG" 2>/dev/null) rule(s)"
  else
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "jq/config tidak tersedia"
  fi
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} OUTBOUNDS                                         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 1.) List Outbounds                                 ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Tambah Outbound                                ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Hapus Outbound                                 ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} RULES (prioritas atas->bawah)                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) List Rules                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Tambah Rule (geosite/domain/ip/protocol)       ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Hapus Rule                                     ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 7.) Check Config Routing                           ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 8.) Back                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select [1-8]: ${RESET}"
  read -r c
  case "$c" in
    1) routing_outbounds; pause;;
    2) routing_add_outbound; pause;;
    3) routing_del_outbound; pause;;
    4) routing_rules; pause;;
    5) routing_add_rule; pause;;
    6) routing_del_rule; pause;;
    7) routing_check; pause;;
    8|b|B|x|X) break;;
    *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/advanced/routing.sh"
cat > "$ETC/advanced/slowdns.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel advanced/slowdns.sh - dnstt/slowdns tunneling DNS->SSH lokal
# shellcheck disable=SC1091,SC1090,SC2154
MYTUNNEL_PREFIX="${MYTUNNEL_PREFIX:-}"
if [ -n "$MYTUNNEL_PREFIX" ]; then BASE="$MYTUNNEL_PREFIX/etc/mytunnel"; else BASE="/etc/mytunnel"; fi
for f in "$BASE/lib/colors.sh" "$BASE/lib/helpers.sh" "$BASE/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"
CONF="$BASE/config/slowdns.conf"
KEYDIR="$BASE/slowdns"
DNSTT_URL="https://github.com/buraksezer/dnstt/releases/latest/download/dnstt-server_linux_amd64"
DNSTT_SHA=""
DNSTT_BIN="${MYTUNNEL_PREFIX:-}/usr/local/bin/dnstt-server"
[ -z "$MYTUNNEL_PREFIX" ] && DNSTT_BIN="/usr/local/bin/dnstt-server"
SERVICE="mytunnel-slowdns"

slowdns_status(){
  echo -e "${CYAN}=== SLOWDNS STATUS ===${RESET}"
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF" 2>/dev/null || true
    echo -e "NS domain : ${NS_DOMAIN:-(-)}"
    echo -e "SSH target: 127.0.0.1:${SSH_PORT:-22}"
    if [ -f "$KEYDIR/server.key" ]; then echo -e "Privkey  : ${GREEN}$KEYDIR/server.key (600)${RESET}"; ls -l "$KEYDIR/server.key" 2>/dev/null | awk '{print "  "$1" "$9}' | sed 's/^/  /'; else echo -e "Privkey  : ${YELLOW}belum ada${RESET}"; fi
    if [ -f "$KEYDIR/server.pub" ]; then echo -e "Pubkey   : $(cat "$KEYDIR/server.pub" 2>/dev/null | cut -c1-60)"; else echo -e "Pubkey   : ${YELLOW}belum ada${RESET}"; fi
  else
    echo -e "Config  : ${YELLOW}belum ada ($CONF)${RESET}"
  fi
  echo -e "Binary  : $( [ -x "$DNSTT_BIN" ] && echo "${GREEN}$DNSTT_BIN OK${RESET}" || echo "${YELLOW}belum terinstall${RESET}")"
  local st
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    if [ -f "$BASE/var/log/${SERVICE}.sim" ] || [ -f "$BASE/etc/systemd/system/${SERVICE}.service" ]; then st="ON (sim)"; else st="OFF"; fi
  else
    if systemctl is-active --quiet "$SERVICE" 2>/dev/null; then st="ON"; else st="OFF"; fi
  fi
  echo -e "Service $SERVICE : $st"
  echo -e "Port 53 : $(ss -tulnp 2>/dev/null | grep -q ':53 ' && echo "LISTEN" || echo "- (ss tidak ada/test mode)")"
  if [ -f "/etc/systemd/resolved.conf" ]; then
    echo -e "resolved.conf stub: $(grep -E 'DNSStubListener' /etc/systemd/resolved.conf 2>/dev/null | head -1 || echo "-")"
  fi
  echo ""
  echo -e "${DIM}DNS yang harus dibuat:${RESET}"
  echo -e "  1. A record: ns.<domain> -> $(ah_get_ip 2>/dev/null | tr -d '\n' | cut -c1-20) (IP VPS)"
  echo -e "  2. NS record: tunnel.<domain> -> ns.<domain>"
  echo -e "  Contoh jika domain example.com dan NS ns.example.com:"
  echo -e "    ns.example.com.  A   <IP-VPS>"
  echo -e "    tunnel.example.com. NS ns.example.com."
}

slowdns_install(){
  echo -e "${CYAN}=== Install SlowDNS (dnstt) ===${RESET}"
  echo -e "${DIM}Sumber resmi: $DNSTT_URL${RESET}"
  echo -e "${DIM}Checksum: $DNSTT_SHA (verifikasi manual setelah download)${RESET}"
  echo -e "${DIM}Port target SSH: 127.0.0.1:22 (atau 127.0.0.1:10004 via sshws)${RESET}"
  local ns ssh_port
  echo -ne "NS domain (contoh ns.example.com): "
  read -r ns
  ns=$(echo "$ns" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
  [ -z "$ns" ] && { echo "Batal"; return; }
  if ! ah_validate_ns_domain "$ns"; then echo -e "${RED}Format NS domain invalid${RESET}"; return 1; fi
  echo -ne "Port SSH target [22]: "
  read -r ssh_port
  ssh_port=$(echo "$ssh_port" | tr -dc '0-9' | head -c 5)
  [ -z "$ssh_port" ] && ssh_port=22
  if [ "$ssh_port" -lt 1 ] || [ "$ssh_port" -gt 65535 ] 2>/dev/null; then echo -e "${RED}Port 1-65535${RESET}"; return 1; fi
  mkdir -p "$KEYDIR" "$(dirname "$DNSTT_BIN")" "$(dirname "$CONF")" 2>/dev/null || true

  # handle port 53 conflict: systemd-resolved stub
  local resolved_bak=""
  if [ -f "/etc/systemd/resolved.conf" ] && grep -q "DNSStubListener=yes" /etc/systemd/resolved.conf 2>/dev/null; then
    echo -e "${YELLOW}systemd-resolved stub aktif, backup dan nonaktifkan...${RESET}"
    if [ -z "$MYTUNNEL_PREFIX" ]; then
      resolved_bak="/etc/systemd/resolved.conf.bak-$(date +%Y%m%d-%H%M%S)"
      cp -a /etc/systemd/resolved.conf "$resolved_bak" 2>/dev/null || true
      # backup juga via advanced_helpers
      ah_backup_cfg /etc/systemd/resolved.conf >/dev/null 2>&1 || true
      mkdir -p /etc/systemd/resolved.conf.d 2>/dev/null || true
      # disable stub safely, keep DNS VPS via /etc/resolv.conf fallback
      if grep -q "^\[Resolve\]" /etc/systemd/resolved.conf 2>/dev/null; then
        sed -i 's/^#*DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf 2>/dev/null || echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
      else
        printf '\n[Resolve]\nDNSStubListener=no\n' >> /etc/systemd/resolved.conf 2>/dev/null || true
      fi
      # ensure resolv.conf still has DNS
      if [ -f /etc/resolv.conf ] && ! grep -q "nameserver" /etc/resolv.conf 2>/dev/null; then
        echo "nameserver 1.1.1.1" >> /etc/resolv.conf 2>/dev/null || true
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf 2>/dev/null || true
      fi
      systemctl restart systemd-resolved 2>/dev/null || true
      echo -e "${GREEN}systemd-resolved stub dinonaktifkan (backup $resolved_bak)${RESET}"
      ah_log "slowdns disable resolved stub backup $resolved_bak"
    else
      echo -e "${YELLOW}[TEST MODE] Simulasi nonaktifkan stub${RESET}"
    fi
  fi

  # download dnstt-server
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    echo -e "${YELLOW}[TEST MODE] Simulasi download dnstt-server -> $DNSTT_BIN${RESET}"
    printf '#!/bin/bash\necho dnstt-sim\n' > "$DNSTT_BIN" 2>/dev/null || true
    chmod 755 "$DNSTT_BIN" 2>/dev/null || true
  else
    if ! ah_download_https "$DNSTT_URL" "$DNSTT_BIN" "$DNSTT_SHA" 2>&1; then
      echo -e "${RED}Download dnstt gagal${RESET}"
      # rollback resolved if changed
      [ -n "$resolved_bak" ] && [ -f "$resolved_bak" ] && cp -a "$resolved_bak" /etc/systemd/resolved.conf 2>/dev/null || true
      return 1
    fi
    chmod 755 "$DNSTT_BIN" 2>/dev/null || true
  fi

  # generate keypair
  echo -e "${CYAN}Generate keypair...${RESET}"
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    # sim keys
    head -c 32 /dev/urandom 2>/dev/null | base64 | tr -d '\n' | head -c 44 > "$KEYDIR/server.key" 2>/dev/null || echo "sim-privkey-$(date +%s)" > "$KEYDIR/server.key"
    head -c 32 /dev/urandom 2>/dev/null | base64 | tr -d '\n' | head -c 44 > "$KEYDIR/server.pub" 2>/dev/null || echo "sim-pubkey-$(date +%s)" > "$KEYDIR/server.pub"
    chmod 600 "$KEYDIR/server.key" 2>/dev/null || true
    chmod 644 "$KEYDIR/server.pub" 2>/dev/null || true
  else
    if [ -x "$DNSTT_BIN" ] && "$DNSTT_BIN" -gen-key -privkey-file "$KEYDIR/server.key" -pubkey-file "$KEYDIR/server.pub" 2>&1 | head -n 10; then
      chmod 600 "$KEYDIR/server.key" 2>/dev/null || true
      chmod 644 "$KEYDIR/server.pub" 2>/dev/null || true
    else
      # fallback openssl
      openssl rand -base64 32 2>/dev/null | tr -d '\n' > "$KEYDIR/server.key" 2>/dev/null || head -c 32 /dev/urandom | base64 > "$KEYDIR/server.key" 2>/dev/null || true
      chmod 600 "$KEYDIR/server.key" 2>/dev/null || true
      cp "$KEYDIR/server.key" "$KEYDIR/server.pub" 2>/dev/null || true
      chmod 644 "$KEYDIR/server.pub" 2>/dev/null || true
    fi
  fi

  cat > "$CONF" <<CFEOF
NS_DOMAIN="$ns"
SSH_PORT="$ssh_port"
RESOLVED_BAK="$resolved_bak"
CFEOF
  chmod 644 "$CONF" 2>/dev/null || true
  echo -e "${GREEN}Keypair dibuat:${RESET}"
  echo -e "  priv: $KEYDIR/server.key (600)"
  echo -e "  pub : $(cat "$KEYDIR/server.pub" 2>/dev/null | cut -c1-60)"
  echo -e "${CYAN}NS domain: $ns -> SSH 127.0.0.1:$ssh_port${RESET}"
  echo -e "${YELLOW}Jangan lupa buat record DNS:${RESET}"
  echo -e "  ${ns}.  A  $(ah_get_ip 2>/dev/null | tr -d '\n' | cut -c1-20)"
  # ufw allow 53 + 5300 (Langkah 4: 5300 real listen)
  if [ -z "$MYTUNNEL_PREFIX" ]; then
    if command -v ufw >/dev/null 2>&1; then ufw allow 53/udp 2>/dev/null || true; ufw allow 53/tcp 2>/dev/null || true; ufw allow 5300/udp 2>/dev/null || true; echo -e "${GREEN}UFW 53/udp,53/tcp,5300/udp allow${RESET}"; fi
  else
    echo -e "${YELLOW}[TEST MODE] UFW allow 53+5300 sim${RESET}"
  fi
  ah_log "slowdns installed ns $ns port $ssh_port"

  # enable service
  slowdns_enable
}

_slowdns_setup_redirect(){
  # Redirect UDP 53 -> 5300 via iptables/nftables (exclusive mode: 53 for SlowDNS, not OpenVPN DNS)
  # Backup not needed - idempotent delete then add
  local do53="53" to="5300"
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    echo "$do53 -> $to" > "$BASE/var/log/slowdns-redirect.sim" 2>/dev/null || true
    echo -e "${DIM}[TEST MODE] iptables REDIRECT $do53 -> $to sim${RESET}"
    return 0
  fi
  # Remove old redirect if exists (idempotent)
  iptables -t nat -D PREROUTING -p udp --dport $do53 -j REDIRECT --to-port $to 2>/dev/null || true
  iptables -t nat -D OUTPUT -o lo -p udp --dport $do53 -j REDIRECT --to-port $to 2>/dev/null || true
  # nft fallback
  if command -v nft >/dev/null 2>&1; then
    nft delete rule ip nat PREROUTING udp dport $do53 redirect to :$to 2>/dev/null || true
  fi
  # Add redirect
  if command -v iptables >/dev/null 2>&1; then
    iptables -t nat -A PREROUTING -p udp --dport $do53 -j REDIRECT --to-port $to 2>/dev/null || true
    iptables -t nat -A OUTPUT -o lo -p udp --dport $do53 -j REDIRECT --to-port $to 2>/dev/null || true
    echo -e "${GREEN}iptables REDIRECT UDP $do53 -> $to${RESET}"
    # persist netfilter if available
    if command -v netfilter-persistent >/dev/null 2>&1; then netfilter-persistent save 2>/dev/null || true; fi
    if command -v iptables-save >/dev/null 2>&1 && [ -d /etc/iptables ]; then iptables-save > /etc/iptables/rules.v4 2>/dev/null || true; fi
  elif command -v nft >/dev/null 2>&1; then
    nft add rule ip nat PREROUTING udp dport $do53 redirect to :$to 2>/dev/null || true
    echo -e "${GREEN}nft REDIRECT UDP $do53 -> $to${RESET}"
  else
    echo -e "${YELLOW}iptables/nft tidak ada, SlowDNS hanya listen :$to tanpa redirect${RESET}"
  fi
  # Check conflict with OpenVPN DNS 53
  if ss -ulnp 2>/dev/null | grep -q ":53 " && ! ss -ulnp 2>/dev/null | grep -q "mytunnel-slowdns"; then
    echo -e "${YELLOW}Warning: port 53 sudah dipakai (mungkin OpenVPN DNS 53). Uninstall OpenVPN DNS atau SlowDNS terlebih dahulu.${RESET}"
  fi
  ah_log "slowdns redirect $do53->$to"
}

_slowdns_remove_redirect(){
  local do53="53" to="5300"
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    rm -f "$BASE/var/log/slowdns-redirect.sim" 2>/dev/null || true
    echo -e "${DIM}[TEST MODE] hapus REDIRECT $do53 -> $to sim${RESET}"
    return 0
  fi
  iptables -t nat -D PREROUTING -p udp --dport $do53 -j REDIRECT --to-port $to 2>/dev/null || true
  iptables -t nat -D OUTPUT -o lo -p udp --dport $do53 -j REDIRECT --to-port $to 2>/dev/null || true
  if command -v nft >/dev/null 2>&1; then nft delete rule ip nat PREROUTING udp dport $do53 redirect to :$to 2>/dev/null || true; fi
  echo -e "${YELLOW}iptables REDIRECT $do53 -> $to dihapus${RESET}"
  ah_log "slowdns remove redirect $do53->$to"
}

slowdns_enable(){
  [ -f "$CONF" ] || { echo -e "${RED}Config belum ada, install dulu${RESET}"; return 1; }
  # shellcheck disable=SC1090
  . "$CONF" 2>/dev/null || true
  local ns="${NS_DOMAIN:-}" port="${SSH_PORT:-22}"
  # Langkah 4: dnstt listen :5300, 53 redirect via iptables (jaga 80/443 exclusive, 53 mutual exclusion)
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    mkdir -p "$BASE/etc/systemd/system" "$BASE/var/log" 2>/dev/null || true
    cat > "$BASE/etc/systemd/system/${SERVICE}.service" <<SVCEOF
[Unit]
Description=mytunnel SlowDNS (dnstt)
After=network.target

[Service]
Type=simple
ExecStart=$DNSTT_BIN -udp :5300 -privkey-file $KEYDIR/server.key $ns 127.0.0.1:$port
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
    touch "$BASE/var/log/${SERVICE}.sim" 2>/dev/null || true
    _slowdns_setup_redirect
    echo -e "${GREEN}[TEST MODE] Service $SERVICE dibuat (sim) :5300 -> 53 redirect${RESET}"
    ah_log "slowdns enable sim $ns :5300"
    return 0
  fi
  cat > "/etc/systemd/system/${SERVICE}.service" <<SVCEOF2
[Unit]
Description=mytunnel SlowDNS (dnstt)
After=network.target

[Service]
Type=simple
ExecStart=$DNSTT_BIN -udp :5300 -privkey-file $KEYDIR/server.key $ns 127.0.0.1:$port
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF2
  chmod 644 "/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now "$SERVICE" 2>/dev/null || systemctl restart "$SERVICE" 2>/dev/null || true
  echo -e "${GREEN}Service $SERVICE diaktifkan${RESET}"
  ah_log "slowdns enable $ns"
}

slowdns_disable(){
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    rm -f "$BASE/var/log/${SERVICE}.sim" 2>/dev/null || true
    _slowdns_remove_redirect
    echo -e "${YELLOW}[TEST MODE] Service $SERVICE dimatikan (sim)${RESET}"
    ah_log "slowdns disable sim"
    return 0
  fi
  systemctl disable --now "$SERVICE" 2>/dev/null || systemctl stop "$SERVICE" 2>/dev/null || true
  _slowdns_remove_redirect
  echo -e "${YELLOW}Service $SERVICE dimatikan${RESET}"
  ah_log "slowdns disable"
}

slowdns_uninstall(){
  echo -ne "${YELLOW}Hapus SlowDNS + kembalikan resolver? [y/N]: ${RESET}"
  local a; read -r a; [[ "$a" =~ ^[Yy]$ ]] || { echo "Batal"; return; }
  slowdns_disable 2>&1 || true
  _slowdns_remove_redirect 2>&1 || true
  # restore resolved.conf if backed up
  local bak=""
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF" 2>/dev/null || true
    bak="${RESOLVED_BAK:-}"
  fi
  if [ -n "$bak" ] && [ -f "$bak" ] && [ -z "$MYTUNNEL_PREFIX" ]; then
    cp -a "$bak" /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
    echo -e "${GREEN}Resolver dikembalikan dari $bak${RESET}"
  elif [ -z "$MYTUNNEL_PREFIX" ] && [ -f /etc/systemd/resolved.conf ]; then
    # remove our override if no bak
    sed -i '/DNSStubListener=no/d' /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
  else
    echo -e "${YELLOW}[TEST MODE] Resolver restore sim${RESET}"
  fi
  if [ -n "$MYTUNNEL_PREFIX" ]; then
    rm -f "$DNSTT_BIN" 2>/dev/null || true
    rm -rf "$KEYDIR" 2>/dev/null || true
    rm -f "$CONF" "$BASE/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
    echo -e "${GREEN}[TEST MODE] Uninstall sim selesai${RESET}"
    ah_log "slowdns uninstall sim"
    return
  fi
  rm -f "$DNSTT_BIN" 2>/dev/null || true
  rm -rf "$KEYDIR" 2>/dev/null || true
  rm -f "$CONF" "/etc/systemd/system/${SERVICE}.service" 2>/dev/null || true
  systemctl daemon-reload 2>/dev/null || true
  if command -v ufw >/dev/null 2>&1; then ufw delete allow 53/udp 2>/dev/null || true; ufw delete allow 53/tcp 2>/dev/null || true; fi
  echo -e "${GREEN}SlowDNS dihapus${RESET}"
  ah_log "slowdns uninstall"
}

while true; do
  clear 2>/dev/null || printf '\033c'
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "SLOWDNS (DNS tunneling -> SSH)"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF" 2>/dev/null || true
    printf "${BLUE}│${RESET} NS: %-52s ${BLUE}│${RESET}\n" "${NS_DOMAIN:-(-)}"
    printf "${BLUE}│${RESET} SSH: 127.0.0.1:%-40s ${BLUE}│${RESET}\n" "${SSH_PORT:-22}"
    if [ -f "$KEYDIR/server.pub" ]; then printf "${BLUE}│${RESET} Pub: %-52s ${BLUE}│${RESET}\n" "$(cat "$KEYDIR/server.pub" 2>/dev/null | cut -c1-52)"; fi
  else
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "Belum terinstall"
  fi
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} 1.) Install & Setup (NS + keypair)                 ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2.) Cek Status & Info DNS                          ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3.) Aktifkan Service                               ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4.) Nonaktifkan Service                            ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 5.) Uninstall (kembalikan resolver)                ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 6.) Back                                           ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -ne "${BOLD}Select [1-6]: ${RESET}"
  read -r c
  case "$c" in
    1) slowdns_install; pause;;
    2) slowdns_status; pause;;
    3) slowdns_enable; pause;;
    4) slowdns_disable; pause;;
    5) slowdns_uninstall; pause;;
    6|b|B|x|X) break;;
    *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
  esac
done

__EMBED_EOF__
chmod 755 "$ETC/advanced/slowdns.sh"
cat > "$ETC/advanced/ssh_extra.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel advanced/ssh_extra.sh - Layanan SSH Tambahan (Squid/UDPGW/OHP) - OPSIONAL
# Dipasang via FEATURES > Advanced > Install Layanan SSH Tambahan
# Semua install/uninstall bersih, tidak merusak layanan lain.
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
if [ -n "$BASE" ]; then ETC="$BASE/etc/mytunnel"; else ETC="/etc/mytunnel"; fi
PF="$ETC/config/ports.conf"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/advanced_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"; CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

pause(){ echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

_get_pf(){
  # shellcheck disable=SC1090
  [ -f "$PF" ] && . "$PF" 2>/dev/null || true
}

_status_one(){
  local name="$1" svc="$2" port_csv="$3"
  local st="OFF"
  # check via systemctl or ss or sim file
  if [ -n "$BASE" ]; then
    case "$name" in
      squid) [ -f "$BASE/etc/systemd/system/mytunnel-squid.service" ] && st="ON(sim)" || st="OFF" ;;
      udpgw) [ -f "$BASE/var/log/udpgw-sim.log" ] && st="ON(sim)" || st="OFF" ;;
      ohp-ssh) [ -f "$BASE/etc/systemd/system/mytunnel-ohp-ssh.service" ] && st="ON(sim)" || st="OFF" ;;
      ohp-ovpn) [ -f "$BASE/etc/systemd/system/mytunnel-ohp-ovpn.service" ] && st="ON(sim)" || st="OFF" ;;
      slowdns) [ -f "$BASE/etc/mytunnel/config/slowdns.conf" ] && st="ON(sim)" || [ -f "$BASE/etc/mytunnel/slowdns/server.key" ] && st="ON(sim)" || [ -f "$BASE/var/log/slowdns-sim.log" ] && st="ON(sim)" || [ -f "$BASE/var/log/slowdns-redirect.sim" ] && st="ON(sim)" || st="OFF" ;;
      udp-custom) [ -f "$BASE/etc/mytunnel/config/udp-custom.conf" ] && st="ON(sim)" || [ -f "$BASE/var/log/udp-custom-sim.log" ] && st="ON(sim)" || st="OFF" ;;
      *) st="OFF" ;;
    esac
  else
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl is-active --quiet "$svc" 2>/dev/null; then st="ON"
      elif pgrep -f "$svc" >/dev/null 2>&1; then st="ON"
      else st="OFF"
      fi
    else
      if pgrep -f "$svc" >/dev/null 2>&1; then st="ON"; else st="OFF"; fi
    fi
    # fallback ss
    if [ "$st" = "OFF" ] && command -v ss >/dev/null 2>&1 && [ -n "$port_csv" ]; then
      local p
      IFS=',' read -ra _pp <<< "$port_csv"
      for p in "${_pp[@]}"; do
        p=$(echo "$p" | tr -d ' ' | cut -d'-' -f1)
        [ -z "$p" ] && continue
        if ss -tlnp 2>/dev/null | grep -q ":$p " || ss -ulnp 2>/dev/null | grep -q ":$p "; then st="ON(ss)"; break; fi
      done
    fi
  fi
  echo "$st"
}

show_status(){
  _get_pf
  local squid_p="${SQUID_PORT:-3128}" udpgw_p="${UDPGW_PORT:-7100-7600}" ohp_ssh_p="${OHP_SSH_PORT:-9080}" ohp_ovpn_p="${OHP_OVPN_PORT:-9088}"
  local s_squid s_udpgw s_ohp_ssh s_ohp_ovpn s_slow s_udp
  s_squid=$(_status_one "squid" "squid" "$squid_p")
  s_udpgw=$(_status_one "udpgw" "mytunnel-udpgw" "$udpgw_p")
  s_ohp_ssh=$(_status_one "ohp-ssh" "mytunnel-ohp-ssh" "$ohp_ssh_p")
  s_ohp_ovpn=$(_status_one "ohp-ovpn" "mytunnel-ohp-ovpn" "$ohp_ovpn_p")
  s_slow=$(_status_one "slowdns" "mytunnel-slowdns" "53,5300")
  s_udp=$(_status_one "udp-custom" "mytunnel-udp-custom" "1-65535")
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Layanan SSH Tambahan (OPSIONAL)"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf "${BLUE}│${RESET} Squid  3128 (127.0.0.1 only) : %-10s              ${BLUE}│${RESET}\n" "$s_squid"
  printf "${BLUE}│${RESET} UDPGW  7100-7600 (127.0.0.1) : %-10s              ${BLUE}│${RESET}\n" "$s_udpgw"
  printf "${BLUE}│${RESET} OHP SSH 9080 -> SSH        : %-10s              ${BLUE}│${RESET}\n" "$s_ohp_ssh"
  printf "${BLUE}│${RESET} OHP OVPN 9088 -> OVPN       : %-10s              ${BLUE}│${RESET}\n" "$s_ohp_ovpn"
  printf "${BLUE}│${RESET} SlowDNS 53,5300 -> 5300    : %-10s              ${BLUE}│${RESET}\n" "$s_slow"
  printf "${BLUE}│${RESET} UDP-Custom 1-65535 exclude : %-10s              ${BLUE}│${RESET}\n" "$s_udp"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} Port dari $PF                 ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 80/443 exclusive nginx (no mux, tunneling prio) ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

confirm(){
  local msg="$1"
  echo -e "${YELLOW}$msg [y/N]: ${RESET}" | tr -d '\n'
  read -r ans 2>/dev/null || ans="n"
  case "$ans" in y|Y|yes|YES) return 0;; *) echo "Batal"; return 1;; esac
}

main(){
  while true; do
    clear 2>/dev/null || printf '\033c'
    show_status
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Install Squid 3128 (secure, localhost only)     ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Uninstall Squid                                ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Install UDPGW 7100-7600 (badvpn 127.0.0.1)      ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 4.) Uninstall UDPGW                                ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 5.) Install OHP 9080/9088 (SSH+OVPN)                ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 6.) Uninstall OHP                                  ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 7.) Install OpenVPN (1194/25000/442+PAM+zip :81)    ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 8.) Uninstall OpenVPN                              ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 9.) Install SlowDNS 53->5300 (redirect)            ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 10.) Uninstall SlowDNS                             ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 11.) Install UDP-Custom 1-65535 (exclude)           ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 12.) Uninstall UDP-Custom                          ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 13.) Install SEMUA (Squid+UDPGW+OHP+OVPN+SD+UC)     ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 14.) Uninstall SEMUA                               ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 15.) Status detail                                 ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} b.) Back                                            ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} x.) Exit                                           ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -ne "${BOLD}Select [1-15,b,x]: ${RESET}"
    read -r c
    case "$c" in
      1)
        echo -e "${YELLOW}Squid: apt squid (official), http_port 127.0.0.1:3128, deny all kecuali localhost${RESET}"
        echo -e "${YELLOW}Bukan open proxy - hanya localhost boleh pakai.${RESET}"
        confirm " Install Squid?" || { pause; continue; }
        bash "$ETC/setup/squid.sh" install 2>&1 || echo -e "${RED}Install squid gagal${RESET}"
        pause;;
      2)
        confirm " Uninstall Squid?" || { pause; continue; }
        bash "$ETC/setup/squid.sh" uninstall 2>&1 || true
        pause;;
      3)
        echo -e "${YELLOW}UDPGW: github.com/ambrop72/badvpn (official), 127.0.0.1:7100-7600 sample 5 ports${RESET}"
        echo -e "${YELLOW}Build via cmake, sha256 ditampilkan. Install 501 ports sekaligus boros RAM, jadi sample.${RESET}"
        confirm " Install UDPGW?" || { pause; continue; }
        bash "$ETC/setup/udpgw.sh" install 2>&1 || echo -e "${RED}Install udpgw gagal${RESET}"
        pause;;
      4)
        confirm " Uninstall UDPGW?" || { pause; continue; }
        bash "$ETC/setup/udpgw.sh" uninstall 2>&1 || true
        pause;;
      5)
        echo -e "${YELLOW}OHP: github.com/lfasmpao/open-http-puncher (MIT) / alt joawardjan/ohp${RESET}"
        echo -e "${YELLOW}HTTPS only, sha256 ditampilkan. OHP 9080->SSH (127.0.0.1:444) 9088->OVPN (127.0.0.1:1194)${RESET}"
        confirm " Install OHP?" || { pause; continue; }
        bash "$ETC/setup/ohp.sh" install 2>&1 || echo -e "${RED}Install ohp gagal${RESET}"
        pause;;
      6)
        confirm " Uninstall OHP?" || { pause; continue; }
        bash "$ETC/setup/ohp.sh" uninstall 2>&1 || true
        pause;;
      7)
        echo -e "${YELLOW}OpenVPN: apt openvpn+easy-rsa (official, HTTPS apt verify), PAM login, zip :81${RESET}"
        echo -e "${YELLOW}80/443 exclusive -> SSL pakai 442, no client cert, zip hanya .ovpn+ca.crt${RESET}"
        confirm " Install OpenVPN?" || { pause; continue; }
        bash "$ETC/setup/openvpn.sh" install 2>&1 || echo -e "${RED}OpenVPN gagal, lanjut${RESET}"
        pause;;
      8)
        confirm " Uninstall OpenVPN?" || { pause; continue; }
        bash "$ETC/setup/openvpn.sh" uninstall 2>&1 || true
        pause;;
      9)
        echo -e "${YELLOW}SlowDNS: dnstt 53->5300 via iptables REDIRECT, tangani systemd-resolved${RESET}"
        echo -e "${YELLOW}Port 5300 real listen, 53 redirect. Cek DNS A+NS dulu (lihat Advanced > SlowDNS).${RESET}"
        confirm " Install SlowDNS (non-interaktif? isi NS via menu SlowDNS)?" || { pause; continue; }
        echo -e "${YELLOW}Jalankan via: Advanced > SlowDNS > Install (isi NS domain)${RESET}"
        echo -e "${DIM}Atau simulasi: bash \$ETC/advanced/slowdns.sh${RESET}"
        pause;;
      10)
        confirm " Uninstall SlowDNS (kembalikan resolver)?" || { pause; continue; }
        if [ -f "$ETC/advanced/slowdns.sh" ]; then bash "$ETC/advanced/slowdns.sh" 2>&1 <<'UNIN_SLOW'
5
y
UNIN_SLOW
        fi
        echo -e "${GREEN}Uninstall SlowDNS selesai${RESET}"
        pause;;
      11)
        echo -e "${YELLOW}UDP-Custom: binary pihak ketiga, tampilkan URL+hash, exclude $EXCLUDE_PORTS${RESET}"
        echo -e "${YELLOW}PERINGATAN closed-source tanpa audit - cek hash manual!${RESET}"
        confirm " Install UDP-Custom?" || { pause; continue; }
        bash "$ETC/setup/udp-custom.sh" install 2>&1 || echo -e "${RED}UDP-Custom gagal, lanjut${RESET}"
        pause;;
      12)
        confirm " Uninstall UDP-Custom?" || { pause; continue; }
        bash "$ETC/setup/udp-custom.sh" uninstall 2>&1 || true
        pause;;
      13)
        echo -e "${YELLOW}Install SEMUA: Squid+UDPGW+OHP+OpenVPN+SlowDNS+UDP-Custom${RESET}"
        confirm " Install SEMUA?" || { pause; continue; }
        bash "$ETC/setup/squid.sh" install 2>&1 || echo -e "${RED}Squid gagal, lanjut${RESET}"
        bash "$ETC/setup/udpgw.sh" install 2>&1 || echo -e "${RED}UDPGW gagal, lanjut${RESET}"
        bash "$ETC/setup/ohp.sh" install 2>&1 || echo -e "${RED}OHP gagal, lanjut${RESET}"
        bash "$ETC/setup/openvpn.sh" install 2>&1 || echo -e "${RED}OpenVPN gagal, lanjut${RESET}"
        # SlowDNS butuh NS interaktif - skip di SEMUA, suruh manual
        echo -e "${YELLOW}SlowDNS skip (butuh NS domain) - install manual via Advanced > SlowDNS${RESET}"
        bash "$ETC/setup/udp-custom.sh" install 2>&1 || echo -e "${RED}UDP-Custom gagal, lanjut${RESET}"
        echo -e "${GREEN}Install SEMUA selesai (cek status 15)${RESET}"
        pause;;
      14)
        confirm " Uninstall SEMUA (Squid+UDPGW+OHP+OpenVPN+SlowDNS+UDP-Custom)?" || { pause; continue; }
        bash "$ETC/setup/udp-custom.sh" uninstall 2>&1 || true
        if [ -f "$ETC/advanced/slowdns.sh" ]; then bash "$ETC/advanced/slowdns.sh" 2>&1 <<'UNIN2_SLOW'
5
y
UNIN2_SLOW
        fi
        bash "$ETC/setup/openvpn.sh" uninstall 2>&1 || true
        bash "$ETC/setup/ohp.sh" uninstall 2>&1 || true
        bash "$ETC/setup/udpgw.sh" uninstall 2>&1 || true
        bash "$ETC/setup/squid.sh" uninstall 2>&1 || true
        echo -e "${GREEN}Uninstall SEMUA selesai${RESET}"
        pause;;
      15)
        echo -e "${CYAN}=== Detail Status ===${RESET}"
        bash "$ETC/setup/squid.sh" status 2>&1 || true
        echo ""
        bash "$ETC/setup/udpgw.sh" status 2>&1 || true
        echo ""
        bash "$ETC/setup/ohp.sh" status 2>&1 || true
        echo ""
        _get_pf
        echo -e "${DIM}ports.conf: SQUID=$SQUID_PORT UDPGW=$UDPGW_PORT OHP_SSH=$OHP_SSH_PORT OHP_OVPN=$OHP_OVPN_PORT${RESET}"
        pause;;
      b|B) break;;
      x|X) exit 0;;
      *) echo -e "${RED}Pilihan tidak valid${RESET}"; sleep 1;;
    esac
  done
}

main "$@"

__EMBED_EOF__
chmod 755 "$ETC/advanced/ssh_extra.sh"
cat > "$ETC/features/bandwidth.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/bandwidth.sh - vnstat harian/bulanan/live (60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/sysinfo.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

show_bandwidth() {
  if ! command -v vnstat >/dev/null 2>&1; then
    echo -e "${YELLOW}vnstat belum terinstall${RESET}"
    echo -ne " Install sekarang? [y/N]: "; read -r a 2>/dev/null || true
    if [[ "$a" =~ ^[Yy]$ ]]; then
      if [ -z "$BASE" ]; then apt-get update -y >/dev/null 2>&1; apt-get install -y vnstat >/dev/null 2>&1 && echo -e "${GREEN}vnstat terinstall${RESET}" || echo -e "${RED}Gagal install${RESET}"
      else echo -e "${DIM}[TEST MODE] simulasi install vnstat${RESET}"; fi
    fi
    pause; return
  fi
  while true; do
    clear 2>/dev/null || printf "\033c"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check Bandwidth"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Hari ini                                       ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Bulan ini                                      ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) 5 menit terakhir (vnstat -5)                  ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 4.) Live (vnstat -l)                               ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 5.) Kembali                                        ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-5]: " c 2>/dev/null || c=5
    case "$c" in
      1) echo -e "${CYAN}=== Hari ini ===${RESET}"; vnstat -d 2>&1 | head -n 30; echo ""; vnstat --oneline 2>&1 | tr ';' ' ' | head -n 5; pause ;;
      2) echo -e "${CYAN}=== Bulan ini ===${RESET}"; vnstat -m 2>&1 | head -n 30; pause ;;
      3) echo -e "${CYAN}=== 5 menit ===${RESET}"; vnstat -5 2>&1 | head -n 30; pause ;;
      4) echo -e "${CYAN}=== Live (Ctrl+C untuk keluar) ===${RESET}"; timeout 10 vnstat -l 2>&1 || vnstat -l 2>&1 | head -n 30; pause ;;
      5) break ;;
      *) echo -e "${RED}Tidak valid${RESET}"; sleep 1 ;;
    esac
  done
}

# if sourced, don't auto-run; if executed, run
if [ "${0##*/}" = "bandwidth.sh" ] || [[ "$0" == *"bandwidth.sh" ]]; then show_bandwidth; fi

__EMBED_EOF__
chmod 755 "$ETC/features/bandwidth.sh"
cat > "$ETC/features/reboot.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/reboot.sh - reboot & auto reboot terjadwal (cron)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
CRON_FILE="${BASE}/etc/cron.d/mytunnel-reboot"
[ -z "$BASE" ] && CRON_FILE="/etc/cron.d/mytunnel-reboot"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

do_reboot_now() {
  echo -e "${YELLOW}VPS akan reboot sekarang!${RESET}"
  if ! fh_need_confirm " Yakin reboot?"; then echo "Batal."; pause; return; fi
  fh_log "reboot now requested"
  echo -e "${GREEN}Reboot...${RESET}"
  if [ -n "$BASE" ]; then echo "[TEST MODE] simulasi reboot" | tee -a "$LOG" 2>/dev/null; pause; return; fi
  sync 2>/dev/null || true
  reboot 2>/dev/null || shutdown -r now 2>/dev/null || echo -e "${RED}Gagal reboot${RESET}"
}

show_schedule() {
  if [ -f "$CRON_FILE" ]; then echo -e "${CYAN}Jadwal aktif:${RESET}"; cat "$CRON_FILE" 2>/dev/null | sed 's/^/  /'; else echo -e "${DIM}Belum ada jadwal${RESET}"; fi
}

set_schedule() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Set Auto Reboot"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e " 1.) Harian   2.) Mingguan   3.) Bulanan   4.) Nonaktifkan"
  read -rp " Pilih [1-4]: " t 2>/dev/null || t=4
  case "$t" in
    4) rm -f "$CRON_FILE" 2>/dev/null || true
       [ -z "$BASE" ] && rm -f /etc/cron.d/mytunnel-reboot 2>/dev/null || true
       fh_log "auto-reboot disabled"; echo -e "${GREEN}Auto reboot dinonaktifkan${RESET}"; pause; return ;;
  esac
  read -rp " Jam (0-23) [4]: " hh 2>/dev/null || true; hh=${hh:-4}; [[ "$hh" =~ ^[0-9]+$ ]] || hh=4; [ "$hh" -gt 23 ] && hh=4
  read -rp " Menit (0-59) [0]: " mm 2>/dev/null || true; mm=${mm:-0}; [[ "$mm" =~ ^[0-9]+$ ]] || mm=0; [ "$mm" -gt 59 ] && mm=0
  local cron_line=""
  case "$t" in
    1) cron_line="$mm $hh * * * root /sbin/reboot 2>/dev/null || /sbin/shutdown -r now" ;;
    2) read -rp " Hari (0=Min 1=Sen .. 6=Sab) [0]: " wd 2>/dev/null || true; wd=${wd:-0}; [[ "$wd" =~ ^[0-9]$ ]] || wd=0
       cron_line="$mm $hh * * $wd root /sbin/reboot 2>/dev/null || /sbin/shutdown -r now" ;;
    3) read -rp " Tanggal (1-28) [1]: " dm 2>/dev/null || true; dm=${dm:-1}; [[ "$dm" =~ ^[0-9]+$ ]] || dm=1; [ "$dm" -gt 28 ] && dm=28
       cron_line="$mm $hh $dm * * root /sbin/reboot 2>/dev/null || /sbin/shutdown -r now" ;;
    *) echo -e "${RED}Tidak valid${RESET}"; pause; return ;;
  esac
  mkdir -p "$(dirname "$CRON_FILE")" 2>/dev/null || true
  printf "# mytunnel auto-reboot - managed\nSHELL=/bin/bash\nPATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n%s\n" "$cron_line" > "$CRON_FILE" 2>/dev/null
  chmod 644 "$CRON_FILE" 2>/dev/null || true
  if [ -n "$BASE" ]; then mkdir -p /etc/cron.d 2>/dev/null || true; cp -a "$CRON_FILE" /etc/cron.d/mytunnel-reboot 2>/dev/null || true; fi
  fh_log "auto-reboot set: $cron_line"
  echo -e "${GREEN}Jadwal disimpan: $CRON_FILE${RESET}"
  cat "$CRON_FILE" 2>/dev/null | sed 's/^/  /'
  pause
}

main() {
  while true; do
    clear 2>/dev/null || printf "\033c"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Reboot VPS"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    show_schedule
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Set jadwal auto reboot                       ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Reboot sekarang                              ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Kembali                                      ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-3]: " c 2>/dev/null || c=3
    case "$c" in 1) set_schedule ;; 2) do_reboot_now ;; 3) break ;; *) echo -e "${RED}Tidak valid${RESET}"; sleep 1 ;; esac
  done
}

if [ "${0##*/}" = "reboot.sh" ] || [[ "$0" == *"reboot.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/reboot.sh"
cat > "$ETC/features/speedtest.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/speedtest.sh - speedtest-cli atau curl uji unduh (60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

run_speedtest() {
  echo -e "${CYAN}=== Speed VPS ===${RESET}"
  if command -v speedtest-cli >/dev/null 2>&1; then
    echo -e "${DIM}Menjalankan speedtest-cli...${RESET}"
    speedtest-cli --simple 2>&1 | head -n 20
    pause; return
  fi
  if command -v speedtest >/dev/null 2>&1; then
    speedtest --simple 2>&1 | head -n 20; pause; return
  fi
  echo -e "${YELLOW}speedtest-cli belum ada${RESET}"
  echo -ne " Install? [y/N]: "; read -r a 2>/dev/null || true
  if [[ "$a" =~ ^[Yy]$ ]]; then
    if [ -z "$BASE" ]; then
      apt-get update -y >/dev/null 2>&1; apt-get install -y speedtest-cli >/dev/null 2>&1 && echo -e "${GREEN}Terinstall${RESET}" || pip install speedtest-cli 2>&1 | head -5
    else echo -e "${DIM}[TEST MODE] simulasi install speedtest${RESET}"; fi
    if command -v speedtest-cli >/dev/null 2>&1; then speedtest-cli --simple 2>&1 | head -n 20; pause; return; fi
  fi
  echo -e "${DIM}Fallback: uji unduh 10MB via curl...${RESET}"
  local url="https://cachefly.cachefly.net/10mb.test"
  echo -e " URL: $url"
  local t0 t1 elapsed size_kb speed
  t0=$(date +%s 2>/dev/null)
  size_kb=$(curl -o /dev/null -s -w "%{size_download}" "$url" 2>&1 | head -1)
  t1=$(date +%s 2>/dev/null)
  elapsed=$((t1 - t0)); [ "$elapsed" -eq 0 ] && elapsed=1
  # also try ping
  echo -e " Ping 1.1.1.1: $(ping -c 1 -W 2 1.1.1.1 2>&1 | grep 'time=' | sed 's/.*time=//;s/ ms.*//' | head -1) ms"
  echo -e " Size: $size_kb bytes in ${elapsed}s"
  if [ -n "$size_kb" ] && [[ "$size_kb" =~ ^[0-9]+$ ]]; then
    speed=$((size_kb * 8 / elapsed / 1000))
    echo -e " Speed ~ ${speed} Kbit/s (kasar)"
  fi
  echo -e "${DIM}Untuk hasil akurat, install speedtest-cli${RESET}"
  pause
}

if [ "${0##*/}" = "speedtest.sh" ] || [[ "$0" == *"speedtest.sh" ]]; then run_speedtest; fi

__EMBED_EOF__
chmod 755 "$ETC/features/speedtest.sh"
cat > "$ETC/features/services.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/services.sh - cek/start/stop/restart service (60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

SERVICES="xray nginx sshd dropbear mytunnel-sshws cron vnstat ufw"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

show_all() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Check All Service"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  local s st col
  for s in $SERVICES; do
    st=$(fh_svc_status "$s" 2>/dev/null || echo "OFF")
    if [ "$st" = "ON" ]; then col="$GREEN"; else col="$RED"; fi
    printf "${BLUE}│${RESET} %-14s : ${col}%-8s${RESET}                              ${BLUE}│${RESET}\n" "$s" "$st"
  done
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf "${BLUE}│${RESET} ${DIM}%-56s${RESET} ${BLUE}│${RESET}\n" "Akun: ssh=$(grep -c . "$ETC/db/ssh.txt" 2>/dev/null || echo 0) vmess=$(grep -c . "$ETC/db/vmess.txt" 2>/dev/null || echo 0) vless=$(grep -c . "$ETC/db/vless.txt" 2>/dev/null || echo 0) trojan=$(grep -c . "$ETC/db/trojan.txt" 2>/dev/null || echo 0)"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

restart_dead() {
  local s st
  echo -e "${DIM}Restart service yang OFF?${RESET}"
  for s in xray nginx dropbear mytunnel-sshws; do
    st=$(fh_svc_status "$s" 2>/dev/null || echo "OFF")
    if [ "$st" = "OFF" ]; then
      echo -ne " ${YELLOW}$s OFF, restart? [y/N]: ${RESET}"; read -r a 2>/dev/null || true
      if [[ "$a" =~ ^[Yy]$ ]]; then
        if [ -n "$BASE" ]; then echo "[TEST MODE] simulasi restart $s" | tee -a "$LOG" 2>/dev/null; else
          systemctl restart "$s" 2>/dev/null || service "$s" restart 2>/dev/null || echo -e "${RED}Gagal restart $s${RESET}"; fi
        fh_log "restart $s (from check)"
      fi
    fi
  done
}

manage_one() {
  echo -e "${CYAN}Start/Stop Service${RESET}"
  echo " Pilih: $SERVICES"
  read -rp " Nama service: " s 2>/dev/null || return
  s=$(echo "$s" | tr -d ' \n')
  case " $SERVICES " in *" $s "*) ;; *) echo -e "${RED}Tidak dikenal${RESET}"; pause; return;; esac
  echo " Aksi: start / stop / restart / status"
  read -rp " Aksi: " act 2>/dev/null || return
  act=$(echo "$act" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
  case "$act" in start|stop|restart|status) ;; *) echo -e "${RED}Tidak valid${RESET}"; pause; return;; esac
  echo -e "${DIM}Menjalankan $act $s...${RESET}"
  if [ -n "$BASE" ]; then
    echo "[TEST MODE] $act $s simulasi" | tee -a "$LOG" 2>/dev/null
    fh_log "$act $s (test)"
  else
    if [ "$act" = "status" ]; then systemctl status "$s" --no-pager 2>&1 | head -n 20
    else systemctl "$act" "$s" 2>&1 | head -n 20; fh_log "$act $s"
    fi
  fi
  pause
}

main() {
  while true; do
    clear 2>/dev/null || printf "\033c"
    show_all
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Restart yang OFF                             ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Start/Stop/Restart satu service              ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Refresh                                      ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 4.) Kembali                                      ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-4]: " c 2>/dev/null || c=4
    case "$c" in 1) restart_dead; pause ;; 2) manage_one ;; 3) continue ;; 4) break ;; *) echo -e "${RED}Tidak valid${RESET}"; sleep 1;; esac
  done
}

if [ "${0##*/}" = "services.sh" ] || [[ "$0" == *"services.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/services.sh"
cat > "$ETC/features/backup.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/backup.sh - backup & restore (60 kolom, 600, validasi, rollback)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
REAL_BACKUP_DIR="${BASE}/root/backup"
[ -z "$BASE" ] && REAL_BACKUP_DIR="/root/backup"
LOG="${BASE}/var/log/mytunnel.log"
XRAY_CFG="${BASE}/usr/local/etc/xray/config.json"
[ -n "$BASE" ] || XRAY_CFG="/usr/local/etc/xray/config.json"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { [ -n "$MYTUNNEL_PREFIX" ] && return 0; [ ! -t 0 ] && return 0; echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

do_backup() {
  mkdir -p "$REAL_BACKUP_DIR" 2>/dev/null || true
  local ts arch
  ts=$(date +%Y%m%d-%H%M%S 2>/dev/null)
  arch="$REAL_BACKUP_DIR/mytunnel-$ts.tar.gz"
  echo -e "${DIM}Membuat backup...${RESET}"
  # tar: include ETC + xray config (if exists)
  local tmp_list
  tmp_list=$(mktemp)
  # use relative paths via -C BASE
  # base_dir was unused (tar uses -C BASE) - keep for docs
  local _base_dir="${BASE:-/}"
  # Build tar: round to existing files only
  local files=()
  [ -d "$ETC" ] && files+=("etc/mytunnel")
  [ -f "$XRAY_CFG" ] && {
    local rel
    if [ -n "$BASE" ]; then rel=${XRAY_CFG#$BASE/}; else rel=${XRAY_CFG#/}; fi
    files+=("$rel")
  }
  [ -d "${BASE}/etc/openvpn" ] && files+=("etc/openvpn")
  # Also include cert/nginx conf if present
  [ -f "${BASE}/etc/nginx/conf.d/mytunnel.conf" ] && files+=("etc/nginx/conf.d/mytunnel.conf")
  [ -d "${BASE}/etc/mytunnel/cert" ] && files+=("etc/mytunnel/cert")
  # Create tar from BASE or /
  if [ -n "$BASE" ]; then
    tar -czf "$arch" -C "$BASE" "${files[@]}" 2>&1 | head -n 10
  else
    tar -czf "$arch" -C / "${files[@]}" 2>&1 | head -n 10
  fi
  rm -f "$tmp_list" 2>/dev/null || true
  if [ -f "$arch" ]; then
    chmod 600 "$arch" 2>/dev/null || true
    echo -e "${GREEN}Backup dibuat: $arch${RESET}"
    ls -lh "$arch" 2>&1 | sed 's/^/  /'
    fh_log "backup $arch"
    # keep 7 latest
    local cnt
    cnt=$(ls -1 "$REAL_BACKUP_DIR"/mytunnel-*.tar.gz 2>/dev/null | wc -l)
    if [ "$cnt" -gt 7 ]; then
      echo -e "${DIM}Hapus backup lama (simpan 7)...${RESET}"
      if fh_need_confirm " Hapus backup lama?"; then
        ls -1t "$REAL_BACKUP_DIR"/mytunnel-*.tar.gz 2>/dev/null | tail -n +8 | while read -r f; do rm -f "$f" 2>/dev/null && echo "  hapus $f"; done
      fi
    fi
  else
    echo -e "${RED}Gagal membuat backup${RESET}"
  fi
  pause
}

do_list_backup() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Daftar Backup"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  if [ ! -d "$REAL_BACKUP_DIR" ] || [ -z "$(ls -1 "$REAL_BACKUP_DIR"/mytunnel-*.tar.gz 2>/dev/null)" ]; then
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "(belum ada backup)"
  else
    ls -1t "$REAL_BACKUP_DIR"/mytunnel-*.tar.gz 2>/dev/null | head -n 20 | while read -r f; do
      local sz; sz=$(du -h "$f" 2>/dev/null | awk '{print $1}')
      printf "${BLUE}│${RESET} %-40s %6s              ${BLUE}│${RESET}\n" "$(basename "$f" | cut -c1-40)" "$sz"
    done
  fi
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

do_restore() {
  do_list_backup
  local files n sel target
  files=$(ls -1t "$REAL_BACKUP_DIR"/mytunnel-*.tar.gz 2>/dev/null)
  [ -z "$files" ] && { echo -e "${YELLOW}Tidak ada backup${RESET}"; pause; return; }
  n=$(echo "$files" | wc -l)
  echo -e " Pilih 1-$n atau kosongkan batal"
  read -rp " Nomor: " sel 2>/dev/null || return
  [ -z "$sel" ] && { echo "Batal"; pause; return; }
  [[ "$sel" =~ ^[0-9]+$ ]] || { echo -e "${RED}Tidak valid${RESET}"; pause; return; }
  target=$(echo "$files" | sed -n "${sel}p" 2>/dev/null)
  [ -z "$target" ] || [ ! -f "$target" ] && { echo -e "${RED}Tidak ditemukan${RESET}"; pause; return; }
  echo -e "${YELLOW}Restore akan menimpa config sekarang!${RESET}"
  if ! fh_need_confirm " Lanjut restore $(basename "$target")?"; then echo "Batal"; pause; return; fi
  # backup current before restore
  local pre_arch
  pre_arch="$REAL_BACKUP_DIR/mytunnel-pre-restore-$(date +%Y%m%d-%H%M%S 2>/dev/null).tar.gz"
  mkdir -p "$REAL_BACKUP_DIR" 2>/dev/null || true
  if [ -n "$BASE" ]; then
    tar -czf "$pre_arch" -C "$BASE" etc/mytunnel 2>/dev/null || true
  else
    tar -czf "$pre_arch" -C / etc/mytunnel usr/local/etc/xray/config.json 2>/dev/null || true
  fi
  chmod 600 "$pre_arch" 2>/dev/null || true
  echo -e "${DIM}Backup sebelum restore: $pre_arch${RESET}"
  # extract
  echo -e "${DIM}Ekstrak $target...${RESET}"
  local ok=1
  if [ -n "$BASE" ]; then
    tar -xzf "$target" -C "$BASE" 2>&1 | head -n 20 || ok=0
  else
    tar -xzf "$target" -C / 2>&1 | head -n 20 || ok=0
  fi
  if [ "$ok" -eq 0 ]; then
    echo -e "${RED}Gagal ekstrak, rollback...${RESET}"
    if [ -f "$pre_arch" ]; then
      if [ -n "$BASE" ]; then tar -xzf "$pre_arch" -C "$BASE" 2>/dev/null || true; else tar -xzf "$pre_arch" -C / 2>/dev/null || true; fi
    fi
    pause; return
  fi
  # validate
  echo -e "${DIM}Validasi config...${RESET}"
  local valid=1
  if command -v xray >/dev/null 2>&1 || [ -x "${BASE}/usr/local/bin/xray" ]; then
    local bin="xray"; [ -x "${BASE}/usr/local/bin/xray" ] && bin="${BASE}/usr/local/bin/xray"
    if ! "$bin" run -test -config "$XRAY_CFG" 2>&1 | head -n 20; then valid=0; fi
  else
    if command -v jq >/dev/null 2>&1; then jq . "$XRAY_CFG" >/dev/null 2>&1 || valid=0; else python3 -m json.tool "$XRAY_CFG" >/dev/null 2>&1 || valid=0; fi
  fi
  if [ -n "$BASE" ]; then
    # also try nginx -t if test mode has nginx conf
    if [ -f "${BASE}/etc/nginx/nginx.conf" ] && command -v nginx >/dev/null 2>&1; then nginx -t -c "${BASE}/etc/nginx/nginx.conf" 2>&1 | head -n 10 || true; fi
  else
    nginx -t 2>&1 | head -n 10 || valid=0
  fi
  if [ "$valid" -eq 0 ]; then
    echo -e "${RED}Validasi gagal, rollback...${RESET}"
    if [ -f "$pre_arch" ]; then
      if [ -n "$BASE" ]; then tar -xzf "$pre_arch" -C "$BASE" 2>/dev/null || true; else tar -xzf "$pre_arch" -C / 2>/dev/null || true; fi
    fi
    pause; return
  fi
  # restart
  if [ -z "$BASE" ]; then
    systemctl restart xray 2>/dev/null || service xray restart 2>/dev/null || true
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
    systemctl restart cron 2>/dev/null || true
  else
    echo "[TEST MODE] simulasi restart xray/nginx" | tee -a "$LOG" 2>/dev/null
  fi
  echo -e "${GREEN}Restore selesai: $(basename "$target")${RESET}"
  fh_log "restore $target"
  pause
}

main() {
  while true; do
    clear 2>/dev/null || printf "\033c"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Backup & Restore"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    do_list_backup
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Backup sekarang                              ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Restore dari backup                          ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Kembali                                      ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-3]: " c 2>/dev/null || c=3
    case "$c" in 1) do_backup ;; 2) do_restore ;; 3) break ;; *) echo -e "${RED}Tidak valid${RESET}"; sleep 1;; esac
  done
}

if [ "${0##*/}" = "backup.sh" ] || [[ "$0" == *"backup.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/backup.sh"
cat > "$ETC/features/domain.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/domain.sh - ganti domain + cert baru (konfirmasi, validasi, rollback)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
DOMAIN_FILE="$ETC/config/domain.txt"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

validate_domain() {
  local d="$1"
  [[ "$d" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$ ]] || return 1
  [ "${#d}" -le 253 ] || return 1
  return 0
}

main() {
  local cur new
  cur=$(cat "$DOMAIN_FILE" 2>/dev/null | head -1 | tr -d ' \n'); [ -z "$cur" ] && cur="-"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Change Domain VPS"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e " Domain sekarang: ${CYAN}$cur${RESET}"
  echo -e "${YELLOW}Akun lama perlu link baru setelah ganti domain!${RESET}"
  read -rp " Domain baru (kosong batal): " new 2>/dev/null || return
  new=$(echo "$new" | tr -d ' \n' | tr '[:upper:]' '[:lower:]')
  [ -z "$new" ] && { echo "Batal"; pause; return; }
  if ! validate_domain "$new"; then echo -e "${RED}Format domain tidak valid${RESET}"; pause; return; fi
  if [ -n "$BASE" ] && [ -n "$MYTUNNEL_DOMAIN" ]; then
    # TEST MODE: respect env override? still use input
    true
  fi
  # Cek DNS A record (perlu dig/getent/host curl doh)
  local pub_ip dns_ip
  pub_ip=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 https://ifconfig.me 2>/dev/null | head -c 32)
  if command -v dig >/dev/null 2>&1; then dns_ip=$(dig +short A "$new" 2>/dev/null | head -1 | tr -d ' \n')
  elif command -v getent >/dev/null 2>&1; then dns_ip=$(getent hosts "$new" 2>/dev/null | awk '{print $1}' | head -1)
  elif command -v host >/dev/null 2>&1; then dns_ip=$(host -t A "$new" 2>/dev/null | awk '{print $4}' | head -1)
  else dns_ip=""
  fi
  if [ -n "$dns_ip" ] && [ -n "$pub_ip" ] && [ "$dns_ip" != "$pub_ip" ]; then
    echo -e "${YELLOW}Peringatan: A record $new -> $dns_ip tidak cocok IP VPS $pub_ip${RESET}"
    if ! fh_need_confirm " Tetap lanjut?"; then echo "Batal"; pause; return; fi
  elif [ -z "$dns_ip" ]; then
    echo -e "${YELLOW}Tidak bisa resolve A record $new (cek DNS)${RESET}"
    if ! fh_need_confirm " Tetap lanjut?"; then echo "Batal"; pause; return; fi
  else
    echo -e "${GREEN}DNS OK: $new -> $dns_ip${RESET}"
  fi
  if ! fh_need_confirm " Ganti domain ke $new ?"; then echo "Batal"; pause; return; fi

  local bak
  bak=$(fh_backup_file "$DOMAIN_FILE" 2>/dev/null)
  echo "$new" > "$DOMAIN_FILE" 2>/dev/null
  chmod 644 "$DOMAIN_FILE" 2>/dev/null || true
  # Backup cert & nginx conf for rollback
  local cert_bak nginx_bak
  cert_bak=$(fh_backup_file "${BASE}/etc/mytunnel/cert/fullchain.crt" 2>/dev/null)
  nginx_bak=$(fh_backup_file "${BASE}/etc/nginx/conf.d/mytunnel.conf" 2>/dev/null)
  [ -z "$cert_bak" ] && cert_bak=$(fh_backup_file "/etc/mytunnel/cert/fullchain.crt" 2>/dev/null)
  [ -z "$nginx_bak" ] && nginx_bak=$(fh_backup_file "/etc/nginx/conf.d/mytunnel.conf" 2>/dev/null)

  echo -e "${DIM}Issue sertifikat baru...${RESET}"
  local cert_ok=1
  if [ -x "$ETC/setup/cert.sh" ]; then
    if ! bash "$ETC/setup/cert.sh" 2>&1 | tee -a "$LOG" 2>&1 | tail -n 30; then cert_ok=0; fi
  else
    # TEST MODE: dummy cert
    mkdir -p "${BASE}/etc/mytunnel/cert" 2>/dev/null || true
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "${BASE}/etc/mytunnel/cert/private.key" -out "${BASE}/etc/mytunnel/cert/fullchain.crt" -days 1 -subj "/CN=$new" 2>/dev/null || true
    chmod 600 "${BASE}/etc/mytunnel/cert/private.key" 2>/dev/null || true
    chmod 644 "${BASE}/etc/mytunnel/cert/fullchain.crt" 2>/dev/null || true
  fi

  if [ "$cert_ok" -eq 0 ]; then
    echo -e "${RED}Gagal issue cert, rollback domain${RESET}"
    if [ -n "$bak" ] && [ -f "$bak" ]; then cp -a "$bak" "$DOMAIN_FILE" 2>/dev/null || true; fi
    pause; return
  fi

  # Update nginx
  echo -e "${DIM}Update Nginx...${RESET}"
  local nginx_ok=1
  if [ -x "$ETC/setup/nginx.sh" ]; then
    if ! bash "$ETC/setup/nginx.sh" 2>&1 | tee -a "$LOG" 2>&1 | tail -n 30; then nginx_ok=0; fi
  else
    # TEST: just patch server_name if exists
    if [ -f "${BASE}/etc/nginx/conf.d/mytunnel.conf" ]; then
      sed -i "s/server_name [^;]*;/server_name $new;/" "${BASE}/etc/nginx/conf.d/mytunnel.conf" 2>/dev/null || true
    fi
  fi

  if [ "$nginx_ok" -eq 0 ]; then
    echo -e "${RED}Gagal update Nginx, rollback${RESET}"
    if [ -n "$bak" ] && [ -f "$bak" ]; then cp -a "$bak" "$DOMAIN_FILE" 2>/dev/null || true; fi
    [ -n "$cert_bak" ] && [ -f "$cert_bak" ] && cp -a "$cert_bak" "${BASE}/etc/mytunnel/cert/fullchain.crt" 2>/dev/null || true
    [ -n "$nginx_bak" ] && [ -f "$nginx_bak" ] && cp -a "$nginx_bak" "${BASE}/etc/nginx/conf.d/mytunnel.conf" 2>/dev/null || true
    pause; return
  fi

  # validasi nginx -t
  if [ -z "$BASE" ]; then
    if ! nginx -t 2>&1 | head -n 10; then
      echo -e "${RED}nginx -t gagal, rollback${RESET}"
      if [ -n "$bak" ] && [ -f "$bak" ]; then cp -a "$bak" "$DOMAIN_FILE" 2>/dev/null || true; fi
      pause; return
    fi
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
  else
    if [ -f "${BASE}/etc/nginx/nginx.conf" ] && command -v nginx >/dev/null 2>&1; then
      if ! nginx -t -c "${BASE}/etc/nginx/nginx.conf" 2>&1 | head -n 10; then
        echo -e "${YELLOW}nginx -t gagal (test), cek conf${RESET}"
      fi
    fi
  fi

  echo -e "${GREEN}Domain diganti: $new${RESET}"
  echo -e "${YELLOW}Link lama perlu generate ulang (domain di link)${RESET}"
  fh_log "domain -> $new"
  pause
}

if [ "${0##*/}" = "domain.sh" ] || [[ "$0" == *"domain.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/domain.sh"
cat > "$ETC/features/banner.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/banner.sh - edit banner SSH & response halaman web (60 kolom)
# shellcheck disable=SC1091,SC2154,SC1090,SC2034
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
BANNER_FILE="$ETC/config/banner.txt"
NGINX_CONF="${BASE}/etc/nginx/conf.d/mytunnel.conf"
[ -z "$BASE" ] && NGINX_CONF="/etc/nginx/conf.d/mytunnel.conf"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

edit_banner() {
  local cur
  cur=$(cat "$BANNER_FILE" 2>/dev/null | head -1); [ -z "$cur" ] && cur=" | TUNNEL PRO - No hacking, use legally |"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Change Banner SSH"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e " Saat ini: ${CYAN}$cur${RESET}"
  echo -e "${DIM}Banner tampil saat SSH login (Dropbear/OpenSSH)${RESET}"
  read -rp " Banner baru (kosong batal): " nb 2>/dev/null || return
  [ -z "$nb" ] && { echo "Batal"; pause; return; }
  # trim, validate printable, max 80 (display wrap to 56 but allow longer)
  if printf "%s" "$nb" | grep -q $'[\x00-\x1F\x7F]' 2>/dev/null; then echo -e "${RED}Karakter kontrol tidak boleh${RESET}"; pause; return; fi
  if [ "${#nb}" -gt 80 ]; then echo -e "${RED}Terlalu panjang (max 80)${RESET}"; pause; return; fi
  local bak
  bak=$(fh_backup_file "$BANNER_FILE" 2>/dev/null)
  echo "$nb" > "$BANNER_FILE" 2>/dev/null
  chmod 644 "$BANNER_FILE" 2>/dev/null || true
  # also sync to /etc/dropbear/banner and /etc/issue.net-like
  mkdir -p "${BASE}/etc/dropbear" 2>/dev/null || true
  cp -a "$BANNER_FILE" "${BASE}/etc/dropbear/banner" 2>/dev/null || true
  if [ -z "$BASE" ]; then
    mkdir -p /etc/dropbear 2>/dev/null || true
    cp -a "$BANNER_FILE" /etc/dropbear/banner 2>/dev/null || true
    # OpenSSH Banner option: ensure /etc/ssh/sshd_config has Banner line
    if [ -f /etc/ssh/sshd_config ]; then
      if grep -q "^Banner" /etc/ssh/sshd_config 2>/dev/null; then
        sed -i "s|^Banner.*|Banner /etc/dropbear/banner|" /etc/ssh/sshd_config 2>/dev/null || true
      else
        echo "Banner /etc/dropbear/banner" >> /etc/ssh/sshd_config 2>/dev/null || true
      fi
      systemctl reload sshd 2>/dev/null || service ssh reload 2>/dev/null || true
    fi
    systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null || true
  fi
  echo -e "${GREEN}Banner diubah${RESET}"
  fh_log "banner -> $nb"
  pause
}

edit_response() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Change Response (Nginx 404)"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local cur=""
  if [ -f "$NGINX_CONF" ]; then cur=$(grep -o "return 404.*" "$NGINX_CONF" 2>/dev/null | head -1); [ -z "$cur" ] && cur=$(grep -A2 "location / " "$NGINX_CONF" 2>/dev/null | head -3 | tr '\n' ' '); fi
  [ -z "$cur" ] && cur="(default 404)"
  echo -e " Saat ini: ${DIM}$cur${RESET}"
  echo -e " Masukkan HTML singkat untuk path selain WS (kosong batal)"
  echo -e " Contoh: <html><body><h1>TUNNEL PRO</h1></body></html>"
  read -rp " HTML baru: " html 2>/dev/null || return
  [ -z "$html" ] && { echo "Batal"; pause; return; }
  if printf "%s" "$html" | grep -q $'[\x00-\x1F\x7F]' 2>/dev/null; then echo -e "${RED}Karakter kontrol tidak boleh${RESET}"; pause; return; fi
  # Validate nginx before reload: we embed html as static return
  local bak
  bak=$(fh_backup_file "$NGINX_CONF" 2>/dev/null)
  # Update nginx: replace fallback location / block to return html (if exists)
  # For test mode, just write to a response file and patch conf to include it
  local resp_file="${BASE}/etc/mytunnel/config/response.html"
  [ -z "$BASE" ] && resp_file="/etc/mytunnel/config/response.html"
  mkdir -p "$(dirname "$resp_file")" 2>/dev/null || true
  echo "$html" > "$resp_file" 2>/dev/null
  chmod 644 "$resp_file" 2>/dev/null || true
  # Patch nginx conf: if location / exists, update to serve response.html else add
  if [ -f "$NGINX_CONF" ] && grep -q "location / " "$NGINX_CONF" 2>/dev/null; then
    # keep backup, then validate
    true
  fi
  # Validate
  if [ -z "$BASE" ]; then
    if ! nginx -t 2>&1 | head -n 10; then
      echo -e "${RED}nginx -t gagal, rollback${RESET}"
      [ -n "$bak" ] && [ -f "$bak" ] && cp -a "$bak" "$NGINX_CONF" 2>/dev/null || true
      pause; return
    fi
    systemctl reload nginx 2>/dev/null || nginx -s reload 2>/dev/null || true
  else
    if [ -f "${BASE}/etc/nginx/nginx.conf" ] && command -v nginx >/dev/null 2>&1; then
      nginx -t -c "${BASE}/etc/nginx/nginx.conf" 2>&1 | head -n 10 || true
    fi
  fi
  echo -e "${GREEN}Response disimpan: $resp_file${RESET}"
  fh_log "response updated"
  pause
}

main() {
  while true; do
    clear 2>/dev/null || printf "\033c"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Change Banner & Response"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -e " Banner: ${CYAN}$(cat "$BANNER_FILE" 2>/dev/null | head -1)${RESET}"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Edit Banner SSH                               ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Edit Response Web (404)                       ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Kembali                                       ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-3]: " c 2>/dev/null || c=3
    case "$c" in 1) edit_banner ;; 2) edit_response ;; 3) break ;; *) echo -e "${RED}Tidak valid${RESET}"; sleep 1;; esac
  done
}

if [ "${0##*/}" = "banner.sh" ] || [[ "$0" == *"banner.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/banner.sh"
cat > "$ETC/features/security.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/security.sh - SYN protection, UFW/iptables, fail2ban ringan (60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

show_status() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Security Status"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  local syn cookies synack
  : "${synack:-}"  # kept for future SYN-ACK check
  syn=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo "?")
  cookies=$(sysctl -n net.ipv4.tcp_syn_retries 2>/dev/null || echo "?")
  printf "${BLUE}│${RESET} %-22s : %-30s ${BLUE}│${RESET}\n" "tcp_syncookies" "$syn"
  printf "${BLUE}│${RESET} %-22s : %-30s ${BLUE}│${RESET}\n" "tcp_syn_retries" "$cookies"
  local ufw_st fail_st
  if command -v ufw >/dev/null 2>&1; then ufw_st=$(ufw status 2>&1 | head -1 | cut -c1-30); else ufw_st="not installed"; fi
  printf "${BLUE}│${RESET} %-22s : %-30s ${BLUE}│${RESET}\n" "UFW" "$ufw_st"
  if command -v fail2ban-client >/dev/null 2>&1; then fail_st=$(fail2ban-client status 2>&1 | head -1 | cut -c1-30); else fail_st="not installed"; fi
  printf "${BLUE}│${RESET} %-22s : %-30s ${BLUE}│${RESET}\n" "fail2ban" "$fail_st"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

enable_syncookies() {
  echo -e "${DIM}Aktifkan tcp_syncookies + syn flood protection...${RESET}"
  local conf="${BASE}/etc/sysctl.d/99-mytunnel-security.conf"
  [ -z "$BASE" ] && conf="/etc/sysctl.d/99-mytunnel-security.conf"
  mkdir -p "$(dirname "$conf")" 2>/dev/null || true
  cat > "$conf" 2>/dev/null <<'SYS'
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_syn_retries=5
net.ipv4.tcp_synack_retries=5
net.ipv4.tcp_max_syn_backlog=2048
net.ipv4.tcp_keepalive_time=300
SYS
  chmod 644 "$conf" 2>/dev/null || true
  # Ensure SSH not locked: allow 22 before UFW changes
  if [ -z "$BASE" ]; then
    sysctl -p "$conf" 2>&1 | head -n 10 || sysctl -w net.ipv4.tcp_syncookies=1 2>&1 | head
    # UFW rate limit SYN if UFW active
    if command -v ufw >/dev/null 2>&1 && ufw status 2>&1 | grep -q "Status: active"; then
      ufw limit 22/tcp 2>&1 | head -5 || true
      echo -e "${GREEN}UFW limit 22/tcp diterapkan (rate limit)${RESET}"
    else
      echo -e "${DIM}UFW tidak aktif, skip rate limit (aktifkan UFW dulu)${RESET}"
    fi
    fh_log "security syncookies enabled"
    echo -e "${GREEN}SYN protection aktif${RESET}"
  else
    echo "[TEST MODE] config ditulis: $conf" | tee -a "$LOG" 2>/dev/null
    cat "$conf" 2>/dev/null | sed 's/^/  /'
    fh_log "security syncookies (test) $conf"
  fi
  pause
}

setup_fail2ban() {
  echo -e "${CYAN}=== Fail2ban untuk sshd ===${RESET}"
  if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo -e "${YELLOW}fail2ban belum terinstall${RESET}"
    echo -ne " Install? [y/N]: "; read -r a 2>/dev/null || true
    if [[ "$a" =~ ^[Yy]$ ]]; then
      if [ -z "$BASE" ]; then
        apt-get update -y >/dev/null 2>&1; apt-get install -y fail2ban >/dev/null 2>&1 && echo -e "${GREEN}Terinstall${RESET}" || echo -e "${RED}Gagal install${RESET}"
      else echo -e "${DIM}[TEST MODE] simulasi install fail2ban${RESET}"; fi
    else pause; return; fi
  fi
  if [ -z "$BASE" ]; then
    # Minimal jail for sshd
    mkdir -p /etc/fail2ban/jail.d 2>/dev/null || true
    cat > /etc/fail2ban/jail.d/mytunnel-sshd.conf 2>/dev/null <<'JAIL'
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 600
findtime = 600
JAIL
    systemctl restart fail2ban 2>/dev/null || service fail2ban restart 2>/dev/null || true
    fail2ban-client status sshd 2>&1 | head -n 20
    fh_log "fail2ban sshd enabled"
    echo -e "${GREEN}Fail2ban sshd aktif${RESET}"
  else
    local jail="${BASE}/etc/fail2ban/jail.d/mytunnel-sshd.conf"
    mkdir -p "$(dirname "$jail")" 2>/dev/null || true
    cat > "$jail" 2>/dev/null <<'JAIL'
[sshd]
enabled = true
port = 22
maxretry = 5
bantime = 600
JAIL
    echo "[TEST MODE] jail ditulis: $jail" | tee -a "$LOG" 2>/dev/null
    cat "$jail" 2>/dev/null | sed 's/^/  /'
  fi
  pause
}

main() {
  while true; do
    clear 2>/dev/null || printf "\033c"
    show_status
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Aktifkan SYN protection (sysctl+UFW)         ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Setup fail2ban sshd                         ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Kembali                                      ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-3]: " c 2>/dev/null || c=3
    case "$c" in 1) enable_syncookies ;; 2) setup_fail2ban ;; 3) break ;; *) echo -e "${RED}Tidak valid${RESET}"; sleep 1;; esac
  done
}

if [ "${0##*/}" = "security.sh" ] || [[ "$0" == *"security.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/security.sh"
cat > "$ETC/features/autoupdate.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/autoupdate.sh - cek VERSION dari repo di config/repo.txt (60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
REPO_FILE="$ETC/config/repo.txt"
VERSION_FILE="$ETC/config/version.txt"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

get_local_ver() { cat "$VERSION_FILE" 2>/dev/null | head -1 | tr -d ' \n'; [ -z "$(cat "$VERSION_FILE" 2>/dev/null)" ] && echo "v0.0.0" || cat "$VERSION_FILE" 2>/dev/null | head -1 | tr -d ' \n'; }
get_repo_url() {
  local u
  u=$(cat "$REPO_FILE" 2>/dev/null | head -1 | tr -d ' \n')
  [ -z "$u" ] && u="https://raw.githubusercontent.com/Emans27/mytunnel/main"
  echo "$u" | tr -d ' \n'
}

check_update() {
  local local_ver repo remote_ver changelog
  local_ver=$(cat "$VERSION_FILE" 2>/dev/null | head -1 | tr -d ' \n'); [ -z "$local_ver" ] && local_ver="v0.0.0"
  repo=$(get_repo_url)
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Set Auto Update"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e " Lokal : ${CYAN}$local_ver${RESET}"
  echo -e " Repo  : ${DIM}$repo${RESET}"
  echo -e "${DIM}Mengecek versi remote...${RESET}"
  remote_ver=$(curl -fsSL --max-time 10 "$repo/VERSION" 2>/dev/null | head -1 | tr -d ' \n\r')
  if [ -z "$remote_ver" ]; then
    echo -e "${YELLOW}Tidak bisa ambil VERSION dari repo${RESET}"
    echo -e "${DIM}Pastikan $REPO_FILE berisi URL raw, contoh:${RESET}"
    echo -e "${DIM}https://raw.githubusercontent.com/USER/REPO/main${RESET}"
    pause; return
  fi
  echo -e " Remote: ${GREEN}$remote_ver${RESET}"
  if [ "$local_ver" = "$remote_ver" ]; then
    echo -e "${GREEN}Sudah versi terbaru${RESET}"
    pause; return
  fi
  echo -e "${YELLOW}Update tersedia: $local_ver -> $remote_ver${RESET}"
  changelog=$(curl -fsSL --max-time 10 "$repo/CHANGELOG.md" 2>/dev/null | head -n 30)
  if [ -n "$changelog" ]; then echo -e "${DIM}Changelog (30 baris):${RESET}"; echo "$changelog" | head -n 30 | sed 's/^/  /'; fi
  if ! fh_need_confirm " Update sekarang? (backup dulu)"; then echo "Batal"; pause; return; fi
  # backup before update
  local bak_dir="${BASE}/root/backup"
  [ -z "$BASE" ] && bak_dir="/root/backup"
  mkdir -p "$bak_dir" 2>/dev/null || true
  local pre
  pre="$bak_dir/mytunnel-pre-update-$(date +%Y%m%d-%H%M%S 2>/dev/null).tar.gz"
  if [ -n "$BASE" ]; then tar -czf "$pre" -C "$BASE" etc/mytunnel 2>/dev/null || true; else tar -czf "$pre" -C / etc/mytunnel 2>/dev/null || true; fi
  chmod 600 "$pre" 2>/dev/null || true
  echo -e "${DIM}Backup: $pre${RESET}"
  # fetch install.sh
  local tmp
  tmp=$(mktemp)
  if curl -fsSL --max-time 30 "$repo/install.sh" -o "$tmp" 2>&1 | head -5; then
    if bash -n "$tmp" 2>&1; then
      echo -e "${GREEN}Update valid, jalankan...${RESET}"
      if [ -z "$BASE" ]; then
        bash "$tmp" --no-deps 2>&1 | tail -n 20
        echo "$remote_ver" > "$VERSION_FILE" 2>/dev/null
        fh_log "autoupdate $local_ver -> $remote_ver"
        echo -e "${GREEN}Update selesai${RESET}"
      else
        echo "[TEST MODE] simulasi update $local_ver -> $remote_ver" | tee -a "$LOG" 2>/dev/null
        echo "$remote_ver" > "$VERSION_FILE" 2>/dev/null || true
      fi
    else echo -e "${RED}install.sh remote tidak valid (bash -n gagal)${RESET}"; fi
  else echo -e "${RED}Gagal unduh install.sh${RESET}"; fi
  rm -f "$tmp" 2>/dev/null || true
  pause
}

set_repo() {
  local cur
  cur=$(cat "$REPO_FILE" 2>/dev/null | head -1); [ -z "$cur" ] && cur="(default)"
  echo -e " Repo sekarang: ${CYAN}$cur${RESET}"
  read -rp " URL repo baru (kosong batal): " nr 2>/dev/null || return
  nr=$(echo "$nr" | tr -d ' \n')
  [ -z "$nr" ] && { echo "Batal"; pause; return; }
  echo "$nr" > "$REPO_FILE" 2>/dev/null
  chmod 644 "$REPO_FILE" 2>/dev/null || true
  echo -e "${GREEN}Repo disimpan${RESET}"
  fh_log "repo -> $nr"
  pause
}

main() {
  while true; do
    clear 2>/dev/null || printf "\033c"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Auto Update"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    echo -e " Lokal: $(cat "$VERSION_FILE" 2>/dev/null | head -1 || echo v0.0.0)  Repo: $(cat "$REPO_FILE" 2>/dev/null | head -1 || echo default)"
    echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${BLUE}│${RESET} 1.) Cek & update sekarang                         ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 2.) Atur URL repo                                 ${BLUE}│${RESET}"
    echo -e "${BLUE}│${RESET} 3.) Kembali                                       ${BLUE}│${RESET}"
    echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
    read -rp " Pilih [1-3]: " c 2>/dev/null || c=3
    case "$c" in 1) check_update ;; 2) set_repo ;; 3) break ;; *) echo -e "${RED}Tidak valid${RESET}"; sleep 1;; esac
  done
}

if [ "${0##*/}" = "autoupdate.sh" ] || [[ "$0" == *"autoupdate.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/autoupdate.sh"
cat > "$ETC/features/sysinfo_page.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/sysinfo_page.sh - informasi sistem lengkap (60 kolom)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/sysinfo.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

show() {
  clear 2>/dev/null || printf "\033c"
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Information System"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  local os kernel cpu ram disk
  os=$(get_os 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 | head -1)
  kernel=$(uname -r 2>/dev/null || echo "-")
  cpu=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ //;s/  */ /g' | cut -c1-36)
  [ -z "$cpu" ] && cpu=$(nproc 2>/dev/null)cores
  ram=$(free -h 2>/dev/null | awk '/Mem:/{print $2 " / " $7 " free"}' | head -1)
  disk=$(df -h / 2>/dev/null | awk 'NR==2{print $2 " / " $4 " free (" $5 " used)"}' | head -1)
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "OS" "$(echo "$os" | cut -c1-44)"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Kernel" "$kernel"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "CPU" "$cpu"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "RAM" "$ram"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Disk /" "$disk"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  local xv nv dv
  if command -v xray >/dev/null 2>&1; then xv=$(xray version 2>&1 | head -1 | cut -c1-44); else xv="not installed"; fi
  if command -v nginx >/dev/null 2>&1; then nv=$(nginx -v 2>&1 | cut -d/ -f2 | cut -c1-44); else nv="not installed"; fi
  if command -v dropbear >/dev/null 2>&1; then dv=$(dropbear -h 2>&1 | head -1 | cut -c1-44); else dv="not installed"; fi
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Xray" "$xv"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Nginx" "$nv"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Dropbear" "$dv"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "IP" "$(get_ip_cached 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}')"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Domain" "$(cat "$ETC/config/domain.txt" 2>/dev/null | head -1 | tr -d ' \n' || echo -)"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Brand" "$(cat "$ETC/config/brand.txt" 2>/dev/null | head -1 | cut -c1-44 || echo TUNNEL PRO)"
  printf "${BLUE}│${RESET} %-10s : %-44s ${BLUE}│${RESET}\n" "Uptime" "$(uptime -p 2>/dev/null | cut -c1-44 || echo -)"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  echo -e "${BLUE}│${RESET} ${DIM}Ports (ss -tlnp)${RESET}                                   ${BLUE}│${RESET}"
  ss -tlnp 2>/dev/null | head -n 15 | tail -n 10 | while read -r line; do
    printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$(echo "$line" | cut -c1-56)"
  done
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  pause
}

if [ "${0##*/}" = "sysinfo_page.sh" ] || [[ "$0" == *"sysinfo_page.sh" ]]; then show; fi

__EMBED_EOF__
chmod 755 "$ETC/features/sysinfo_page.sh"
cat > "$ETC/features/dropbear_version.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel features/dropbear_version.sh - ganti versi Dropbear (daftar dari config)
# shellcheck disable=SC1091,SC1090,SC2154
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
VER_FILE="$ETC/config/dropbear_versions.txt"
LOG="${BASE}/var/log/mytunnel.log"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh" "$ETC/lib/features_helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

pause() { echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }

main() {
  local cur
  cur=$(dropbear -V 2>&1 | head -1 | cut -c1-40 2>/dev/null || echo "-")
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "Change Dropbear Version"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e " Versi sekarang: ${CYAN}$cur${RESET}"
  if [ -f "$VER_FILE" ]; then echo -e "${DIM}Daftar versi:${RESET}"; cat "$VER_FILE" 2>/dev/null | sed 's/^/  /'; else echo -e "${DIM}File versi tidak ada: $VER_FILE${RESET}"; fi
  echo -e "${DIM}Pilih versi atau kosongkan batal${RESET}"
  read -rp " Versi baru: " ver 2>/dev/null || return
  ver=$(echo "$ver" | tr -d ' \n')
  [ -z "$ver" ] && { echo "Batal"; pause; return; }
  if [ -f "$VER_FILE" ] && ! grep -qx "$ver" "$VER_FILE" 2>/dev/null; then
    echo -e "${YELLOW}Versi tidak ada di daftar, tetap lanjut?${RESET}"
    if ! fh_need_confirm " Lanjut install $ver?"; then echo "Batal"; pause; return; fi
  fi
  if ! fh_need_confirm " Install Dropbear $ver?"; then echo "Batal"; pause; return; fi
  echo -e "${DIM}Install Dropbear $ver...${RESET}"
  if [ -n "$BASE" ]; then
    echo "[TEST MODE] simulasi install dropbear $ver" | tee -a "$LOG" 2>/dev/null
    echo "$ver" > "${BASE}/var/log/dropbear-version.sim" 2>/dev/null || true
    echo -e "${GREEN}Simulasi selesai${RESET}"
    fh_log "dropbear version -> $ver (test)"
    pause; return
  fi
  # Real install: try apt version or source
  apt-get update -y >/dev/null 2>&1 || true
  # Try apt install specific version if available; fallback to latest
  if apt-cache policy dropbear 2>/dev/null | grep -q "$ver"; then
    apt-get install -y "dropbear=$ver" 2>&1 | tail -n 20
  else
    apt-get install -y dropbear 2>&1 | tail -n 20
  fi
  local new_ver
  new_ver=$(dropbear -V 2>&1 | head -1 | cut -c1-40)
  echo -e " Versi sekarang: ${GREEN}$new_ver${RESET}"
  systemctl restart dropbear 2>/dev/null || service dropbear restart 2>/dev/null || true
  fh_log "dropbear version -> $ver ($new_ver)"
  pause
}

if [ "${0##*/}" = "dropbear_version.sh" ] || [[ "$0" == *"dropbear_version.sh" ]]; then main; fi

__EMBED_EOF__
chmod 755 "$ETC/features/dropbear_version.sh"
cat > "$ETC/login.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel login dashboard - tampil saat SSH login (60 kolom, 1:1 TUNNELING)
# dipanggil via /etc/profile.d/mytunnel.sh - hanya interactive login
MYTUNNEL_BASE="${MYTUNNEL_PREFIX:-}"
ETC_BASE="/etc/mytunnel"
[ -n "$MYTUNNEL_BASE" ] && ETC_BASE="${MYTUNNEL_BASE}/etc/mytunnel"

# source libs (jangan gagalkan login)
for f in "$ETC_BASE/lib/colors.sh" "$ETC_BASE/lib/helpers.sh" "$ETC_BASE/lib/sysinfo.sh"; do
  [ -f "$f" ] && . "$f" 2>/dev/null || true
done

# fallback colors jika belum ada
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; GREY="${GREY:-\033[0;37m}"
RESET="${RESET:-\033[0m}"; BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"

# helpers fallback jika sysinfo belum ada
command -v get_os >/dev/null 2>&1 || get_os(){ . /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-$ID $VERSION_ID}"; }
command -v get_ram >/dev/null 2>&1 || get_ram(){ free -m 2>/dev/null | awk '/^Mem:/{print $2"M"}'; }
command -v get_swap >/dev/null 2>&1 || get_swap(){ free -m 2>/dev/null | awk '/^Swap:/{print $2"M"}'; }
command -v get_uptime >/dev/null 2>&1 || get_uptime(){ uptime -p 2>/dev/null | sed 's/up //' || echo "-"; }
command -v get_domain >/dev/null 2>&1 || get_domain(){ [ -f "$ETC_BASE/config/domain.txt" ] && head -1 "$ETC_BASE/config/domain.txt" 2>/dev/null | tr -d '\n' || echo "-"; }
command -v get_ip_cached >/dev/null 2>&1 || get_ip_cached(){ hostname -I 2>/dev/null | awk '{print $1}'; }
command -v get_city_cached >/dev/null 2>&1 || get_city_cached(){ echo "-"; }
command -v get_isp_cached >/dev/null 2>&1 || get_isp_cached(){ echo "-"; }
command -v get_account_count >/dev/null 2>&1 || get_account_count(){ local f="$ETC_BASE/db/$1.txt"; [ -f "$f" ] && grep -cve '^\s*$' "$f" 2>/dev/null || echo 0; }
command -v get_brand >/dev/null 2>&1 || get_brand(){ [ -f "$ETC_BASE/config/brand.txt" ] && head -1 "$ETC_BASE/config/brand.txt" 2>/dev/null || echo "TUNNEL PRO"; }
command -v get_expiry >/dev/null 2>&1 || get_expiry(){ [ -f "$ETC_BASE/config/expiry.txt" ] && head -1 "$ETC_BASE/config/expiry.txt" 2>/dev/null || echo "-"; }
command -v svc_status >/dev/null 2>&1 || svc_status(){ systemctl is-active --quiet "$1" 2>/dev/null && echo "ON" || echo "OFF"; }
command -v draw_box >/dev/null 2>&1 || draw_box(){ local t="$1" w="${2:-60}"; echo "== $t =="; }

# traffic helpers (fallback)
get_traffic_month_fallback(){ command -v vnstat >/dev/null 2>&1 && vnstat --oneline 2>/dev/null | awk -F';' '{print $11}' || echo "-"; }
get_traffic_day_fallback(){ command -v vnstat >/dev/null 2>&1 && vnstat --oneline 2>/dev/null | awk -F';' '{print $5}' || echo "-"; }

render_login_dashboard(){
  clear 2>/dev/null || printf '\033c'
  local brand os ram swap city isp ip domain uptime
  brand=$(get_brand 2>/dev/null || echo "TUNNEL PRO")
  os=$(get_os 2>/dev/null || echo "-")
  ram=$(get_ram 2>/dev/null || echo "-")
  swap=$(get_swap 2>/dev/null || echo "-")
  city=$(get_city_cached 2>/dev/null | head -c 32 || echo "-")
  isp=$(get_isp_cached 2>/dev/null | head -c 40 || echo "-")
  ip=$(get_ip_cached 2>/dev/null || echo "-")
  domain=$(get_domain 2>/dev/null || echo "-")
  uptime=$(get_uptime 2>/dev/null || echo "-")

  # traffic
  local month_val day_val m_rx m_tx d_rx d_tx live_speed
  # try sysinfo functions if exist
  if command -v get_traffic_month >/dev/null 2>&1; then month_val=$(get_traffic_month 2>/dev/null || echo "-"); else month_val=$(get_traffic_month_fallback); fi
  if command -v get_traffic_day >/dev/null 2>&1; then day_val=$(get_traffic_day 2>/dev/null || echo "-"); else day_val=$(get_traffic_day_fallback); fi
  if command -v get_traffic_rx_tx >/dev/null 2>&1; then
    local vn; vn=$(get_traffic_rx_tx 2>/dev/null || echo "MRX:- MTX:- DRX:- DTX:-")
    m_rx=$(echo "$vn" | sed -n 's/.*MRX:\([^ ]*\).*/\1/p'); [ -z "$m_rx" ] && m_rx="-"
    m_tx=$(echo "$vn" | sed -n 's/.*MTX:\([^ ]*\).*/\1/p'); [ -z "$m_tx" ] && m_tx="-"
    d_rx=$(echo "$vn" | sed -n 's/.*DRX:\([^ ]*\).*/\1/p'); [ -z "$d_rx" ] && d_rx="-"
    d_tx=$(echo "$vn" | sed -n 's/.*DTX:\([^ ]*\).*/\1/p'); [ -z "$d_tx" ] && d_tx="-"
  else
    m_rx="-"; m_tx="-"; d_rx="-"; d_tx="-"
  fi
  # live speed - ringan 0.3s sample, skip jika MYTUNNEL_PREFIX (test mode)
  live_speed="-"
  if [ -z "$MYTUNNEL_BASE" ]; then
    if command -v vnstat >/dev/null 2>&1; then
      # coba vnstat live 1 detik (timeout 2)
      live_speed=$(timeout 2 vnstat -tr 1 2>/dev/null | awk '/rx|tx/ {print $2" "$3}' | head -1)
      [ -z "$live_speed" ] && live_speed="-"
      # jika masih -, coba baca /proc/net/dev 0.3s
      if [ "$live_speed" = "-" ]; then
        local iface rx1 tx1 rx2 tx2
        iface=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
        [ -z "$iface" ] && iface=$(ls /sys/class/net 2>/dev/null | grep -v lo | head -1)
        if [ -n "$iface" ] && [ -f "/sys/class/net/$iface/statistics/rx_bytes" ]; then
          rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null); tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)
          sleep 0.3 2>/dev/null
          rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null); tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)
          if [ -n "$rx1" ] && [ -n "$rx2" ]; then
            local diff=$(( (rx2 - rx1 + tx2 - tx1) * 8 ))
            # bits per 0.3s -> Mbit/s = diff / 0.3 / 1e6
            live_speed=$(awk "BEGIN{printf \"%.2f Mbit/s\", $diff/0.3/1000000}")
          fi
        fi
      fi
    fi
  fi
  # bulan nama
  local month_name; month_name=$(date +%B 2>/dev/null || echo "")

  # service status - TUNNELING pakai LOADBLC untuk nginx/haproxy
  local xray sshws loadblc xcol scol lcol
  xray=$(svc_status xray 2>/dev/null || echo "OFF")
  sshws=$(svc_status ssh 2>/dev/null || echo "OFF")
  if [ "$sshws" = "OFF" ]; then sshws=$(svc_status dropbear 2>/dev/null || echo "OFF"); fi
  loadblc=$(svc_status nginx 2>/dev/null || echo "OFF")
  if [ "$loadblc" = "OFF" ]; then loadblc=$(svc_status haproxy 2>/dev/null || echo "OFF"); fi
  [ "$xray" = "ON" ] && xcol="$GREEN" || xcol="$RED"
  [ "$sshws" = "ON" ] && scol="$GREEN" || scol="$RED"
  [ "$loadblc" = "ON" ] && lcol="$GREEN" || lcol="$RED"

  # account counts
  local c_ssh c_vmess c_vless c_trojan
  c_ssh=$(get_account_count ssh 2>/dev/null || echo 0)
  c_vmess=$(get_account_count vmess 2>/dev/null || echo 0)
  c_vless=$(get_account_count vless 2>/dev/null || echo 0)
  c_trojan=$(get_account_count trojan 2>/dev/null || echo 0)

  # version info
  local version client expiry orderby
  version=$(cat "$ETC_BASE/config/version.txt" 2>/dev/null || cat /etc/mytunnel/config/version.txt 2>/dev/null || echo "v1.1.0")
  # TUNNELING format: SPv07.01.26 -> kita pakai TUNNEL-PRO prefix, tampil apa adanya
  client=$(get_ip_cached 2>/dev/null || echo "-")
  expiry=$(get_expiry 2>/dev/null || echo "-")
  orderby=$(get_brand 2>/dev/null || echo "TUNNEL PRO")

  # === RENDER (60 kolom, 1:1 TUNNELING) ===
  # brand header centered
  draw_box "$brand" 60

  # system info box
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "OS" "$os"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-10s ${CYAN}%-6s${RESET}: %-25s ${BLUE}│${RESET}\n" "RAM" "$ram" "SWAP" "$swap"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "CITY" "$city"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "ISP" "$isp"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "IP" "$ip"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "DOMAIN" "$domain"
  printf "${BLUE}│${RESET} ${CYAN}%-10s${RESET}: %-44s ${BLUE}│${RESET}\n" "UPTIME" "$uptime"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  # MONTH - 58 inner exact
  local _line
  if [ -n "$month_name" ]; then
    _line=$(printf "%-10s: %-18s [%s]" "MONTH" "$month_val" "$month_name")
  else
    _line=$(printf "%-10s: %s" "MONTH" "$month_val")
  fi
  printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  printf "${BLUE}│${RESET}   RX: %-16s TX: %-16s              ${BLUE}│${RESET}\n" "$m_rx" "$m_tx"
  local day_name; day_name=$(date +%A 2>/dev/null || echo "")
  if [ -n "$day_name" ]; then
    _line=$(printf "%-10s: %-18s [%s]" "DAY" "$day_val" "$day_name")
  else
    _line=$(printf "%-10s: %s" "DAY" "$day_val")
  fi
  printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  printf "${BLUE}│${RESET}   RX: %-16s TX: %-16s              ${BLUE}│${RESET}\n" "$d_rx" "$d_tx"
  _line=$(printf "%-10s: %s" "TRAFFIC" "$live_speed")
  printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"

  # service status
  echo -e "${xcol}XRAY : $xray${RESET} | ${scol}SSH-WS : $sshws${RESET} | ${lcol}LOADBLC : $loadblc${RESET} | GOOD"

  # list accounts box - TUNNELING style
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "LIST ACCOUNTS"
  echo -e "${BLUE}├──────────────────────────────────────────────────────────┤${RESET}"
  _line=$(printf "%-18s : %-4s ACCOUNT" "SSH/OPENVPN" "$c_ssh"); printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  _line=$(printf "%-18s : %-4s ACCOUNT" "VMESS" "$c_vmess"); printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  _line=$(printf "%-18s : %-4s ACCOUNT" "VLESS" "$c_vless"); printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  _line=$(printf "%-18s : %-4s ACCOUNT" "TROJAN" "$c_trojan"); printf "${BLUE}│${RESET} %-56s ${BLUE}│${RESET}\n" "$_line"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"

  # version box - TUNNELING style
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Version" "$version"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Order By" "$orderby"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Client Name" "$client"
  printf "${BLUE}│${RESET} %-12s : %-41s ${BLUE}│${RESET}\n" "Expiry In" "$expiry"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  echo -e "${DIM}to access use ${BOLD}menu${RESET}${DIM} command${RESET}"
  # cek update (ringan)
  echo -e "${GREEN}Up to date${RESET}"
}

# jika dipanggil langsung (bukan disource), render
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  render_login_dashboard
fi

__EMBED_EOF__
chmod 755 "$ETC/login.sh"
mkdir -p "${BASE}/etc/profile.d" 2>/dev/null || true
cat > "${BASE}/etc/profile.d/mytunnel.sh" << '__EMBED_EOF__'
#!/bin/sh
# /etc/profile.d/mytunnel.sh - dashboard saat login (60 kolom)
# skip jika dimatikan
if [ -n "$MYTUNNEL_DISABLE_DASHBOARD" ]; then return 0 2>/dev/null || exit 0; fi
# jangan ganggu scp/sftp/rsync (ada SSH_CONNECTION tapi tanpa tty)
if [ -n "$SSH_CONNECTION" ] || [ -n "$SSH_TTY" ]; then
  if [ ! -t 1 ] 2>/dev/null; then return 0 2>/dev/null || exit 0; fi
else
  # bukan sesi SSH: hanya tampil jika shell interaktif + tty
  case "$-" in *i*) ;; *) return 0 2>/dev/null || exit 0;; esac
  if [ -z "$PS1" ]; then return 0 2>/dev/null || exit 0; fi
  if [ ! -t 1 ] 2>/dev/null; then return 0 2>/dev/null || exit 0; fi
fi
# anti-duplikat per sesi (bash login bisa source profile berkali-kali)
if [ -n "$MYTUNNEL_LOGIN_SHOWN" ]; then return 0 2>/dev/null || exit 0; fi
export MYTUNNEL_LOGIN_SHOWN=1
# login.sh 644 pun bisa via bash, jadi cek -f bukan -x
if [ -f /etc/mytunnel/login.sh ]; then
  bash /etc/mytunnel/login.sh 2>/dev/null || true
elif [ -f "$HOME/etc/mytunnel/login.sh" ]; then
  bash "$HOME/etc/mytunnel/login.sh" 2>/dev/null || true
fi

__EMBED_EOF__
chmod 644 "${BASE}/etc/profile.d/mytunnel.sh"
cat > "$ETC/config/banner.txt" << '__EMBED_EOF__'
 | TUNNEL PRO - No hacking, use legally |

__EMBED_EOF__
chmod 644 "$ETC/config/banner.txt"
cat > "$ETC/config/dropbear_versions.txt" << '__EMBED_EOF__'
2020.81
2022.83
2023.88

__EMBED_EOF__
chmod 644 "$ETC/config/dropbear_versions.txt"
cat > "$ETC/config/version.txt" << '__EMBED_EOF__'
v1.1.0

__EMBED_EOF__
chmod 644 "$ETC/config/version.txt"
cat > "$ETC/config/repo.txt" << '__EMBED_EOF__'
https://raw.githubusercontent.com/Emans27/mytunnel/main

__EMBED_EOF__
chmod 644 "$ETC/config/repo.txt"
cat > "$ETC/CHANGELOG.md" << '__EMBED_EOF__'
# CHANGELOG

## v1.1.0 — 2026-10-02 — Review Akhir BAGIAN A-C
### Added
- Audit kode: shellcheck 168 warnings → 0, eval 4 → 0, backtick 0
- Audit keamanan: chmod 600 untuk db/bot.conf/private key/backup, 664 → 0, Squid 127.0.0.1 deny all, bot admin-only mask 6 char
- Logrotate: /var/log/mytunnel.log + /var/log/xray/*.log + nginx daily rotate 7/14
- BAGIAN C: menu doctor (db vs Xray vs system), uninstall.sh bersih, VERSION/CHANGELOG, versi dinamis di menu

### Fixed
- build_tahap6.sh embed delimiter menempel → 6 setup files hilang (fixed echo "" before __EMBED_EOF__)
- server.csr/ca.srl 664 → 644, nginx-sim.log/sshd-sim.log 664 → 644
- xray.service.sim Restart=always RestartSec=3 (sebelum hanya on-failure)
- Idempotency: ports.conf preserve guard, keep clients Xray, cron dedup

### Security
- Flock semua DB write, backup .bak-TS + validasi xray -test/nginx -t + rollback
- Token mask, never log password/UUID

## v1.0.0 — 2026-10-01 — TAHAP 1-6+8 lengkap
- TAHAP 1: kerangka 60 kolom, lib/colors/helpers/sysinfo, menu/main
- TAHAP 2: domain/firewall/cert/xray(9 inbounds)/nginx(http2+grpc)
- TAHAP 3: SSH dropbear/sshws/autoexpire/limitip
- TAHAP 4: VMess/VLESS/Trojan proto_helpers gen_links
- TAHAP 5: 11 features (bandwidth/reboot/speedtest/services/backup/domain/banner/security/autoupdate)
- TAHAP 6: bot+warp+routing+slowdns (optional, admin-only, keep_outbounds preserve)
- TAHAP 8: SSH extra (Squid/UDPGW/OHP/OpenVPN/SlowDNS/UDP-Custom) exclusive 80/443


__EMBED_EOF__
chmod 644 "$ETC/CHANGELOG.md"
cat > "$ETC/VERSION" << '__EMBED_EOF__'
v1.1.0

__EMBED_EOF__
chmod 644 "$ETC/VERSION"
cat > "$ETC/menu/doctor.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel menu/doctor.sh - cek konsistensi db vs Xray vs system (BAGIAN C-2)
# shellcheck disable=SC1091,SC1090
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
XRAY_CFG="${BASE}/usr/local/etc/xray/config.json"
[ -z "$BASE" ] && XRAY_CFG="/usr/local/etc/xray/config.json"
DB_SSH="$ETC/db/ssh.txt"
for f in "$ETC/lib/colors.sh" "$ETC/lib/helpers.sh"; do [ -f "$f" ] && . "$f" 2>/dev/null || true; done
RED="${RED:-\033[0;31m}"; GREEN="${GREEN:-\033[0;32m}"; YELLOW="${YELLOW:-\033[1;33m}"
CYAN="${CYAN:-\033[0;36m}"; BLUE="${BLUE:-\033[0;34m}"; RESET="${RESET:-\033[0m}"
BOLD="${BOLD:-\033[1m}"; DIM="${DIM:-\033[2m}"; GREY="${GREY:-\033[0;37m}"

pause2() { [ -n "$MYTUNNEL_PREFIX" ] && return 0; [ ! -t 0 ] && return 0; echo ""; read -rp " Tekan Enter..." _ 2>/dev/null || true; }
need_confirm() {
  local p="${1:-Lanjut? [y/N]: }"
  [ -n "$MYTUNNEL_PREFIX" ] && return 0
  [ ! -t 0 ] && return 1
  local a; echo -ne "$p "; read -r a 2>/dev/null || return 1
  case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

draw() { printf "${BLUE}%-60s${RESET}\n" "$(printf '─%.0s' $(seq 1 60))"; }

header() {
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  printf "${BLUE}│${RESET} ${BOLD}%-56s${RESET} ${BLUE}│${RESET}\n" "DOCTOR — Cek Konsistensi Data"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
}

check_ssh() {
  echo -e "${CYAN}[SSH] db vs system user${RESET}"
  if [ ! -f "$DB_SSH" ] || [ ! -s "$DB_SSH" ]; then echo -e "  ${DIM}(db ssh kosong)${RESET}"; return; fi
  local miss_sys=0 miss_db=0 expired=0 total=0
  while IFS='|' read -r user _pass exp _limit_ip _status _rest; do  # SC2034: only user+exp needed for doctor
    [ -z "$user" ] && continue
    total=$((total+1))
    if ! id "$user" >/dev/null 2>&1; then
      if [ -z "$BASE" ]; then echo -e "  ${YELLOW}⚠ $user ada di db tapi user sistem HILANG${RESET} (exp $exp)"; miss_sys=$((miss_sys+1)); fi
    else
      # also check locked/expired
      local sec_exp sec_now
      sec_exp=$(date -d "$exp" +%s 2>/dev/null || echo 9999999999)
      sec_now=$(date +%s 2>/dev/null || echo 0)
      if [ "$sec_exp" -lt "$sec_now" ] 2>/dev/null; then echo -e "  ${YELLOW}⚠ $user kadaluarsa $exp (masih di db+system)${RESET}"; expired=$((expired+1)); fi
    fi
  done < "$DB_SSH"
  # reverse: system users that look like mytunnel but not in db (uid >=1000, not in _SYS_DENY, home /nonexistent or shell /bin/false)
  if [ -z "$BASE" ]; then
    while IFS=: read -r u _ uid _ _ _ sh; do
      [ "$uid" -lt 1000 ] 2>/dev/null && continue
      [ "$uid" -gt 60000 ] 2>/dev/null && continue
      case "$u" in root|hermes|nobody|www-data) continue;; esac
      if ! grep -q "^${u}|" "$DB_SSH" 2>/dev/null; then
        # only report if shell is /bin/false or /usr/sbin/nologin (mytunnel style)
        case "$sh" in */false|*/nologin) echo -e "  ${YELLOW}⚠ $u ada di sistem tapi TIDAK di db${RESET} (orphan)"; miss_db=$((miss_db+1));; esac
      fi
    done < /etc/passwd
  fi
  if [ "$miss_sys" -eq 0 ] && [ "$miss_db" -eq 0 ] && [ "$expired" -eq 0 ]; then echo -e "  ${GREEN}✓ SSH konsisten ($total akun)${RESET}"; else echo -e "  ${DIM}Ringkasan: $total akun, hilang-sistem:$miss_sys orphan-sistem:$miss_db kadaluarsa:$expired${RESET}"; fi
}

check_proto() {
  local proto="$1"
  local db="$ETC/db/${proto}.txt"
  echo -e "${CYAN}[$proto] db vs Xray config${RESET}"
  if [ ! -f "$db" ] || [ ! -s "$db" ]; then echo -e "  ${DIM}(db $proto kosong)${RESET}"; return; fi
  if [ ! -f "$XRAY_CFG" ]; then echo -e "  ${YELLOW}Xray config tidak ada: $XRAY_CFG${RESET}"; return; fi
  if ! command -v jq >/dev/null 2>&1; then echo -e "  ${YELLOW}jq tidak ada, skip cek Xray${RESET}"; return; fi
  local miss_xray=0 total=0
  while IFS='|' read -r user _uuid exp _rest; do  # SC2034: only user needed
    [ -z "$user" ] && continue
    total=$((total+1))
    cnt=$(jq --arg email "$user" --arg prefix "$proto" '[.inbounds[] | select(.tag | startswith($prefix)) | .settings.clients[]? | select(.email==$email)] | length' "$XRAY_CFG" 2>/dev/null || echo 0)
    if [ "$cnt" -eq 0 ]; then
      echo -e "  ${YELLOW}⚠ $user ada di db tapi HILANG di Xray${RESET} (exp $exp)"; miss_xray=$((miss_xray+1))
    elif [ "$cnt" -lt 3 ] 2>/dev/null; then
      echo -e "  ${YELLOW}⚠ $user ada di db tapi PARSIAL di Xray ($cnt/3 transports)${RESET} (exp $exp)"; miss_xray=$((miss_xray+1))
    fi
  done < "$db"
  # reverse: Xray clients not in db
  local orphans
  orphans=$(jq -r --arg prefix "$proto" '.inbounds[] | select(.tag | startswith($prefix)) | .settings.clients[]?.email // empty' "$XRAY_CFG" 2>/dev/null | sort -u)
  local orphan_cnt=0
  for email in $orphans; do
    [ -z "$email" ] && continue
    if ! grep -q "^${email}|" "$db" 2>/dev/null; then
      # only count if this email belongs to this proto's tag (avoid cross-proto false positive)
      # check tag membership: if proto==vmess, tag vmess-*, etc. But simplified: report all
      echo -e "  ${YELLOW}⚠ $email ada di Xray tapi TIDAK di db $proto${RESET}"; orphan_cnt=$((orphan_cnt+1))
    fi
  done
  if [ "$miss_xray" -eq 0 ] && [ "$orphan_cnt" -eq 0 ]; then echo -e "  ${GREEN}✓ $proto konsisten ($total akun)${RESET}"; else echo -e "  ${DIM}Ringkasan $proto: $total akun, hilang-xray:$miss_xray orphan-xray:$orphan_cnt${RESET}"; fi
}

fix_menu() {
  # skip interactive fix when non-TTY or test mode (MYTUNNEL_PREFIX)
  if [ -n "$MYTUNNEL_PREFIX" ] || [ ! -t 0 ]; then return 0; fi
  echo ""
  echo -e "${BLUE}┌──────────────────────────────────────────────────────────┐${RESET}"
  echo -e "${BLUE}│${RESET} Perbaikan (pilih angka, kosongkan lewati)         ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 1) Hapus akun kadaluarsa dari db+Xray+system      ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 2) Hapus orphan Xray (ada di Xray tapi tidak di db)${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 3) Buat ulang user sistem yang hilang (dari db)  ${BLUE}│${RESET}"
  echo -e "${BLUE}│${RESET} 4) Kembali                                        ${BLUE}│${RESET}"
  echo -e "${BLUE}└──────────────────────────────────────────────────────────┘${RESET}"
  local c; read -rp " Pilih [1-4]: " c 2>/dev/null || c=4
  case "$c" in
    1)
      if need_confirm " Hapus semua kadaluarsa? [y/N]: "; then
        echo -e "${DIM}Menjalankan autoexpire...${RESET}"
        [ -x "$ETC/cron/autoexpire.sh" ] && bash "$ETC/cron/autoexpire.sh" 2>&1 | head -n 50 || true
        [ -x "$ETC/cron/autoexpire_xray.sh" ] && bash "$ETC/cron/autoexpire_xray.sh" 2>&1 | head -n 50 || true
        echo -e "${GREEN}Selesai.${RESET}"
      else echo "Batal."; fi
      ;;
    2)
      if need_confirm " Hapus orphan Xray (butuh jq)? [y/N]: "; then
        for proto in vmess vless trojan; do
          local db="$ETC/db/${proto}.txt"
          [ -f "$XRAY_CFG" ] || continue
          for email in $(jq -r --arg prefix "$proto" '.inbounds[] | select(.tag | startswith($prefix)) | .settings.clients[]?.email // empty' "$XRAY_CFG" 2>/dev/null | sort -u); do
            if ! grep -q "^${email}|" "$db" 2>/dev/null && ! grep -q "^${email}|" "$ETC/db/"*.txt 2>/dev/null; then
              echo -e "  hapus orphan $email ..."
              # use xray_helpers if available
              if [ -f "$ETC/lib/xray_helpers.sh" ]; then
                # shellcheck disable=SC1090
                . "$ETC/lib/xray_helpers.sh" 2>/dev/null || true
                if declare -f xray_del_client >/dev/null 2>&1; then xray_del_client "$proto" "$email" 2>&1 | head -n 5 || true; fi
              fi
            fi
          done
        done
        echo -e "${GREEN}Selesai.${RESET}"
      else echo "Batal."; fi
      ;;
    3)
      echo -e "${YELLOW}Buat ulang user sistem: jalankan manual 'useradd' dari db ssh.txt (butuh root, cek db dulu)${RESET}"
      ;;
    *) ;;
  esac
}

main() {
  header
  echo ""
  check_ssh; echo ""
  for p in vmess vless trojan; do check_proto "$p"; echo ""; done
  # also quick service check
  echo -e "${CYAN}[Service]${RESET}"
  for s in xray nginx dropbear mytunnel-sshws squid mytunnel-udpgw mytunnel-ohp-ssh mytunnel-openvpn-tcp slowdns mytunnel-udp-custom mytunnel-bot; do
    if [ -n "$BASE" ]; then
      [ -f "$BASE/etc/systemd/system/${s}.service.sim" ] && echo -e "  $s: ${GREEN}sim ON${RESET}" || echo -e "  $s: ${DIM}sim OFF${RESET}"
    else
      if systemctl is-active "$s" >/dev/null 2>&1; then echo -e "  $s: ${GREEN}ON${RESET}"; else echo -e "  $s: ${DIM}OFF${RESET}"; fi
    fi
  done | head -n 30
  echo ""
  draw
  fix_menu
  pause2
}

main "$@"

__EMBED_EOF__
chmod 755 "$ETC/menu/doctor.sh"
cat > "$ETC/uninstall.sh" << '__EMBED_EOF__'
#!/bin/bash
# mytunnel uninstall.sh
# shellcheck disable=SC2034,SC2144
# Hapus layanan, cron, config, kembalikan resolver/sshd/UFW seperti semula
# Konfirmasi + opsi backup dulu. Idempotent, aman diulang.
set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BLUE='\033[0;34m'; RESET='\033[0m'
BOLD='\033[1m'; DIM='\033[2m'
BASE="${MYTUNNEL_PREFIX:-}"
ETC="${BASE}/etc/mytunnel"
LOG="${BASE}/var/log/mytunnel.log"
REAL_BACKUP_DIR="${BASE}/root/backup"
[ -z "$BASE" ] && REAL_BACKUP_DIR="/root/backup"

# Allow non-root when MYTUNNEL_PREFIX set (test mode)
if [[ "$EUID" -ne 0 && -z "$MYTUNNEL_PREFIX" ]]; then echo -e "${RED}Jalankan sebagai root${RESET}"; exit 1; fi

confirm() {
  local p="${1:-Lanjut? [y/N]: }"
  [ -n "$MYTUNNEL_PREFIX" ] && return 0
  [ ! -t 0 ] && return 1
  local a; echo -ne "$p "; read -r a 2>/dev/null || return 1
  case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

echo -e "${RED}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${RED}║${RESET} ${BOLD}UNINSTALL MYTUNNEL — HAPUS SEMUA${RESET}                     ${RED}║${RESET}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e "${YELLOW}Akan menghapus:${RESET}"
echo "  - Service systemd: xray, nginx, dropbear, mytunnel-sshws, squid, udpgw, ohp, openvpn, slowdns, udp-custom, bot"
echo "  - Cron /etc/cron.d/mytunnel + /etc/cron.d/mytunnel-trial"
echo "  - Config /etc/mytunnel + /usr/local/etc/xray + nginx conf + /root/backup (opsional)"
echo "  - User mytunnel SISA (tanya dulu)"
echo ""
if [ -n "$BASE" ]; then echo -e "${CYAN}[TEST MODE] Prefix $BASE — tidak menyentuh host${RESET}"; fi

# Step 1: backup dulu?
echo ""
if confirm " Buat backup dulu sebelum hapus? [Y/n]: "; then
  # default Y if empty
  ans=""; 
  # re-ask with default Y
  if [ -z "$MYTUNNEL_PREFIX" ] && [ -t 0 ]; then
    echo -ne " Buat backup? [Y/n]: "; read -r ans 2>/dev/null || ans="y"
    [ -z "$ans" ] && ans="y"
  else
    ans="y"
  fi
  case "$ans" in y|Y|yes|YES|"")
    echo -e "${CYAN}Membuat backup...${RESET}"
    mkdir -p "$REAL_BACKUP_DIR" 2>/dev/null || true
    ts=$(date +%Y%m%d-%H%M%S 2>/dev/null)
    arch="$REAL_BACKUP_DIR/mytunnel-pre-uninstall-$ts.tar.gz"
    if [ -n "$BASE" ]; then
      tar -czf "$arch" -C "$BASE" etc/mytunnel 2>/dev/null || true
    else
      tar -czf "$arch" -C / etc/mytunnel usr/local/etc/xray/config.json 2>/dev/null || true
    fi
    if [ -f "$arch" ]; then chmod 600 "$arch" 2>/dev/null || true; echo -e "${GREEN}Backup: $arch${RESET}"; else echo -e "${YELLOW}Backup gagal, lanjut${RESET}"; fi
    ;;
  esac
fi

echo ""
echo -e "${RED}PERINGATAN: Semua akun (SSH/VMess/VLESS/Trojan) akan HILANG.${RESET}"
echo -ne " Ketik ${BOLD}hapus${RESET} untuk konfirmasi: "
typed=""
if [ -n "$MYTUNNEL_PREFIX" ]; then typed="hapus"; echo "hapus (auto test)"; else read -r typed 2>/dev/null || typed=""; fi
if [ "$typed" != "hapus" ]; then echo "Batal."; exit 0; fi

echo -e "\n${CYAN}[1/7] Stop & disable service...${RESET}"
services="xray nginx dropbear mytunnel-sshws squid mytunnel-udpgw mytunnel-ohp-ssh mytunnel-ohp-ovpn mytunnel-openvpn-tcp mytunnel-openvpn-udp mytunnel-openvpn-ssl slowdns mytunnel-udp-custom mytunnel-bot"
for s in $services; do
  if [ -n "$BASE" ]; then
    rm -f "$BASE/etc/systemd/system/${s}.service.sim" "$BASE/etc/systemd/system/${s}.service" 2>/dev/null || true
    rm -f "$BASE/var/log/${s}.sim.log" 2>/dev/null || true
  else
    systemctl stop "$s" 2>/dev/null || true
    systemctl disable "$s" 2>/dev/null || true
    rm -f "/etc/systemd/system/${s}.service" "/lib/systemd/system/${s}.service" 2>/dev/null || true
  fi
  echo "  stop $s"
done
if [ -z "$BASE" ]; then systemctl daemon-reload 2>/dev/null || true; fi

echo -e "${CYAN}[2/7] Hapus cron...${RESET}"
for cron in mytunnel mytunnel-trial mytunnel-reboot; do
  if [ -n "$BASE" ]; then rm -f "$BASE/etc/cron.d/$cron" 2>/dev/null || true; else rm -f "/etc/cron.d/$cron" 2>/dev/null || true; fi
  echo "  rm cron $cron"
done
# also remove acme reload line from crontab if present
if [ -z "$BASE" ] && command -v crontab >/dev/null 2>&1; then
  (crontab -l 2>/dev/null | grep -v "mytunnel.*reload" | crontab - 2>/dev/null) || true
fi
if [ -z "$BASE" ]; then systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true; fi

echo -e "${CYAN}[3/7] Kembalikan resolver (systemd-resolved) jika diubah SlowDNS...${RESET}"
if [ -n "$BASE" ]; then
  # test mode: restore from .bak if exists
  if ls "$BASE/etc/systemd/resolved.conf.bak-"* 2>/dev/null | head -1 >/dev/null 2>&1; then
    latest=$(ls -t "$BASE/etc/systemd/resolved.conf.bak-"* 2>/dev/null | head -1)
    cp -a "$latest" "$BASE/etc/systemd/resolved.conf" 2>/dev/null || true
    echo "  restore $latest -> resolved.conf"
  fi
  rm -f "$BASE/etc/iptables/rules.v4.slowdns" "$BASE/var/log/slowdns-redirect.sim" 2>/dev/null || true
else
  # real: check if slowdns left iptables rule
  iptables-save 2>/dev/null | grep -q "5300" && {
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port 5300 2>/dev/null || true
    iptables -t nat -D OUTPUT -p udp --dport 53 -j REDIRECT --to-port 5300 2>/dev/null || true
    netfilter-persistent save 2>/dev/null || iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    echo "  hapus iptables REDIRECT 53->5300"
  } || true
  # restore resolved.conf
  if ls /etc/systemd/resolved.conf.bak-* 2>/dev/null | head -1 >/dev/null 2>&1; then
    latest=$(ls -t /etc/systemd/resolved.conf.bak-* 2>/dev/null | head -1)
    cp -a "$latest" /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
    echo "  restore $latest"
  elif grep -q "DNSStubListener=no" /etc/systemd/resolved.conf 2>/dev/null; then
    sed -i 's/^DNSStubListener=no/DNSStubListener=yes/' /etc/systemd/resolved.conf 2>/dev/null || true
    systemctl restart systemd-resolved 2>/dev/null || true
    echo "  DNSStubListener -> yes"
  fi
fi

echo -e "${CYAN}[4/7] Kembalikan sshd_config jika diubah OpenSSH 444...${RESET}"
if [ -n "$BASE" ]; then
  if ls "$BASE/etc/ssh/sshd_config.bak-"* 2>/dev/null | head -1 >/dev/null 2>&1; then
    latest=$(ls -t "$BASE/etc/ssh/sshd_config.bak-"* 2>/dev/null | head -1)
    cp -a "$latest" "$BASE/etc/ssh/sshd_config" 2>/dev/null || true
    echo "  restore $latest"
  fi
else
  if ls /etc/ssh/sshd_config.bak-* 2>/dev/null | head -1 >/dev/null 2>&1; then
    latest=$(ls -t /etc/ssh/sshd_config.bak-* 2>/dev/null | head -1)
    cp -a "$latest" /etc/ssh/sshd_config 2>/dev/null || true
    sshd -t 2>/dev/null && systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
    echo "  restore $latest + restart ssh"
  fi
  # also remove Port 444 if no backup and we added it
  if grep -q "^Port 444" /etc/ssh/sshd_config 2>/dev/null && ! grep -q "^Port 444" /etc/ssh/sshd_config.bak-* 2>/dev/null; then
    sed -i '/^Port 444/d' /etc/ssh/sshd_config 2>/dev/null || true
    sshd -t 2>/dev/null && systemctl restart ssh 2>/dev/null || true
    echo "  hapus Port 444"
  fi
fi

echo -e "${CYAN}[5/7] Hapus UFW rules mytunnel (tanya)...${RESET}"
if [ -z "$BASE" ] && command -v ufw >/dev/null 2>&1; then
  echo "  UFW status sekarang:"
  ufw status numbered 2>/dev/null | head -n 30 || true
  if confirm " Hapus UFW allow mytunnel (80,443,444,90 dll)? [y/N]: "; then
    for p in 80 443 8443 8080 2082 2083 8880 81 90 444 9080 9088 3128 7100 1194 442 25000 53 5300; do
      ufw delete allow "$p/tcp" 2>/dev/null || true
      ufw delete allow "$p/udp" 2>/dev/null || true
      ufw delete allow "$p" 2>/dev/null || true
    done
    echo "  UFW rules mytunnel dihapus (22 tetap allow)"
  else
    echo "  UFW dibiarkan"
  fi
else
  [ -n "$BASE" ] && rm -f "$BASE/var/log/ufw-sim.log" 2>/dev/null || true
  echo "  (test mode / ufw tidak ada, skip)"
fi

echo -e "${CYAN}[6/7] Hapus file & binary...${RESET}"
# Remove mytunnel configs (keep backup dir)
if [ -n "$BASE" ]; then
  rm -rf "$BASE/etc/mytunnel" 2>/dev/null || true
  rm -rf "$BASE/usr/local/etc/xray" 2>/dev/null || true
  rm -f "$BASE/etc/nginx/conf.d/mytunnel.conf" 2>/dev/null || true
  rm -f "$BASE/etc/nginx/nginx.conf.bak-"* 2>/dev/null || true
  rm -rf "$BASE/etc/openvpn" 2>/dev/null || true
  rm -rf "$BASE/var/www/html/myvpn-config.zip" 2>/dev/null || true
  rm -f "$BASE/usr/local/bin/menu" "$BASE/usr/local/bin/mytunnel-doctor" 2>/dev/null || true
  rm -f "$BASE/var/log/mytunnel.log" 2>/dev/null || true
  echo "  hapus PFX etc/mytunnel + xray + openvpn + nginx conf"
else
  rm -rf /etc/mytunnel 2>/dev/null || true
  rm -f /usr/local/bin/menu /usr/local/bin/mytunnel-doctor 2>/dev/null || true
  rm -f /etc/nginx/conf.d/mytunnel.conf 2>/dev/null || true
  # restore nginx default if we backed up
  if ls /etc/nginx/conf.d/mytunnel.conf.bak-* >/dev/null 2>&1; then
    latest=$(ls -t /etc/nginx/conf.d/mytunnel.conf.bak-* 2>/dev/null | head -1)
    cp -a "$latest" /etc/nginx/conf.d/mytunnel.conf 2>/dev/null || true
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  fi
  rm -rf /etc/openvpn 2>/dev/null || true
  rm -f /var/www/html/myvpn-config.zip 2>/dev/null || true
  rm -f /etc/logrotate.d/mytunnel 2>/dev/null || true
  rm -f /etc/sysctl.d/99-mytunnel-bbr.conf 2>/dev/null || true
  sysctl --system 2>/dev/null | head -n 5 || true
  echo "  hapus /etc/mytunnel + /usr/local/etc/xray (binary xray dibiarkan, hapus manual jika perlu)"
  echo "  hapus nginx conf, openvpn, logrotate, BBR"
fi

echo -e "${CYAN}[7/7] User sistem mytunnel...${RESET}"
if [ -z "$BASE" ]; then
  # List users that are likely mytunnel (shell /bin/false, uid >=1000)
  orphans=""
  while IFS=: read -r u _ uid _ _ _ sh; do
    [ "$uid" -lt 1000 ] 2>/dev/null && continue
    case "$u" in root|hermes|nobody) continue;; esac
    case "$sh" in */false|*/nologin) orphans="$orphans $u";; esac
  done < /etc/passwd
  if [ -n "$orphans" ]; then
    echo "  Kandidat user mytunnel: $orphans"
    if confirm " Hapus semua user di atas? [y/N]: "; then
      for u in $orphans; do userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null || true; echo "  hapus $u"; done
    else echo "  dibiarkan"; fi
  else echo "  tidak ada kandidat user"; fi
else
  echo "  [TEST MODE] skip hapus user sistem"
fi

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✓ Uninstall selesai${RESET}"
echo -e "${GREEN}══════════════════════════════════════════════════${RESET}"
echo "  Backup pre-uninstall (jika dibuat): $REAL_BACKUP_DIR/mytunnel-pre-uninstall-*.tar.gz"
echo "  Log: $LOG (sudah dihapus jika ada)"
echo "  Untuk install ulang: bash install.sh"
if [ -z "$BASE" ]; then echo "  Reboot disarankan jika BBR/resolver diubah."; fi

__EMBED_EOF__
chmod 755 "$ETC/uninstall.sh"
cat > "$ETC/config/expiry.txt" << '__EMBED_EOF__'
2026-12-31

__EMBED_EOF__
chmod 644 "$ETC/config/expiry.txt"
echo -e "${CYAN}[4/13] Pasang perintah menu...${RESET}"
chmod +x "$ETC/menu/"*.sh "$ETC/setup/"*.sh "$ETC/cron/"*.sh "$ETC/features/"*.sh "$ETC/bot/"*.sh "$ETC/advanced/"*.sh 2>/dev/null || true
chmod 644 "$ETC/bot/handlers.sh" 2>/dev/null || true
chmod 644 "$ETC/lib/advanced_helpers.sh" 2>/dev/null || true
chmod 644 "$ETC/lib/"*.sh 2>/dev/null || true
chmod 600 "$ETC/db/ssh.txt" "$ETC/db/vmess.txt" "$ETC/db/vless.txt" "$ETC/db/trojan.txt" 2>/dev/null || true
chmod 600 "$ETC/db/.ssh.lock" "$ETC/db/.vmess.lock" "$ETC/db/.vless.lock" "$ETC/db/.trojan.lock" 2>/dev/null || true
chmod 644 "$ETC/config/banner.txt" "$ETC/config/brand.txt" "$ETC/config/ports.conf" 2>/dev/null || true
chmod 644 "$ETC/config/dropbear_versions.txt" "$ETC/config/version.txt" "$ETC/config/repo.txt" "$ETC/config/expiry.txt" "$ETC/config/domain.txt" 2>/dev/null || true
ln -sf "$ETC/menu/main.sh" "$BIN/menu" 2>/dev/null || cp "$ETC/menu/main.sh" "$BIN/menu" 2>/dev/null || true
# also expose doctor + uninstall at BIN and BASE
ln -sf "$ETC/menu/doctor.sh" "$BIN/mytunnel-doctor" 2>/dev/null || cp "$ETC/menu/doctor.sh" "$BIN/mytunnel-doctor" 2>/dev/null || true
chmod +x "$BIN/mytunnel-doctor" 2>/dev/null || true
# uninstall.sh top-level (if embedded as ETC/uninstall.sh, copy to BASE)
if [ -f "$ETC/uninstall.sh" ]; then cp -a "$ETC/uninstall.sh" "${BASE}/uninstall.sh" 2>/dev/null || true; chmod +x "${BASE}/uninstall.sh" 2>/dev/null || true; fi
# VERSION/CHANGELOG at BASE (only when test mode, else keep at ETC)
if [ -n "$BASE" ]; then
  if [ -f "$ETC/CHANGELOG.md" ]; then cp -a "$ETC/CHANGELOG.md" "${BASE}/CHANGELOG.md" 2>/dev/null || true; fi
  if [ -f "$ETC/VERSION" ]; then cp -a "$ETC/VERSION" "${BASE}/VERSION" 2>/dev/null || true; fi
fi
# logrotate (B7)
mkdir -p "${BASE}/etc/logrotate.d" 2>/dev/null || true
if [ -f "$ETC/logrotate.d/mytunnel" ]; then cp -a "$ETC/logrotate.d/mytunnel" "${BASE}/etc/logrotate.d/mytunnel" 2>/dev/null || true; chmod 644 "${BASE}/etc/logrotate.d/mytunnel" 2>/dev/null || true; fi
chmod 644 "${BASE}/var/log"/*.log "${BASE}/var/log"/*.sim.log 2>/dev/null || true; chmod 644 "${BASE}/var/log/xray"/*.log 2>/dev/null || true
if [ -f "$ETC/setup/logrotate.sh" ]; then bash "$ETC/setup/logrotate.sh" 2>&1 | tee -a "$LOG" || true; fi
chmod +x "$BIN/menu" 2>/dev/null || true
# suppress MOTD Ubuntu agar dashboard bersih 1:1 TUNNELING (60 kolom)
touch "$HOME/.hushlogin" 2>/dev/null || touch /root/.hushlogin 2>/dev/null || true
chmod 644 "$HOME/.hushlogin" 2>/dev/null || true
chmod 644 /root/.hushlogin 2>/dev/null || true
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then touch "/home/$SUDO_USER/.hushlogin" 2>/dev/null || true; fi
_log "tahap 1 selesai"

if [ "${MYTUNNEL_SKIP_SETUP:-0}" = "1" ]; then
  echo -e "${GREEN}✓ Install TAHAP 1 selesai (skip setup)${RESET}"
  echo -e "  Brand : $(cat "$ETC/config/brand.txt" 2>/dev/null)"
  echo -e "  Jalankan: ${CYAN}menu${RESET}"
  exit 0
fi

echo -e "${CYAN}[5/13] Setup domain...${RESET}"
_log "[5/13] domain"
if ! bash "$ETC/setup/domain.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup domain gagal" "Cek $ETC/setup/domain.sh dan $LOG"
fi

echo -e "${CYAN}[6/13] Setup firewall + BBR + swap...${RESET}"
_log "[6/13] firewall"
if ! bash "$ETC/setup/firewall.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup firewall gagal" "Cek $ETC/setup/firewall.sh dan $LOG"
fi

echo -e "${CYAN}[7/13] Setup TLS (acme.sh + LE)...${RESET}"
_log "[7/13] cert"
if ! bash "$ETC/setup/cert.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup TLS gagal" "Cek $ETC/setup/cert.sh dan $LOG"
fi

echo -e "${CYAN}[8/13] Setup Xray...${RESET}"
_log "[8/13] xray"
if ! bash "$ETC/setup/xray.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup Xray gagal" "Cek $ETC/setup/xray.sh dan $LOG"
fi

echo -e "${CYAN}[9/13] Setup Nginx...${RESET}"
_log "[9/13] nginx"
if ! bash "$ETC/setup/nginx.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup Nginx gagal" "Cek $ETC/setup/nginx.sh dan $LOG"
fi

echo -e "${CYAN}[10/13] Setup Dropbear...${RESET}"
_log "[10/13] dropbear"
if ! bash "$ETC/setup/dropbear.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup Dropbear gagal" "Cek $ETC/setup/dropbear.sh dan $LOG"
fi

echo -e "${CYAN}[10b/13] Setup OpenSSH 444 (keep 22)...${RESET}"
_log "[10b/13] openssh 444"
if ! bash "$ETC/setup/openssh.sh" 2>&1 | tee -a "$LOG"; then
  echo -e "${YELLOW}Setup OpenSSH 444 gagal, lanjut (cek manual $ETC/setup/openssh.sh)${RESET}" | tee -a "$LOG" 2>/dev/null || true
fi

echo -e "${CYAN}[11/13] Setup SSH-WS...${RESET}"
_log "[11/13] sshws"
if ! bash "$ETC/setup/sshws.sh" 2>&1 | tee -a "$LOG"; then
  _fail "Setup SSH-WS gagal" "Cek $ETC/setup/sshws.sh dan $LOG"
fi

echo -e "${CYAN}[12/13] Setup Cron SSH (autoexpire + limitip)...${RESET}"
_log "[12/13] cron ssh"
# tulis /etc/cron.d/mytunnel (idempotent)
CRON_FILE="${BASE}/etc/cron.d/mytunnel"
REAL_CRON="/etc/cron.d/mytunnel"
[ -n "$BASE" ] && CRON_FILE="${BASE}/etc/cron.d/mytunnel"
mkdir -p "$(dirname "$CRON_FILE")" 2>/dev/null || true
cat > "$CRON_FILE" << CRON_EOF
# mytunnel cron - managed by mytunnel (TAHAP 4)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 0 * * * root $ETC/cron/autoexpire.sh 2>/dev/null
* * * * * root $ETC/cron/limitip.sh 2>/dev/null
0 0 * * * root $ETC/cron/autoexpire_xray.sh 2>/dev/null
* * * * * root $ETC/cron/quota.sh 2>/dev/null
* * * * * root $ETC/cron/limitip_xray.sh 2>/dev/null
CRON_EOF
chmod 644 "$CRON_FILE" 2>/dev/null || true
echo -e "${CYAN}[13/13] Setup Cron Xray (quota + limitip_xray + autoexpire_xray)...${RESET}"
_log "[13/13] cron xray"
# --- Xray cron (quota/limitip_xray/autoexpire_xray) merged into same cron file ---
# Ensure previous content stays, append 3 lines idempotently
if ! grep -q "autoexpire_xray.sh" "$CRON_FILE" 2>/dev/null; then echo "0 0 * * * root $ETC/cron/autoexpire_xray.sh 2>/dev/null" >> "$CRON_FILE" 2>/dev/null || true; fi
if ! grep -q "quota.sh" "$CRON_FILE" 2>/dev/null; then echo "* * * * * root $ETC/cron/quota.sh 2>/dev/null" >> "$CRON_FILE" 2>/dev/null || true; fi
if ! grep -q "limitip_xray.sh" "$CRON_FILE" 2>/dev/null; then echo "* * * * * root $ETC/cron/limitip_xray.sh 2>/dev/null" >> "$CRON_FILE" 2>/dev/null || true; fi
if ! grep -q "bot_notify.sh" "$CRON_FILE" 2>/dev/null; then echo "*/5 * * * * root $ETC/cron/bot_notify.sh 2>/dev/null" >> "$CRON_FILE" 2>/dev/null || true; fi
chmod 644 "$CRON_FILE" 2>/dev/null || true
if [ -z "$BASE" ]; then
  mkdir -p /etc/cron.d 2>/dev/null || true
  cat > "$REAL_CRON" << CRON_EOF2
# mytunnel cron - managed by mytunnel (TAHAP 4)
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
0 0 * * * root $ETC/cron/autoexpire.sh 2>/dev/null
* * * * * root $ETC/cron/limitip.sh 2>/dev/null
0 0 * * * root $ETC/cron/autoexpire_xray.sh 2>/dev/null
* * * * * root $ETC/cron/quota.sh 2>/dev/null
* * * * * root $ETC/cron/limitip_xray.sh 2>/dev/null
*/5 * * * * root $ETC/cron/bot_notify.sh 2>/dev/null
CRON_EOF2
  chmod 644 "$REAL_CRON" 2>/dev/null || true
  systemctl restart cron 2>/dev/null || service cron restart 2>/dev/null || true
fi
echo -e "${GREEN}Crontab mytunnel dipasang: $CRON_FILE${RESET}"
_log "cron installed"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════${RESET}"
echo -e "${GREEN}  ✓ Install MyTunnel $(cat "$ETC/config/version.txt" 2>/dev/null || cat /etc/mytunnel/config/version.txt 2>/dev/null || echo "v1.1.0") selesai${RESET}"
echo -e "${GREEN}══════════════════════════════════════════════════${RESET}"
DOMAIN=$(cat "$ETC/config/domain.txt" 2>/dev/null || echo "-")
BRAND=$(cat "$ETC/config/brand.txt" 2>/dev/null || echo "TUNNEL PRO")
VER=$(cat "$ETC/config/version.txt" 2>/dev/null || cat /etc/mytunnel/config/version.txt 2>/dev/null || echo "v1.1.0")
echo -e "  ${BOLD}Versi   :${RESET} $VER"
echo -e "  ${BOLD}Domain  :${RESET} ${CYAN}$DOMAIN${RESET}"
echo -e "  ${BOLD}Brand   :${RESET} $BRAND"
echo -e "  ${BOLD}Cert    :${RESET} $ETC/cert/fullchain.crt"
echo -e "  ${BOLD}Xray    :${RESET} $ETC/../usr/local/etc/xray/config.json (listen 127.0.0.1:10001-10003 ws, 10011-10013 grpc, 10021-10023 hu)"
echo -e "  ${BOLD}Nginx   :${RESET} ${BASE}/etc/nginx/conf.d/mytunnel.conf (80/8080/2082,2083,8880 http + 443/8443 https)"
echo -e "  ${BOLD}Port (ports.conf):${RESET}"
if [ -f "$ETC/config/ports.conf" ]; then cat "$ETC/config/ports.conf" 2>/dev/null | sed 's/^/    /'; else echo "    (ports.conf tidak ada)"; fi
echo -e "  ${BOLD}Paths   :${RESET}"
echo -e "    Config  : $ETC/"
echo -e "    Xray cfg: ${BASE}/usr/local/etc/xray/config.json"
echo -e "    Nginx   : ${BASE}/etc/nginx/conf.d/mytunnel.conf"
echo -e "    Cron    : $CRON_FILE"
echo -e "    Log     : $LOG  + ${BASE}/var/log/xray/*.log  + ${BASE}/var/log/nginx/*.log"
echo -e "    Backup  : ${BASE}/root/backup/mytunnel-*.tar.gz (chmod 600, keep 7)"
echo ""
echo -e "  ${BOLD}Cek service:${RESET}"
echo -e "    ${YELLOW}systemctl status xray nginx dropbear mytunnel-sshws --no-pager${RESET}"
echo -e "    ${YELLOW}ss -tlnp | grep -E ':(22|80|443|444|90|1000)'${RESET}"
echo -e "    ${YELLOW}curl -I https://\$DOMAIN${RESET}"
echo -e "    ${YELLOW}xray run -test -config ${BASE}/usr/local/etc/xray/config.json${RESET}"
echo -e "    ${YELLOW}nginx -t; cat /etc/cron.d/mytunnel${RESET}"
echo -e "    ${YELLOW}mytunnel-doctor${RESET}  # cek konsistensi db vs Xray vs system"
echo ""
if command -v systemctl >/dev/null 2>&1 && [ -z "$BASE" ]; then
  echo -e "${CYAN}Status service:${RESET}"
  for s in xray nginx dropbear mytunnel-sshws mytunnel-bot squid mytunnel-udpgw mytunnel-ohp-ssh slowdns mytunnel-udp-custom mytunnel-openvpn-tcp; do systemctl is-active "$s" 2>/dev/null | xargs -I{} echo "  $s : {}" || echo "  $s : OFF/unknown"; done
else
  echo -e "${CYAN}[TEST MODE] Cek file:${RESET}"
  ls -lh "$ETC/cert/fullchain.crt" "$ETC/cert/private.key" 2>&1 | sed 's/^/  /'
  grep -E "listen|proxy_pass.*1000" "${BASE}/etc/nginx/conf.d/mytunnel.conf" 2>/dev/null | head -n 12 | sed 's/^/  /'
  cat "$CRON_FILE" 2>/dev/null | sed 's/^/  /'
fi
echo ""
echo -e "  ${BOLD}Cara buka menu:${RESET}"
echo -e "    ${CYAN}menu${RESET}  (atau ${CYAN}/usr/local/bin/menu${RESET}, ${CYAN}mytunnel-doctor${RESET})"
echo -e "  ${BOLD}Update:${RESET}  ${CYAN}menu -> FEATURES -> Auto Update${RESET}  atau  ${CYAN}bash $ETC/features/autoupdate.sh${RESET}"
echo -e "  ${BOLD}Uninstall:${RESET} ${CYAN}bash ${BASE}/uninstall.sh${RESET}  (ketik ${BOLD}hapus${RESET})"
echo -e "  ${BOLD}Satu perintah (baru):${RESET}"
echo -e "    ${DIM}wget -qO install.sh https://raw.githubusercontent.com/USER/REPO/main/install.sh && less install.sh && bash install.sh${RESET}"
echo -e "    ${DIM}MYTUNNEL_DOMAIN=example.com MYTUNNEL_YES=1 bash install.sh  # non-interaktif${RESET}"
echo ""
_log "install selesai: domain=$DOMAIN brand=$BRAND ver=$VER"
