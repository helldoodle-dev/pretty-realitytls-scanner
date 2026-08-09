#!/usr/bin/env bash
#
# vless-all.sh — one-command deploy of
#   VLESS + Reality   (TCP + XTLS Vision, port 443)
#   VLESS + WebSocket (no TLS, port 8080)
#   VLESS + TCP       (plain, port 8443)
#   VLESS + XHTTP     (no TLS, port 8444)
#   VLESS + gRPC      (no TLS, port 2096)
# on Xray-core or sing-box. No web panels.
#
# Usage:
#   sudo bash vless-all.sh                     # core: xray
#   sudo bash vless-all.sh -c sing-box         # core: sing-box
#   sudo bash vless-all.sh --ws-port 80 --tcp-port 2053
#
# All options are optional — default runs fully non-interactive.

set -uo pipefail

# ── Colors ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────
CORE="xray"
UUID=""
REALITY_DEST="vk.ru"
REALITY_PORT=443
WS_PORT=8080
TCP_PORT=8443
XHTTP_PORT=8444
GRPC_PORT=2096
DOMAIN=""
SERVER_IP_OVERRIDE=""
NO_FIREWALL=0
INFO_FILE="/root/vless-info.txt"

usage() {
  cat <<'EOF'
Usage: sudo bash vless-all.sh [options]

Deploys VLESS+Reality, VLESS+WebSocket, VLESS+TCP, VLESS+XHTTP and
VLESS+gRPC on Xray-core or sing-box in one command. Non-interactive.

Options:
  -c, --core xray|sing-box   Core engine (default: xray)
  -u, --uuid <uuid>          Client UUID (default: random)
  -d, --reality-dest <host>  Reality target/SNI (default: vk.ru)
  -p, --reality-port <port>  Reality listen port (default: 443)
      --ws-port <port>       WebSocket listen port (default: 8080)
      --tcp-port <port>      Plain TCP listen port (default: 8443)
      --xhttp-port <port>    XHTTP listen port (default: 8444)
      --grpc-port <port>     gRPC listen port (default: 2096)
      --domain <host>        Server public domain/IP used as transport Host
      --server-ip <ip>       IP used inside the generated links (default: auto-detect)
      --no-firewall          Do not touch firewall rules
      --info-file <path>     Where to save client info (default: /root/vless-info.txt)
  -h, --help                 Show this help
EOF
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    -c|--core)          CORE="$2"; shift 2 ;;
    -u|--uuid)          UUID="$2"; shift 2 ;;
    -d|--reality-dest)  REALITY_DEST="$2"; shift 2 ;;
    -p|--reality-port)  REALITY_PORT="$2"; shift 2 ;;
    --ws-port)          WS_PORT="$2"; shift 2 ;;
    --tcp-port)         TCP_PORT="$2"; shift 2 ;;
    --xhttp-port)       XHTTP_PORT="$2"; shift 2 ;;
    --grpc-port)        GRPC_PORT="$2"; shift 2 ;;
    --domain)           DOMAIN="$2"; shift 2 ;;
    --server-ip)        SERVER_IP_OVERRIDE="$2"; shift 2 ;;
    --no-firewall)      NO_FIREWALL=1; shift ;;
    --info-file)        INFO_FILE="$2"; shift 2 ;;
    -h|--help)          usage ;;
    *) echo -e "${RED}Unknown option: $1${NC}"; usage ;;
  esac
done

case "$CORE" in
  xray|sing-box|singbox|sing) : ;;
  *) echo -e "${RED}Unknown core: ${CORE} (use xray or sing-box)${NC}"; exit 1 ;;
esac
[ "$CORE" = "singbox" ] && CORE="sing-box"
[ "$CORE" = "sing" ] && CORE="sing-box"

# ── Root check ────────────────────────────────────────────────
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo -e "${RED}Run as root: sudo bash $0${NC}"
  exit 1
fi

# ── Helpers ───────────────────────────────────────────────────
log() { echo "[$(date '+%H:%M:%S')] $*"; }

detect_pkg() {
  if   command -v apt-get >/dev/null 2>&1; then PKG="apt"
  elif command -v dnf     >/dev/null 2>&1; then PKG="dnf"
  elif command -v yum     >/dev/null 2>&1; then PKG="yum"
  elif command -v apk     >/dev/null 2>&1; then PKG="apk"
  else echo -e "${RED}Unsupported distro (only Debian/Ubuntu, RHEL/CentOS/Fedora, Alpine).${NC}"; exit 1
  fi
}

