#!/usr/bin/env bash
# generate-npm-snapshot.sh — dump NPM proxy hosts to _snapshots/npm.yaml
# Requires: curl, jq
# Usage: NPM_EMAIL=admin@example.com NPM_PASSWORD=secret ./generate-npm-snapshot.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOTS_DIR="$SCRIPT_DIR/../_snapshots"
OUTPUT="$SNAPSHOTS_DIR/npm.yaml"
NPM_BASE="https://proxy.home.lab"

: "${NPM_EMAIL:?NPM_EMAIL must be set}"
: "${NPM_PASSWORD:?NPM_PASSWORD must be set}"

mkdir -p "$SNAPSHOTS_DIR"

echo "Authenticating against $NPM_BASE..."
TOKEN=$(curl -f "$NPM_BASE/api/tokens" \
  -H "Content-Type: application/json" \
  -d "{\"identity\":\"$NPM_EMAIL\",\"secret\":\"$NPM_PASSWORD\"}" \
  | jq -r '.token')

: "${TOKEN:?Authentication failed — empty token returned from $NPM_BASE}"

echo "Fetching proxy hosts..."
curl -f "$NPM_BASE/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" \
  | jq -r '
    "generated: \"" + (now | todate) + "\"",
    "source: \"https://proxy.home.lab\"",
    "proxy_hosts:",
    (sort_by(.domain_names[0])[] |
      "  - domains:",
      (.domain_names[] | "      - \"" + . + "\""),
      "    upstream: \"" + .forward_scheme + "://" + .forward_host + ":" + (.forward_port | tostring) + "\"",
      "    enabled: " + (if .enabled then "true" else "false" end)
    )
  ' > "$OUTPUT"

COUNT=$(grep -c '^ *- domains:' "$OUTPUT" || true)
echo "Done — $COUNT proxy hosts written to $OUTPUT"
