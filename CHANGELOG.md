# CHANGELOG

## v1.9.6 — 2026-10-12 — fix stream module dynamic + cert 429 tidak lagi matiin install
### Fixed
- **`--with-stream=dynamic` (Debian 12)**: `nginx -V 2>&1 | grep -q -- '--with-stream'`
  ikut match nilai dynamic, sehingga guard `ensure_nginx_stream()` langsung `return 0`
  dan `load_module` tidak pernah ditambahkan — padahal modul `.so` tetap WAJIB dimuat
  lewat `load_module`. Akibatnya blok `stream { listen 443; ssl_preread on; }` tidak
  aktif, `configure-final-443.sh` rollback, dan **443 tidak listen** (80 tetap jalan
  karena tidak butuh modul stream). Semua guard diganti ke `grep -q -- '--with-stream[^=]'`
  supaya hanya static compile yang boleh skip `load_module`.
- **cert 429 / install-cert gagal tidak lagi mematikan install**: log VPS menunjukkan
  `cat: /root/.acme.sh/<domain>_ecc/fullchain.cer: No such file or directory` →
  `✗ File cert kosong setelah issue` → `die`, sehingga VPS terpasang tanpa cert apa pun
  dan 443 mati total (bukan cuma warning browser). `--install-cert` yang gagal atau
  staging yang kosong sekarang memanggil `fallback_selfsigned()` (self-signed 365 hari,
  backup + chmod yang benar) lalu `return 0`, jadi install lanjut dan 443 tetap listen TLS.

### Catatan
- Kegagalan **429 rate limit** Let's Encrypt (`new-certificates-per-exact-set-of-identifiers`,
  5 per 168 jam) adalah limit eksternal LE, tidak bisa diperbaiki dari repo. Reset otomatis
  setelah 7 hari; lalu ulangi dengan `bash /etc/mytunnel/setup/cert.sh --force`.

## v1.9.5 — 2026-10-12 — fix port 443 tidak listen: modul stream nginx tidak pernah dimuat
### Fixed
- **Penyebab utama 443 mati (80 tetap konek)**: nginx dari repo distro (`apt-get install nginx`)
  TIDAK otomatis memuat modul stream. Blok `stream { listen 443; ssl_preread on; }` yang
  dipasang `configure-final-443.sh` membuat `nginx -t` gagal ("unknown directive \"stream\""),
  sehingga script rollback dan 443 tidak pernah listen. HTTP di port 80 tidak butuh modul
  stream — itu sebab 80 konek sementara 443 mati.
- `setup/nginx.sh` `install_nginx()` sekarang memanggil `ensure_nginx_stream()`:
  pasang `libnginx-mod-stream` kalau belum ada, dan tambahkan `load_module modules/ngx_stream_module.so;`
  di baris paling atas nginx.conf (posisi wajib, sebelum `events`/`http`),
  lalu validasi `nginx -t`.
- Install nginx baru memakai `apt-get install -y nginx libnginx-mod-stream` (fallback ke `nginx` saja).
- `configure-final-443.sh` `check_prereq()` tidak lagi `die` kebetulan user tidak punya modul —
  sekarang memasang otomatis, dan menambah `load_module` ke nginx.conf sebelum melanjutkan.
- `configure-final-443.sh` (file fisik) disinkronkan dengan versi embed di `install.sh`.

### Verifikasi
- `bash -n` semua file OK; harness `MYTUNNEL_PREFIX --no-deps` OK.
- `nginx.sh` & `configure-final-443.sh` hasil harness memuat guard (7 dan 9 ref).
- Simulasi penambahan `load_module`: masuk di baris 1, sebelum `events`/`http` — divalidasi grep.

## v1.9.4 — 2026-10-12 — fix Change Domain dan --force + cert.sh idempoten
### Fixed
- `features/domain.sh` (menu 6 -> 9 Change Domain VPS): parsing `CN` dari subject cert
  pakai `sed "s/.*CN *= *//"` yang menghasilkan `new.example.com, o = mytunnel` ketika
  subject mengandung field lain (contoh `O=MyTunnel` dari self-signed). Akibatnya validasi
  "cert harus milik domain baru" salah tolak dan menggagalkan ganti domain. Sekarang pakai
  `-nameopt RFC2253` + split per-field, teruji 3 kasus (CN saja, CN+O, CN huruf besar).
