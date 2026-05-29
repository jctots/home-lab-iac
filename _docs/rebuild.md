# Full rebuild procedure

[← README](../README.md)

End-to-end procedure for rebuilding the home lab from scratch. See [hardware.md](hardware.md) for hardware specs and known issues, [provisioning.md](provisioning.md) for the VM creation and deployment workflow, and [scripts.md](scripts.md) for the script reference.

## Overview

```
1. changi (Proxmox host)
     └─► 2. VM templates (9001 → 9002 → 9003)
               └─► 3. Production VMs (bishan, bedok, braddell)
4. clementi (Rprivatey Pi — independent of Proxmox)
5. Clone repo + deploy containers on each VM
```

---

## 1. changi — Proxmox host

Install Proxmox on the Lenovo ThinkCentre M720q, then apply the host config:

- Fix the NIC hardware hang — see `changi/changi-host-config.md` and [hardware.md](hardware.md) § Known issues
- Install git: `apt install git`

---

## 2. VM templates

Create the template chain in order. See `changi/` for the full procedure per template.

```
9001-linux-no-media.md   ← blank VM shell
9002-trixie-qemu.md      ← + Debian Trixie cloud image + qemu-guest-agent
9003-trixie-portainer.md ← + Docker + portainer-agent
```

---

## 3. Production VMs

Clone the repo on changi first:

```bash
git clone --filter=blob:none --sparse https://git.home.lab/homelab-user/home-lab-iac.git ~/stacks
cd ~/stacks
git sparse-checkout set changi/ _scripts/
```

For each VM (bishan, bedok, braddell), run the creation script then follow the manual steps:

```bash
bash changi/_setup/1001-bishan.sh   && # follow changi/1001-bishan.md
bash changi/_setup/1002-bedok.sh    && # follow changi/1002-bedok.md
bash changi/_setup/1003-braddell.sh    # follow changi/1003-braddell.md
```

---

## 4. clementi — Rprivatey Pi

clementi is a physical Rprivatey Pi 4 running Rprivatey Pi OS. It is not managed by Proxmox.

1. Flash Rprivatey Pi OS (64-bit, Lite) to SD card
2. Enable SSH, set hostname to `clementi`, assign static IP `192.168.xx.xx` in florence DHCP
3. Copy the age key from the operator machine:
   ```bash
   scp ~/.config/sops/age/keys.txt homelab-admin@clementi:~/.config/sops/age/keys.txt
   ```
4. Run the setup script:
   ```bash
   bash clementi/_setup/clementi-setup.sh
   ```

---

## 5. Deploy containers on each VM

On each VM (bishan, bedok, braddell, clementi):

### 5.1 Clone the repo

```bash
git clone --filter=blob:none --sparse https://git.home.lab/homelab-user/home-lab-iac.git ~/stacks
cd ~/stacks
git sparse-checkout set <hostname>/ shared/ _scripts/
```

### 5.2 Install tools

```bash
sudo bash _scripts/setup-debian.sh
```

### 5.3 Copy the age key and set env var

```bash
# Copy key from secure storage (password manager or operator machine)
scp operator@<your-machine>:~/age-key-home-lab-iac.txt ~/age-key-home-lab-iac.txt

# Add to ~/.bashrc
echo 'export SOPS_AGE_KEY_FILE=~/age-key-home-lab-iac.txt' >> ~/.bashrc
source ~/.bashrc
```

### 5.4 Decrypt .env files

```bash
find ~/stacks -name ".env" | xargs -I{} sops --decrypt --in-place {}
```

### 5.5 Deploy all stacks

```bash
bash ~/stacks/_scripts/deploy.sh
```

---

## 6. Link stacks to Gitea in Portainer

Portainer is used for **pulling validated updates** — not for editing or testing. The workflow is:

1. **Test on the VM first** — edit the compose file in the local clone (`~/stacks/<vm>/<stack>/docker-compose.yml`), deploy with `docker compose up -d`, verify it works
2. **Commit and push** to Gitea once validated
3. **Portainer "Pull and redeploy"** to apply the update across environments, or `git pull && docker compose up -d` via CLI

> Never edit compose files in Portainer's web editor — git is the source of truth.

### 6.1 Generate a Gitea access token

In Gitea: **Settings → Applications → Generate Token**
- Token name: `portainer` (read-only is sufficient)
- Permission: `repository` read

Save the token — shown only once.

### 6.2 Add a stack from repository

