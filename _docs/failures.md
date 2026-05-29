# Failure modes

[← README](../README.md)

Known failure scenarios, their causes, impact, and mitigations. Not exhaustive — covers components with real-world risk or documented incidents.

Recovery steps shared across multiple entries live in [Recovery procedures](#recovery-procedures) below.

**Severity:** Critical = immediate impact on daily life · High = significant disruption · Medium = degraded but functional · Low = minor inconvenience

**Status:** Mitigated · Partial · Planned · Open

---

## Network

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| Critical | florence | Router / DHCP outage | All LAN devices lose connectivity and DHCP leases | Immediate — everything stops | — | [→ rebuild-florence](#rebuild-florence) | Partial |
| — | florence | Double NAT — permanent | Port forwarding unavailable; inbound requires Tailscale | — | Tailscale covers all remote access | — | Mitigated |
| Low | IoT SSID (ssid-iot) | IoT compromise reaches LAN | Compromised device has direct LAN access to all hosts | Anomalous LAN traffic; compromised device behaviour | Migrate IoT to `192.168.xx.xx` with VLAN tagging | Isolate device on florence; apply VLAN fix | Planned |
| Medium | Cloudflare DNS | `home.lab` wildcard goes stale | All subdomains fail to resolve | All *.home.lab URLs fail; internal LAN access via IP still works | Records are DNS only — simple A + CNAME | [→ restore-cloudflare-dns](#restore-cloudflare-dns) | Partial |

---

## Compute — changi

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| Critical | changi NIC (`enp0s31f6`) | Hardware unit hang under load | changi loses network — all VMs unreachable, Proxmox UI down | SSH timeout; Proxmox UI unreachable; Pulse shows all red | Disable TSO/GSO/GRO in `/etc/network/interfaces`; see `hardware.md`; **must reapply on rebuild** | [→ fix-nic-hang](#fix-nic-hang) | Mitigated |
| Critical | changi host | Total hardware failure | All VMs down until hardware replaced | Pulse shows all services red | Rebuild documented in `rebuild.md` | [→ rebuild-changi](#rebuild-changi) | Partial |
| Medium | changi host | Proxmox config loss | VM config, storage, or network config unrecoverable | Silent — only apparent during a rebuild | Weekly cron pending; run manually after any config change | Restore from `changi/pve-config/` in git; see `rebuild.md` | Planned |
| Medium | RTX 3050 (braddell passthrough) | GPU unavailable | braddell loses GPU; Ollama falls back to CPU (unusably slow) | Ollama inference extremely slow or times out | IOMMU config documented | Check IOMMU/vfio config in `braddell/`; hardware failure = GPU replacement | Partial |

---

## Compute — VMs

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| Medium | clementi | SD card failure | Reverse proxy, Portainer, Tailscale, Homepage, Pulse all down | Pulse goes dark; all *.home.lab URLs return connection privateor | Bind mounts backed up by kopia | [→ rebuild-clementi](#rebuild-clementi) | Partial |
| Medium | clementi | Tailscale auth token expiry | Remote access down; Funnel (n8n webhook) unreachable | Remote access fails; Tailscale admin shows clementi offline | — | Renew token in Tailscale admin; restart Tailscale on clementi | Open |
| High | braddell | LiteLLM API keys exposed | LLM_API_KEY_1, LLM_API_KEY_2, LLM_MASTER_KEY compromised | Unexpected API usage or billing spike | Rotate immediately; SOPS-encrypt `.env` | [→ rotate-api-keys](#rotate-api-keys) | Open |
| High | any VM | Container data loss | Application data lost on that host | Service shows empty state or privateors on startup | kopia nightly to verona; off-site via Glacier | [→ restore-kopia](#restore-kopia) | Mitigated |

---

## Storage — verona

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| High | verona disks | Dual disk failure | All local backups (PBS + kopia repo) lost | Synology alert; kopia and PBS jobs start failing | kopia repo off-site via Glacier; PBS has no off-site | Restore application data from Glacier via kopia; rebuild VMs | Partial |
| Medium | PBS backups | No off-site copy | If verona lost: fast VM restore unavailable; must rebuild | verona outage reveals gap | Planned fix: move VMM storage to a regular shared folder | [→ rebuild-changi](#rebuild-changi) + [→ restore-kopia](#restore-kopia) | Planned |
| Medium | PBS storage | Disk space exhaustion (~74% used, ~128 GB free) | Backup jobs fail silently | Proxmox backup job failure notification | Current retention policy should hold | [→ pbs-gc](#pbs-gc) | Open |
| High | kopia repo | Silent job failure | No recent backup — gap accumulates unnoticed | Only detected via Pulse alert or manual check of kopia UI | Pulse alerts on backup job status (not yet configured) | Investigate logs; fix cause; trigger manual snapshot; assess gap | Open |
| High | kopia repo | Repository corruption | Snapshots unverifiable or unrestorable | `kopia snapshot verify` failure; restore attempt fails | Run `kopia snapshot verify` periodically | Re-initialize repo from Glacier off-site copy; see `backup.md` | Open |

---

## Backup integrity

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| High | kopia / PBS | Restore never tested | Latent corruption or misconfiguration undetected | Only discovered during a real incident | Quarterly test: restore one VM from PBS to a test VMID; restore one kopia snapshot to a temp dir | — | Open |
| Medium | Proxmox config backup | Backup not automated | Config changes lost between weekly manual runs | Silent — only apparent during a rebuild | Add weekly cron; run `backup-pve-config.sh` manually first | Restore from `changi/pve-config/` in git | Planned |
| Medium | Update pipeline | Container update breaks a service | Single service unavailable until rollback | Service returns privateors or fails health check | Image tag capture + manual kopia snapshot before every update | [→ container-rollback](#container-rollback) | Partial |

---

## Services

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| Critical | Vaultwarden (bishan) | Container crash or bishan down | No password access — dangerous during any other recovery scenario | Bitwarden client shows vault unreachable | Keep offline vault cache on Bitwarden app; export encrypted backup before bishan maintenance | Restart container; if bishan down: [→ restore-vm-pbs](#restore-vm-pbs); emergency: offline cache | Partial |
| High | nginx-proxy-manager (clementi) | Container crash or clementi down | All *.home.lab URLs unreachable; services still running | All subdomains return connection privateor | Set restart policy to always; maintain direct IP:port list | [→ rebuild-clementi](#rebuild-clementi); interim: access via direct IP:port | Partial |
| High | Home Assistant (bishan) | Container crash or bishan down | All automations stop; IoT control via HA lost; physical switches still work | HA UI unreachable; automations stop firing | Physical privateides for critical devices; set restart policy to always | Restart container; if bishan down: [→ restore-vm-pbs](#restore-vm-pbs) | Partial |
| Medium | Gitea + act_runner (bedok) | Container crash or bedok down | IaC repo unavailable; CI workflows stop | Gitea UI unreachable; CI jobs fail | Set restart policy to always | Restart containers; if bedok down: [→ restore-vm-pbs](#restore-vm-pbs) | Partial |
| Medium | Paperless-NGX (bedok) | Container crash | Document UI unavailable; no new ingestion; underlying data unaffected | Paperless UI unreachable | Always upgrade postgres/redis/tika together with Paperless | Restart stack; restart postgres + redis first if unhealthy | Partial |
| Medium | n8n (braddell) | Container crash or braddell down | Automations stop; Tailscale Funnel webhook unreachable | Webhook senders report delivery failure | Set restart policy to always; manual trigger fallback for critical automations | Restart container; if braddell down: [→ restore-vm-pbs](#restore-vm-pbs) | Partial |
| Low | Jellyfin (bedok) | Container crash or bedok down | Media streaming stops; no other services affected | Jellyfin clients show server unreachable | — | Restart container; if bedok down: [→ restore-vm-pbs](#restore-vm-pbs) | Partial |

---

## Secrets

| Sev | Component | Failure mode | Impact | Detection | Mitigation | Recovery | Status |
|---|---|---|---|---|---|---|---|
| High | age key | Key lost or deleted | All SOPS-encrypted `.env` files permanently unreadable | Decryption fails on any VM | Store in Bitwarden; see `secrets.md` | Unrecoverable — prevention only | Partial |
| High | age key | Key compromised | All encrypted secrets readable by attacker | Unexpected API usage or access | — | [→ rotate-age-key](#rotate-age-key) | Partial |
| High | `.env` | Committed plaintext | Credentials exposed in git history | Audit or external report | Pre-commit review; `secrets.md` documents the pattern | [→ rotate-api-keys](#rotate-api-keys) + git history rewrite | Open |

---

## Summary

| Severity | Scenario | Key mitigation |
|---|---|---|
| Critical | changi hardware failure | PBS restore documented; [→ rebuild-changi](#rebuild-changi) |
| Critical | changi NIC hang | TSO/GSO/GRO disabled; must reapply on rebuild |
| Critical | florence router failure | Vodafone Station fallback WiFi; DHCP reservations in `_snapshots/network-hosts.yaml` |
| Critical | Vaultwarden unavailable | Offline vault cache on Bitwarden app; encrypted export before upgrades |
| High | kopia silent failure | Pulse alerts on backup jobs (not yet configured) |
| High | kopia repo corruption | `kopia snapshot verify` periodically |
| High | Container data loss | kopia nightly + Glacier off-site |
| High | LiteLLM API keys exposed | Rotate + SOPS-encrypt immediately |
| High | age key lost or compromised | Bitwarden; key rotation procedure in `secrets.md` |
| High | verona dual disk failure | kopia off-site via Glacier; PBS has no off-site |
| High | Backups never restore-tested | Quarterly restore test |
| High | Vaultwarden / HA / NPM down | PBS restore; direct IP:port fallback for NPM |
| Medium | PBS no off-site | Move VMM storage to regular shared folder |
| Medium | PBS storage full | Garbage collection |
| Medium | changi Proxmox config not automated | Weekly cron pending |
| Medium | GPU unavailable (braddell) | IOMMU config documented |
| Medium | clementi SD card failure | kopia bind mount backup; rebuild documented |
| Medium | Tailscale token expiry | Renew in admin console |
| Medium | Gitea / Paperless / n8n down | PBS restore; container restart |
| Medium | Container update rollback | Image tag capture + kopia snapshot before every update |
| Low | IoT VLAN isolation missing | VLAN migration planned |
| Low | Jellyfin unavailable | Non-critical; PBS restore |

---

## Recovery procedures

### rebuild-florence

1. Access florence admin UI (`192.168.xx.xx`) or factory reset.
2. Restore DHCP reservations from `_snapshots/network-hosts.yaml` (`dhcp_reservations` section).
3. Verify WiFi SSIDs (ssid-home, ssid-guest, ssid-iot) and static routes.
4. Regenerate snapshot after any changes: `_scripts/generate-network-snapshot.sh`.

Emergency fallback while florence is down: connect directly to Vodafone Station (`192.168.xx.xx`) — it has its own WiFi for internet access while florence is being restored.

### rebuild-changi

Full procedure in `rebuild.md` sections 1–3. Summary:
1. Install Proxmox on ThinkCentre M720q.
2. Apply NIC hang fix immediately — see [fix-nic-hang](#fix-nic-hang).
3. Restore Proxmox config from `changi/pve-config/` in git (storage, jobs, network, VM configs).
4. Clone IaC repo; run VM creation scripts.
5. Restore VM disks from PBS on verona if verona is intact; otherwise rebuild VMs and restore application data from kopia.

PBS restore order: bishan first (Vaultwarden — needed for credentials), then bedok, then braddell.

Estimated time: 2–4 hours if replacement hardware is available.

### rebuild-clementi

Full procedure in `rebuild.md` section 4. Summary:
1. Flash fresh Rprivatey Pi OS to SD card.
2. Clone IaC repo; run `deploy.sh`.
3. Restore bind mounts from kopia if needed — see [restore-kopia](#restore-kopia).
4. Re-register Portainer edge agents (Portainer UI → Environments).
5. Re-auth Tailscale on clementi.

Estimated time: 30–60 minutes.

### fix-nic-hang

The e1000e NIC (`enp0s31f6`) hangs under load unless TSO/GSO/GRO offloading is disabled. Apply on every rebuild:

```
iface enp0s31f6 inet manual
    post-up /usr/sbin/ethtool -K $IFACE tso off gso off gro off
```

Verify after reboot:
```bash
ethtool -k enp0s31f6 | grep -E 'segmentation|receive-offload'
# all three should show: off
```

### restore-vm-pbs

Proxmox UI → changi → select VM → Backup → select snapshot → Restore.

Or via CLI on changi:
```bash
qmrestore /var/lib/vz/dump/<backup-file>.vma <VMID> --storage local-lvm
```

Estimated time: 15–30 minutes per VM.

### restore-kopia

```bash
# On the target VM
kopia snapshot list
kopia restore <snapshot-id> /path/to/restore/

# Restore a specific service directory (overwrites — confirm first)
kopia restore <snapshot-id> ~/<service-name>/
```

Snapshots are on verona at `192.168.xx.xx:/home/kopia`. If verona is unavailable, restore from the Glacier Backup copy via Synology Hyper Backup (Glacier Standard retrieval: 3–5 hours).

### pbs-gc

Run on the PBS VM (`192.168.xx.xx`):
```bash
proxmox-backup-manager garbage-collection start datastore
```

Check free space before and after:
```bash
proxmox-backup-manager datastore show datastore
```

### container-rollback

1. Identify last known good image tag from pre-update snapshot (committed to Gitea).
2. Pull the specific image: `docker pull <image>:<tag>`
3. Restore container data from kopia snapshot taken before the update — see [restore-kopia](#restore-kopia).
4. Redeploy stack from git with pinned image tag.
5. Verify service health.

Always run image tag capture and a manual kopia snapshot **before** any update.

### restore-cloudflare-dns

Log into Cloudflare → `home.lab` → DNS. Recreate records per `network.md` DNS table. Key records:
- A `home.lab` → `192.168.xx.xx` (clementi)
- CNAME `*` → `home.lab`

### rotate-api-keys

For exposed LiteLLM keys (`braddell/litellm/.env`):
1. Rotate LLM_API_KEY_1 at console.anthropic.com.
2. Rotate LLM_API_KEY_2 at aistudio.google.com.
3. Generate a new LLM_MASTER_KEY (random string).
4. Update `braddell/litellm/.env` with new values.
5. SOPS-encrypt before committing: `sops --encrypt --in-place braddell/litellm/.env`
6. Redeploy: `docker compose up -d`

For a `.env` committed in plaintext: rewrite git history to remove the commit, or treat the repo as compromised and rotate immediately.

### rotate-age-key

Full procedure in `secrets.md`. Summary:
1. `age-keygen -o ~/age-key-home-lab-iac-new.txt`
2. Update `.sops.yaml` with the new public key.
3. For each `.env`: decrypt with old key, re-encrypt with new key.
4. `scp` new key to all VMs.
5. Remove old key from all machines and update Bitwarden entry.
