# Secrets management

[← README](../README.md)

`.env` files are encrypted with SOPS + age and committed to the repo.

## Tools

- **age** — key generation and management
- **SOPS** — encrypts/decrypts `.env` files using the age key

Install on Windows: `_scripts/setup-windows.ps1`
Install on Debian VMs: `sudo bash _scripts/setup-debian.sh`

## Initial setup (once per operator)

Generate an age key:

```bash
age-keygen -o ~/age-key-home-lab-iac.txt
```

The file contains a public key (safe to share) and a private key (keep secret). The public key is already registered in `.sops.yaml` at the repo root — if you generate a new key, update `.sops.yaml` with the new public key and re-encrypt all `.env` files.

Store `age-key-home-lab-iac.txt` securely — password manager or encrypted storage. Never commit it.

## Distributing the key to a VM

Copy the key file to the VM over SSH:

```bash
scp ~/age-key-home-lab-iac.txt <vm-user>@<vm-ip>:~/age-key-home-lab-iac.txt
```

Set the environment variable so SOPS finds the key. Add to `~/.bashrc` or `~/.profile` on the VM:

```bash
export SOPS_AGE_KEY_FILE=~/age-key-home-lab-iac.txt
```

## Encrypting a new .env file

```bash
export SOPS_AGE_KEY_FILE=~/age-key-home-lab-iac.txt
sops --encrypt --in-place <vm>/<service>/.env
```

## Decrypting before use

```bash
export SOPS_AGE_KEY_FILE=~/age-key-home-lab-iac.txt
sops --decrypt --in-place <vm>/<service>/.env
```

Re-encrypt before committing:

```bash
sops --encrypt --in-place <vm>/<service>/.env
```

> **Never commit a plaintext `.env`.** If you accidentally do, rotate the exposed keys immediately.

## Updating a secret value

1. Decrypt: `sops --decrypt --in-place <vm>/<service>/.env`
2. Edit the value.
3. Re-encrypt: `sops --encrypt --in-place <vm>/<service>/.env`
4. Commit and push.

## Key rotation

1. Generate a new age key: `age-keygen -o ~/age-key-home-lab-iac-new.txt`
2. Update `.sops.yaml` with the new public key.
3. For each `.env` file: decrypt with old key, re-encrypt with new key.
4. Distribute the new key to all VMs.
5. Remove the old key from all machines.

---

## Gitea Actions secrets

CI pipeline secrets stored in Gitea repo **Settings → Secrets → Actions**:

| Secret | Purpose | Permissions | Stored in |
|---|---|---|---|
| `SSH_PRIVATE_KEY` | Runner SSH key for VMs + florence | SSH login as `homelab-admin` on all VMs; as `homelab-user` on florence; as `homelab-admin` on changi | Bitwarden — "gitea-runner" SSH key item |
| `PBS_TOKEN_ID` | PBS API token ID | Administrator role on `/` in PBS (required for datastore + prune/verify job access) | `root@pam!gitea-runner` (literal) |
| `PBS_TOKEN_SECRET` | PBS API token secret | — | Bitwarden — "PBS gitea-runner token" |
| `PROXMOX_TOKEN_ID` | Proxmox API token ID | PVEAuditor role on `/` in Proxmox (read-only: storage, backup jobs, network, VM configs) | `root@pam!gitea-runner` (literal) |
| `PROXMOX_TOKEN_SECRET` | Proxmox API token secret | — | Bitwarden — "Proxmox gitea-runner token" |
| `NPM_EMAIL` | nginx-proxy-manager login | NPM admin — read proxy host list | Bitwarden — NPM credentials |
| `NPM_PASSWORD` | nginx-proxy-manager login | — | Bitwarden — NPM credentials |
| `GH_PAT` | GitHub fine-grained PAT for public mirror sync | Contents: read/write on `homelab-user/home-lab-iac` only | Bitwarden — "GitHub PAT home-lab-iac sync" |

The SSH public key must be present in `authorized_keys` on all VMs, florence, and changi (homelab-admin user). See [rebuild.md](rebuild.md) § 7 for setup procedure.

---

See also: [security.md](security.md) — age key and SOPS are covered in the CI and secrets threat section · [failures.md](failures.md) — recovery procedures for key loss and compromise
