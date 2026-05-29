#!/bin/bash
# Generates current image SHA for each running Docker container in YAML format
# Format: hostname as level 1, container name and image hash as level 2
# Usage: bash _scripts/generate-image-snapshot.sh

set -euo pipefail

HOSTNAME=$(hostname)

echo "${HOSTNAME}:"

docker ps --no-trunc --format '{{.Names}}' | while IFS= read -r cname; do
  sha=$(docker inspect --format '{{.Image}}' "$cname" 2>/dev/null || echo "N/A")
  echo "  ${cname}: \"${sha}\""
done
