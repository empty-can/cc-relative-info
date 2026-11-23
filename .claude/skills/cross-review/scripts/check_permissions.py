"""権限の事前列挙の照合（agent-permission-runtime.md §1 の機械にできる部分）。

使い方: python -I -X utf8 check_permissions.py <agents のフォルダ> <settings.json> [<settings.local.json>] [--ledger <台帳>]
  agents のフォルダの cross-review-*.md の `tools` と、担当が出すことの決まっている呼び出し（下の EXPECTED）を、
  settings の permissions の allow・ask・deny と照らし、担当ごとに 8 種別の表の行を出す。--ledger を付けると、台帳の
  「## 権限の事前列挙（agent-permission-runtime.md §1）」の表をこの結果で置き換える
照らし方は近似である: ルールの `Tool(pattern)` の pattern を、`:*` と ` *` を「後ろに何でも」とみなすグロブで当てる。
公式の照合（コマンドの分割、組み込みの読み取りの集合、auto mode の classifier など）は再現しない。
終了コード: 0 = 決まった呼び出しが deny・ask に当たらない／1 = 当たる（担当が止まる）／2 = 引数の誤り（--ledger の値が無い・
agents のフォルダに cross-review-*.md が無い・1 つ目の settings が無い）／
3 = settings が壊れている（JSON が読めない。permission 全体が効かない）か、台帳に権限の表が無い。
2 つ目以降の無い settings ファイル（例えば別の端末で settings.local.json が無い）は誤りにせず、表の注記に「無かった」と書いて
照合を続ける。
"""
import fnmatch
import json
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
EXPECTED = {
    "Bash": ["bash C:/x/30_tmp/r1/a.sh", "python -I -X utf8 C:/x/30_tmp/r1/a.py", "git -C C:/repo diff a b -- x",
             "git -C C:/repo show a:x", "python -I -X utf8 .claude/skills/cross-review/scripts/scaffold.py make v",
             "python -I -X utf8 .claude/skills/cross-review/scripts/check_lf.py f"],
    "PowerShell": ["pwsh -NoProfile -File C:/x/30_tmp/r1/a.ps1", "python -I -X utf8 C:/x/30_tmp/r1/a.py", "bash C:/x/30_tmp/r1/a.sh",
                   "git -C C:/repo diff a b -- x"],
}
HEAD = "## 権限の事前列挙（agent-permission-runtime.md §1）"


MISSING = []


def load_rules(paths):
    rules = {"allow": [], "ask": [], "deny": []}
    for p in paths:
        if not Path(p).exists():
            MISSING.append(str(p))
            continue
        try:
            data = json.loads(Path(p).read_bytes().decode("utf-8"))
        except (OSError, json.JSONDecodeError) as e:
            print(f"settings が読めない（JSON が壊れていると permission 全体が効かない）: {p}: {e}", file=sys.stderr)
            sys.exit(3)
        perm = data.get("permissions", {})
        for k in rules:
            rules[k] += [(r, Path(p).name) for r in perm.get(k, [])]
    return rules


def rule_matches(rule, tool, arg):
    m = re.match(r"^(\w+)(?:\((.*)\))?$", rule)
    if not m or m.group(1) != tool:
        return False
    pat = m.group(2)
    if pat is None:
        return True
    pat = pat.replace(":*", "*")
    if pat.endswith(" *"):
        pat = pat[:-2] + "*"
    return fnmatch.fnmatchcase(arg, pat)


def agent_tools(path):
    text = Path(path).read_bytes().decode("utf-8")
    m = re.search(r"^tools:[ \t]*(.*)$", text, re.M)
    if not m:
        return []
    if m.group(1).strip():
        return [t.strip() for t in m.group(1).split(",") if t.strip()]
    rest = text[m.end():].split("\n")[1:]
    items = []
    for line in rest:
        mm = re.match(r"^\s+-\s*(\S+)", line)
        if not mm:
            break
        items.append(mm.group(1).strip("\"'"))
    return items


