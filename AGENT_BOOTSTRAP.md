# Agent Bootstrap Playbook (AI_OS Online-First)

## Objective

From this folder alone, an agent should set up:
1. Local machine (`local`), or
2. Remote machine over SSH/Tailscale (`remote`),

with minimal user actions and cross-platform defaults.

## First Questions

1. `local` or `remote`?
2. Enable optional local Ollama runtime (`--with-ollama`)?
3. Do a clean reset (`--reset-state`) before startup?

## Execution Commands

```bash
./bootstrap/one_click.sh local
./bootstrap/one_click.sh local --with-ollama
./bootstrap/one_click.sh remote <remote-host>
./bootstrap/one_click.sh remote <remote-host> --with-ollama
```

## Runtime Lanes

1. Manager: `assistant-manager` (Gemini)
2. Engineer: `assistant-engineer` (DeepSeek)
3. Validator: `assistant-validator` (OpenAI)
4. Optional local Ollama runtime is enabled only with `--with-ollama` (no automatic fallback chain)

## Skills Architecture

1. Skills live in `AI_OS/skills/<skill_name>/`.
2. Each skill requires `tool.json` and an executable (`executor.sh` or `executor.py`).
3. Bootstrap validates skill manifests and injects discovered skills into MCP configs.

## Audit Gate Rule

Completion requires validator token:
1. `AUDIT_PASSED` -> mark complete
2. anything else -> keep task open with findings

## Bootstrap Guarantees

1. Creates `.env` if missing.
2. Generates missing secrets.
3. Validates required online keys (`GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`) unless bypassed.
4. Applies low-memory profile values when needed.
5. Renders MCP/registry templates into runtime config.
6. Copies MCP config to common Cline/Antigravity paths.
7. Discovers skills and writes `AI_OS/config/skills_index.json`.
8. Starts services in health-aware order.
9. Pulls optional local Ollama models sequentially when `--with-ollama` is enabled.

## Hard Limits (Human Needed)

1. Account creation/login flows.
2. OS admin/security approvals.
3. CAPTCHA/SMS verification.
