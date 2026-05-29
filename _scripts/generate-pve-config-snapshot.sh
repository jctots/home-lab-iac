#!/usr/bin/env bash
# generate-pve-config-snapshot.sh — snapshot Proxmox config via API → _snapshots/pve-config.yaml
# Requires: curl, jq
#
# Required env vars:
#   PROXMOX_TOKEN_ID     API token ID   (e.g. gitea-runner@pve!gitea-runner)
#   PROXMOX_TOKEN_SECRET API token UUID
#
# Token auth header format for PVE: PVEAPIToken=ID=SECRET (= separator, not : like PBS)
# Create token in Proxmox UI → Datacenter → API Tokens. Requires Sys.Audit + VM.Audit on /.
#
# Optional:
#   PROXMOX_HOST  (default: https://192.168.xx.xx:8006)
#   PROXMOX_NODE  (default: changi)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$SCRIPT_DIR/../_snapshots/pve-config.yaml"
PROXMOX_HOST="${PROXMOX_HOST:-https://192.168.xx.xx:8006}"
NODE="${PROXMOX_NODE:-changi}"

: "${PROXMOX_TOKEN_ID:?PROXMOX_TOKEN_ID must be set}"
: "${PROXMOX_TOKEN_SECRET:?PROXMOX_TOKEN_SECRET must be set}"

pve_get() {
  echo "GET /api2/json/$1" >&2
  curl -f -k \
    -H "Authorization: PVEAPIToken=${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}" \
    "${PROXMOX_HOST}/api2/json/$1"
}

{
  echo "generated: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  echo "source: \"Proxmox API — ${NODE}\""

  echo ""
  echo "storage:"
  pve_get "storage" | jq -r '
    .data[] |
    "  - id: \"" + .storage + "\"",
    "    type: \"" + .type + "\"",
    (if .path then "    path: \"" + .path + "\"" else empty end),
    (if .server then "    server: \"" + .server + "\"" else empty end),
    (if .export then "    export: \"" + .export + "\"" else empty end)
  '

  echo ""
  echo "backup_jobs:"
  pve_get "cluster/backup" | jq -r '
    .data[] |
    "  - id: \"" + .id + "\"",
    "    vmid: \"" + (.vmid // "all") + "\"",
    "    storage: \"" + .storage + "\"",
    "    schedule: \"" + .schedule + "\"",
    (if .mode then "    mode: \"" + .mode + "\"" else empty end),
    (if ."prune-backups" then "    prune_backups: \"" + (."prune-backups" | to_entries | map(.key + "=" + (.value | tostring)) | join(",")) + "\"" else empty end)
  '

  echo ""
  echo "network:"
  pve_get "nodes/${NODE}/network" | jq -r '
    .data[] |
    "  - iface: \"" + .iface + "\"",
    "    type: \"" + .type + "\"",
    (if .address then "    address: \"" + .address + "\"" else empty end),
    (if .gateway then "    gateway: \"" + .gateway + "\"" else empty end),
    (if .bridge_ports then "    bridge_ports: \"" + .bridge_ports + "\"" else empty end)
  '

  echo ""
  echo "vm_configs:"
  pve_get "nodes/${NODE}/qemu" | jq -r '.data[].vmid' | sort -n | while read -r vmid; do
    echo "  - vmid: ${vmid}"
    pve_get "nodes/${NODE}/qemu/${vmid}/config" | jq -r '
      .data |
      (if .name    then "    name: \""   + .name            + "\""       else empty end),
      (if .cores   then "    cores: "    + (.cores   | tostring)          else empty end),
      (if .memory  then "    memory: "   + (.memory  | tostring)          else empty end),
      (if .net0    then "    net0: \""   + .net0             + "\""       else empty end),
      (if .scsi0   then "    scsi0: \""  + .scsi0            + "\""       else empty end),
      (if .boot    then "    boot: \""   + .boot             + "\""       else empty end)
    '
  done
} > "$OUTPUT"

echo "Done — pve-config snapshot written to $OUTPUT"
