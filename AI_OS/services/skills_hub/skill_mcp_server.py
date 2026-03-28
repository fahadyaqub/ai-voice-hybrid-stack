#!/usr/bin/env python3
"""MCP adapter for one AI_OS skill directory.

This process exposes one callable tool for the selected skill and delegates
execution to the skill's local executor script.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run one AI_OS skill as an MCP server")
    parser.add_argument("--skill-dir", required=True, help="Path to skill directory")
    parser.add_argument(
        "--repo-root",
        default="",
        help="Repository root passed to executors via AIOS_REPO_ROOT",
    )
    return parser.parse_args()


def load_skill(skill_dir: Path) -> tuple[dict[str, Any], Path]:
    tool_file = skill_dir / "tool.json"
    if not tool_file.exists():
        raise FileNotFoundError(f"Missing tool.json at {tool_file}")

    tool = json.loads(tool_file.read_text(encoding="utf-8"))
    for key in ("name", "description", "input_schema"):
        if key not in tool:
            raise ValueError(f"tool.json missing required key: {key}")

    executor_rel = tool.get("executor", "executor.sh")
    executor = skill_dir / executor_rel
    if not executor.exists():
        raise FileNotFoundError(f"Missing executor at {executor}")

    return tool, executor


def main() -> int:
    args = parse_args()
    skill_dir = Path(args.skill_dir).resolve()
    repo_root = Path(args.repo_root).resolve() if args.repo_root else None

    try:
        tool, executor = load_skill(skill_dir)
    except Exception as exc:  # pragma: no cover
        print(f"Failed loading skill: {exc}", file=sys.stderr)
        return 1

    try:
        from mcp.server.fastmcp import FastMCP
    except Exception as exc:  # pragma: no cover
        print("Missing dependency 'mcp'. Install with: pip install -r requirements.txt", file=sys.stderr)
        print(str(exc), file=sys.stderr)
        return 2

    skill_name = str(tool["name"])
    description = str(tool["description"])
    input_schema = tool.get("input_schema", {})

    server = FastMCP(f"ai-os-skill-{skill_name}")

    @server.tool()
    def skill_info() -> dict[str, Any]:
        """Return metadata for this skill."""
        return {
            "name": skill_name,
            "description": description,
            "input_schema": input_schema,
            "skill_dir": str(skill_dir),
            "executor": str(executor),
        }

    @server.tool()
    def run(
        action: str,
        message: str = "",
        branch: str = "",
        repo: str = "",
    ) -> str:
        """Execute the skill's action through its local executor."""
        cmd = [str(executor), action]
        if message:
            cmd.extend(["--message", message])
        if branch:
            cmd.extend(["--branch", branch])
        if repo:
            cmd.extend(["--repo", repo])

        env = os.environ.copy()
        if repo_root is not None:
            env["AIOS_REPO_ROOT"] = str(repo_root)

        proc = subprocess.run(
            cmd,
            cwd=str(skill_dir),
            env=env,
            text=True,
            capture_output=True,
        )

        output = proc.stdout.strip()
        err = proc.stderr.strip()
        if proc.returncode != 0:
            joined = "\n".join(x for x in [output, err] if x)
            raise RuntimeError(joined or f"Executor failed with code {proc.returncode}")

        if err:
            return f"{output}\n{err}".strip()
        return output

    server.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
