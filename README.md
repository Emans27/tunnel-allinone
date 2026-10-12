# MyTunnel — TUNNEL PRO v1.9.1

Tunneling All-In-One untuk **Debian 11/12 + Ubuntu 18/20/22/24** (disarankan **Debian 12** / **Ubuntu 22.04**). Transport **Xray VMess/VLess/Trojan** WS + gRPC + HTTPUpgrade lewat **Nginx 443 exclusive**, SSH/Dropbear/OpenSSH, plus fitur opsional bot, WARP, SlowDNS, Squid, UDPGW, OHP, OpenVPN, dan LOGIN REPORT.

Brand permanen sejak v1.9.0: `chattr +i` + canon root-only + cron tiap menit. Menu `8 SET BRAND` jadi read-only.

## Install

Sekali paste, di VPS **root**, tanpa setting lanjutan:

```bash
wget -qO install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone/main/install.sh && MYTUNNEL_DOMAIN=domain.kamu MYTUNNEL_YES=1 bash install.sh
```

Domain harus A-record -> IP VPS dan **Cloudflare proxy OFF** (awan abu, bukan oranye).

Urutan: preflight cek root/OS/RAM/disk/internet/port -> tulis semua config, lib, menu, setup, cron -> pasang Nginx, Xray, Dropbear, Stunnel -> **step `[9d/13]` jalankan `configure-final-443.sh`** (bikin 443 = nginx stream ssl_preread) -> UFW, BBR, sysctl, user system.

Cek hasil:

```bash
ss -tlnp | grep -E ':(80|443|8443|444|90)\b'
menu
```

### Opsi lain

```bash
bash install.sh                                    # interaktif (tanya domain/brand)
bash install.sh --domain example.com --yes         # sama, via arg
bash install.sh --help                             # semua flag
MYTUNNEL_PREFIX=/tmp/t MYTUNNEL_DOMAIN=example.com bash install.sh --no-deps   # test mode, tanpa root
```

Domain diambil dari env, atau dari `/etc/mytunnel/config/domain.txt` kalau sudah ada - jadi reinstall tidak perlu domain baru.

## Persyaratan

- OS Debian 11/12 atau Ubuntu 18/20/22/24, `arch` x86_64/arm64
- RAM 512 MB, disk 2 GB bebas
- Akses root
- Domain A-record -> IP VPS
- Port bebas: 80, 443, 444, 81, 8443
- Internet + DNS jalan

## Arsitektur 443

```
443 TCP -> nginx stream ssl_preread
       ALPN h2/http/1.1 -> nginx 127.0.0.1:9443 (TLS/http2)
       ALPN lain          -> stunnel 127.0.0.1:4443 -> tlsmux (klien legacy)
8443 TCP -> nginx TLS/http2 langsung
80 TCP   -> httpmux (WS/HTTPUpgrade)
```

Dijalankan otomatis saat install. Kalau perlu jalankan ulang manual:

```bash
bash /root/configure-final-443.sh --dry-run    # lihat rencana
bash /root/configure-final-443.sh              # terapkan
bash /root/configure-final-443.sh --rollback   # kembalikan dari backup
```

Idempoten, backup bertanggal di `/root/mytunnel-443-backup/<timestamp>/`, `nginx -t` sebelum reload, rollback otomatis kalau validasi gagal.

| Transport | Path | Port | Upstream |
|---|---|---|---|
| WS | `/vless`, `/vmess`, `/trojan` | 80, 443, 8443 | Xray WS |
| gRPC | `serviceName=vless/vmess/trojan` | 443, 8443 | Xray gRPC via `grpc_pass` |
| HTTPUpgrade | `/upvless`, `/upvmess`, `/uptrojan` | 80, 443, 8443 | Xray HTTPUpgrade |

## Port

Satu sumber kebenaran: `/etc/mytunnel/config/ports.conf` (juga ada `ports.conf` di root repo). Ubah angkanya di situ, bukan di script.

| Layanan | Port |
|---|---|
| OpenSSH | 444 (keep 22) |
| Dropbear | 90 |
| TLS | 443, 8443 |
| None TLS | 80, 8080 |
| Any | 2082, 2083, 8880 |
| SSH-WS | 10004 (internal, lewat Nginx) |
| Config | 81 |
| SlowDNS | 5300 (redirect 53) |
| UDP-Custom | 1-65535 |
| OHP SSH / OHP OVPN | 9080 / 9088 |
| Squid | 3128 |
| UDPGW | 7100-7600 |
| OpenVPN | 1194 TCP, 442 SSL, 25000 UDP |
| Xray API | 10085 |

Output `Create SSH` hanya mencetak baris yang benar-benar aktif (`systemctl is-active` / `ss -tlnp`).

