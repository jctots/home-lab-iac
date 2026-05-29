#!/usr/bin/env bash
# generate-pbs-config-snapshot.sh — snapshot PBS config and status via API → _snapshots/pbs-config.yaml
# Requires: curl, jq
#
# Required env vars:
#   PBS_TOKEN_ID     PBS API token ID (e.g. root@pam!gitea-runner)
#   PBS_TOKEN_SECRET PBS API token secret
#
# Optional:
#   PBS_HOST       (default: https://192.168.xx.xx:8007)
#   PBS_DATASTORE  (default: datastore)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$SCRIPT_DIR/../_snapshots/pbs-config.yaml"
PBS_HOST="${PBS_HOST:-https://192.168.xx.xx:8007}"
PBS_DATASTORE="${PBS_DATASTORE:-datastore}"

: "${PBS_TOKEN_ID:?PBS_TOKEN_ID must be set}"
: "${PBS_TOKEN_SECRET:?PBS_TOKEN_SECRET must be set}"

pbs_get() {
  echo "GET /api2/json/$1" >&2
  curl -f -k \
    -H "Authorization: PBSAPIToken=${PBS_TOKEN_ID}:${PBS_TOKEN_SECRET}" \
    "${PBS_HOST}/api2/json/$1"
}

{
  echo "generated: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  echo "source: \"PBS API — ${PBS_HOST}\""

  echo ""
  echo "datastore_status:"
  pbs_get "admin/datastore/${PBS_DATASTORE}/status" | jq -r '
    .data |
    "  total_gb: "     + ((.total // 0) / 1073741824 | round | tostring),
    "  used_gb: "      + ((.used  // 0) / 1073741824 | round | tostring),
    "  available_gb: " + ((.avail // 0) / 1073741824 | round | tostring)
  '

  echo ""
  echo "prune_jobs:"
  prune_json=$(pbs_get "admin/prune-job" 2>/dev/null) || { echo "  # endpoint unavailable" >&2; prune_json='{"data":[]}'; }
  echo "$prune_json" | jq -r '
    .data[] |
    "  - id: \""       + .id    + "\"",
    "    store: \""     + .store + "\"",
    (if .["keep-last"]    then "    keep-last: "    + (.["keep-last"]    | tostring) else empty end),
    (if .["keep-daily"]   then "    keep-daily: "   + (.["keep-daily"]   | tostring) else empty end),
    (if .["keep-weekly"]  then "    keep-weekly: "  + (.["keep-weekly"]  | tostring) else empty end),
    (if .["keep-monthly"] then "    keep-monthly: " + (.["keep-monthly"] | tostring) else empty end),
    (if .schedule         then "    schedule: \""   + .schedule          + "\""       else empty end)
  '

  echo ""
  echo "verify_jobs:"
  verify_json=$(pbs_get "admin/verify-job" 2>/dev/null) || { echo "  # endpoint unavailable" >&2; verify_json='{"data":[]}'; }
  echo "$verify_json" | jq -r '
    .data[] |
    "  - id: \""    + .id    + "\"",
    "    store: \""  + .store + "\"",
    (if .schedule then "    schedule: \"" + .schedule + "\"" else empty end)
  '
} > "$OUTPUT"

echo "Done — pbs-config snapshot written to $OUTPUT"
