#!/usr/bin/env bash
# Deploy all stacks for this VM.
# Runs docker compose up -d for every service in:
#   - <hostname>/ (VM-specific stacks)
#   - shared/     (stacks running on all VMs)
#
# Usage: bash _scripts/deploy.sh
# Run from the repo root on the target VM.

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

deploy_folder() {
  local folder="$1"
  for service_dir in "$folder"/*/; do
    [ -f "$service_dir/docker-compose.yml" ] || continue
    service=$(basename "$service_dir")
    echo "Deploying $service..."
    docker compose -f "$service_dir/docker-compose.yml" up -d
  done
}

echo "=== Deploying shared stacks ==="
deploy_folder "$SHARED_DIR"

echo ""
echo "=== Deploying $HOSTNAME stacks ==="
deploy_folder "$VM_DIR"

echo ""
echo "Done."
