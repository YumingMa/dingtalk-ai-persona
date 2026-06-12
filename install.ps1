# ==============================================================
# 公司 AI 分身 · Windows 一键安装配置脚本
# 用法：irm https://your-company.com/setup.ps1 | iex
# ==============================================================

# ── 管理员配置区 ───────────────────────────────────────────────
$HAI_GATEWAY_URL   = "https://your-lightchat-server.example"   # HAI Gateway 地址
$INSTALL_DIR       = "$env:USERPROFILE\ai-persona"              # 安装目录
$PYTHON_MIN_VER    = "3.10"
# ────────────────────────────────────────────────────────────────

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"

# ── 工具函数 ──────────────────────────────────────────────────
function Write-Step($n, $text) {
    Write-Host ""
    Write-Host "  [$n] $text" -ForegroundColor Cyan
    Write-Host "  $('─' * 50)" -ForegroundColor DarkGray
}
function Write-Ok($t)   { Write-Host "  ✅ $t" -ForegroundColor Green }
function Write-Info($t) { Write-Host "  →  $t" -ForegroundColor Gray }
function Write-Warn($t) { Write-Host "  ⚠  $t" -ForegroundColor Yellow }
function Write-Err($t)  { Write-Host "  ❌ $t" -ForegroundColor Red; exit 1 }
function Pause-Key($t = "按任意键继续...") {
    Write-Host "  $t" -ForegroundColor DarkGray -NoNewline
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
}
function Read-Input($prompt, $default = "") {
    Write-Host "  $prompt" -ForegroundColor White -NoNewline
    if ($default) { Write-Host " [$default]" -ForegroundColor DarkGray -NoNewline }
    Write-Host ": " -NoNewline
    $val = Read-Host
    if ([string]::IsNullOrWhiteSpace($val) -and $default) { return $default }
    return $val
}
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# ── 欢迎界面 ─────────────────────────────────────────────────
Clear-Host
Write-Host ""
Write-Host "  ╔════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║       公司 AI 分身  ·  一键安装配置         ║" -ForegroundColor Cyan
Write-Host "  ║   安装完成后，在钉钉和你的 AI 分身直接说话  ║" -ForegroundColor DarkCyan
Write-Host "  ╚════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Pause-Key "按任意键开始（约 5 分钟）..."

# ════════════════════════════════════════════════════
# Step 1: Python
# ════════════════════════════════════════════════════
Write-Step 1 "检查 / 安装 Python"

$py = Get-Command python -ErrorAction SilentlyContinue
if ($py) {
    $ver = (python --version 2>&1) -replace "Python ",""
    Write-Ok "Python $ver 已安装"
} else {
    Write-Info "未检测到 Python，正在通过 winget 安装..."
    try {
        winget install -e --id Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements
        Refresh-Path
        Write-Ok "Python 安装完成"
    } catch {
        Write-Warn "winget 安装失败，请手动安装 Python 3.10+："
        Write-Host "  https://www.python.org/downloads/" -ForegroundColor Yellow
        Pause-Key "安装完成后按任意键继续..."
        Refresh-Path
    }
}

# ════════════════════════════════════════════════════
# Step 2: dws
# ════════════════════════════════════════════════════
Write-Step 2 "安装 dws 钉钉命令行工具"

if (Get-Command dws -ErrorAction SilentlyContinue) {
    $v = (& dws version 2>$null | Select-String "Version").ToString().Trim()
    Write-Ok "dws 已安装  $v"
} else {
    Write-Info "下载安装 dws..."
    irm https://raw.githubusercontent.com/DingTalk-Real-AI/dingtalk-workspace-cli/main/scripts/install.ps1 | iex
    Refresh-Path
    Write-Ok "dws 安装完成"
}

# ════════════════════════════════════════════════════
# Step 3: 创建项目目录 + 写入 Python 文件
# ════════════════════════════════════════════════════
Write-Step 3 "创建 AI 分身项目目录"

New-Item -ItemType Directory -Force $INSTALL_DIR | Out-Null
Write-Ok "目录：$INSTALL_DIR"

# ── requirements.txt ──
@"
dingtalk-stream>=0.24.0
anthropic>=0.100.0
pydantic-settings>=2.7.0
python-dotenv>=1.0.0
"@ | Set-Content "$INSTALL_DIR\requirements.txt" -Encoding UTF8

