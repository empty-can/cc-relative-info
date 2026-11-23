"""PreToolUse hook（Write・Edit）: 書き込み先のパスを検査する。

1. hook の設定とログ（と、名前が cross-review-hook. で始まるファイル）への書き込みは、担当の種類によらず止める
2. 一時の場所（/tmp、%TEMP%、AppData/Local/Temp、セッションの scratchpad）への書き込みは止める
3. 設定の allow の、担当の種類（agent_type）の行に挙げた場所の下だけを許す（行が無ければ "*" の行。どちらも無ければ止める）
パスは .. を解いてから比べる。設定が無い・壊れている・雛型のままのときは止める（主担当が段階 0 で置く）。
agent_type が cross-review- で始まらない入力は、何もせず通す。
"""
import importlib.util
import os
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # .claude の下に __pycache__ を作らない

_spec = importlib.util.spec_from_file_location("hook_common", Path(__file__).resolve().parent / "hook_common.py")
hc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(hc)

HOOK = "pre_write"
TEMP_PARTS = ("/appdata/local/temp/",)
FIX_TEMP = "一時ファイルは `<作業フォルダ>\\30_tmp\\<担当名>\\` に置く。足場は `C:\\tmp\\<名前>`（scaffold.py で作る）"


def temp_roots(data):
    roots = ["/tmp", "/var/tmp"]
    for key in ("TEMP", "TMP", "TMPDIR"):
        v = os.environ.get(key)
        if v:
            roots.append(v)
    if data.get("scratchpad_dir"):
        roots.append(data["scratchpad_dir"])
    return roots


def body(data):
    config, err = hc.load_config()
    ti = data.get("tool_input")
    if not isinstance(ti, dict):
        hc.deny(config, data, HOOK, "tool_input の形が想定外", "主担当に知らせる")
    path = str(ti.get("file_path") or "")
    d = lambda reason, fix: hc.deny(config, data, HOOK, reason, fix, path)
    if err:
        d(err, "主担当に、hook の設定を段階 0 の手順で置いてもらう")
    if not path:
        d("書き込み先のパスが無い", "file_path を書く")
    if any(hc.under(path, p) for p in hc.protected_paths(config)) or hc.norm(path).rsplit("/", 1)[-1].startswith("cross-review-hook."):
        d(f"hook の設定・ログへの書き込み: {path}", "担当は hook の設定とログを書き換えない（読むのは Read ツールで）")
    p = hc.norm(path)
    if any(hc.under(p, r) for r in temp_roots(data)) or any(part in p + "/" for part in TEMP_PARTS):
        d(f"一時の場所への書き込み: {path}", FIX_TEMP)
    allow = config.get("allow") or {}
    agent = str(data.get("agent_type"))
    patterns = allow.get(agent, allow.get("*"))
    if patterns is None:
        d(f"hook の設定の allow に {agent} の行が無い", "主担当に、hook の設定の allow へこの担当の行を足してもらう")
    if not hc.match_any(path, patterns):
        listed = "、".join(patterns) if patterns else "（無し）"
        d(f"{agent} が書いてよい場所の外: {path}",
          f"書いてよいのは次の下だけ: {listed}。対象の文書や報告書を書き換える役でないなら、出力は依頼文のパスに書く。"
          "要る場所が無いときは、書かずに最後の返答の「判断してほしいこと」に書く")
    return 0


if __name__ == "__main__":
    sys.exit(hc.guarded_main(HOOK, body))
