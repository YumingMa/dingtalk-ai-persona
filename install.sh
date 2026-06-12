#!/usr/bin/env bash
# ==============================================================
# 公司 AI 分身 · macOS / Linux 一键安装配置脚本
# 用法：curl -fsSL https://your-company.com/setup.sh | bash
# ==============================================================
set -e

# ── 管理员配置区（部署前修改）────────────────────────────────
HAI_GATEWAY_URL="${HAI_GATEWAY_URL:-https://your-lightchat-server.example}"
HAI_GATEWAY_MODEL="${HAI_GATEWAY_MODEL:-claude-sonnet-4-6}"
INSTALL_DIR="${INSTALL_DIR:-$HOME/ai-persona}"
# ────────────────────────────────────────────────────────────────

# ── 颜色 & 工具函数 ──────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()  { echo -e "${CYAN}  →  $*${RESET}"; }
ok()    { echo -e "${GREEN}  ✅ $*${RESET}"; }
warn()  { echo -e "${YELLOW}  ⚠  $*${RESET}"; }
err()   { echo -e "${RED}  ❌ $*${RESET}"; }
title() { echo -e "\n${BOLD}  [$1] $2${RESET}\n  $(printf '%.0s─' {1..50})"; }
pause() { echo -e "\n${CYAN}  ${1:-按 Enter 继续...}${RESET}" && read -r _; }

ask() {
    # ask "提示" "默认值" → 返回用户输入（空则用默认值）
    local prompt="$1" default="$2" val
    if [ -n "$default" ]; then
        echo -ne "${BOLD}  $prompt${RESET} [${CYAN}$default${RESET}]: "
    else
        echo -ne "${BOLD}  $prompt${RESET}: "
    fi
    read -r val
    echo "${val:-$default}"
}

ask_secret() {
    local prompt="$1" val
    echo -ne "${BOLD}  $prompt${RESET}: "
    read -rs val; echo
    echo "$val"
}