# ── config.py ──
@'
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DINGTALK_APP_KEY: str = ""
    DINGTALK_APP_SECRET: str = ""
    ANTHROPIC_API_KEY: str = ""
    ANTHROPIC_BASE_URL: str = ""
    ANTHROPIC_DEFAULT_SONNET_MODEL: str = "claude-sonnet-4-6"
    class Config:
        env_file = ".env"
        extra = "ignore"

settings = Settings()
'@ | Set-Content "$INSTALL_DIR\config.py" -Encoding UTF8

# ── dws_runner.py ──
@'
import json, subprocess

def run_dws(args: list, timeout: int = 30) -> dict:
    result = subprocess.run(
        ["dws"] + args + ["-f", "json", "-y"],
        capture_output=True, text=True, timeout=timeout,
    )
    try:
        return json.loads((result.stdout or result.stderr).strip())
    except:
        return {"raw": result.stdout.strip(), "error": result.returncode != 0}
'@ | Set-Content "$INSTALL_DIR\dws_runner.py" -Encoding UTF8

# ── session.py ──
@'
import time
from collections import deque
import asyncio

class MsgDedup:
    def __init__(self, ttl=60):
        self._seen: dict[str, float] = {}
        self._ttl = ttl
    def is_duplicate(self, msg_id: str) -> bool:
        now = time.time()
        self._seen = {k: v for k, v in self._seen.items() if now - v < self._ttl}
        if msg_id in self._seen: return True
        self._seen[msg_id] = now
        return False

class ConvQueue:
    def __init__(self): self._locks: dict[str, asyncio.Lock] = {}
    def get_lock(self, conv_id: str) -> asyncio.Lock:
        if conv_id not in self._locks: self._locks[conv_id] = asyncio.Lock()
        return self._locks[conv_id]

class ConvHistory:
    MAX = 20
    def __init__(self): self._h: dict[str, deque] = {}
    def get(self, uid: str) -> list:
        return list(self._h.get(uid, deque()))
    def append(self, uid: str, role: str, content: str):
        if uid not in self._h: self._h[uid] = deque(maxlen=self.MAX)
        self._h[uid].append({"role": role, "content": content})
    def clear(self, uid: str): self._h.pop(uid, None)

dedup = MsgDedup()
conv_queue = ConvQueue()
conv_history = ConvHistory()
'@ | Set-Content "$INSTALL_DIR\session.py" -Encoding UTF8

# ── lightchat.py ──
@'
import json
import anthropic
from config import settings

_client = anthropic.Anthropic(
    api_key=settings.ANTHROPIC_API_KEY or None,
    base_url=settings.ANTHROPIC_BASE_URL or None,
)
_MODEL = settings.ANTHROPIC_DEFAULT_SONNET_MODEL

def chat(messages: list, tools: list | None = None) -> dict:
    system = ""
    msgs = []
    for m in messages:
        if m["role"] == "system": system = m["content"]; continue
        if m["role"] == "tool":
            block = {"type":"tool_result","tool_use_id":m["tool_call_id"],"content":m.get("content","")}
            if msgs and msgs[-1]["role"] == "user" and isinstance(msgs[-1]["content"], list):
                msgs[-1]["content"].append(block)
            else:
                msgs.append({"role":"user","content":[block]})
            continue
        if m["role"] == "assistant":
            blocks = []
            if m.get("content"): blocks.append({"type":"text","text":m["content"]})
            for tc in m.get("tool_calls") or []:
                fn = tc["function"]
                try: inp = json.loads(fn["arguments"])
                except: inp = {}
                blocks.append({"type":"tool_use","id":tc["id"],"name":fn["name"],"input":inp})
            msgs.append({"role":"assistant","content":blocks or m.get("content","")})
            continue
        msgs.append({"role":m["role"],"content":m.get("content","")})

    kw = dict(model=_MODEL, max_tokens=4096, messages=msgs)
    if system: kw["system"] = system
    if tools:
        kw["tools"] = [{"name":t["function"]["name"],"description":t["function"].get("description",""),"input_schema":t["function"].get("parameters",{"type":"object","properties":{}})} for t in tools]

    resp = _client.messages.create(**kw)
    tool_calls, text = [], ""
    for b in resp.content:
        if b.type == "tool_use":
            tool_calls.append({"id":b.id,"type":"function","function":{"name":b.name,"arguments":json.dumps(b.input,ensure_ascii=False)}})
        elif b.type == "text":
            text += b.text
    msg = {"role":"assistant","content":text}
    if tool_calls: msg["tool_calls"] = tool_calls
    return {"choices":[{"finish_reason":"tool_calls" if tool_calls else "stop","message":msg}]}
'@ | Set-Content "$INSTALL_DIR\lightchat.py" -Encoding UTF8

