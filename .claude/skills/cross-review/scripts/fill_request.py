"""依頼文の雛型（templates/進行/依頼文_共通の欄.md と 依頼文_<役割>.md）をつなぎ、台帳と引数の値で埋める（バイトモード。LF）。

使い方: python -I -X utf8 fill_request.py <台帳> <役割> <出力> [<名前>=<値> ...]
  役割: 構成の確認・Round1・回答・同件調査_拾い出し・同件調査_確かめ・反映・差分の点検・確認の回
  台帳の「固有の値」（作業フォルダ・リポジトリ・公式ドキュメントの断面・判断基準・扱う状態の範囲・文書の決まり・
  報告書の置き場所）を読み、雛型の {{名前}} と {{名前。例 …}} を置き換える。引数の値は台帳の値より優先する
  よく使う名前: 担当名・足場の名前・対象の文書・今の対象・前の対象・報告書・観点・版・n・日付（構成の確認）
  埋まらなかった {{…}} は、出力の後に一覧で出す（終了コード 1。主担当が判断で埋める）。全部埋まれば 0
  引数が「名前=値」でない・出力が台帳と同じ・出力が既にある（--force が無い）ときは終了コード 2
"""
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
TPL = Path(__file__).resolve().parent.parent / "templates" / "進行"
ROLES = ["構成の確認", "Round1", "回答", "同件調査_拾い出し", "同件調査_確かめ", "反映", "差分の点検", "確認の回"]
LEDGER_KEYS = ["作業フォルダ", "リポジトリ", "対象の文書", "公式ドキュメントの断面", "判断基準", "扱う状態の範囲", "文書の決まり", "報告書の置き場所"]
ALIAS = {"断面のパス": "公式ドキュメントの断面", "作業フォルダの絶対パス": "作業フォルダ", "リポジトリの絶対パス": "リポジトリ",
         "この担当が書く・読む報告書のパス": "報告書", "報告書のパス": "報告書", "前の対象、または「無し」": "前の対象",
         "今の対象": "今の対象", "起点": "前の対象", "終点、または空（作業ツリー）": "今の対象", "台帳のパス": "台帳",
         "作業指示者の決定と、台帳の「決定」の一覧。決まるまで進める事項は、手順・例・表をどの側で書くか": "決まっていること",
         "論理整合性 / 実用性 / 作業指示者+人間読み手": "観点", "今の版": "版", "YYYY-MM-DD": "日付"}


def read(p):
    data = Path(p).read_bytes()
    if b"\r" in data:
        sys.exit(f"CR が入っている: {p}")
    return data.decode("utf-8")


def ledger_values(path):
    text = read(path)
    vals = {"台帳": str(path)}
    for k in LEDGER_KEYS:
        m = re.search(r"^\| " + re.escape(k) + r" \| ([^\n]*) \|$", text, re.M)
        if m and "{{" not in m.group(1):
            vals[k] = m.group(1).strip().strip("`")
    # 台帳の「決定」の表から、依頼文の「決まっていること」を作る（テンプレートの例の行と「未決」は除く）
    sec = re.search(r"^## 決定[^\n]*\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if sec:
        rows = [l for l in sec.group(1).split("\n") if l.startswith("|") and "{{" not in l and not l.startswith("|---")][1:]
        items = []
        for r in rows:
            c = [x.strip() for x in r.strip("|").split("|")]
            if len(c) >= 5 and c[2] != "未決":
                items.append(f"* {c[1]}: {c[2]}（{c[3]}）")
            elif len(c) >= 5:
                items.append(f"* {c[1]}: 未決。決まるまでは {c[4]}")
        vals["決まっていること"] = "\n".join(items) if items else "* 無し（台帳の「決定」は空）"
    return vals


def main(argv):
    force = "--force" in argv
    argv = [a for a in argv if a != "--force"]
    if len(argv) < 3 or argv[1] not in ROLES:
        print(__doc__, file=sys.stderr)
        return 2
    ledger, role, out, *pairs = argv
    bad = [x for x in pairs if "=" not in x]
    if bad:
        print(f"引数が「名前=値」の形でない: {bad}\n" + __doc__, file=sys.stderr)
        return 2
    if Path(out).resolve() == Path(ledger).resolve():
        print("出力が台帳と同じパス（引数の順を確かめる）", file=sys.stderr)
        return 2
    if Path(out).exists() and not force:
        print(f"出力 {out} は既にある（上書きするときは --force）", file=sys.stderr)
        return 2
    vals = ledger_values(ledger)
    vals.update(dict(x.split("=", 1) for x in pairs))
    common = read(TPL / "依頼文_共通の欄.md")
    common = re.sub(r"\A<!--.*?-->\n\n", "", common, flags=re.S)   # 主担当への注記は依頼文に入れない
    body = read(TPL / f"依頼文_{role}.md")
    body = re.sub(r"^\{\{ここに 依頼文_共通の欄\.md を写して埋める[^}]*\}\}$", lambda m: common.rstrip("\n"), body, count=1, flags=re.M)

    def rep(m):
        name = m.group(1)
        key = ALIAS.get(name, name)
        key = re.split(r"[。、]", key)[0]
        key = ALIAS.get(key, key)
        return vals[key] if key in vals else m.group(0)

    filled = re.sub(r"\{\{([^{}]+)\}\}", rep, body)
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    Path(out).write_bytes(filled.encode("utf-8"))
    left = sorted(set(re.findall(r"\{\{[^{}]+\}\}", filled)))
    print(f"書いた: {out}")
    if left:
        print(f"埋まらなかった欄 {len(left)} 個（主担当が判断で埋める）:")
        for x in left:
            print("  " + x)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
