# Security

[← README](../README.md)

Threat analysis for the home lab. Purpose: identify the attack surface, understand blast radius per threat, and prioritise mitigations.

**Threat model:** home lab, personal use. Not a hardened production environment. Security decisions may trade hardening for simplicity where the risk is personal/private only. Physical access attacks and nation-state threats are out of scope.

**Severity:** Critical = credential/system compromise with wide blast radius · High = significant exposure or data loss · Medium = limited or conditional risk · Low = minimal realistic risk

**Status:** Mitigated · Partial · Accepted · Open
- *Accepted* = known risk, within home lab threat model, not worth the operational cost to mitigate

---

## Attack surface

| Zone | What is reachable | How |
|---|---|---|
| Internet (anyone) | n8n webhook endpoint only | Tailscale Funnel → braddell:5678 |
| Internet (anyone) | Gitea (`git.home.lab`) | nginx-proxy-manager → bedok:3000 |
| Tailscale (authenticated devices) | All services marked LAN / Tailscale in [services.md](services.md) | Tailscale subnet routing via clementi |
| LAN 192.168.xx.xx/24 | All services on all hosts | Flat network — see [network.md](network.md) for topology |
| IoT (ssid-iot SSID) → LAN | All LAN hosts | Wireless isolation only; no VLAN — see [iot.md](iot.md) |

Everything not in this table is internal-only (docker-internal or localhost).

---

## Exposed endpoints

| Sev | Component | Threat | Impact | Detection | Mitigation | Response | Status |
|---|---|---|---|---|---|---|---|
| High | n8n Funnel (braddell:5678) | Unauthenticated webhook triggers | Anyone who discovers the Funnel URL can trigger n8n workflows — including destructive automations | Unexpected workflow executions in n8n audit log | Enable n8n webhook authentication (header secret) on all public-facing webhook nodes; Funnel URL is not publicly listed | Disable Funnel; audit and revert triggered workflows | Partial |
| High | Gitea (`git.home.lab`) | Internet-facing git server with CI secrets inside | Brute-force or credential stuffing attack on Gitea accounts; if successful: repo access + SSH_PRIVATE_KEY CI secret = SSH access to all VMs | Gitea failed login logs; unexpected repo access or CI runs | Strong Gitea admin password; disable user registration; enable 2FA on Gitea admin account | Rotate SSH_PRIVATE_KEY; audit CI job history; revoke compromised Gitea session | Partial |
| Medium | Gitea SSH (port 222) | SSH exposed via port forwarding | Direct SSH brute-force against Gitea's SSH port | Auth log on bedok | Key-based auth only; disable password auth for Gitea SSH | Block IP; review auth logs | Partial |

---

## LAN trust and lateral movement

