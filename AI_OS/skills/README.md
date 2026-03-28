# Skills Directory

Each subdirectory in `AI_OS/skills/` is a modular capability.

Minimum required files per skill:
1. `tool.json`: metadata and input schema.
2. `executor.sh` or `executor.py`: executable logic.

During bootstrap, skills are discovered and injected into MCP configuration files for host tools (Cline/Antigravity) and OpenClaw.
