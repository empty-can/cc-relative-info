"""PostToolUse hook（Write・Edit）: 書いたファイルに CR があれば、Claude に「LF に戻す」と返す（自動では直さない）。

返し方: 終了コード 0 で JSON の {"decision": "block", "reason": ...}（reason が tool の結果の横に Claude へ届く）。
CR が無いとき・読めないときは何も出さずに終了コード 0。
agent_type が cross-review- で始まらない入力は、何もせず通す。
"""
import importlib.util
import json
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # .claude の下に __pycache__ を作らない

HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


hc = _load("hook_common")
check_lf = _load("check_lf")
HOOK = "post_write"


def main():
    data = hc.read_input()
    if not hc.is_cross_review_agent(data):
        return 0
    ti = data.get("tool_input")
    if not isinstance(ti, dict):
        return 0   # PostToolUse は止められない。想定外の入力は知らせずに通す
    path = str(ti.get("file_path") or "")
    if not path:
        return 0
    try:
        n = check_lf.count_cr(path)
    except OSError:
        return 0
    if n == 0:
        return 0
    config, _ = hc.load_config()
    hc.log(config, data, HOOK, "notice", f"CR が {n} 個入った", path)
    reason = (f"[cross-review hook] {path} に CR が {n} 個入った。LF に戻す。"
              "直し方: Python のバイトモードで b'\\r\\n' を b'\\n' に置き換えるスクリプトを `<作業フォルダ>\\30_tmp\\<担当名>\\` に書き、"
              "`python -I -X utf8 <ファイル>` で実行する。その後 `python -I -X utf8 .claude/skills/cross-review/scripts/check_lf.py <ファイル>` で 0 を確かめる")
    sys.stdout.write(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
