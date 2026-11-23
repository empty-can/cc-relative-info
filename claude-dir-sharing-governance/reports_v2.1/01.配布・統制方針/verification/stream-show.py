"""claude -p --output-format stream-json --verbose の出力を、判定に要る部分だけ表示する。

usage: python -I -X utf8 stream-show.py <stream-json のファイル> [--no-transcript]

表示するもの
  1. init: 実際のモデル・CLI の版・permission mode・使えるツール（MCP を除く／MCP の数）・
     起動時に見えている skills と agents・memory_paths・additional_directories
  2. ツール呼び出しの順序。手番（assistant の message.id）ごとに番号を振るので、
     同じ手番に複数のツールが並んでいれば「並列に呼んだ」と分かる
  3. ツールの結果（エラーかどうか・permission の判定の出所・先頭 300 字。300 字より後ろに
     合言葉の形の文字列があれば、それも別の行に出す）と、result の permission_denials
  4. モデルの最終の回答
  5. セッション記録（~/.claude/projects/*/<session_id>.jsonl。読むだけ）から、Claude Code が
     文脈に足したもののうち、判定に使う種類だけ（nested_memory＝rule とサブディレクトリの
     CLAUDE.md、dynamic_skill＝サブディレクトリの skill、起動時の指示ファイル、起動後の
     skill_listing）を、ツール呼び出しと同じ並びで表示する。
     記録には利用者のメールアドレス等が入っているので、ここに挙げた種類のパスと名前以外は出さない。
  6. 先行操作と Skill の手番の関係（同じ手番なら、Skill の起動の成否では判定できない）
"""
import glob
import json
import os
import re
import sys

SHOW_ATTACH = {"nested_memory", "dynamic_skill", "skill_listing"}
# 起動時の指示ファイルの種類名は版で変わりうるので、名前に次の語を含むものも出す
SHOW_ATTACH_WORDS = ("instruction", "memory", "claude_md", "claudemd")
NEVER_ATTACH = {"session_context", "credential_org", "prompt_snapshot", "environment",
                "mcp_instructions_delta", "deferred_tools_delta", "total_tokens_reminder",
                "hook_success", "date", "model", "language", "advisor_tool", "command_permissions"}


# 足場が埋める合言葉の形（NESTCLONE-AG7705・RULEPROBE-QX41・NESTCLONE-M2-7708 など）
PASS_RE = re.compile(r"\b[A-Z]{3,}(?:-[A-Z0-9]*\d[A-Z0-9]*)+\b")


def short(s, n=300):
    s = str(s).replace("\r", "").replace("\n", " / ")
    return s if len(s) <= n else s[:n] + "…"


def hidden_passwords(s, n=300):
    """short() で切った後ろにある合言葉を返す。Agent の結果は前置きが長く、合言葉が切れるため。"""
    s = str(s).replace("\r", "").replace("\n", " / ")
    if len(s) <= n:
        return []
    found = []
    for m in PASS_RE.finditer(s):
        if m.end() > n and m.group(0) not in found:
            found.append(m.group(0))
    return found


