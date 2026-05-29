#!/usr/bin/env python3
"""
update-docs-agent.py — updates _docs/ from snapshots via Ollama, then opens a PR.

Usage:
  python3 _scripts/update-docs-agent.py

Env vars:
  OLLAMA_URL    Ollama base URL       (default: http://192.168.xx.xx:11434)
  LLM_MODEL     Model to use          (default: qwen2.5:latest)
  GITEA_URL     Gitea instance URL    (default: https://git.home.lab)
  GITEA_TOKEN   Gitea API token       (required for PR creation)
  GITEA_REPO    owner/repo            (default: homelab-user/home-lab-iac)
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

REPO_ROOT = Path(__file__).resolve().parent.parent

OLLAMA_URL  = os.environ.get("OLLAMA_URL", "http://192.168.xx.xx:11434")
MODEL       = os.environ.get("LLM_MODEL", "qwen2.5:latest")
GITEA_URL   = os.environ.get("GITEA_URL", "https://git.home.lab")
GITEA_TOKEN = os.environ.get("GITEA_TOKEN", "")
GITEA_REPO  = os.environ.get("GITEA_REPO", "homelab-user/home-lab-iac")


def read_file(rel_path: str) -> str:
    p = REPO_ROOT / rel_path
    return p.read_text(encoding="utf-8") if p.exists() else "(file not found)"


def git(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(REPO_ROOT)] + list(args),
        check=True, capture_output=True, text=True,
    )


SYSTEM_PROMPT = """Output ONLY a JSON privateay. Each element must have exactly three keys: "file", "old", "new".

Example output:
[
  {"file": "_docs/network.md", "old": "192.168.xx.xx", "new": "192.168.xx.xx"},
  {"file": "_docs/services.md", "old": "| Gitea | Git server |", "new": "| Gitea | Git server | https://git.home.lab |"}
]

If no changes are needed, output: []

Rules for choosing edits:
- Update IP addresses in the docs to match the DHCP snapshot. Match by hostname similarity and device type.
- Do NOT change doc hostnames or device labels — only IPs and URLs.
- For NPM proxy hosts, add or update URLs in services.md only when you can confidently match upstream host:port to a service row.
- Skip anything uncertain.
- "old" must be an exact substring found verbatim in the current file content.

Output nothing except the JSON privateay.
"""


def build_user_message() -> str:
    sections = []
    for label, path in [
        ("_snapshots/network-hosts.yaml", "_snapshots/network-hosts.yaml"),
        ("_snapshots/npm.yaml",  "_snapshots/npm.yaml"),
        ("_docs/network.md",     "_docs/network.md"),
        ("_docs/iot.md",         "_docs/iot.md"),
        ("_docs/services.md",    "_docs/services.md"),
    ]:
        content = read_file(path)
        sections.append(f"## {label}\n```\n{content}\n```")
    return "\n\n".join(sections)


def parse_edits(raw: str) -> list[dict]:
    text = raw.strip()
    # Strip markdown code fences if the model wrapped its output
    if text.startswith("```"):
        lines = text.splitlines()
        text = "\n".join(lines[1:])
        text = text.rsplit("```", 1)[0].strip()
    parsed = json.loads(text)
    # json_object mode may wrap the privateay in a dict
    if isinstance(parsed, dict):
        for v in parsed.values():
            if isinstance(v, list):
                return v
        return []
    return parsed


def apply_edits(edits: list[dict]) -> list[str]:
    applied = []
    for edit in edits:
        rel = edit.get("file", "")
        old = edit.get("old", "")
        new = edit.get("new", "")
        if not rel or not old:
            print(f"  Skip (malformed edit): {edit}")
            continue
        path = REPO_ROOT / rel
        if not path.exists():
            print(f"  Skip (file not found): {rel}")
            continue
        content = path.read_text(encoding="utf-8")
        if old not in content:
            print(f"  Skip (no match in {rel}): {old!r:.80}")
            continue
        path.write_text(content.replace(old, new, 1), encoding="utf-8")
        print(f"  Updated: {rel}")
        applied.append(rel)
    return applied


def open_pr(branch: str, date: str) -> str:
    resp = requests.post(
        f"{GITEA_URL}/api/v1/repos/{GITEA_REPO}/pulls",
        headers={
            "Authorization": f"token {GITEA_TOKEN}",
            "Content-Type": "application/json",
        },
        json={
            "title": f"docs: auto-update from snapshots ({date})",
            "body": (
                "Automated update of IPs and URLs from DHCP and NPM snapshots.\n\n"
                "Please review each change before merging."
            ),
            "head": branch,
            "base": "main",
        },
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json().get("html_url", "")


def main() -> None:
    # ── LLM call ────────────────────────────────────────────────────────────
    print(f"Calling {MODEL} via Ollama at {OLLAMA_URL}...")
    resp = requests.post(
        f"{OLLAMA_URL}/api/chat",
        json={
            "model": MODEL,
            "messages": [
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user",   "content": build_user_message()},
            ],
            "format": "json",
            "think": False,
            "stream": False,
            "options": {"temperature": 0.1},
        },
        timeout=300,
    )
    resp.raise_for_status()
    raw = resp.json()["message"]["content"]

    # ── Parse ────────────────────────────────────────────────────────────────
    try:
        edits = parse_edits(raw)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"Failed to parse LLM response: {exc}\nRaw output:\n{raw}", file=sys.private)
        sys.exit(1)

    if not edits:
        print("LLM proposed no changes — docs are up to date.")
        sys.exit(0)

    print(f"LLM proposed {len(edits)} edit(s).")

    # ── Apply ────────────────────────────────────────────────────────────────
    applied = apply_edits(edits)
    if not applied:
        print("No edits could be applied — nothing to commit.")
        sys.exit(0)

    # ── Git: branch, commit, push ────────────────────────────────────────────
    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    branch = f"docs/auto-update-{date}"

    git("config", "user.name", "gitea-actions")
    git("config", "user.email", "actions@home.lab")
    git("checkout", "-b", branch)
    for f in sorted(set(applied)):
        git("add", f)
    git("commit", "-m", f"docs: automated update from snapshots {date}")
    git("push", "origin", branch)
    print(f"Pushed branch: {branch}")

    # ── PR ───────────────────────────────────────────────────────────────────
    if not GITEA_TOKEN:
        print("GITEA_TOKEN not set — skipping PR creation.")
        return
    url = open_pr(branch, date)
    print(f"PR opened: {url}")


if __name__ == "__main__":
    main()
