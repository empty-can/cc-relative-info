"""クロスレビューの報告書を機械的に扱う道具（標準ライブラリだけ。バイトモードで読み書きし、LF を保つ）。

使い方: python -I -X utf8 report_tool.py <動作> ...
  new <観点> <報告書の置き場所> <YYYY-MM-DD> <対象のパス> <対象コミット>
        テンプレートを写して報告書を作る。名前は クロスレビュー_<観点>観点_<日付>.md。観点は 論理整合性・実用性・作業指示者+人間読み手
        既にあれば作らない（終了コード 2）。表の「レビュー日」「レビュー対象」「版」（0.8）を埋める
  extract <報告書>        指摘の一覧（ID・ラベル・今のラベル・観点・取り下げ・確認の態度の並び・題）を TSV で出す
  count <報告書>          今の現役の件数（ラベル × 観点）と取り下げ累計を出す
  check-counts <報告書> <版>
        件数表の <版> の列（同左は前の列の値）と、extract から数えた現役の件数を突き合わせる。違えば終了コード 1
  fill-counts <報告書> <版>
        件数表の <版> の列に、数えた現役の件数・合計・取り下げ累計を書き（前の列と同じなら「同左」）、続けて check-counts を流す
  summary <報告書>       判断依頼サマリーの表の骨組み（除外基準 1・2 で選んだ C・I の行。差し戻しリスクの欄はレビューアが書く）。
        「作業指示者の裁定」は「不要」で始まるもの以外（必要・あり・空・雛型のままも）を「要」として載せる
  targets <報告書> <n>    確認の回 n 回目で確かめる ID を出す（n=1 は全部、n≥2 は n-1 回目の追加と再指摘）
  converge <報告書> <n>   確認の回 n 回目の結果から、収束か次の版かを出す（追加の C・I と、C・I への再指摘の数）。
        版の上限は冒頭の表の「レビュー区分」で分ける: 論理整合性・実用性は 0.83、作業指示者+人間読み手は 0.81
        （その後の未収束は 0.9 の打ち切り）。レビュー区分が読めなければ止める（終了コード 3）
  set-version <報告書> <版> <日付> <内容>
        冒頭の表の「版」を <版> にし、変更履歴の <版> の行の日付・内容を埋める（無ければ行を足す）
  fill-answers <報告書> <回答ファイル>
        回答ファイルの欄を、報告書のレビューイの欄へ 1 回だけ流し込む（欄がプレースホルダのままのときだけ）。
        回答ファイルの形: 「@@ <ID> 問題点」か「@@ <ID> 修正案」の行の後に本文。流し込みの前後で、欄の外の行が 1 行も
        消えていないことを確かめる
書式が報告書のテンプレートと合わない（指摘の見出しが 1 つも無い・節の下の ### が「### <ID>. <題>」でない・態度らしい行
（「…態度**:」「…態度：」など）が「* **レビューア態度**: <5 区分>」でない・確認の欄の外にある・1 つの確認の欄に態度の行が
1 個でない・追加の印が「（追加・確認 n 回目）」でない・回の印の無い確認の欄・件数表や「合計」「取り下げ累計」の行が無い・
確かめるはずの C・I に n 回目の態度が無い・態度が未記入の欄が残る・C・I の問題点か修正案の確認の欄（n 回目）が無い・
重要度の語で始まる「##」の見出しが「## <ラベル>」でない・ID の形の見出しが節の下の「### <ID>.」でも直前の指摘の小見出しでもない
（「#### I2.」「###I2.」・節の外の指摘など）・追加の印のある見出しが指摘の見出しとして読めない・重要度変更の先のラベルが
「→ <ラベル>」で読めない・件数表に同じ名前の行が 2 つあるなど）ときは、0 件や「収束」「一致」を返さずに、読めなかった所を
出して終了コード 3 で止まる。態度の値の「{{…}}」と「（未記入）」は未記入と読む（数えない。converge では止める）。
終了コード: 0 = できた・一致・収束／1 = 件数が合わない・未収束／2 = 引数の誤り／3 = 書式が合わない。
"""
import re
import sys
from collections import Counter, OrderedDict
from pathlib import Path

sys.dont_write_bytecode = True

