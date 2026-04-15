#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash ./provision.sh" >&2
  exit 1
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/opt/anytype-vault"

source /etc/os-release
OS_ID="${ID}"
CODENAME="${VERSION_CODENAME:-}"
ARCH="$(dpkg --print-architecture)"

if [[ -z "${CODENAME}" ]]; then
  echo "Could not determine VERSION_CODENAME from /etc/os-release" >&2
  exit 1
fi

echo "Detected OS: ${OS_ID} ${CODENAME} (${ARCH})"

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  sudo \
  unzip

install -d -m 0755 /etc/apt/keyrings

case "${OS_ID}" in
  debian)
    DOCKER_BASE_URL="https://download.docker.com/linux/debian"
    TAILSCALE_CHANNEL_PATH="debian/${CODENAME}"
    ;;
  ubuntu)
    DOCKER_BASE_URL="https://download.docker.com/linux/ubuntu"
    TAILSCALE_CHANNEL_PATH="ubuntu/${CODENAME}"
    ;;
  *)
    echo "Unsupported OS: ${OS_ID}. This script supports Debian and Ubuntu." >&2
    exit 2
    ;;
esac

# Clean up any stale repo files from previous bad runs
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/sources.list.d/tailscale.list

# --------------------------
# Docker repo
# --------------------------
curl -fsSL "${DOCKER_BASE_URL}/gpg" \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

cat > /etc/apt/sources.list.d/docker.list <<EOF
deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] ${DOCKER_BASE_URL} ${CODENAME} stable
EOF

# --------------------------
# Tailscale repo
# Use vendor-provided key + vendor-provided .list file
# --------------------------
curl -fsSL "https://pkgs.tailscale.com/stable/${TAILSCALE_CHANNEL_PATH}.noarmor.gpg" \
  -o /etc/apt/keyrings/tailscale.gpg
chmod a+r /etc/apt/keyrings/tailscale.gpg

curl -fsSL "https://pkgs.tailscale.com/stable/${TAILSCALE_CHANNEL_PATH}.tailscale-keyring.list" \
  -o /etc/apt/sources.list.d/tailscale.list

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

# Optional: let the invoking user talk to Docker without sudo after relogin
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  usermod -aG docker "${SUDO_USER}" || true
fi

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
echo "  2) Re-login or run: newgrp docker"
echo "  3) Create ${PREFIX}/env/compose.env from env/compose.env.example"
echo "  4) Create ${PREFIX}/env/backup.env from env/backup.env.example"
echo "  5) Enable services:"
echo "       sudo systemctl enable --now anytype-vault.service"
echo "       sudo systemctl enable --now anytype-vault-backup.timer"
