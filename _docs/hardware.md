# Hardware

[← README](../README.md)

## changi — Proxmox host

Lenovo ThinkCentre M720q.

| Component | Details |
|---|---|
| CPU | Intel i5-8400T — 6 cores / 6 threads, 1.70GHz base |
| RAM | 32GB total |
| GPU | NVIDIA RTX 3050 6GB VRAM (GA107) — PCIe passthrough to `braddell` (1003) |
| NVMe (Crucial P3 Plus, CT1000P3PSSD8, 931.5G) | Proxmox boot + LVM thin pool — all VM virtual disks live here |
| SATA (Crucial BX500, CT1000BX500SSD1, 931.5G) | Passed through to `bedok` as raw disk — appears as `sdc`, mounted at `/mnt/share`; private media files and scrypted NVR recordings stored here. Disk ID: `ata-CT1000BX500SSD1_2507E9A7967C` |
| PVE version | 9.1.5, kernel 6.17.9-1-pve |

### Known issues

**e1000e NIC hardware unit hang** — the onboard NIC (`enp0s31f6`) triggers a hardware unit hang under load. Fix: disable TSO/GSO/GRO offloading. See [failures.md](failures.md) for the recovery procedure. Add to `/etc/network/interfaces` under the physical interface entry:

```
iface enp0s31f6 inet manual
    post-up /usr/sbin/ethtool -K $IFACE tso off gso off gro off
```

Verify after reboot:
```bash
ethtool -k enp0s31f6 | grep -E 'segmentation|receive-offload'
# tcp-segmentation-offload, generic-segmentation-offload, generic-receive-offload should all be: off
```

## clementi — Rprivatey Pi 4

Infrastructure layer — reverse proxy, Portainer server, Tailscale node, monitoring. Runs Docker.

## verona — Synology DS218+

NAS. Disk config: RAID 1 (2 disks mirrored — single disk failure tolerated).

Backup targets:
- Proxmox VM snapshots — pushed from changi via PBS (`192.168.xx.xx`, runs inside Synology VMM)
- Docker bind mounts — pulled from each host (clementi, bishan, bedok, braddell) via kopia

## florence — Synology MR2200AC

LAN router, DHCP, gateway. Double NAT behind Vodafone Station — permanent constraint (Vodafone Hessen does not support bridge/passthrough mode).

**WAN IP:** `192.168.xx.xx` (assigned by Vodafone Station).

---

## Proxmox VMs (changi)

| VMID | Name | IP | Cores | RAM | Disk | Status | Role |
|---|---|---|---|---|---|---|---|
| 1001 | bishan | 192.168.xx.xx | 4 | 8GB | 32GB | running | Personal services |
| 1002 | bedok | 192.168.xx.xx | — | 8GB | 64GB | running | Storage (NVMe direct mount) + Gitea + Media |
| 1003 | braddell | 192.168.xx.xx | 4 | 16GB | 128GB | running | LLM (RTX 3050 6GB passthrough) |
| 2001 | bendemeer | — | — | 4GB | 64GB | stopped | — |
| 8001 | sentosa | — | — | 8GB | 32GB | stopped | — |

### VM templates

Templates used as base for cloning production VMs. Not started in normal operation.

| VMID | Name | Base | Purpose |
|---|---|---|---|
| 9001 | trixie-base | Debian Trixie cloud image | Minimal Debian — source for 9002 |
| 9002 | trixie-qemu | 9001 | Adds qemu-guest-agent |
| 9003 | trixie-portainer | 9002 | Adds Docker + portainer-agent — clone this for new VMs |
