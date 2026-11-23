#!/usr/bin/env bash
# 本紙 §7-4 の「ランチャーが止まったとき」の表と、§5-6・§7-2・§7-3 の対処を、止める → 書いてある対処 → もう一度起動、の順で通す。
# ランチャーは launcher-states.sh と同じく、launcher-example.ps1 の $SharedUrl の行と末尾の claude の行の 2 行だけを差し替え、BOM を付ける。
# メンバーがする対処（移す・消す・写す）は、メンバーの端末と同じく PowerShell で行う。claude は起動しない。
#   LSHELL=pwsh|powershell bash launcher-remedy.sh [場面...]   （既定は pwsh・全部。足場は $VERIF_ROOT/lremedy-<シェル>）
set -u
. "$(dirname "$0")/lib.sh" || exit 1
S="$(cd "$(dirname "$0")" && pwd)" || verif_die "スクリプトの場所へ移れません"
LSHELL="${LSHELL:-pwsh}"; SH_EXE="$LSHELL"; [ "$LSHELL" = powershell ] && SH_EXE=powershell.exe
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
ALL=(t01 t02 t03 t04 t04b t04c t06 t07 t07b t07w t07r t08 t09 t10 t12 t13 t14 t15 t16 t17 t18 m73)
SC=("$@"); [ ${#SC[@]} -gt 0 ] || SC=("${ALL[@]}")
want() { case " ${SC[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

NAME="lremedy-$LSHELL"
verif_fresh_dir "$NAME"; W="$VERIF_ROOT/$NAME"; verif_cd "$W"; W_W="$(verif_winpath "$W")"
echo "######## launcher-remedy.sh $(date '+%Y-%m-%d %H:%M:%S %z') ／ $(git --version) ／ $SH_EXE $("$SH_EXE" -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' | tr -d '\r')"
cp "$S/launcher-example.ps1" "$W/launcher-original.ps1" || verif_die "写せない"
cp "$S/launcher-example-check.ps1" "$W/launcher-check.ps1" || verif_die "写せない"

# 共有リポ: main（.gitignore に settings.local.json）・java/base・java/design・python/base
git init -q --bare -b main "$W/shared.git" || verif_die "bare"
git clone -q "$W/shared.git" "$W/maint" 2>/dev/null || verif_die "maint"
( verif_enter_repo "$W/maint"
  printf 'settings.local.json\n' > .gitignore; echo "main の CLAUDE.md" > CLAUDE.md; mkdir rules; echo a > rules/a.md
  git add -A && git commit -qm "main" && git push -q origin main || exit 1
  git switch -qc java/base && echo j > rules/java.md && git add -A && git commit -qm "java/base" || exit 1
  git switch -qc java/design && echo d > rules/design.md && git add -A && git commit -qm "java/design" || exit 1
  git switch -qc python/base main && echo p > rules/py.md && git add -A && git commit -qm "python/base" || exit 1
  git push -q origin java/base java/design python/base ) || verif_die "共有リポの準備"

IFS= read -r CLAUDE_LINE <<'EOF'
Write-Output ("[起動] .claude のブランチ=" + (git -C $ClaudeDir rev-parse --abbrev-ref HEAD) + " / 先頭=" + (git -C $ClaudeDir log --oneline -1))
EOF
launcher_for() { # $1=URL $2=出どころ → 標準出力に、2 行を差し替えて BOM を付けたランチャー
  printf '\357\273\277'
  awk -v u="\$SharedUrl = \"$1\"" -v cl="$CLAUDE_LINE" '/^\$SharedUrl = / {print u; next} $0=="claude @ClaudeArgs" {print cl; next} {print}' "$2"
}
mk() { # $1=ケース名 [$2=URL] [$3=出どころ]
  local c="$W/cases/$1" url="${2:-$W_W/shared.git}" src="${3:-$W/launcher-original.ps1}"
  verif_fresh_dir "$NAME/cases/$1"
  ( verif_cd "$c"; git init -q -b main && printf '.claude/\n' > .gitignore && git add -A && git commit -qm init ) || verif_die "作業リポ: $1"
  launcher_for "$url" "$src" > "$c/start_claude_code.ps1"
  [ "$(tail -c +4 "$c/start_claude_code.ps1" | diff "$src" - | grep -c '^[<>]')" = 4 ] || verif_die "差し替えが 2 行ではない: $1"
}
run() { # $1=ケース名 以降=引数
  local c="$W/cases/$1"; shift
  echo "  \$ .\\start_claude_code.ps1 $*"
  "$SH_EXE" -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & '$(verif_winpath "$c")/start_claude_code.ps1' $*; $VERIF_PS_EXIT" 2>&1 | tr -d '\r' | tr -d '\033' | sed 's/^/    | /'
  LRC=${PIPESTATUS[0]}; echo "    → 終了コード $LRC"
}
mpw() { # $1=ケース名 $2=PowerShell のコマンド（作業リポジトリのルートで実行する。メンバーの手の操作）
  local c="$W/cases/$1"
  verif_under_root "$c" || verif_die "VERIF_ROOT の外: $c"
  echo "  （メンバーの操作 PS> $2）"
  # 終了コードは、最後のコマンドが外部コマンド（git）ならその値、コマンドレットなら $? から 0/1 にする
  ( verif_cd "$c"; "$SH_EXE" -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Set-Location '$(verif_winpath "$c")'; \$global:LASTEXITCODE = 0; $2; if (-not \$?) { exit 1 }; exit \$LASTEXITCODE" 2>&1 | tr -d '\r' | tr -d '\033' | sed 's/^/    ps| /'; echo "    → 終了コード ${PIPESTATUS[0]}" )
}
clone_ok() { mk "$1"; git clone -q "$W/shared.git" "$W/cases/$1/.claude" 2>/dev/null || verif_die "clone: $1"; }
in_repo() { local d="$1"; shift; ( verif_enter_repo "$d"; git "$@" ) || verif_die "git $* : $d"; }
in_bare() { local d="$1"; shift; ( verif_enter_repo "$d" bare; git "$@" ) || verif_die "git $* : $d"; }
maint() { ( verif_enter_repo "$W/maint"; eval "$*" ) || verif_die "maint: $*"; }
st() { echo "    .claude: $(git -C "$W/cases/$1/.claude" rev-parse --abbrev-ref HEAD 2>/dev/null || echo なし) ／ status: [$(git -C "$W/cases/$1/.claude" status --porcelain 2>&1 | tr '\n' ' ')] ／ 作業リポ status: [$(git -C "$W/cases/$1" status --porcelain 2>&1 | tr '\n' ' ')]"; }
tree_am() { echo "    agent-memory の中身: $(cd "$W/cases/$1/.claude" 2>/dev/null && find agent-memory -type f 2>/dev/null | sort | while read -r f; do printf '%s=%s ' "$f" "$(cat "$f")"; done)"; }
hdr() { echo; echo "################ $*"; }
sub_member() { # $1=ケース名 → submodule の作業リポジトリを移行し、移行の前に clone していたメンバーが pull した状態を作る
  local S4="$W/cases/$1src"
  verif_fresh_dir "$NAME/cases/$1src"
  git init -q --bare -b main "$S4/work.git" || verif_die "work.git"
  git clone -q "$S4/work.git" "$S4/w0" 2>/dev/null
  ( verif_enter_repo "$S4/w0"; echo w > README.md && git add -A && git commit -qm init && git -c protocol.file.allow=always submodule add -q "$W_W/shared.git" .claude && git commit -qm "submodule" && git push -q origin main ) || verif_die "submodule の作業リポ"
  mk "$1"; ( verif_under_root "$W/cases/$1" && rm -rf "$W/cases/$1" ) || verif_die "消せない"
  ( verif_cd "$W/cases"; git -c protocol.file.allow=always clone -q --recurse-submodules "$S4/work.git" "$1" 2>/dev/null ) || verif_die "member clone"
  echo '{"p":1}' > "$W/cases/$1/.claude/settings.local.json"
  [ -n "${2:-}" ] && echo "手元の編集" >> "$W/cases/$1/.claude/CLAUDE.md"
  ( verif_enter_repo "$S4/w0"; git submodule deinit -q -f .claude && git rm -q -f .claude && rm -rf .git/modules/.claude && printf '.claude/\n' > .gitignore && git add .gitignore && git commit -qm "移行" && git push -q origin main ) || verif_die "移行"
  ( verif_enter_repo "$W/cases/$1"; git pull -q 2>&1 | sed 's/^/    pull| /' )
  launcher_for "$W_W/shared.git" "$W/launcher-original.ps1" > "$W/cases/$1/start_claude_code.ps1"
}

if want t01; then
  hdr "T01 「中身がありますが、共有リポのクローンではありません」→ 個人のファイルを退避し、.claude を .claude.old へ移して、同じ -Branch で起動し直す → 個人のファイルを戻す"
  mk t01; mkdir -p "$W/cases/t01/.claude/rules"; echo old > "$W/cases/t01/.claude/rules/old.md"; echo '{"p":1}' > "$W/cases/t01/.claude/settings.local.json"
  run t01 -Branch java/design
  mpw t01 "New-Item -ItemType Directory -Force ..\\t01-personal | Out-Null; Copy-Item .claude\\settings.local.json ..\\t01-personal\\; Move-Item .claude .claude.old"
  run t01 -Branch java/design; st t01
  mpw t01 "Copy-Item ..\\t01-personal\\settings.local.json .claude\\"
  run t01 -Branch java/design; st t01
  mpw t01 "Move-Item .claude.old ..\\t01-claude.old"; st t01
fi

if want t02; then
  hdr "T02 「clone に失敗」＋ Remote branch not found → -Branch の綴りを直して起動し直す"
  mk t02; run t02 -Branch java/desing; echo "    .claude: $( [ -e "$W/cases/t02/.claude" ] && echo ある || echo 無い )"
  run t02 -Branch java/design; st t02
fi

if want t03; then
  hdr "T03 「clone に失敗」＋ does not appear to be a git repository → メンテナーが URL を確かめる（\$SharedUrl を正しい値にしたランチャーに差し替える）"
  mk t03 "$W_W/nonexistent.git"; run t03; echo "    .claude: $( [ -e "$W/cases/t03/.claude" ] && echo ある || echo 無い )"
  launcher_for "$W_W/shared.git" "$W/launcher-original.ps1" > "$W/cases/t03/start_claude_code.ps1"
  run t03; st t03
fi

if want t04; then
  hdr "T04 submodule から移った作業リポジトリで、メンバーが §7-3 の手順 1 を自分で実行して壊した →「git リポジトリとして読めません」→ §7-3 のメンバーの手順を字面どおりに"
  sub_member t04
  echo "  -- メンバーが手順 1 を自分で実行する（壊す）"
  ( verif_enter_repo "$W/cases/t04"; git submodule deinit -f .claude > /dev/null 2>&1; git rm -q -f .claude > /dev/null 2>&1; rm -rf .git/modules/.claude )
  run t04
  mpw t04 "git -C .claude status --porcelain"
  mpw t04 "New-Item -ItemType Directory -Force ..\\t04-personal | Out-Null; Copy-Item .claude\\settings.local.json ..\\t04-personal\\"
  mpw t04 "Remove-Item -Recurse -Force .claude, .git\\modules\\.claude"
  echo "    .claude: $( [ -e "$W/cases/t04/.claude" ] && echo 残っている || echo 消えた )"
  run t04; st t04
fi

if want t04b; then
  hdr "T04b submodule から移った作業リポジトリで、submodule の中の CLAUDE.md を手元で編集していたメンバー（手順 1 は実行していない）→ status で確かめ、出たものを外へ写し、.claude と .git/modules/.claude を消す"
  sub_member t04b edit
  run t04b
  mpw t04b "git -C .claude status --porcelain"
  mpw t04b "New-Item -ItemType Directory -Force ..\\t04b-keep | Out-Null; Copy-Item .claude\\CLAUDE.md, .claude\\settings.local.json ..\\t04b-keep\\"
  mpw t04b "Remove-Item -Recurse -Force .claude, .git\\modules\\.claude"
  echo "    .claude: $( [ -e "$W/cases/t04b/.claude" ] && echo 残っている || echo 消えた ) ／ .git/modules/.claude: $( [ -e "$W/cases/t04b/.git/modules/.claude" ] && echo 残っている || echo 消えた )"
  run t04b; st t04b
  mpw t04b "Copy-Item ..\\t04b-keep\\settings.local.json .claude\\"; run t04b
fi

if want t04c; then
  hdr "T04c T04 と同じ壊れ方で、個人のファイルを外へ写し、.claude だけを消してから起動し直す → 個人のファイルを戻す"
  sub_member t04c
  ( verif_enter_repo "$W/cases/t04c"; git submodule deinit -f .claude > /dev/null 2>&1; git rm -q -f .claude > /dev/null 2>&1; rm -rf .git/modules/.claude )
  run t04c
  mpw t04c "New-Item -ItemType Directory -Force ..\\t04c-personal | Out-Null; Copy-Item .claude\\settings.local.json ..\\t04c-personal\\; Remove-Item -Recurse -Force .claude"
  run t04c; st t04c
  mpw t04c "Copy-Item ..\\t04c-personal\\settings.local.json .claude\\"; run t04c
fi

if want t06; then
  hdr "T06 「ローカル変更があります」＋ ' M'・'??'（自分で作った・直したもの）→ 外へ写してから相談 → もう一度起動すると"
  clone_ok t06; echo x >> "$W/cases/t06/.claude/CLAUDE.md"; echo memo > "$W/cases/t06/.claude/memo.md"
  run t06
  mpw t06 "New-Item -ItemType Directory -Force ..\\t06-keep | Out-Null; Copy-Item .claude\\CLAUDE.md, .claude\\memo.md ..\\t06-keep\\"
  echo "  -- 写しただけで、もう一度起動"; run t06
  clone_ok t06b; echo x >> "$W/cases/t06b/.claude/CLAUDE.md"; echo memo > "$W/cases/t06b/.claude/memo.md"; echo '{"p":1}' > "$W/cases/t06b/.claude/settings.local.json"
  echo "  -- 要らないと分かった後: 個人のファイルを退避し、.claude を消して起動し直す"
  mpw t06b "New-Item -ItemType Directory -Force ..\\t06b-keep | Out-Null; Copy-Item .claude\\settings.local.json, .claude\\CLAUDE.md, .claude\\memo.md ..\\t06b-keep\\; Remove-Item -Recurse -Force .claude"
  run t06b; st t06b
fi

if want t07; then
  hdr "T07 「ローカル変更があります」＋ '?? agent-memory/'（main を使うメンバー）→ メンテナーが main の .gitignore に足す → もう一度 → 外へ移して起動 → 戻す"
  clone_ok t07; mkdir -p "$W/cases/t07/.claude/agent-memory/reviewer"; echo m > "$W/cases/t07/.claude/agent-memory/reviewer/MEMORY.md"
  run t07
  maint 'git switch -q main && git pull -q && printf "agent-memory/\nworktrees/\n" >> .gitignore && git commit -qam "ignore agent-memory/ worktrees/" && git push -q origin main'
  echo "  （メンテナー: main の .gitignore に agent-memory/・worktrees/ を足して push）"
  run t07
  mpw t07 "Move-Item .claude\\agent-memory ..\\t07-agent-memory"; run t07
  mpw t07 "Move-Item ..\\t07-agent-memory .claude\\agent-memory"; run t07; st t07
  echo "    MEMORY.md: $(cat "$W/cases/t07/.claude/agent-memory/reviewer/MEMORY.md" 2>/dev/null || echo 無い)"
fi

if want t07b; then
  hdr "T07b 同じで、java/design を使うメンバー。メンテナーが main に足しただけ（定常手順の前）→ 移して起動・戻す → 定常手順の後"
  maint 'git switch -q main && git pull -q && { grep -qx "agent-memory/" .gitignore || { printf "agent-memory/\nworktrees/\n" >> .gitignore && git commit -qam "ignore agent-memory/ worktrees/" && git push -q origin main; }; }'
  echo "    main の .gitignore: [$(MSYS2_ARG_CONV_EXCL="*" git -C "$W/shared.git" show main:.gitignore | tr '\n' ' ')] ／ java/design の .gitignore: [$(MSYS2_ARG_CONV_EXCL="*" git -C "$W/shared.git" show java/design:.gitignore | tr '\n' ' ')]"
  clone_ok t07b; in_repo "$W/cases/t07b/.claude" switch -q java/design
  mkdir -p "$W/cases/t07b/.claude/agent-memory/reviewer"; echo m > "$W/cases/t07b/.claude/agent-memory/reviewer/MEMORY.md"
  run t07b -Branch java/design
  mpw t07b "Move-Item .claude\\agent-memory ..\\t07b-agent-memory"; run t07b -Branch java/design
  mpw t07b "Move-Item ..\\t07b-agent-memory .claude\\agent-memory"; run t07b -Branch java/design
  echo "  （メンテナー: 定常手順の代わりに、java/base・java/design を main の上へ rebase して force-push）"
  maint 'git fetch -q origin && git switch -q java/design && git reset -q --hard origin/java/design && git branch -q -f java/base origin/java/base && git -c rebase.updateRefs=true rebase -q origin/main && git push -q --force-with-lease=java/base:$(git rev-parse origin/java/base) --force-with-lease=java/design:$(git rev-parse origin/java/design) origin java/base java/design'
  echo "    java/design の .gitignore（後）: [$(MSYS2_ARG_CONV_EXCL="*" git -C "$W/shared.git" show java/design:.gitignore | tr '\n' ' ')]"
  run t07b -Branch java/design
  mpw t07b "Move-Item .claude\\agent-memory ..\\t07b-agent-memory"; run t07b -Branch java/design
  mpw t07b "Move-Item ..\\t07b-agent-memory .claude\\agent-memory"; run t07b -Branch java/design; st t07b
  maint 'git switch -q main'
fi

if want t07w; then
  hdr "T07w '?? worktrees/'（作業リポジトリの git worktree add で .claude/worktrees/ の下に置いた。Claude Code が作る worktree の代わり）"
  maint 'git switch -q main && git pull -q && { grep -qx "worktrees/" .gitignore || { printf "agent-memory/\nworktrees/\n" >> .gitignore && git commit -qam "ignore agent-memory/ worktrees/" && git push -q origin main; }; }'
  echo "    main の .gitignore（今）: [$(MSYS2_ARG_CONV_EXCL="*" git -C "$W/shared.git" show main:.gitignore | tr '\n' ' ')]"
  echo "  -- (1) .gitignore に worktrees/ が入っていない python/base で"
  clone_ok t07w; in_repo "$W/cases/t07w/.claude" switch -q python/base
  in_repo "$W/cases/t07w" worktree add -q -b wt1 .claude/worktrees/wt1
  run t07w -Branch python/base
  mpw t07w "Move-Item .claude\\worktrees ..\\t07w-worktrees"
  echo "    移した後の git worktree list: $(git -C "$W/cases/t07w" worktree list --porcelain | grep -c prunable) 件が prunable"
  run t07w -Branch python/base
  mpw t07w "Move-Item ..\\t07w-worktrees .claude\\worktrees"
  echo "    戻した後: worktree list の prunable $(git -C "$W/cases/t07w" worktree list --porcelain | grep -c prunable) 件 ／ wt1 の status: $(git -C "$W/cases/t07w/.claude/worktrees/wt1" status --short --branch 2>&1 | head -1)"
  run t07w -Branch python/base
  echo "  -- (2) .gitignore に worktrees/ が入っている main で"
  clone_ok t07w2; in_repo "$W/cases/t07w2" worktree add -q -b wt1 .claude/worktrees/wt1
  echo "    .claude の status --porcelain: [$(git -C "$W/cases/t07w2/.claude" status --porcelain | tr '\n' ' ')]"
  run t07w2; st t07w2
  echo "  -- (3) .gitignore に agent-memory/ が入っている main で agent-memory を書いた"
  clone_ok t07i; mkdir -p "$W/cases/t07i/.claude/agent-memory/r"; echo m > "$W/cases/t07i/.claude/agent-memory/r/MEMORY.md"; run t07i; st t07i
fi

if want t07r; then
  hdr "T07r 外へ移して起動した後、戻す先に同じ名前の agent-memory/ が作り直されていたとき（使っている間に Claude Code が書いたものとする）"
  maint 'git switch -q main && git pull -q && { grep -qx "agent-memory/" .gitignore || { printf "agent-memory/\nworktrees/\n" >> .gitignore && git commit -qam "ignore agent-memory/ worktrees/" && git push -q origin main; }; }'
  echo "  -- (1) ディレクトリごとの Move-Item で戻す"
  clone_ok t07r; mkdir -p "$W/cases/t07r-out/agent-memory/reviewer"; echo 古いメモ > "$W/cases/t07r-out/agent-memory/reviewer/MEMORY.md"
  mkdir -p "$W/cases/t07r/.claude/agent-memory/reviewer"; echo 新しいメモ > "$W/cases/t07r/.claude/agent-memory/reviewer/MEMORY.md"
  mpw t07r "Move-Item ..\\t07r-out\\agent-memory .claude\\agent-memory"; tree_am t07r; run t07r
  echo "  -- (2) 中身だけを Move-Item で戻す（名前がぶつからない: 外は reviewer/、中は other/）"
  clone_ok t07s; mkdir -p "$W/cases/t07s-out/agent-memory/reviewer"; echo 古いメモ > "$W/cases/t07s-out/agent-memory/reviewer/MEMORY.md"
  mkdir -p "$W/cases/t07s/.claude/agent-memory/other"; echo 新しいメモ > "$W/cases/t07s/.claude/agent-memory/other/MEMORY.md"
  mpw t07s "Move-Item ..\\t07s-out\\agent-memory\\* .claude\\agent-memory\\"; tree_am t07s; run t07s
  echo "  -- (3) 中身だけを Move-Item で戻す（名前がぶつかる: 外も中も reviewer/）"
  clone_ok t07u; mkdir -p "$W/cases/t07u-out/agent-memory/reviewer"; echo 古いメモ > "$W/cases/t07u-out/agent-memory/reviewer/MEMORY.md"; echo 古いだけのメモ > "$W/cases/t07u-out/agent-memory/reviewer/notes.md"
  mkdir -p "$W/cases/t07u/.claude/agent-memory/reviewer"; echo 新しいメモ > "$W/cases/t07u/.claude/agent-memory/reviewer/MEMORY.md"
  mpw t07u "Move-Item ..\\t07u-out\\agent-memory\\* .claude\\agent-memory\\"; tree_am t07u
  echo "    外に残ったもの: $(cd "$W/cases/t07u-out" && find . -type f | sort | tr '\n' ' ')"
  run t07u
fi

if want t08; then
  hdr "T08 改名（java → java/base）の後: 1 回目「切替に失敗」（cannot lock ref）→ 2 回目「ローカル変更」（D/A）→ 個人のファイルを退避し、.claude を消して、同じ -Branch で起動し直す"
  git init -q --bare -b main "$W/shared2.git" || verif_die "shared2"
  git clone -q "$W/shared2.git" "$W/maint2" 2>/dev/null
  ( verif_enter_repo "$W/maint2"; printf 'settings.local.json\n' > .gitignore; echo m > CLAUDE.md; git add -A && git commit -qm main && git push -q origin main && git switch -qc java && echo j > j.md && git add -A && git commit -qm java && git push -q origin java ) || verif_die "shared2"
  for c in t08 t08c; do
    src="$W/launcher-original.ps1"; [ $c = t08c ] && src="$W/launcher-check.ps1"
    mk $c "$W_W/shared2.git" "$src"; git clone -q "$W/shared2.git" "$W/cases/$c/.claude" 2>/dev/null; in_repo "$W/cases/$c/.claude" switch -q java
    echo '{"p":1}' > "$W/cases/$c/.claude/settings.local.json"
  done
  ( verif_enter_repo "$W/maint2"; git switch -q main && git push -q origin --delete java && git branch -q -D java && git switch -qc java/base && echo jb > jb.md && git add -A && git commit -qm java/base && git push -q origin java/base ) || verif_die "改名"
  run t08 -Branch java/base; run t08 -Branch java/base
  mpw t08 "New-Item -ItemType Directory -Force ..\\t08-personal | Out-Null; Copy-Item .claude\\settings.local.json ..\\t08-personal\\; Remove-Item -Recurse -Force .claude"
  echo "    .claude: $( [ -e "$W/cases/t08/.claude" ] && echo 残っている || echo 消えた )"
  run t08 -Branch java/base; st t08
  mpw t08 "Copy-Item ..\\t08-personal\\settings.local.json .claude\\"; run t08 -Branch java/base
  echo "  -- 3-a' を足した版（launcher-example-check.ps1）で、表示の「.claude.old へ移して」のとおりに"
  run t08c -Branch java/base
  mpw t08c "Move-Item .claude ..\\t08c-claude.old"; run t08c -Branch java/base; st t08c
fi

if want t09; then
  hdr "T09 fetch に失敗（止まらない）→ ネットワークが戻ったら、同じ -Branch で起動し直す（共有リポの名前を一時的に変えてネットワークの不通の代わりにする）"
  clone_ok t09; in_repo "$W/cases/t09/.claude" switch -q java/base
  maint 'git switch -q java/base && git pull -q && echo j2 >> rules/java.md && git commit -qam "java/base 追記" && git push -q origin java/base'
  mv "$W/shared.git" "$W/shared.git.off" || verif_die "mv"
  run t09 -Branch java/base
  mv "$W/shared.git.off" "$W/shared.git" || verif_die "mv"
  run t09 -Branch java/base; echo "    java 追記が届いたか: $(grep -c j2 "$W/cases/t09/.claude/rules/java.md") 件"
  maint 'git switch -q main'
fi

if want t10; then
  hdr "T10 「切替に失敗」＋ invalid reference → 綴り（大文字小文字も）を確かめて起動し直す"
  clone_ok t10; run t10 -Branch java/desing; run t10 -Branch java/design; st t10
  clone_ok t10c; run t10c -Branch Java/Design; run t10c -Branch java/design; st t10c
  echo "  -- 消されたブランチ（合っていればメンテナーへ）: メンテナーが python/old を消した → 代わりの名前を聞いて起動し直す"
  maint 'git switch -qc python/old main && git push -q origin python/old && git switch -q main'; in_bare "$W/shared.git" branch -q -D python/old
  clone_ok t10d; run t10d -Branch python/old; run t10d -Branch python/base; st t10d
fi

if want t12; then
  hdr "T12 「切替に失敗」＋ index.lock → 使っていなければ .claude\\.git\\index.lock を消して起動し直す"
  clone_ok t12; : > "$W/cases/t12/.claude/.git/index.lock"; run t12 -Branch java/design
  mpw t12 "Remove-Item .claude\\.git\\index.lock"; run t12 -Branch java/design; st t12
  clone_ok t12b; : > "$W/cases/t12b/.claude/.git/index.lock"; run t12b
  mpw t12b "Remove-Item .claude\\.git\\index.lock"; run t12b; st t12b
fi

if want t13; then
  hdr "T13 「切替に失敗」＋ a branch is expected, got remote branch → origin/ を外して起動し直す"
  clone_ok t13; run t13 -Branch origin/java/design; run t13 -Branch java/design; st t13
fi

if want t14; then
  hdr "T14 「現在のブランチ … が指定 '-' と一致しません」→ 名前をそのまま書いて起動し直す"
  clone_ok t14; in_repo "$W/cases/t14/.claude" switch -q java/design; in_repo "$W/cases/t14/.claude" switch -q main
  run t14 -Branch -; st t14; run t14 -Branch main; st t14
fi

if want t15; then
  hdr "T15 「reset --hard に失敗」＋ ambiguous argument → 正しい名前で起動し直す"
  clone_ok t15; in_repo "$W/cases/t15/.claude" switch -q python/base
  maint 'git switch -qc python/tmp main && git push -q origin python/tmp && git switch -q main'
  in_repo "$W/cases/t15/.claude" fetch -q origin; in_repo "$W/cases/t15/.claude" switch -q python/tmp
  in_bare "$W/shared.git" branch -q -D python/tmp
  run t15 -Branch python/tmp; run t15 -Branch python/base; st t15
  echo "    手元に残った python/tmp: $(git -C "$W/cases/t15/.claude" branch --format='%(refname:short) %(upstream:track)' | grep python/tmp)"
  clone_ok t15m; in_repo "$W/cases/t15m/.claude" branch -q mine; run t15m -Branch mine; run t15m -Branch java/base; st t15m
  clone_ok t15n; in_repo "$W/cases/t15n/.claude" switch -q java/design; in_repo "$W/cases/t15n/.claude" switch -q main
  run t15n -Branch Java/Design; run t15n -Branch java/design; st t15n
fi

if want t16; then
  hdr "T16 「切り替えました: java/design → main」（止まらない）→ -Branch を付けて起動し直す"
  clone_ok t16; in_repo "$W/cases/t16/.claude" switch -q java/design
  run t16 -Branch=java/design; run t16 -Branch java/design; st t16
fi

if want t17; then
  hdr "T17 5.1 の実行ポリシー（Restricted）で実行されない → 未決の選択の (b)・(c) の形で起動する（(a) Set-ExecutionPolicy は端末の設定を変えるので実行しない。(c) は .cmd を介さずに直接呼ぶ）"
  clone_ok t17
  echo "    powershell.exe の実行ポリシー（PSExecutionPolicyPreference を外した後）: $(env -u PSExecutionPolicyPreference powershell.exe -NoProfile -Command 'Get-ExecutionPolicy' | tr -d '\r')"
  ( verif_cd "$W/cases/t17"
    echo "  \$ powershell.exe -File start_claude_code.ps1"; env -u PSExecutionPolicyPreference powershell.exe -NoProfile -File "$(verif_winpath .)/start_claude_code.ps1" 2>&1 | tr -d '\r' | head -3 | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}"
    echo "  \$ (c) powershell.exe -ExecutionPolicy Bypass -File start_claude_code.ps1"; env -u PSExecutionPolicyPreference powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(verif_winpath .)/start_claude_code.ps1" 2>&1 | tr -d '\r' | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}"
    echo "  \$ (b) pwsh -File start_claude_code.ps1"; env -u PSExecutionPolicyPreference pwsh -NoProfile -File "$(verif_winpath .)/start_claude_code.ps1" 2>&1 | tr -d '\r' | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}" )
fi

if want t18; then
  hdr "T18 5.1 で BOM なしのランチャーが構文エラー → メンテナーが BOM 付きで配り直す"
  clone_ok t18
  tail -c +4 "$W/cases/t18/start_claude_code.ps1" > "$W/cases/t18/s.tmp" && mv "$W/cases/t18/s.tmp" "$W/cases/t18/start_claude_code.ps1"   # BOM を外す
  ( verif_cd "$W/cases/t18"; echo "  \$ powershell.exe（BOM なし）"; powershell.exe -NoProfile -Command "& '$(verif_winpath .)/start_claude_code.ps1'; $VERIF_PS_EXIT" 2>&1 | tr -d '\r' | head -2 | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}" )
  { printf '\357\273\277'; cat "$W/cases/t18/start_claude_code.ps1"; } > "$W/cases/t18/s.tmp" && mv "$W/cases/t18/s.tmp" "$W/cases/t18/start_claude_code.ps1"
  ( verif_cd "$W/cases/t18"; echo "  \$ powershell.exe（BOM 付きで配り直した後）"; powershell.exe -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & '$(verif_winpath .)/start_claude_code.ps1'; $VERIF_PS_EXIT" 2>&1 | tr -d '\r' | sed 's/^/    | /'; echo "    → 終了コード ${PIPESTATUS[0]}" )
fi

if want m73; then
  hdr "M73 §7-3: 通常のディレクトリから移った作業リポジトリで、手元で .claude/CLAUDE.md を編集していたメンバー → 外へ写し、git checkout -- .claude で戻してから pull → ランチャー"
  verif_fresh_dir "$NAME/cases/m73src"; S7="$W/cases/m73src"
  git init -q --bare -b main "$S7/work.git"; git clone -q "$S7/work.git" "$S7/w0" 2>/dev/null
  ( verif_enter_repo "$S7/w0"; mkdir .claude && echo "旧 CLAUDE" > .claude/CLAUDE.md && printf 'settings.local.json\n' > .gitignore && git add -A && git commit -qm init && git push -q origin main ) || verif_die "w0"
  ( verif_cd "$W/cases"; git clone -q "$S7/work.git" m73 ) || verif_die "member clone"
  echo "手元の編集" >> "$W/cases/m73/.claude/CLAUDE.md"; echo '{"p":1}' > "$W/cases/m73/.claude/settings.local.json"
  launcher_for "$W_W/shared.git" "$W/launcher-original.ps1" > "$S7/w0/start_claude_code.ps1"   # BOM 付きで commit する
  ( verif_enter_repo "$S7/w0"; mv .claude .claude.bak && git rm -q -r --cached .claude && printf '.claude/\n.claude.bak/\n' > .gitignore && git add .gitignore start_claude_code.ps1 && git commit -qm "移行" && git push -q origin main ) || verif_die "移行"
  ( verif_enter_repo "$W/cases/m73"; git pull -q 2>&1 | sed 's/^/    pull| /'; echo "    pull の終了コード ${PIPESTATUS[0]}" )
  mpw m73 "New-Item -ItemType Directory -Force ..\\m73-keep | Out-Null; Copy-Item .claude\\CLAUDE.md, .claude\\settings.local.json ..\\m73-keep\\; git checkout -- .claude"
  ( verif_enter_repo "$W/cases/m73"; git pull -q 2>&1 | sed 's/^/    pull| /'; echo "    pull の終了コード ${PIPESTATUS[0]}"; echo "    .claude の中身: $(cd .claude 2>/dev/null && ls -A | tr '\n' ' ')" )
  run m73
  mpw m73 "Move-Item .claude .claude.old"; run m73; st m73
fi
echo; echo "######## 終了 ########"
