#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_LOCAL_USER="${USER:-$(id -un 2>/dev/null || echo user)}"

MODE="${1:-${MODE:-}}"
REMOTE_HOST="${REMOTE_HOST:-}"
WITH_OLLAMA="${WITH_OLLAMA:-false}"
RESET_STATE="${RESET_STATE:-false}"
REPO_URL="${REPO_URL:-https://github.com/fahadyaqub/ai-voice-hybrid-stack.git}"
AUTO_GIT_INIT="${AUTO_GIT_INIT:-false}"

for arg in "${@:2}"; do
  if [[ "${arg}" == "--with-ollama" ]]; then
    WITH_OLLAMA="true"
  elif [[ "${arg}" == "--reset-state" ]]; then
    RESET_STATE="true"
  elif [[ -z "${REMOTE_HOST}" ]]; then
    REMOTE_HOST="${arg}"
  fi
done

if [[ -z "${MODE}" ]]; then
  cat <<USAGE
Usage:
  $0 local [--with-ollama] [--reset-state]
  $0 remote [remote_host] [--with-ollama] [--reset-state]

or set env:
  MODE=local $0
  MODE=remote REMOTE_HOST=<remote_host> $0

Optional env vars:
  WITH_OLLAMA=true|false (default: false)
  RESET_STATE=true|false (default: false)
  SKIP_ONLINE_KEY_CHECK=true|false (default: false)
  AUTO_GIT_INIT=true|false (default: false)
  REPO_URL (default: https://github.com/fahadyaqub/ai-voice-hybrid-stack.git)
  AIOS_ROOT_REL (default: AI_OS)
  REMOTE_USER (default: current shell user)
  REMOTE_BASE_DIR (default: auto -> <remote-home>/agent-stack)
  PROJECT_NAME (default: ai-voice-hybrid-stack)
USAGE
  exit 1
fi

ensure_repo_context() {
  if ! command -v git >/dev/null 2>&1; then
    echo "WARNING: git not found; skipping repository check."
    return 0
  fi

  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    return 0
  fi

  echo "==> Repository check: current directory is not a git repository."
  echo "    Skills Era workflow expects git metadata for status/commit/push handoffs."

  local do_init="false"
  if [[ "${AUTO_GIT_INIT}" == "true" ]]; then
    do_init="true"
  elif [[ -t 0 ]]; then
    read -r -p "Initialize git repo and set origin to ${REPO_URL}? [y/N]: " reply
    case "${reply}" in
      y|Y|yes|YES) do_init="true" ;;
    esac
  fi

  if [[ "${do_init}" != "true" ]]; then
    echo "WARNING: continuing without git initialization."
    echo "Run manually when ready:"
    echo "  git init"
    echo "  git remote add origin ${REPO_URL}"
    return 0
  fi

  git init
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "${REPO_URL}"
  fi
  echo "==> Git repository initialized and origin configured."
}

ensure_repo_context

if [[ "${MODE}" == "local" ]]; then
  export WITH_OLLAMA
  export RESET_STATE
  export SKIP_ONLINE_KEY_CHECK="${SKIP_ONLINE_KEY_CHECK:-false}"
  exec "${SCRIPT_DIR}/local_bootstrap.sh"
fi

if [[ "${MODE}" != "remote" ]]; then
  echo "ERROR: MODE must be 'local' or 'remote'."
  exit 1
fi

