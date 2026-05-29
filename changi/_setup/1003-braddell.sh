#!/usr/bin/env bash
# Creation script for braddell (1003)
# Generated: 2026-05-19 — re-run _scripts/generate-vm-setup.sh to update
# Run on changi as root

set -euo pipefail

# 1. Clone from template and apply hardware profile
qm clone 9003 1003 --name braddell && \
qm set 1003 \n  --cores 4 \n  --memory 16384 \n  --onboot 1 \n  --machine q35 \n  --bios ovmf \n  --vga none \n  --efidisk0 local-lvm:0,efitype=4m \n  --hostpci0 01:00,pcie=1,x-vga=1

# 2. Add to DHCP reservation, then stop VM
# qm stop 1003

# 3. Remove cloud-init drive and start VM
# qm set 1003 --delete ide2 && qm start 1003

# Manual steps after boot — see 1003-braddell.md