LABELS = ["CRITICAL", "IMPORTANT", "SUGGESTION", "POSITIVE"]
LETTER = {"C": "CRITICAL", "I": "IMPORTANT", "S": "SUGGESTION", "P": "POSITIVE"}
VIEW_TEMPLATES = {"論理整合性": "論理整合性.md", "実用性": "実用性.md", "作業指示者+人間読み手": "作業指示者+人間読み手.md"}
TPL_DIR = Path(__file__).resolve().parent.parent / "templates" / "レビューア"
ID_HEAD = re.compile(r"^### (?P<id>(?:U-)?(?P<letter>[CISP])-?(?P<num>\d+))[.:：]\s*(?P<title>.*)$")
SECTION = re.compile(r"^## (CRITICAL|IMPORTANT|SUGGESTION|POSITIVE)\s*$")
CONFIRM = re.compile(r"^#{4,5} \S+[.:]? ?レビューア確認")
ROUND_TAG = re.compile(r"(?:確認 )?(\d+) 回目")   # 「（確認 n 回目）」と「（n 回目）」の両方を回の印と読む
ADDED_TAG = re.compile(r"（追加・確認 (\d+) 回目）")
ATTITUDE = re.compile(r"^\* \*\*レビューア態度\*\*:\s*(.*)$")
VIEW = re.compile(r"^\*\*観点\*\*:\s*(.*)$")
ATTITUDES = ("受容", "取り下げ", "重要度変更", "再指摘", "修正採用")
# 態度の行らしいもの（「態度」で終わる見出し語の後にコロン）。厳しい形 ATTITUDE に合わなければ止める
LOOSE_ATT = re.compile(r"^\s*(?:[-*+]\s+)?\**\s*[^\s*:：]*態度\**\s*[:：]")
OWNER_HEAD = re.compile(r"^#{3,5} .*作業指示者")   # 作業指示者の態度表明の欄（「**態度**:」はここでは態度の行と読まない）
# 読み落としを止めるための緩い形（N1）。厳しい形（ID_HEAD・SECTION・ADDED_TAG）に合わないのに、これらに合う行があれば止める
LOOSE_ID_HEAD = re.compile(r"^#+\s*(?P<id>(?:U-)?[CISP]-?\d+)[.:：]")                     # 「#」の後に ID の形（空白なしも）
LOOSE_SECTION = re.compile(r"^#{1,2}\s*(?:CRITICAL|IMPORTANT|SUGGESTION|POSITIVE)", re.I)   # 重要度の語で始まる「#」「##」
ID_LED_LINE = re.compile(r"^\s*(?:[-*+]\s+)?\**\s*(?:U-)?[CISP]-?\d+[.:：]")                # ID で始まる本文の行（太字・箇条も）
ADDED_LOOSE = re.compile(r"[（(]\s*追加\s*[・･]?\s*確認")
CHANGE_TO = re.compile(r"重要度変更[^→]*→\s*(CRITICAL|IMPORTANT|SUGGESTION|POSITIVE)")       # 矢印は → だけを読む（-> などは止める）


def norm_id(fid):
    """ID の比べ方: 「C-1」と「C1」を同じとみなす（U- の接頭は残す）。"""
    return re.sub(r"^(U-)?([CISP])-?", r"\1\2", fid)


def unfilled(value):
    """態度の値が未記入（雛型の {{…}}、v2.1 の書式の「（未記入）」）か。"""
    v = value.strip()
    return v.startswith("{{") or v.lstrip("（(").startswith("未記入")


class FormatError(Exception):
    pass


def read(path):
    data = Path(path).read_bytes()
    if b"\r" in data:
        raise FormatError(f"CR が入っている（LF に戻してから使う）: {path}")
    return data.decode("utf-8")


def write(path, text):
    assert "\r" not in text
    Path(path).write_bytes(text.encode("utf-8"))


