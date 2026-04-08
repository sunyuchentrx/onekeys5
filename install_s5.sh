#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
STATE_FILE="/etc/onekeys5.env"
MANAGER_PATH="/usr/local/bin/S5"

PORT=""
USERNAME=""
PASSWORD=""
SERVICE_NAME=""
EXTERNAL_IFACE=""
INTERNAL_IP=""
PUBLIC_IP=""

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

write_state_file() {
  cat >"${STATE_FILE}" <<EOF
PORT='${PORT}'
USERNAME='${USERNAME}'
PASSWORD='${PASSWORD}'
SERVICE_NAME='${SERVICE_NAME}'
PUBLIC_IP='${PUBLIC_IP}'
INTERNAL_IP='${INTERNAL_IP}'
EOF
  chmod 600 "${STATE_FILE}"
}

install_manager() {
  cat >"${MANAGER_PATH}" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

STATE_FILE="/etc/onekeys5.env"

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Please run S5 as root or with sudo."
    exit 1
  fi
}

load_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
  fi

  : "${SERVICE_NAME:=danted}"
  : "${PORT:=unknown}"
  : "${USERNAME:=unknown}"
  : "${PASSWORD:=unknown}"
  : "${PUBLIC_IP:=unknown}"
}

run_service() {
  local action="$1"
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl "${action}" "${SERVICE_NAME}" >/dev/null 2>&1; then
      return 0
    fi
  fi

  if command -v service >/dev/null 2>&1; then
    service "${SERVICE_NAME}" "${action}"
    return 0
  fi

  echo "No supported service manager found."
  return 1
}

show_status() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl status "${SERVICE_NAME}" --no-pager -l || true
  elif command -v service >/dev/null 2>&1; then
    service "${SERVICE_NAME}" status || true
  else
    echo "No supported service manager found."
  fi
}

show_logs() {
  if command -v journalctl >/dev/null 2>&1; then
    journalctl -u "${SERVICE_NAME}" -n 50 --no-pager || true
  elif [[ -f /var/log/syslog ]]; then
    grep -i dante /var/log/syslog | tail -n 50 || true
  else
    echo "No supported log source found."
  fi
}

show_info() {
  load_state
  cat <<INFO
S5 current configuration:
  Host: ${PUBLIC_IP}
  Port: ${PORT}
  User: ${USERNAME}
  Password: ${PASSWORD}
  Service: ${SERVICE_NAME}
INFO
}

uninstall_s5() {
  read -r -p "This will remove dante-server and delete the S5 user. Continue? [y/N]: " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    return 0
  fi

  run_service stop || true
  if command -v apt-get >/dev/null 2>&1; then
    apt-get remove -y dante-server || true
  fi

  if [[ -n "${USERNAME:-}" ]] && id "${USERNAME}" >/dev/null 2>&1; then
    userdel -r "${USERNAME}" >/dev/null 2>&1 || userdel "${USERNAME}" >/dev/null 2>&1 || true
  fi

  rm -f /etc/danted.conf "${STATE_FILE}" /usr/local/bin/S5
  echo "S5 uninstalled."
}

reinstall_hint() {
  echo "Reinstall with:"
  echo "  curl -fsSL https://raw.githubusercontent.com/sunyuchentrx/onekeys5/main/install_s5.sh | sudo bash -s -- --port <port> --user <user> --password '<password>'"
}

menu() {
  while true; do
    clear || true
    load_state
    cat <<MENU
==============================
 S5 Management Menu
==============================
1. Start service
2. Stop service
3. Restart service
4. Show status
5. Show logs
6. Show current config
7. Uninstall S5
8. Reinstall command
0. Exit
MENU
    read -r -p "Select an option: " choice
    case "${choice}" in
      1) run_service start; echo "Started." ;;
      2) run_service stop; echo "Stopped." ;;
      3) run_service restart; echo "Restarted." ;;
      4) show_status ;;
      5) show_logs ;;
      6) show_info ;;
      7) uninstall_s5; exit 0 ;;
      8) reinstall_hint ;;
      0) exit 0 ;;
      *) echo "Invalid option." ;;
    esac
    echo
    read -r -p "Press Enter to continue..." _
  done
}

require_root
load_state
menu
EOF
  chmod 755 "${MANAGER_PATH}"
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

Management:
  Command: S5

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
  write_state_file
  install_manager
  print_result
}

main "$@"
