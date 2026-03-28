#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${REMOTE_HOST:-}" ]]; then
  echo "ERROR: REMOTE_HOST is required (example: 100.101.102.103)."
  exit 1
fi

REMOTE_USER="${REMOTE_USER:-${USER:-$(id -un 2>/dev/null || echo user)}}"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-}"
PROJECT_NAME="${PROJECT_NAME:-ai-voice-hybrid-stack}"
AIOS_ROOT_REL="${AIOS_ROOT_REL:-AI_OS}"
WITH_OLLAMA="${WITH_OLLAMA:-false}"
RESET_STATE="${RESET_STATE:-false}"
SKIP_ONLINE_KEY_CHECK="${SKIP_ONLINE_KEY_CHECK:-false}"
DEFAULT_SSH_OPTS="-o ServerAliveInterval=30 -o ServerAliveCountMax=10 -o IdentitiesOnly=yes"
if [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  DEFAULT_SSH_OPTS="${DEFAULT_SSH_OPTS} -i ${HOME}/.ssh/id_ed25519"
fi
SSH_OPTS="${SSH_OPTS:-${DEFAULT_SSH_OPTS}}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "/workspace" ]]; then
  PROJECT_DIR="/workspace"
else
  PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
fi

echo "==> Checking SSH access to ${REMOTE_USER}@${REMOTE_HOST}"
ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "echo 'SSH OK on' \$(hostname)"

if [[ -z "${REMOTE_BASE_DIR}" ]]; then
  REMOTE_HOME="$(ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" 'printf %s "$HOME"')"
  if [[ -z "${REMOTE_HOME}" ]]; then
    echo "ERROR: Could not resolve remote home directory for ${REMOTE_USER}@${REMOTE_HOST}"
    exit 1
  fi
  REMOTE_BASE_DIR="${REMOTE_HOME}/agent-stack"
fi

echo "==> Preparing remote directory ${REMOTE_BASE_DIR}"
ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p '${REMOTE_BASE_DIR}'"

echo "==> Syncing project to remote machine"
rsync -az --delete \
  --exclude ".env" \
  --exclude ".DS_Store" \
  "${PROJECT_DIR}/" \
  "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_BASE_DIR}/${PROJECT_NAME}/"

echo "==> Running remote bootstrap tasks"
ssh ${SSH_OPTS} "${REMOTE_USER}@${REMOTE_HOST}" \
  "REMOTE_BASE_DIR='${REMOTE_BASE_DIR}' PROJECT_NAME='${PROJECT_NAME}' AIOS_ROOT_REL='${AIOS_ROOT_REL}' WITH_OLLAMA='${WITH_OLLAMA}' RESET_STATE='${RESET_STATE}' SKIP_ONLINE_KEY_CHECK='${SKIP_ONLINE_KEY_CHECK}' bash -s" <<'EOF'
set -euo pipefail

REMOTE_USER="$(whoami)"
REMOTE_BASE_DIR="${REMOTE_BASE_DIR:-${HOME}/agent-stack}"
PROJECT_NAME="${PROJECT_NAME:-ai-voice-hybrid-stack}"
AIOS_ROOT_REL="${AIOS_ROOT_REL:-AI_OS}"
WITH_OLLAMA="${WITH_OLLAMA:-false}"
RESET_STATE="${RESET_STATE:-false}"
SKIP_ONLINE_KEY_CHECK="${SKIP_ONLINE_KEY_CHECK:-false}"
PROJECT_DIR="${REMOTE_BASE_DIR}/${PROJECT_NAME}"
AIOS_DIR="${PROJECT_DIR}/${AIOS_ROOT_REL}"
COMPOSE_FILE="${AIOS_DIR}/services/docker-compose.yml"
ENV_FILE="${PROJECT_DIR}/.env"
ENV_EXAMPLE="${PROJECT_DIR}/.env.example"

PATH="/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:${PATH}"

dcompose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "${COMPOSE_FILE}" "$@"
    return
  fi
  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "${COMPOSE_FILE}" "$@"
    return
  fi
  echo "ERROR: Docker Compose is not available."
  return 1
}

set_env_value() {
  local key="$1"
  local value="$2"
  local file="$3"
  local tmp="${file}.tmp"

  if grep -q "^${key}=" "${file}"; then
    awk -F= -v OFS="=" -v k="${key}" -v v="${value}" '$1==k{$0=k"="v} {print}' "${file}" > "${tmp}"
    mv "${tmp}" "${file}"
  else
    printf "%s=%s\n" "${key}" "${value}" >> "${file}"
  fi
}

