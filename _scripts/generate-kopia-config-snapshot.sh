#!/usr/bin/env bash
# generate-kopia-config-snapshot.sh — snapshot full kopia configuration across all VMs
# Writes _snapshots/kopia-config.yaml (single combined file).
# path_policies and latest_snapshots are repo-wide — captured once from the first reachable host.
# Requires: ssh (key-based), docker exec kopia on target VMs, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOTS_DIR="$SCRIPT_DIR/../_snapshots"
HOSTS=(bishan bedok braddell clementi)

mkdir -p "$SNAPSHOTS_DIR"
rm -f "$SNAPSHOTS_DIR"/kopia-*-config.yaml

TMPDIR_MAIN=$(mktemp -d)
trap "rm -rf $TMPDIR_MAIN" EXIT

for host in "${HOSTS[@]}"; do
  echo "Collecting kopia config from ${host}..."
  TMPDIR_HOST="$TMPDIR_MAIN/$host"
  mkdir -p "$TMPDIR_HOST"

  ssh -o ConnectTimeout=5 -o BatchMode=yes "homelab-admin@${host}" \
    "docker exec kopia kopia repository status --json 2>/dev/null" \
    > "$TMPDIR_HOST/repo.json" 2>/dev/null \
    || echo '{}' > "$TMPDIR_HOST/repo.json"

  ssh -o ConnectTimeout=5 -o BatchMode=yes "homelab-admin@${host}" \
    "docker exec kopia kopia policy list --json 2>/dev/null" \
    > "$TMPDIR_HOST/policies.json" 2>/dev/null \
    || echo '[]' > "$TMPDIR_HOST/policies.json"

  ssh -o ConnectTimeout=5 -o BatchMode=yes "homelab-admin@${host}" \
    "docker exec kopia kopia snapshot list --json 2>/dev/null" \
    > "$TMPDIR_HOST/snapshots.json" 2>/dev/null \
    || true

  echo "Done — collected from ${host}"
done

python3 - "$TMPDIR_MAIN" "${HOSTS[@]}" > "$SNAPSHOTS_DIR/kopia-config.yaml" << 'PYEOF'
import json, sys, datetime
from pathlib import Path

tmpdir = Path(sys.argv[1])
hosts  = sys.argv[2:]

def read_json(path):
    try:
        text = path.read_text().strip()
        return json.loads(text) if text else {}
    except Exception:
        return {}

def read_ndjson(path):
    try:
        lines = [l for l in path.read_text().splitlines() if l.strip()]
        if not lines:
            return []
        try:
            parsed = json.loads('\n'.join(lines))
            return parsed if isinstance(parsed, list) else [parsed]
        except json.JSONDecodeError:
            return [json.loads(l) for l in lines]
    except Exception:
        return []

def is_global(target):
    return not any([target.get('userName'), target.get('host'), target.get('path')])

# ── YAML renderer ────────────────────────────────────────────────────────────
# Returns a list of lines (each already indented).
# List items that are dicts inline the first key on the "- " line; subsequent
# keys in the same item are aligned with the first key (pad + two spaces).