def parse(text):
    lines = text.split("\n")
    findings = []
    section = None
    cur = None
    in_confirm = None
    in_owner = False
    block = None   # 今読んでいる「レビューア確認」の欄: {"line", "round", "n"}

    def close_block():
        """確認の欄の終わり: 態度の行がちょうど 1 個か、態度の行が無く雛型のまま（{{…}} の行・見出し）なら未記入として読む。"""
        nonlocal block
        if block is not None:
            if block["n"] == 0 and block["ph"]:
                block["f"]["unfilled"].append(block["round"])
            elif block["n"] != 1:
                raise FormatError(f"{block['line']} 行目のレビューア確認の欄に、態度の行（「* **レビューア態度**: <態度>」）が "
                                  f"{block['n']} 個ある（1 個のはず）")
        block = None

    last_id = None   # 直前の指摘の ID（雛型のままの指摘も覚える。小見出し「#### C1. 問題点」を指摘の見出しと読まないため）
    for no, line in enumerate(lines, 1):
        if line.startswith("#"):
            close_block()
            if LOOSE_SECTION.match(line) and not SECTION.match(line):
                raise FormatError(f"{no} 行目: 重要度の節の見出しが「## CRITICAL」などの形でない（語を足さない）: {line[:60]!r}")
            is_head = bool(section) and bool(ID_HEAD.match(line))   # 重要度の節の下の「### <ID>. <題>」
            mi = LOOSE_ID_HEAD.match(line)
            if mi and not is_head and norm_id(mi.group("id")) != last_id:
                raise FormatError(f"{no} 行目: ID の形の見出しが、重要度の節（## CRITICAL など）の下の「### <ID>. <題>」でなく、"
                                  f"直前の指摘（{last_id or 'なし'}）の小見出しでもない: {line[:60]!r}")
            if ADDED_LOOSE.search(line) and not is_head:
                raise FormatError(f"{no} 行目: 追加の印のある見出しが、指摘の見出し（重要度の節の下の「### <ID>. <題>（追加・確認 n 回目）」）"
                                  f"として読めない: {line[:60]!r}")
        elif ADDED_LOOSE.search(line) and ID_LED_LINE.match(line):
            raise FormatError(f"{no} 行目: 追加の指摘が見出し（「### <ID>. <題>（追加・確認 n 回目）」）でなく本文の行に書かれている: {line[:60]!r}")
        m = SECTION.match(line)
        if m:
            section = m.group(1)
            cur = None
            continue
        if line.startswith("## "):
            section = None
            cur = None
            continue
        if section and line.startswith("### ") and not ID_HEAD.match(line):
            raise FormatError(f"{no} 行目: 指摘の見出しが「### <ID>. <題>」の形でない: {line[:60]!r}")
        m = ID_HEAD.match(line)
        if m and section:
            last_id = norm_id(m.group("id"))
        if m and section and m.group("title").startswith("{{"):
            cur = None   # 雛型のままの指摘（題が {{ で始まる）は数えない
            continue
        if m and section:
            if LETTER[m.group("letter")] != section:
                raise FormatError(f"{no} 行目: ID {m.group('id')} が節 {section} と合わない")
            cur = OrderedDict(id=m.group("id"), label=section, title=m.group("title"), view="", line=no,
                              added_round=None, attitudes=[], withdrawn=False, now=section, added_bad=False,
                              agree="", ruling=False, unfilled=[], blocks=[])
            a = ADDED_TAG.search(m.group("title"))
            if a:
                cur["added_round"] = int(a.group(1))
            elif "追加" in m.group("title"):
                cur["added_bad"] = True   # 追加の印の書き方が崩れている（converge・targets で止める）
            findings.append(cur)
            in_confirm = None
            continue
        if cur is None:
            continue
        m = VIEW.match(line)
        if m and not cur["view"]:
            cur["view"] = re.split(r"[（(]", m.group(1).strip())[0].strip()
            continue
        if line.startswith("#"):
            in_owner = bool(OWNER_HEAD.match(line))
            if CONFIRM.match(line):
                r = ROUND_TAG.search(line)
                in_confirm = int(r.group(1)) if r else 0
                block = {"line": no, "round": in_confirm, "n": 0, "ph": "{{" in line, "f": cur}
                kind = "問題点" if "問題点" in line else ("修正案" if "修正案" in line else "")
                cur["blocks"].append((in_confirm, kind))   # C11: C・I の 2 つの欄が回ごとにあるかを converge で見る
            else:
                in_confirm = None
            continue
        if block is not None and line.strip().startswith("{{"):
            block["ph"] = True   # 「{{C1 と同じ項目}}」など、雛型のままの欄
        if "同意の程度" in line:
            ma = re.search(r"同意の程度\**\s*[:：]\s*(.*)$", line)   # テンプレートは太字。v2.1 の書式は太字なし
            if ma and not cur["agree"]:
                cur["agree"] = ma.group(1).strip()
        mj = re.search(r"作業指示者の裁定\**\s*[:：]\s*(.*)$", line)
        if mj and not mj.group(1).strip().startswith("不要"):
            cur["ruling"] = True   # 「不要」で始まるもの以外（必要・あり・空・雛型のままも）は「要」として載せる（安全な側）
        mr = re.search(r"(?:裁定に回す点|作業指示者の判断に回したもの)\**\s*[:：]\s*(.*)$", line)   # 後者は v2.1 の書式
        if mr and mr.group(1).strip() and not mr.group(1).strip().startswith(("無し", "なし", "{{")):
            cur["ruling"] = True
        if not LOOSE_ATT.match(line):
            continue   # 態度の行らしくない行（理由の文が「態度」の語に触れるだけの行も）は読まない。欄ごとの数で崩れを捕まえる
        if in_owner and in_confirm is None:
            continue   # 作業指示者の態度表明の「**態度**:」
        m = ATTITUDE.match(line.strip())
        if not m:
            raise FormatError(f"{no} 行目: 態度の行が「* **レビューア態度**: <態度>」の形でない: {line.strip()[:60]!r}")
        if in_confirm is None:
            raise FormatError(f"{no} 行目: レビューア確認の欄の外に態度の行がある（欄の見出しが「##### <ID>. レビューア確認: …（確認 n 回目）」の形か確かめる）")
        block["n"] += 1
        att = m.group(1).strip().strip("*").strip()
        if unfilled(att):
            cur["unfilled"].append(in_confirm)
            continue
        if not att.startswith(ATTITUDES):
            raise FormatError(f"{no} 行目: 態度が 5 つの区分（{'・'.join(ATTITUDES)}）のどれでもない: {att[:30]!r}")
        cur["attitudes"].append((in_confirm, att))
        if att.startswith("取り下げ"):
            cur["withdrawn"] = True
        if att.startswith("重要度変更"):
            ch = CHANGE_TO.search(att)
            if not ch:
                raise FormatError(f"{no} 行目: 重要度変更の先のラベルが読めない（「重要度変更（<元> → <先のラベル>）」の形で、矢印は →）: {att[:40]!r}")
            cur["now"] = ch.group(1)
    close_block()
    if not findings:
        raise FormatError("指摘の見出し（## CRITICAL などの節の下の ### <ID>. <題>）が 1 つも無い。テンプレートの書式と合わない")
    return findings