env_is_missing() {
  local key="$1"
  local file="$2"
  local raw
  raw="$(grep -E "^${key}=" "${file}" | head -n1 | cut -d= -f2- || true)"
  [[ -z "${raw}" ]] && return 0
  [[ "${raw}" == change-me* ]] && return 0
  return 1
}

render_template() {
  local template="$1"
  local file="$2"
  local root="$3"
  local escaped
  escaped="$(printf '%s' "${root}" | sed 's/[\/&]/\\&/g')"
  sed "s|__AI_OS_ROOT__|${escaped}|g" "${template}" > "${file}"
}

assert_no_placeholder() {
  local file="$1"
  if grep -q "__AI_OS_ROOT__" "${file}"; then
    echo "ERROR: Placeholder token remains in ${file}"
    exit 1
  fi
}

wait_for_service() {
  local service="$1"
  local max_wait="${2:-120}"
  local elapsed=0

  while (( elapsed < max_wait )); do
    local cid
    cid="$(dcompose ps -q "${service}" | head -n1)"
    if [[ -n "${cid}" ]]; then
      local state
      state="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "${cid}" 2>/dev/null || true)"
      if [[ "${state}" == "healthy" || "${state}" == "running" ]]; then
        echo "   ${service}: ${state}"
        return 0
      fi
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  echo "WARNING: ${service} did not become healthy/running within ${max_wait}s"
  return 1
}

ensure_workspace_skeleton() {
  for i in 1 2 3 4 5 6; do
    local dir="${AIOS_DIR}/workspace/project_${i}"
    mkdir -p "${dir}"
    [[ -f "${dir}/PLAN.md" ]] || printf "# PLAN\n\nNo active mission yet.\n" > "${dir}/PLAN.md"
    [[ -f "${dir}/STATUS.md" ]] || printf "# STATUS\n\nNo work started yet.\n" > "${dir}/STATUS.md"
  done
}

discover_skills_and_update_mcp() {
  local mcp_file="${AIOS_DIR}/config/mcp_config.json"
  local skills_index_file="${AIOS_DIR}/config/skills_index.json"
  local skills_dir="${AIOS_DIR}/skills"
  local skill_server="${AIOS_DIR}/services/skills_hub/skill_mcp_server.py"

  AIOS_DIR="${AIOS_DIR}" \
  PROJECT_DIR="${PROJECT_DIR}" \
  MCP_FILE="${mcp_file}" \
  SKILLS_DIR="${skills_dir}" \
  SKILL_SERVER="${skill_server}" \
  SKILLS_INDEX_FILE="${skills_index_file}" \
  python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

aios_dir = Path(os.environ["AIOS_DIR"]).resolve()
project_dir = Path(os.environ["PROJECT_DIR"]).resolve()
mcp_file = Path(os.environ["MCP_FILE"]).resolve()
skills_dir = Path(os.environ["SKILLS_DIR"]).resolve()
skill_server = Path(os.environ["SKILL_SERVER"]).resolve()
skills_index_file = Path(os.environ["SKILLS_INDEX_FILE"]).resolve()

if not mcp_file.exists():
    print(f"ERROR: MCP runtime config not found at {mcp_file}", file=sys.stderr)
    sys.exit(1)

data = json.loads(mcp_file.read_text(encoding="utf-8"))
servers = data.setdefault("mcpServers", {})
for key in list(servers.keys()):
    if key.startswith("ai-os-skill-") or key == "ai-os-skills":
        del servers[key]

skills_index = []
if skills_dir.exists():
    if not skill_server.exists():
        print(f"ERROR: skill MCP server not found at {skill_server}", file=sys.stderr)
        sys.exit(1)

    for skill_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        tool_file = skill_dir / "tool.json"
        if not tool_file.exists():
            continue

        try:
            tool = json.loads(tool_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"ERROR: invalid JSON in {tool_file}: {exc}", file=sys.stderr)
            sys.exit(1)

        for key in ("name", "description", "input_schema"):
            if key not in tool:
                print(f"ERROR: {tool_file} missing required key '{key}'", file=sys.stderr)
                sys.exit(1)

        if not isinstance(tool["input_schema"], dict):
            print(f"ERROR: input_schema must be an object in {tool_file}", file=sys.stderr)
            sys.exit(1)

        executor_rel = tool.get("executor", "executor.sh")
        executor_path = skill_dir / executor_rel
        if not executor_path.exists():
            print(f"ERROR: executor not found for skill '{tool['name']}': {executor_path}", file=sys.stderr)
            sys.exit(1)

        slug = re.sub(r"[^a-z0-9]+", "_", str(tool["name"]).lower()).strip("_") or "skill"
        tool_mcp_name = f"skill_{slug}"

        skills_index.append(
            {
                "name": tool["name"],
                "description": tool["description"],
                "input_schema": tool["input_schema"],
                "skill_dir": str(skill_dir.resolve()),
                "executor": str(executor_path.resolve()),
                "mcp_server_id": "ai-os-skills",
                "mcp_tool_name": tool_mcp_name,
            }
        )

if skills_index:
    servers["ai-os-skills"] = {
        "command": "python3",
        "args": [
            str(skill_server),
            "--skills-dir",
            str(skills_dir.resolve()),
            "--repo-root",
            str(project_dir),
        ],
    }

mcp_file.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
skills_index_file.write_text(json.dumps({"skills": skills_index}, indent=2) + "\n", encoding="utf-8")
print(f"discovered_skills={len(skills_index)}")
PY
}

