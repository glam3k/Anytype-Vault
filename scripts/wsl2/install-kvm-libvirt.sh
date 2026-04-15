#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0" >&2
  exit 1
fi

apt-get update
apt-get install -y --no-install-recommends \
  qemu-kvm \
  qemu-utils \
  libvirt-daemon-system \
  libvirt-clients \
  virtinst \
  bridge-utils \
  dnsmasq-base

systemctl enable --now libvirtd || true

# Allow current user to use libvirt without sudo (re-login required)
if [[ -n "${SUDO_USER:-}" ]]; then
  usermod -aG libvirt,kvm "${SUDO_USER}" || true
  echo "Added ${SUDO_USER} to groups: libvirt,kvm (re-login WSL session to apply)."
fi

echo "KVM/libvirt install complete."
