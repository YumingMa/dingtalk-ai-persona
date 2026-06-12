"""dws 工具定义 + 执行，直接用本机 dws（用户自己的钉钉身份）。"""

import json
import tempfile
import os
from dws_runner import run_dws

TOOLS = [
    {"type": "function", "function": {
        "name": "doc_read",
        "description": "读取钉钉云文档内容，返回 Markdown 正文。",
        "parameters": {"type": "object", "properties": {
            "node": {"type": "string", "description": "文档 URL 或 nodeId"},
        }, "required": ["node"]},
    }},
    {"type": "function", "function": {
        "name": "doc_search",
        "description": "按关键词搜索钉钉文档。",
        "parameters": {"type": "object", "properties": {
            "keyword": {"type": "string", "description": "搜索关键词"},
        }, "required": ["keyword"]},
    }},
    {"type": "function", "function": {
        "name": "doc_create",
        "description": "在知识库中创建新文档。",
        "parameters": {"type": "object", "properties": {
            "name":      {"type": "string", "description": "文档标题"},
            "content":   {"type": "string", "description": "Markdown 正文"},
            "workspace": {"type": "string", "description": "知识库 workspaceId 或 URL"},
        }, "required": ["name", "content", "workspace"]},
    }},
    {"type": "function", "function": {
        "name": "chat_send_message",
        "description": "以用户身份发钉钉消息。user_id 单聊，group_id 群聊，二选一。",
        "parameters": {"type": "object", "properties": {
            "text":     {"type": "string", "description": "消息内容（支持 Markdown）"},
            "title":    {"type": "string", "description": "消息标题"},
            "user_id":  {"type": "string", "description": "接收人 userId（单聊）"},
            "group_id": {"type": "string", "description": "群 openConversationId（群聊）"},
        }, "required": ["text"]},
    }},
    {"type": "function", "function": {
        "name": "chat_search_group",
        "description": "按关键词搜索钉钉群聊。",
        "parameters": {"type": "object", "properties": {
            "keyword": {"type": "string", "description": "群名关键词"},
        }, "required": ["keyword"]},
    }},
    {"type": "function", "function": {
        "name": "search_person",
        "description": "按姓名搜索企业通讯录人员，返回 userId 等信息。",
        "parameters": {"type": "object", "properties": {
            "name": {"type": "string", "description": "姓名关键词"},
        }, "required": ["name"]},
    }},
    {"type": "function", "function": {
        "name": "report_list_inbox",
        "description": "获取收件箱日志/周报列表。",
        "parameters": {"type": "object", "properties": {
            "start": {"type": "string", "description": "开始时间 ISO-8601，如 2026-06-01T00:00:00+08:00"},
            "end":   {"type": "string", "description": "结束时间 ISO-8601"},
            "size":  {"type": "integer", "description": "每页条数，最大 20"},
        }, "required": ["start", "end"]},
    }},
    {"type": "function", "function": {
        "name": "report_get",
        "description": "读取一份日志/周报的详细内容。",
        "parameters": {"type": "object", "properties": {
            "report_id": {"type": "string", "description": "日志 ID"},
        }, "required": ["report_id"]},
    }},
    {"type": "function", "function": {
        "name": "todo_list",
        "description": "查询我的待办事项。",
        "parameters": {"type": "object", "properties": {
            "done": {"type": "boolean", "description": "true=已完成，false=未完成（默认）"},
        }},
    }},
    {"type": "function", "function": {
        "name": "calendar_list_events",
        "description": "查询我的日历日程。",
        "parameters": {"type": "object", "properties": {
            "start_time": {"type": "string", "description": "开始时间 ISO-8601"},
            "end_time":   {"type": "string", "description": "结束时间 ISO-8601"},
        }},
    }},
    {"type": "function", "function": {
        "name": "wiki_list_spaces",
        "description": "列出我有权访问的知识库空间。",
        "parameters": {"type": "object", "properties": {}},
    }},
]


def execute_tool(name: str, arguments: str | dict) -> str:
    args = json.loads(arguments) if isinstance(arguments, str) else arguments

    match name:
        case "doc_read":
            result = run_dws(["doc", "read", "--node", args["node"]])

        case "doc_search":
            result = run_dws(["doc", "search", "--keyword", args["keyword"]])

        case "doc_create":
            with tempfile.NamedTemporaryFile(mode="w", suffix=".md", delete=False) as f:
                f.write(args["content"])
                tmp = f.name
            try:
                result = run_dws(["doc", "create",
                    "--name", args["name"],
                    "--content-file", tmp,
                    "--content-format", "markdown",
                    "--workspace", args["workspace"]])
            finally:
                os.unlink(tmp)

        case "chat_send_message":
            cmd = ["chat", "message", "send",
                   "--title", args.get("title", args["text"][:30]),
                   "--text",  args["text"]]
            if args.get("group_id"):
                cmd += ["--group", args["group_id"]]
            elif args.get("user_id"):
                cmd += ["--user", args["user_id"]]
            result = run_dws(cmd)

        case "chat_search_group":
            result = run_dws(["chat", "search", "--keyword", args["keyword"]])

        case "search_person":
            result = run_dws(["aisearch", "person", "--query", args["name"]])

        case "report_list_inbox":
            result = run_dws(["report", "inbox", "list",
                "--start", args["start"], "--end", args["end"],
                "--size", str(args.get("size", 20))])

        case "report_get":
            result = run_dws(["report", "entry", "get",
                "--report-id", args["report_id"]])

        case "todo_list":
            result = run_dws(["todo", "task", "list",
                "--status", str(args.get("done", False)).lower()])

        case "calendar_list_events":
            cmd = ["calendar", "event", "list"]
            if args.get("start_time"):
                cmd += ["--start-time", args["start_time"]]
            if args.get("end_time"):
                cmd += ["--end-time", args["end_time"]]
            result = run_dws(cmd)

        case "wiki_list_spaces":
            result = run_dws(["wiki", "space", "list"])

        case _:
            result = {"error": f"未知工具: {name}"}

    return json.dumps(result, ensure_ascii=False)
