"""担当の最後の返答を、決まりの形と hook のログに突き合わせる（主担当が完了の通知ごとに流す）。

使い方: python -I -X utf8 check_return.py <返答を写したファイル> <subagent_type> [<agent_id> <hook のログ>]
確かめること:
  1. 「最初に読んだファイル」の欄があり、その担当が読むべきファイル（下の EXPECTED）が全部挙がっている
  2. 「決まりから外れた実行」「許可されなかった呼び出し」の欄がある
  3. ログ（<agent_id> の行）に hook が止めた記録があるのに、返答の「決まりから外れた実行」が「無し」になっていない
ログは hook が止めた・知らせたときにだけ作られる。ログが無いときは、hook と同じ定義（hook_common.load_config）で設定
（.claude/workspace/cross-review-hook.json）を読み、読めて、かつ渡したログのパスが設定の work_folder から出るパスと
同じなら、注意（「記録 0 行（ログが無い）」）にして問題にしない。設定が読めない・パスが違うときは問題にする。
問題が無ければ終了コード 0、あれば 1（問題の一覧を出す）、引数が誤りなら 2。
"""
import importlib.util
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
P = ".claude/skills/cross-review/"
EXPECTED = {
    "cross-review-logic-reviewer": ["references/rules.md", "references/reviewing.md", "templates/レビューア/論理整合性.md"],
    "cross-review-practicality-reviewer": ["references/rules.md", "references/reviewing.md", "templates/レビューア/実用性.md"],
    "cross-review-reader-reviewer": ["references/rules.md", "references/reviewing.md", "templates/レビューア/"],
    "cross-review-reviser": ["references/rules.md", "references/revising.md"],
    "cross-review-diff-checker": ["references/rules.md", "references/diff-check.md", "templates/点検/差分の点検.md"],
    "cross-review-clerk": ["references/rules.md", "references/clerk.md"],
}
FORBIDDEN = {"cross-review-diff-checker": ["references/revising.md"]}


def section(text, name):
    m = re.search(r"\*\*" + re.escape(name) + r"\*\*[:：]?(.*?)(?=\n\s*[-*] \*\*|\n#|\Z)", text, re.S)
    return m.group(1).strip() if m else None


def missing_log(log):
    """ログが無いときの扱い: (問題の文, 注意の文) のどちらかを返す。
    ログが無いだけ（設定が読め、渡したパスが設定から出るログのパスと同じ）なら注意。渡すパスの誤りを黙って 0 行にしないため、
    パスが違えば問題にする。"""
    try:
        spec = importlib.util.spec_from_file_location("cross_review_hook_common", Path(__file__).resolve().parent / "hook_common.py")
        hc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hc)
        config, err = hc.load_config()
        want = hc.log_path(config) if not err else ""
        same = bool(want) and hc.norm(want) == hc.norm(log)
    except Exception as e:   # hook_common を読めない・形が違う: 設定が読めないのと同じに扱う（止める側）
        return f"hook のログ {log} が無く、hook の設定を確かめられない（hook_common.py: {type(e).__name__}: {e}）", None
    if err:
        return f"hook のログ {log} が無く、hook の設定も読めない（{err}）", None
    if not same:
        return f"hook のログ {log} が無い。設定の work_folder から出るログのパスは {want}（渡すパスを確かめる）", None
    return None, f"hook のログ {log} はまだ無い（どの担当も hook に止められていない・知らされていない）。記録 0 行（ログが無い）として扱う"


def main(argv):
    if len(argv) not in (2, 4) or argv[1] not in EXPECTED:
        print(__doc__, file=sys.stderr)
        return 2
    reply = Path(argv[0]).read_bytes().decode("utf-8", "replace").replace("\\", "/")
    kind = argv[1]
    problems = []
    first = section(reply, "最初に読んだファイル")
    if first is None:
        problems.append("「最初に読んだファイル」の欄が無い")
    elif "前の回に読んだ" not in first:
        for exp in EXPECTED[kind]:
            if exp not in first:
                problems.append(f"最初に読んだファイルに {P}{exp} が無い")
        for bad in FORBIDDEN.get(kind, []):
            if bad in first:
                problems.append(f"読まない決まりの {P}{bad} を読んでいる")
    off = section(reply, "決まりから外れた実行")
    if off is None:
        problems.append("「決まりから外れた実行」の欄が無い")
    if section(reply, "許可されなかった呼び出し") is None:
        problems.append("「許可されなかった呼び出し」の欄が無い")
    if len(argv) == 4:
        agent_id, log = argv[2], argv[3]
        lines = []
        no_log = ""
        if not Path(log).exists():
            bad, note = missing_log(log)
            if bad:
                problems.append(bad)
            else:
                print(f"注意: {note}")
                no_log = "（ログが無い）"
        else:
            lines = [l for l in Path(log).read_bytes().decode("utf-8", "replace").splitlines()
                     if f"\t{agent_id}\t" in l and "\tdeny\t" in l]
        if lines and (off is None or re.match(r"^無し", off)):
            problems.append(f"hook のログに止めた記録が {len(lines)} 行あるのに、返答の「決まりから外れた実行」が無しになっている")
        print(f"hook のログの止めた記録: {len(lines)} 行{no_log}（{agent_id}）")
    if problems:
        print("問題:")
        for p in problems:
            print("  " + p)
        return 1
    print("問題: 0")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