if [[ -z "${REMOTE_HOST}" ]]; then
  if command -v tailscale >/dev/null 2>&1; then
    TS_JSON="$(tailscale status --json 2>/dev/null || true)"
    if [[ -n "${TS_JSON}" && "${TS_JSON}" == \{* ]]; then
      CANDIDATES=()
      while IFS= read -r line; do
        [[ -n "${line}" ]] && CANDIDATES+=("${line}")
      done < <(TS_JSON="${TS_JSON}" python3 - <<'PY'
import json
import os
import sys

try:
    data = json.loads(os.environ.get("TS_JSON", ""))
except Exception:
    sys.exit(0)

peers = data.get("Peer", {}) or {}
rows = []
for p in peers.values():
    if not p.get("Online"):
        continue
    host = p.get("DNSName") or p.get("HostName") or ""
    ip = (p.get("TailscaleIPs") or [""])[0]
    target = host or ip
    if not target:
        continue
    rows.append((target, p.get("HostName") or target, ip))

for target, name, ip in rows:
    print(f"{target}|{name}|{ip}")
PY
)
      if [[ "${#CANDIDATES[@]}" -eq 1 ]]; then
        REMOTE_HOST="$(echo "${CANDIDATES[0]}" | cut -d'|' -f1)"
        echo "==> Auto-selected remote host from Tailscale: ${REMOTE_HOST}"
      elif [[ "${#CANDIDATES[@]}" -gt 1 ]]; then
        echo "Multiple online Tailscale peers found:"
        idx=1
        for row in "${CANDIDATES[@]}"; do
          target="$(echo "${row}" | cut -d'|' -f1)"
          name="$(echo "${row}" | cut -d'|' -f2)"
          ip="$(echo "${row}" | cut -d'|' -f3)"
          echo "  ${idx}) ${name} (${target}, ${ip})"
          idx=$((idx + 1))
        done
        read -r -p "Select remote machine number: " choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#CANDIDATES[@]} )); then
          REMOTE_HOST="$(echo "${CANDIDATES[$((choice - 1))]}" | cut -d'|' -f1)"
        fi
      fi
    fi
  fi

  if [[ -z "${REMOTE_HOST}" ]]; then
    echo "ERROR: remote mode requires <remote_host> or REMOTE_HOST env var."
    echo "Tip: run 'tailscale status' and use the machine DNS name or 100.x IP."
    exit 1
  fi
fi

export REMOTE_HOST
export WITH_OLLAMA
export RESET_STATE
export SKIP_ONLINE_KEY_CHECK="${SKIP_ONLINE_KEY_CHECK:-false}"
export AIOS_ROOT_REL="${AIOS_ROOT_REL:-AI_OS}"
export REMOTE_USER="${REMOTE_USER:-${DEFAULT_LOCAL_USER}}"
export REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-}"
export PROJECT_NAME="${PROJECT_NAME:-ai-voice-hybrid-stack}"

echo "==> One-click bootstrap (remote) for ${REMOTE_USER}@${REMOTE_HOST}"
echo "==> Ollama profile: ${WITH_OLLAMA}"
echo "==> Reset state: ${RESET_STATE}"

if command -v ssh >/dev/null 2>&1 && command -v rsync >/dev/null 2>&1; then
  echo "==> Using local ssh/rsync path"
  exec "${SCRIPT_DIR}/remote_bootstrap.sh"
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Missing ssh/rsync locally and docker is not available."
  echo "Install docker or install ssh+rsync, then retry."
  exit 1
fi

echo "==> Local ssh/rsync not found. Falling back to containerized bootstrap path"
docker build -f "${SCRIPT_DIR}/Dockerfile" -t agent-remote-bootstrap "${SCRIPT_DIR}/.."
docker run --rm -it \
  -e REMOTE_HOST="${REMOTE_HOST}" \
  -e REMOTE_USER="${REMOTE_USER}" \
  -e REMOTE_BASE_DIR="${REMOTE_BASE_DIR}" \
  -e PROJECT_NAME="${PROJECT_NAME}" \
  -e AIOS_ROOT_REL="${AIOS_ROOT_REL}" \
  -e WITH_OLLAMA="${WITH_OLLAMA}" \
  -e RESET_STATE="${RESET_STATE}" \
  -e SKIP_ONLINE_KEY_CHECK="${SKIP_ONLINE_KEY_CHECK}" \
  -v "${HOME}/.ssh:/root/.ssh:ro" \
  -v "${SCRIPT_DIR}/..:/workspace" \
  agent-remote-bootstrap