install_deps() {
  log "Installing dependencies (curl, openssl, ca-certificates)..."
  case "$PKG" in
    apt) apt-get update -qq >/dev/null 2>&1
         apt-get install -y -qq curl openssl ca-certificates jq >/dev/null 2>&1 ;;
    dnf) dnf install -y -q curl openssl ca-certificates jq >/dev/null 2>&1 ;;
    yum) yum install -y -q curl openssl ca-certificates jq >/dev/null 2>&1 ;;
    apk) apk add --no-cache curl openssl ca-certificates jq >/dev/null 2>&1 ;;
  esac
}

get_public_ip() {
  local ip=""
  ip=$(curl -4 -s --max-time 5 https://api.ipify.org 2>/dev/null) \
    || ip=$(curl -4 -s --max-time 5 https://ifconfig.me 2>/dev/null) \
    || ip=$(curl -4 -s --max-time 5 https://icanhazip.com 2>/dev/null) \
    || ip=""
  echo "$ip" | tr -d '[:space:]'
}

# ── Core install ──────────────────────────────────────────────
install_xray() {
  log "Installing Xray-core..."
  bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh) install >/dev/null 2>&1 || {
    echo -e "${RED}Xray install failed.${NC}"; return 1; }
  command -v xray >/dev/null 2>&1 || { echo -e "${RED}xray binary not found.${NC}"; return 1; }
  log "$(xray version 2>/dev/null | head -1)"
}

install_singbox() {
  log "Installing sing-box..."
  bash <(curl -fsSL https://sing-box.app/install) >/dev/null 2>&1 || {
    echo -e "${RED}sing-box install failed.${NC}"; return 1; }
  command -v sing-box >/dev/null 2>&1 || { echo -e "${RED}sing-box binary not found.${NC}"; return 1; }
  log "$(sing-box version 2>/dev/null | head -1)"
}

# ── Key generation ────────────────────────────────────────────
gen_uuid() {
  if [ -z "$UUID" ]; then
    if command -v xray >/dev/null 2>&1; then
      UUID="$(xray uuid 2>/dev/null | tr -d '[:space:]')"
    elif command -v sing-box >/dev/null 2>&1; then
      UUID="$(sing-box generate uuid 2>/dev/null | tr -d '[:space:]')"
    fi
  fi
  [ -z "$UUID" ] && UUID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '[:space:]')"
  if [ -z "$UUID" ]; then
    echo -e "${RED}Cannot generate UUID.${NC}"
    return 1
  fi
  return 0
}

gen_reality_keys() {
  local raw=""
  if [ "$CORE" = "xray" ]; then
    raw="$(xray x25519 2>/dev/null || true)"
    PRIVATE_KEY="$(echo "$raw" | sed -n '1p' | awk '{print $NF}')"
    PUBLIC_KEY="$(echo "$raw" | sed -n '2p' | awk '{print $NF}')"
    [ -z "$PUBLIC_KEY" ] && PUBLIC_KEY="$(xray x25519 -i "$PRIVATE_KEY" 2>/dev/null | tail -1 | awk '{print $NF}')"
  else
    raw="$(sing-box generate reality-keypair 2>/dev/null || true)"
    PRIVATE_KEY="$(echo "$raw" | sed -n 's/^PrivateKey: //p')"
    PUBLIC_KEY="$(echo "$raw" | sed -n 's/^PublicKey: //p')"
  fi
  if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}Reality key generation failed. Raw output:${NC}"; echo "$raw"; return 1
  fi
  return 0
}

gen_short_id() {
  SHORT_ID="$(openssl rand -hex 8 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 16)"
}

gen_ws_path() {
  WS_PATH="$(openssl rand -hex 6 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 12)"
  WS_PATH="/${WS_PATH}"
  WS_PATH_URL="$(printf '%s' "$WS_PATH" | sed 's|/|%2F|')"
}

gen_xhttp_path() {
  XHTTP_PATH="$(openssl rand -hex 6 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 12)"
  XHTTP_PATH="/${XHTTP_PATH}"
  XHTTP_PATH_URL="$(printf '%s' "$XHTTP_PATH" | sed 's|/|%2F|')"
}

gen_grpc_service() {
  GRPC_SERVICE="$(openssl rand -hex 8 2>/dev/null || tr -dc 'a-f0-9' </dev/urandom | head -c 16)"
}

