#!/usr/bin/env bash
# 本紙 §7-3 の移行（submodule の .claude/ を、gitignore した入れ子クローンへ置き換える）を本文どおりに通し、
# 移行の commit を pull したほかのメンバーの .claude/ に何が起きるかを測る。claude は起動しない。
#
#   bash migrate-submodule.sh        足場は $VERIF_ROOT/migrate
#
# 場面:
#   移行担当 a   §7-3 手順 1（submodule の場合）→ 2 → 4 を本文どおりに実行し、作業リポの git status を見る
#   メンバー b   作業リポを pull しただけで、ランチャーを実行する
#   メンバー c   pull の後、§7-3 手順 1（submodule の場合）を自分でも実行し、ランチャーを実行する
#   メンバー d   pull の後、ローカル変更が無いことを確かめ、.claude/ と .git/modules/.claude を消してからランチャーを実行する
#   参考 a2・e   通常のディレクトリ（作業リポが追跡）の場合。移行担当 a2 が §7-3 手順 1（通常のディレクトリ）→ 2 → 4 を実行し、
#                追跡していない settings.local.json を持つメンバー e が pull してランチャーを実行する。
#                ランチャーが止まったら、表示のとおり .claude/ を .claude.old へ移して、もう一度実行する
# ランチャーは launcher-example.ps1（本紙 §5-6 の例と同じもの）から、$SharedUrl の行と末尾の
# `claude @ClaudeArgs` の 2 行だけを差し替えて使う（claude の代わりに .claude のブランチと git-dir を表示する）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
command -v pwsh >/dev/null || verif_die "pwsh が無い"

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
# ローカルのパスを submodule の URL に使うため（git 2.38.1 以降は既定で禁止）
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always

LAUNCHER_SRC="$VERIF_LIB_DIR/launcher-example.ps1"
[ -f "$LAUNCHER_SRC" ] || verif_die "ランチャー例が無い: $LAUNCHER_SRC"

verif_fresh_dir migrate
W="$VERIF_ROOT/migrate"
verif_cd "$W"
W_W="$(verif_winpath "$W")"

echo "######## migrate-submodule.sh $(date '+%Y-%m-%d %H:%M:%S %z') ／ $(git --version) ／ pwsh $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()') ########"

# ---- ランチャー（2 行だけ差し替え） ----
IFS= read -r CLAUDE_LINE <<'EOF'
Write-Output ("[起動] .claude のブランチ=" + (git -C $ClaudeDir rev-parse --abbrev-ref HEAD) + " / git-dir=" + (git -C $ClaudeDir rev-parse --absolute-git-dir))
EOF
put_launcher() { # $1=作業リポのディレクトリ
  awk -v u="\$SharedUrl = \"$W_W/shared.git\"" -v cl="$CLAUDE_LINE" '
    /^\$SharedUrl = / {print u; next}
    $0=="claude @ClaudeArgs" {print cl; next}
    {print}' "$LAUNCHER_SRC" > "$1/start_claude_code.ps1"
  [ "$(diff "$LAUNCHER_SRC" "$1/start_claude_code.ps1" | grep -c '^[<>]')" = 4 ] || verif_die "差し替えが 2 行ではない: $1"
}
run_launcher() { # $1=作業リポのディレクトリ
  echo "  ランチャーを実行:"
  pwsh -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; & '$(verif_winpath "$1")/start_claude_code.ps1'; $VERIF_PS_EXIT" 2>&1 | sed 's/^/    | /'
  echo "    → 終了コード ${PIPESTATUS[0]}"
}
# VERIF_ROOT の下のパスだけを消す
rm_under_root() {
  local p
  for p in "$@"; do
    [ -e "$p" ] || continue
    verif_under_root "$p" || verif_die "VERIF_ROOT の外は消さない: $p"
    rm -rf "$p"
  done
}
state() { # 起動ディレクトリ（作業リポのトップ）で、.claude の状態を表示する
  echo "  .claude: $( [ -e .claude ] && echo ある || echo 無い ) ／ .claude/.git: $( [ -f .claude/.git ] && echo "ファイル（$(cat .claude/.git)）" || { [ -d .claude/.git ] && echo ディレクトリ || echo 無い; } )"
  echo "  .git/modules/.claude: $( [ -d .git/modules/.claude ] && echo ある || echo 無い )"
  # .claude/.git が無いと、git -C .claude は外側の作業リポを見てしまうので、そのときは表示しない
  if [ -e .claude/.git ]; then
    echo "  .claude の HEAD: $(git -C .claude rev-parse --abbrev-ref HEAD 2>&1 | head -1)"
  else
    echo "  .claude の HEAD: （.claude/.git が無い）"
  fi
  echo "  作業リポの git status --short: [$(git status --short | tr '\n' ' ')]"
}