is_macos() { [[ "$OSTYPE" == "darwin"* ]]; }
is_headless() { [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && ! is_macos; }
has_cmd() { command -v "$1" &>/dev/null; }

# ── 欢迎 ─────────────────────────────────────────────────────
clear
echo -e "${CYAN}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║       公司 AI 分身  ·  一键安装配置           ║"
echo "  ║   安装完成后直接在钉钉和 AI 分身对话即可       ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
echo "  系统：$(uname -s) $(uname -m)"
echo "  目录：$INSTALL_DIR"
pause "按 Enter 开始安装（约 5 分钟）..."

# ════════════════════════════════════════════════════════════
# Step 1: Python 3.10+
# ════════════════════════════════════════════════════════════
title 1 "检查 / 安装 Python 3.10+"

install_python() {
    warn "未检测到 Python 3.10+，尝试自动安装..."

    if is_macos; then
        if has_cmd brew; then
            info "使用 Homebrew 安装..."
            brew install python@3.12 && ok "Python 安装完成" && return
        fi
        warn "Homebrew 未安装。"
        echo -e "\n  ${YELLOW}请手动安装 Python（二选一）：${RESET}"
        echo "  ① 官网下载（推荐）：https://www.python.org/downloads/"
        echo "  ② 安装 Homebrew 后自动装：https://brew.sh"
        pause "安装完成后按 Enter 继续..."
    else
        # Linux
        if has_cmd apt-get; then
            info "使用 apt 安装..."
            sudo apt-get update -q && sudo apt-get install -y python3 python3-pip python3-venv \
                && ok "Python 安装完成" && return
        elif has_cmd dnf; then
            info "使用 dnf 安装..."
            sudo dnf install -y python3 python3-pip && ok "Python 安装完成" && return
        elif has_cmd yum; then
            info "使用 yum 安装..."
            sudo yum install -y python3 python3-pip && ok "Python 安装完成" && return
        elif has_cmd pacman; then
            info "使用 pacman 安装..."
            sudo pacman -S --noconfirm python python-pip && ok "Python 安装完成" && return
        fi
        warn "无法自动安装，请手动安装 Python 3.10+："
        echo "  官网下载：https://www.python.org/downloads/"
        echo "  Ubuntu/Debian：sudo apt install python3 python3-pip"
        echo "  CentOS/RHEL：  sudo yum install python3 python3-pip"
        echo "  Arch Linux：   sudo pacman -S python python-pip"
        pause "安装完成后按 Enter 继续..."
    fi
}

PYTHON=""
for cmd in python3 python; do
    if has_cmd "$cmd"; then
        ver=$("$cmd" --version 2>&1 | grep -oP '\d+\.\d+' | head -1)
        major=$(echo "$ver" | cut -d. -f1)
        minor=$(echo "$ver" | cut -d. -f2)
        if [ "$major" -ge 3 ] && [ "$minor" -ge 10 ]; then
            PYTHON="$cmd"
            ok "Python $("$cmd" --version 2>&1) 已安装"
            break
        fi
    fi
done

[ -z "$PYTHON" ] && install_python
[ -z "$PYTHON" ] && for cmd in python3 python; do has_cmd "$cmd" && PYTHON="$cmd" && break; done
[ -z "$PYTHON" ] && { err "仍未找到 Python，请手动安装后重新运行此脚本"; exit 1; }

# ════════════════════════════════════════════════════════════
# Step 2: dws
# ════════════════════════════════════════════════════════════
title 2 "安装 dws 钉钉命令行工具"

if has_cmd dws; then
    ver=$(dws version 2>/dev/null | grep Version | awk '{print $2}')
    ok "dws $ver 已安装"
else
    info "正在安装 dws..."
    if curl -fsSL https://raw.githubusercontent.com/DingTalk-Real-AI/dingtalk-workspace-cli/main/scripts/install.sh | sh; then
        export PATH="$HOME/.local/bin:$PATH"
        ok "dws 安装完成"
    else
        warn "自动安装失败，请手动安装："
        echo
        echo "  macOS / Linux（curl）："
        echo "  ${CYAN}curl -fsSL https://raw.githubusercontent.com/DingTalk-Real-AI/dingtalk-workspace-cli/main/scripts/install.sh | sh${RESET}"
        echo
        echo "  npm（需要 Node.js）："
        echo "  ${CYAN}npm install -g dingtalk-workspace-cli${RESET}"
        echo
        echo "  手动下载二进制："
        echo "  https://github.com/DingTalk-Real-AI/dingtalk-workspace-cli/releases"
        echo
        pause "安装完成后按 Enter 继续..."
        export PATH="$HOME/.local/bin:$PATH"
        has_cmd dws || { err "仍未找到 dws 命令，请确认安装后重新运行"; exit 1; }
    fi
fi

# ════════════════════════════════════════════════════════════
# Step 3: 创建项目目录 + 写入 Python 文件
# ════════════════════════════════════════════════════════════
title 3 "创建 AI 分身项目"

mkdir -p "$INSTALL_DIR"
ok "目录：$INSTALL_DIR"

# requirements.txt
cat > "$INSTALL_DIR/requirements.txt" << 'EOF'
dingtalk-stream>=0.24.0
anthropic>=0.100.0
pydantic-settings>=2.7.0
python-dotenv>=1.0.0
EOF

# config.py
cat > "$INSTALL_DIR/config.py" << 'EOF'
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
EOF

# dws_runner.py
cat > "$INSTALL_DIR/dws_runner.py" << 'EOF'
import json, subprocess

def run_dws(args: list, timeout: int = 30) -> dict:
    result = subprocess.run(
        ["dws"] + args + ["-f", "json", "-y"],
        capture_output=True, text=True, timeout=timeout,
    )
    try:
        return json.loads((result.stdout or result.stderr).strip())
    except Exception:
        return {"raw": result.stdout.strip(), "error": result.returncode != 0}
EOF

# session.py
cat > "$INSTALL_DIR/session.py" << 'EOF'
import time, asyncio
from collections import deque

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
    def get_lock(self, cid: str):
        if cid not in self._locks: self._locks[cid] = asyncio.Lock()
        return self._locks[cid]

class ConvHistory:
    MAX = 20
    def __init__(self): self._h: dict[str, deque] = {}
    def get(self, uid): return list(self._h.get(uid, deque()))
    def append(self, uid, role, content):
        if uid not in self._h: self._h[uid] = deque(maxlen=self.MAX)
        self._h[uid].append({"role": role, "content": content})
    def clear(self, uid): self._h.pop(uid, None)

dedup = MsgDedup()
conv_queue = ConvQueue()
conv_history = ConvHistory()
EOF

# lightchat.py
cat > "$INSTALL_DIR/lightchat.py" << 'EOF'
import json
import anthropic
from config import settings

_client = anthropic.Anthropic(
    api_key=settings.ANTHROPIC_API_KEY or None,
    base_url=settings.ANTHROPIC_BASE_URL or None,
)
_MODEL = settings.ANTHROPIC_DEFAULT_SONNET_MODEL

def chat(messages: list, tools: list | None = None) -> dict:
    system, msgs = "", []
    for m in messages:
        if m["role"] == "system":
            system = m["content"]; continue
        if m["role"] == "tool":
            blk = {"type": "tool_result", "tool_use_id": m["tool_call_id"], "content": m.get("content", "")}
            if msgs and msgs[-1]["role"] == "user" and isinstance(msgs[-1]["content"], list):
                msgs[-1]["content"].append(blk)
            else:
                msgs.append({"role": "user", "content": [blk]})
            continue
        if m["role"] == "assistant":
            blocks = []
            if m.get("content"): blocks.append({"type": "text", "text": m["content"]})
            for tc in m.get("tool_calls") or []:
                fn = tc["function"]
                try: inp = json.loads(fn["arguments"])
                except: inp = {}
                blocks.append({"type": "tool_use", "id": tc["id"], "name": fn["name"], "input": inp})
            msgs.append({"role": "assistant", "content": blocks or m.get("content", "")})
            continue
        msgs.append({"role": m["role"], "content": m.get("content", "")})

    kw = dict(model=_MODEL, max_tokens=4096, messages=msgs)
    if system: kw["system"] = system
    if tools:
        kw["tools"] = [{"name": t["function"]["name"], "description": t["function"].get("description", ""),
                        "input_schema": t["function"].get("parameters", {"type": "object", "properties": {}})}
                       for t in tools]
    resp = _client.messages.create(**kw)
    tool_calls, text = [], ""
    for b in resp.content:
        if b.type == "tool_use":
            tool_calls.append({"id": b.id, "type": "function", "function": {"name": b.name, "arguments": json.dumps(b.input, ensure_ascii=False)}})
        elif b.type == "text":
            text += b.text
    msg = {"role": "assistant", "content": text}
    if tool_calls: msg["tool_calls"] = tool_calls
    return {"choices": [{"finish_reason": "tool_calls" if tool_calls else "stop", "message": msg}]}
EOF

# dws_tools.py
cat > "$INSTALL_DIR/dws_tools.py" << 'EOF'
import json, tempfile, os
from dws_runner import run_dws

TOOLS = [
    {"type":"function","function":{"name":"doc_read","description":"读取钉钉文档内容","parameters":{"type":"object","properties":{"node":{"type":"string","description":"文档 URL 或 nodeId"}},"required":["node"]}}},
    {"type":"function","function":{"name":"doc_search","description":"按关键词搜索文档","parameters":{"type":"object","properties":{"keyword":{"type":"string"}},"required":["keyword"]}}},
    {"type":"function","function":{"name":"doc_create","description":"在知识库创建新文档","parameters":{"type":"object","properties":{"name":{"type":"string"},"content":{"type":"string"},"workspace":{"type":"string","description":"知识库 workspaceId 或 URL"}},"required":["name","content","workspace"]}}},
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
        case "doc_read":      r = run_dws(["doc","read","--node",args["node"]])
        case "doc_search":    r = run_dws(["doc","search","--keyword",args["keyword"]])
        case "doc_create":
            with tempfile.NamedTemporaryFile(mode="w",suffix=".md",delete=False) as f:
                f.write(args["content"]); tmp=f.name
            try:    r = run_dws(["doc","create","--name",args["name"],"--content-file",tmp,"--content-format","markdown","--workspace",args["workspace"]])
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
            if args.get("end_time"):   cmd += ["--end-time",args["end_time"]]
            r = run_dws(cmd)
        case "wiki_list_spaces":  r = run_dws(["wiki","space","list"])
        case _:                   r = {"error": f"未知工具: {name}"}
    return json.dumps(r, ensure_ascii=False)
EOF

# agent.py
cat > "$INSTALL_DIR/agent.py" << 'EOF'
from dws_tools import TOOLS, execute_tool
from lightchat import chat

SYSTEM_PROMPT = """你是用户在钉钉上的 AI 分身，能以用户自己的身份操作钉钉：
读取/创建文档、发送消息、分析周报、管理待办、查询日程、搜索知识库等。
原则：理解意图选工具执行；发消息前告知用户内容；遇到权限不足如实告知。
所有操作等同于用户本人在钉钉上亲自执行。"""

def run_agent(user_message: str, history: list | None = None, max_rounds: int = 5) -> str:
    messages = [{"role":"system","content":SYSTEM_PROMPT}, *(history or []), {"role":"user","content":user_message}]
    for _ in range(max_rounds):
        resp = chat(messages, tools=TOOLS)
        choice = resp["choices"][0]; msg = choice["message"]
        if choice.get("finish_reason") == "tool_calls" and msg.get("tool_calls"):
            messages.append(msg)
            for tc in msg["tool_calls"]:
                messages.append({"role":"tool","tool_call_id":tc["id"],
                                  "content":execute_tool(tc["function"]["name"],tc["function"]["arguments"])})
            continue
        return msg.get("content") or "（无回复内容）"
    return "处理超时，请稍后重试。"
EOF

# bot.py
cat > "$INSTALL_DIR/bot.py" << 'EOF'
import asyncio, logging, threading
import dingtalk_stream
from dingtalk_stream import AckMessage
from agent import run_agent
from session import conv_history, conv_queue, dedup

logger = logging.getLogger(__name__)
HELP = """我是你的 AI 分身，能以你的身份操作钉钉：

📄 帮我读一下这篇文档：[链接]
✍️  帮我在知识库新建一篇文档...
💬 帮我告诉张三：明天会议取消
📊 总结本周团队周报
✅ 查一下我有哪些未完成待办
📅 我今天有什么安排

直接说需求，发 /clear 清除对话记忆。"""

class PersonaBotHandler(dingtalk_stream.ChatbotHandler):
    def process(self, callback):
        msg = dingtalk_stream.ChatbotMessage.from_dict(callback.data)
        mid = getattr(msg,"message_id","") or getattr(msg,"msgId","")
        if mid and dedup.is_duplicate(mid): return AckMessage.STATUS_OK,"ok"
        threading.Thread(target=lambda: asyncio.run(self._run(msg)), daemon=True).start()
        return AckMessage.STATUS_OK,"ok"

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
            if text == "/help":  self.reply_text(HELP, incoming_message=msg); return
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
EOF

# main.py
cat > "$INSTALL_DIR/main.py" << 'EOF'
import logging
import dingtalk_stream
from bot import PersonaBotHandler
from config import settings

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

def main():
    print(f"\n  🤖 AI 分身启动中...")
    print(f"  AppKey: {settings.DINGTALK_APP_KEY[:8]}...\n")
    cred = dingtalk_stream.Credential(settings.DINGTALK_APP_KEY, settings.DINGTALK_APP_SECRET)
    client = dingtalk_stream.DingTalkStreamClient(cred)
    client.register_callback_handler(dingtalk_stream.ChatbotMessage.TOPIC, PersonaBotHandler())
    print("  ✅ AI 分身已上线，在钉钉和它说话吧！\n")
    client.start_forever()

if __name__ == "__main__":
    main()
EOF

ok "Python 文件写入完成"

# ════════════════════════════════════════════════════════════
# Step 4: 安装 Python 依赖
# ════════════════════════════════════════════════════════════
title 4 "安装 Python 依赖"

cd "$INSTALL_DIR"

PIP=""
for cmd in pip3 pip; do
    has_cmd "$cmd" && PIP="$cmd" && break
done

if [ -z "$PIP" ]; then
    warn "未找到 pip，尝试安装..."
    $PYTHON -m ensurepip --upgrade 2>/dev/null || true
    $PYTHON -m pip --version &>/dev/null && PIP="$PYTHON -m pip"
fi

if [ -z "$PIP" ]; then
    err "无法找到 pip"
    echo "  请手动安装 pip："
    echo "  macOS：  python3 -m ensurepip --upgrade"
    echo "  Ubuntu： sudo apt install python3-pip"
    echo "  CentOS： sudo yum install python3-pip"
    pause "安装完成后按 Enter 继续..."
    $PYTHON -m pip --version &>/dev/null && PIP="$PYTHON -m pip"
fi

info "pip install 依赖..."
if $PIP install -r requirements.txt -q; then
    ok "依赖安装完成"
else
    warn "安装失败，尝试使用国内镜像源..."
    if $PIP install -r requirements.txt -q -i https://pypi.tuna.tsinghua.edu.cn/simple/; then
        ok "依赖安装完成（清华镜像）"
    else
        err "依赖安装失败"
        echo "  请手动执行："
        echo "  cd $INSTALL_DIR && pip3 install -r requirements.txt"
        echo "  或使用镜像：pip3 install -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple/"
        pause "安装完成后按 Enter 继续..."
    fi
fi

# ════════════════════════════════════════════════════════════
# Step 5: 钉钉登录
# ════════════════════════════════════════════════════════════
title 5 "钉钉登录授权"

auth_status=$(dws auth status 2>/dev/null | grep '"authenticated"' | grep -c 'true' || true)

if [ "$auth_status" -gt 0 ]; then
    ok "已登录钉钉，跳过"
else
    echo ""
    if is_headless; then
        echo -e "  ${YELLOW}检测到无图形界面环境，将使用设备流授权（Device Flow）${RESET}"
        echo "  请按提示在手机或其他浏览器完成授权"
        echo ""
        pause "按 Enter 开始授权..."
        if ! dws auth login --device; then
            warn "登录失败，请重试："
            echo "  手动执行：dws auth login --device"
            echo "  安装文档：https://github.com/DingTalk-Real-AI/dingtalk-workspace-cli"
            pause "登录成功后按 Enter 继续..."
        fi
    else
        echo -e "  ${BOLD}即将打开浏览器，用手机钉钉扫码授权${RESET}"
        pause "按 Enter 打开授权页..."
        if ! dws auth login; then
            warn "浏览器授权失败，改用设备流..."
            dws auth login --device || {
                err "登录失败"
                echo "  请手动执行：dws auth login --device"
                echo "  安装文档：https://github.com/DingTalk-Real-AI/dingtalk-workspace-cli"
                pause "登录成功后按 Enter 继续..."
            }
        fi
    fi
    ok "钉钉登录成功"
fi

# ════════════════════════════════════════════════════════════
# Step 6: 创建 AI 分身机器人
# ════════════════════════════════════════════════════════════
title 6 "创建你的 AI 分身机器人"

APP_KEY=""
APP_SECRET=""

echo ""
info "正在钉钉开放平台为你创建专属 AI 分身..."

if has_cmd dws && dws devapp --help &>/dev/null 2>&1; then
    robot_out=$(dws devapp robot create \
        --app-name "我的AI分身" \
        --robot-name "AI分身" \
        --desc "我的钉钉AI助手" \
        --yes --format json 2>/dev/null || true)

    APP_KEY=$(echo "$robot_out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('clientId') or d.get('appKey') or d.get('result',{}).get('clientId',''))" 2>/dev/null || true)
    APP_SECRET=$(echo "$robot_out" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('clientSecret') or d.get('appSecret') or d.get('result',{}).get('clientSecret',''))" 2>/dev/null || true)
fi

if [ -z "$APP_KEY" ]; then
    warn "自动创建未成功，请手动操作："
    echo ""
    echo -e "  ${BOLD}方法一（推荐）：命令行创建${RESET}"
    echo "  dws devapp robot create --app-name \"我的AI分身\" --robot-name \"AI分身\" --yes"
    echo ""
    echo -e "  ${BOLD}方法二：网页创建${RESET}"
    echo "  1. 访问 https://open-dev.dingtalk.com"
    echo "  2. 应用开发 → 企业内部应用 → 创建应用"
    echo "  3. 开启「机器人」功能 → 选择 Stream 模式"
    echo "  4. 在「基础信息」页复制 AppKey 和 AppSecret"
    echo ""
    echo -e "  ${YELLOW}注意：如果提示「没有开发者身份」，请联系管理员在${RESET}"
    echo -e "  ${YELLOW}https://open-dev.dingtalk.com 「权限管理」中添加你为开发者${RESET}"
    echo ""
    APP_KEY=$(ask "请输入 AppKey（clientId）" "")
    APP_SECRET=$(ask_secret "请输入 AppSecret（clientSecret）")
fi

[ -z "$APP_KEY" ]    && { err "AppKey 不能为空"; exit 1; }
[ -z "$APP_SECRET" ] && { err "AppSecret 不能为空"; exit 1; }
ok "机器人配置完成  AppKey: ${APP_KEY:0:8}..."

# ════════════════════════════════════════════════════════════
# Step 7: 配置 HAI Gateway
# ════════════════════════════════════════════════════════════
title 7 "配置 HAI Gateway（AI 模型服务）"

echo ""
echo -e "  ${BOLD}HAI Gateway 是公司的 AI 模型服务，每人有自己的访问 Token。${RESET}"
echo "  如果不知道 Token，请联系管理员申请。"
echo ""

# URL（有默认值则直接用，否则询问）
if [ "$HAI_GATEWAY_URL" = "https://your-lightchat-server.example" ]; then
    HAI_GATEWAY_URL=$(ask "HAI Gateway 地址" "https://")
    [ -z "$HAI_GATEWAY_URL" ] && { err "Gateway 地址不能为空"; exit 1; }
else
    echo -e "  Gateway 地址：${CYAN}$HAI_GATEWAY_URL${RESET}（已预配置）"
fi

HAI_TOKEN=$(ask_secret "你的 HAI Gateway Token")
[ -z "$HAI_TOKEN" ] && { err "Token 不能为空"; exit 1; }

# 可选：自定义模型
HAI_GATEWAY_MODEL=$(ask "模型名称" "$HAI_GATEWAY_MODEL")

ok "HAI Gateway 配置完成"

# ════════════════════════════════════════════════════════════
# Step 8: 写入 .env
# ════════════════════════════════════════════════════════════
title 8 "生成配置文件"

cat > "$INSTALL_DIR/.env" << EOF
DINGTALK_APP_KEY=$APP_KEY
DINGTALK_APP_SECRET=$APP_SECRET
ANTHROPIC_API_KEY=$HAI_TOKEN
ANTHROPIC_BASE_URL=$HAI_GATEWAY_URL
ANTHROPIC_DEFAULT_SONNET_MODEL=$HAI_GATEWAY_MODEL
EOF

ok ".env 写入完成：$INSTALL_DIR/.env"

# ════════════════════════════════════════════════════════════
# Step 9: 创建启动脚本
# ════════════════════════════════════════════════════════════
title 9 "创建启动脚本"

LAUNCH_SCRIPT="$INSTALL_DIR/启动AI分身.sh"
cat > "$LAUNCH_SCRIPT" << EOF
#!/bin/bash
# AI 分身启动脚本
export PATH="\$HOME/.local/bin:\$PATH"
cd "$INSTALL_DIR"
$PYTHON main.py
EOF
chmod +x "$LAUNCH_SCRIPT"

# macOS：创建 .command 文件（双击可运行）
if is_macos; then
    APP_SCRIPT="$HOME/Desktop/AI分身.command"
    cat > "$APP_SCRIPT" << EOF
#!/bin/bash
export PATH="\$HOME/.local/bin:\$PATH"
cd "$INSTALL_DIR"
$PYTHON main.py
EOF
    chmod +x "$APP_SCRIPT"
    ok "桌面快捷方式已创建：~/Desktop/AI分身.command"
else
    ok "启动脚本：$LAUNCH_SCRIPT"
    echo "  运行命令：bash '$LAUNCH_SCRIPT'"
fi

# ── 完成 ─────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║          🎉  安装配置完成！                  ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${RESET}"
if is_macos; then
    echo "  以后启动：双击桌面的「AI分身.command」"
else
    echo "  以后启动：bash '$LAUNCH_SCRIPT'"
fi
echo ""
echo "  现在先试一下，正在启动 AI 分身..."
echo ""
pause "按 Enter 启动..."

export PATH="$HOME/.local/bin:$PATH"
cd "$INSTALL_DIR"
$PYTHON main.py
