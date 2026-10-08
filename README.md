# MyTunnel — TUNNEL PRO v1.1.0

Varian tunneling All-In-One netral universal **Debian 11/12 + Ubuntu 18/20/22/24** (disarankan **Debian 12 / Ubuntu 22.04**). Banner/brand edit 1 baris (`menu → 8 SET BRAND`), transport **Xray VMess/VLess/Trojan** WS+gRPC+HTTPUpgrade lewat **Nginx 80/443 exclusive**, SSH/Dropbear/OpenSSH, plus fitur opsional bot/WARP/routing/SlowDNS/Squid/UDPGW/OHP/OpenVPN.

> **Aman:** `wget` lalu `less` dulu, baru `bash` — tanpa `curl | bash`. Download hanya HTTPS, verifikasi SHA256.

## Fitur

- **SSH**: OpenSSH 444 + Dropbear 90 + SSH-WS :10004 (proxy Nginx 80/443/8443/8080/2082,2083,8880), auto-expire, limit IP, quota, trial
- **VMess / VLess / Trojan**: 9 inbound Xray (WS `/vmess /vless /trojan` + gRPC `vmess/vless/trojan` + HTTPUpgrade `/up*`), listen `127.0.0.1:10001-10023` + `10085 api`, TLS `443,8443`, link `vless:// / vmess:// / trojan://` siap v2rayNG/NekoBox
- **Nginx** :80 WS/HU+acme + :443 `ssl http2` TLS1.2/1.3 (3600s), + :8443/:8080/:2082,2083,8880/:81 config
- **Sertifikat** `acme.sh` auto + validasi `nginx -t`/`xray -test` + rollback
- **Layanan opsional SSH** (aktif hanya jika terpasang, output kondisional):
  Squid `127.0.0.1:3128`, UDPGW `127.0.0.1:7100-7600` (badvpn), OHP `9080→444 + 9088→1194`, OpenVPN `1194/tcp 25000/udp 442/ssl 53/dns`, SlowDNS `5300` (redirect `53→5300`), UDP-Custom `1-65535`
- **Bot Telegram** (opsional): create/trial/cek akun, admin-only `chat_id`, token `chmod 600` & mask `xxxxx***`, throttle
- **WARP / Routing / SlowDNS** opsional, preserve `outbounds/routing` Xray saat reinstall
- **FEATURES (11)**: Bandwidth, Reboot, Speedtest, Services, Backup/Restore, Domain, Banner, Security, Auto-Update, Sysinfo, Dropbear-Version
- **Ketahanan**: flock DB (`600`), backup `.bak-TS` + validasi + rollback, idempotent 2× aman, `doctor` (db vs Xray vs system), `uninstall.sh` bersih + restore resolver/sshd/UFW, `logrotate` daily 7, `VERSION`/`CHANGELOG` + tampil di kotak menu

## Persyaratan

| Item | Minimal | Catatan |
|---|---|---|
| OS | Debian 11/12, Ubuntu 18/20/22/24 | Disarankan **Debian 12** / **Ubuntu 22.04**; `arch` x86_64/arm64 |
| RAM / Disk | 512 MB / 2 GB bebas | Preflight cek `free`/`df`; swap 2G disarankan |
| Akses | **root** (`id -u 0`) | `sudo -i` dulu |
| Domain | A record → IP VPS | `dig +short A domain` == IP `curl ipinfo.io/ip`; **Cloudflare proxy OFF** (awan abu, bukan oranye) |
| Port bebas | 80, 443, 444, 81, 8443 | Preflight `ss -tlnp` warning jika bentrok; 80/443 **exclusive tunneling** (tanpa mux/sslh) |
| Internet | ping 1.1.1.1 + DNS | preflight cek |

## Arsitektur Final 443

`install.sh` lama tidak diubah. Terapkan konfigurasi final bertahap setelah install:

```bash
wget -qO configure-final-443.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone/main/configure-final-443.sh
less configure-final-443.sh
bash configure-final-443.sh --dry-run
bash configure-final-443.sh
```

Jalur:

