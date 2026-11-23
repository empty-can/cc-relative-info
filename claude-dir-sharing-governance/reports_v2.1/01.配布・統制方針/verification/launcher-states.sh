#!/usr/bin/env bash
# 本紙 §5-6 のランチャー最小例を、状態を変えて PowerShell で通す（claude は起動しない）。
#
#   LSHELL=pwsh|powershell  LBOM=0|1  bash launcher-states.sh [ランチャー例の出どころ]
#
#   LSHELL  pwsh（PowerShell 7。既定）か powershell（Windows PowerShell 5.1 の powershell.exe）
#   LBOM    1 のとき、差し替えた後のランチャーの先頭に UTF-8 の BOM を足す（既定 0＝出どころのまま。BOM なし）
#
# 出どころの既定は同じディレクトリの launcher-example.ps1。本紙（.md）を渡すと、
# 「# start_claude_code.ps1（Windows 版・最小例）」で始まる powershell のコードブロックを抜き出して使う。
# launcher-example-check.ps1（3-a' の検査を足した選択肢の版）を渡すこともできる。
# 出どころから変えるのは 2 行だけ:
#   - $SharedUrl の行 → 足場の bare リポジトリ
#   - 末尾の `claude @ClaudeArgs` → 状態の表示と、claude の代わりに引数を 1 個ずつ表示する python
# 共有リポは main（.gitignore に settings.local.json）・java/base・java/design（C12b・C14 のために、途中で python/base を足す）。
# 足場は $VERIF_ROOT/launcher-<LSHELL>-bom<LBOM>。
set -u
. "$(dirname "$0")/lib.sh" || exit 1

LSHELL="${LSHELL:-pwsh}"; LBOM="${LBOM:-0}"
case "$LSHELL" in pwsh|powershell) ;; *) verif_die "LSHELL は pwsh か powershell" ;; esac
case "$LBOM" in 0|1) ;; *) verif_die "LBOM は 0 か 1" ;; esac
SH_EXE="$LSHELL"; [ "$LSHELL" = powershell ] && SH_EXE=powershell.exe

SRC="${1:-$VERIF_LIB_DIR/launcher-example.ps1}"
[ -f "$SRC" ] || verif_die "ランチャー例が無い: $SRC"
command -v "$SH_EXE" >/dev/null || verif_die "$SH_EXE が無い"
command -v python >/dev/null || verif_die "python が無い"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1

NAME="launcher-$LSHELL-bom$LBOM"
verif_fresh_dir "$NAME"
W="$VERIF_ROOT/$NAME"
verif_cd "$W"
W_W="$(verif_winpath "$W")"

echo "######## launcher-states.sh $(date '+%Y-%m-%d %H:%M:%S %z') ／ $(git --version) ／ $SH_EXE $("$SH_EXE" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | tr -d '\r') ／ BOM=$LBOM ########"
echo "出どころ: $SRC"
echo "実行ポリシー（この環境の PSExecutionPolicyPreference=${PSExecutionPolicyPreference:-なし}）: $("$SH_EXE" -NoProfile -Command 'Get-ExecutionPolicy' | tr -d '\r')"