def active_counts(findings):
    c = Counter()
    withdrawn = Counter()
    for f in findings:
        if f["withdrawn"]:
            withdrawn[f["label"]] += 1
        else:
            c[(f["now"], f["view"])] += 1
    return c, withdrawn


def count_tables(text):
    """件数表: {ラベル: {"cols": [...], "rows": {観点: [値...]}}}"""
    tables = {}
    lines = text.split("\n")
    i = 0
    while i < len(lines):
        m = re.match(r"^#{3,5} (CRITICAL|IMPORTANT|SUGGESTION|POSITIVE) 件数推移", lines[i])
        if m:
            j = i + 1
            while j < len(lines) and not lines[j].startswith("|"):
                j += 1
            head = [c.strip() for c in lines[j].strip("|").split("|")]
            rows = OrderedDict()
            k = j + 2
            while k < len(lines) and lines[k].startswith("|"):
                cells = [c.strip().strip("*") for c in lines[k].strip("|").split("|")]
                if cells[0] in rows:   # C11: 同じ名前の行が 2 つあると、後ろの行だけで検算してしまう
                    raise FormatError(f"{m.group(1)} の件数表に「{cells[0]}」の行が 2 つある（{k + 1} 行目）")
                rows[cells[0]] = cells[1:]
                k += 1
            tables[m.group(1)] = {"cols": head[1:], "rows": rows}
            i = k
        else:
            i += 1
    if len(tables) != 4:
        raise FormatError(f"件数表（#### <ラベル> 件数推移）が 4 つ無い（見つかったのは {list(tables)}）")
    return tables


def cell_value(values, idx):
    if idx >= len(values):
        return None   # 行の列が足りない（未記入として扱い、黙って一致にしない）
    j = idx
    while j >= 0:
        v = values[j].replace("*", "").strip()
        if v.startswith("同左") or v.startswith("←"):
            j -= 1
            continue
        m = re.match(r"^(\d+)(?:$|[（(])", v)   # 「9（1 回目に I9 を追加）」のような注記つきも数として読む
        if m:
            return int(m.group(1))
        return None
    return None


