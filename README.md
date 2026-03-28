# AI_OS Director Stack (Online-First)

A portable multi-agent stack for a dedicated machine, using cloud models first so it runs well across hardware sizes.

## What This Is

`ai-voice-hybrid-stack` gives you a ready-to-run "AI operating environment" where:
1. A manager lane handles planning/context.
2. An engineer lane handles implementation.
3. A validator lane reviews and gates completion.
4. A shared 6-project workspace keeps work organized.
5. Antigravity + Cline act as the operator control plane.

## What It Is For

Use this when you want:
1. A separate machine for agentic workflows (local or remote).
2. Lower cost than always-running large local models.
3. Multi-project orchestration in one setup.
4. A repeatable install flow you can share with others.

## Platform Support

1. macOS: supported.
2. Linux: supported.
3. Windows: supported via WSL2 (recommended) with Docker running in WSL2/Desktop integration.

## Core Idea

Online-first routing:
1. Use cloud models for primary lanes (Gemini/DeepSeek/OpenAI).
2. Keep local models optional (`--with-ollama`) for constrained hardware.
3. Route requests through one internal API (`query-router`) so tools/agents use a single endpoint.

## Architecture

1. `AI_OS/services`: Docker services (LiteLLM, router, n8n, OpenClaw, Redis, Postgres, TTS, optional Ollama).
2. `AI_OS/workspace`: `project_1` to `project_6`.
3. `AI_OS/persona`: agent role contracts (`CEO_SOUL.md`, `ENGINEER_SPEC.md`, `VALIDATOR_SPEC.md`).
4. `AI_OS/config`: registry + MCP templates/runtime configs.

Intelligence lanes:
1. `assistant-manager` -> Gemini
2. `assistant-engineer` -> DeepSeek
3. `assistant-validator` -> OpenAI

## Control Plane (Important)

`Antigravity + Cline` are part of the full solution.
1. They are host apps, not Docker services in this repo.
2. Bootstrap copies MCP config to common Antigravity/Cline locations.
3. Include Antigravity/Cline RAM usage in memory planning.

## Install Options (Smoothness)

1. `GitHub (Recommended)`: easiest to share and maintain.
2. `Tailscale + SSH (Recommended for your remote-control workflow)`: best for taking over setup remotely.
3. `USB copy`: works offline, but least maintainable.

Best practical pattern is GitHub + Tailscale + remote bootstrap.

## Quick Start: Local Machine

```bash
git clone https://github.com/fahadyaqub/ai-voice-hybrid-stack.git
cd ai-voice-hybrid-stack
./bootstrap/one_click.sh local
```

Optional local model runtime:
```bash
./bootstrap/one_click.sh local --with-ollama
```

Optional destructive reset:
```bash
./bootstrap/one_click.sh local --reset-state
```

## Quick Start: Remote Mac (Over Tailscale/SSH)

On the remote Mac (manual minimum):
1. Install Tailscale.
2. Sign in to Tailscale.
3. Ensure SSH is available.

From your controller machine:
```bash
git clone https://github.com/fahadyaqub/ai-voice-hybrid-stack.git
cd ai-voice-hybrid-stack
REMOTE_USER=agent-runner ./bootstrap/one_click.sh remote <remote-host-or-tailnet-name>
```

Optional local model runtime on remote:
```bash
REMOTE_USER=agent-runner ./bootstrap/one_click.sh remote <remote-host-or-tailnet-name> --with-ollama
```

## Quick Start: Remote Cloud VM (Google Cloud, etc.)

Yes, this can run on remote cloud machines too.

Recommended for Linux VMs:
1. Create VM.
2. Install Docker + Docker Compose on the VM.
3. Enable SSH access.
4. Run remote bootstrap from your controller with Linux paths/users.

Example:
```bash
git clone https://github.com/fahadyaqub/ai-voice-hybrid-stack.git
cd ai-voice-hybrid-stack
REMOTE_USER=ubuntu REMOTE_BASE_DIR=/home/ubuntu/agent-stack ./bootstrap/one_click.sh remote <vm-ip-or-dns>
```

Notes for cloud:
1. `REMOTE_BASE_DIR` auto-defaults to `<remote-home>/agent-stack` if not provided.
2. Set `REMOTE_USER` explicitly when it differs from your local username.
3. Install provider keys in `.env` on the target stack path.

## Required API Keys

Set these in `.env`:
1. `GEMINI_API_KEY`
2. `DEEPSEEK_API_KEY`
3. `OPENAI_API_KEY`

If missing, bootstrap blocks startup by default (online-first protection).

Intentional bypass:
```bash
SKIP_ONLINE_KEY_CHECK=true ./bootstrap/one_click.sh local
```

## Runtime Flags

1. `--with-ollama`: starts optional Ollama runtime and pulls configured local models.
2. `--reset-state`: removes compose state/volumes before startup (destructive).

Without `--with-ollama`, stack is fully online-only.

## Default Endpoints

1. n8n: `http://localhost:5678`
2. Query Router API: `http://localhost:4001/v1`
3. OpenClaw: `http://localhost:3400`

Ports are bound to localhost by default. For remote access, use SSH tunnels.

Example tunnel:
```bash
ssh -L 5678:localhost:5678 -L 4001:localhost:4001 -L 3400:localhost:3400 <user>@<host>
```

## Day-to-Day Usage Flow

1. Open Antigravity/Cline.
2. Point tools/agents to Query Router endpoint (`/v1`).
3. Work inside `AI_OS/workspace/project_1..project_6`.
4. Use validator lane and only mark complete on `AUDIT_PASSED`.

## Security Model

1. Localhost-only service bindings.
2. OpenClaw mounts limited to `workspace`, `persona`, `config`.
3. `.env` is not committed by default.
4. Runtime config templates are rendered locally during bootstrap.

## Memory and Cost Defaults

1. Cloud-first lanes reduce local RAM pressure.
2. Redis cache bounded to `100mb` with LRU.
3. Service limits applied (including router/TTS caps).
4. LiteLLM budget guardrails enabled:
   - `max_budget: 10.0`
   - `budget_duration: 1d`

Container runtime recommendation:
1. OrbStack preferred.
2. Docker Desktop supported fallback.
3. On low-memory hosts (for example around 8GB), keep Ollama optional and use cloud-first mode.

## Troubleshooting

1. `docker: command not found`:
   - install/start OrbStack or Docker Desktop.
2. Remote bootstrap cannot SSH:
   - verify Tailscale/SSH, user, and host.
3. Startup blocked on key check:
   - set required API keys in `.env`.
4. UI not reachable:
   - check SSH tunnel and `docker compose ps` on target.

## What Is Automated vs Manual

Automated:
1. `.env` creation and secret generation (when missing).
2. Config rendering and MCP file copy.
3. Ordered service startup.

Manual (cannot be fully automated reliably):
1. Account logins (email/Tailscale/provider portals).
2. OS security dialogs and admin approvals.
3. CAPTCHA/SMS verification steps.

## Canonical Files

1. Compose: `AI_OS/services/docker-compose.yml`
2. LiteLLM config: `AI_OS/services/litellm/config.yaml`
3. Router: `AI_OS/services/router/app.py`
4. Bootstrap entrypoint: `bootstrap/one_click.sh`