# ---- 共有リポ（bare）と作業リポ（bare）。作業リポは .claude/ を submodule として持つ ----
git init -q --bare -b main shared.git || verif_die "shared.git を作れない"
git clone -q shared.git s 2>/dev/null || verif_die "s を作れない"
( verif_enter_repo "$W/s"
  echo shared > CLAUDE.md && git add -A && git commit -qm s && git push -q origin main ) || verif_die "共有リポの準備に失敗"
git init -q --bare -b main work.git || verif_die "work.git を作れない"
git clone -q work.git a 2>/dev/null || verif_die "a を作れない"
( verif_enter_repo "$W/a"
  echo root > CLAUDE.md && git add -A && git commit -qm init || exit 1
  git submodule add -q ../shared.git .claude || exit 1
  git commit -qm "submodule .claude" && git push -q origin main ) || verif_die "作業リポの準備に失敗"
for m in b c d; do
  git clone -q --recurse-submodules work.git "$m" 2>/dev/null || verif_die "$m を作れない"
done
( verif_enter_repo "$W/b"
  echo "=== 準備: メンバーのクローン（b・c・d は同じ形）の .claude/.git: $( [ -f .claude/.git ] && echo ファイル || echo ディレクトリ ) ／ HEAD=$(git -C .claude rev-parse --abbrev-ref HEAD)" )

echo
echo "=== 移行担当 a が §7-3 手順 1（submodule の場合）→ 2 → 4 を本文どおりに実行"
( verif_enter_repo "$W/a"
  git submodule deinit -f .claude 2>&1 | sed 's/^/  /'; echo "  deinit=${PIPESTATUS[0]}"
  git rm -f .claude 2>&1 | sed 's/^/  /'; echo "  rm=${PIPESTATUS[0]}"
  rm_under_root .git/modules/.claude
  git commit -qm "chore: .claude の submodule 登録を解除"; echo "  commit=$?"
  echo "  手順 1 の後: .claude=$( [ -e .claude ] && echo ある || echo 無い ) ／ .claude.bak=$( [ -e .claude.bak ] && echo ある || echo 無い ) ／ .gitmodules=$( [ -s .gitmodules ] && echo 中身あり || echo 空か無し )"
  printf '.claude/\n' >> .gitignore && git add .gitignore && git commit -qm "ignore .claude/"; echo "  手順 2 commit=$?"
  git clone -q --branch main ../shared.git .claude 2>/dev/null; echo "  手順 4 clone=$?"
  echo "  a の作業リポの git status --short: [$(git status --short | tr '\n' ' ')]"
  git push -q origin main; echo "  push=$?" ) || verif_die "移行担当の段で中断"

echo
echo "=== メンバー b: 作業リポを pull しただけ"
( verif_enter_repo "$W/b"
  git pull -q 2>&1 | sed 's/^/  /'; echo "  pull=${PIPESTATUS[0]}"
  state
  put_launcher "$W/b"
  run_launcher "$W/b"
  echo "  ランチャーの後の作業リポの git status --short: [$(git status --short | tr '\n' ' ')]" )