- `setup/cert.sh` tidak punya parser argumen sama sekali, padahal v1.9.3 memberi instruksi
  `bash $ETC/setup/cert.sh --force` ke user. Ditambahkan parser `--force` (paksa issue ulang
  walau cert masih ada) dan `--help`.
- `cert.sh` sekarang idempoten: kalau cert untuk domain itu sudah ada dan masih valid,
  issue di-skip (bukan re-issue tiap kali dipanggil dari step install/change-domain).
  `--force` melewati skip ini — dipakai untuk mengganti self-signed fallback dengan LE asli.
- Pesan setelah fallback self-signed sekarang menyebut reset rate limit 7 hari secara eksplisit.

## v1.9.3 — 2026-10-12 — cert gagal (429 rate limit LE) tidak lagi mati total install
### Fixed
- `setup/cert.sh`: saat ACME gagal (HTTP 429 `too many certificates (5) already issued for
  this exact set of identifiers`, atau DNS belum propagasi), script sebelumnya memanggil
  `die` = `exit 1` sehingga seluruh install berhenti. Sekarang pasang **self-signed
  365 hari** sebagai fallback (cert lama di-backup `.bak-<timestamp>` dulu) dan install
  lanjut sampai selesai, supaya 443/8443/80 tetap listen dan menu/xray/dropbear tetap terpasang.
- Pesan error sekarang menyebut rate limit 5/domain/minggu secara eksplisit, dan petunjuk
  ulangi issue manual: `bash $ETC/setup/cert.sh --force`.
- Cert self-signed tetap memicu warning 'untrusted' di browser (wajar) — ini memang
  fallback sementara sampai rate limit LE reset (7 hari) dan issue ulang dimasukkan.

### Catatan
- Kegagalan 429 Let's Encrypt bukan bug script dan tidak bisa diperbaiki dari repo:
  limit LE = 5 sertifikat per exact set identifier per minggu. Solusi: tunggu reset
  seminggu, atau pakai domain lain, atau pakai DNS-01 challenge.

## v1.9.2 — 2026-10-12 — fix 443 tidak listen + login-report tidak bisa menerima token bot
### Fixed
- **PORT 443 tidak pernah ter-setup**: embed `configure-final-443.sh` menulis ke
  `${BASE}/configure-final-443.sh` yang saat produksi = `/configure-final-443.sh` (root FS),
  tapi `chmod` diarahkan ke `/root/configure-final-443.sh`. File tidak executable sehingga
  blok step `[9d/13]` selalu dilewati. Sekarang keduanya pakai variabel `F443` yang sama
  (`${BASE:-/root}/configure-final-443.sh`).
- step `[9d/13]` sekarang memverifikasi `ss -tln | grep ':443 '` dan `:80 ` setelah setup;
  kalau belum listen, paksa buka UFW + reload nginx, jalankan ulang httpmux, lalu laporkan
  status final ke layar (tidak diam-diam gagal).
- **LOGIN REPORT tidak bisa menerima token bot**: `menu 1` memanggil `lr_sanitize` yang
  tidak pernah didefinisikan di `common.sh`/`collector.sh`/`core.sh`. Akibatnya
  `t=$(lr_sanitize "$t")` menghasilkan string kosong dan token yang diketik user hilang.
  Fungsi `lr_sanitize` sekarang ada (buang karakter di luar `[0-9A-Za-z:_-]`).
- `lr_load_conf` kini memanggil `lr_defaults` lebih dulu: semua variabel config punya nilai
  default, jadi `set -u` tidak lagi melempar "unbound variable" (XRAY_CONFIG, XRAY_ACCESS_LOG,
  dll) saat `/etc/login-report/config.conf` hilang atau rusak.
