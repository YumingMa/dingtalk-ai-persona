"""Agent 主循环：LightChat + dws 工具编排。"""

import json
from dws_tools import TOOLS, execute_tool
from lightchat import chat

SYSTEM_PROMPT = """你是用户在钉钉上的 AI 分身。你能以用户自己的身份操作钉钉：
读取/创建文档、发送消息、分析周报、管理待办、查询日程、搜索知识库等。

原则：
- 理解用户意图，选择合适工具，逐步执行
- 发消息给他人前，先告知用户将要发送的内容
- 读取内容后，用清晰易读的方式呈现
- 遇到权限不足或功能不支持，如实告知
- 所有操作等同于用户本人在钉钉上亲自执行"""


def run_agent(user_message: str, history: list[dict] | None = None, max_rounds: int = 5) -> str:
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        *(history or []),
        {"role": "user", "content": user_message},
    ]

    for _ in range(max_rounds):
        response = chat(messages, tools=TOOLS)
        choice = response["choices"][0]
        msg = choice["message"]

        if choice.get("finish_reason") == "tool_calls" and msg.get("tool_calls"):
            messages.append(msg)
            for tc in msg["tool_calls"]:
                result = execute_tool(tc["function"]["name"], tc["function"]["arguments"])
                messages.append({
                    "role": "tool",
                    "tool_call_id": tc["id"],
                    "content": result,
                })
            continue

        return msg.get("content") or "（无回复内容）"

    return "处理超时，请稍后重试。"