# ---- ランチャー例を取り出す ----
case "$SRC" in
  *.md)
    awk 'BEGIN{s=0} s==0 && /^```powershell$/ {s=1; next}
         s==1 { if ($0=="# start_claude_code.ps1（Windows 版・最小例）") {s=2; print; next} else {s=0; next} }
         s==2 && /^```$/ {exit} s==2 {print}' "$SRC" > "$W/launcher-original.ps1" ;;
  *) cp "$SRC" "$W/launcher-original.ps1" || verif_die "写せない" ;;
esac
[ "$(grep -c '^\$SharedUrl = ' "$W/launcher-original.ps1")" = 1 ] || verif_die "\$SharedUrl の行がちょうど 1 行ではない"
[ "$(grep -c '^claude @ClaudeArgs$' "$W/launcher-original.ps1")" = 1 ] || verif_die "claude @ClaudeArgs の行がちょうど 1 行ではない"
echo "ランチャー例: $(wc -l < "$W/launcher-original.ps1") 行"

# ---- 共有リポ（bare）とメンテナーのクローン ----
verif_fresh_dir "$NAME/shared.git"
git init -q --bare -b main "$W/shared.git" || verif_die "bare を作れない"
git clone -q "$W/shared.git" "$W/maint" 2>/dev/null || verif_die "maint を作れない"
(
  verif_enter_repo "$W/maint"
  printf 'settings.local.json\n' > .gitignore; echo "main の CLAUDE.md" > CLAUDE.md; mkdir rules; echo a > rules/a.md
  git add -A && git commit -qm "main" && git push -q origin main || exit 1
  git switch -qc java/base && echo j > rules/java.md && git add -A && git commit -qm "java/base" || exit 1
  git switch -qc java/design && echo d > rules/design.md && git add -A && git commit -qm "java/design" || exit 1
  git push -q origin java/base java/design || exit 1
) || verif_die "共有リポの準備に失敗"

# ---- 置き換える 2 行 ----
IFS= read -r CLAUDE_LINE <<'EOF'
Write-Output ("[起動] cwd=" + (Get-Location).Path + " / .claude のブランチ=" + (git -C $ClaudeDir rev-parse --abbrev-ref HEAD) + " / 先頭=" + (git -C $ClaudeDir log --oneline -1)); python -I -X utf8 -c "import sys; print('[claude の引数] ' + str(len(sys.argv) - 1) + ' 個: ' + ' '.join('<' + a + '>' for a in sys.argv[1:]))" @ClaudeArgs
EOF

mk() { # $1=ケース名 [$2=URL] → 作業リポとランチャーを作る
  local c="$W/cases/$1" url="${2:-$W_W/shared.git}"
  verif_fresh_dir "$NAME/cases/$1"
  ( verif_cd "$c"; git init -q -b main && printf '.claude/\n' > .gitignore ) || verif_die "作業リポを作れない: $1"
  awk -v u="\$SharedUrl = \"$url\"" -v cl="$CLAUDE_LINE" '
    /^\$SharedUrl = / {print u; next}
    $0=="claude @ClaudeArgs" {print cl; next}
    {print}' "$W/launcher-original.ps1" > "$c/start_claude_code.ps1"
  # 変わったのが 2 行だけであることを確かめる
  [ "$(diff "$W/launcher-original.ps1" "$c/start_claude_code.ps1" | grep -c '^[<>]')" = 4 ] || verif_die "差し替えが 2 行ではない: $1"
  if [ "$LBOM" = 1 ]; then
    { printf '\357\273\277'; cat "$c/start_claude_code.ps1"; } > "$c/s.tmp" && mv "$c/s.tmp" "$c/start_claude_code.ps1" || verif_die "BOM を足せない"
  fi
}
# & で呼ぶ。構文エラーで 1 行も実行されなかったときに終了コード 0 にならないよう、終わり方は lib.sh の VERIF_PS_EXIT
run() { # $1=ケース名 以降=ランチャーへの引数
  local c="$W/cases/$1"; shift
  echo "  \$ & start_claude_code.ps1 $*"
  "$SH_EXE" -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & '$(verif_winpath "$c")/start_claude_code.ps1' $*; $VERIF_PS_EXIT" 2>&1 | tr -d '\r' | sed 's/^/    | /'
  echo "    → 終了コード ${PIPESTATUS[0]}"
}
run_file() { # $1=ケース名 以降=引数（-File で呼ぶ）
  local c="$W/cases/$1"; shift
  echo "  \$ $SH_EXE -File start_claude_code.ps1 $*"
  "$SH_EXE" -NoProfile -File "$(verif_winpath "$c")/start_claude_code.ps1" "$@" 2>&1 | tr -d '\r' | sed 's/^/    | /'
  echo "    → 終了コード ${PIPESTATUS[0]}"
}
run_caller() { # $1=ケース名 $2=ランチャーを呼ぶ PowerShell の 1 行（引数の書き方をそのまま試す）
  local c="$W/cases/$1"
  printf '\357\273\277[Console]::OutputEncoding=[Text.Encoding]::UTF8\n%s\n%s\n' "$2" "$VERIF_PS_EXIT" > "$c/caller.ps1"
  echo "  caller.ps1: $2"
  ( verif_cd "$c"; "$SH_EXE" -NoProfile -File "$(verif_winpath "$c")/caller.ps1" 2>&1 | tr -d '\r' | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}" )
}
clone_ok() { # $1=ケース名 → 作業リポを作り、.claude に共有リポを clone しておく（main）
  mk "$1"; git clone -q "$W/shared.git" "$W/cases/$1/.claude" 2>/dev/null || verif_die "clone できない: $1"
}
in_repo() { # $1=リポジトリ 以降=git の引数（書き込み系はこれを通す）
  local d="$1"; shift
  ( verif_enter_repo "$d"; git "$@" ) || verif_die "git $* に失敗: $d"
}
in_bare() { local d="$1"; shift; ( verif_enter_repo "$d" bare; git "$@" ) || verif_die "git $* に失敗: $d"; }
show_branch() { echo "    .claude のブランチ（後）: $(git -C "$W/cases/$1/.claude" rev-parse --abbrev-ref HEAD 2>/dev/null || echo なし) ／ 先頭: $(git -C "$W/cases/$1/.claude" log --oneline -1 2>/dev/null)"; }

echo; echo "== C1 初回（.claude 無し・-Branch 省略）"; mk c1; run c1
echo; echo "== C2 初回（-Branch java/design）"; mk c2; run c2 -Branch java/design
echo; echo "== C3 初回（存在しないブランチ）"; mk c3; run c3 -Branch no/such; echo "    .claude: $( [ -e "$W/cases/c3/.claude" ] && echo ある || echo 無い )"
echo; echo "== C4 初回（URL が壊れている）"; mk c4 "$W_W/nonexistent.git"; run c4
echo; echo "== C5 空の .claude がある"; mk c5; mkdir "$W/cases/c5/.claude"; run c5
echo; echo "== C6 非空で git でない .claude がある（移行前の資産）"; mk c6; mkdir -p "$W/cases/c6/.claude/rules"; echo old > "$W/cases/c6/.claude/rules/old.md"; echo '{"p":1}' > "$W/cases/c6/.claude/settings.local.json"; run c6
echo "    .claude の中身（後）: $(cd "$W/cases/c6/.claude" || exit 1; find . -type f | sort | tr '\n' ' ')"
echo; echo "== C7 追跡ファイルを 2 つ編集した"; clone_ok c7; echo x >> "$W/cases/c7/.claude/CLAUDE.md"; echo x >> "$W/cases/c7/.claude/rules/a.md"; run c7
echo; echo "== C8 未追跡ファイルがある"; clone_ok c8; echo memo > "$W/cases/c8/.claude/memo.md"; run c8; echo "    memo.md（後）: $( [ -f "$W/cases/c8/.claude/memo.md" ] && echo 残っている || echo 無い )"
echo; echo "== C9 ignore 済みの settings.local.json だけがある"; clone_ok c9; echo '{"p":1}' > "$W/cases/c9/.claude/settings.local.json"; run c9; echo "    settings.local.json（後）: $(cat "$W/cases/c9/.claude/settings.local.json" 2>/dev/null || echo 消えた)"
echo; echo "== C10 java/design で作業していたメンバーが -Branch を省略"; clone_ok c10; in_repo "$W/cases/c10/.claude" switch -q java/design; run c10; show_branch c10
echo; echo "== C11 既存クローンで存在しないブランチ"; clone_ok c11; in_repo "$W/cases/c11/.claude" switch -q java/design; run c11 -Branch no/such; show_branch c11; echo "    rules（後）: [$(ls "$W/cases/c11/.claude/rules" | tr '\n' ' ')]"
echo; echo "== C12a fetch 失敗（remote URL を壊す）・手元にあるブランチ"; clone_ok c12a; in_repo "$W/cases/c12a/.claude" remote set-url origin "$W_W/broken.git"; run c12a -Branch java/base
echo; echo "== C12b fetch 失敗・一度も取っていないブランチ（clone 後に作られた）"; clone_ok c12b
( verif_enter_repo "$W/maint"; git switch -qc python/base main && echo p > rules/py.md && git add -A && git commit -qm py && git push -q origin python/base ) || verif_die "python/base を作れない"
in_repo "$W/cases/c12b/.claude" remote set-url origin "$W_W/broken.git"; run c12b -Branch python/base
echo; echo "== C13 メンテナーが rebase して force-push した後"; clone_ok c13; in_repo "$W/cases/c13/.claude" switch -q java/design
( verif_enter_repo "$W/maint"
  git switch -q main && echo "main 追記" >> CLAUDE.md && git commit -qam "main 追記" && git push -q origin main || exit 1
  git switch -q java/design && git -c rebase.updateRefs=true rebase -q main || exit 1
  git push -q --force-with-lease=java/base --force-with-lease=java/design origin java/base java/design ) || verif_die "rebase と push に失敗"
run c13 -Branch java/design; echo "    main 追記が届いたか: $(grep -c 'main 追記' "$W/cases/c13/.claude/CLAUDE.md") 件"
echo; echo "== C14 リモートでブランチが消された（ローカルには残っている）"; clone_ok c14; in_repo "$W/cases/c14/.claude" switch -q python/base
in_bare "$W/shared.git" branch -D python/base >/dev/null; run c14 -Branch python/base
echo; echo "== C15 大文字小文字違い（-Branch Java/Design。clone した直後＝ref は packed）"; clone_ok c15; run c15 -Branch Java/Design; show_branch c15; git -C "$W/cases/c15/.claude" branch --format='    ローカルブランチ: %(refname:short)'
echo; echo "== C16 detached HEAD のクローン"; clone_ok c16; in_repo "$W/cases/c16/.claude" switch -q --detach HEAD; run c16
echo; echo "== C17 Claude Code が .claude/ の下に書いたファイル（agent-memory を模擬）"; clone_ok c17; mkdir -p "$W/cases/c17/.claude/agent-memory/reviewer"; echo m > "$W/cases/c17/.claude/agent-memory/reviewer/MEMORY.md"; run c17
echo; echo "== C18 サブディレクトリから起動"; clone_ok c18; mkdir -p "$W/cases/c18/sub"
( verif_cd "$W/cases/c18/sub"
  "$SH_EXE" -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & ../start_claude_code.ps1; $VERIF_PS_EXIT" 2>&1 | tr -d '\r' | sed 's/^/    | /'
  echo "    → 終了コード ${PIPESTATUS[0]}" )

echo; echo "== A1 引数を渡す: -c（既存クローン・main）"; clone_ok a1; run a1 -c
echo; echo "== A2 引数を渡す: --resume abc（-Branch なし。java/design で作業中）"; clone_ok a2; in_repo "$W/cases/a2/.claude" switch -q java/design; run a2 --resume abc; show_branch a2
echo; echo "== A3 引数を渡す: -Branch java/design -p 'a b'"; clone_ok a3; run a3 -Branch java/design -p "'a b'"; show_branch a3
echo; echo "== A4 引数を渡す: -w x -d --model sonnet"; clone_ok a4; run a4 -w x -d --model sonnet
echo; echo "== A5 引数を渡す: 引数の途中に -Branch（--model sonnet -Branch java/base -c）"; clone_ok a5; run a5 --model sonnet -Branch java/base -c; show_branch a5
echo; echo "== A6 -File で呼ぶ: -Branch java/design -c --resume abc"; clone_ok a6; run_file a6 -Branch java/design -c --resume abc
echo; echo "== A7 初回（.claude 無し）で -Branch java/base -c"; mk a7; run a7 -Branch java/base -c

echo; echo "######## 足した状態（N）"
echo; echo "== N1 -Branch が最後の引数（値が無い）"; clone_ok n1; in_repo "$W/cases/n1/.claude" switch -q java/design; run n1 -c -Branch; show_branch n1
echo; echo "== N2 小文字の -branch java/design"; clone_ok n2; run n2 -branch java/design; show_branch n2
echo; echo "== N3 -Branch=java/design（= でつないだ）"; clone_ok n3; in_repo "$W/cases/n3/.claude" switch -q java/design; run n3 -Branch=java/design; show_branch n3
echo; echo "== N4 --branch java/design（ハイフン 2 つ）"; clone_ok n4; run n4 --branch java/design; show_branch n4
echo; echo "== N5 大文字小文字違い（-Branch Java/Design）。一度 java/design へ切り替えたことがある（loose な ref がある）"
clone_ok n5; in_repo "$W/cases/n5/.claude" switch -q java/design; in_repo "$W/cases/n5/.claude" switch -q main
echo "    refs/heads/java/design のファイル: $( [ -f "$W/cases/n5/.claude/.git/refs/heads/java/design" ] && echo ある || echo 無い )"
run n5 -Branch Java/Design; show_branch n5
echo "    ローカルブランチ: $(git -C "$W/cases/n5/.claude" branch --format='%(refname:short)' | tr '\n' ' ')"
echo "  -- 続けて、正しい名前 -Branch java/design で起動し直す"; run n5 -Branch java/design; show_branch n5
echo "    ローカルブランチ: $(git -C "$W/cases/n5/.claude" branch --format='%(refname:short)' | tr '\n' ' ')"
echo; echo "== N5b 大文字小文字違い。origin/java/design が fetch で更新されて loose な ref になっている"
clone_ok n5b; in_repo "$W/cases/n5b/.claude" switch -q java/design; in_repo "$W/cases/n5b/.claude" switch -q main
( verif_enter_repo "$W/maint"; git switch -q java/design && echo d2 >> rules/design.md && git commit -qam "java/design 追記" && git push -q origin java/design ) || verif_die "java/design 追記"
in_repo "$W/cases/n5b/.claude" fetch -q origin
echo "    refs/remotes/origin/java/design のファイル: $( [ -f "$W/cases/n5b/.claude/.git/refs/remotes/origin/java/design" ] && echo ある || echo 無い )"
run n5b -Branch Java/Design; show_branch n5b
echo; echo "== N6 index.lock が残っている（git が異常終了した後）"; clone_ok n6; : > "$W/cases/n6/.claude/.git/index.lock"; run n6 -Branch java/design; show_branch n6
echo; echo "== N6b 同じで -Branch 省略（main のまま）"; clone_ok n6b; : > "$W/cases/n6b/.claude/.git/index.lock"; run n6b
echo; echo "== N7 .claude がファイル"; mk n7; echo x > "$W/cases/n7/.claude"; run n7
echo; echo "== N8 -Branch origin/java/design"; clone_ok n8; run n8 -Branch origin/java/design; show_branch n8
echo; echo "== N9 -Branch -（直前のブランチ）"; clone_ok n9; in_repo "$W/cases/n9/.claude" switch -q java/design; in_repo "$W/cases/n9/.claude" switch -q main; run n9 -Branch -; show_branch n9
echo; echo "== N10 手元だけのブランチ mine（origin に無い）"; clone_ok n10; in_repo "$W/cases/n10/.claude" branch -q mine; run n10 -Branch mine; show_branch n10
echo; echo "== N11 メンテナーがブランチを消した後、一度もそのブランチを使ったことのないメンバー"; clone_ok n11
( verif_enter_repo "$W/maint"; git switch -qc python/old main && git push -q origin python/old ) || verif_die "python/old"
in_bare "$W/shared.git" branch -D python/old > /dev/null; run n11 -Branch python/old
echo; echo "== N12 D/F: 旧い名前 java を使っていたメンバー。メンテナーが java を消して java/base を作った（別の共有リポ shared2）"
git init -q --bare -b main "$W/shared2.git" || verif_die "shared2"
git clone -q "$W/shared2.git" "$W/maint2" 2>/dev/null || verif_die "maint2"
( verif_enter_repo "$W/maint2"
  printf 'settings.local.json\n' > .gitignore; echo m > CLAUDE.md; git add -A && git commit -qm main && git push -q origin main || exit 1
  git switch -qc java && echo j > j.md && git add -A && git commit -qm java && git push -q origin java ) || verif_die "shared2 の準備"
for c in n12 n12b; do
  mk $c "$W_W/shared2.git"; git clone -q "$W/shared2.git" "$W/cases/$c/.claude" 2>/dev/null || verif_die "$c clone"
  in_repo "$W/cases/$c/.claude" switch -q java
done
( verif_enter_repo "$W/maint2"; git switch -q main && git push -q origin --delete java && git branch -q -D java && git switch -qc java/base && echo jb > jb.md && git add -A && git commit -qm java/base && git push -q origin java/base ) || verif_die "java→java/base"
echo "  -- -Branch java/base"; run n12 -Branch java/base; show_branch n12
echo "    refs/remotes/origin: $(git -C "$W/cases/n12/.claude" for-each-ref --format='%(refname:short)' refs/remotes/ | tr '\n' ' ') ／ ローカル: $(git -C "$W/cases/n12/.claude" branch --format='%(refname:short)' | tr '\n' ' ')"
echo "  -- -Branch 省略（main）"; run n12; show_branch n12
echo "  -- もう一度 -Branch java/base"; run n12 -Branch java/base; show_branch n12
echo "    git -C .claude status --short: $(git -C "$W/cases/n12/.claude" status --short | tr '\n' ' ')"
echo "  -- 戻し方 (1): switch -f main で作業ツリーを戻し、旧いローカルブランチ java を消してから -Branch java/base"
in_repo "$W/cases/n12/.claude" switch -q -f main; in_repo "$W/cases/n12/.claude" branch -q -D java
run n12 -Branch java/base; show_branch n12
echo "  -- 戻し方 (2): 同じ状態の n12b で 1 回失敗させた後、.claude を消して（個人のファイルを退避した前提）ランチャーに clone させる"
run n12b -Branch java/base; show_branch n12b
( verif_cd "$W/cases/n12b"; verif_under_root "$W/cases/n12b/.claude" && rm -rf "$W/cases/n12b/.claude" ) || verif_die "消せない"
run n12b -Branch java/base; show_branch n12b
echo; echo "== N13 引数に二重引用符を含む値と空の値（caller.ps1 から呼ぶ）"
clone_ok n13; run_caller n13 "& \"\$PSScriptRoot\\start_claude_code.ps1\" -p 'say \"hi\" now' --x ''"
echo; echo "== N14 実行ポリシー: PSExecutionPolicyPreference を外して -File で起動する（メンバーの普通の端末に近い）"
clone_ok n14
echo "  Get-ExecutionPolicy（外した後）: $(env -u PSExecutionPolicyPreference "$SH_EXE" -NoProfile -Command 'Get-ExecutionPolicy' | tr -d '\r')"
( verif_cd "$W/cases/n14"; env -u PSExecutionPolicyPreference "$SH_EXE" -NoProfile -File "$(verif_winpath "$W/cases/n14")/start_claude_code.ps1" 2>&1 | tr -d '\r' | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}" )
echo; echo "######## 終了 ########"