- `lr_set_conf` membuat `config.conf` dari template default bila file belum ada, sehingga
  menu 1 tetap bisa menyimpan token pada instalasi baru.
- `lr_log` memilih path fallback writable (`$TMPDIR/login-report.log`) bila `/var/log` tidak bisa ditulis.
- `LR_BASE`/`LR_CONF`/`LR_LOG` di `core.sh`, `menu.sh`, `common.sh` kini memakai `${VAR:-default}`
  agar bisa di-override (test mode) tanpa mengubah perilaku produksi.
- dispatcher menu 10 tidak lagi membuang stderr (`2>/dev/null` dihapus) dan punya fallback ke
  `/etc/mytunnel/login-report/menu.sh`; kode error ditampilkan sebagai `rc=$?`.
- semua fungsi `lr_*` yang dipanggil sudah terdefinisi (scan otomatis: 0 missing).

## v1.9.1 — 2026-10-12 — install 1-perintah tanpa setting lanjutan + login-report token bisa dimasukan
### Fixed
- login-report: `/etc/login-report/config.conf` dijamin ada saat install. Sebelumnya blok copy
  hanya jalan kalau `[ -d /etc/login-report ]` dan `install -d -m 700` gagal (non-root),
  sehingga `lr_load_conf` gagal "config tidak ada" dan menu (10) tidak bisa menerima
  BOT_TOKEN / CHAT_ID. Sekarang ada fallback default berisi semua key.
- login-report: semua path install ikut prefix (`$BASE`) sehingga test mode `MYTUNNEL_PREFIX`
  tidak lagi gagal "Permission denied" saat menulis unit systemd.
- domain & brand diambil otomatis dari env atau `/etc/mytunnel/*.txt`; tidak ada lagi
  prompt konfirmasi install yang menggantung di piped input.
- brand fallback stabil ke "SUNEK VPN" (bukan "My Brand").

## v1.9.0 — 2026-10-11 — brand permanen total (tidak bisa diubah lewat jalur mana pun) + bersihkan referensi skrip lama
### Fixed
- brand permanen 4 lapis: chattr +i, canon 600 root-only, cron tiap menit, dan bg_set() menolak tanpa jalur bypass
- --brand dan MYTUNNEL_BRAND sekarang diabaikan bila brand.txt sudah immutable
- embed config/brand.txt tidak menimpa file yang sudah terkunci
- menu SET BRAND NAME (8) sepenuhnya read-only; jalur "FORCE" dihapus (dead code)
- bg_set() tidak lagi menerima parameter force sama sekali

## v1.8.1 — 2026-10-11 — brand permanen total + login-report menu 10
### Fixed
- brand_guard: brand.txt dipaksa kembali ke canon tiap menit, canon jadi 600 root-only
- brand_guard: bg_set menolak kalau sudah terkunci (return 2) — tak bisa diubah tanpa FORCE
- menu SET BRAND NAME (8) jadi read-only; perlu ketik FORCE eksplisit untuk mengubah
- config/repo.txt default disamakan ke tunnel-allinone (bukan mytunnel-installer)
### Added
- login-report: menu 10 (laporan user aktif ke Telegram via systemd timer)
- login-report: core.sh dipasang 755 (fix systemd 203/EXEC)

## v1.8.0 — 2026-10-09 — IP publik salah baca (IPv6) + xray live-apply tanpa restart
### Fixed
- `get_ip_cached()` dan `ah_get_ip()` memakai `curl` tanpa `-4`, sehingga di host
  dual-stack hasilnya bisa IPv6 (`2400:6180:...`) dan muncul di menu IP/client,
  WARP, SlowDNS, dan notifikasi bot. Keduanya sekarang memaksa IPv4 (`curl -s4`)
  dan mem-parse ulang hasilnya dengan regex IPv4; fallback `hostname -I` (yang
  mengembalikan IPv6 lebih dulu) juga difilter.
- `features/domain.sh`: `pub_ip` untuk pengecekan A-record ikut dipaksa IPv4 —
  sebelumnya bisa membandingkan A-record IPv4 dengan IP publik IPv6 dan
  melaporkan mismatch palsu.