```text
443 TCP -> nginx stream ssl_preread
       ALPN h2/http/1.1 -> nginx 127.0.0.1:9443 (TLS/http2)
       ALPN lain          -> stunnel 127.0.0.1:4443 -> tlsmux -> 8080/SSH legacy
8443 TCP -> nginx TLS/http2 langsung
80 TCP   -> httpmux lama (WS/HTTPUpgrade; gRPC tidak dipakai)
```

| Transport | Path/service | Port yang didukung | Upstream |
|---|---|---|---|
| WS | `/vless`, `/vmess`, `/trojan` | 80, 443, 8443 | Xray WS inbound |
| gRPC | `serviceName=vless/vmess/trojan` | 443, 8443 | Xray gRPC via `grpc_pass` |
| HTTPUpgrade | `/upvless`, `/upvmess`, `/uptrojan` | 80, 443, 8443 | Xray HTTPUpgrade |
| XHTTP | `/xvless` (dan proto lain jika tersedia) | 80, 443, 8443 | Xray XHTTP, `mode=auto` |

Skrip idempoten: backup di `/root/mytunnel-443-backup/<timestamp>/`, `nginx -t` sebelum reload, rollback otomatis bila validasi gagal. Rollback manual:

```bash
bash configure-final-443.sh --rollback
```

`--dry-run` hanya menampilkan rencana. Konfigurasi baru perlu diuji per transport; hasil uji LIVE dicatat di CHANGELOG sebelum branch digabung. Instalasi VPS baru dari `install.sh` lama perlu menjalankan skrip ini sampai integrasi final ke installer selesai (B).

## Cara Install

### Satu perintah (disarankan — cek dulu)

```bash
wget -qO install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone/main/install.sh
less install.sh   # periksa isinya
bash install.sh
# ikuti preflight → ringkasan OS/RAM/disk/port → konfirmasi [Y/n] → tanya Domain & Brand
```

`install.sh` cek **root, OS, arch, RAM/disk, internet, port 80/443** lalu minta confirm sebelum ubah sistem. Semua port dari `config/ports.conf` (edit file itu saja untuk ganti port).

### Non-interaktif (otomasi / CI)

```bash
# via env
MYTUNNEL_DOMAIN=example.com MYTUNNEL_BRAND="My Brand" MYTUNNEL_YES=1 bash install.sh
# atau via arg (butuh MYTUNNEL_PREFIX saat test)
bash install.sh --domain example.com --brand "My Brand" --yes
MYTUNNEL_PREFIX=/tmp/test MYTUNNEL_DOMAIN=example.com bash install.sh --no-deps  # test tanpa deps
bash install.sh --help   # lihat opsi
```

### Cara buka menu

```bash
menu
/usr/local/bin/menu
mytunnel-doctor          # cek konsistensi db vs Xray vs system
```

### Update

```bash
menu → 6 FEATURES → Auto Update
# atau
bash /etc/mytunnel/features/autoupdate.sh
# manual: wget -qO install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone/main/install.sh && bash install.sh
# idempotent: jalankan 2× aman (brand/cron/nginx/xray tidak duplikat)
```

### Backup & Restore

```bash
menu → 6 FEATURES → Backup   # tar xz 600 keep 7 di /etc/mytunnel/backup/
# file: backup-mytunnel-TS.tar.gz (db/*.txt + config + Xray json + OpenVPN + ports.conf)
ls -lh /etc/mytunnel/backup/
# restore (VPS baru / ganti domain)
scp backup-*.tar.gz root@baru:/tmp/
tar -xzf /tmp/backup-*.tar.gz -C /   # atau via menu Backup → Restore
systemctl restart xray nginx
mytunnel-doctor   # verifikasi 0 orphan
```

### Ganti domain / brand

```bash
menu → 6 FEATURES → Domain   # atau echo example.com > /etc/mytunnel/config/domain.txt && bash /etc/mytunnel/setup/domain.sh
menu → 8 SET BRAND NAME      # echo "Nama Baru" > /etc/mytunnel/config/brand.txt
# idempotent: jika domain.txt sudah ada, install ulang pakai existing
```

### Uninstall bersih