def cmd_new(view, out_dir, date, target, commit):
    if view not in VIEW_TEMPLATES:
        print(f"観点が誤り: {view}（{'・'.join(VIEW_TEMPLATES)}）", file=sys.stderr)
        return 2
    out = Path(out_dir) / f"クロスレビュー_{view}観点_{date}.md"
    if out.exists():
        print(f"既にある（作らない）: {out}", file=sys.stderr)
        return 2
    text = read(TPL_DIR / VIEW_TEMPLATES[view])
    reps = {"| レビュー日 | {{YYYY-MM-DD}}（Round 1） |": f"| レビュー日 | {date}（Round 1） |",
            "| 版 | {{0.8 / 0.81 / 0.82 / 0.83 / 0.9 / 1.0}} |": "| 版 | 0.8 |",
            "`{{対象の文書のパス}}`（{{行数}} 行。対象コミット `{{短いハッシュ}}`）":
                f"`{target}`（{len(read(target).split(chr(10))) if Path(target).is_file() else '{{行数}}'} 行。対象コミット `{commit}`）",
            "|0.8|{{YYYY-MM-DD}}|": f"|0.8|{date}|"}
    for a, b in reps.items():
        if text.count(a) != 1:
            raise FormatError(f"テンプレートに欄が無い: {a}")
        text = text.replace(a, b, 1)
    out.parent.mkdir(parents=True, exist_ok=True)
    write(out, text)
    print(out)
    return 0


def cmd_extract(path):
    for f in parse(read(path)):
        atts = " / ".join(f"{r}:{a[:20]}" for r, a in f["attitudes"])
        print("\t".join([f["id"], f["label"], f["now"], f["view"] or "（観点なし）", "取り下げ" if f["withdrawn"] else "",
                         str(f["added_round"] or ""), atts, f["title"][:60]]))
    return 0


def cmd_count(path):
    c, w = active_counts(parse(read(path)))
    for lab in LABELS:
        items = {v: n for (l, v), n in c.items() if l == lab}
        print(f"{lab}\t合計 {sum(items.values())}\t" + "\t".join(f"{v}={n}" for v, n in items.items()) + f"\t取り下げ累計 {w[lab]}")
    return 0


def cmd_check_counts(path, version):
    text = read(path)
    c, w = active_counts(parse(text))
    tables = count_tables(text)
    bad = 0
    for lab in LABELS:
        t = tables[lab]
        if version not in t["cols"]:
            raise FormatError(f"{lab} の件数表に {version} の列が無い（列: {t['cols']}）")
        idx = t["cols"].index(version)
        for view, vals in t["rows"].items():
            if view == "合計":
                continue
            if view == "取り下げ累計":
                raw = vals[idx].strip() if idx < len(vals) else ""
                if version == "0.8" and raw in ("—", "-", "－", "―"):
                    continue   # 0.8 の列（取り下げはまだ無い）の「—」だけを読み飛ばす
                want = cell_value(vals, idx)
                if want is None or want != w[lab]:
                    print(f"{'未記入' if want is None else '食い違い'}\t{lab}\t取り下げ累計\t表={raw!r}\t数えた={w[lab]}")
                    bad += 1
                continue
            want = cell_value(vals, idx)
            got = c[(lab, view)]
            if want is None:
                print(f"未記入\t{lab}\t{view}\t表={vals[idx] if idx < len(vals) else ''!r}\t数えた={got}")
                bad += 1
            elif want != got:
                print(f"食い違い\t{lab}\t{view}\t表={want}\t数えた={got}")
                bad += 1
        for must in ("合計", "取り下げ累計") if lab != "POSITIVE" else ("合計",):   # テンプレートの POSITIVE の表に取り下げ累計の行は無い
            if must not in t["rows"]:
                raise FormatError(f"{lab} の件数表に「{must}」の行が無い")
        if "取り下げ累計" not in t["rows"] and w[lab]:
            print(f"食い違い\t{lab}\t取り下げ累計\t表=（行が無い）\t数えた={w[lab]}")
            bad += 1
        total = cell_value(t["rows"]["合計"], idx)
        got_total = sum(n for (l, _), n in c.items() if l == lab)
        if total is None:
            print(f"未記入\t{lab}\t合計\t表={t['rows']['合計'][idx] if idx < len(t['rows']['合計']) else ''!r}\t数えた={got_total}")
            bad += 1
        elif total != got_total:
            print(f"食い違い\t{lab}\t合計\t表={total}\t数えた={got_total}")
            bad += 1
        views_in_table = set(t["rows"]) - {"合計", "取り下げ累計"}
        for (l, v), n in c.items():
            if l == lab and v not in views_in_table:
                print(f"表に無い観点\t{lab}\t{v}\t数えた={n}")
                bad += 1
    print("突き合わせ: " + ("一致" if bad == 0 else f"{bad} か所が合わない"))
    return 1 if bad else 0