### Added
- `_xray_live_apply()` di `lib/xray_helpers.sh`: add/del client dikirim ke instance
  Xray yang sedang berjalan lewat Xray API (HandlerService, `xray api adu/rmu`),
  lalu menulis flag `/run/mytunnel-live-apply` yang membuat `xray_reload()` melewati
  restart. Klien baru langsung aktif tanpa memutus sesi lain.
- `cron/bot_notify.sh` memuat `features_helpers.sh` (helper `fh_*` sebelumnya tidak
  tersedia di konteks cron).

### Verified (live, VPS <VPS-IP>)
- IPv6 `<VPS-IPv6>` -> regex tolak (`[]`), IPv4 -> `<VPS-IP>`.
- `ah_get_ip` = `get_ip_cached` = `<VPS-IP>`.
- Repo <-> VPS: 70/70 file embedded identik (diff per-blok + tar pull ulang).
- `bash -n` seluruh 70 blok + `install.sh` = 0 error.

## v1.7.1 — 2026-10-08 — Port 80 (SSH + enhanced mode) tidak pernah terpasang
### Fixed
- `setup/httpmux.sh` ada di installer tapi **driver tidak pernah memanggilnya**, jadi
  `mytunnel-httpmux` (listener :80) tidak pernah jalan. Akibatnya port 80 dipegang
  server default bawaan paket nginx (`sites-enabled/default`, halaman "Welcome to nginx")
  dan bukan oleh mux mytunnel -> SSH port 80 dan enhanced mode HTTP Custom mati.
  Driver sekarang memanggilnya di tahap baru `[9c/13]` setelah nginx + tlsmux.
- `install_httpmux()` sekarang menjalankan `_free_port80` lebih dulu: `sites-enabled/default`
  yang memegang `listen 80 default_server` dipindah ke `/root/backup/` lalu nginx direload.
  Tanpa ini httpmux gagal bind :80 (EADDRINUSE).
- `mytunnel-httpmux.py` hanya punya dua cabang (CONNECT -> SSH, sisanya -> nginx :8080),
  sehingga **raw SSH** di port 80 (klien mengirim banner `SSH-2.0-...`) dilempar ke nginx
  dan menggantung sampai timeout. Ditambah deteksi banner SSH + cabang ketiga
  `is_rawssh` yang meneruskan langsung ke SSH :22. Loop pembaca header juga berhenti
  lebih awal saat melihat banner SSH (banner tidak pernah memuat `\r\n\r\n`, jadi
  tanpa itu selalu menunggu sampai timeout).
- Peringatan "masih ada listener di :80" tidak lagi muncul saat httpmux sendiri yang
  memegang port itu.

### Verified (live, VPS <VPS-IP>, dari host luar)
- `mytunnel-httpmux` active, listener `0.0.0.0:80`; `/etc/nginx/sites-enabled/` kosong.
- HTTP biasa :80 -> 204 (diteruskan ke nginx :8080).
- Raw SSH :80 -> banner `SSH-2.0-OpenSSH_8.9p1 Ubuntu-3ubuntu0.17` + key exchange;
  `ssh -p 80` dari luar berhasil sampai MOTD.
- CONNECT enhanced :80 -> `HTTP/1.1 200 Connection Established` + banner SSH.
- `bash -n` + shellcheck -S error = 0 (install.sh); python `py_compile` OK.

## v1.7.0 — 2026-10-08 — Fix UDP-Custom (1-65535) tidak pernah terpasang
### Fixed
- `setup/udp-custom.sh` menunjuk URL rilis yang **404**
  (`.../releases/latest/download/udp-custom`) sehingga binary tidak pernah terunduh.
  Diganti ke lokasi file yang benar + **SHA256 dipin** dan diverifikasi sebelum
  binary dipasang (gagal = batal, tidak dieksekusi).
- `--listen $range` adalah flag yang **tidak ada** di binary ePro v1.4. Field
  `listen` hanya menerima **satu port**; rentang 1-65535 ditangani binary lewat
  iptables DNAT (PREROUTING) untuk semua port kecuali `--exclude`.
  Unit systemd diperbaiki jadi `server --config <json> --exclude <ports>`.
