## Anytype Vault (Anytype Sync + Restic + Tailscale)

Self-hosted “Identity Vault” for Anytype sync using `any-sync-bundle`, backed up with Restic to Backblaze B2, reachable only over Tailscale.

### WSL2 + LUKS Debian VM (“L2”) setup

If you’re hosting this inside **WSL2** using a nested **Debian 12** VM with **LUKS-encrypted LVM**, follow:

- `docs/wsl2-debian12-luks-vm.md`

### Repository layout

- **`/opt/anytype-vault` on the VM**
  - **`/opt/anytype-vault/compose`**: docker compose project (this repo)
  - **`/opt/anytype-vault/data`**: persistent Anytype sync data (this is what we back up)
  - **`/opt/anytype-vault/bin`**: operational scripts (`backup.sh`)
  - **`/opt/anytype-vault/env`**: secrets/config (`backup.env`, optional `compose.env`)
- **In this git repo**
  - **`docker-compose.yml`**: Anytype sync bundle
  - **`provision.sh`**: bootstrap Debian 12 VM
  - **`backup.sh`**: restic backup+retention+maintenance
  - **`systemd/`**: `anytype-vault.service`, `anytype-vault-backup.service`, `anytype-vault-backup.timer`
  - **`.gitignore`**: prevents committing secrets and data

### Quick start (inside Debian 12 VM)

1. Clone this repo into `/opt/anytype-vault/compose`:

```bash
sudo mkdir -p /opt/anytype-vault/compose
sudo chown -R "$USER:$USER" /opt/anytype-vault
git clone <your-fork-or-repo-url> /opt/anytype-vault/compose
cd /opt/anytype-vault/compose
```

2. Run provisioning:

```bash
sudo bash ./provision.sh
```

3. Authenticate Tailscale (one-time):

```bash
sudo tailscale up
tailscale status
```

4. Create backup config (secrets live outside git):

```bash
sudo install -d -m 0700 -o root -g root /opt/anytype-vault/env
sudo cp ./env/backup.env.example /opt/anytype-vault/env/backup.env
sudo nano /opt/anytype-vault/env/backup.env
```

5. Start the vault:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now anytype-vault.service
sudo systemctl status anytype-vault.service --no-pager
```

6. Enable daily backups at 03:00:

```bash
sudo systemctl enable --now anytype-vault-backup.timer
systemctl list-timers --all | grep anytype-vault-backup
```

### Client link (extract `client-config.yml`)

The Anytype clients (desktop/iPhone) need the bundle’s `client-config.yml`.

- **Where it is**: inside the persisted data folder.
- **How to locate it** (run on the VM):

```bash
sudo find /opt/anytype-vault/data -maxdepth 4 -name "client-config.yml" -print
```

Then copy it securely to your workstation (over Tailscale) and import/link it in Anytype (client UI varies by platform/version).

### The “Cafe Sync” story (Tailscale-only)

- **No router ports** are opened.
- Your phone/laptop must be on the **same Tailscale network** to reach the sync endpoint.
- The container advertises the VM’s **Tailscale IP** as its reachable address, so clients can sync from anywhere (coffee shop, LTE) as long as Tailscale is connected.

### Backups (Restic → Backblaze B2)

Backups are **folder-level**, not VM disk images:

- **Back up**: `/opt/anytype-vault/data`
- **Do NOT back up**: `.qcow2` / VM disk

Manual run:

```bash
sudo /opt/anytype-vault/bin/backup.sh
```

Retention policy:

- keep daily: **7**
- keep weekly: **4**
- keep monthly: **6**

### The “L2 move” (restore into a brand new VM)

Goal: rebuild from **git repo + Restic snapshots**, not from VM images.

1. Fresh Debian 12 VM: clone repo to `/opt/anytype-vault/compose` and run:

```bash
cd /opt/anytype-vault/compose
sudo bash ./provision.sh
sudo tailscale up
```

2. Recreate the Restic repo reference and credentials:

```bash
sudo cp ./env/backup.env.example /opt/anytype-vault/env/backup.env
sudo nano /opt/anytype-vault/env/backup.env
```

3. Initialize Restic only if this is a new repo (first time ever):

```bash
sudo bash -c 'set -a; source /opt/anytype-vault/env/backup.env; set +a; restic snapshots' \
  || sudo bash -c 'set -a; source /opt/anytype-vault/env/backup.env; set +a; restic init'
```

4. Restore the latest snapshot into `/opt/anytype-vault/data`:

```bash
sudo systemctl stop anytype-vault.service || true
sudo rm -rf /opt/anytype-vault/data
sudo install -d -m 0750 -o root -g docker /opt/anytype-vault/data

sudo bash -c 'set -a; source /opt/anytype-vault/env/backup.env; set +a; restic restore latest --target /'
```

Notes:
- The restore targets `/`, so paths like `/opt/anytype-vault/data/...` land correctly.
- If you prefer a safer restore, restore to a temp dir and then `rsync` into place.

5. Start the vault again:

```bash
sudo systemctl start anytype-vault.service
sudo systemctl status anytype-vault.service --no-pager
```

### Security model notes

- **Zero-trust entry**: Tailscale is the only ingress.
- **At-rest secrecy**: store `/opt/anytype-vault/data` on your LUKS-encrypted volume in the L2 VM.
- **Presence requirement**: LUKS passphrase is entered manually per boot (e.g., via `virsh console`).
