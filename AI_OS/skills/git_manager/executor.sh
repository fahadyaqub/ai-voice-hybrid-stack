#!/usr/bin/env bash
set -euo pipefail

action="${1:-}"
shift || true

repo_root="${AIOS_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
repo="${repo_root}"
message=""
branch=""

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

    git -C "${repo}" add -A
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
