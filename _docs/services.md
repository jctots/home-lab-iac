# Services

[← README](../README.md)

Container map per host. See [network.md](network.md) for port routing and remote access, [security.md](security.md) for the attack surface per service, and [backup.md](backup.md) for what is backed up on each host.

Snapshots for reference:

- `_snapshots/image-hash-{host}.yaml` — current image hashes per host; regenerated weekly by CI (snapshots workflow)
- `_snapshots/npm.yaml` — external URLs (nginx-proxy-manager); regenerated weekly by CI (snapshots workflow)
- `_snapshots/network-hosts.yaml` — full host→IP map (DHCP reservations + static hosts); regenerated weekly by CI

---

## clementi — Infrastructure (Rprivatey Pi 4)

| Container                                     | Port                              | Access          | Notes                                       |
| --------------------------------------------- | --------------------------------- | --------------- | ------------------------------------------- |
| [nginx-proxy-manager](https://proxy.home.lab) | 80, 81 (admin UI), 443            | LAN / Internet  | Reverse proxy for external traffic          |
| [portainer](https://docker.home.lab)          | 9443 (HTTPS), 8000 (agent tunnel) | LAN / Tailscale | Portainer CE server — manages all VM agents |
| [homepage](https://home.home.lab)             | 3000                              | LAN             | Homelab dashboard                           |
| [pulse](https://pulse.home.lab)               | 7655                              | LAN             | Proxmox monitoring                          |
| kopia                                         | 51515                             | LAN / Tailscale | Docker bind mounts → verona (Synology NAS)  |

## bishan (1001) — Personal services

| Container                              | Port      | Access          | Notes                                      |
| -------------------------------------- | --------- | --------------- | ------------------------------------------ |
| portainer_agent                        | 9001      | LAN             | Portainer management                       |
| [vaultwarden](https://vault.home.lab)  | 9080→80   | LAN / Tailscale | Password manager (Bitwarden-compatible)    |
| [actual](https://budget.home.lab)      | 5006      | LAN / Tailscale | Budget — Actual Budget                     |
| [home-assistant](https://ha.home.lab)  | —         | LAN / Tailscale | Home automation                            |
| home-assistant-matter-server           | —         | LAN             | Matter server (sidecar to home-assistant)  |
| [stirling-pdf](https://pdf.home.lab)   | 8080      | LAN / Tailscale | PDF tools                                  |
| [mealie](https://recipes.home.lab)     | 9925→9000 | LAN / Tailscale | Recipe manager                             |
| [homebox](https://homebox.home.lab)    | 3100→7745 | LAN / Tailscale | Home inventory                             |
| [kopia](https://kopia-bishan.home.lab) | 51515     | LAN / Tailscale | Docker bind mounts → verona (Synology NAS) |
| offers-api                             | 3000      | LAN             | Custom API                                 |

## bedok (1002) — Storage + Gitea + Media

| Container                                        | Port                                     | Access          | Notes                                                        |
| ------------------------------------------------ | ---------------------------------------- | --------------- | ------------------------------------------------------------ |
| [gitea](https://git.home.lab)                    | 3000, 222 (SSH)                          | LAN / Tailscale | `docker.gitea.com/gitea:1.25.5`                              |
| gitea-runner                                     | —                                        | —               | Gitea Actions runner; connects via external URL              |
| portainer_agent                                  | 9001                                     | LAN             | Portainer management                                         |
| [jellyfin](https://stream.home.lab)              | 8096 (HTTP), 7359 (UDP)                  | LAN / Tailscale | Media server                                                 |
| [filebrowser](https://files-bedok.home.lab)      | 8080→80                                  | LAN / Tailscale | Web file browser                                             |
| samba                                            | —                                        | LAN             | SMB file shares                                              |
| [scrypted](https://nvr.home.lab)                 | —                                        | LAN             | NVR / camera HomeKit bridge                                  |
| [kopia](https://kopia-bedok.home.lab)            | 51515                                    | LAN / Tailscale | Docker bind mounts → verona (Synology NAS)                   |
| **paperless stack**                              |                                          |                 |                                                              |
| [paperless-ngx](https://paperless.home.lab)      | 8010→8000                                | LAN / Tailscale | Document management                                          |
| [paperless-ai](https://paperless-ai.home.lab)    | 3100→3000                                | LAN             | AI document processor                                        |
| [paperless-gpt](https://paperless-gpt.home.lab)  | 8081→8080                                | LAN             | GPT integration for paperless                                |
| paperless-postgres                               | internal                                 | —               | DB for paperless-ngx                                         |
| paperless-redis                                  | internal                                 | —               | Cache/queue for paperless-ngx                                |
| paperless-gotenberg                              | internal                                 | —               | PDF generation                                               |
| paperless-tika                                   | internal                                 | —               | Document parsing                                             |

## braddell (1003) — LLM (RTX 3050 6GB)

| Container                                    | Port      | Access                   | Notes                                                                     |
| -------------------------------------------- | --------- | ------------------------ | ------------------------------------------------------------------------- |
| [local-ai-ollama](https://ollama.home.lab)   | 11434     | LAN / Tailscale          | GPU-backed inference                                                      |
| [local-ai-open-webui](https://gpt.home.lab)  | 3000→8080 | LAN / Tailscale          | Chat UI                                                                   |
| [local-ai-n8n](https://n8n.home.lab)         | 5678      | LAN / Tailscale / Funnel | Workflow automation; Funnel domain: `clementi.ts.net.private` (webhooks) |
| local-ai-postgres                            | internal  | —                        | DB for n8n / open-webui                                                   |
| [local-ai-qdrant](https://qdrant.home.lab)   | 6333      | LAN / Tailscale          | Vector DB                                                                 |
| [litellm](https://litellm.home.lab)          | 4000      | LAN / Tailscale          | OpenAI-compatible API proxy                                               |
| litellm-postgres                             | 5432      | LAN                      | DB for LiteLLM                                                            |
| [libretranslate](https://translate.home.lab) | 5000      | LAN / Tailscale          | Translation (CUDA)                                                        |
| [kopia](https://kopia-braddell.home.lab)     | 51515     | LAN / Tailscale          | Docker bind mounts → verona (Synology NAS)                                |
| portainer_agent                              | 9001      | LAN / Tailscale          | Portainer management                                                      |

### braddell — Ollama models

| Model                             | Size  | Notes                                   |
| --------------------------------- | ----- | --------------------------------------- |
| gemma4:latest                     | 9.6GB | Overflows 6GB VRAM into RAM             |
| aliafshar/gemma3-it-qat-tools:12b | 8.9GB | Tool use, instruction-tuned             |
| gemma3:12b                        | 8.1GB | —                                       |
| llama3.1:8b                       | 4.9GB | Fits entirely in 6GB VRAM               |
| minicpm-v:latest                  | 5.5GB | Multimodal                              |
| codegemma:latest                  | 5.0GB | Coding                                  |
| deepseek-ocr:3b                   | 6.7GB | OCR                                     |
| gemma3:4b / gemma3:latest         | 3.3GB | Fast, smaller                           |
| embeddinggemma:latest             | 621MB | Embeddings — feeds Qdrant               |
| translategemma:latest             | 3.3GB | Translation — pairs with libretranslate |
| functiongemma:latest              | 300MB | Function calling                        |

## verona — Synology DS218+ (NAS)

DSM packages — not Docker containers.

| Service                                       | Access          | Notes                                                                              |
| --------------------------------------------- | --------------- | ---------------------------------------------------------------------------------- |
| Synology Photos                               | LAN / Tailscale | Photo library                                                                      |
| Synology Drive                                | LAN / Tailscale | File sync                                                                          |
| [Synology DSM](https://dsm.home.lab)          | LAN             | DSM admin UI                                                                       |
| [Proxmox Backup Server](https://pbs.home.lab) | LAN             | Runs inside Synology VMM at `192.168.xx.xx`; stores Proxmox VM backups from changi |

## changi — Proxmox PVE host

| Service                            | Access | Notes                    |
| ---------------------------------- | ------ | ------------------------ |
| [Proxmox VE](https://pve.home.lab) | LAN    | Hypervisor management UI |

## florence — Synology MR2200AC (router)

| Service                                         | Access | Notes                                                             |
| ----------------------------------------------- | ------ | ----------------------------------------------------------------- |
| [Synology Router Manager](https://srm.home.lab) | LAN    | Router admin UI; double NAT permanent (Vodafone Hessen no bridge) |
