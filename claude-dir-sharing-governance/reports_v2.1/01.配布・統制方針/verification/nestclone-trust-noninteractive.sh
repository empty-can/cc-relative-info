#!/usr/bin/env bash
# V7 の前段（非対話）: .claude/settings.json の permissions.allow が claude -p で適用されるか、
# stderr の警告（this workspace has not been trusted）にどの trust の key が出るかを見る。
#
#   nested: 作業リポジトリの .claude/ が別リポジトリのクローン（.gitignore 済み。案C-1 の形）
#   plain : 対照。.claude/settings.json を作業リポジトリ自身が追跡する普通の形
# どちらも allow に Bash(./trustprobe.sh) を書き、--permission-mode default・--allowedTools なし・
# --tools Bash で ./trustprobe.sh を実行させる。trustprobe.out が作られたか、ツールの結果が拒否か、
# stderr の警告を記録する。
# 足場は毎回新しいパス（$VERIF_ROOT/trust-<形>-<時刻>）に作り、前後で ~/.claude.json の projects に
# そのパスの trust の記録が無いことを読むだけで確かめる（~/.claude.json には書かない）。
#
#   bash nestclone-trust-noninteractive.sh                 2 つの足場を作り、それぞれ claude -p で測る
#   bash nestclone-trust-noninteractive.sh scaffold-only   入れ子クローンの足場（trust-nested-<時刻>）だけを作り、
#                                                          claude は起動しない（V7 の対話の手順で使う足場を作るとき）
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
MODE="${1:-measure}"
case "$MODE" in measure|scaffold-only) ;; *) verif_die "引数は scaffold-only だけ: $MODE" ;; esac

STAMP=$(date +%Y%m%d%H%M%S)
PROMPT='Bash ツールで `./trustprobe.sh` を、この文字列のまま 1 回だけ実行してください（bash などを前に付けない）。ほかのコマンドは一切実行してはいけません。実行できたら出力をそのまま返し、拒否されたりエラーになったりしたら `DENIED <理由を 1 行>` とだけ返してください。別の方法を試してはいけません。'

make_probe() {
  cat > trustprobe.sh <<'SH'
#!/usr/bin/env bash
echo "TRUSTPROBE-RAN-$(date +%s)" | tee trustprobe.out
SH
  chmod +x trustprobe.sh
}

ALLOW_JSON='{
  "permissions": {
    "allow": ["Bash(./trustprobe.sh)"]
  }
}'

# measure <形> <足場のディレクトリ名>
measure() {
  local kind="$1" name="$2" out
  verif_enter_repo "$VERIF_ROOT/$name/work"
  echo "=== [$kind] 足場: $(verif_winpath .) ==="
  echo "--- 実行前の trust の記録:"
  "$VERIF_PY" -I -X utf8 "$VERIF_LIB_DIR/trust-lookup.py" "$name"
  verif_header "--tools Bash（--allowedTools なし）／ --permission-mode default"
  out="$VERIF_ROOT/$name/session.jsonl"
  verif_claude_stream "$out" --model "$VERIF_MODEL" --permission-mode default --tools "Bash" -p "$PROMPT"
  echo "  ==== 要約 [$kind] trustprobe.out: $([ -f trustprobe.out ] && echo '作られた（実行された）' || echo '無い（実行されていない）')" \
       "／ permission_denials: $(sed -n 's/^  permission_denials=//p' "$out.show")" \
       "／ stderr の trust の警告: $(grep -c 'has not been trusted' "$out.stderr") 行 ／ rc=$VERIF_RC"
  echo "--- stderr（全文）:"; cat "$out.stderr"
  echo "--- 実行後の trust の記録:"
  "$VERIF_PY" -I -X utf8 "$VERIF_LIB_DIR/trust-lookup.py" "$name"
  echo
}

# ---- nested: 入れ子クローン ----
N1="trust-nested-$STAMP"
verif_fresh_dir "$N1"
verif_cd "$VERIF_ROOT/$N1"
git init -q --bare shared.git || exit 1
git clone -q shared.git shared 2>/dev/null || exit 1
verif_enter_repo shared
git config user.email m@example.com; git config user.name m
printf '%s\n' "$ALLOW_JSON" > settings.json
printf '# 共有 .claude（V7 の足場）\n' > CLAUDE.md
git add -A && git commit -qm init && git push -q origin HEAD || verif_die "共有リポの準備に失敗"
cd .. || exit 1
mkdir work || exit 1
verif_cd work
git init -q || exit 1
verif_enter_repo .
git config user.email w@example.com; git config user.name w
printf '.claude/\ntrustprobe.out\n' > .gitignore
make_probe
git add -A && git commit -qm init || verif_die "作業リポの commit に失敗"
git clone -q ../shared.git .claude 2>/dev/null || verif_die ".claude の clone に失敗"
if [ "$MODE" = scaffold-only ]; then
  echo "足場を作った（claude は起動していない）: $(verif_winpath "$VERIF_ROOT/$N1/work")"
  echo "--- trust の記録:"
  "$VERIF_PY" -I -X utf8 "$VERIF_LIB_DIR/trust-lookup.py" "$N1"
  exit 0
fi
measure nested "$N1"

# ---- plain: 作業リポジトリが .claude/settings.json を追跡する ----
N2="trust-plain-$STAMP"
verif_fresh_dir "$N2"
verif_cd "$VERIF_ROOT/$N2"
mkdir work || exit 1
verif_cd work
git init -q || exit 1
verif_enter_repo .
git config user.email w@example.com; git config user.name w
mkdir -p .claude || exit 1
printf '%s\n' "$ALLOW_JSON" > .claude/settings.json
printf '# 作業リポの .claude（対照）\n' > .claude/CLAUDE.md
printf 'trustprobe.out\n' > .gitignore
make_probe
git add -A && git commit -qm init || verif_die "作業リポの commit に失敗"
measure plain "$N2"