def cmd_fill_counts(path, version):
    """件数表の <版> の列に、extract から数えた現役の件数と取り下げ累計を書く（前の列と同じなら「同左」）。"""
    text = read(path)
    c, w = active_counts(parse(text))
    tables = count_tables(text)
    lines = text.split("\n")
    for lab in LABELS:
        t = tables[lab]
        if version not in t["cols"]:
            raise FormatError(f"{lab} の件数表に {version} の列が無い（列: {t['cols']}）")
        idx = t["cols"].index(version)
        start = next(i for i, l in enumerate(lines) if re.match(r"^#{3,5} " + lab + r" 件数推移", l))
        j = next(i for i in range(start, len(lines)) if lines[i].startswith("|")) + 2
        while j < len(lines) and lines[j].startswith("|"):
            cells = [x.strip() for x in lines[j].strip("|").split("|")]
            name = cells[0].strip("*")
            if name == "合計":
                v = sum(n for (l, _), n in c.items() if l == lab)
                s = f"**{v}**"
            elif name == "取り下げ累計":
                v = w[lab]
                s = str(v)
            else:
                v = c[(lab, name)]
                s = str(v)
            prev = cell_value(cells[1:], idx - 1) if idx > 0 else None
            cells[idx + 1] = "同左" if (prev is not None and prev == v and idx > 0) else s
            lines[j] = "| " + " | ".join(cells) + " |"
            j += 1
    write(path, "\n".join(lines))
    print(f"件数表の {version} の列を書いた")
    return cmd_check_counts(path, version)


def current_version(text):
    m = re.search(r"^\| 版 \| ([0-9.]+)", text, re.M)
    if not m:
        raise FormatError("冒頭の表に「| 版 | <版> |」の行が無い")
    return m.group(1)


NEXT = {"0.8": "0.81", "0.81": "0.82", "0.82": "0.83"}
NEXT_CAPPED = {"0.8": "0.81"}   # 作業指示者+人間読み手（仕上げの回）の版の上限は 0.81（M3）


def review_kind(text):
    """冒頭の表の「レビュー区分」（観点）。読めない・知らない値なら止める（版の上限を誤らないため）。"""
    m = re.search(r"^\| レビュー区分 \|([^|\n]*)\|", text, re.M)
    v = m.group(1).strip() if m else ""
    v = v[:-2] if v.endswith("観点") else v
    if v not in VIEW_TEMPLATES:
        raise FormatError(f"冒頭の表の「| レビュー区分 | <観点>観点 |」が読めない（{'・'.join(VIEW_TEMPLATES)} のどれか）: {v[:30]!r}")
    return v


def cmd_converge(path, n):
    text = read(path)
    findings = parse(text)
    n = int(n)
    capped = review_kind(text) == "作業指示者+人間読み手"
    require_readable_rounds(findings, n)
    if not any(r == n for f in findings for r, _ in f["attitudes"]) and not any(f["added_round"] == n for f in findings):
        raise FormatError(f"確認 {n} 回目の欄（「レビューア確認…（確認 {n} 回目）」か「（追加・確認 {n} 回目）」の見出し）が無い")
    ci = [f for f in findings if f["now"] in ("CRITICAL", "IMPORTANT") and not f["withdrawn"]]
    added = [f["id"] for f in ci if f["added_round"] == n]
    again = [f["id"] for f in ci if any(r == n and a.startswith("再指摘") for r, a in f["attitudes"])]
    ver = current_version(text)
    converged = not added and not again
    if converged:
        nxt, note = "0.9", "収束"
    elif capped and ver in NEXT_CAPPED:
        nxt, note = NEXT_CAPPED[ver], "未収束。版を進めて Round 2 からやり直す（この観点の上限の版）"
    elif capped:
        nxt, note = "0.9", ("未収束。作業指示者+人間読み手は版の上限 0.81 の後なので打ち切り（0.82・0.83 の列と変更履歴の行は -。"
                            "未収束の ID を冒頭の表と変更履歴に書く）")
    elif ver in NEXT:
        nxt, note = NEXT[ver], "未収束。版を進めて Round 2 からやり直す"
    else:
        nxt, note = "0.9", "未収束。0.83 の後なので打ち切り（未収束の ID を冒頭の表と変更履歴に書く）"
    print(f"確認 {n} 回目: 追加の C・I {len(added)} 件 {added}／C・I への再指摘 {len(again)} 件 {again}")
    print(f"今の版 {ver} → 次の版 {nxt}（{note}）")
    return 0 if converged else 1