configure_mcp_targets() {
  local mcp_file="${AIOS_DIR}/config/mcp_config.json"
  local openclaw_mcp_dir="${AIOS_DIR}/config/openclaw"
  local openclaw_mcp_file="${openclaw_mcp_dir}/mcp_config.json"
  local -a targets=(
    "${HOME}/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/mcp_config.json"
    "${HOME}/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    "${HOME}/.config/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/mcp_config.json"
    "${HOME}/.config/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    "${HOME}/.config/Antigravity/User/mcp_config.json"
    "${HOME}/.config/Antigravity/mcp_config.json"
    "${HOME}/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/mcp_config.json"
    "${HOME}/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    "${HOME}/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/mcp_config.json"
    "${HOME}/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    "${HOME}/Library/Application Support/Antigravity/User/mcp_config.json"
    "${HOME}/Library/Application Support/Antigravity/mcp_config.json"
  )

  mkdir -p "${openclaw_mcp_dir}"
  AIOS_DIR="${AIOS_DIR}" OPENCLAW_MCP_FILE="${openclaw_mcp_file}" MCP_FILE="${mcp_file}" python3 - <<'PY'
import json
import os
from pathlib import Path

aios_dir = Path(os.environ["AIOS_DIR"]).resolve()
mcp_file = Path(os.environ["MCP_FILE"]).resolve()
openclaw_mcp_file = Path(os.environ["OPENCLAW_MCP_FILE"]).resolve()

data = json.loads(mcp_file.read_text(encoding="utf-8"))
servers = data.get("mcpServers", {})

for _name, server in servers.items():
    args = server.get("args")
    if not isinstance(args, list):
        continue

    for i, arg in enumerate(args):
        if isinstance(arg, str) and arg.startswith(str(aios_dir / "workspace")):
            rel = Path(arg).resolve().relative_to((aios_dir / "workspace").resolve())
            args[i] = f"/workspace/{rel.as_posix()}"

    if server.get("command") == "python3" and args and isinstance(args[0], str):
        if args[0].endswith("/AI_OS/services/skills_hub/skill_mcp_server.py"):
            args[0] = "/repo/AI_OS/services/skills_hub/skill_mcp_server.py"
            for i, arg in enumerate(args):
                if arg == "--skills-dir" and i + 1 < len(args):
                    args[i + 1] = "/repo/AI_OS/skills"
                if arg == "--repo-root" and i + 1 < len(args):
                    args[i + 1] = "/repo"

openclaw_mcp_file.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

  for t in "${targets[@]}"; do
    mkdir -p "$(dirname "${t}")"
    cp "${mcp_file}" "${t}" || true
  done
}

detect_mem_bytes() {
  local host_os
  host_os="$(uname -s 2>/dev/null || echo unknown)"

  if [[ "${host_os}" == "Darwin" ]]; then
    sysctl -n hw.memsize 2>/dev/null || echo 0
    return
  fi

  if [[ "${host_os}" == "Linux" && -r /proc/meminfo ]]; then
    local kb
    kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)"
    if [[ "${kb}" =~ ^[0-9]+$ ]]; then
      echo $((kb * 1024))
      return
    fi
  fi

  echo 0
}

