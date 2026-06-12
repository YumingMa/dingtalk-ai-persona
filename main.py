"""Entry point — 启动钉钉 Stream 模式机器人。"""

import logging

import dingtalk_stream

from bot import BotHandler
from config import settings
from db import init_db

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


def main():
    init_db()
    logger.info("数据库初始化完成")

    credential = dingtalk_stream.Credential(
        settings.DINGTALK_APP_KEY,
        settings.DINGTALK_APP_SECRET,
    )
    client = dingtalk_stream.DingTalkStreamClient(credential)
    client.register_callback_handler(
        dingtalk_stream.ChatbotMessage.TOPIC,
        BotHandler(),
    )

    logger.info("机器人启动中，等待消息...")
    client.start_forever()


if __name__ == "__main__":
    main()
