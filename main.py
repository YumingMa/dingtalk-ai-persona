"""Entry point — start DingTalk Stream bot with auto dws auth check."""

import json
import logging
import subprocess
import sys

import dingtalk_stream

from bot import PersonaBotHandler
from config import settings

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)


def check_dws_auth() -> bool:
    """Return True if dws is already authenticated."""
    try:
        result = subprocess.run(
            ["dws", "auth", "status", "-f", "json"],
            capture_output=True, text=True, timeout=10,
        )
        data = json.loads(result.stdout)
        return bool(data.get("authenticated") and data.get("token_valid"))
    except Exception:
        return False


def ensure_dws_auth() -> None:
    """Check dws auth status; trigger device login if not authenticated."""
    print("\n  Checking DingTalk authorization...")

    if check_dws_auth():
        print("  [OK] DingTalk already authorized\n")
        return

    print("  [!] Not authorized. Starting DingTalk login...")
    print("      Please scan the QR code or visit the URL shown below.\n")

    result = subprocess.run(["dws", "auth", "login", "--device"])

    if result.returncode != 0 or not check_dws_auth():
        print("\n  [ERROR] DingTalk authorization failed.")
        print("  Please run manually: dws auth login --device")
        sys.exit(1)

    print("  [OK] DingTalk authorization successful\n")


def main():
    ensure_dws_auth()

    if not settings.DINGTALK_APP_KEY or not settings.DINGTALK_APP_SECRET:
        print("  [ERROR] DINGTALK_APP_KEY / APP_SECRET not set in .env")
        sys.exit(1)

    print(f"  Starting AI Persona bot...")
    print(f"  AppKey: {settings.DINGTALK_APP_KEY[:8]}...\n")

    credential = dingtalk_stream.Credential(
        settings.DINGTALK_APP_KEY,
        settings.DINGTALK_APP_SECRET,
    )
    client = dingtalk_stream.DingTalkStreamClient(credential)
    client.register_callback_handler(
        dingtalk_stream.ChatbotMessage.TOPIC,
        PersonaBotHandler(),
    )

    print("  [OK] AI Persona is online! Go chat with it in DingTalk.\n")
    client.start_forever()


if __name__ == "__main__":
    main()
