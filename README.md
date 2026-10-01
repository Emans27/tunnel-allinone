# Tunnel All-in-One
Auto Install: Xray (VLESS/VMess/Trojan/SS) + OpenVPN + SSH Dropbear + UDP-Custom + WS + Tunnelcore + HAProxy + Nginx.
## Pakai
```bash
wget -O install.sh https://raw.githubusercontent.com/Emans27/tunnel-allinone/main/tunnel-install.sh && chmod +x install.sh && sudo bash install.sh
```
## File
- tunnel-install.sh — fixed (outbounds/api, jq insert, no upgrade -y, dynamic IF, plugin path fix)
- tunnel-binaries.tar.gz — 17M (xray 1.8.24, ws, udp-mini, udp-custom, badvpn-udpgw)
