#!/usr/bin/env bash
# RustDesk Server OSS installer for Ubuntu / Debian (systemd).
# Run: sudo bash install-rustdesk.sh
set -Eeuo pipefail
export LC_ALL=C
umask 077
BASE=/rustdesk-server
COMPOSE="$BASE/compose.yml"
C='' G='' Y='' R='' Z=''
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
  C=$'\e[1;36m'; G=$'\e[1;32m'; Y=$'\e[1;33m'; R=$'\e[1;31m'; Z=$'\e[0m'
fi
info() { printf '%s%s%s\n' "$C" "$*" "$Z"; }
ok() { printf '%s%s%s\n' "$G" "$*" "$Z"; }
die() { printf '%sERROR: %s%s\n' "$R" "$*" "$Z" >&2; exit 1; }
trap 'printf "\n%sError on line %s. Operation stopped; existing data has not been automatically rolled back.%s\n" "$R" "$LINENO" "$Z" >&2' ERR
[[ $EUID -eq 0 ]] || die 'Please run: sudo bash install-rustdesk.sh'
[[ -t 0 ]] || die 'This script requires an interactive terminal.'
confirm() { local answer; read -r -p "$1 [n/Y]: " answer; [[ -z $answer || $answer =~ ^([yY]|[yY][eE][sS])$ ]]; }
pause() { read -r -p 'Press Enter to return to the menu ...' _; }
dc() { docker compose --project-name rustdesk-server -f "$COMPOSE" "$@"; }
require_stack() { [[ -f $COMPOSE ]] || die "No installation found at $COMPOSE."; }
banner() {
  printf '%s' "$C"
  cat <<'LOGO'
  ____            _   ____            _
 |  _ \ _   _ ___| |_|  _ \  ___  ___| | __
 | |_) | | | / __| __| | | |/ _ \/ __| |/ /
 |  _ <| |_| \__ \ |_| |_| |  __/\__ \   <
 |_| \_\\__,_|___/\__|____/ \___||___/_|\_\
             SERVER OSS | DOCKER