# ── Configs ───────────────────────────────────────────────────
write_xray_config() {
  local config="/usr/local/etc/xray/config.json"
  mkdir -p "$(dirname "$config")"
  cat > "$config" <<EOF
{
  "log": { "loglevel": "warning", "access": "none" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": ${REALITY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}", "flow": "xtls-rprx-vision" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}:443",
          "serverNames": [ "${REALITY_DEST}" ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [ "${SHORT_ID}" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    },
    {
      "listen": "0.0.0.0",
      "port": ${WS_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${WS_PATH}" }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    },
    {
      "listen": "0.0.0.0",
      "port": ${TCP_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}" } ],
        "decryption": "none"
      },
      "streamSettings": { "network": "tcp", "security": "none" },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    },
    {
      "listen": "0.0.0.0",
      "port": ${XHTTP_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "none",
        "xhttpSettings": { "path": "${XHTTP_PATH}", "mode": "stream-up" }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    },
    {
      "listen": "0.0.0.0",
      "port": ${GRPC_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [ { "id": "${UUID}" } ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "none",
        "grpcSettings": { "serviceName": "${GRPC_SERVICE}" }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls", "quic" ] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      { "type": "field", "ip": [ "geoip:private" ], "outboundTag": "block" },
      { "type": "field", "protocol": [ "bittorrent" ], "outboundTag": "block" }
    ]
  }
}
EOF
}

write_singbox_config() {
  local config="/etc/sing-box/config.json"
  mkdir -p "$(dirname "$config")"
  cat > "$config" <<EOF
{
  "log": { "level": "warn" },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality",
      "listen": "0.0.0.0",
      "listen_port": ${REALITY_PORT},
      "users": [ { "uuid": "${UUID}", "flow": "xtls-rprx-vision" } ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DEST}",
        "reality": {
          "enabled": true,
          "handshake": { "server": "${REALITY_DEST}", "server_port": 443 },
          "private_key": "${PRIVATE_KEY}",
          "short_id": [ "${SHORT_ID}" ]
        }
      }
    },
    {
      "type": "vless",
      "tag": "vless-ws",
      "listen": "0.0.0.0",
      "listen_port": ${WS_PORT},
      "users": [ { "uuid": "${UUID}" } ],
      "transport": { "type": "ws", "path": "${WS_PATH}" }
    },
    {
      "type": "vless",
      "tag": "vless-tcp",
      "listen": "0.0.0.0",
      "listen_port": ${TCP_PORT},
      "users": [ { "uuid": "${UUID}" } ]
    },
    {
      "type": "vless",
      "tag": "vless-xhttp",
      "listen": "0.0.0.0",
      "listen_port": ${XHTTP_PORT},
      "users": [ { "uuid": "${UUID}" } ],
      "transport": { "type": "httpupgrade", "path": "${XHTTP_PATH}" }
    },
    {
      "type": "vless",
      "tag": "vless-grpc",
      "listen": "0.0.0.0",
      "listen_port": ${GRPC_PORT},
      "users": [ { "uuid": "${UUID}" } ],
      "transport": { "type": "grpc", "service_name": "${GRPC_SERVICE}" }
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ]
}
EOF
}

# ── Systemd ───────────────────────────────────────────────────
stop_existing() {
  local svc
  if [ "$CORE" = "xray" ]; then svc="xray"; else svc="sing-box"; fi
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    systemctl stop "$svc" 2>/dev/null || true
    log "Stopped old ${svc} — old keys/ports freed."
  fi
}

check_ports() {
  local busy=""
  [ "$REALITY_PORT" -ge 1 ] && [ "$REALITY_PORT" -le 65535 ] || { echo -e "${RED}Invalid reality port: ${REALITY_PORT}${NC}"; return 1; }
  [ "$WS_PORT" -ge 1 ] && [ "$WS_PORT" -le 65535 ] || { echo -e "${RED}Invalid ws port: ${WS_PORT}${NC}"; return 1; }
  [ "$TCP_PORT" -ge 1 ] && [ "$TCP_PORT" -le 65535 ] || { echo -e "${RED}Invalid tcp port: ${TCP_PORT}${NC}"; return 1; }
  [ "$XHTTP_PORT" -ge 1 ] && [ "$XHTTP_PORT" -le 65535 ] || { echo -e "${RED}Invalid xhttp port: ${XHTTP_PORT}${NC}"; return 1; }
  [ "$GRPC_PORT" -ge 1 ] && [ "$GRPC_PORT" -le 65535 ] || { echo -e "${RED}Invalid grpc port: ${GRPC_PORT}${NC}"; return 1; }
  local uniq
  uniq="$(printf '%s\n' "$REALITY_PORT" "$WS_PORT" "$TCP_PORT" "$XHTTP_PORT" "$GRPC_PORT" | sort -u | wc -l)"
  [ "$uniq" -eq 5 ] || { echo -e "${RED}Ports must differ: ${REALITY_PORT} / ${WS_PORT} / ${TCP_PORT} / ${XHTTP_PORT} / ${GRPC_PORT}${NC}"; return 1; }
  for p in "$REALITY_PORT" "$WS_PORT" "$TCP_PORT" "$XHTTP_PORT" "$GRPC_PORT"; do
    if ss -tln 2>/dev/null | grep -q ":${p} "; then
      busy="${busy} ${p}"
    fi
  done
  if [ -n "$busy" ]; then
    echo -e "${RED}Port(s) already in use:${busy}. Pick free ones, e.g. -p 8443 --ws-port 8080 --tcp-port 2053${NC}"
    return 1
  fi
  return 0
}

enable_service() {
  local svc
  if [ "$CORE" = "xray" ]; then svc="xray"; else svc="sing-box"; fi
  systemctl daemon-reload
  systemctl enable "$svc" >/dev/null 2>&1 || true
  systemctl restart "$svc" || { echo -e "${RED}${svc} failed to start:${NC}"; journalctl -u "$svc" -n 30 --no-pager; return 1; }
  log "${svc} is running."
}

# ── Firewall ──────────────────────────────────────────────────
open_firewall() {
  [ "$NO_FIREWALL" -eq 1 ] && return 0
  local ports=("$REALITY_PORT" "$WS_PORT" "$TCP_PORT" "$XHTTP_PORT" "$GRPC_PORT")
  if command -v ufw >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      ufw allow "${p}/tcp" comment 'vless' >/dev/null 2>&1 || true
    done
    ufw status >/dev/null 2>&1 || ufw --force enable >/dev/null 2>&1
    log "UFW: ports ${ports[*]} opened."
  elif command -v firewall-cmd >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      firewall-cmd --permanent --add-port="${p}/tcp" >/dev/null 2>&1 || true
    done
    firewall-cmd --reload >/dev/null 2>&1 || true
    log "firewalld: ports ${ports[*]} opened."
  elif command -v iptables >/dev/null 2>&1; then
    for p in "${ports[@]}"; do
      iptables -C INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1 \
        || iptables -I INPUT -p tcp --dport "$p" -j ACCEPT >/dev/null 2>&1
    done
    log "iptables: ports ${ports[*]} opened (not persisted)."
  fi
}

# ── Links ─────────────────────────────────────────────────────
print_links() {
  local wshost="${DOMAIN:-$SERVER_IP}"
  local link_reality link_ws link_tcp link_xhttp link_grpc

  link_xhttp="vless://${UUID}@${SERVER_IP}:${XHTTP_PORT}?encryption=none&security=none&type=httpupgrade&path=${XHTTP_PATH_URL}&host=${wshost}#VLESS-XHTTP-${XHTTP_PORT}"
  link_grpc="vless://${UUID}@${SERVER_IP}:${GRPC_PORT}?encryption=none&security=none&type=grpc&mode=gun&serviceName=${GRPC_SERVICE}&host=${wshost}#VLESS-gRPC-${GRPC_PORT}"
  link_reality="vless://${UUID}@${SERVER_IP}:${REALITY_PORT}?encryption=none&security=reality&type=tcp&flow=xtls-rprx-vision&fp=qq&sni=${REALITY_DEST}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}#VLESS-Reality-${REALITY_PORT}"
  link_ws="vless://${UUID}@${SERVER_IP}:${WS_PORT}?encryption=none&type=ws&path=${WS_PATH_URL}&host=${wshost}#VLESS-WS-${WS_PORT}"
  link_tcp="vless://${UUID}@${SERVER_IP}:${TCP_PORT}?encryption=none&type=tcp#VLESS-TCP-${TCP_PORT}"

  cat > "$INFO_FILE" <<EOF
════════════════════════════════════════════════════════
  VLESS All-in-One — connection details
  Core: ${CORE}   Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
════════════════════════════════════════════════════════

Server IP   : ${SERVER_IP}
UUID        : ${UUID}
Public Key  : ${PUBLIC_KEY}
Short ID    : ${SHORT_ID}
SNI/Reality : ${REALITY_DEST}
WS path     : ${WS_PATH}
XHTTP path  : ${XHTTP_PATH}
gRPC name   : ${GRPC_SERVICE}
Host        : ${wshost}

1) VLESS + Reality  (port ${REALITY_PORT}):
${link_reality}

2) VLESS + WebSocket  (port ${WS_PORT}):
${link_ws}

3) VLESS + TCP  (port ${TCP_PORT}):
${link_tcp}