```bash
bash uninstall.sh            # ketik: hapus  (konfirmasi)
bash uninstall.sh --backup   # backup dulu .tar.gz 600 baru hapus
# yang dihapus: service xray/nginx/dropbear/sshws/squid/udpgw/ohp/openvpn/slowdns/udp-custom/bot,
# cron mytunnel, nginx location /vmess+/up*, Xray client, UFW rule, resolver/sshd restore dari .bak-*
# directory: /etc/mytunnel /usr/local/etc/xray /var/log/mytunnel.log
```

## Tabel Port & Layanan (`config/ports.conf`)

Satu sumber kebenaran — ubah angka di file ini, script ikut.

| Layanan | Port | Protokol / Catatan |
|---|---|---|
| **OpenSSH** | 444 | `sshd` `Port 444` (keep 22), `sshd -t` validasi |
| **Dropbear** | 90 | `dropbear :90` |
| **TLS** | 443,8443 | Nginx `listen 443 ssl http2` + `8443 ssl http2` → Xray WS/gRPC/HU |
| **None TLS** | 80,8080 | Nginx `:80` (acme/.well-known) + `proxy /vmess*` & `grpc_pass` |
| **Any** | 2082,2083,8880 | Nginx listen tambahan WS/HU |
| **SSH-WS** | 10004 | `127.0.0.1:10004` path `/ssh-ws` |
| **Config** | 81 | `http://DOMAIN:81/myvpn-config.zip` (Nginx `root /var/www/html`) |
| **SlowDNS** | 53,5300 | `dnstt` `:5300` + `iptables REDIRECT 53→5300`, `DNSStubListener=no` |
| **UDP-Custom** | 1-65535 | rentang UDP; exclude `22,444,80,443,53,81,25000,5300,...` di setup |
| **OHP+SSH** | 9080 | `ohp -a 127.0.0.1:444 -b 0.0.0.0:9080` |
| **Squid** | 3128 | `http_port 127.0.0.1:3128` + `acl localhost` `http_access deny all` (bukan open proxy) |
| **UDPGW** | 7100-7600 | `badvpn-udpgw 127.0.0.1:7100-7600` systemd 5 sample |
| **OpenVPN TCP** | 1194 | `proto tcp` `auth-user-pass` `<ca>` saja |
| **OpenVPN SSL** | 442 | `proto tcp` (443 exclusive Nginx) |
| **OpenVPN UDP** | 25000 | `proto udp` |
| **OpenVPN DNS** | 53 | mutual exclusion: OFF jika SlowDNS aktif (REDIRECT menang) |
| **OHP+OVPN** | 9088 | `ohp -a 127.0.0.1:1194 -b 0.0.0.0:9088` |
| **Xray API** | 10085 | `127.0.0.1:10085` stats |

> Output `Create SSH` cetak **hanya baris yang aktif** (`systemctl is-active` / `ss -tlnp/-ulnp`), urutan persis tabel di atas; dipakai ulang Create/Trial/bot Check Config.

## Panduan Menu

```
menu utama: 1 SSH  2 VMESS  3 VLESS  4 TROJAN  5 SETUP BOT  6 FEATURES  7 SET TIME  8 SET BRAND  9 DOCTOR  x EXIT
```

| Menu | Isi singkat |
|---|---|
| **1 SSH** | Create / Trial / Renew / Delete / Check / Member / Auto-kill; `print_ssh_account_info` baca `ports.conf` + `is-active` |
| **2 VMess / 3 VLess / 4 Trojan** | Create / Trial / Renew / Delete / Check; WS path `/vmess /vless /trojan`, gRPC serviceName sama, HU `/up*`; VLess `Encryption:none`, Trojan `Key` |
| **5 BOT** | Pasang token, set admin `chat_id`, webhook/polling, test `123456 ALLOWED 999999 BLOCKED`, mask `abc123***` |
| **6 FEATURES** | Bandwidth, Reboot, Speedtest, Services, Backup, Domain, Banner, Security, AutoUpdate, Sysinfo, Dropbear-Version + `Layanan SSH Tambahan` (Squid/UDPGW/OHP/OpenVPN/SlowDNS/UDP-Custom) |
| **7 TIME** | Set timezone/reduce |
| **8 BRAND** | `BRAND_NAME` 1 baris (guard `tunnelcore`→editable) |
| **9 DOCTOR** | Banding `db/*.txt` vs `config.json` Xray vs `getent passwd`; lapor hilang/orphan/PARSIAL/expired + tawarkan fix |