def require_readable_rounds(findings, n=None):
    """収束の判定・確かめる ID の選び出しの前に、読めない書式が無いことを確かめる（読めなければ止める）。"""
    require_round_tags(findings)
    bad = [f["id"] for f in findings if f["added_bad"]]
    if bad:
        raise FormatError("追加の印が「（追加・確認 n 回目）」の形でない見出しがある: " + "・".join(bad[:10]))
    if n is not None:
        want = target_ids(findings, n)
        ci = [f for f in findings if f["id"] in want and f["now"] in ("CRITICAL", "IMPORTANT") and not f["withdrawn"]
              and f["added_round"] != n]
        missing = [f["id"] for f in ci if not any(r == n for r, _ in f["attitudes"])]
        if missing:
            raise FormatError(f"確認 {n} 回目で確かめるはずの C・I に、確認 {n} 回目の態度が無い: " + "・".join(missing[:10]))
        # 確かめるはずの C・I に、未記入の態度（n 回目の欄、または回の印の無い雛型のままの欄）が残っていれば止める
        left = [f["id"] for f in ci if any(r in (n, 0) for r in f["unfilled"])]
        if left:
            raise FormatError(f"確認 {n} 回目で確かめるはずの C・I に、態度が未記入の確認の欄（問題点・修正案のどちらか）が残っている: "
                              + "・".join(left[:10]))
        # C11: 元のラベルが C・I の指摘は、問題点と修正案の 2 つの確認の欄を回ごとに書く（欄を丸ごと消すと読み落とすため）
        two = [f for f in findings if f["id"] in want and f["label"] in ("CRITICAL", "IMPORTANT") and not f["withdrawn"]
               and f["added_round"] != n]
        lack = []
        for f in two:
            kinds = {k for r, k in f["blocks"] if r == n}
            miss = [k for k in ("問題点", "修正案") if k not in kinds]
            if miss:
                lack.append(f"{f['id']}（{'・'.join(miss)}）")
        if lack:
            raise FormatError(f"確認 {n} 回目で確かめるはずの C・I に、確認 {n} 回目の「レビューア確認: 問題点／修正案」の欄が無い: "
                              + "・".join(lack[:10]))


def target_ids(findings, n):
    if n == 1:
        return [f["id"] for f in findings if not f["withdrawn"]]
    return [f["id"] for f in findings if f["added_round"] == n - 1
            or any(r == n - 1 and a.startswith("再指摘") for r, a in f["attitudes"])]


def require_round_tags(findings):
    """回の印の無い確認の欄（記入済みの態度があるのに「（確認 n 回目）」が無い）があれば止める。黙って 0 件と数えないため。"""
    bad = [f["id"] for f in findings if any(r == 0 for r, _ in f["attitudes"])]
    if bad:
        raise FormatError("回の印（「（確認 n 回目）」）の無いレビューア確認の欄がある: " + "・".join(bad[:10]))


def cmd_targets(path, n):
    """確認の回 n 回目で確かめる ID（n=1: 取り下げていない全部。n≥2: n-1 回目に足した指摘と、n-1 回目に再指摘にした指摘）。"""
    findings = parse(read(path))
    n = int(n)
    require_readable_rounds(findings)
    ids = target_ids(findings, n)
    print(f"確認 {n} 回目で確かめる ID（{len(ids)} 件）: " + "・".join(ids))
    return 0


def anchor(fid, title):
    s = f"{fid}. {title}".lower()
    s = re.sub(r"[^\w\s\-]", "", s)
    return "#" + re.sub(r"\s", "-", s.strip())


def cmd_summary(path):
    """判断依頼サマリーの表の骨組み（除外基準 1・2 で選んだ行）を出す。「差し戻しリスク」の欄はレビューアが書く。
    除外基準 1: SUGGESTION 以下。除外基準 2: 回答の同意の程度が「完全同意」で、レビューアの態度が全部「受容」のもの
    （ただし、回答の「作業指示者の裁定」が「不要」で始まらないか、「裁定に回す点」が「無し」でない指摘は載せる）。
    態度表明の列は、最後に記入された態度（無ければ「（確認前）」）。"""
    findings = parse(read(path))
    out = []
    for lab in ("CRITICAL", "IMPORTANT"):
        act = [f for f in findings if f["now"] == lab and not f["withdrawn"]]
        rows = []
        for f in act:
            only_accept = f["attitudes"] and all(a.startswith("受容") for _, a in f["attitudes"])
            if f["agree"].startswith("完全同意") and only_accept and not f["ruling"]:
                continue
            last = f["attitudes"][-1][1].split("（")[0] if f["attitudes"] else "（確認前）"
            rows.append(f"| [{f['id']}]({anchor(f['id'], f['title'])}) | {f['title'].replace('|', '／')} | {{{{差し戻しリスクの概要}}}} | {last} |")
        out.append(f"##### {lab}（{len(act)} 件、判断依頼対象 {len(rows)} 件）")
        out.append("")
        if rows:
            out += ["| ID | タイトル | 差し戻しリスク | 態度表明 |", "|---|---|---|---|"] + rows
        else:
            out.append("該当なし")
        out.append("")
    print("\n".join(out).rstrip())
    return 0


