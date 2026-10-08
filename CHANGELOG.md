# CHANGELOG

## v1.6.0 — 2026-10-08 — Blok akun SSH (mono per baris) + create/trial
### Added
- `ssh_account_block()` di `lib/ssh_helpers.sh`: cetak blok akun SSH persis
  (HOST/Username/Password, Expired, TLS/NoneTLS/Any/OpenSSH/Dropbear, lalu
  SlowDNS/UDP-Custom/OHP+SSH/Squid/UDPGW/OpenVPN TCP+SSL+UDP+DNS/OHP+OVPN,
  baris ringkas `host:443@user:pass  host:80@user:pass`, dan link config).
  Nilai port dibaca dari `ports.conf` (dinamis).
- `ah_notify_admin_mono()` di `lib/advanced_helpers.sh`: kirim blok ke Telegram
  dengan tiap baris dibungkus `<code>` (parse_mode=HTML) -> mono per baris,
  bukan satu code block `<pre>`. Escape `&`/`<`/`>`; fallback teks biasa.

### Changed
- `print_ssh_account_info()` = jarak + `ssh_account_block` + jarak (terminal).
- Notif Telegram saat **create** dan **trial** akun SSH kini mengirim blok lengkap
  sebagai mono per baris (sebelumnya hanya baris ringkas).
- Pemisah blok pakai 36 tanda minus biasa (`------------------------------------`),
  bukan karakter box.

### Unchanged
- Service, port, config VPS: tidak diubah (hanya file di `/etc/mytunnel`).
- `main` tidak disentuh; kerja ini di branch `final-443-stream`.

### Verified (live, VPS 206.189.32.83 / tesc.sunekvip.cc.cd)
- Blok persis sesuai spec: dash 36, label rata kolom 16, dua spasi di baris ringkas.
- Telegram API balas `"ok":true`; payload `<code>...</code>` per baris.
- `ssh_create` dgn username yang sudah ada -> pesan error + exit 2, DB tidak bertambah.
- `bash -n` + shellcheck -S error: 0.

## v1.5.0 — 2026-10-08 — Baris ringkas akun SSH + notif Telegram mono
### Added
- `ssh_compact_line(user, pass)` di `lib/ssh_helpers.sh`: hasilkan satu baris ringkas
  `host:TLS@user:pass & host:NONTLS@user:pass` (port diambil dari `ports.conf`,
  ambil port pertama dari `TLS_PORT` dan `NONTLS_PORT`).
- `print_ssh_account_info` mencetak baris ringkas itu di akhir blok (terminal).

### Changed
- Notif Telegram saat buat akun SSH (create/trial/recovery) kini mengirim HANYA baris
  ringkas dalam mono (inline code), bukan seluruh blok `Account Created Successfully`.
  Contoh: `` `host:443@user:pass & host:80@user:pass` ``

### Verified
- Harness: baris ringkas = `tesc.sunekvip.cc.cd:443@emon:emon & tesc.sunekvip.cc.cd:80@emon:emon`;
  notif Telegram = `` `tesc.sunekvip.cc.cd:443@emon:emon & tesc.sunekvip.cc.cd:80@emon:emon` ``;
  blok terminal tetap tampil + baris ringkas di akhir. `bash -n`/shellcheck -S error 0.

## v1.4.0 — 2026-10-08 — Perbaikan stunnel/tlsmux + guard listen 443 + label vless
### Fixed
- **CRITICAL** `configure-final-443.sh`: `apply_http_tls_listen()` sekarang MENGHAPUS
  `listen 443` / `listen [::]:443` dari `mytunnel.conf` saat menambah `listen 127.0.0.1:9443`.
  Sebelumnya 443 dipegang nginx (http) DAN blok `stream ssl_preread` -> nginx gagal start
  (`bind() to 0.0.0.0:443 failed (98)`) saat reload/restart. Terverifikasi live: skenario
  regresi (listen 443 ada) kini lolos, nginx tetap active.
- `setup/tlsmux.sh`: kini self-contained — tulis `mytunnel-tlsmux.py`, bikin systemd unit
  `mytunnel-tlsmux.service`, install stunnel4 (apt), tulis `/etc/stunnel/stunnel.conf`
  (`accept 127.0.0.1:4443 -> 127.0.0.1:1443`), bikin `stunnel.pem` (cert LE, fallback
  self-signed), bikin unit `mytunnel-stunnel.service`, matikan SysV `stunnel4`.
  Sebelumnya file ini hanya menulis python + chmod; tidak ada unit/conf.

