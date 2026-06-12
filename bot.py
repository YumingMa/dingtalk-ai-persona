"""钉钉 Stream 机器人，本地运行，用户自己的 dws 身份。"""

import asyncio
import logging
import subprocess
import threading

import dingtalk_stream
from dingtalk_stream import AckMessage

from agent import run_agent
from session import conv_history, conv_queue, dedup

logger = logging.getLogger(__name__)

HELP_TEXT = """我是你的 AI 分身，能以你的身份操作钉钉：

📄 读文档  —  帮我读一下这篇文档：[链接]
✍️  写文档  —  帮我在知识库新建一篇文档...
💬 发消息  —  帮我告诉张三：明天会议取消
📊 看周报  —  总结本周团队周报
✅ 待办   —  查一下我有哪些未完成待办
📅 日程   —  我今天有什么安排

直接说需求就好，发 /clear 清除对话记忆。"""


class PersonaBotHandler(dingtalk_stream.ChatbotHandler):

    def process(self, callback: dingtalk_stream.CallbackMessage):
        msg = dingtalk_stream.ChatbotMessage.from_dict(callback.data)

        # 消息去重
        msg_id = getattr(msg, "message_id", None) or getattr(msg, "msgId", "")
        if msg_id and dedup.is_duplicate(msg_id):
            return AckMessage.STATUS_OK, "ok"

        # Ack-first，异步处理
        threading.Thread(target=self._handle, args=(msg,), daemon=True).start()
        return AckMessage.STATUS_OK, "ok"

    def _handle(self, msg):
        asyncio.run(self._handle_async(msg))

    async def _handle_async(self, msg):
        user_id = msg.sender_staff_id or "local"
        conv_id = getattr(msg, "conversation_id", None) or user_id
        text = _clean_text(msg)

        async with conv_queue.get_lock(conv_id):
            await self._dispatch(msg, user_id, text)

    async def _dispatch(self, msg, user_id, text):
        if text == "/help":
            self.reply_text(HELP_TEXT, incoming_message=msg)
            return

        if text == "/clear":
            conv_history.clear(user_id)
            self.reply_text("✅ 对话记忆已清除。", incoming_message=msg)
            return

        if not text:
            return

        self.reply_text("⏳ 思考中...", incoming_message=msg)

        try:
            history = conv_history.get(user_id)
            reply = run_agent(text, history=history)
            conv_history.append(user_id, "user", text)
            conv_history.append(user_id, "assistant", reply)
        except Exception as e:
            logger.exception(f"Agent error for {user_id}")
            reply = f"出错了：{e}"

        self.reply_text(reply, incoming_message=msg)


def _clean_text(msg) -> str:
    text = (msg.text.content or "").strip()
    if msg.at_users:
        for at in msg.at_users:
            for key in ("dingtalkId", "staffId", "robotCode"):
                val = at.get(key, "")
                if val:
                    text = text.replace(f"@{val}", "").strip()
    return text