def cmd_set_version(path, version, date, content):
    text = read(path)
    old = current_version(text)
    text = re.sub(r"^(\| 版 \| )[0-9.]+", lambda m: m.group(1) + version, text, count=1, flags=re.M)
    row = re.compile(r"^\|" + re.escape(version) + r"\|[^\n]*$", re.M)
    new_row = f"|{version}|{date}|{content}|"
    if row.search(text):
        text = row.sub(lambda m: new_row, text, count=1)
    else:
        rows = list(re.finditer(r"^\|[0-9.]+\|[^\n]*$", text, re.M))
        if not rows:
            raise FormatError("変更履歴の表（|版|日付|内容|）が無い")
        last = rows[-1]
        text = text[:last.end()] + "\n" + new_row + text[last.end():]
    write(path, text)
    print(f"版 {old} → {version}。変更履歴: {new_row}")
    return 0


def cmd_fill_answers(path, answers):
    text = read(path)
    entries = []
    cur = None
    for line in read(answers).split("\n"):
        m = re.match(r"^@@ (\S+) (問題点|修正案)\s*$", line)
        if m:
            cur = {"id": m.group(1), "kind": m.group(2), "body": []}
            entries.append(cur)
        elif cur is not None:
            cur["body"].append(line)
    if not entries:
        raise FormatError("回答ファイルに「@@ <ID> 問題点|修正案」の行が無い")
    lines = text.split("\n")
    kept_before = []
    spans = []
    for e in entries:
        pat = re.compile(r"^#{4,5} " + re.escape(e["id"]) + r"[.:]? ?レビューイからの" + (r"回答" if e["kind"] == "問題点" else r"見解"))
        hits = [i for i, l in enumerate(lines) if pat.match(l)]
        if len(hits) != 1:
            raise FormatError(f"{e['id']} の {e['kind']} のレビューイの欄が {len(hits)} 個ある（1 個のはず）")
        s = hits[0]
        t = next((i for i in range(s + 1, len(lines)) if lines[i].startswith("#")), len(lines))
        body = "\n".join(lines[s + 1:t])
        if "{{" not in body:
            raise FormatError(f"{e['id']} の {e['kind']} の欄は記入済み（流し込みは 1 回だけ。追記は Edit で行う）")
        spans.append((s, t, e))
    spans.sort(key=lambda x: x[0], reverse=True)
    outside = [l for i, l in enumerate(lines) if not any(s < i < t for s, t, _ in spans)]
    for s, t, e in spans:
        body = "\n".join(e["body"]).strip("\n").split("\n")
        lines[s + 1:t] = [""] + body + [""]
    new_lines = lines
    # 欄の外の行が全部残っているか（順序どおり部分列として含まれるか）
    it = iter(new_lines)
    missing = [l for l in outside if not any(l == x for x in it)]
    if missing:
        raise FormatError(f"流し込みで欄の外の行が消えた（{len(missing)} 行。最初: {missing[0][:60]!r}）。書き込まない")
    write(path, "\n".join(new_lines))
    print(f"流し込んだ欄: {len(spans)}（{', '.join(e['id'] + ' ' + e['kind'] for _, _, e in sorted(spans))}）")
    return 0


def main(argv):
    cmds = {"new": (cmd_new, 5), "extract": (cmd_extract, 1), "count": (cmd_count, 1), "check-counts": (cmd_check_counts, 2),
            "converge": (cmd_converge, 2), "set-version": (cmd_set_version, 4), "fill-answers": (cmd_fill_answers, 2),
            "fill-counts": (cmd_fill_counts, 2), "targets": (cmd_targets, 2), "summary": (cmd_summary, 1)}
    if not argv or argv[0] not in cmds or len(argv) - 1 != cmds[argv[0]][1]:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        return cmds[argv[0]][0](*argv[1:])
    except FormatError as e:
        print(f"書式が合わない: {e}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
