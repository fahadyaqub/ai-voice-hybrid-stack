# One-Command Bootstrap (AI_OS Online-First)

## Commands

```bash
./bootstrap/one_click.sh local
./bootstrap/one_click.sh local --with-ollama
./bootstrap/one_click.sh remote <remote-host>
./bootstrap/one_click.sh remote <remote-host> --with-ollama
```

Optional destructive reset (compose volumes):
```bash
./bootstrap/one_click.sh local --reset-state
./bootstrap/one_click.sh remote <remote-host> --reset-state
```

## What It Does

1. Prepares `.env` and generated secrets.
2. Validates required online keys (`GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, `OPENAI_API_KEY`) unless bypassed.
3. Applies low-memory safeguards for Ollama when needed.
4. Renders MCP config, discovers `AI_OS/skills/*`, and appends skill MCP entries.
5. Copies MCP config for host tools (Cline/Antigravity) and OpenClaw runtime.
6. Starts services in ordered health-aware sequence.
7. Pulls optional local Ollama models sequentially when `--with-ollama` is enabled.

## Canonical Compose

`AI_OS/services/docker-compose.yml`

## Notes

1. OpenClaw is always started.
2. Online-first routing relies on configured provider keys.
3. Without `--with-ollama`, startup is fully online-only (no local model path).
4. `--reset-state` is optional and destructive to compose state.
5. Set `SKIP_ONLINE_KEY_CHECK=true` only for intentional local-only testing.
