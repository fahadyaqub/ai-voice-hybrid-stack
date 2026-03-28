# ai-voice-hybrid-stack

Cloud-first, multi-agent runtime for local or remote machines.

This repository provisions a portable AI operations stack with:
- LiteLLM model gateway
- Query Router (single `/v1` endpoint)
- OpenClaw manager runtime
- n8n automation runtime
- Redis + Postgres backing services
- Optional Ollama local models
- Modular MCP skills (`AI_OS/skills/*`)

## Features

- One-command bootstrap for local and remote hosts
- Cloud-first routing (Gemini + DeepSeek + OpenAI)
- Optional local model runtime with `--with-ollama`
- Cross-platform target support (macOS, Linux, Windows via WSL2)
- Works with Antigravity + Cline via shared MCP config
- Skills discovery pipeline with starter `git_manager` skill

## Prerequisites

### Controller machine (where you run bootstrap)
- `git`
- `python3` (for MCP skill adapters)
- `ssh` and `rsync` (for remote mode)
- Docker CLI available (if using containerized fallback path)

### Target machine (where services run)
- Docker Engine + Docker Compose
- `python3` (for MCP skill adapters)
- SSH access from controller machine
- Internet access for pulling images and calling model APIs

### Required model API keys
Add these to `.env` on the stack root:
- `GEMINI_API_KEY`
- `DEEPSEEK_API_KEY`
- `OPENAI_API_KEY`

## Quick Start

### 1) Clone

```bash
git clone https://github.com/fahadyaqub/ai-voice-hybrid-stack.git
cd ai-voice-hybrid-stack
```

### 2) Local install (same machine)

```bash
./bootstrap/one_click.sh local
```

Optional local model runtime:

```bash
./bootstrap/one_click.sh local --with-ollama
```

### 3) Remote install (another machine)

```bash
REMOTE_USER=<remote-user> ./bootstrap/one_click.sh remote <remote-host>
```

Optional local model runtime on remote:

```bash
REMOTE_USER=<remote-user> ./bootstrap/one_click.sh remote <remote-host> --with-ollama
```

Notes:
- If `REMOTE_BASE_DIR` is not set, it defaults to `<remote-home>/agent-stack`.
- `remote-host` can be IP, DNS name, or Tailscale hostname.

### 4) Remote cloud VM (example: Google Cloud)

```bash
REMOTE_USER=ubuntu REMOTE_BASE_DIR=/home/ubuntu/agent-stack ./bootstrap/one_click.sh remote <vm-ip-or-dns>
```

## Commands

```bash
# local
./bootstrap/one_click.sh local

# local + optional ollama
./bootstrap/one_click.sh local --with-ollama

# remote
./bootstrap/one_click.sh remote <remote-host>

# remote + optional ollama
./bootstrap/one_click.sh remote <remote-host> --with-ollama

# destructive reset (removes compose state/volumes)
./bootstrap/one_click.sh local --reset-state
./bootstrap/one_click.sh remote <remote-host> --reset-state
```

## Configuration

`.env` is auto-created from `.env.example` when missing.

Bootstrap also performs a repository check:
- If current directory is not a git repo, it offers to run `git init` and set `origin`.
- Set `AUTO_GIT_INIT=true` to auto-accept this.
- Override remote with `REPO_URL=<git-url>`.

Bootstrap also auto-generates missing secrets such as:
- `POSTGRES_PASSWORD`
- `LITELLM_MASTER_KEY`
- `N8N_ENCRYPTION_KEY`
- `OPENCLAW_GATEWAY_TOKEN`

To intentionally bypass online-key preflight:

```bash
SKIP_ONLINE_KEY_CHECK=true ./bootstrap/one_click.sh local
```

## Skills

Skills live under `AI_OS/skills/<name>/` and use:
1. `tool.json` (name, description, input schema)
2. `executor.sh` or `executor.py`

During bootstrap:
1. Skills are validated.
2. MCP entries are appended for discovered skills.
3. `AI_OS/config/skills_index.json` is generated.

Starter skill included:
- `AI_OS/skills/git_manager` (`status`, `commit`, `pull`, `push` with branch safety defaults)

## Service Endpoints

After startup:
- n8n: `http://localhost:5678`
- Query Router API: `http://localhost:4001/v1`
- OpenClaw: `http://localhost:3400`

For remote hosts, use SSH tunneling:

```bash
ssh -L 5678:localhost:5678 -L 4001:localhost:4001 -L 3400:localhost:3400 <user>@<host>
```

## How Routing Works

Configured lanes:
- `assistant-manager` -> Gemini
- `assistant-engineer` -> DeepSeek
- `assistant-validator` -> OpenAI

Requests go through Query Router, which forwards to LiteLLM.

## Antigravity / Cline Integration

Bootstrap renders and copies MCP config so Antigravity and Cline can share:
1. Workspace context (`AI_OS/workspace/project_1..project_6`)
2. Discovered MCP skills from `AI_OS/skills/`

## Resource Profile

- Cloud-first by default (best for lower-memory machines)
- `--with-ollama` enables local model runtime
- Low-memory safeguards are applied automatically when needed
- Redis is memory bounded (`100mb`, `allkeys-lru`)

## Security Defaults

- Host-exposed ports bind to localhost
- OpenClaw mount scope is limited to workspace/persona/config and repo path for skill-driven git workflows
- `.env` is ignored by git

## Repository Structure

```text
AI_OS/
  services/
  workspace/
  persona/
  config/
  skills/
bootstrap/
.env.example
```

## Troubleshooting

- `docker: command not found`
  - Start/install your container runtime (OrbStack or Docker Desktop on macOS, Docker Engine on Linux/WSL2).
- Remote bootstrap SSH failure
  - Verify `REMOTE_USER`, host, key auth, and network/Tailscale connectivity.
- Startup blocked by missing keys
  - Set `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, `OPENAI_API_KEY` in `.env`.
- Service UI not reachable
  - Check tunnels and run `docker compose -f AI_OS/services/docker-compose.yml ps` on target host.

## Canonical Files

- Compose: `AI_OS/services/docker-compose.yml`
- LiteLLM: `AI_OS/services/litellm/config.yaml`
- Router: `AI_OS/services/router/app.py`
- Bootstrap entry: `bootstrap/one_click.sh`
