"""直接调用本机 dws（用户已 auth login，无需传 token）。"""

import json
import subprocess


def run_dws(args: list[str], timeout: int = 30) -> dict:
    result = subprocess.run(
        ["dws"] + args + ["-f", "json", "-y"],
        capture_output=True, text=True, timeout=timeout,
    )
    output = result.stdout.strip() or result.stderr.strip()
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        return {"raw": output, "error": result.returncode != 0}