# ── dws_tools.py ──
@'
import json, tempfile, os
from dws_runner import run_dws

TOOLS = [
    {"type":"function","function":{"name":"doc_read","description":"读取钉钉文档内容","parameters":{"type":"object","properties":{"node":{"type":"string","description":"文档 URL 或 nodeId"}},"required":["node"]}}},
    {"type":"function","function":{"name":"doc_search","description":"按关键词搜索文档","parameters":{"type":"object","properties":{"keyword":{"type":"string"}},"required":["keyword"]}}},
    {"type":"function","function":{"name":"doc_create","description":"在知识库创建新文档","parameters":{"type":"object","properties":{"name":{"type":"string"},"content":{"type":"string","description":"Markdown 正文"},"workspace":{"type":"string","description":"知识库 workspaceId 或 URL"}},"required":["name","content","workspace"]}}},
    {"type":"function","function":{"name":"chat_send_message","description":"以用户身份发钉钉消息，user_id 单聊，group_id 群聊","parameters":{"type":"object","properties":{"text":{"type":"string"},"title":{"type":"string"},"user_id":{"type":"string"},"group_id":{"type":"string"}},"required":["text"]}}},
    {"type":"function","function":{"name":"chat_search_group","description":"搜索钉钉群聊","parameters":{"type":"object","properties":{"keyword":{"type":"string"}},"required":["keyword"]}}},
    {"type":"function","function":{"name":"search_person","description":"搜索企业通讯录人员","parameters":{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}}},
    {"type":"function","function":{"name":"report_list_inbox","description":"获取收件箱日志周报列表","parameters":{"type":"object","properties":{"start":{"type":"string"},"end":{"type":"string"},"size":{"type":"integer"}},"required":["start","end"]}}},
    {"type":"function","function":{"name":"report_get","description":"读取日志周报详情","parameters":{"type":"object","properties":{"report_id":{"type":"string"}},"required":["report_id"]}}},
    {"type":"function","function":{"name":"todo_list","description":"查询我的待办","parameters":{"type":"object","properties":{"done":{"type":"boolean"}}}}},
    {"type":"function","function":{"name":"calendar_list_events","description":"查询我的日程","parameters":{"type":"object","properties":{"start_time":{"type":"string"},"end_time":{"type":"string"}}}}},
    {"type":"function","function":{"name":"wiki_list_spaces","description":"列出我的知识库空间","parameters":{"type":"object","properties":{}}}},
]

def execute_tool(name: str, arguments) -> str:
    args = json.loads(arguments) if isinstance(arguments, str) else arguments
    match name:
        case "doc_read":       r = run_dws(["doc","read","--node",args["node"]])
        case "doc_search":     r = run_dws(["doc","search","--keyword",args["keyword"]])
        case "doc_create":
            with tempfile.NamedTemporaryFile(mode="w",suffix=".md",delete=False) as f:
                f.write(args["content"]); tmp=f.name
            try: r = run_dws(["doc","create","--name",args["name"],"--content-file",tmp,"--content-format","markdown","--workspace",args["workspace"]])
            finally: os.unlink(tmp)
        case "chat_send_message":
            cmd = ["chat","message","send","--title",args.get("title",args["text"][:30]),"--text",args["text"]]
            if args.get("group_id"): cmd += ["--group",args["group_id"]]
            elif args.get("user_id"): cmd += ["--user",args["user_id"]]
            r = run_dws(cmd)
        case "chat_search_group": r = run_dws(["chat","search","--keyword",args["keyword"]])
        case "search_person":     r = run_dws(["aisearch","person","--query",args["name"]])
        case "report_list_inbox": r = run_dws(["report","inbox","list","--start",args["start"],"--end",args["end"],"--size",str(args.get("size",20))])
        case "report_get":        r = run_dws(["report","entry","get","--report-id",args["report_id"]])
        case "todo_list":         r = run_dws(["todo","task","list","--status",str(args.get("done",False)).lower()])
        case "calendar_list_events":
            cmd = ["calendar","event","list"]
            if args.get("start_time"): cmd += ["--start-time",args["start_time"]]
            if args.get("end_time"): cmd += ["--end-time",args["end_time"]]
            r = run_dws(cmd)
        case "wiki_list_spaces":  r = run_dws(["wiki","space","list"])
        case _:                   r = {"error":f"未知工具:{name}"}
    return json.dumps(r, ensure_ascii=False)
'@ | Set-Content "$INSTALL_DIR\dws_tools.py" -Encoding UTF8

