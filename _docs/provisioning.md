# Provisioning

[← README](../README.md)

End-to-end workflow for adding or rebuilding a VM and deploying its containers. See [hardware.md](hardware.md) for VM specs and the template chain, [services.md](services.md) for what runs on each host, and [scripts.md](scripts.md) for the full script reference.

---

## 1. VM creation (Proxmox on changi)

### Template chain

```
9001 (Debian Trixie cloud image)
  └─► 9002 (+ qemu-guest-agent)
        └─► 9003 (+ Docker + portainer-agent)
              └─► 1001 bishan
              └─► 1002 bedok
              └─► 1003 braddell
```

Clone from 9003 for any new VM — the `.sh` scripts use this as the base.

### Files in `changi/`

| File | Purpose | Updated by |
|---|---|---|
| `*.md` | Manual setup steps that can't be scripted | Human |
| `_setup/changi-setup.sh` | Re-apply host config (storage, backup jobs, network) on a fresh Proxmox install | `_scripts/generate-host-setup.sh` (CI) |
| `_setup/{vmid}-{name}.sh` | Generated `qm clone` + `qm set` commands | `_scripts/generate-vm-setup.sh` (CI) |
| `_snapshots/vm-{vmid}-{name}.yaml` | Full VM config snapshot (hardware, disks, network, PCIe) | `_scripts/generate-vm-setup.sh` (CI) |

```
changi-host-config.md           host-level config (NIC hang fix, etc.)
9002-trixie-qemu.md             template creation — Debian Trixie + qemu-guest-agent
9003-trixie-portainer.md        template creation — adds Docker + portainer-agent
1001-bishan.md  +  _setup/1001-bishan.sh
1002-bedok.md   +  _setup/1002-bedok.sh
1003-braddell.md + _setup/1003-braddell.sh
```

### Creating or rebuilding a VM

1. Run the generated creation script on changi as root:
   ```bash
   bash changi/_setup/<vmid>-<name>.sh
   ```
2. Follow the manual steps in the matching `.md` file.

### Keeping VM config snapshots current

Trigger the `generate-setup-scripts` workflow in Gitea Actions after any VM hardware or host config change. It SSHes to changi, regenerates all scripts, and commits to `changi/_setup/` and `_snapshots/`.

To run locally on changi:
```bash
bash _scripts/generate-vm-setup.sh
bash _scripts/generate-host-setup.sh
```

---

## 2. Container deployment

### Prerequisites

- Repo cloned with sparse checkout on the VM (see [rebuild.md](rebuild.md))
- Age key present and `SOPS_AGE_KEY_FILE` set (see [secrets.md](secrets.md))

### Decrypt .env files

From the repo root on the VM:

```bash
find . -name ".env" | xargs -I{} sops --decrypt --in-place {}
```

### Deploy all stacks

```bash
bash _scripts/deploy.sh
```

Deploys `shared/` first, then the VM's own folder. Detects hostname automatically.

### Deploy a single stack

```bash
docker compose -f <vm>/<service>/docker-compose.yml up -d
```

### Re-encrypt after editing

```bash
find . -name ".env" | xargs -I{} sops --encrypt --in-place {}
```

Commit and push once re-encrypted.

---

## 3. Updating a running stack

### Step 1 — snapshot current image hashes

Run on the VM before pulling new images:

```bash
bash _scripts/generate-image-snapshot.sh > _snapshots/image-hash-$(hostname).yaml
git add _snapshots/image-hash-$(hostname).yaml && git commit -m "snapshot: pre-update image hashes $(date +%Y-%m-%d)"
```

This is the rollback reference. Do not skip it.

### Step 2a — via terminal

```bash
git pull
docker compose -f <vm>/<service>/docker-compose.yml pull
docker compose -f <vm>/<service>/docker-compose.yml up -d
```

Docker Compose only recreates containers whose image or config changed.

### Step 2b — via Portainer

Portainer → select environment → Stacks → select stack → **Pull and redeploy**
— OR — Containers → select container → **Recreate** → enable **Re-pull image**

For rollback procedure, see [failures.md → container-rollback](failures.md#container-rollback).
