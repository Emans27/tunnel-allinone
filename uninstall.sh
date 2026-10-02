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
