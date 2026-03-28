#!/usr/bin/env python3
"""MCP adapter that exposes all AI_OS skills as tools in one process."""

from __future__ import annotations

import argparse
import json
import keyword
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run aggregated AI_OS skills as one MCP server")
    parser.add_argument("--skills-dir", required=True, help="Path to AI_OS/skills directory")
    parser.add_argument(
        "--repo-root",
        default="",
        help="Repository root passed to executors via AIOS_REPO_ROOT",
    )
    return parser.parse_args()


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", value.strip().lower())
    slug = re.sub(r"_+", "_", slug).strip("_")
    if not slug:
        slug = "skill"
    if slug[0].isdigit():
        slug = f"s_{slug}"
    if keyword.iskeyword(slug):
        slug = f"{slug}_tool"
    return slug


def py_type_for_schema(schema: dict[str, Any]) -> str:
    t = schema.get("type", "string")
    if t == "boolean":
        return "bool"
    if t == "integer":
        return "int"
    if t == "number":
        return "float"
    if t == "array":
        return "list"
    if t == "object":
        return "dict"
    return "str"


def default_literal(schema: dict[str, Any]) -> str:
    if "default" in schema:
        return repr(schema["default"])

    t = schema.get("type", "string")
    if t == "boolean":
        return "False"
    if t in {"integer", "number"}:
        return "0"
    if t == "array":
        return "None"
    if t == "object":
        return "None"
    return "''"


def discover_skills(skills_dir: Path) -> list[dict[str, Any]]:
    discovered: list[dict[str, Any]] = []

    if not skills_dir.exists():
        return discovered

    for skill_dir in sorted(p for p in skills_dir.iterdir() if p.is_dir()):
        tool_file = skill_dir / "tool.json"
        if not tool_file.exists():
            continue

        try:
            tool = json.loads(tool_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise ValueError(f"Invalid JSON in {tool_file}: {exc}") from exc

        for key in ("name", "description", "input_schema"):
            if key not in tool:
                raise ValueError(f"{tool_file} missing required key '{key}'")

        input_schema = tool["input_schema"]
        if not isinstance(input_schema, dict):
            raise ValueError(f"input_schema must be object in {tool_file}")
        if input_schema.get("type", "object") != "object":
            raise ValueError(f"input_schema.type must be 'object' in {tool_file}")

        properties = input_schema.get("properties", {})
        if not isinstance(properties, dict):
            raise ValueError(f"input_schema.properties must be object in {tool_file}")

        required = input_schema.get("required", [])
        if not isinstance(required, list):
            raise ValueError(f"input_schema.required must be array in {tool_file}")

        executor_rel = tool.get("executor", "executor.sh")
        executor = skill_dir / executor_rel
        if not executor.exists():
            raise ValueError(f"Executor not found for {tool['name']}: {executor}")

        tool_name = f"skill_{slugify(str(tool['name']))}"

        discovered.append(
            {
                "name": str(tool["name"]),
                "tool_name": tool_name,
                "description": str(tool["description"]),
                "input_schema": input_schema,
                "properties": properties,
                "required": set(str(x) for x in required),
                "executor": executor.resolve(),
                "skill_dir": skill_dir.resolve(),
            }
        )

    return discovered


def build_tool_function(
    tool_name: str,
    description: str,
    properties: dict[str, Any],
    required: set[str],
    run_skill_fn,
):
    fields: list[tuple[str, str, bool, str]] = []
    for raw_name, schema in properties.items():
        if not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", raw_name):
            raise ValueError(f"Unsupported property name '{raw_name}' in skill {tool_name}")
        if keyword.iskeyword(raw_name):
            raise ValueError(f"Unsupported property name '{raw_name}' (python keyword) in skill {tool_name}")

        typ = py_type_for_schema(schema if isinstance(schema, dict) else {})
        is_required = raw_name in required
        default = default_literal(schema if isinstance(schema, dict) else {})
        fields.append((raw_name, typ, is_required, default))

    signature_parts = []
    payload_lines = []
    annotations: dict[str, Any] = {
        "str": str,
        "int": int,
        "float": float,
        "bool": bool,
        "dict": dict,
        "list": list,
    }

    for name, typ, is_required, default in fields:
        if is_required:
            signature_parts.append(f"{name}: {typ}")
        else:
            signature_parts.append(f"{name}: {typ} = {default}")
        payload_lines.append(f"    payload['{name}'] = {name}")

    signature = ", ".join(signature_parts)
    payload_block = "\n".join(payload_lines) if payload_lines else "    pass"

    src = f"""
def {tool_name}({signature}) -> str:
    payload = {{}}
{payload_block}
    return _run_skill(payload)
"""

    namespace: dict[str, Any] = {"_run_skill": run_skill_fn}
    namespace.update(annotations)
    exec(src, namespace)  # noqa: S102 - controlled generated source
    fn = namespace[tool_name]
    fn.__doc__ = description
    return fn


def main() -> int:
    args = parse_args()
    skills_dir = Path(args.skills_dir).resolve()
    repo_root = Path(args.repo_root).resolve() if args.repo_root else None

    try:
        from mcp.server.fastmcp import FastMCP
    except Exception as exc:  # pragma: no cover
        print("Missing dependency 'mcp'. Install with: pip install -r requirements.txt", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 2

    try:
        skills = discover_skills(skills_dir)
    except Exception as exc:
        print(f"Failed discovering skills: {exc}", file=sys.stderr)
        return 1

    server = FastMCP("ai-os-skills")

    @server.tool()
    def list_skills() -> dict[str, Any]:
        """List discovered skills and their MCP tool names."""
        return {
            "count": len(skills),
            "skills": [
                {
                    "name": s["name"],
                    "tool_name": s["tool_name"],
                    "description": s["description"],
                    "input_schema": s["input_schema"],
                }
                for s in skills
            ],
        }

    for skill in skills:
        executor = Path(skill["executor"])
        skill_dir = Path(skill["skill_dir"])
        skill_name = str(skill["name"])

        def _run_skill(payload: dict[str, Any], *, _exec=executor, _dir=skill_dir, _name=skill_name) -> str:
            env = os.environ.copy()
            env["AIOS_SKILL_NAME"] = _name
            env["AIOS_SKILL_INPUT_JSON"] = json.dumps(payload)
            if repo_root is not None:
                env["AIOS_REPO_ROOT"] = str(repo_root)

            try:
                proc = subprocess.run(
                    [str(_exec)],
                    cwd=str(_dir),
                    env=env,
                    text=True,
                    capture_output=True,
                    timeout=30,
                )
            except subprocess.TimeoutExpired:
                raise RuntimeError(f"Skill '{_name}' timed out after 30s")

            stdout = proc.stdout.strip()
            stderr = proc.stderr.strip()
            if proc.returncode != 0:
                joined = "\n".join(x for x in [stdout, stderr] if x)
                raise RuntimeError(joined or f"Skill '{_name}' failed with code {proc.returncode}")

            return "\n".join(x for x in [stdout, stderr] if x).strip()

        try:
            fn = build_tool_function(
                tool_name=str(skill["tool_name"]),
                description=str(skill["description"]),
                properties=dict(skill["properties"]),
                required=set(skill["required"]),
                run_skill_fn=_run_skill,
            )
        except Exception as exc:
            print(f"Failed building tool for skill '{skill_name}': {exc}", file=sys.stderr)
            return 1

        server.tool()(fn)

    server.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
