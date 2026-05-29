#!/usr/bin/env bash
# Run on changi to capture current VM configs and generate creation scripts.
# Outputs <vmid>-<name>.yaml (full config snapshot) to _snapshots/ and <vmid>-<name>.sh (qm commands)
# to changi/setup-scripts/.
# Requires: homelab-admin user in www-data group on changi (reads /etc/pve/ via pmxcfs)
#
# Usage: bash _scripts/generate-vm-setup.sh

set -euo pipefail

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPTS_DIR="$REPO_DIR/changi/_setup"
SNAPSHOTS_DIR="$REPO_DIR/_snapshots"
mkdir -p "$SCRIPTS_DIR" "$SNAPSHOTS_DIR"

# Remove stale outputs so deleted VMs don't persist
rm -f "$SNAPSHOTS_DIR"/vm-*.yaml "$SCRIPTS_DIR"/[0-9]*.sh

# Production VMs only — templates (9002, 9003) use a different creation
# procedure (cloud image import) and are documented manually in changi/*.md
VMS=(
  "1001:bishan:9003"
  "1002:bedok:9003"
  "1003:braddell:9003"
)

for vm in "${VMS[@]}"; do
  VMID=$(echo "$vm" | cut -d: -f1)
  NAME=$(echo "$vm" | cut -d: -f2)
  CLONE_SOURCE=$(echo "$vm" | cut -d: -f3)

  echo "Processing $VMID ($NAME)..."

  CONFIG=$(cat "/etc/pve/nodes/changi/qemu-server/${VMID}.conf")

  # Save full config as YAML snapshot
  python3 - <<PYEOF > "$SNAPSHOTS_DIR/vm-${VMID}-${NAME}.yaml"
import sys, datetime

config_text = """${CONFIG}"""
generated = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

fields = {}
for line in config_text.splitlines():
    line = line.strip()
    if not line or line.startswith('#') or ':' not in line:
        continue
    key, _, val = line.partition(': ')
    fields[key.strip()] = val.strip()

print(f'generated: "{generated}"')
print(f'vmid: {${VMID}}')
print(f'name: "{fields.get("name", "")}"')
print()
print('hardware:')
for key in ('cores', 'sockets', 'memory', 'balloon', 'cpu', 'machine', 'bios', 'ostype'):
    if key in fields:
        val = fields[key]
        print(f'  {key}: "{val}"')
print()
print('network:')
for key in sorted(k for k in fields if k.startswith('net')):
    print(f'  {key}: "{fields[key]}"')
print()
print('disks:')
for key in sorted(k for k in fields if any(k.startswith(p) for p in ('scsi', 'ide', 'sata', 'virtio', 'efidisk'))):
    print(f'  {key}: "{fields[key]}"')
print()
print('pcie_passthrough:')
pcie = [k for k in fields if k.startswith('hostpci')]
if pcie:
    for key in sorted(pcie):
        print(f'  {key}: "{fields[key]}"')
else:
    print('  []')
print()
print('options:')
for key in ('onboot', 'agent', 'serial0', 'vga', 'scsihw', 'numa'):
    if key in fields:
        print(f'  {key}: "{fields[key]}"')
PYEOF

  # Extract settings for qm set
  CORES=$(echo "$CONFIG"  | awk -F': ' '/^cores:/   {print $2}')
  MEMORY=$(echo "$CONFIG" | awk -F': ' '/^memory:/  {print $2}')
  ONBOOT=$(echo "$CONFIG" | awk -F': ' '/^onboot:/  {print $2}')
  MACHINE=$(echo "$CONFIG"| awk -F': ' '/^machine:/ {print $2}')
  BIOS=$(echo "$CONFIG"   | awk -F': ' '/^bios:/    {print $2}')
  VGA=$(echo "$CONFIG"    | awk -F': ' '/^vga:/     {print $2}')

  SET_ARGS=""
  [ -n "$CORES" ]   && SET_ARGS+=" \\\n  --cores $CORES"
  [ -n "$MEMORY" ]  && SET_ARGS+=" \\\n  --memory $MEMORY"
  [ -n "$ONBOOT" ]  && SET_ARGS+=" \\\n  --onboot $ONBOOT"
  [ -n "$MACHINE" ] && SET_ARGS+=" \\\n  --machine $MACHINE"
  [ -n "$BIOS" ]    && SET_ARGS+=" \\\n  --bios $BIOS"
  [ -n "$VGA" ]     && SET_ARGS+=" \\\n  --vga $VGA"

  # EFI disk (needed for OVMF/UEFI VMs)
  EFIDISK=$(echo "$CONFIG" | awk -F': ' '/^efidisk0:/ {print $2}')
  [ -n "$EFIDISK" ] && SET_ARGS+=" \\\n  --efidisk0 local-lvm:0,efitype=4m"

  # PCIe passthrough devices
  while IFS= read -r line; do
    KEY=$(echo "$line" | awk '{print $1}' | tr -d ':')
    VAL=$(echo "$line" | awk '{print $2}')
    SET_ARGS+=" \\\n  --${KEY} ${VAL}"
  done < <(echo "$CONFIG" | grep "^hostpci")

  # Write creation script
  cat > "$SCRIPTS_DIR/${VMID}-${NAME}.sh" <<EOF
#!/usr/bin/env bash
# Creation script for ${NAME} (${VMID})
# Generated: $(date +%Y-%m-%d) — re-run _scripts/generate-vm-setup.sh to update
# Run on changi as root

set -euo pipefail

# 1. Clone from template and apply hardware profile
qm clone ${CLONE_SOURCE} ${VMID} --name ${NAME} && \\
qm set ${VMID}$(echo -e "$SET_ARGS")

# 2. Add to DHCP reservation, then stop VM
# qm stop ${VMID}

# 3. Remove cloud-init drive and start VM
# qm set ${VMID} --delete ide2 && qm start ${VMID}

# Manual steps after boot — see ${VMID}-${NAME}.md
EOF
  chmod +x "$SCRIPTS_DIR/${VMID}-${NAME}.sh"

  echo "  -> _snapshots/vm-${VMID}-${NAME}.yaml + changi/_setup/${VMID}-${NAME}.sh"
done

echo ""
echo "Done. Commit changi/_setup/ and _snapshots/ to update the IaC record."