| Sev | Component | Threat | Impact | Detection | Mitigation | Response | Status |
|---|---|---|---|---|---|---|---|
| High | Portainer CE (clementi) | Portainer compromise = all containers compromised | Attacker can deploy, modify, or destroy any container on any VM | Unexpected container changes in Portainer audit log | Strong Portainer admin password; 2FA if supported; Portainer on LAN/Tailscale only (not internet-facing) | Rotate Portainer credentials; audit all container states; treat all VMs as potentially modified | Partial |
| High | Docker socket (all VMs) | Container escape via /var/run/docker.sock | Any container with socket access can become root on the host | Unexpected processes on host; rootkit indicators | Inherent to Portainer agent design; accepted for home lab | Rebuild affected VM from PBS/kopia; rotate all credentials on that host | Accepted |
| Medium | Ollama (braddell:11434) | Unauthenticated API on LAN | API abuse — model inference at cost (GPU compute); prompt injection if exposed via automation | Unexpectedly high GPU utilisation | Ollama has no built-in auth; mitigated by LAN/Tailscale scope only; IoT VLAN isolation removes IoT as a vector once implemented | Block at host firewall if compromise suspected | Partial |
| Medium | LiteLLM (braddell:4000) | API key brute-force or key leak from LAN | Unauthorised API calls charged to upstream providers (Anthropic, Google) | Unexpected billing spike; LiteLLM request logs | LLM_MASTER_KEY required; LAN/Tailscale only; rotate exposed key — see `failures.md` Secrets section | Rotate LLM_MASTER_KEY and upstream API keys | Partial |
| Medium | Qdrant (braddell:6333) | Unauthenticated vector DB on LAN | Read or delete of embeddings/vector data | Unexpected API calls in Qdrant logs | Qdrant has optional API key auth — enable it; LAN/Tailscale only | Rebuild Qdrant collections from source data | Open |
| Medium | litellm-postgres (braddell:5432) | DB port accessible on LAN | Direct DB access if postgres auth is weak | Unexpected connections in postgres logs | Verify postgres is not bound to 0.0.0.0; should be docker-internal only | Rotate DB credentials; audit data | Open |
| Low | IoT lateral movement | Compromised IoT device reaches LAN hosts | IoT device accesses services or scans hosts on 192.168.xx.xx/24 | Anomalous LAN traffic from 192.168.xx.xx–254 range | VLAN isolation planned (see `failures.md`); wireless isolation is current partial mitigation | Isolate device on florence; block MAC | Planned |
| Low | Homepage (clementi:3000) | No auth — exposes service map | Attacker with LAN access sees all service URLs and hosts | — | Acceptable for home lab; LAN/Tailscale only; no sensitive data on the page | — | Accepted |

---

## CI and secrets

| Sev | Component | Threat | Impact | Detection | Mitigation | Response | Status |
|---|---|---|---|---|---|---|---|
| Critical | SSH_PRIVATE_KEY (Gitea CI secret) | Key leaked via Gitea compromise or malicious workflow | SSH access to all VMs from the CI runner on bedok | Unexpected SSH sessions on VMs; unknown CI jobs | Scope the key to minimum required hosts; review which workflows consume it; rotate regularly | Rotate key immediately; audit SSH auth logs on all VMs; review recent CI runs | Partial |
| High | n8n credential store (braddell postgres) | braddell compromise exposes all n8n credentials | All API keys, webhook secrets, and integration credentials stored in n8n are readable | Silent until credentials are abused | n8n credentials are encrypted at rest (n8n uses AES encryption with N8N_ENCRYPTION_KEY); ensure N8N_ENCRYPTION_KEY is in SOPS-encrypted `.env` | Rotate all n8n credentials; regenerate N8N_ENCRYPTION_KEY and re-enter all credentials | Partial |
| High | SOPS age key on VMs | Age key file compromised on a VM | All encrypted `.env` files in the repo are decryptable | Silent | Key stored at `~/age-key-home-lab-iac.txt` — restrict file permissions (`chmod 600`); never in Docker volumes or env vars | Rotate age key — see `failures.md` → rotate-age-key | Partial |
| Medium | Gitea repo — network topology exposed | Repo accessible to attacker | Attacker learns IP layout, service names, and port map — useful for targeted LAN attacks | — | All Gitea repos are Private; secrets are SOPS-encrypted | Verify repo visibility after any Gitea upgrade or settings change | Mitigated |

---

## Incident response

No formal playbook — home lab threat model. General steps when a compromise is suspected:

1. **Isolate** — disconnect the affected host from the network (florence DHCP lease, or physical cable) to stop lateral movement
2. **Assess blast radius** — identify what credentials or services were accessible from the compromised host (cross-reference attack surface table above)
3. **Rotate credentials** — rotate all secrets accessible from the compromised host before reconnecting anything: SSH keys, API keys, Gitea passwords, n8n credentials, age key if on the host
4. **Rebuild** — restore VM from PBS snapshot (pre-compromise) or rebuild from scratch; restore data from kopia
5. **Audit** — check logs on adjacent hosts for signs of lateral movement before declaring all-clear

Credential rotation procedures: see [failures.md](failures.md) → rotate-api-keys and rotate-age-key. For SOPS and age key management, see [secrets.md](secrets.md).