def attach_line(a):
    t = a.get("type")
    if t == "nested_memory":
        c = a.get("content") or {}
        extra = f" globs={c.get('globs')}" if isinstance(c, dict) and c.get("globs") else ""
        return f"nested_memory {a.get('path') or a.get('displayPath')}{extra}"
    if t == "dynamic_skill":
        return f"dynamic_skill {a.get('skillDir')} names={a.get('skillNames')}"
    if t == "skill_listing":
        if a.get("isInitial"):
            return None  # 起動時の一覧は init の skills で見る
        return f"skill_listing（起動後に追加） names={a.get('names')}"
    # 起動時の指示ファイルなど: パスらしい項目だけ出す
    # 中身（content）は出さず、パスと種類だけを出す
    keys = {}
    for k in ("path", "displayPath", "names"):
        if k in a and isinstance(a[k], (str, list)):
            keys[k] = a[k]
    for k, v in a.items():
        if isinstance(v, list):
            paths = [f"{x.get('path')}（{x.get('type')}）" for x in v if isinstance(x, dict) and x.get("path")]
            if paths:
                keys[k] = paths
    return f"{t} {json.dumps(keys, ensure_ascii=False)[:600]}"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    no_tr = "--no-transcript" in sys.argv
    if not args:
        print("usage: stream-show.py <stream-json file>")
        return 2
    events = []
    with open(args[0], encoding="utf-8", errors="replace") as f:
        for line in f:
            s = line.strip()
            if not s:
                continue
            if not s.startswith("{"):
                print("  (stream 以外の行)", short(s, 300))
                continue
            try:
                events.append(json.loads(s))
            except ValueError:
                print("  (JSON でない行)", short(s, 300))

    session_id = None
    turn_of = {}      # message.id -> 手番の番号
    calls = []        # (手番, name, input)
    print("  ---- stream-json ----")
    for ev in events:
        t = ev.get("type")
        if t == "system" and ev.get("subtype") == "init":
            session_id = ev.get("session_id")
            tools = ev.get("tools") or []
            mcp = [x for x in tools if x.startswith("mcp__")]
            print(f"  init: model={ev.get('model')} cli={ev.get('claude_code_version')} "
                  f"permissionMode={ev.get('permissionMode')}")
            print(f"  init: tools（MCP 以外）={[x for x in tools if not x.startswith('mcp__')]} MCP のツール数={len(mcp)}")
            print(f"  init: skills={ev.get('skills')}")
            print(f"  init: agents={ev.get('agents')}")
            print(f"  init: memory_paths={ev.get('memory_paths')}")
            print(f"  init: additional_directories={ev.get('additional_directories')}")
        elif t == "assistant":
            msg = ev.get("message", {})
            mid = msg.get("id")
            for block in msg.get("content", []):
                if block.get("type") == "tool_use":
                    if mid not in turn_of:
                        turn_of[mid] = len(turn_of) + 1
                    n = turn_of[mid]
                    calls.append((n, block.get("name"), block.get("input")))
                    print(f"  [手番{n}] tool: {block.get('name')} {short(json.dumps(block.get('input'), ensure_ascii=False), 300)}")
        elif t == "user":
            content = ev.get("message", {}).get("content", [])
            meta = {m.get("id"): m.get("permission_decision") for m in (ev.get("tool_result_meta") or []) if isinstance(m, dict)}
            if isinstance(content, list):
                for block in content:
                    if block.get("type") == "tool_result":
                        body = block.get("content")
                        if isinstance(body, list):
                            body = " ".join(b.get("text", "") for b in body if isinstance(b, dict))
                        err = " is_error=true" if block.get("is_error") else ""
                        pd = meta.get(block.get("tool_use_id"))
                        pds = f" permission={json.dumps(pd, ensure_ascii=False)}" if pd else ""
                        print(f"           result:{err}{pds} {short(body)}")
                        hidden = hidden_passwords(body)
                        if hidden:
                            print(f"           result の 300 字より後ろの合言葉: {hidden}")
                    elif block.get("type") == "text" and ev.get("isSynthetic"):
                        print(f"           (skill 本文) {short(block.get('text'), 200)}")
        elif t == "result":
            print(f"  result: subtype={ev.get('subtype')} is_error={ev.get('is_error')} num_turns={ev.get('num_turns')}")
            print(f"  permission_denials={json.dumps(ev.get('permission_denials'), ensure_ascii=False)[:600]}")
            print("  ---- 回答 ----")
            for ln in str(ev.get("result", "")).splitlines():
                print("  | " + ln)

    # 先行操作と Skill の手番の関係
    skill_turns = [n for (n, name, _) in calls if name == "Skill"]
    # 先行操作 = Skill・Agent 以外のツール
    other_turns = [n for (n, name, _) in calls if name not in ("Skill", "Agent", "Task")]
    if skill_turns:
        first_skill = skill_turns[0]
        same = [n for n in other_turns if n == first_skill]
        before = [n for n in other_turns if n < first_skill]
        if same:
            print(f"  ---- 手番: 最初の Skill（手番{first_skill}）は先行操作と同じ手番 → Skill の成否では判定できない")
        elif before:
            print(f"  ---- 手番: 先行操作（手番{max(before)}）の結果の後に Skill（手番{first_skill}）→ 判定できる")
        else:
            print(f"  ---- 手番: Skill（手番{first_skill}）より前に先行操作なし")
    else:
        print("  ---- 手番: Skill は呼ばれなかった")

    if no_tr or not session_id:
        if not session_id:
            print("  （init が無いのでセッション記録は探さない）")
        return 0
    pat = os.path.join(os.path.expanduser("~"), ".claude", "projects", "*", f"{session_id}.jsonl")
    found = glob.glob(pat)
    print(f"  ---- セッション記録（文脈に足されたもの） session_id={session_id} ----")
    if not found:
        print("  記録が見つからない")
        return 0
    print(f"  記録: {found[0]}")
    summary = {"nested_memory": [], "dynamic_skill": [], "startup": []}
    with open(found[0], encoding="utf-8", errors="replace") as f:
        for line in f:
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            t = ev.get("type")
            if t == "assistant":
                for block in (ev.get("message") or {}).get("content", []) or []:
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        print(f"  記録 tool: {block.get('name')} {short(json.dumps(block.get('input'), ensure_ascii=False), 160)}")
            elif t == "user":
                c = (ev.get("message") or {}).get("content")
                if isinstance(c, list):
                    for block in c:
                        if isinstance(block, dict) and block.get("type") == "tool_result":
                            print(f"  記録 result{' (error)' if block.get('is_error') else ''}")
            a = ev.get("attachment")
            if isinstance(a, dict):
                at = a.get("type") or ""
                if at in NEVER_ATTACH:
                    continue
                if at in SHOW_ATTACH or any(w in at.lower() for w in SHOW_ATTACH_WORDS):
                    ln = attach_line(a)
                    if ln:
                        print(f"  記録 文脈+ {ln}")
                    if at == "nested_memory":
                        summary["nested_memory"].append(str(a.get("path")))
                    elif at == "dynamic_skill":
                        summary["dynamic_skill"].append(str(a.get("skillDir")))
                    elif at != "skill_listing":
                        summary["startup"].append(ln)
    print(f"  記録の要約: nested_memory={summary['nested_memory']} dynamic_skill={summary['dynamic_skill']} 起動時の指示等={len(summary['startup'])} 件")
    return 0


if __name__ == "__main__":
    sys.exit(main())