LOGO
  printf '%s\n' "$Z"
}
docker_ready() {
  if ! docker info >/dev/null 2>&1; then
    systemctl start docker
  fi
  docker info >/dev/null 2>&1 || die 'Docker daemon is not available.'
  docker compose version >/dev/null 2>&1 || die 'Docker Compose plugin is missing. Please complete your existing Docker installation.'
}
install_docker() {
  if command -v docker >/dev/null 2>&1; then
    info 'Using the existing Docker installation.'
    docker_ready
    return
  fi
  [[ -f /etc/os-release ]] || die 'Unable to identify the operating system.'
  . /etc/os-release
  [[ $ID == ubuntu || $ID == debian ]] || die 'Automatic Docker installation supports Ubuntu and Debian only.'
  command -v systemctl >/dev/null || die 'systemd is required.'
  local package
  for package in docker.io docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q '^install ok installed$'; then
      die "Package $package may conflict with Docker CE. Review your existing container runtime first. No packages have been removed."
    fi
  done
  info 'Installing Docker Engine and Compose from the official Docker repository ...'
  apt-get update
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL --retry 3 "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod 0644 /etc/apt/keyrings/docker.asc
  local codename=${VERSION_CODENAME:-}
  [[ -n $codename ]] || die 'Distribution codename is missing.'
  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/$ID
Suites: $codename
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  chmod 0644 /etc/apt/sources.list.d/docker.sources
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  docker_ready
}
show_key() {
  [[ -s $BASE/hbbs/id_ed25519.pub ]] || die 'Public key not found. Check installation status and logs.'
  local address='YOUR-SERVER-IP-OR-DOMAIN'
  [[ ! -f $BASE/server-address ]] || address=$(cat "$BASE/server-address")
  ok 'RustDesk client: Settings > Network > ID/Relay server'
  printf '\nID server:    %s\nRelay server: %s\nAPI server:   leave empty\n\n' "$address" "$address"
  ok 'Public key (copy the entire line into the Key field):'
  cat "$BASE/hbbs/id_ed25519.pub"
  printf '\n\nFile: %s/hbbs/id_ed25519.pub\n' "$BASE"
  info 'The private key id_ed25519 stays on the server. Existing keys are preserved.'
}
check_running() {
  local service cid running
  for service in hbbs hbbr; do
    cid=$(dc ps -q "$service")
    [[ -n $cid ]] || { dc logs --tail=60; die "$service is not running."; }
    running=$(docker inspect --format '{{.State.Running}}' "$cid")
    [[ $running == true ]] || { dc logs --tail=60; die "$service is not running."; }
  done
}
firewall() {
  info 'Required: TCP 21115,21116,21117 and UDP 21116.'
  info 'Configure your cloud firewall / router separately for this server.'
  info 'Keep WebSocket ports 21118/21119 closed publicly; web clients require a separate reverse proxy setup.'
  if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
    if confirm 'Allow these RustDesk ports in the active UFW firewall?'; then
      ufw allow 21115:21117/tcp
      ufw allow 21116/udp
    fi
  fi
}
deploy() {
  local address default='' stamp
  [[ ! -f $BASE/server-address ]] || default=$(cat "$BASE/server-address")
  read -r -p "Public domain or IPv4 (without https:// or port) [$default]: " address
  address=${address:-$default}
  [[ $address =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ && ${#address} -le 253 ]] || die 'Invalid address. Enter a domain or IPv4 address.'
  printf '\nData: %s/hbbs and %s/hbbr\nServer: %s\n' "$BASE" "$BASE" "$address"
  confirm 'Set up Docker and install/update RustDesk?' || return 0
  install_docker
  install -d -m 0700 "$BASE" "$BASE/hbbs" "$BASE/hbbr"
  stamp=$(date +%Y%m%d-%H%M%S)
  if [[ -f $COMPOSE ]]; then
    cp -a "$COMPOSE" "$COMPOSE.backup-$stamp"
  fi
  # Do not take over containers managed by another Compose project.
  local name owner
  for name in hbbs hbbr; do
    if docker container inspect "$name" >/dev/null 2>&1; then
      owner=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "$name")
      [[ $owner == rustdesk-server ]] || die "Container $name belongs to another project. Please review it first."
    fi
  done
  printf '%s\n' "$address" > "$BASE/server-address"
  cat > "$COMPOSE" <<EOF
name: rustdesk-server
services:
  hbbs:
    image: rustdesk/rustdesk-server:latest
    container_name: hbbs
    command: ["hbbs", "-r", "$address:21117"]
    network_mode: host
    volumes:
      - /rustdesk-server/hbbs:/root
    restart: unless-stopped
    logging:
      options:
        max-size: "10m"
        max-file: "3"
  hbbr:
    image: rustdesk/rustdesk-server:latest
    container_name: hbbr
    command: ["hbbr"]
    network_mode: host
    volumes:
      - /rustdesk-server/hbbr:/root
    restart: unless-stopped
    logging:
      options:
        max-size: "10m"
        max-file: "3"
EOF
  dc config --quiet
  dc pull
  dc up -d
  info 'Waiting for RustDesk to generate its public key ...'
  local attempt
  for ((attempt=0; attempt<30; attempt++)); do
    [[ ! -s $BASE/hbbs/id_ed25519.pub ]] || break
    sleep 1
  done
  sleep 2
  check_running
  firewall
  show_key
  ok 'Containers started. Verify external connectivity using a RustDesk client.'
}
uninstall() {
  require_stack
  info 'Removes the RustDesk containers in this Compose project. Docker stays installed.'
  confirm 'Remove the RustDesk containers?' || return 0
  dc down
  if confirm 'Also permanently delete ALL data, database files and keys under /rustdesk-server?'; then
    local typed
    read -r -p 'Type DELETE to permanently delete the data:  ' typed
    if [[ $typed == DELETE ]]; then
      [[ $BASE == /rustdesk-server && ! -L $BASE ]] || die 'Unexpected data path.'
      rm -rf -- "$BASE"
      ok 'RustDesk data removed. Docker and unrelated containers are retained.'
    else
      info 'Data has been retained.'
    fi
  fi
  info 'Any firewall rules previously added are retained.'
}
main() {
  local choice
  while true; do
    banner
    printf '  1) Install / Update deployment\n  2) Show status\n  3) Show public key and client settings\n  4) Show logs\n  5) Restart RustDesk\n  6) Firewall guidance / UFW rules\n  7) Uninstall RustDesk (keep Docker)\n  0) Exit\n\n'
    read -r -p 'Select an option: ' choice
    case $choice in
      1) deploy ;;
      2) require_stack; dc ps -a ;;
      3) show_key ;;
      4) require_stack; dc logs --tail=100 ;;
      5) require_stack; dc restart; sleep 2; check_running ;;
      6) firewall ;;
      7) uninstall ;;
      0) exit 0 ;;
      *) info 'Please select a valid menu option.' ;;
    esac
    pause
  done
}
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main; fi
