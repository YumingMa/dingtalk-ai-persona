"""
会话管理：同会话串行队列 + 消息去重 + 会话历史记忆。
参考 Peter 的 connect_queue.go / connect_stream.go 设计。
"""

import asyncio
import time
from collections import deque


class MsgDedup:
    """消息去重，防止钉钉重发导致重复回复（参考 connect_stream.go msgDedup）。"""

    def __init__(self, ttl_seconds: int = 60, max_size: int = 1000):
        self._seen: dict[str, float] = {}
        self._ttl = ttl_seconds
        self._max_size = max_size

    def is_duplicate(self, msg_id: str) -> bool:
        now = time.time()
        self._evict(now)
        if msg_id in self._seen:
            return True
        self._seen[msg_id] = now
        return False

    def _evict(self, now: float) -> None:
        if len(self._seen) < self._max_size:
            return
        expired = [k for k, t in self._seen.items() if now - t > self._ttl]
        for k in expired:
            del self._seen[k]


class ConvQueue:
    """
    同会话消息串行处理，不同会话并行。
    参考 Peter 的 connect_queue.go convQueue。
    避免同一群聊多条消息并发破坏会话上下文。
    """

    def __init__(self):
        self._locks: dict[str, asyncio.Lock] = {}

    def get_lock(self, conv_id: str) -> asyncio.Lock:
        if conv_id not in self._locks:
            self._locks[conv_id] = asyncio.Lock()
        return self._locks[conv_id]


class ConvHistory:
    """
    每个用户的会话历史（多轮对话上下文）。
    参考 Peter 的 convSessions，但存完整消息历史供 LightChat 使用。
    """

    MAX_TURNS = 10  # 保留最近 10 轮

    def __init__(self):
        self._history: dict[str, deque] = {}

    def get(self, user_id: str) -> list[dict]:
        return list(self._history.get(user_id, deque()))

    def append(self, user_id: str, role: str, content: str) -> None:
        if user_id not in self._history:
            self._history[user_id] = deque(maxlen=self.MAX_TURNS * 2)
        self._history[user_id].append({"role": role, "content": content})

    def clear(self, user_id: str) -> None:
        self._history.pop(user_id, None)


# 全局单例
dedup = MsgDedup()
conv_queue = ConvQueue()
conv_history = ConvHistory()
