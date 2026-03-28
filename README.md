# AI_OS Director Stack (Online-First)

This package provides a portable `AI_OS` stack optimized for 8GB M1 hardware by using cloud models first.

## Modes

1. `local`: run on the same machine.
2. `remote`: run on another machine over SSH/Tailscale.

## Core Architecture

1. `AI_OS/services`: LiteLLM, Query Router, n8n, Redis cache, Postgres, TTS, OpenClaw, and optional Ollama runtime.
2. `AI_OS/workspace`: shared room with `project_1` to `project_6`.
3. `AI_OS/persona`: `CEO_SOUL.md`, `ENGINEER_SPEC.md`, `VALIDATOR_SPEC.md`.
4. `AI_OS/config`: registry + MCP templates/runtime files.

## Control Plane (Important)

1. This stack is designed to be operated with `Antigravity + Cline` for multi-agent workflows.
2. `Antigravity/Cline` are host-level tools (not Docker services in this repo), but they are part of the full solution.
3. Bootstrap renders and copies `AI_OS/config/mcp_config.json` to common Cline/Antigravity locations so agents can share the same `AI_OS/workspace`.
4. For memory planning on 8GB hardware, include host-side `Antigravity/Cline` RAM usage in addition to Docker container usage.

## Intelligence Lanes

1. `assistant-manager` -> Gemini (planning/context)
2. `assistant-engineer` -> DeepSeek (implementation)
3. `assistant-validator` -> OpenAI (audit)
4. Optional local model runtime only when started with `--with-ollama` (no automatic fallback chain)

## One Command

Local:
```bash
./bootstrap/one_click.sh local
```

Remote:
```bash
./bootstrap/one_click.sh remote <remote-host>
```

Remote + optional Ollama runtime:
```bash
./bootstrap/one_click.sh remote <remote-host> --with-ollama
```

Local + optional Ollama runtime:
```bash
./bootstrap/one_click.sh local --with-ollama
```

Optional clean state reset (destructive to compose volumes):
```bash
./bootstrap/one_click.sh local --reset-state
```

Online-first preflight requires these keys in `.env`:
1. `GEMINI_API_KEY`
2. `DEEPSEEK_API_KEY`
3. `OPENAI_API_KEY`

To bypass key check intentionally:
```bash
SKIP_ONLINE_KEY_CHECK=true ./bootstrap/one_click.sh local
```

Without `--with-ollama`, the stack is fully online-only (no local model path).

## 8GB Safety Defaults

1. `OLLAMA_NUM_PARALLEL=1` (applied when `--with-ollama` is used)
2. `OLLAMA_MAX_LOADED_MODELS=1` (applied when `--with-ollama` is used)
3. `OLLAMA_KEEP_ALIVE=0` (applied when `--with-ollama` is used)
4. Redis bounded cache (`100mb`, `allkeys-lru`)
5. `litellm` and `n8n` set to `mem_limit: 1g`

## Container Runtime Choice (8GB M1)

1. `OrbStack` is the recommended default for 8GB M1 (lower overhead and faster startup).
2. `Docker Desktop` still works as a fallback.
3. Compose flow is unchanged in either runtime; bootstrap now tries `OrbStack` first, then `Docker Desktop`.

## Service Endpoints

1. n8n: `http://localhost:5678`
2. Query Router API: `http://localhost:4001/v1`
3. OpenClaw: `http://localhost:3400`

## Security Defaults

1. Host ports bound to localhost.
2. OpenClaw mounts only `AI_OS/workspace`, `AI_OS/persona`, `AI_OS/config`.
3. No automatic mount of host personal folders/credentials into runtime containers.
4. Secrets generated into `.env` when missing.

## Manual Steps (cannot be fully automated)

1. Email/Tailscale/Bitwarden account creation/sign-in.
2. macOS privileged approval prompts.
3. CAPTCHA/SMS verification flows.
