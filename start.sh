#!/usr/bin/env bash
# start.sh — Enable and start Anytype Vault after provisioning.
# Run AFTER provision.sh has completed.
#
# Usage:
#   sudo bash ./start.sh
#
# What this does:
#   1. Verifies provisioning prerequisites
#   2. Installs env files if missing (from examples)
#   3. Ensures compose dir is in place at /opt/anytype-vault/compose
#   4. Prompts to authenticate Tailscale if not already up
#   5. Enables and starts anytype-vault.service
#   6. Enables anytype-vault-backup.timer
#   7. Prints status summary
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
info()  { echo -e "${GREEN}[start]${NC} $*"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
error() { echo -e "${RED}[error]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

require_root() {
  [[ "${EUID}" -eq 0 ]] || die "Run as root: sudo bash ./start.sh"
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/opt/anytype-vault"
COMPOSE_DIR="${PREFIX}/compose"
ENV_DIR="${PREFIX}/env"

# ---------------------------------------------------------------------------
# 1. Require root
# ---------------------------------------------------------------------------
require_root

# ---------------------------------------------------------------------------
# 2. Verify provisioning was done
# ---------------------------------------------------------------------------
info "Checking provisioning prerequisites..."

for bin in docker restic tailscale; do
  command -v "$bin" &>/dev/null \
    || die "'$bin' not found. Run 'sudo bash ./provision.sh' first."
done

systemctl is-active --quiet docker \
  || die "docker.service is not running. Run 'sudo bash ./provision.sh' first."

[[ -f /etc/systemd/system/anytype-vault.service ]] \
  || die "anytype-vault.service not installed. Run 'sudo bash ./provision.sh' first."

info "Prerequisites OK."

# ---------------------------------------------------------------------------
# 3. Install compose dir at /opt/anytype-vault/compose (idempotent)
# ---------------------------------------------------------------------------
if [[ ! -d "${COMPOSE_DIR}" ]]; then
  info "Installing compose directory to ${COMPOSE_DIR} ..."
  install -d -m 0750 -o root -g docker "${COMPOSE_DIR}"
fi

# Sync repo files into compose dir (rsync preferred; cp fallback)
if command -v rsync &>/dev/null; then
  rsync -a --exclude='.git' --exclude='data/' \
    "${REPO_ROOT}/" "${COMPOSE_DIR}/"
else
  cp -rT "${REPO_ROOT}" "${COMPOSE_DIR}"
  rm -rf "${COMPOSE_DIR}/.git" "${COMPOSE_DIR}/data"
fi
chown -R root:docker "${COMPOSE_DIR}"
info "Compose directory ready at ${COMPOSE_DIR}."

# ---------------------------------------------------------------------------
# 4. Install env files if missing
# ---------------------------------------------------------------------------
install -d -m 0700 -o root -g root "${ENV_DIR}"

if [[ ! -f "${ENV_DIR}/compose.env" ]]; then
  warn "${ENV_DIR}/compose.env not found — copying example."
  install -m 0600 -o root -g root \
    "${REPO_ROOT}/env/compose.env.example" "${ENV_DIR}/compose.env"
  echo
  warn "IMPORTANT: Edit ${ENV_DIR}/compose.env and set TAILSCALE_IP."
  warn "  Get the value with: tailscale ip -4"
  warn "  Then re-run: sudo bash ./start.sh"
  echo
  COMPOSE_ENV_NEEDS_EDIT=1
else
  COMPOSE_ENV_NEEDS_EDIT=0
fi

if [[ ! -f "${ENV_DIR}/backup.env" ]]; then
  warn "${ENV_DIR}/backup.env not found — copying example."
  install -m 0600 -o root -g root \
    "${REPO_ROOT}/env/backup.env.example" "${ENV_DIR}/backup.env"
  warn "Edit ${ENV_DIR}/backup.env with your B2/Restic credentials before backups will work."
fi

# ---------------------------------------------------------------------------
# 5. Abort if compose.env still has placeholder value
# ---------------------------------------------------------------------------
if [[ "${COMPOSE_ENV_NEEDS_EDIT}" -eq 1 ]]; then
  die "Stopped: fill in ${ENV_DIR}/compose.env then re-run this script."
fi

# Verify TAILSCALE_IP was actually changed from the placeholder
# shellcheck disable=SC1090
source "${ENV_DIR}/compose.env" 2>/dev/null || true
if [[ "${TAILSCALE_IP:-}" == "100.x.y.z" || -z "${TAILSCALE_IP:-}" ]]; then
  die "TAILSCALE_IP in ${ENV_DIR}/compose.env is not set. Run 'tailscale ip -4' and update the file."
fi

# ---------------------------------------------------------------------------
# 6. Tailscale authentication check / prompt
# ---------------------------------------------------------------------------
info "Checking Tailscale status..."
if tailscale status &>/dev/null; then
  info "Tailscale is up ($(tailscale ip -4 2>/dev/null || echo 'IP unknown'))."
else
  warn "Tailscale does not appear to be authenticated."
  echo
  echo "  Run in another terminal:  sudo tailscale up"
  echo "  Then re-run:              sudo bash ./start.sh"
  echo
  read -r -p "Tailscale is not authenticated. Continue anyway? [y/N] " REPLY
  [[ "${REPLY}" =~ ^[Yy]$ ]] || die "Aborted — authenticate Tailscale first."
fi

# ---------------------------------------------------------------------------
# 7. Reload systemd and enable+start the vault service
# ---------------------------------------------------------------------------
info "Reloading systemd daemon..."
systemctl daemon-reload

info "Enabling and starting anytype-vault.service..."
systemctl enable --now anytype-vault.service

# ---------------------------------------------------------------------------
# 8. Enable the backup timer
# ---------------------------------------------------------------------------
info "Enabling anytype-vault-backup.timer (daily at 03:00)..."
systemctl enable --now anytype-vault-backup.timer

# ---------------------------------------------------------------------------
# 9. Optional: initialise Restic repo if backup.env has real credentials
# ---------------------------------------------------------------------------
# shellcheck disable=SC1090
source "${ENV_DIR}/backup.env" 2>/dev/null || true

if [[ "${RESTIC_REPOSITORY:-}" != "b2:your-bucket-name:anytype-vault" \
      && -n "${RESTIC_REPOSITORY:-}" \
      && "${RESTIC_PASSWORD:-}" != "change-me" \
      && -n "${RESTIC_PASSWORD:-}" ]]; then
  info "Checking Restic repository..."
  export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD
  if ! restic snapshots &>/dev/null; then
    warn "Restic repo not found or not initialised. Initialising now..."
    restic init && info "Restic repo initialised." \
      || warn "Restic init failed — check backup.env credentials."
  else
    info "Restic repo reachable."
  fi
else
  warn "backup.env still has placeholder values — skipping Restic check."
  warn "Edit ${ENV_DIR}/backup.env before backups will work."
fi

# ---------------------------------------------------------------------------
# 10. Status summary
# ---------------------------------------------------------------------------
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
info "Anytype Vault — Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
systemctl status anytype-vault.service --no-pager -l || true
echo
systemctl list-timers --all | grep anytype-vault-backup || true
echo
info "To find client-config.yml:"
echo "  sudo find ${PREFIX}/data -maxdepth 4 -name 'client-config.yml'"
echo
info "Manual backup:"
echo "  sudo ${PREFIX}/bin/backup.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