echo
echo "=== メンバー c: pull の後、§7-3 手順 1（submodule の場合）を自分でも実行"
( verif_enter_repo "$W/c"
  git pull -q 2>&1 | sed 's/^/  /'; echo "  pull=${PIPESTATUS[0]}"
  git submodule deinit -f .claude 2>&1 | sed 's/^/  /'; echo "  deinit=${PIPESTATUS[0]}"
  git rm -f .claude 2>&1 | sed 's/^/  /'; echo "  rm=${PIPESTATUS[0]}"
  rm_under_root .git/modules/.claude; echo "  rm -rf .git/modules/.claude: 実行した"
  state
  put_launcher "$W/c"
  run_launcher "$W/c" )

echo
echo "=== メンバー d: pull の後、ローカル変更が無いことを確かめ、.claude/ と .git/modules/.claude を消してからランチャー"
( verif_enter_repo "$W/d"
  git pull -q 2>&1 | sed 's/^/  /'; echo "  pull=${PIPESTATUS[0]}"
  echo "  git -C .claude status --porcelain: [$(git -C .claude status --porcelain | tr '\n' ' ')]（終了コード ${PIPESTATUS[0]}）"
  rm_under_root .claude .git/modules/.claude
  state
  put_launcher "$W/d"
  run_launcher "$W/d"
  echo "  ランチャーの後:"
  state )

echo
echo "=== 参考 e: 通常のディレクトリ（作業リポが .claude/ を追跡）から移った作業リポを pull したメンバー"
git init -q --bare -b main work2.git || verif_die "work2.git を作れない"
git clone -q work2.git a2 2>/dev/null || verif_die "a2 を作れない"
( verif_enter_repo "$W/a2"
  mkdir .claude && echo "旧 .claude" > .claude/CLAUDE.md && echo root > CLAUDE.md && git add -A && git commit -qm init && git push -q origin main ) \
  || verif_die "work2 の準備に失敗"
git clone -q work2.git e 2>/dev/null || verif_die "e を作れない"
( verif_enter_repo "$W/e"; echo '{"p":1}' > .claude/settings.local.json
  echo "  e の準備: 追跡していない .claude/settings.local.json を置いた" )
echo "  移行担当 a2 が §7-3 手順 1（通常のディレクトリの場合）→ 2 → 4 を本文どおりに実行"
( verif_enter_repo "$W/a2"
  mv .claude .claude.bak || exit 1
  git rm -r -q --cached .claude; echo "  git rm -r --cached=$?"
  printf '.claude/\n.claude.bak/\n' >> .gitignore && git add .gitignore && git commit -qm "chore: .claude を gitignore" ; echo "  手順 1・2 commit=$?"
  git clone -q --branch main ../shared.git .claude 2>/dev/null; echo "  手順 4 clone=$?"
  echo "  a2 の作業リポの git status --short: [$(git status --short | tr '\n' ' ')]"
  git push -q origin main; echo "  push=$?" ) || verif_die "a2 の移行に失敗"
( verif_enter_repo "$W/e"
  git pull -q 2>&1 | sed 's/^/  /'; echo "  pull=${PIPESTATUS[0]}"
  echo "  e の .claude の中身: [$( [ -d .claude ] && (cd .claude && find . -type f | sort | tr '\n' ' ') )]"
  state
  put_launcher "$W/e"
  run_launcher "$W/e"
  echo "  ランチャーの後の .claude の中身: [$( [ -d .claude ] && (cd .claude && find . -type f | sort | tr '\n' ' ') )]"
  echo "  表示のとおり .claude/ を .claude.old へ移してから、ランチャーをもう一度実行:"
  mv .claude .claude.old || exit 1
  run_launcher "$W/e"
  echo "  .claude.old の中身: [$(cd .claude.old && find . -type f | sort | tr '\n' ' ')] ／ 作業リポの git status --short: [$(git status --short | tr '\n' ' ')]" )

echo
echo "######## 終了 ########"
