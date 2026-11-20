#!/usr/bin/env bash
#
# setup.sh - Prepares a fresh Linux runner as a temporary VPS with GUI & Chrome.
#
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SETUP]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

VPS_USER="${VPS_USER:-luffy}"
VPS_PASSWORD="${VPS_PASSWORD:-luffy@123}"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"
VPS_HOSTNAME="${VPS_HOSTNAME:-gh-vps}"
ENABLE_DOCKER="${ENABLE_DOCKER:-true}"

if [ -z "$VPS_PASSWORD" ]; then
  err "VPS_PASSWORD cannot be empty"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

log "Updating package lists..."
sudo apt-get update -y

log "Installing base tools & Python..."
sudo apt-get install -y --no-install-recommends \
  git curl wget unzip zip ca-certificates gnupg lsb-release \
  python3 python3-pip python3-venv python3-dev \
  nodejs npm \
  build-essential \
  vim nano htop \
  net-tools dnsutils \
  openssh-server \
  tmate

if [ "$ENABLE_DOCKER" = "true" ]; then
  log "Installing Docker..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo systemctl enable docker
  sudo systemctl start docker
fi

log "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh

if [ -n "$TAILSCALE_AUTHKEY" ]; then
  log "Starting Tailscale..."
  sudo systemctl enable tailscaled
  sudo systemctl start tailscaled
  sleep 3
  sudo tailscale up \
    --authkey="$TAILSCALE_AUTHKEY" \
    --hostname="$VPS_HOSTNAME" \
    --accept-routes || warn "tailscale up returned non-zero"
else
  warn "TAILSCALE_AUTHKEY not set — Tailscale will not be connected"
fi

log "Creating user '$VPS_USER'..."
if ! id -u "$VPS_USER" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$VPS_USER"
  echo "$VPS_USER:$VPS_PASSWORD" | sudo chpasswd
  sudo usermod -aG sudo "$VPS_USER"
  echo "$VPS_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/$VPS_USER" >/dev/null
  sudo chmod 0440 "/etc/sudoers.d/$VPS_USER"
else
  warn "User '$VPS_USER' already exists"
  echo "$VPS_USER:$VPS_PASSWORD" | sudo chpasswd
fi

log "Enabling SSH password authentication..."
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl enable ssh
sudo systemctl restart ssh || sudo systemctl restart sshd || true

log "Installing XFCE Desktop Environment & XRDP..."
sudo apt-get install -y --no-install-recommends \
  xfce4 xfce4-goodies dbus-x11 \
  xrdp xorgxrdp xserver-xorg-core

# Configure startwm.sh for XRDP to reliably launch XFCE with D-Bus
sudo tee /etc/xrdp/startwm.sh >/dev/null << 'EOF'
#!/bin/sh
if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
export XDG_CONFIG_DIRS="/etc/xdg"
export XDG_DATA_DIRS="/usr/share"
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chmod +x /etc/xrdp/startwm.sh

# User session file
echo "exec dbus-launch --exit-with-session startxfce4" | sudo tee "/home/$VPS_USER/.xsession" >/dev/null
sudo chown "$VPS_USER:$VPS_USER" "/home/$VPS_USER/.xsession"
sudo chmod +x "/home/$VPS_USER/.xsession"

# Fix XRDP group and security options for Windows RDP client compatibility
sudo adduser xrdp ssl-cert || true
sudo sed -i 's/^crypt_level=.*/crypt_level=low/' /etc/xrdp/xrdp.ini
sudo sed -i 's/^security_layer=.*/security_layer=negotiate/' /etc/xrdp/xrdp.ini

sudo systemctl enable xrdp
sudo systemctl restart xrdp

log "Installing Google Chrome..."
wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb
sudo apt-get install -y /tmp/chrome.deb || sudo apt-get -f install -y
rm -f /tmp/chrome.deb

# Cleanup cache
log "Cleaning up package caches..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

log "Setup complete. GUI, Chrome, and Python are ready."
