import json
import os
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, Response, StreamingResponse

app = FastAPI(title="ai-query-router", version="0.2.0")

LITELLM_BASE_URL = os.getenv("LITELLM_BASE_URL", "http://litellm:4000").rstrip("/")
SMART_ALIAS = os.getenv("ROUTER_SMART_ALIAS", "assistant-smart")
ONLINE_ALIAS = os.getenv("ROUTER_ONLINE_ALIAS", "assistant-manager")
REASONING_ALIAS = os.getenv("ROUTER_REASONING_ALIAS", "assistant-engineer")
VALIDATOR_ALIAS = os.getenv("ROUTER_VALIDATOR_ALIAS", "assistant-validator")
DEFAULT_ALIAS = os.getenv("ROUTER_DEFAULT_ALIAS", "assistant-manager")
RESPECT_EXPLICIT_MODELS = os.getenv("ROUTER_RESPECT_EXPLICIT_MODELS", "true").lower() == "true"
DEFAULT_LANGUAGE = os.getenv("ROUTER_DEFAULT_LANGUAGE", "english").strip().lower()

WEB_KEYWORDS = {
    "latest",
    "current",
    "today",
    "yesterday",
    "this week",
    "this month",
    "news",
    "price",
    "stock",
    "weather",
    "score",
    "schedule",
    "who is the ceo",
    "release date",
    "regulation",
    "law",
}

CODE_KEYWORDS = {
    "error",
    "exception",
    "traceback",
    "stack trace",
    "debug",
    "fix",
    "bug",
    "refactor",
    "test failed",
    "compile",
    "deploy",
    "docker",
    "kubernetes",
    "sql",
    "api",
    "python",
    "typescript",
    "javascript",
    "java",
    "go ",
    "rust",
    "bash",
    "regex",
    "function",
    "class ",
    "git ",
}

AUDIT_KEYWORDS = {
    "audit",
    "review",
    "validator",
    "peer review",
    "security review",
    "compliance",
    "verify",
    "validate",
    "approve",
    "approval",
    "qa",
    "check this",
    "check the code",
    "hard problem",
}


def _extract_text_from_messages(messages: list[dict[str, Any]]) -> str:
    chunks: list[str] = []
    for msg in messages:
        content = msg.get("content", "")
        if isinstance(content, str):
            chunks.append(content)
            continue
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") == "text":
                    text = part.get("text", "")
                    if isinstance(text, str):
                        chunks.append(text)
    return "\n".join(chunks).lower()


def _contains_any(text: str, keywords: set[str]) -> bool:
    return any(keyword in text for keyword in keywords)


def _is_code_like(text: str) -> bool:
    if "```" in text:
        return True
    return _contains_any(text, CODE_KEYWORDS)


def _is_web_like(text: str) -> bool:
    return _contains_any(text, WEB_KEYWORDS)


def _is_audit_like(text: str) -> bool:
    return _contains_any(text, AUDIT_KEYWORDS)


def choose_model(requested_model: str | None, body: dict[str, Any]) -> str:
    requested = (requested_model or "").strip()

    if requested and requested != SMART_ALIAS and RESPECT_EXPLICIT_MODELS:
        return requested

    messages = body.get("messages", [])
    if not isinstance(messages, list):
        return DEFAULT_ALIAS

    prompt_text = _extract_text_from_messages(messages)

    if _is_audit_like(prompt_text):
        return VALIDATOR_ALIAS
    if _is_web_like(prompt_text):
        return ONLINE_ALIAS
    if _is_code_like(prompt_text):
        return REASONING_ALIAS
    return DEFAULT_ALIAS


def _ensure_language_system_message(body: dict[str, Any]) -> None:
    if DEFAULT_LANGUAGE != "english":
        return

    messages = body.get("messages")
    if not isinstance(messages, list):
        return

    system_text = (
        "Default response language is English. "
        "If the user explicitly requests another language, follow that request."
    )

    for msg in messages:
        if not isinstance(msg, dict):
            continue
        if msg.get("role") != "system":
            continue
        content = msg.get("content", "")
        if isinstance(content, str) and "Default response language is English" in content:
            return

    messages.insert(0, {"role": "system", "content": system_text})


def _forward_headers(request: Request) -> dict[str, str]:
    headers = {}
    for key, value in request.headers.items():
        lk = key.lower()
        if lk in {"host", "content-length"}:
            continue
        headers[key] = value
    return headers


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/v1/models")
async def models(request: Request) -> Response:
    upstream_url = f"{LITELLM_BASE_URL}/v1/models"
    async with httpx.AsyncClient(timeout=60.0) as client:
        resp = await client.get(upstream_url, headers=_forward_headers(request))

    if resp.status_code >= 400:
        return Response(content=resp.content, status_code=resp.status_code, media_type=resp.headers.get("content-type"))

    try:
        payload = resp.json()
    except json.JSONDecodeError:
        return Response(content=resp.content, status_code=resp.status_code, media_type=resp.headers.get("content-type"))

    data = payload.get("data")
    if isinstance(data, list):
        has_smart = any(isinstance(item, dict) and item.get("id") == SMART_ALIAS for item in data)
        if not has_smart:
            data.insert(
                0,
                {
                    "id": SMART_ALIAS,
                    "object": "model",
                    "owned_by": "query-router",
                },
            )

    return JSONResponse(payload, status_code=resp.status_code)


@app.post("/v1/chat/completions")
async def chat_completions(request: Request) -> Response:
    try:
        body = await request.json()
    except json.JSONDecodeError as exc:
        raise HTTPException(status_code=400, detail="Invalid JSON body") from exc

    if not isinstance(body, dict):
        raise HTTPException(status_code=400, detail="Request body must be an object")

    selected_model = choose_model(body.get("model"), body)
    body["model"] = selected_model
    _ensure_language_system_message(body)

    upstream_url = f"{LITELLM_BASE_URL}/v1/chat/completions"
    headers = _forward_headers(request)
    stream = bool(body.get("stream"))

    if stream:
        client = httpx.AsyncClient(timeout=None)
        req = client.build_request("POST", upstream_url, headers=headers, json=body)
        upstream_stream = await client.send(req, stream=True)

        async def iterator() -> Any:
            try:
                async for chunk in upstream_stream.aiter_bytes():
                    yield chunk
            finally:
                await upstream_stream.aclose()
                await client.aclose()

        return StreamingResponse(
            iterator(),
            status_code=upstream_stream.status_code,
            media_type=upstream_stream.headers.get("content-type", "text/event-stream"),
        )

    async with httpx.AsyncClient(timeout=None) as client:
        resp = await client.post(upstream_url, headers=headers, json=body)

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        media_type=resp.headers.get("content-type"),
    )


@app.api_route("/v1/{path:path}", methods=["GET", "POST", "PUT", "PATCH", "DELETE"])
async def passthrough(path: str, request: Request) -> Response:
    upstream_url = f"{LITELLM_BASE_URL}/v1/{path}"
    headers = _forward_headers(request)
    body = await request.body()

    async with httpx.AsyncClient(timeout=None) as client:
        resp = await client.request(request.method, upstream_url, headers=headers, content=body, params=request.query_params)

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        media_type=resp.headers.get("content-type"),
    )
