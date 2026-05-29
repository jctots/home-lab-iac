# home-lab-iac

Infrastructure-as-code for the home.lab home lab. Docker Compose files and VM provisioning for all self-hosted services.

## Structure

```
_docs/          documentation
_scripts/       setup scripts and utilities
_snapshots/     CI-generated snapshots — image hashes, network host map, DHCP/NPM state, and config snapshots (PVE, PBS, kopia, per-VM)
changi/         Proxmox VM provisioning — setup-scripts/ (generated), manual steps and template docs
shared/         stacks that run on all VMs (kopia, portainer-agent)
bishan/         personal services (vaultwarden, home-assistant, mealie, ...)
bedok/          storage + media (gitea, jellyfin, paperless, private, ...)
braddell/       LLM stack (ollama, open-webui, n8n, litellm, ...)
clementi/       infrastructure layer (nginx-proxy-manager, homepage, pulse)
```

## Network topology

```
Internet ──► Vodafone Station (NAT1, 192.168.xx.xx)
             └──► florence / Synology MR2200AC (NAT2, 192.168.xx.xx)
                  └──► TP-Link TL-SG105 (switch)
                       ├── changi    192.168.xx.xx  (Proxmox hypervisor)
                       ├── clementi  192.168.xx.xx  (Rprivatey Pi 4 — proxy, Portainer, Tailscale)
                       ├── verona    192.168.xx.xx  (Synology NAS)
                       └── IKEA Dirigera  192.168.xx.xx  (Zigbee/Matter hub)

Proxmox VMs (on changi):
  bishan    192.168.xx.xx  personal services
  bedok     192.168.xx.xx  storage + media
  braddell  192.168.xx.xx  LLM (RTX 3050 6GB)

Synology VMMs (on verona):
  pbs       192.168.xx.xx  Proxmox Backup Server

Inbound traffic:
  Internet ──► clementi:nginx-proxy-manager ──► LAN ──► bedok:3000 (Gitea)
           └──► clementi:Tailscale Funnel   ──► n8n webhooks (braddell:5678)

Tailscale (on clementi):
  subnet routing  ──► full homelab accessible from any Tailscale device
  exit node       ──► route all traffic through homelab
  Funnel          ──► public HTTPS for webhooks (n8n)

act_runner (Docker on bedok) ──► https://git.home.lab/ ──► clementi:nginx-proxy-manager ──► Gitea
```

## Documentation

| Doc | Purpose |
|---|---|
| [_docs/backup.md](_docs/backup.md) | Backup strategy — PBS, kopia, Synology native |
| [_docs/failures.md](_docs/failures.md) | Failure modes — blast radius, detection, mitigation, recovery |
| [_docs/hardware.md](_docs/hardware.md) | Hardware inventory — changi, clementi, verona, florence, Proxmox VMs |
| [_docs/iot.md](_docs/iot.md) | IoT devices by room |
| [_docs/network.md](_docs/network.md) | Network — LAN subnet, WiFi, Cloudflare DNS, remote access |
| [_docs/provisioning.md](_docs/provisioning.md) | VM creation (Proxmox) and container deployment |
| [_docs/rebuild.md](_docs/rebuild.md) | Full rebuild from scratch — bare metal to running containers |
| [_docs/scripts.md](_docs/scripts.md) | Script reference — what each script does, where it runs |
| [_docs/secrets.md](_docs/secrets.md) | SOPS + age key management, encryption, rotation |
| [_docs/security.md](_docs/security.md) | Security — attack surface, threat analysis, incident response |
| [_docs/services.md](_docs/services.md) | Service map — all containers per host |
| [_docs/update.md](_docs/update.md) | Monthly update/upgrade runbook — OS, containers, Synology, Proxmox |

## Roadmap

Planned improvements in approximate phase order.

**Network — VLAN isolation**
- Segment IoT devices onto a dedicated subnet (192.168.xx.xx / ssid-iot SSID) — block internet access and lateral movement to the main LAN; florence MR2200ac supports VLANs natively
- Add guest network isolation (ssid-guest SSID, 192.168.xx.xx) — internet-only, no internal access
- Home Assistant and Scrypted retain firewall exceptions to reach IoT devices across VLANs

**Infrastructure**
- Infrastructure LXC on changi — move NPM, Portainer, Pi-hole + Unbound, and Homepage off the Rprivatey Pi 4 onto a lightweight LXC on the hypervisor; reduces single-point-of-failure risk on the management plane
- Internal DNS — Pi-hole + Unbound on the infrastructure LXC for network-wide ad blocking and recursive DNS

**Media**
- Jellyfin GPU transcoding — move Jellyfin to the LLM host (braddell, RTX 3050) for hardware-accelerated transcoding; media files served via NFS from the storage host (bedok)

**Remote access**
- Cloudflare Tunnel — replace Tailscale Funnel for public webhook ingress; decouples public access from VPN provider

**Backup**
- PBS off-site gap — move PBS VM storage from Synology VMM hidden folder to a regular shared folder so Glacier Backup can include it
- Quarterly restore test — scheduled restore test: PBS VM to test VMID + kopia data to temp location

**Security**
- Qdrant API key authentication — currently unauthenticated on LAN
- `.env.example` files for all stacks

**CI / Automation**
- Public GitHub mirror — sanitized sync of this repo (excluding snapshots and private stacks)
