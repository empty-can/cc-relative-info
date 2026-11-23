#!/usr/bin/env bash
# 条件付きロード（paths 付き rule・サブディレクトリの CLAUDE.md・サブディレクトリの skill）が、
# 先行操作の形ごとに発火するかを測る（発火の系列の本体）。
# 先に trigger-setup.sh で足場（$VERIF_ROOT/trigprobe）を作っておくこと。
#
# - 各セッションは --tools で「先行操作に使うツール」と Skill だけを使える状態にする
#   （--allowedTools は確認なしで実行するツールの指定で、使えるツールは絞らない。
#   claude.ai の MCP のツールは --tools で外れない。init の行に数を出す）
# - プロンプトで「先行操作の結果を受け取ってから、次の手番で Skill を呼ぶ」と指示し、
#   stream-json の手番（message.id）で確かめて表示する。同じ手番なら Skill の成否では判定できない
# - 判定の証拠: 陽性は合言葉、陽性・陰性ともセッション記録の「文脈に足されたもの」
#   （nested_memory・dynamic_skill）。モデルの回答（RULE= 等）は並べて表示するだけ
#
# usage: bash trigger-matrix.sh [回数（既定 2）] [行の ID ...（既定 全行）]
#   行の ID: ctrl read write edit55 edit45 editr55 editr45 editn55 editn45 cat head grep pipe multi greptool
#   環境変数を引き継いで起動する場合: VERIF_INHERIT_ENV=1 bash trigger-matrix.sh 1
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1

SCAF="$VERIF_ROOT/trigprobe"
OUTDIR="$VERIF_ROOT/trigger-stream"
mkdir -p "$OUTDIR" || exit 1
verif_enter_repo "$SCAF"
[ -f sub/target.probefile ] || verif_die "足場がありません。trigger-setup.sh を先に実行してください"

N="${1:-2}"; shift || true
ROWS="${*:-ctrl read write edit55 edit45 editr55 editr45 editn55 editn45 cat head grep pipe multi greptool}"
ENVTAG=$([ "${VERIF_INHERIT_ENV:-0}" = 1 ] && echo inherit || echo strip)

ASK=$'\n\n先行操作は上の 1 つだけです。ほかのツール呼び出しやコマンドで、ファイルを読んだり探したりしてはいけません。\n先行操作のツールの結果を受け取ってから、**次の応答で**（先行操作と同じ応答の中に並べずに）Skill ツールで `subskill` を起動してください。\nそのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで起動した `subskill` が返した合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'
ASK_CTRL=$'\n\nSkill ツールで `subskill` を起動してください。そのうえで、以下を「ラベル=値」の形で1行ずつ出力してください。\n- いま文脈にある RULEPROBE- で始まる合言葉があれば `RULE=<合言葉>`、無ければ `RULE=NONE`\n- SUBCLAUDE- で始まる合言葉があれば `CMD=<合言葉>`、無ければ `CMD=NONE`\n- Skill ツールで起動した `subskill` が返した合言葉を `SKILL=<合言葉>`。起動できなければ `SKILL=FAIL`'

# 足場を初期状態へ戻す（足場のリポジトリに入り直してから git を使う）
cleanup() {
  ( verif_enter_repo "$SCAF" && git checkout -q -- sub/target.probefile && rm -f sub/new.probefile sub/other.probefile )
}
trap cleanup EXIT

# run <ID> <ラベル> <モデル> <使えるツール（カンマ区切り）> <先行操作の指示> [ctrl]
run() {
  local id="$1" label="$2" model="$3" tools="$4" pre="$5" kind="${6:-}" i out show ask
  case " $ROWS " in *" $id "*) ;; *) return 0 ;; esac
  ask="$ASK"; [ "$kind" = ctrl ] && ask="$ASK_CTRL"
  for i in $(seq 1 "$N"); do
    cleanup
    printf 'delta epsilon\n' > sub/other.probefile
    echo "================ [$id] $label ／ $ENVTAG ／ $i 回目 ================"
    VERIF_CUR_MODEL="$model" verif_header "--tools $tools（--allowedTools も同じ）"
    out="$OUTDIR/$id-$ENVTAG-$i-$(date +%H%M%S).jsonl"
    # shellcheck disable=SC2086
    verif_claude_stream "$out" --model "$model" --tools "$tools" --allowedTools ${tools//,/ } -p "${pre}${ask}"
    show="$(cat "$out.show")"
    echo "  ---- 先行操作の対象のファイル: $(tr '\n' '/' < sub/target.probefile) ／ sub/new.probefile: $( [ -f sub/new.probefile ] && echo あり || echo 無し )"
    local rec_rule rec_cmd rec_skill turn ans
    rec_rule=$(echo "$show" | grep -q '記録 文脈+ nested_memory .*scoped\.md' && echo 有 || echo 無)
    rec_cmd=$(echo "$show" | grep -q '記録 文脈+ nested_memory .*sub\\CLAUDE\.md' && echo 有 || echo 無)
    rec_skill=$(echo "$show" | grep -q '記録 文脈+ dynamic_skill .*sub\\.claude\\skills' && echo 有 || echo 無)
    turn=$(echo "$show" | sed -n 's/^  ---- 手番: //p' | head -1)
    ans=$(echo "$show" | sed -n 's/^  | *\(\(RULE\|CMD\|SKILL\)=.*\)$/\1/p' | tr '\n' ' ')
    echo "  ==== 要約 [$id/$ENVTAG/$i] 記録: rule=$rec_rule CLAUDE.md=$rec_cmd skill=$rec_skill ／ 手番: $turn ／ 回答: $ans／ rc=$VERIF_RC"
    echo
  done
}

