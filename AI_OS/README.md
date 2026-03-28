# AI_OS Directory (Online-First)

Portable runtime unit for the stack.

## Structure

1. `services/` Docker services and service configs.
2. `workspace/` Project slots (`project_1` ... `project_6`).
3. `persona/` manager/engineer/validator identity specs.
4. `config/` registry + MCP templates/runtime files.

## Canonical Compose

`AI_OS/services/docker-compose.yml`

## Rendering Flow

Templates:
1. `config/mcp_config.template.json`
2. `config/registry.template.json`

Bootstrap-generated runtime files:
1. `config/mcp_config.json`
2. `config/registry.json`