apply_low_memory_profile_if_needed() {
  local mem_bytes
  mem_bytes="$(detect_mem_bytes)"
  local threshold=$((10 * 1024 * 1024 * 1024))

  if [[ "${mem_bytes}" =~ ^[0-9]+$ ]] && (( mem_bytes > 0 && mem_bytes <= threshold )); then
    echo "==> [remote] low-memory host detected (~10GB or less); enforcing Ollama safety limits"
    set_env_value "OLLAMA_NUM_PARALLEL" "1" "${ENV_FILE}"
    set_env_value "OLLAMA_MAX_LOADED_MODELS" "1" "${ENV_FILE}"
    set_env_value "OLLAMA_KEEP_ALIVE" "0" "${ENV_FILE}"
  fi
}

ensure_env_and_secrets() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    echo "Created ${ENV_FILE} from template"
  fi

  if env_is_missing "POSTGRES_PASSWORD" "${ENV_FILE}"; then
    set_env_value "POSTGRES_PASSWORD" "$(openssl rand -hex 24)" "${ENV_FILE}"
  fi
  if env_is_missing "LITELLM_MASTER_KEY" "${ENV_FILE}"; then
    set_env_value "LITELLM_MASTER_KEY" "sk-$(openssl rand -hex 24)" "${ENV_FILE}"
  fi
  if env_is_missing "N8N_ENCRYPTION_KEY" "${ENV_FILE}"; then
    set_env_value "N8N_ENCRYPTION_KEY" "$(openssl rand -hex 32)" "${ENV_FILE}"
  fi
  if env_is_missing "N8N_BASIC_AUTH_PASSWORD" "${ENV_FILE}"; then
    set_env_value "N8N_BASIC_AUTH_PASSWORD" "$(openssl rand -hex 20)" "${ENV_FILE}"
  fi
  if env_is_missing "OPENCLAW_GATEWAY_TOKEN" "${ENV_FILE}"; then
    set_env_value "OPENCLAW_GATEWAY_TOKEN" "$(openssl rand -hex 24)" "${ENV_FILE}"
  fi
  if env_is_missing "REDIS_HOST" "${ENV_FILE}"; then
    set_env_value "REDIS_HOST" "redis" "${ENV_FILE}"
  fi
  if env_is_missing "REDIS_PORT" "${ENV_FILE}"; then
    set_env_value "REDIS_PORT" "6379" "${ENV_FILE}"
  fi
  if env_is_missing "LITELLM_CACHE_TTL" "${ENV_FILE}"; then
    set_env_value "LITELLM_CACHE_TTL" "1800" "${ENV_FILE}"
  fi
}