def scalar(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    elif v is None:
        return 'null'
    elif isinstance(v, str):
        needs_quote = (not v or v[0] in '-?!&*|>{['
                       or any(c in v for c in ':{}[]#\n'))
        return f'"{v}"' if needs_quote else v
    else:
        return str(v)

def is_empty(v):
    return v is None or v == {} or v == []

def dump(data, indent=0):
    pad = '  ' * indent
    lines = []

    if isinstance(data, dict):
        for k, v in data.items():
            if is_empty(v):
                continue
            if isinstance(v, (dict, list)):
                sub = dump(v, indent + 1)
                if not sub:
                    continue
                lines.append(f'{pad}{k}:')
                lines.extend(sub)
            else:
                lines.append(f'{pad}{k}: {scalar(v)}')

    elif isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                entries = [(k, v) for k, v in item.items() if not is_empty(v)]
                if not entries:
                    continue
                (fk, fv), rest = entries[0], entries[1:]
                inner = pad + '  '  # keys after the first align here
                if isinstance(fv, (dict, list)):
                    sub = dump(fv, indent + 2)
                    lines.append(f'{pad}- {fk}:')
                    lines.extend(sub)
                else:
                    lines.append(f'{pad}- {fk}: {scalar(fv)}')
                for k, v in rest:
                    if isinstance(v, (dict, list)):
                        sub = dump(v, indent + 2)
                        if not sub:
                            continue
                        lines.append(f'{inner}{k}:')
                        lines.extend(sub)
                    else:
                        lines.append(f'{inner}{k}: {scalar(v)}')
            else:
                if not is_empty(item):
                    lines.append(f'{pad}- {scalar(item)}')

    return lines

def section(title, data, indent=0):
    lines = [f'{"  " * indent}{title}:']
    sub = dump(data, indent + 1)
    lines.extend(sub if sub else [f'{"  " * (indent + 1)}(none)'])
    return lines

# ── Collect repo-wide data from first reachable host ────────────────────────

global_policy  = None
path_policies  = []
raw_snapshots  = []
host_repos     = {}

for host in hosts:
    repo     = read_json(tmpdir / host / 'repo.json')
    policies = read_ndjson(tmpdir / host / 'policies.json')
    snaps    = read_ndjson(tmpdir / host / 'snapshots.json')

    storage = repo.get('storage', {})
    conn    = storage.get('config', storage)
    host_repos[host] = {
        'type':     storage.get('type', repo.get('type', 'unknown')),
        'host':     conn.get('host', ''),
        'path':     conn.get('path', ''),
        'username': conn.get('username', ''),
    }

    if global_policy is None and policies:
        for p in policies:
            if is_global(p.get('target', {})):
                global_policy = {k: v for k, v in p.items() if k not in ('target', 'id')}
                break

    if not path_policies and policies:
        for p in policies:
            if not is_global(p.get('target', {})):
                path_policies.append({k: v for k, v in p.items() if k != 'id'})

    if not raw_snapshots and snaps:
        raw_snapshots = snaps

# ── Latest snapshot per source (host:path) ──────────────────────────────────

latest = {}
for s in raw_snapshots:
    src_obj = s.get('source', {})
    key = f'{src_obj.get("host", "?")}:{src_obj.get("path", "?")}'
    t   = s.get('startTime', '')
    if key not in latest or t > latest[key]['startTime']:
        latest[key] = s

latest_snapshots = []
for key, s in sorted(latest.items()):
    size    = s.get('stats', {}).get('totalSize', 0)
    size_mb = round(size / 1048576, 1) if size else 0
    latest_snapshots.append({
        'source':  key,
        'time':    s.get('startTime', ''),
        'size_mb': size_mb,
    })

# ── Index path policies and snapshots by host ───────────────────────────────

policies_by_host = {}
for p in path_policies:
    h = p.get('target', {}).get('host', '')
    policies_by_host.setdefault(h, []).append(p)
for h in policies_by_host:
    policies_by_host[h].sort(key=lambda p: p.get('target', {}).get('path', ''))

snapshots_by_host = {}
for key, s in sorted(latest.items()):
    h = s.get('source', {}).get('host', '?')
    size    = s.get('stats', {}).get('totalSize', 0)
    size_mb = round(size / 1048576, 1) if size else 0
    snapshots_by_host.setdefault(h, []).append({
        'path':    s.get('source', {}).get('path', '?'),
        'time':    s.get('startTime', ''),
        'size_mb': size_mb,
    })

# ── Render ───────────────────────────────────────────────────────────────────

out = []
out.append(f'generated: "{datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}"')
out.append('')

# Global policy
out.extend(section('global_policy', global_policy or {}))
out.append('')

# Hosts — connection info, path policies, latest snapshots
out.append('hosts:')
for host in hosts:
    repo = host_repos.get(host, {})
    out.append(f'  {host}:')
    for k in ['type', 'host', 'path', 'username']:
        if repo.get(k):
            out.append(f'    {k}: {scalar(repo[k])}')

    # Path policies for this host
    host_policies = policies_by_host.get(host, [])
    out.append('    path_policies:')
    if host_policies:
        for p in host_policies:
            target = p.get('target', {})
            fields = {k: v for k, v in p.items() if k != 'target' and not is_empty(v)}
            entry  = {'path': target.get('path', ''), **fields}
            sub    = dump([entry], 3)
            out.extend(sub)
    else:
        out.append('      (none)')

    # Latest snapshots for this host
    host_snaps = snapshots_by_host.get(host, [])
    out.append('    latest_snapshots:')
    if host_snaps:
        sub = dump(host_snaps, 3)
        out.extend(sub)
    else:
        out.append('      (none)')
    out.append('')

print('\n'.join(out))
PYEOF

echo "Done — kopia config snapshot written to $SNAPSHOTS_DIR/kopia-config.yaml"