In Portainer (https://clementi:9443):

1. **Stacks → Add stack**
2. Name the stack (e.g. `nginx-proxy-manager`)
3. Build method: **Repository**
4. Repository URL: `https://git.home.lab/homelab-user/home-lab-iac.git`
5. Authentication: enable → Username: `homelab-user` → Password: *(paste token)*
6. Compose path: `clementi/nginx-proxy-manager/docker-compose.yml`
   *(use `<vm>/<stack>/docker-compose.yml` for each stack)*
7. **Deploy the stack**

Repeat for each stack on each environment.

### 6.3 Updating a stack via Portainer

After committing and pushing a compose file change to Gitea:

**Stacks → select stack → Pull and redeploy**

Portainer fetches the latest compose file from Gitea and recreates affected containers.

---

## 7. CI pipeline setup

The CI runner runs on bedok (act_runner). After the VMs are deployed, configure the pipeline secrets and SSH access.

### 7.1 Generate the CI SSH keypair

Generate a dedicated keypair in Bitwarden (SSH Key item, name: `gitea-runner`). This keypair is used by the runner to SSH into all VMs and florence.

### 7.2 Add the runner public key to each VM

On each VM (bishan, bedok, braddell, clementi) as `homelab-admin`:

```bash
echo "ssh-ed25519 <gitea-runner-pubkey> gitea-runner" >> ~/.ssh/authorized_keys
```

### 7.2a Create homelab-admin user on changi and add runner public key

The `generate-setup-scripts` workflow SSHes to changi as `homelab-admin` (in `www-data` group) to read Proxmox config files via pmxcfs.

```bash
useradd -m -G www-data homelab-admin
mkdir -p /home/homelab-admin/.ssh
echo "ssh-ed25519 <gitea-runner-pubkey> gitea-runner" >> /home/homelab-admin/.ssh/authorized_keys
chmod 700 /home/homelab-admin/.ssh && chmod 600 /home/homelab-admin/.ssh/authorized_keys
chown -R homelab-admin:homelab-admin /home/homelab-admin/.ssh
```

### 7.3 Add the runner public key to florence

Florence stores authorized keys at a non-standard path (`/etc/ssh/keys/%u/authorized_keys`):

```bash
sudo mkdir -p /etc/ssh/keys/homelab-user
echo "ssh-ed25519 <gitea-runner-pubkey> gitea-runner" | sudo tee /etc/ssh/keys/homelab-user/authorized_keys
sudo chown -R homelab-user:users /etc/ssh/keys/homelab-user
sudo chmod 700 /etc/ssh/keys/homelab-user && sudo chmod 600 /etc/ssh/keys/homelab-user/authorized_keys
```

### 7.4 Create the Proxmox API token

In the Proxmox web UI (`https://proxmox.home.lab` or `https://192.168.xx.xx:8006`):

1. **Datacenter → Permissions → API Tokens → Add**
   - User: `root@pam`, Token name: `gitea-runner`, leave Privilege Separation **enabled** (default)
2. **Datacenter → Permissions → Add → API Token** (not "User")
   - Path: `/`, API Token: `root@pam!gitea-runner`, Role: `PVEAuditor`, Propagate: ✓

Save the token secret — shown only once.

### 7.5 Create the PBS API token

In the PBS web UI (`https://pbs.home.lab`):

1. **Configuration → Access Control → API Tokens → Add**
   - User: `root@pam`, Token name: `gitea-runner`
2. **Configuration → Access Control → Permissions → Add**
   - Path: `/`, API Token: `root@pam!gitea-runner`, Role: `Administrator`

Save the token secret — shown only once.

### 7.6 Set Gitea Actions secrets

In the Gitea repo: **Settings → Secrets → Actions**, add:

| Secret | Value |
|---|---|
| `SSH_PRIVATE_KEY` | gitea-runner private key (from Bitwarden) |
| `PBS_TOKEN_ID` | `root@pam!gitea-runner` |
| `PBS_TOKEN_SECRET` | PBS token secret |
| `PROXMOX_TOKEN_ID` | `root@pam!gitea-runner` |
| `PROXMOX_TOKEN_SECRET` | Proxmox token secret |
| `NPM_EMAIL` | nginx-proxy-manager login email |
| `NPM_PASSWORD` | nginx-proxy-manager login password |

---

## Verification

After deployment, check all containers are running:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Capture a working-state snapshot (see [_docs/snapshots](#)):

```bash
bash ~/stacks/_scripts/generate-image-snapshot.sh > ~/stacks/_snapshots/image-hash-$(hostname).yaml
cd ~/stacks && git add _snapshots/ && git commit -m "snapshot: $(hostname)" && git push
```
