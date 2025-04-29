#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

#====================================================
# A professional shell script to install Git, Docker,
# and Docker Compose on Debian-based systems.
#====================================================

# Logging utilities
timestamp() { date +"%Y-%m-%d %H:%M:%S"; }
log_info()  { echo -e "$(timestamp) \e[32m[INFO]   \e[0m$*"; }
log_warn()  { echo -e "$(timestamp) \e[33m[WARN]   \e[0m$*"; }
log_error() { echo -e "$(timestamp) \e[31m[ERROR]  \e[0m$*" >&2; }

# Trap errors
tap_error() {
  log_error "An unexpected error occurred on line $1. Exiting."
  exit 1
}
trap 'tap_error $LINENO' ERR

# Detect non-root and use sudo
if [ "$EUID" -ne 0 ]; then
  SUDO='sudo'
  log_warn "Not running as root; will prepend sudo to privileged commands."
else
  SUDO=''
fi

# Ensure Debian-based system
if ! [ -f /etc/debian_version ]; then
  log_error "This script only supports Debian-based distributions."
  exit 1
fi

# Update and upgrade packages
log_info "Updating package index..."
$SUDO apt update -y
log_info "Upgrading existing packages..."
$SUDO apt upgrade -y

# Install essential packages
declare -a ESSENTIALS=(curl git jq lz4 build-essential screen)
log_info "Installing essentials: ${ESSENTIALS[*]}"
$SUDO apt install -y "${ESSENTIALS[@]}"

# Install Docker if missing or outdated
if command -v docker &>/dev/null; then
  CURRENT_DOCKER=$(docker --version)
  log_info "Docker already installed: $CURRENT_DOCKER"
else
  log_info "Installing Docker Engine..."
  $SUDO apt install -y docker.io
  log_info "Enabling Docker service..."
  $SUDO systemctl enable docker
  $SUDO systemctl start docker
fi

# Add current user to docker group
group_exists=$(getent group docker || true)
if [[ -z "$group_exists" ]]; then
  log_info "Creating docker group..."
  $SUDO groupadd docker
fi
log_info "Adding user '$USER' to docker group..."
$SUDO usermod -aG docker "$USER"

# Install Docker Compose CLI plugin
COMPOSE_VERSION="v2.29.2"
DOCKER_CONFIG_DIR=${DOCKER_CONFIG:-"$HOME/.docker"}
CLI_PLUGINS_DIR="$DOCKER_CONFIG_DIR/cli-plugins"
PLUGIN_PATH="$CLI_PLUGINS_DIR/docker-compose"

log_info "Installing Docker Compose CLI plugin ($COMPOSE_VERSION)..."
mkdir -p "$CLI_PLUGINS_DIR"
curl -SL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
  -o "$PLUGIN_PATH"
chmod +x "$PLUGIN_PATH"

# Optionally install legacy binary in /usr/local/bin if needed
LEGACY_PATH="/usr/local/bin/docker-compose"
if ! command -v docker-compose &>/dev/null; then
  log_info "Installing legacy docker-compose binary to $LEGACY_PATH..."
  curl -SL "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" \
    | $SUDO tee "$LEGACY_PATH" >/dev/null
  $SUDO chmod +x "$LEGACY_PATH"
fi

# Verify installations
log_info "Verifying installations..."
docker --version
docker compose version || docker-compose --version

# Final message and reboot prompt
log_info "Installation complete."
read -rp "Reboot now to apply group changes? [y/N]: " REBOOT_ANS
if [[ "$REBOOT_ANS" =~ ^[Yy]$ ]]; then
  log_info "Rebooting..."
  $SUDO reboot
else
  log_info "Please reboot manually to finalize setup."
fi
