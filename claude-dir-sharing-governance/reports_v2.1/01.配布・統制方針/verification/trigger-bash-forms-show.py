"""trigger-bash-forms.sh の補助。stream-json から、ツール呼び出しと最終の回答だけを表示する。"""
import json
import sys

sys.stdin.reconfigure(encoding="utf-8", errors="replace")
for line in sys.stdin:
    line = line.strip()
    if not line.startswith("{"):
        if line:
            print("  (raw)", line[:200])
        continue
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    if ev.get("type") == "system" and ev.get("subtype") == "init":
        print(f"  model={ev.get('model')} cli={ev.get('claude_code_version')}")
    elif ev.get("type") == "assistant":
        for block in ev.get("message", {}).get("content", []):
            if block.get("type") == "tool_use":
                print("  tool:", block.get("name"), json.dumps(block.get("input"), ensure_ascii=False)[:200])
    elif ev.get("type") == "user":
        content = ev.get("message", {}).get("content", [])
        if isinstance(content, list):
            for block in content:
                if block.get("type") == "tool_result":
                    body = block.get("content")
                    if isinstance(body, list):
                        body = " ".join(b.get("text", "") for b in body if isinstance(b, dict))
                    print("  result:", str(body).replace("\n", " / ")[:200])
    elif ev.get("type") == "result":
        print("  ---- 回答 ----")
        print(ev.get("result", ""))
