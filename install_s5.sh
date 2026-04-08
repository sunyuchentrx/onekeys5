#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

PORT=""
USERNAME=""
PASSWORD=""

usage() {
  cat <<EOF
Usage:
  sudo bash ${SCRIPT_NAME} --port <port> --user <username> --password <password>

Required arguments:
  --port        SOCKS5 listen port
  --user        Username for SOCKS5 authentication
  --password    Password for SOCKS5 authentication

Example:
  sudo bash ${SCRIPT_NAME} --port 1080 --user demo --password 'StrongPass123'
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Please run this script as root or with sudo."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        [[ $# -ge 2 ]] || fail "--port requires a value"
        PORT="$2"
        shift 2
        ;;
      --user)
        [[ $# -ge 2 ]] || fail "--user requires a value"
        USERNAME="$2"
        shift 2
        ;;
      --password)
        [[ $# -ge 2 ]] || fail "--password requires a value"
        PASSWORD="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        fail "Unknown argument: $1"
        ;;
    esac
  done

  [[ -n "${PORT}" ]] || fail "--port is required"
  [[ -n "${USERNAME}" ]] || fail "--user is required"
  [[ -n "${PASSWORD}" ]] || fail "--password is required"
}

validate_args() {
  [[ "${PORT}" =~ ^[0-9]+$ ]] || fail "--port must be a number"
  (( PORT >= 1 && PORT <= 65535 )) || fail "--port must be between 1 and 65535"
  [[ "${USERNAME}" =~ ^[a-zA-Z0-9._-]+$ ]] || fail "--user only supports letters, numbers, dot, underscore and hyphen"
  [[ "${USERNAME}" != "root" ]] || fail "--user cannot be root"
}

detect_package_manager() {
  command -v apt-get >/dev/null 2>&1 || fail "This script supports Debian/Ubuntu with apt-get only."
}

install_packages() {
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y dante-server iproute2 curl
}

create_or_update_user() {
  if id "${USERNAME}" >/dev/null 2>&1; then
    echo "${USERNAME}:${PASSWORD}" | chpasswd
  else
    useradd --system --shell /usr/sbin/nologin --create-home "${USERNAME}"
    echo "${USERNAME}:${PASSWORD}" | chpasswd
  fi
}

detect_interfaces() {
  EXTERNAL_IFACE="$(ip route get 1.1.1.1 | awk '{for (i = 1; i <= NF; i++) if ($i == "dev") {print $(i+1); exit}}')"
  [[ -n "${EXTERNAL_IFACE:-}" ]] || fail "Unable to detect external network interface."

  INTERNAL_IP="$(ip -4 route get 1.1.1.1 | awk '{for (i = 1; i <= NF; i++) if ($i == "src") {print $(i+1); exit}}')"
  [[ -n "${INTERNAL_IP:-}" ]] || fail "Unable to detect server IPv4 address."
}

write_config() {
  cat >/etc/danted.conf <<EOF
logoutput: syslog

internal: 0.0.0.0 port = ${PORT}
external: ${EXTERNAL_IFACE}

socksmethod: username
user.privileged: root
user.unprivileged: nobody
user.libwrap: nobody

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: connect disconnect error
}

client block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}

socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  command: bind connect udpassociate
  log: connect disconnect error
}

socks block {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  log: error
}
EOF
}

restart_service() {
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl restart danted >/dev/null 2>&1; then
      SERVICE_NAME="danted"
      systemctl enable danted >/dev/null 2>&1 || true
    elif systemctl restart dante-server >/dev/null 2>&1; then
      SERVICE_NAME="dante-server"
      systemctl enable dante-server >/dev/null 2>&1 || true
    fi
  fi

  if [[ -z "${SERVICE_NAME:-}" ]] && command -v service >/dev/null 2>&1; then
    if service danted restart >/dev/null 2>&1; then
      SERVICE_NAME="danted"
    elif service dante-server restart >/dev/null 2>&1; then
      SERVICE_NAME="dante-server"
    fi
  fi

  [[ -n "${SERVICE_NAME:-}" ]] || fail "Installed dante-server, but failed to start the service."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl --no-pager --full status "${SERVICE_NAME}" 2>/dev/null | sed -n '1,8p' || true
  elif command -v service >/dev/null 2>&1; then
    service "${SERVICE_NAME}" status || true
  fi
}

detect_public_ip() {
  PUBLIC_IP="$(curl -4 -fsSL --max-time 10 https://api.ipify.org || true)"
  if [[ -z "${PUBLIC_IP}" ]]; then
    PUBLIC_IP="${INTERNAL_IP}"
  fi
}

print_result() {
  cat <<EOF

S5 installation completed.

Connection details:
  Host: ${PUBLIC_IP}
  Port: ${PORT}
  User: ${USERNAME}
  Password: ${PASSWORD}
  Protocol: SOCKS5

Test example:
  curl --proxy socks5h://${USERNAME}:${PASSWORD}@${PUBLIC_IP}:${PORT} https://api.ipify.org

Config file:
  /etc/danted.conf

Service:
  systemctl status ${SERVICE_NAME}
EOF
}

main() {
  require_root
  parse_args "$@"
  validate_args
  detect_package_manager
  install_packages
  create_or_update_user
  detect_interfaces
  write_config
  restart_service
  detect_public_ip
  print_result
}

main "$@"
