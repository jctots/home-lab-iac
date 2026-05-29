# Backup strategy

[← README](../README.md)

## Overview

| Layer | Tool | What | Target | Schedule | Off-site |
|---|---|---|---|---|---|
| VM disks | Proxmox Backup Server | bishan, bedok, braddell VM disks | verona — PBS (192.168.xx.xx) | Daily 00:00 | No — VMM stores disks in hidden folder, excluded from Glacier Backup |
| Docker bind mounts | kopia | `~/<service-name>/` dirs on each host | verona — SFTP (192.168.xx.xx:/home/kopia) | Nightly (staggered) | Yes — `/home/kopia` in homes → Glacier weekly |
| Proxmox host config | git (CI) | Proxmox API snapshot | changi → CI → Gitea on bedok (PBS-backed) | Weekly (CI) | Via PBS → Hyper Backup |
| Personal data | Synology native | Mobile photos, desktop files | verona — Synology DSM | Continuous / on-change | Yes — Glacier Backup → Amazon Glacier weekly |
| IaC / compose files | git (Gitea) | `home-lab-iac` repo | bedok — Gitea (itself PBS-backed) | On every push | Via PBS VM → Glacier Backup weekly |

> **Off-site (Glacier Backup):** Synology "Glacier Backup" package backs up weekly to Amazon Glacier. Scope: `photos/` (Synology Photos) and `homes/` (Synology Drive, kopia repo at `/home/kopia`, and PBS VM image stored by VMM). All critical data has off-site coverage.

> **RAID ≠ backup:** verona RAID 1 protects against single disk failure only. It does not protect against accidental deletion, filesystem corruption, or physical loss of the NAS. Off-site is the safeguard for those scenarios.

---

## 1. VM disks — Proxmox Backup Server

**What is backed up:** full VM disk snapshots for bishan (1001), bedok (1002), braddell (1003).
changi (hypervisor) is not backed up via PBS — its config is backed up separately (see section 3).

**Target:** PBS on verona at `192.168.xx.xx` (runs inside Synology VMM).
PBS storage: 504 GB total, ~128 GB available as of last check.

**Schedule:** daily at **00:00** (changi local time), snapshot mode.

**Retention:**
| Policy | Count |
|---|---|
| Keep last | 3 |
| Keep daily | 3 |
| Keep weekly | 3 |
| Keep monthly | 3 |

**Inspect backups:**
```bash
# On changi — list scheduled backup jobs and storage status
pvesh get /cluster/backup --output-format json
pvesm status

# On PBS VM (192.168.xx.xx) — datastore: "datastore" at /mnt/datastore/datastore
proxmox-backup-manager datastore list
proxmox-backup-manager datastore show datastore

# List pruning and verification jobs configured on PBS
proxmox-backup-manager prune-job list
proxmox-backup-manager verify-job list

# Run garbage collection manually (reclaims space from expired snapshots)
proxmox-backup-manager garbage-collection start datastore
```

**Restore a VM:**
Proxmox UI → changi → select VM → Backup → select snapshot → Restore.

---

## 2. Docker bind mounts — kopia

**What is backed up:** Docker bind mounts (`~/<service-name>/` per service, e.g. `~/ntfy/`) on each host — application data, configs, databases. Each service directory is backed up individually, allowing per-service restore. The IaC repo (`~/stacks/`) is in git and is not backed up by kopia.

**Target:** verona SFTP at `192.168.xx.xx:/home/kopia`, user `homelab-admin`.
Credentials and known hosts setup: `shared/kopia/kopia_repo_config.md`.

**Schedule (staggered to avoid concurrent SFTP load):**
| Host | Snapshot time |
|---|---|
| clementi | 01:00 |
| bishan | 02:00 |
| bedok | 03:00 |
| braddell | 04:00 |

**Retention per host:**
| Policy | Count |
|---|---|
| Keep latest | 3 |
| Keep daily | 3 |
| Keep weekly | 3 |
| Keep monthly | 3 |

**Inspect snapshots:**
```bash
# On any VM — list snapshots
kopia snapshot list

# Show repository status
kopia repository status

# Verify snapshot integrity
kopia snapshot verify
```

**Restore from kopia:**
```bash
# List available snapshots
kopia snapshot list

# Restore to a directory
kopia restore <snapshot-id> /path/to/restore/
```

---

## 3. Proxmox host config — git (CI)

changi's Proxmox configuration is not included in PBS VM snapshots. It is captured weekly by the CI snapshots workflow via the Proxmox REST API and committed to `_snapshots/pve-config.yaml`.

**What is captured** (via Proxmox API, YAML format):
- Storage pool definitions
- Scheduled backup jobs
- Network interfaces
- VM configs (cores, memory, disk, network)

**Also captured** by the same workflow:
- `_snapshots/pbs-config.yaml` — PBS datastore status, prune jobs, verify jobs
- `_snapshots/kopia-config.yaml` — kopia full config: global policy, per-path policies (all VMs), repo connection, latest snapshots

**Use for rebuild:** read the YAML snapshots and re-enter settings in the Proxmox/PBS UI. These are reference documents, not machine-restorable backups.

**Required Gitea secrets:** `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET` — create an API token in Proxmox UI → Datacenter → API Tokens with `Sys.Audit` + `VM.Audit` on `/`.

---

## 4. Personal data — Synology native

| Service | What | Source | Notes |
|---|---|---|---|
| Synology Photos | Mobile phone photos | iOS / Android app | Automatic upload on WiFi |
| Synology Drive | Desktop PC files | Drive client on PC | Continuous sync |

Off-site: Synology **Glacier Backup** package → Amazon Glacier, weekly. Backs up `photos/` and `homes/` shared folders.

---

## 5. clementi — no OS backup needed

clementi is a Rprivatey Pi running standard Debian + Docker. If the SD card fails:
1. Flash a fresh Rprivatey Pi OS image
2. Follow `_docs/rebuild.md` section 4 (clementi setup)
3. Clone the repo + run `deploy.sh`
4. Restore bind mounts from kopia if needed

Docker bind mounts are covered by kopia (section 2). No OS-level backup is needed.

---

## Known gaps

**PBS snapshots have no off-site copy.** Synology Glacier Backup can only target regular shared folders — VMM stores VM disk images in a hidden system folder (`@GuestImage`) which cannot be selected. As a result, PBS snapshots exist only on verona locally.

Recovery path if verona is lost:
- Application data: restore from kopia (off-site via Glacier)
- VMs: rebuild from scratch using `_docs/rebuild.md` + restore kopia data into `~/<service-name>/` per service
- Fast VM restore from PBS snapshot: not possible until verona is rebuilt

Planned improvement: move PBS VM storage to a regular shared folder so Glacier Backup can include it. *(tracked in home-lab-infrastructure vault)*

---

## Open items

- **PBS storage at 74%** — monitor free space; ~128 GB headroom remains
- **Restore testing** — plan quarterly: restore one VM from PBS to a test VMID; restore one kopia snapshot to a temp directory *(tracked in home-lab-infrastructure vault)*

---

See also: [failures.md](failures.md) — failure modes and recovery procedures for backup systems · [update.md](update.md) — backup readiness check is step 1 of the monthly update runbook
