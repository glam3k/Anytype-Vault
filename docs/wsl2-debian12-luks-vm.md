## WSL2 → KVM Debian 12 VM (LUKS-encrypted) “L2” guide

This guide sets up the **L1 host** as WSL2 (Ubuntu/Debian in Windows), running an **L2 guest** Debian 12 VM via KVM/QEMU, with **LUKS-encrypted LVM** inside the guest.

### Prereqs (Windows / WSL2)

- **Windows features**: ensure virtualization is enabled in BIOS/UEFI and Windows has WSL2 working.
- **Nested virtualization**: WSL2 must expose `/dev/kvm`.

On WSL, verify:

```bash
ls -la /dev/kvm
```

If `/dev/kvm` is missing, fix WSL2/KVM before continuing (WSL kernel update, virtualization settings, etc.).

### 1) Install KVM/QEMU + libvirt inside WSL2

Run:

```bash
sudo bash ./scripts/wsl2/install-kvm-libvirt.sh
```

Then re-open the WSL session (or `newgrp libvirt` / log out/in) so group membership takes effect.

Verify:

```bash
virsh -c qemu:///system list --all
```

### 2) Create storage locations (keep VM disk on Linux filesystem)

Avoid storing VM images on `/mnt/c/...` (performance + fs semantics). Use the WSL distro filesystem:

```bash
sudo install -d -m 0755 /var/lib/libvirt/images
```

### 3) Download Debian 12 ISO

Example (pick the current netinst ISO and checksum it as you prefer):

```bash
mkdir -p ~/iso
cd ~/iso
# download debian-12.x.x-amd64-netinst.iso into ~/iso
```

### 4) Create and install the Debian 12 VM

You can use `virt-install` (recommended) to create a libvirt-managed VM.

Example:

```bash
VM_NAME="anytype-vault-debian12"
DISK="/var/lib/libvirt/images/${VM_NAME}.qcow2"
ISO="$HOME/iso/debian-12-netinst.iso"

sudo qemu-img create -f qcow2 "$DISK" 80G

sudo virt-install \
  --name "$VM_NAME" \
  --memory 4096 \
  --vcpus 2 \
  --cpu host \
  --machine q35 \
  --disk path="$DISK",format=qcow2,bus=virtio \
  --cdrom "$ISO" \
  --network network=default,model=virtio \
  --graphics none \
  --console pty,target_type=serial \
  --os-variant debian12
```

Connect to the installer console:

```bash
sudo virsh console "$VM_NAME"
```

To exit the console: press `Ctrl+]`.

### 5) Debian installer: choose LUKS-encrypted LVM

Inside the Debian installer:

- Choose **“Guided - use entire disk and set up encrypted LVM”**
- Set a strong **encryption passphrase** (this is the “presence requirement”)

After installation, the VM will reboot and you will be prompted to unlock the disk.

### 6) Boot-time unlocking (manual, by design)

Each boot requires typing the LUKS passphrase on the VM console:

```bash
sudo virsh start "$VM_NAME"
sudo virsh console "$VM_NAME"
```

This ensures the encrypted data is never mounted unless you explicitly unlock it.

### 7) Inside the Debian VM: install Anytype Vault stack

Once Debian is installed and unlocked:

- Create/mount your filesystem where **`/opt/anytype-vault`** lives (inside the encrypted volume)
- Follow the repo README “Quick start” inside the VM:
  - clone repo to `/opt/anytype-vault/compose`
  - run `sudo bash ./provision.sh`
  - bring up Tailscale and set env files
  - `systemctl enable --now anytype-vault.service`
  - `systemctl enable --now anytype-vault-backup.timer`

### Notes / troubleshooting

- **Networking**: libvirt default NAT works fine; Tailscale runs inside the Debian VM (L2) and is your only entry point.
- **Performance**: ensure `/dev/kvm` exists and `--cpu host` is used (KVM acceleration).
- **WSL systemd**: if your distro uses systemd, libvirt services are easier. If not, use a systemd-enabled WSL distro configuration or run libvirt manually.
