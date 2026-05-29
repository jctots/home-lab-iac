#!/usr/bin/env bash
# Creation script for bedok (1002)
# Generated: 2026-05-19 — re-run _scripts/generate-vm-setup.sh to update
# Run on changi as root

set -euo pipefail

# 1. Clone from template and apply hardware profile
qm clone 9003 1002 --name bedok && \
qm set 1002 \n  --cores 4 \n  --memory 8192 \n  --onboot 1 \n  --vga serial0

# 2. Add to DHCP reservation, then stop VM
# qm stop 1002

# 3. Remove cloud-init drive and start VM
# qm set 1002 --delete ide2 && qm start 1002

# Manual steps after boot — see 1002-bedok.md
