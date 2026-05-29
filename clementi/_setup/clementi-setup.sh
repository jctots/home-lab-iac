#!/usr/bin/env bash
# clementi-setup.sh — provision clementi (Rprivatey Pi 4) from a fresh Rprivatey Pi OS Lite install
# Run as the default pi/homelab-admin user after first SSH login.
# Prerequisites: SSH enabled, hostname set to clementi, static IP 192.168.xx.xx in florence DHCP.

set -euo pipefail

echo "=== 1. System update ==="
sudo apt update && sudo apt dist-upgrade -y

echo ""
echo "=== 2. Docker ==="
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
echo "Docker installed. Log out and back in for group membership to take effect."

echo ""
echo "=== 3. SOPS + age ==="
# setup-debian.sh installs age and SOPS
sudo bash ~/stacks/_scripts/setup-debian.sh

echo ""
echo "=== 4. Clone IaC repo ==="
git clone --filter=blob:none --sparse https://git.home.lab/homelab-user/home-lab-iac.git ~/stacks
cd ~/stacks
git sparse-checkout set clementi/ shared/ _scripts/

echo ""
echo "=== 5. Decrypt secrets ==="
# Copy age key from operator machine first:
#   scp ~/.config/sops/age/keys.txt homelab-admin@clementi:~/.config/sops/age/keys.txt
echo "Ensure age key is at ~/.config/sops/age/keys.txt before continuing."
echo "Then run: cd ~/stacks && bash _scripts/deploy.sh"

echo ""
echo "=== 6. Tailscale ==="
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --advertise-exit-node --advertise-routes=192.168.xx.xx/24
echo "Complete auth in Tailscale admin console."
echo "Enable exit node + subnet router approval at https://login.tailscale.com/admin/machines"

echo ""
echo "=== 7. Manual steps ==="
echo "After containers are running:"
echo "  a. Portainer CE: set admin password, add all VM agents"
echo "  b. nginx-proxy-manager: restore proxy host config from _snapshots/npm.yaml"
echo "  c. Verify all *.home.lab subdomains resolve correctly"
echo "  d. Homepage: no config needed (mounts from clementi/homepage/)"
echo "  e. Pulse: connect to changi at 192.168.xx.xx"
echo ""
echo "Done — run 'bash ~/stacks/_scripts/deploy.sh' to deploy containers."
