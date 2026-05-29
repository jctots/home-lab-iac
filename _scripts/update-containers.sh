#!/usr/bin/env bash
# Pull latest images and redeploy all stacks for this VM.
# Run on the target VM after check-backup-status passes and image hashes are snapshotted.
# Mirrors deploy.sh — pulls before starting each service.
#
# Usage: bash _scripts/update-containers.sh
# Run from the repo root on the target VM.
#
# Manual checks required after (see _docs/update.md):
#   bedok: verify Gitea version (no version skip), verify private VPN routing

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOSTNAME=$(hostname)
VM_DIR="$REPO_DIR/$HOSTNAME"
SHARED_DIR="$REPO_DIR/shared"

if [ ! -d "$VM_DIR" ]; then
  echo "Error: no folder found for hostname '$HOSTNAME' in repo root."
  echo "Expected: $VM_DIR"
  exit 1
fi

update_folder() {
  local folder="$1"
  for service_dir in "$folder"/*/; do
    [ -f "$service_dir/docker-compose.yml" ] || continue
    service=$(basename "$service_dir")
    echo "==> $service"
    docker compose -f "$service_dir/docker-compose.yml" pull
    docker compose -f "$service_dir/docker-compose.yml" up -d
    echo ""
  done
}

echo "=== Updating shared stacks ==="
update_folder "$SHARED_DIR"

echo "=== Updating $HOSTNAME stacks ==="
update_folder "$VM_DIR"

echo "Done."