# ── agent.py ──
@'
from dws_tools import TOOLS, execute_tool
from lightchat import chat

SYSTEM_PROMPT = """你是用户在钉钉上的 AI 分身，能以用户自己的身份操作钉钉：读文档、发消息、看周报、管待办、查日程等。
原则：理解意图选工具执行；发消息前告知用户内容；遇到权限不足如实告知；所有操作等同用户本人执行。"""

def run_agent(user_message: str, history: list | None = None, max_rounds: int = 5) -> str:
    messages = [{"role":"system","content":SYSTEM_PROMPT}, *(history or []), {"role":"user","content":user_message}]
    for _ in range(max_rounds):
        resp = chat(messages, tools=TOOLS)
        choice = resp["choices"][0]; msg = choice["message"]
        if choice.get("finish_reason") == "tool_calls" and msg.get("tool_calls"):
            messages.append(msg)
            for tc in msg["tool_calls"]:
                messages.append({"role":"tool","tool_call_id":tc["id"],"content":execute_tool(tc["function"]["name"],tc["function"]["arguments"])})
            continue
        return msg.get("content") or "（无回复内容）"
    return "处理超时，请稍后重试。"
'@ | Set-Content "$INSTALL_DIR\agent.py" -Encoding UTF8

# ── bot.py ──
@'
import asyncio, logging, threading
import dingtalk_stream
from dingtalk_stream import AckMessage
from agent import run_agent
from session import conv_history, conv_queue, dedup

logger = logging.getLogger(__name__)
HELP = """我是你的 AI 分身，能以你的身份操作钉钉：
📄 帮我读一下这篇文档：[链接]
💬 帮我告诉张三：明天会议取消
📊 总结本周团队周报
✅ 查一下我有哪些未完成待办
📅 我今天有什么安排
发 /clear 清除对话记忆。"""

class PersonaBotHandler(dingtalk_stream.ChatbotHandler):
    def process(self, callback):
        msg = dingtalk_stream.ChatbotMessage.from_dict(callback.data)
        msg_id = getattr(msg,"message_id","") or getattr(msg,"msgId","")
        if msg_id and dedup.is_duplicate(msg_id): return AckMessage.STATUS_OK,"ok"
        threading.Thread(target=lambda: asyncio.run(self._run(msg)), daemon=True).start()
        return AckMessage.STATUS_OK, "ok"

    async def _run(self, msg):
        uid = msg.sender_staff_id or "user"
        cid = getattr(msg,"conversation_id",None) or uid
        text = (msg.text.content or "").strip()
        if msg.at_users:
            for at in msg.at_users:
                for k in ("dingtalkId","staffId","robotCode"):
                    v = at.get(k,"")
                    if v: text = text.replace(f"@{v}","").strip()
        async with conv_queue.get_lock(cid):
            if text == "/help": self.reply_text(HELP, incoming_message=msg); return
            if text == "/clear": conv_history.clear(uid); self.reply_text("✅ 对话记忆已清除。", incoming_message=msg); return
            if not text: return
            self.reply_text("⏳ 思考中...", incoming_message=msg)
            try:
                reply = run_agent(text, history=conv_history.get(uid))
                conv_history.append(uid,"user",text)
                conv_history.append(uid,"assistant",reply)
            except Exception as e:
                logger.exception("agent error"); reply = f"出错了：{e}"
            self.reply_text(reply, incoming_message=msg)
'@ | Set-Content "$INSTALL_DIR\bot.py" -Encoding UTF8

# ── main.py ──
@'
import logging
import dingtalk_stream
from bot import PersonaBotHandler
from config import settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

def main():
    print(f"\n  🤖 AI 分身启动中...\n  钉钉 AppKey: {settings.DINGTALK_APP_KEY[:8]}...\n")
    cred = dingtalk_stream.Credential(settings.DINGTALK_APP_KEY, settings.DINGTALK_APP_SECRET)
    client = dingtalk_stream.DingTalkStreamClient(cred)
    client.register_callback_handler(dingtalk_stream.ChatbotMessage.TOPIC, PersonaBotHandler())
    print("  ✅ AI 分身已上线，在钉钉和它说话吧！\n")
    client.start_forever()

if __name__ == "__main__":
    main()
'@ | Set-Content "$INSTALL_DIR\main.py" -Encoding UTF8

Write-Ok "Python 文件写入完成"

# ════════════════════════════════════════════════════
# Step 4: 安装 Python 依赖
# ════════════════════════════════════════════════════
Write-Step 4 "安装 Python 依赖"
Write-Info "pip install..."
Set-Location $INSTALL_DIR
python -m pip install -r requirements.txt -q
Write-Ok "依赖安装完成"

