# Update and upgrade strategy

[← README](../README.md)

## Overview

| Layer | Method | Frequency | Notes |
|---|---|---|---|
| Proxmox hypervisor (changi) | `apt dist-upgrade` + reboot | Monthly | All VMs go down during reboot — do last |
| Debian VMs (bishan, bedok, braddell, clementi) | `apt dist-upgrade` + reboot | Monthly | Update before changi to preserve per-VM control |
| Docker containers | Pull + redeploy (see [provisioning.md](provisioning.md)) | Monthly or per-service | Snapshot image hashes first |
| Synology DSM (verona) | DSM UI → Update & Restore | Monthly | NAS stays up; brief service privateuption |
| Proxmox Backup Server | PBS web UI → Administration → Updates | Monthly | Update after DSM; PBS is a VM on verona |
| florence firmware | Synology MR2200AC UI → Update | As released | LAN drops briefly during reboot |

See [services.md](services.md) for what runs on each VM. See [backup.md](backup.md) for the backup strategy that gates the update process. See [failures.md](failures.md) for the container rollback procedure.

> **Safe update window:** avoid the backup window (00:00–04:00 local time — see [backup.md](backup.md)). Afternoon is the least disruptive.

---

## Monthly runbook

Run in order. Each step links to the detailed section below.

### Preparation (all hosts)

- [ ] Run backup readiness check (on changi — exits non-zero if any check fails):
  ```bash
  bash ~/stacks/_scripts/check-backup-status.sh
  ```
- [ ] Verify latest CI snapshots are current (snapshots workflow runs weekly — trigger manually if needed)

### Synology DSM + packages — [§4](#4-synology-dsm-verona)

- [ ] Apply DSM update (Control Panel → Update & Restore → DSM Update)
- [ ] Apply package updates (Package Center → Updates)
- [ ] Confirm kopia SFTP accessible: `kopia repository status` on any VM
- [ ] Confirm PBS VM is running in VMM

### PBS — [§5](#5-proxmox-backup-server)

- [ ] Apply PBS updates (Administration → Updates → Upgrade)
- [ ] Confirm changi can reach PBS datastore:
  ```bash
  pvesh get /nodes/changi/storage/pbs/status --output-format json
  ```

### VMs — OS update — [§1](#1-debian-vms--os-updates)

- [ ] clementi: `apt dist-upgrade` + reboot → confirm nginx-proxy-manager + Portainer
- [ ] bishan: `apt dist-upgrade` + reboot → confirm Home Assistant
- [ ] bedok: `apt dist-upgrade` + reboot → confirm Gitea at `https://git.home.lab/`
- [ ] braddell: `apt dist-upgrade` + reboot → confirm `nvidia-smi` + Ollama/Open WebUI

### Docker containers — [§3](#3-docker-containers)

- [ ] Per VM: pull and redeploy all stacks:
  ```bash
  bash ~/stacks/_scripts/update-containers.sh
  ```
- [ ] bedok/Gitea: check release notes before pulling; verify no version skip
- [ ] bedok/private: verify private containers still exit via VPN after update

### Proxmox hypervisor — [§2](#2-proxmox-hypervisor-changi)

- [ ] Run on changi: `apt dist-upgrade` + reboot
- [ ] Confirm all VMs auto-started and services are up

### florence — [§6](#6-florence--router-firmware)

- [ ] Apply firmware if available (SRM → Update & Restore → Router Update)
- [ ] Confirm DHCP leases intact and all hosts reachable

---

## 1. Debian VMs — OS updates

Update each VM before updating changi. This lets each VM reboot independently while the hypervisor is still running.

**On each VM (bishan, bedok, braddell, clementi):**
```bash
sudo apt update && sudo apt dist-upgrade -y
sudo reboot
```

Verify the service comes back up after reboot before moving to the next VM. Critical services to confirm:

| VM | Check after reboot |
|---|---|
| bishan | Home Assistant UI accessible |
| bedok | Gitea accessible at `https://git.home.lab/` |
| braddell | Ollama and Open WebUI accessible |
| clementi | nginx-proxy-manager + Portainer accessible |

**braddell — kernel updates and CUDA:**
If a new kernel was installed, verify CUDA/NVIDIA drivers still load after reboot:
```bash
nvidia-smi
```
If `nvidia-smi` fails, the driver may need reinstalling against the new kernel. Check installed driver version:
```bash
dpkg -l | grep nvidia-driver
```

