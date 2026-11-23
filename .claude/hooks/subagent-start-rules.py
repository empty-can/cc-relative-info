"""SubagentStart の hook: サブエージェントの共通の決まりを、担当（サブエージェント）の文脈の先頭に足す。

置き場所: .claude/hooks/subagent-start-rules.py。決まりのファイルは、このスクリプトの場所からの相対で
../rule-assets/subagent-common-rules.md（.claude/rule-assets/subagent-common-rules.md）。
設定（settings の hooks.SubagentStart）から次の形で呼ぶ:
  python -I -X utf8 ${CLAUDE_PROJECT_DIR}/.claude/hooks/subagent-start-rules.py
出力: {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": <決まりの全文>}} を stdout に。
担当の種類によらず、全部の担当に同じ文を足す。入力（stdin の JSON）は読み捨てて使わない。
決まりのファイルが無い・読めない・UTF-8 でない・LIMIT 字を超えるときは、何も出さずに終了コード 0（担当の起動を止めない）。
hook の出力は 10,000 字を超えると切られるので、LIMIT は 9,000 字にしてある。
"""
import json
import os
import sys

sys.dont_write_bytecode = True
LIMIT = 9000
HERE = os.path.dirname(os.path.abspath(__file__))
RULES = os.path.normpath(os.path.join(HERE, "..", "rule-assets", "subagent-common-rules.md"))


def main():
    try:
        sys.stdin.buffer.read()   # 入力は使わないが、書き手が詰まらないように読み捨てる
    except (OSError, ValueError, AttributeError):
        pass
    try:
        with open(RULES, "rb") as f:
            text = f.read().decode("utf-8")
    except (OSError, UnicodeDecodeError):
        return 0
    text = text.replace("\r\n", "\n")
    if not text.strip() or len(text) > LIMIT:
        return 0
    out = {"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": text}}
    sys.stdout.buffer.write(json.dumps(out, ensure_ascii=False).encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