EDIT_PRE='まず Edit ツールで sub/target.probefile の "alpha beta gamma" を "alpha beta gamma delta" に置換してください。'
# Read ツールは使える状態にするが、呼ばせない（公式の「Read が使えて確認が要らないとき、未読のファイルを
# 編集できる」の条件）。手番の表示で Edit より前に Read が無いことを確かめること
EDITN_PRE='まず Edit ツールで sub/target.probefile の "alpha beta gamma" を "alpha beta gamma delta" に置換してください。**Read ツールは呼ばないでください**（ファイルを読まずに、いきなり Edit を呼ぶこと）。Edit が失敗しても、Read で読み直してはいけません。'
EDITR_PRE='まず sub/target.probefile の "alpha beta gamma" を "alpha beta gamma delta" に置換してください。必要なら先に Read ツールでそのファイルを読んで構いません（その場合、Read と Edit が先行操作です）。'

run ctrl     "先行操作なし（対照）"                    "$VERIF_MODEL"   "Skill"           '何も先行操作をしないでください。' ctrl
run read     "Read ツール"                             "$VERIF_MODEL"   "Read,Skill"      'まず Read ツールで sub/target.probefile を読んでください。'
run write    "Write ツール（新規作成）"                "$VERIF_MODEL"   "Write,Skill"     'まず Write ツールで sub/new.probefile を新規作成し、内容は "x" の 1 行にしてください。'
run edit55   "Edit（Read は使えない）claude-haiku-5-5" claude-haiku-5-5 "Edit,Skill"      "$EDIT_PRE"
run edit45   "Edit（Read は使えない）claude-haiku-4-5" claude-haiku-4-5 "Edit,Skill"      "$EDIT_PRE"
run editr55  "Edit（Read も使える）claude-haiku-5-5"   claude-haiku-5-5 "Read,Edit,Skill" "$EDITR_PRE"
run editr45  "Edit（Read も使える）claude-haiku-4-5"   claude-haiku-4-5 "Read,Edit,Skill" "$EDITR_PRE"
run editn55  "Edit（Read は使えるが呼ばない）claude-haiku-5-5" claude-haiku-5-5 "Read,Edit,Skill" "$EDITN_PRE"
run editn45  "Edit（Read は使えるが呼ばない）claude-haiku-4-5" claude-haiku-4-5 "Read,Edit,Skill" "$EDITN_PRE"
run cat      "Bash の cat（1 ファイル）"               "$VERIF_MODEL"   "Bash,Skill"      'まず Bash ツールで `cat sub/target.probefile` を実行してください。'
run head     "Bash の head（1 ファイル）"              "$VERIF_MODEL"   "Bash,Skill"      'まず Bash ツールで `head -1 sub/target.probefile` を実行してください。'
run grep     "Bash の grep（1 ファイル）"              "$VERIF_MODEL"   "Bash,Skill"      'まず Bash ツールで `grep beta sub/target.probefile` を実行してください。'
run pipe     "Bash のパイプ付き"                       "$VERIF_MODEL"   "Bash,Skill"      'まず Bash ツールで `cat sub/target.probefile | head -1` を実行してください。'
run multi    "Bash の複数ファイル"                     "$VERIF_MODEL"   "Bash,Skill"      'まず Bash ツールで `cat sub/target.probefile sub/other.probefile` を実行してください。'
run greptool "Grep ツール"                             "$VERIF_MODEL"   "Grep,Skill"      'まず Grep ツールで sub/ 配下から "beta" を content モードで検索してください。'