---

## 2. Proxmox hypervisor (changi)

Update changi after all VMs have been updated and confirmed healthy. Rebooting changi shuts down all running VMs.

**Before rebooting changi:**
- Confirm all VMs are in a clean state (no in-progress backups, no active kopia snapshots)
- Export Proxmox config if not done in preparation step:
  ```bash
  bash ~/stacks/_scripts/backup-pve-config.sh
  ```
- Optionally shut down VMs gracefully first via Proxmox UI → each VM → Shutdown

**On changi:**
```bash
sudo apt update && sudo apt dist-upgrade -y
sudo reboot
```

After reboot, verify VMs auto-start (configured in Proxmox VM Options → Start at boot) and confirm services are up.

**Proxmox package repositories:**
changi uses the no-subscription repo. If `apt update` reports a 401 privateor on the enterprise repo, it is safe to ignore — that repo is not configured. Confirm:
```bash
cat /etc/apt/sources.list.d/pve-enterprise.list
```
Should be commented out or absent; `pve-no-subscription.list` should be active.

---

## 3. Docker containers

Follow the procedure in [provisioning.md](provisioning.md) § "Updating a running stack":

1. Snapshot image hashes (pre-update checklist above)
2. Pull updated images and redeploy via CLI or Portainer

Gitea and PBS require extra care — see notes below.

**Gitea (bedok):**
Gitea runs database migrations on startup when upgrading. Do not skip versions — upgrade incrementally if jumping more than one minor version. Check the Gitea release notes before pulling a new image.
```bash
# Check current version before upgrading
docker exec -it gitea gitea --version
```

**private (bedok):**
After a private image update, re-verify that the private containers still route through the VPN before using them:
```bash
docker exec -it private-private curl -s https://ipinfo.io/ip
```
The IP should be the VPN exit IP, not your home IP.

---

## 4. Synology DSM (verona)

1. DSM UI → **Control Panel → Update & Restore → DSM Update**
2. Check release notes — DSM major updates can change SMB/NFS behavior or package compatibility
3. Update includes a reboot — kopia targets on all VMs will be briefly unavailable; not a problem outside the backup window

After DSM update, confirm:
- Synology Photos and Drive accessible
- kopia repo on verona SFTP accessible: `kopia repository status` on any VM
- PBS VM is running (check Synology VMM)

**Synology packages:**
After DSM update, check for package updates: DSM UI → **Package Center → Updates**.

---

## 5. Proxmox Backup Server

PBS runs as a VM inside Synology VMM. Update it after DSM is confirmed stable.

1. Log in to PBS web UI at `192.168.xx.xx:8007`
2. **Administration → Updates → Upgrade**
3. PBS will prompt to reboot — click Reboot
4. After reboot, confirm changi can still reach PBS datastore:
   ```bash
   pvesh get /nodes/changi/storage/pbs/status --output-format json
   ```

---

## 6. florence — router firmware

florence is the Synology MR2200AC. Firmware updates reboot the router, dropping LAN and WiFi briefly (~1–2 min). Do this last, when downtime is acceptable.

1. Log in to Synology Router Manager (SRM) at `192.168.xx.xx`
2. **Control Panel → Update & Restore → Router Update**
3. After reboot, verify DHCP leases are intact and all hosts are reachable

---

## Rollback

**Docker container:** restore the previous image hash from `_snapshots/<hostname>.yml` and redeploy with the pinned digest:
```bash
docker compose -f <vm>/<service>/docker-compose.yml pull <image>@<digest>
docker compose -f <vm>/<service>/docker-compose.yml up -d
```

**VM OS (bad package or kernel):** restore from PBS snapshot (Proxmox UI → VM → Backup → Restore). kopia data is not affected by a VM restore — bind mounts are on the VM disk, but `~/<service-name>/` data can be restored from kopia if needed after the OS rollback.

**Proxmox hypervisor:** no automated rollback path. Boot into previous kernel via GRUB if a kernel update caused issues:
```
Advanced options for Proxmox VE GNU/Linux → select previous kernel
```
Hold the previous kernel package to prevent re-upgrade until resolved:
```bash
apt-mark hold proxmox-kernel-<version>
```