### Changed
- `install.sh`: `setup/tlsmux.sh` kini DIPANGGIL di driver sebagai `[9b/13]` (setelah nginx).
  Sebelumnya ter-embed tapi tidak pernah dieksekusi -> stunnel tak terpasang, prasyarat
  `configure-final-443.sh` tidak terpenuhi.
- Label output create VLESS disederhanakan jadi 5 (sesuai transport yang tersisa):
  `VLESS WS TLS`, `VLESS WS NO TLS`, `VLESS GRPC`, `VLESS Upgrade TLS`, `VLESS Upgrade NO TLS`.
  Baris label XHTTP yang tersisa (dead, tanpa link pasangannya) dihapus.

### Verified (live, VPS 206.189.32.83 / tesc.sunekvip.cc.cd)
- stunnel dihapus (apt remove) -> `tlsmux.sh` memasangnya kembali; unit tlsmux+stunnel active,
  listen 127.0.0.1:1443 dan 127.0.0.1:4443.
- tlsmux routing: banner SSH -> sshd (`SSH-2.0-OpenSSH_8.9p1`), HTTP -> nginx 8080 (204).
- Regresi listen 443: `configure-final-443.sh` menghapus 443, `nginx -t` lulus, nginx active.
- Idempoten: run kedua -> "sistem sudah memakai konfigurasi final — tidak ada yang diubah".
- Transport: WS 443, gRPC 443 pass (exit IP 206.189.32.83); ALPN h2 -> 9443; no-ALPN -> stunnel 4443.

## v1.3.0 — 2026-10-08 — Hapus XHTTP (tidak kompatibel)
### Removed
- XHTTP transport dihapus total dari stack (9 inbounds: ws/grpc/httpupgrade, sebelumnya 12).
- Inbound `vmess-xh`/`vless-xh`/`trojan-xh` (port 10031-10033) dihapus dari config Xray.
- nginx `location /xvmess`, `/xvless`, `/xtrojan` dihapus dari mytunnel-locations.inc.
- Link generator: 2 baris `type=xhttp` per akun vless dihapus; menu info `path xhttp` dihapus.
- Doctor check: ambang "PARSIAL" 4 -> 3 transports.
- Fungsi `_proto_xhttp_path()` dihapus.

### Why
Xray server (26.3.27) memakai `xhttp` dengan path dinamis UUID (`/<uuid>?x_padding=`),
sementara config memakai path statis `/xvmess`. Hasil uji live: handshake selalu 404
dari Xray (nginx routing sudah benar, terbukti via debug log `test location`).
Tidak memperbaiki tanpa menyelaraskan versi klien/server, jadi XHTTP dihapus.

### Verified (live, VPS 206.189.32.83 / tesc.sunekvip.cc.cd)
- WS 443, WS 8443, gRPC 443, HTTPUpgrade 443: exit IP 206.189.32.83 (PASS)
- ALPN `h2`/`http/1.1` -> nginx 9443; tanpa ALPN -> stunnel 4443 (PASS)
- `bash -n` exit 0, shellcheck -S error exit 0, test-mode install PASS

## v1.2.0 — 2026-10-08 — Final 443 stream + traffic fix
### Added
- `configure-final-443.sh` as a separate, idempotent final-443 migration.
- nginx `stream ssl_preread`: ALPN `h2`/`http/1.1` to local `9443`; legacy fallback to stunnel `127.0.0.1:4443`.
- nginx `worker_connections 4096` and `worker_rlimit_nofile 65535`.
- Persistent conntrack tuning: `nf_conntrack_max=65536`, `nf_conntrack_tcp_timeout_established=7200`.
- Timestamped backups, `--dry-run`, `--rollback`, automatic rollback on failed `nginx -t`.

### Fixed
- Traffic iface auto-detect (`_traffic_iface`, `ip route` default) — replaces hardcoded `enp3s0` that broke on `eth0`/`ens3`/`ens18` VPS.
- WIB day bucket single source of truth (`_traffic_day_idx`) — `get_traffic_day`, `get_traffic_rx_tx`, and fallback now read the same `day[]` index (previously inconsistent `-1` vs `-2`).
- `get_traffic_*` use `vnstat --json` + `jq` (robust field mapping vs `--oneline | awk -F';'`); `jq` guard added to fallback.
- `curl -4` on all Telegram API calls (avoids IPv6 failure path).
- Bot long-polling: persist `OFFSET=$((update_id+1))` per update — prevents reprocessing the same message.

### Note
- Traffic helpers verify: `bash -n` OK, shellcheck 0 error, 0 hardcoded iface, day-index unit tests 4/4 PASS.
- Full 443 stream path (nginx `ssl_preread`/ALPN split) still needs LIVE per-transport testing on a real VPS before relying on it in production.

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