4) VLESS + XHTTP  (port ${XHTTP_PORT}):
${link_xhttp}

5) VLESS + gRPC  (port ${GRPC_PORT}):
${link_grpc}
════════════════════════════════════════════════════════
EOF

  echo ""
  echo -e "${CYAN}╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║          ✅  Ready to connect (${CORE})${NC}${CYAN}            ║${NC}"
  echo -e "${CYAN}╚═══════════════════════════════════════════════════╝${NC}"
  echo -e "  ${BOLD}Server${NC}    : ${SERVER_IP}"
  echo -e "  ${BOLD}UUID${NC}      : ${UUID}"
  echo ""
  echo -e "${BOLD}${GREEN}[1] VLESS + Reality (port ${REALITY_PORT})${NC}"
  echo -e "${GREEN}${link_reality}${NC}"
  echo ""
  echo -e "${BOLD}${GREEN}[2] VLESS + WebSocket (port ${WS_PORT})${NC}"
  echo -e "${GREEN}${link_ws}${NC}"
  echo ""
  echo -e "${BOLD}${GREEN}[3] VLESS + TCP (port ${TCP_PORT})${NC}"
  echo -e "${GREEN}${link_tcp}${NC}"
  echo ""
  echo -e "${BOLD}${GREEN}[4] VLESS + XHTTP (port ${XHTTP_PORT})${NC}"
  echo -e "${GREEN}${link_xhttp}${NC}"
  echo ""
  echo -e "${BOLD}${GREEN}[5] VLESS + gRPC (port ${GRPC_PORT})${NC}"
  echo -e "${GREEN}${link_grpc}${NC}"
  echo ""
  if command -v qrencode >/dev/null 2>&1; then
    echo -e "${YELLOW}══════════ QR: Reality ══════════${NC}"
    qrencode -t ANSIUTF8 -m 2 "$link_reality"
    echo -e "${YELLOW}═════════════════════════════════${NC}"
  fi
  echo -e "${CYAN}📁 Details saved: ${BOLD}${INFO_FILE}${NC}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}⚙  VLESS All-in-One deployer (core: ${BOLD}${CORE}${NC}${CYAN})${NC}"

