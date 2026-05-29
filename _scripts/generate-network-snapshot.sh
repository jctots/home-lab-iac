#!/usr/bin/env bash
# generate-network-snapshot.sh — snapshot network host→IP map to _snapshots/network-hosts.yaml
#
# Combines two sources:
#   1. DHCP reservations from florence (MAC→hostname→IP, for dynamically addressed hosts)
#   2. SSH probe of known static-IP hosts (hostname + primary IP from the host itself)
#
# Required env vars (for florence SSH):
#   FLORENCE_HOST  (default: 192.168.xx.xx)
#   FLORENCE_USER  (default: homelab-user)
#   FLORENCE_PORT  (default: 2022)
#
# Static hosts are hardcoded below — update when adding/removing hosts with static IPs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOTS_DIR="$SCRIPT_DIR/../_snapshots"
OUTPUT="$SNAPSHOTS_DIR/network-hosts.yaml"

FLORENCE_HOST="${FLORENCE_HOST:-192.168.xx.xx}"
FLORENCE_USER="${FLORENCE_USER:-homelab-user}"
FLORENCE_PORT="${FLORENCE_PORT:-2022}"

# Hosts with static IPs not managed by DHCP reservations
STATIC_HOSTS=(
  "changi:192.168.xx.xx"
  "bishan:192.168.xx.xx"
  "bedok:192.168.xx.xx"
  "braddell:192.168.xx.xx"
  "clementi:192.168.xx.xx"
)

mkdir -p "$SNAPSHOTS_DIR"

{
  echo "generated: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
  echo "source_dhcp: \"florence:/etc/dhcpd/dhcpd.conf\""
  echo ""

  # ── DHCP reservations ──────────────────────────────────────────────────────
  echo "dhcp_reservations:"
  echo "Fetching DHCP reservations from florence..." >&2
  RAW=$(ssh -p "$FLORENCE_PORT" "$FLORENCE_USER@$FLORENCE_HOST" \
    "grep '^dhcp-host=' /etc/dhcpd/dhcpd.conf 2>/dev/null") || RAW=""

  if [[ -z "$RAW" ]]; then
    echo "  []"
  else
    echo "$RAW" | sort | awk -F'[=,]' '
      NF >= 4 {
        mac=$2; host=$3; ip=$4
        if (ip == "127.0.0.1") next
        printf "  - hostname: \"%s\"\n    ip: \"%s\"\n    mac: \"%s\"\n", host, ip, mac
      }
    '
  fi

  # ── Static hosts ───────────────────────────────────────────────────────────
  echo ""
  echo "static_hosts:"
  for entry in "${STATIC_HOSTS[@]}"; do
    host="${entry%%:*}"
    expected_ip="${entry##*:}"
    echo "  Probing ${host}..." >&2
    actual_ip=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "homelab-admin@${host}" \
      "hostname -I | awk '{print \$1}'" 2>/dev/null) || actual_ip=""
    if [[ -z "$actual_ip" ]]; then
      echo "  - hostname: \"${host}\""
      echo "    ip: \"${expected_ip}\""
      echo "    note: \"SSH probe failed — using configured IP\""
    else
      echo "  - hostname: \"${host}\""
      echo "    ip: \"${actual_ip}\""
    fi
  done

} > "$OUTPUT"

DHCP_COUNT=$(grep -c '^ *- hostname:' "$OUTPUT" || true)
STATIC_COUNT=${#STATIC_HOSTS[@]}
echo "Done — ${DHCP_COUNT} DHCP reservations + ${STATIC_COUNT} static hosts written to $OUTPUT"