# ════════════════════════════════════════════════════
# Step 5: 钉钉登录
# ════════════════════════════════════════════════════
Write-Step 5 "钉钉登录授权"

$status = & dws auth status 2>$null | ConvertFrom-Json -ErrorAction SilentlyContinue
if ($status -and $status.authenticated) {
    Write-Ok "已登录钉钉，跳过"
} else {
    Write-Host ""
    Write-Host "  即将打开浏览器完成钉钉扫码授权。" -ForegroundColor White
    Pause-Key "按任意键打开..."
    & dws auth login --device
    Write-Ok "钉钉登录成功"
}

# ════════════════════════════════════════════════════
# Step 6: 创建 AI 分身机器人
# ════════════════════════════════════════════════════
Write-Step 6 "创建你的 AI 分身机器人"
Write-Host ""
Write-Host "  正在钉钉开放平台为你创建专属 AI 分身..." -ForegroundColor White

$robotJson = & dws devapp robot create `
    --app-name "我的AI分身" `
    --robot-name "AI分身" `
    --desc "我的钉钉AI助手" `
    --yes --format json 2>$null

try {
    $robot = $robotJson | ConvertFrom-Json
    $APP_KEY    = $robot.clientId    -or $robot.appKey    -or $robot.result.clientId
    $APP_SECRET = $robot.clientSecret -or $robot.appSecret -or $robot.result.clientSecret
    if (-not $APP_KEY) { throw "未获取到 AppKey" }
    Write-Ok "AI 分身机器人创建成功"
    Write-Host "  AppKey: $APP_KEY" -ForegroundColor DarkGray
} catch {
    Write-Warn "自动创建失败（可能需要开发者权限），请手动填写"
    Write-Host ""
    Write-Host "  如果提示「没有开发者身份」，请联系管理员在钉钉开放平台" -ForegroundColor Yellow
    Write-Host "  为你的账号添加开发者权限，然后重新运行此脚本。" -ForegroundColor Yellow
    Write-Host ""
    $APP_KEY    = Read-Input "请输入 AppKey（clientId）"
    $APP_SECRET = Read-Input "请输入 AppSecret（clientSecret）"
}

# ════════════════════════════════════════════════════
# Step 7: 配置 HAI Gateway Token
# ════════════════════════════════════════════════════
Write-Step 7 "配置 HAI Gateway"
Write-Host ""
Write-Host "  请输入你的 HAI Gateway Token（向管理员申请）" -ForegroundColor White
$HAI_TOKEN = Read-Input "HAI Gateway Token"

# ════════════════════════════════════════════════════
# Step 8: 写入 .env
# ════════════════════════════════════════════════════
Write-Step 8 "生成配置文件"

@"
DINGTALK_APP_KEY=$APP_KEY
DINGTALK_APP_SECRET=$APP_SECRET
ANTHROPIC_API_KEY=$HAI_TOKEN
ANTHROPIC_BASE_URL=$HAI_GATEWAY_URL
ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-6
"@ | Set-Content "$INSTALL_DIR\.env" -Encoding UTF8

Write-Ok ".env 配置完成"

# ════════════════════════════════════════════════════
# Step 9: 创建快捷方式 + 启动
# ════════════════════════════════════════════════════
Write-Step 9 "创建桌面快捷方式"

$batContent = "@echo off`r`ncd /d `"$INSTALL_DIR`"`r`npython main.py`r`npause"
$batPath = "$INSTALL_DIR\启动AI分身.bat"
$batContent | Set-Content $batPath -Encoding ASCII

# 创建桌面快捷方式
$desktop = [System.Environment]::GetFolderPath("Desktop")
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\AI分身.lnk")
$shortcut.TargetPath  = $batPath
$shortcut.IconLocation = "shell32.dll,13"
$shortcut.Description = "启动我的钉钉 AI 分身"
$shortcut.Save()

Write-Ok "桌面快捷方式已创建"

# ── 完成 ─────────────────────────────────────────────
Write-Host ""
Write-Host "  ╔════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║         🎉  安装配置完成！                 ║" -ForegroundColor Green
Write-Host "  ╚════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  以后启动：双击桌面的「AI分身」图标" -ForegroundColor White
Write-Host ""
Write-Host "  现在先试一下 —— 正在启动 AI 分身..." -ForegroundColor Cyan
Write-Host ""
Pause-Key "按任意键启动..."

Set-Location $INSTALL_DIR
python main.py