stop_existing
check_ports || exit 1

detect_pkg
install_deps

SERVER_IP="$(get_public_ip)"
[ -z "$SERVER_IP" ] && SERVER_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$SERVER_IP" ] && { echo -e "${RED}Cannot determine server IP.${NC}"; exit 1; }
[ -n "$SERVER_IP_OVERRIDE" ] && SERVER_IP="$SERVER_IP_OVERRIDE"
log "Server IP: ${SERVER_IP}"

if [ "$CORE" = "xray" ]; then install_xray || exit 1; else install_singbox || exit 1; fi

gen_uuid        || exit 1
gen_reality_keys || exit 1
gen_short_id
gen_ws_path
gen_xhttp_path
gen_grpc_service

log "UUID=${UUID}  Reality dest=${REALITY_DEST}  WS path=${WS_PATH}  XHTTP path=${XHTTP_PATH}  gRPC=${GRPC_SERVICE}"

if [ "$CORE" = "xray" ]; then write_xray_config; else write_singbox_config; fi

if command -v jq >/dev/null 2>&1; then
  cfg_file=""
  [ "$CORE" = "xray" ] && cfg_file="/usr/local/etc/xray/config.json" || cfg_file="/etc/sing-box/config.json"
  if ! jq -e . "$cfg_file" >/dev/null 2>&1; then
    echo -e "${RED}Invalid generated config: ${cfg_file}${NC}"
    exit 1
  fi
fi

enable_service || exit 1
open_firewall
print_links