"""
Anthropic Claude 调用封装。
直接读 ANTHROPIC_API_KEY / ANTHROPIC_BASE_URL 环境变量，
与 Claude Code 共用同一套配置，无需额外 token。

内部把 agent.py 使用的 OpenAI 消息格式转换成 Anthropic 格式。
"""

import json

import anthropic

from config import settings

_client = anthropic.Anthropic(
    api_key=settings.ANTHROPIC_API_KEY or None,
    base_url=settings.ANTHROPIC_BASE_URL or None,
)

_MODEL = settings.ANTHROPIC_DEFAULT_SONNET_MODEL


def chat(messages: list[dict], tools: list[dict] | None = None) -> dict:
    """
    接受 OpenAI 格式的 messages，调用 Claude，
    返回 OpenAI 格式的 response dict（供 agent.py 统一解析）。
    """
    system, anthropic_messages = _convert_messages(messages)

    kwargs: dict = dict(
        model=_MODEL,
        max_tokens=4096,
        messages=anthropic_messages,
    )
    if system:
        kwargs["system"] = system
    if tools:
        kwargs["tools"] = _to_anthropic_tools(tools)

    response = _client.messages.create(**kwargs)
    return _to_openai_format(response)


# ── 格式转换 ──────────────────────────────────────────────────────────────


def _convert_messages(messages: list[dict]) -> tuple[str, list[dict]]:
    """
    OpenAI 消息格式 → (system_str, anthropic_messages)

    OpenAI tool result:  {role: "tool", tool_call_id, content}
    Anthropic tool result: {role: "user", content: [{type: "tool_result", tool_use_id, content}]}

    OpenAI assistant with tool_calls:
        {role: "assistant", content, tool_calls: [{id, type, function: {name, arguments}}]}
    Anthropic assistant with tool_use:
        {role: "assistant", content: [{type: "text", ...}, {type: "tool_use", id, name, input}]}
    """
    system = ""
    result: list[dict] = []

    for m in messages:
        role = m["role"]

        if role == "system":
            system = m.get("content") or ""
            continue

        if role == "tool":
            # 合并到前一条 user 消息（Anthropic 要求 tool_result 在 user role 里）
            tool_result_block = {
                "type": "tool_result",
                "tool_use_id": m["tool_call_id"],
                "content": m.get("content") or "",
            }
            if result and result[-1]["role"] == "user" and isinstance(result[-1]["content"], list):
                result[-1]["content"].append(tool_result_block)
            else:
                result.append({"role": "user", "content": [tool_result_block]})
            continue

        if role == "assistant":
            blocks: list[dict] = []
            text = m.get("content") or ""
            if text:
                blocks.append({"type": "text", "text": text})
            for tc in m.get("tool_calls") or []:
                fn = tc["function"]
                try:
                    input_data = json.loads(fn["arguments"])
                except (json.JSONDecodeError, TypeError):
                    input_data = {}
                blocks.append({
                    "type": "tool_use",
                    "id": tc["id"],
                    "name": fn["name"],
                    "input": input_data,
                })
            result.append({"role": "assistant", "content": blocks or text})
            continue

        # user message
        result.append({"role": "user", "content": m.get("content") or ""})

    return system, result


def _to_anthropic_tools(tools: list[dict]) -> list[dict]:
    """OpenAI function calling 格式 → Anthropic tool 格式。"""
    return [
        {
            "name": t["function"]["name"],
            "description": t["function"].get("description", ""),
            "input_schema": t["function"].get("parameters", {"type": "object", "properties": {}}),
        }
        for t in tools
    ]


def _to_openai_format(response) -> dict:
    """Anthropic Messages response → OpenAI Chat Completions 格式。"""
    tool_calls = []
    text_content = ""

    for block in response.content:
        if block.type == "tool_use":
            tool_calls.append({
                "id": block.id,
                "type": "function",
                "function": {
                    "name": block.name,
                    "arguments": json.dumps(block.input, ensure_ascii=False),
                },
            })
        elif block.type == "text":
            text_content += block.text

    finish_reason = "tool_calls" if tool_calls else "stop"
    message: dict = {"role": "assistant", "content": text_content}
    if tool_calls:
        message["tool_calls"] = tool_calls

    return {
        "choices": [{"finish_reason": finish_reason, "message": message}],
        "model": response.model,
    }
