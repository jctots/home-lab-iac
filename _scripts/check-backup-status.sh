#!/usr/bin/env bash
# Pre-update backup readiness check.
# Verifies PBS last backup status via PBS API and kopia last snapshot age on all VMs.
# Runs on the CI runner (bedok). Exit code: 0 = all checks passed, 1 = one or more checks failed.
#
# Required env vars:
#   PBS_HOST         PBS API base URL (default: https://192.168.xx.xx:8007)
#   PBS_TOKEN_ID     PBS API token ID (e.g. gitea-runner@pbs!gitea-runner)
#   PBS_TOKEN_SECRET PBS API token secret
#
# Usage: bash _scripts/check-backup-status.sh

set -euo pipefail

PBS_HOST="${PBS_HOST:-https://192.168.xx.xx:8007}"
PBS_DATASTORE="${PBS_DATASTORE:-datastore}"
HOSTS=(bishan bedok braddell clementi)
VM_IDS=(1001 1002 1003)
MAX_AGE_HOURS=48
ERRORS=0

ok()   { printf "  [ OK ]  %s\n" "$*"; }
fail() { printf "  [FAIL]  %s\n" "$*"; ((ERRORS++)) || true; }
warn() { printf "  [WARN]  %s\n" "$*"; }

# ── PBS: last snapshot per VM ─────────────────────────────────────────────────
echo ""
echo "PBS — last snapshot per VM (datastore: ${PBS_DATASTORE}):"

snapshots_json=$(curl -s -k \
  -H "Authorization: PBSAPIToken=${PBS_TOKEN_ID}:${PBS_TOKEN_SECRET}" \
  "${PBS_HOST}/api2/json/admin/datastore/${PBS_DATASTORE}/snapshots" \
  2>/dev/null) || snapshots_json=""

if [[ -z "$snapshots_json" ]]; then
  fail "could not reach PBS API at ${PBS_HOST}"
else
  for vmid in "${VM_IDS[@]}"; do
    result=$(echo "$snapshots_json" | python3 -c "
import json, sys, datetime

data = json.load(sys.stdin)
snapshots = data.get('data', [])
vm_snaps = [s for s in snapshots if s.get('backup-type') == 'vm' and str(s.get('backup-id')) == '${vmid}']
if not vm_snaps:
    print('MISSING')
else:
    latest = max(vm_snaps, key=lambda s: s.get('backup-time', 0))
    t = latest.get('backup-time', 0)
    dt = datetime.datetime.fromtimestamp(int(t))
    age_h = (datetime.datetime.now() - dt).total_seconds() / 3600
    print(f'OK {dt.strftime(\"%Y-%m-%dT%H:%M\")} {age_h:.0f}')
" 2>/dev/null) || result="ERROR"

    if [[ "$result" == "MISSING" ]]; then
      fail "VM ${vmid}: no snapshot found in PBS"
    elif [[ "$result" == "ERROR" ]]; then
      warn "VM ${vmid}: could not parse PBS response"
    else
      read -r status snap_dt age_h <<< "$result"
      if (( age_h > MAX_AGE_HOURS )); then
        fail "VM ${vmid}: last snapshot ${age_h}h ago (threshold: ${MAX_AGE_HOURS}h) — ${snap_dt}"
      else
        ok "VM ${vmid}: last snapshot ${age_h}h ago — ${snap_dt}"
      fi
    fi
  done
fi

# ── kopia: last snapshot age per VM ──────────────────────────────────────────
echo ""
echo "kopia — last snapshot age (threshold: ${MAX_AGE_HOURS}h):"

for host in "${HOSTS[@]}"; do
  snap_date=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "homelab-admin@${host}" \
    "docker exec kopia kopia snapshot list 2>/dev/null | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' | tail -1" \
    2>/dev/null) || snap_date=""

  if [[ -z "$snap_date" ]]; then
    fail "${host}: no snapshot found or SSH failed"
    continue
  fi

  snap_epoch=$(date -d "${snap_date} UTC" +%s 2>/dev/null) || {
    warn "${host}: could not parse snapshot date '${snap_date}'"
    continue
  }
  now_epoch=$(date +%s)
  age_h=$(( (now_epoch - snap_epoch) / 3600 ))

  if (( age_h > MAX_AGE_HOURS )); then
    fail "${host}: last snapshot ${age_h}h ago (threshold: ${MAX_AGE_HOURS}h) — ${snap_date} UTC"
  else
    ok "${host}: last snapshot ${age_h}h ago"
  fi
done

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
if (( ERRORS > 0 )); then
  echo "RESULT: ${ERRORS} check(s) failed — resolve before proceeding with updates."
  exit 1
else
  echo "RESULT: all checks passed."
  exit 0
fi
