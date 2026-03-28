# AI_OS Online-First Handoff

Last updated: 2026-03-28 (Asia/Karachi)

## Goal

Run a portable, remote-capable multi-agent stack across macOS/Linux/WSL with cloud-first routing.

## Frozen Intelligence Stack

1. Manager (`assistant-manager`): Gemini
2. Engineer (`assistant-engineer`): DeepSeek
3. Validator (`assistant-validator`): OpenAI
4. Optional local Ollama runtime when started with `--with-ollama` (no automatic fallback chain)

## Enforcement Rule

CEO must not mark tasks complete until Validator returns exact `AUDIT_PASSED`.

## Infrastructure Highlights

1. Redis cache layer added with bounded memory:
   - `redis-server --maxmemory 100mb --maxmemory-policy allkeys-lru`
2. `litellm` and `n8n` set to `mem_limit: 1g`.
3. `postgres` and `ollama` now also have explicit memory limits.
4. OpenClaw image pinned: `ghcr.io/openclaw/openclaw:2026.2.26`.
5. Ollama safety locks retained:
   - `OLLAMA_KEEP_ALIVE=0`
   - `OLLAMA_MAX_LOADED_MODELS=1`
6. LiteLLM no longer hard-blocks on Ollama health (online-first startup preserved).

## Bootstrap Enhancements

1. OpenClaw now starts unconditionally.
2. `--reset-state` optional destructive reset support.
3. `--with-ollama` enables optional local Ollama service and model pulls.
4. MCP config render + copy to common host paths for Cline/Antigravity, with placeholder validation.
5. Online-key preflight check (Gemini/DeepSeek/OpenAI) before startup.

## Canonical Paths

1. Compose: `AI_OS/services/docker-compose.yml`
2. LiteLLM config: `AI_OS/services/litellm/config.yaml`
3. Personas: `AI_OS/persona/*.md`
4. Workspace: `AI_OS/workspace/project_1..project_6`

## Manual Steps Still Required

1. Account creation/login (email, Tailscale, Bitwarden).
2. OS-level privileged prompt approvals.
3. CAPTCHA/SMS verification flows.
