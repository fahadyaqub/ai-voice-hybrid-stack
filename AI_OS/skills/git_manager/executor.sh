#!/usr/bin/env bash
set -euo pipefail

repo_root="${AIOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
repo="${repo_root}"
message=""
branch=""
action=""

if [[ -n "${AIOS_SKILL_INPUT_JSON:-}" ]]; then
  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required to parse AIOS_SKILL_INPUT_JSON" >&2
    exit 2
  fi

  mapfile -t parsed < <(AIOS_SKILL_INPUT_JSON="${AIOS_SKILL_INPUT_JSON}" python3 - <<'PY'
import json
import os

payload = json.loads(os.environ.get("AIOS_SKILL_INPUT_JSON", "{}"))
print(payload.get("action", ""))
print(payload.get("message", ""))
print(payload.get("branch", ""))
print(payload.get("repo", ""))
PY
)
  action="${parsed[0]:-}"
  message="${parsed[1]:-}"
  branch="${parsed[2]:-}"
  repo="${parsed[3]:-${repo_root}}"
else
  action="${1:-}"
  shift || true

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --repo)
        repo="$2"
        shift 2
        ;;
      --message)
        message="$2"
        shift 2
        ;;
      --branch)
        branch="$2"
        shift 2
        ;;
      *)
        echo "ERROR: Unknown argument '$1'" >&2
        exit 2
        ;;
    esac
  done
fi

repo_real="$(cd "${repo}" 2>/dev/null && pwd || true)"
root_real="$(cd "${repo_root}" 2>/dev/null && pwd || true)"
if [[ -z "${repo_real}" || -z "${root_real}" || ( "${repo_real}" != "${root_real}" && "${repo_real}" != "${root_real}/"* ) ]]; then
  echo "ERROR: repo path must stay inside AIOS_REPO_ROOT (${repo_root})" >&2
  exit 2
fi

if [[ -z "${action}" ]]; then
  echo "ERROR: action is required (status|commit|pull|push)" >&2
  exit 2
fi

if [[ ! -d "${repo}" ]]; then
  echo "ERROR: repo path does not exist: ${repo}" >&2
  exit 2
fi

if ! git -C "${repo}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not a git repository: ${repo}" >&2
  exit 2
fi

current_branch="$(git -C "${repo}" branch --show-current 2>/dev/null || true)"

case "${action}" in
  status)
    git -C "${repo}" status --short --branch
    ;;

  commit)
    if [[ -z "${message}" ]]; then
      echo "ERROR: --message is required for commit" >&2
      exit 2
    fi

    if [[ -z "$(git -C "${repo}" status --porcelain)" ]]; then
      echo "NO_CHANGES_TO_COMMIT"
      exit 0
    fi

    git -C "${repo}" add -u
    git -C "${repo}" commit -m "${message}"
    ;;

  pull)
    if [[ -z "${branch}" ]]; then
      branch="${current_branch}"
    fi

    if [[ -z "${branch}" ]]; then
      echo "ERROR: could not infer branch for pull" >&2
      exit 2
    fi

    git -C "${repo}" pull --ff-only origin "${branch}"
    ;;

  push)
    if [[ -z "${branch}" ]]; then
      branch="${current_branch}"
    fi

    if [[ -z "${branch}" ]]; then
      echo "ERROR: could not infer branch for push" >&2
      exit 2
    fi

    if [[ "${branch}" == "main" || "${branch}" == "master" ]]; then
      if [[ "${ALLOW_MAIN_PUSH:-false}" != "true" ]]; then
        echo "ERROR: refusing to push to ${branch} without ALLOW_MAIN_PUSH=true" >&2
        exit 3
      fi
    fi

    if [[ -n "$(git -C "${repo}" status --porcelain)" ]]; then
      echo "ERROR: working tree has uncommitted changes; commit before push" >&2
      exit 3
    fi

    git -C "${repo}" push origin "${branch}"
    ;;

  *)
    echo "ERROR: unsupported action '${action}'" >&2
    exit 2
    ;;
esac