### Contoh output (lebar 60 kolom, `──────────────── 36`)

**VMess** (`Remarks: alice01  CITY: Bandung  ISP: ...`):

```
------------------------------------
           VMESS ACCOUNT
------------------------------------
Remarks    : alice01
CITY       : Bandung
ISP        : PT Example
Domain     : example.com
Port TLS   : 443,8443
Port none  : 80,8080
Port Any   : 2082,2083,8880
id         : 550e8400-... 
alterId    : 0
Security   : auto
Network    : ws,grpc,upgrade
Path ws    : /vmess
serviceName: vmess
Path upgrade: /upvmess
Expired On : 2026-11-02  Quota: 10GB  Limit IP: 2
------------------------------------
VMESS WS TLS:
vmess://eyJhZGQiOiJleGFtcGxlLmNvbSIsInBvcnQiOiI0NDMi...
VMESS WS NO TLS: ...
VMESS GRPC: ...
VMESS Upgrade TLS: ...
VMESS Upgrade NO TLS: ...
```

**VLess**: sama tanpa `alterId/Security`, ada `Encryption:none` `Path ws: /vless` `serviceName: vless` `Path upgrade: /upvless`; 5 link `vless://uuid@DOMAIN:443?path=/vless&security=tls&encryption=none...`

**Trojan**: `Key` (bukan `Password`), hanya `Port TLS 443,8443 + Any`, `Path ws: /trojan` `serviceName: trojan` `/uptrojan`, 3 link TLS saja (`ws tls / grpc / upgrade tls`), `Expired On` di **bawah** setelah link (garis sebelum & sesudah).

**SSH** (kondisional — hanya cetak yang `ON`):

```
------------------------------------
            SSH ACCOUNT
------------------------------------
Remarks    : alice
CITY       : Bandung
ISP        : PT Example
Domain     : example.com
TLS        : 443,8443
None TLS   : 80,8080
Any        : 2082,2083,8880
OpenSSH    : 444
Dropbear   : 90
SlowDNS    : 53,5300
UDP-Custom : 1-65535
OHP+SSH    : 9080
Squid      : 3128
UDPGW      : 7100-7600
OpenVPN TCP: 1194
OpenVPN SSL: 442
OpenVPN UDP: 25000
OHP+OVPN   : 9088
Link config: http://example.com:81/myvpn-config.zip
------------------------------------
Username: alice  Password: ***  Expired: 2026-11-02
```

## Troubleshooting

| Gejala | Penyebab umum | Perbaikan |
|---|---|---|
| **Sertifikat gagal** `acme.sh` | A record belum propagasi / Cloudflare proxy ON / port 80 terpakai | `dig +short A domain` harus == IP `curl -4 ifconfig.me`; Cloudflare **abu**; `ss -tlnp :80` bebas; `cat /var/log/mytunnel.log | grep acme`; `bash /etc/mytunnel/setup/cert.sh --force` |
| **Port bentrok** `address already in use` | Nginx/Xray/OpenVPN/Squid bentrok | `ss -tlnp; ss -ulnp`; cek `cat /etc/mytunnel/config/ports.conf`; ubah port di file itu lalu `bash /etc/mytunnel/setup/nginx.sh` + `nginx -t` |
| **Xray tidak start** `exit 23` | `config.json` invalid / port bentrok / permission log | `xray run -test -c /usr/local/etc/xray/config.json`; `jq . /usr/local/etc/xray/config.json`; restore `cp /usr/local/etc/xray/config.json.bak-TS ...`; `mkdir -p /var/log/xray; chown nobody` |
| **Tidak bisa konek** WS/gRPC | Domain/SNI salah / path salah / firewall | Cek link `host=DOMAIN sni=DOMAIN path=/vmess`; `curl -v https://DOMAIN/vmess`; `ufw status`; `nginx -t`; `systemctl status xray nginx` |
| **SSH terkunci** port 444 tidak bisa | UFW belum allow / `sshd_config` salah | Preflight allow `444/tcp` keep `22`; `sshd -t && systemctl restart sshd`; recovery via console `ufw allow 22/tcp`; `cat /etc/ssh/sshd_config | grep Port` |