def main(argv):
    ledger = None
    if "--ledger" in argv:
        i = argv.index("--ledger")
        if i + 1 >= len(argv) or argv[i + 1].startswith("--"):
            print("--ledger の後に台帳のパスが無い\n" + __doc__, file=sys.stderr)
            return 2
        ledger = argv[i + 1]
        argv = argv[:i] + argv[i + 2:]
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    agents_dir, *settings = argv
    if not sorted(Path(agents_dir).glob("cross-review-*.md")):
        print(f"agents のフォルダに cross-review-*.md が無い: {agents_dir}", file=sys.stderr)
        return 2
    if not Path(settings[0]).is_file():
        print(f"共有の settings（1 つ目）が無い: {settings[0]}（無くてよいのは 2 つ目以降の settings.local.json だけ）", file=sys.stderr)
        return 2
    rules = load_rules(settings)
    rows = []
    blocked = 0
    for ap in sorted(Path(agents_dir).glob("cross-review-*.md")):
        tools = agent_tools(ap)
        cols = {}
        for kind in ("Write", "Edit", "Bash", "PowerShell", "MCP", "WebFetch", "Agent", "Read の deny"):
            if kind in ("MCP", "WebFetch", "Agent"):
                prefix = {"MCP": "mcp__", "WebFetch": "webfetch", "Agent": "agent"}[kind]
                cols[kind] = "持たない" if not any(t.lower().startswith(prefix) for t in tools) else "持つ（要確認）"
                continue
            if kind == "Read の deny":
                denies = [r for r, _ in rules["deny"] if r.startswith("Read(")]
                cols[kind] = f"deny {len(denies)} 件（担当は読まない場所）"
                continue
            if kind not in tools:
                cols[kind] = "持たない"
                continue
            notes = []
            for arg in EXPECTED.get(kind, []):
                for level in ("deny", "ask"):
                    hit = [f"{r}（{src}）" for r, src in rules[level] if rule_matches(r, kind, arg)]
                    if hit:
                        notes.append(f"{level}: `{arg}` ← {hit[0]}")
                        blocked += 1
            if kind in ("Write", "Edit"):
                notes.append("場所は hook_pre_write が絞る")
            elif not notes:
                notes.append("決まった呼び出しは deny・ask に当たらない")
            cols[kind] = "；".join(notes)
        rows.append([ap.stem] + [cols[k] for k in ("Write", "Edit", "Bash", "PowerShell", "MCP", "WebFetch", "Agent", "Read の deny")] +
                    ["deny・ask に当たる呼び出しあり" if any("deny:" in c or "ask:" in c for c in cols.values()) else "無し"])
    table = ["| 担当 | Write | Edit | Bash | PowerShell | MCP | WebFetch | Agent | Read の deny | 未カバーと対処 |",
             "|---|---|---|---|---|---|---|---|---|---|"] + ["| " + " | ".join(c.replace("|", "／") for c in r) + " |" for r in rows]
    if MISSING:
        table.append("")
        table.append("注記: 次の settings は無かった（照合に入れていない）: " + "、".join(MISSING))
    print("\n".join(table))
    if ledger:
        text = Path(ledger).read_bytes().decode("utf-8")
        lines = text.split("\n")
        if HEAD not in lines:
            print(f"台帳に「{HEAD}」が無い", file=sys.stderr)
            return 3
        h = lines.index(HEAD)
        i = h + 1
        while i < len(lines) and not lines[i].startswith("|"):
            if lines[i].startswith("## "):
                print(f"台帳の「{HEAD}」の下に表が無い", file=sys.stderr)
                return 3
            i += 1
        if i >= len(lines):
            print(f"台帳の「{HEAD}」の下に表が無い", file=sys.stderr)
            return 3
        j = i
        while j < len(lines) and lines[j].startswith("|"):
            j += 1
        lines[i:j] = table
        Path(ledger).write_bytes("\n".join(lines).encode("utf-8"))
        print(f"台帳の表を置き換えた: {ledger}")
    return 1 if blocked else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