## Menu

```
1 SSH   2 VMESS   3 VLESS   4 TROJAN   5 SETUP BOT
6 FEATURES   7 SET REDUCE/TIME   8 SET BRAND NAME   9 CHECK SERVICES
10 LOGIN REPORT   x EXIT
```

| Menu | Isi |
|---|---|
| 1 SSH | Create / Trial / Renew / Delete / Check / Member / Auto-kill |
| 2-4 VMess / VLESS / Trojan | Create / Trial / Renew / Delete / Check; link siap v2rayNG / NekoBox |
| 5 BOT | Token, admin `chat_id`, polling, test, token dimask `abc123***` |
| 6 FEATURES | Bandwidth, Reboot, Speedtest, Services, Backup/Restore, Domain, Banner, Security, Auto-Update, Sysinfo, Dropbear-Version, layanan SSH tambahan |
| 7 SET REDUCE/TIME | Timezone, reduce |
| 8 SET BRAND NAME | Read-only, brand permanen |
| 9 CHECK SERVICES | Status xray / nginx / ssh / dropbear |
| 10 LOGIN REPORT | Laporan user aktif ke Telegram (`lreport`) |

## LOGIN REPORT

Laporan login user aktif (SSH/VMess/VLESS/Trojan) dikirim ke Telegram via systemd timer. Config ada di `/etc/login-report/config.conf` (mode 600, dibuat saat install).

Isi token bot sekali:

```bash
lreport              # menu: set BOT_TOKEN dari @BotFather, set CHAT_ID, test kirim
# atau
menu -> 10 LOGIN REPORT
```

Default `ENABLED=off`. Aktifkan dari menu, timer systemd dibuat otomatis.

## Update

```bash
menu -> 6 FEATURES -> Auto Update
# atau manual: unduh install.sh lalu jalankan lagi - idempotent, aman 2x
```

## Uninstall

```bash
bash uninstall.sh --backup   # backup dulu (.tar.gz 600), baru hapus
bash uninstall.sh            # tanpa backup, ketik "hapus" untuk konfirmasi
```

Bersihkan: service, cron, location Nginx, Xray client, rule UFW, `/etc/mytunnel`, `/usr/local/etc/xray`, log. Resolver/sshd/UFW di-restore dari `.bak-*`.

## Troubleshooting

| Gejala | Perbaikan |
|---|---|
| Sertifikat gagal | `dig +short A domain` harus == `curl -4 ifconfig.me`; Cloudflare abu; `ss -tlnp :80` kosong; `bash /etc/mytunnel/setup/cert.sh --force` |
| Port bentrok | `ss -tlnp; ss -ulnp`; ubah di `/etc/mytunnel/config/ports.conf`; `bash /etc/mytunnel/setup/nginx.sh` lalu `nginx -t` |
| Xray tidak start | `xray run -test -c /usr/local/etc/xray/config.json`; restore dari `config.json.bak-TS` |
| Tidak konek | cek `host`/`sni`/`path` di link; `curl -v https://DOMAIN/vmess`; `ufw status`; `systemctl status xray nginx` |
| SSH port 444 mati | `sshd -t && systemctl restart sshd`; recovery via console: `ufw allow 22/tcp` |
| 443 tidak listen | `bash /root/configure-final-443.sh --dry-run` lalu jalankan tanpa flag |
| Token bot ditolak | `cat /etc/login-report/config.conf` - pastikan `BOT_TOKEN` dan `CHAT_ID` terisi |

Log & diagnosa:

```bash
tail -n 100 /var/log/mytunnel.log
mytunnel-doctor      # db vs Xray vs system
ls /etc/mytunnel/backup/
```

## Keamanan

- `db/*.txt`, `config/bot.conf`, `config/login-report`, private key, backup: mode 600
- Password/UUID/token tidak masuk log, tidak tampil penuh di layar
- Tanpa `eval`, semua variabel di-quote, validasi username `^[a-z0-9_]{3,16}$`, UUID via regex
- `flock` pada DB, `backup + .bak-TS + validasi + rollback` tiap ubah config
- Bot hanya balas `chat_id == ADMIN_ID`
- Squid `127.0.0.1:3128` + `deny all`, bukan open proxy
- UFW selalu `allow 22/tcp` dulu anti-lockout

## Lisensi

MIT - lihat `LICENSE`. `SHA256SUMS` terbit tiap build, 8 entri (`sha256sum -c SHA256SUMS` harus `8/8 OK`).

> **Disclaimer**: pakai hanya di VPS milik sendiri, patuhi hukum setempat dan ToS provider. Penulis tidak bertanggung jawab atas pemblokiran atau sanksi dari provider.