Log penting:

```bash
tail -n 100 /var/log/mytunnel.log
xray run -test -c /usr/local/etc/xray/config.json
nginx -t; cat /etc/nginx/conf.d/mytunnel.conf | head -n 80
ss -tlnp; ss -ulnp; ufw status
systemctl status xray nginx dropbear squid 2>&1 | head -n 40
mytunnel-doctor          # atau menu → 9 DOCTOR
cat /etc/mytunnel/config/ports.conf
cat /etc/mytunnel/config/domain.txt; cat /etc/mytunnel/config/brand.txt
```

## Keamanan & Disclaimer

- **Izin file**: `db/*.txt 600`, `config/bot.conf 600`, `private key 600`, `backup 600`; `sim.log/nginx.conf 644`, `setup/*.sh 755`, `logrotate.d 644`. Cek `find /etc/mytunnel -ls`.
- **Tanpa kredensial di log**: `password/UUID/token` tidak masuk `/var/log/mytunnel.log` atau output layar penuh (token tampil `abc123***` 6 char).
- **Tanpa `eval`**, semua variabel quote, `jq --arg`, validasi username `^[a-z0-9_]{3,16}$`, UUID regex, `flock` DB, `backup+bak-TS+validasi+rollback` tiap ubah config.
- **Bot** hanya balas `chat_id == ADMIN_ID` (non-admin diabaikan tanpa balasan).
- **Squid** `127.0.0.1:3128` + `allow localhost / deny all` — bukan open proxy. UFW `allow 22` dulu anti-lockout.
- **OpenVPN zip** hanya `.ovpn + ca.crt`, tanpa `server.key/ta.key` (private `600` internal).
- **Service** `User=nobody Restart=always RestartSec=3 LimitNOFILE=65535`; `logrotate` daily 7 compress `/var/log/mytunnel.log + /var/log/xray/*.log`.
- **Download** hanya HTTPS sumber resmi, checksum tampil (SHA256).

> **Disclaimer**: Gunakan hanya di VPS milik sendiri dan patuhi hukum setempat serta **aturan penyedia VPS** (ToS/AUP). Penyalahgunaan untuk spam, DDoS, atau pelanggaran hukum menjadi tanggung jawab pengguna. Penulis tidak bertanggung jawab atas pemblokiran atau sanksi dari provider.

## Lapor Bug

Sertakan:

```
- OS: cat /etc/os-release; uname -m; free -m; df -h /
- Versi: cat /VERSION; cat /etc/mytunnel/config/version.txt; cat /etc/mytunnel/config/ports.conf
- Domain & IP: cat /etc/mytunnel/config/domain.txt; dig +short A domain; curl -4 ifconfig.me
- Log: tail -n 200 /var/log/mytunnel.log; tail -n 100 /var/log/xray/error.log
- Service: systemctl status xray nginx dropbear 2>&1 | head -n 60; ss -tlnp; ufw status
- Validasi: xray run -test -c /usr/local/etc/xray/config.json; nginx -t; mytunnel-doctor
- Langkah reproduksi + yang diharapkan vs yang terjadi
```

Kirim via issue GitHub + lampirkan log terpotong (tanpa password/UUID/token penuh).

## Lisensi

MIT — lihat `LICENSE`. `SHA256SUMS` terbit tiap build (`sha256sum -c SHA256SUMS` harus `6/6 OK`).

## Struktur Repo

```
install.sh      533K 10857L  rwxrwxr-x  bash -n OK  (installer satu perintah)
uninstall.sh     11K   225L  rwxr-xr-x  hapus bersih + restore
VERSION            7  v1.1.0
CHANGELOG.md    1.5K  v1.1.0 (A-D) + v1.0.0 (1-6+8)
SHA256SUMS      459  6 entri (install/uninstall/VERSION/CHANGELOG/README/LICENSE)
README.md       ~12K  dokumen ini
LICENSE         1.1K  MIT
```

Cara packaging: `bash /tmp/build_tahap6.sh` → `install.sh` + `SHA256SUMS` + `Repo structure` + `bash -n OK`.