- Config JSON `/etc/udp/config.json` tidak pernah dibuat (script lama hanya menulis
  file shell vars). Sekarang dibuat dengan `listen`, buffer, dan auth.
- Rule firewall tidak pernah ditambahkan sehingga UDP tetap diblokir. Karena DNAT
  terjadi sebelum filter/INPUT, firewall melihat port hasil terjemahan — jadi rule
  yang benar hanya `LISTEN_PORT/udp` (bukan seluruh rentang). `ufw allow` ditambah
  otomatis (install) dan dihapus saat uninstall.
- `_status` / `_install` / `_uninstall` dirapikan: cek SHA, laporan jumlah DNAT,
  pembersihan DNAT saat uninstall, perbaikan interpolasi warna (`${RED:-...}`) yang
  kehilangan kurung kurawal.
- `_mt_port_active`: kenali `udp-custom` di samping `mytunnel-udp-custom`.

### Verified (live, VPS <VPS-IP>)
- `udp-custom` active, listen UDP :36712; 22 DNAT rule (1-65535 minus exclude).
- SHA256 binary cocok dengan yang dipin.
- Paket uji dari luar ke port acak dalam rentang: DNAT + INPUT ACCEPT naik,
  tidak ada UFW BLOCK, sampai ke socket aplikasi.
- `bash -n` + shellcheck -S error: 0 pada install.sh dan script embedded.

## v1.6.2 — 2026-10-08 — Notif recovery disamakan + hapus ssh_compact_line
### Changed
- `do_recovery()` (menu SSH no. 11/12): notif Telegram kini pakai
  `ah_notify_admin_mono "$(ssh_account_block ...)"` -> blok penuh mono per baris,
  sama seperti create/trial (sebelumnya satu baris `host:443@u:p & host:80@u:p`).

### Removed
- `ssh_compact_line()` — sudah tidak dipakai siapa pun (dead code).

## v1.6.1 — 2026-10-08 — Baris ringkas SSH dipisah jadi 2 baris
### Changed
- `ssh_account_block()`: baris ringkas akun SSH kini **dua baris terpisah**
  (`host:443@user:pass` lalu `host:80@user:pass`), bukan satu baris digabung spasi.
- Di Telegram, tiap baris tetap dibungkus `<code>` sendiri -> dua chip mono terpisah.

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

### Verified (live, VPS <VPS-IP> / <DOMAIN>)
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
- Harness: baris ringkas = `<DOMAIN>:443@<user>:<pass> & <DOMAIN>:80@<user>:<pass>`;
  notif Telegram = `` `<DOMAIN>:443@<user>:<pass> & <DOMAIN>:80@<user>:<pass>` ``;
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

### Verified (live, VPS <VPS-IP> / <DOMAIN>)
- stunnel dihapus (apt remove) -> `tlsmux.sh` memasangnya kembali; unit tlsmux+stunnel active,
  listen 127.0.0.1:1443 dan 127.0.0.1:4443.
- tlsmux routing: banner SSH -> sshd (`SSH-2.0-OpenSSH_8.9p1`), HTTP -> nginx 8080 (204).
- Regresi listen 443: `configure-final-443.sh` menghapus 443, `nginx -t` lulus, nginx active.
- Idempoten: run kedua -> "sistem sudah memakai konfigurasi final — tidak ada yang diubah".
- Transport: WS 443, gRPC 443 pass (exit IP <VPS-IP>); ALPN h2 -> 9443; no-ALPN -> stunnel 4443.

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

### Verified (live, VPS <VPS-IP> / <DOMAIN>)
- WS 443, WS 8443, gRPC 443, HTTPUpgrade 443: exit IP <VPS-IP> (PASS)
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
- Traffic iface auto-detect (`_traffic_iface`, `ip route` default) — replaces hardcoded `<iface>` that broke on `eth0`/`<iface>`/`ens18` VPS.
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

