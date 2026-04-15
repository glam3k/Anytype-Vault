#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash ./provision.sh" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/opt/anytype-vault"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  sudo \
  systemd \
  unzip

install -d -m 0755 /etc/apt/keyrings

# Docker (official repo)
if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
  curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

# Tailscale (official repo)
if [[ ! -f /etc/apt/keyrings/tailscale.gpg ]]; then
  curl -fsSL https://pkgs.tailscale.com/stable/debian/${CODENAME}.noarmor.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/tailscale.gpg
  chmod a+r /etc/apt/keyrings/tailscale.gpg
fi
echo "deb [signed-by=/etc/apt/keyrings/tailscale.gpg] https://pkgs.tailscale.com/stable/debian ${CODENAME} main" \
  > /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y --no-install-recommends \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin \
  tailscale \
  restic

systemctl enable --now docker
systemctl enable --now tailscaled

# /opt/anytype-vault layout
install -d -m 0750 -o root -g docker "${PREFIX}"
install -d -m 0750 -o root -g docker "${PREFIX}/data"
install -d -m 0755 -o root -g root "${PREFIX}/bin"
install -d -m 0700 -o root -g root "${PREFIX}/env"
install -d -m 0755 -o root -g root "${PREFIX}/systemd"

# Install operational scripts
install -m 0755 "${REPO_ROOT}/backup.sh" "${PREFIX}/bin/backup.sh"

# Install systemd units
install -m 0644 "${REPO_ROOT}/systemd/anytype-vault.service" /etc/systemd/system/anytype-vault.service
install -m 0644 "${REPO_ROOT}/systemd/anytype-vault-backup.service" /etc/systemd/system/anytype-vault-backup.service
install -m 0644 "${REPO_ROOT}/systemd/anytype-vault-backup.timer" /etc/systemd/system/anytype-vault-backup.timer

systemctl daemon-reload

echo
echo "Provisioning complete."
echo
echo "Next steps:"
echo "  1) Authenticate Tailscale: sudo tailscale up"
echo "  2) Create ${PREFIX}/env/compose.env from env/compose.env.example (set TAILSCALE_IP)"
echo "  3) Create ${PREFIX}/env/backup.env from env/backup.env.example (B2 + restic)"
echo "  4) Enable services:"
echo "       sudo systemctl enable --now anytype-vault.service"
echo "       sudo systemctl enable --now anytype-vault-backup.timer"