check_online_keys() {
  local -a required=(GEMINI_API_KEY DEEPSEEK_API_KEY OPENAI_API_KEY)
  local -a missing=()
  local raw

  for key in "${required[@]}"; do
    raw="$(grep -E "^${key}=" "${ENV_FILE}" | head -n1 | cut -d= -f2- || true)"
    if [[ -z "${raw}" || "${raw}" == change-me* ]]; then
      missing+=("${key}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 && "${SKIP_ONLINE_KEY_CHECK}" != "true" ]]; then
    echo "ERROR: Missing required online-first API keys: ${missing[*]}"
    echo "Set them in ${ENV_FILE}, or rerun with SKIP_ONLINE_KEY_CHECK=true to bypass."
    exit 3
  fi
}

install_skills_runtime_deps() {
  local req_file="${AIOS_DIR}/services/skills_hub/requirements.txt"
  if [[ ! -f "${req_file}" ]]; then
    return 0
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "WARNING: python3 not found; skipping skill MCP runtime dependency install"
    return 0
  fi

  if ! python3 -m pip --version >/dev/null 2>&1; then
    python3 -m ensurepip --upgrade >/dev/null 2>&1 || true
  fi

  echo "[remote] Installing skill MCP runtime dependencies (best effort)"
  python3 -m pip install --user -r "${req_file}" >/dev/null 2>&1 || true
}

start_stack_in_order() {
  if [[ "${RESET_STATE}" == "true" ]]; then
    echo "[remote] reset-state requested: removing existing compose state/volumes"
    dcompose down -v --remove-orphans || true
  fi

  echo "[remote] Pulling images"
  dcompose pull

  echo "[remote] Starting postgres"
  dcompose up -d postgres
  wait_for_service postgres 120 || true

  echo "[remote] Starting redis"
  dcompose up -d redis
  wait_for_service redis 120 || true

  if [[ "${WITH_OLLAMA}" == "true" ]]; then
    echo "[remote] Starting ollama (--with-ollama)"
    dcompose --profile ollama up -d ollama
    wait_for_service ollama 120 || true
  fi

  echo "[remote] Starting litellm"
  dcompose up -d litellm
  wait_for_service litellm 120 || true

  echo "[remote] Starting query-router + tts"
  dcompose up -d query-router openai-edge-tts
  wait_for_service query-router 120 || true

  echo "[remote] Starting n8n"
  dcompose up -d n8n

  echo "[remote] Starting openclaw"
  dcompose up -d openclaw
}

pull_models_sequentially() {
  if [[ "${WITH_OLLAMA}" != "true" ]]; then
    echo "[remote] Skipping Ollama model pulls (enable with --with-ollama)"
    return 0
  fi

  local model_line
  model_line="$(grep -E '^OLLAMA_PULL_MODELS=' "${ENV_FILE}" | head -n1 | cut -d= -f2- || true)"
  [[ -z "${model_line}" ]] && model_line="qwen2.5:3b-instruct llama3.2:3b"

  echo "[remote] Pulling Ollama models (sequential): ${model_line}"
  for model in ${model_line}; do
    echo "  pulling ${model}"
    dcompose exec -T ollama ollama pull "${model}" || true
  done
}

echo "[1/10] Ensure project path exists"
test -d "${PROJECT_DIR}"

echo "[2/10] Ensure AI_OS files exist"
test -f "${COMPOSE_FILE}"

echo "[3/10] Ensure workspace skeleton"
ensure_workspace_skeleton

echo "[4/10] Ensure .env and secrets"
ensure_env_and_secrets
apply_low_memory_profile_if_needed
check_online_keys

if [[ ! -f "${AIOS_DIR}/config/mcp_config.template.json" || ! -f "${AIOS_DIR}/config/registry.template.json" ]]; then
  echo "ERROR: Missing AI_OS config templates in ${AIOS_DIR}/config"
  exit 1
fi

echo "[5/10] Render AI_OS config placeholders"
render_template "${AIOS_DIR}/config/mcp_config.template.json" "${AIOS_DIR}/config/mcp_config.json" "${AIOS_DIR}"
render_template "${AIOS_DIR}/config/registry.template.json" "${AIOS_DIR}/config/registry.json" "${AIOS_DIR}"
assert_no_placeholder "${AIOS_DIR}/config/mcp_config.json"
assert_no_placeholder "${AIOS_DIR}/config/registry.json"
discover_skills_and_update_mcp
configure_mcp_targets
install_skills_runtime_deps

host_os="$(uname -s 2>/dev/null || echo unknown)"
if [[ "${host_os}" == "Darwin" ]]; then
  echo "[6/10] Install Homebrew if missing (best effort)"
  if ! command -v brew >/dev/null 2>&1; then
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  echo "[7/10] Install OrbStack/Tailscale/Bitwarden (best effort)"
  if command -v brew >/dev/null 2>&1; then
    brew install --cask orbstack tailscale bitwarden || true
  fi

  echo "[8/10] Start container runtime (OrbStack preferred)"
  open -a OrbStack || open -a Docker || true
else
  echo "[6/10] Non-macOS remote detected; skipping Homebrew/cask/GUI steps"
fi

echo "[9/10] Wait for Docker Engine"
docker_ready=0
for _ in $(seq 1 60); do
  if docker info >/dev/null 2>&1; then
    docker_ready=1
    break
  fi
  sleep 3
done
if [[ "${docker_ready}" -ne 1 ]]; then
  echo "WARNING: Docker Engine not ready yet. Start your container runtime/daemon, then run:"
  echo "  cd ${PROJECT_DIR}"
  echo "  docker compose -f ${COMPOSE_FILE} up -d --build"
  exit 0
fi

echo "[10/10] Start stack + pull models"
cd "${PROJECT_DIR}"
start_stack_in_order
pull_models_sequentially
dcompose ps
EOF

cat <<MSG

Remote AI_OS bootstrap finished.

Services on remote host:
- n8n: http://localhost:5678
- Query Router API: http://localhost:4001/v1
- OpenClaw: http://localhost:3400

Recommended next step from controller machine:
1. Open SSH tunnel to 5678/4001/3400.
2. Sign into services and validate routing from n8n/OpenClaw.

MSG
