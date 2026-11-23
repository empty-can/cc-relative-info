#!/usr/bin/env bash
# §5-4 の定常手順（maintain-steady.sh）と、中間ブランチだけを更新したときの手順（maintain-middle.sh）を、
# 理想でない状態を足した足場で通す。対照として、前の形（control-*.sh）も同じ足場で通す。claude は起動しない。各場面は自分の足場（$VERIF_ROOT/sc-<場面>）を maintain-setup.sh で作る（毎回作り直すので、続けて何度実行してもよい）。
#   bash maintain-scenes.sh [場面...]   （既定は全部。場面の名前は下の ALL）
# 手順のスクリプトは、置き換える行（REPO・URL、または対照の cd の行）以外は 1 文字も変えずに使う（diff の行数で確かめる）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
S="$(cd "$(dirname "$0")" && pwd)" || verif_die "スクリプトの場所へ移れません"

# ---- 足場と手順のスクリプトの用意 ----
prep() { # $1=足場の名前 → maintain-setup.sh で作る（origin の main だけが PR #1 で進んだ状態）
  bash "$S/maintain-setup.sh" "$1" > /dev/null 2>&1 || verif_die "足場を作れない: $1"
}
# inst <手順のスクリプト> <クローン> <出力するファイル>: プレースホルダの行だけを差し替える
inst() {
  local src="$S/$1" repo="$2" out="$3" url n
  [ -d "$repo/.git" ] || verif_die "クローンが無い: $repo"
  verif_under_root "$repo" || verif_die "VERIF_ROOT の外: $repo"
  url="$(git -C "$repo" remote get-url origin)" || verif_die "origin が無い: $repo"
  local rw; rw="$(verif_winpath "$repo")"
  case "$1" in
    control-*-prev.sh)
      awk -v r="$rw" '$0=="cd \"<共有リポのパス>\" || exit 1" {print "cd \"" r "\" || exit 1"; next} {print}' "$src" > "$out"
      n=2 ;;
    *)
      awk -v r="$rw" -v u="$url" '
        $0=="REPO='"'"'<メンテナーのクローンのパス>'"'"'" {print "REPO='"'"'" r "'"'"'"; next}
        $0=="URL='"'"'<共有リポの URL>'"'"'"           {print "URL='"'"'" u "'"'"'"; next}
        {print}' "$src" > "$out"
      n=4 ;;
  esac
  [ "$(diff "$src" "$out" | grep -c '^[<>]')" = "$n" ] || verif_die "差し替えの行数が合わない: $1"
}
# runp <見出し> <足場> <クローン名> <スクリプト> <入力（\n 区切り。EOF なら空の stdin）> [スクリプトへの引数]
runp() {
  local label="$1" w="$VERIF_ROOT/$2" who="$3" scr="$4" input="$5"; shift 5
  local f="$w/run-$(basename "$scr" .sh).sh" rc
  inst "$scr" "$w/$who" "$f"
  echo "  \$ bash $(basename "$scr") $*  （stdin: $( [ "$input" = EOF ] && echo '/dev/null' || printf '%q' "$input")）"
  if [ "$input" = EOF ]; then
    bash "$f" "$@" < /dev/null 2>&1 | sed 's/^/    | /'; rc=${PIPESTATUS[0]}
  else
    printf '%b' "$input" | bash "$f" "$@" 2>&1 | sed 's/^/    | /'; rc=${PIPESTATUS[1]}
  fi
  echo "  #### [$label] 終了コード $rc"
  LAST_RC=$rc
}
ostate() { # origin の各ブランチの先頭と、main を含むか
  local w="$VERIF_ROOT/$1" b
  for b in $(git -C "$w/shared.git" for-each-ref --format='%(refname:short)' refs/heads/); do
    printf '    origin %-14s %s  main を含む: %s\n' "$b" "$(git -C "$w/shared.git" rev-parse --short "$b")" \
      "$(git -C "$w/shared.git" merge-base --is-ancestor main "$b" && echo YES || echo NO)"
  done
}
lstate() { # クローンのローカルの状態
  local d="$VERIF_ROOT/$1/$2"
  echo "    ローカル HEAD: $(git -C "$d" rev-parse --abbrev-ref HEAD) ／ rebase 中: $( [ -d "$d/.git/rebase-merge" ] || [ -d "$d/.git/rebase-apply" ] && echo はい || echo いいえ)"
  git -C "$d" for-each-ref --format='    local  %(refname:short) %(objectname:short)' refs/heads/
  git -C "$d" status --short | sed 's/^/    status: /'
}
# 別のクローン（x）で操作する
xdo() { # $1=足場 $2=クローン名 以降=bash のコード（クローンのトップで実行）
  local w="$VERIF_ROOT/$1" c="$2"; shift 2
  ( verif_cd "$w"; [ -d "$w/$c" ] || git clone -q shared.git "$c" 2>/dev/null || exit 1
    verif_enter_repo "$w/$c"; eval "$*" ) || verif_die "xdo に失敗: $1/$c: $*"
}
mdo() { # $1=足場 $2=クローン名 以降=bash のコード（メンテナーのクローンで）
  local w="$VERIF_ROOT/$1" c="$2"; shift 2
  ( verif_enter_repo "$w/$c"; eval "$*" ) || verif_die "mdo に失敗: $1/$c: $*"
}
hdr() { echo; echo "################ $*"; }
want() { case " ${SCENES[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

ALL=(s01 s02 s03 s06 s07 s08 s09 s09d s10 s11 s12 s12v s13 s14 s15 s16 s17 s18 s19 s20 m01 m02 m03 m04 m04d s21)
SCENES=("$@"); [ ${#SCENES[@]} -gt 0 ] || SCENES=("${ALL[@]}")
echo "######## maintain-scenes.sh $(date '+%Y-%m-%d %H:%M:%S %z') ／ $(git --version) ／ bash $BASH_VERSION ／ VERIF_ROOT=$VERIF_ROOT"

if want s01; then
  hdr "S01 基準: ローカルの main が古いまま（PR #1 の前）。対照（前の形）と maintain-steady.sh（y を入れる）"
  prep sc-s01o; runp "S01 対照（前の形）" sc-s01o m control-steady-prev.sh EOF; ostate sc-s01o
  prep sc-s01;  runp "S01 maintain-steady.sh y" sc-s01 m maintain-steady.sh 'y\n'; ostate sc-s01
  hdr "S06 続けてもう一度実行する（何も変わっていない）"
  runp "S06 2 回目 y" sc-s01 m maintain-steady.sh 'y\n'; ostate sc-s01
fi

if want s02; then
  hdr "S02 ③' で中止（n）→ push しない。続けて、もう一度実行して y"
  prep sc-s02; before=$(git -C "$VERIF_ROOT/sc-s02/shared.git" for-each-ref --format='%(objectname)' refs/heads/ | tr '\n' ' ')
  runp "S02 n" sc-s02 m maintain-steady.sh 'n\n'
  after=$(git -C "$VERIF_ROOT/sc-s02/shared.git" for-each-ref --format='%(objectname)' refs/heads/ | tr '\n' ' ')
  echo "    origin が変わっていないか: $( [ "$before" = "$after" ] && echo 変わっていない || echo 変わった )"; lstate sc-s02 m
  runp "S02b 中止の後にもう一度 y" sc-s02 m maintain-steady.sh 'y\n'; ostate sc-s02
fi

if want s03; then
  hdr "S03 ③' の入力が y 以外（yes・空行・EOF）→ どれも push しない。最後に y"
  prep sc-s03; before=$(git -C "$VERIF_ROOT/sc-s03/shared.git" for-each-ref --format='%(objectname)' refs/heads/ | tr '\n' ' ')
  runp "S03a yes" sc-s03 m maintain-steady.sh 'yes\n'
  runp "S03b 空行" sc-s03 m maintain-steady.sh '\n'
  runp "S03c EOF" sc-s03 m maintain-steady.sh EOF
  after=$(git -C "$VERIF_ROOT/sc-s03/shared.git" for-each-ref --format='%(objectname)' refs/heads/ | tr '\n' ' ')
  echo "    3 回の後、origin が変わっていないか: $( [ "$before" = "$after" ] && echo 変わっていない || echo 変わった )"
  runp "S03d y" sc-s03 m maintain-steady.sh 'y\n'; ostate sc-s03
fi

if want s07; then
  hdr "S07 無関係なローカルブランチ（旧い main の上の PR 用のブランチ topic/my-pr）がある"
  for v in o n; do prep sc-s07$v; mdo sc-s07$v m 'git branch topic/my-pr main'; done
  runp "S07 対照（前の形）" sc-s07o m control-steady-prev.sh EOF
  runp "S07 maintain-steady.sh y" sc-s07n m maintain-steady.sh 'y\n'; ostate sc-s07n
fi

if want s08; then
  hdr "S08 origin で消したブランチが手元に残る（java/old。旧い main の上）"
  for v in o n; do
    prep sc-s08$v
    xdo sc-s08$v x 'git push -q origin "origin/main~1:refs/heads/java/old"'
    mdo sc-s08$v m 'git fetch -q origin && git branch -q --track java/old origin/java/old'
    ( verif_enter_repo "$VERIF_ROOT/sc-s08$v/shared.git" bare; git branch -q -D java/old ) || verif_die "origin の java/old を消せない"
  done
  runp "S08 対照（前の形）" sc-s08o m control-steady-prev.sh EOF
  runp "S08 maintain-steady.sh y" sc-s08n m maintain-steady.sh 'y\n'; ostate sc-s08n
fi

if want s09; then
  hdr "S09 origin に、系列の一覧に無いブランチが増えた"
  echo "  (a) java/coding を、旧い java/base（main を含まない）から作った"
  for v in o n; do
    prep sc-s09a$v
    xdo sc-s09a$v x 'git switch -qc java/coding origin/java/base && echo c > rules/coding.md && git add -A && git commit -qm "java/coding" && git push -q origin java/coding'
  done
  runp "S09a 対照（前の形）" sc-s09ao m control-steady-prev.sh EOF; ostate sc-s09ao
  runp "S09a maintain-steady.sh y" sc-s09an m maintain-steady.sh 'y\n'; ostate sc-s09an
  echo "  (b) tools/x を、新しい origin/main から作った（main を含むが、main に取り込まれてはいない）"
  for v in o n; do
    prep sc-s09b$v
    xdo sc-s09b$v x 'git switch -qc tools/x origin/main && echo t > tools.md && git add -A && git commit -qm "tools/x" && git push -q origin tools/x'
  done
  runp "S09b 対照（前の形）" sc-s09bo m control-steady-prev.sh EOF
  runp "S09b maintain-steady.sh y" sc-s09bn m maintain-steady.sh 'y\n'
  echo "  (c) PR 用のブランチ pr/1 が origin に残っている（main に取り込み済み＝main の先祖）"
  for v in o n; do
    prep sc-s09c$v
    xdo sc-s09c$v x 'git push -q origin "origin/main:refs/heads/pr/1"'
  done
  runp "S09c 対照（前の形）" sc-s09co m control-steady-prev.sh EOF
  runp "S09c maintain-steady.sh y" sc-s09cn m maintain-steady.sh 'y\n'
fi

if want s10; then
  hdr "S10 系列の一覧にある python/coding が origin に無い（origin で消した。手元には残る）"
  for v in o n; do prep sc-s10$v; ( verif_enter_repo "$VERIF_ROOT/sc-s10$v/shared.git" bare; git branch -q -D python/coding ) || verif_die "消せない"; done
  runp "S10 対照（前の形）" sc-s10o m control-steady-prev.sh EOF
  runp "S10 maintain-steady.sh y" sc-s10n m maintain-steady.sh 'y\n'; lstate sc-s10n m
fi

if want s11; then
  hdr "S11 作業ツリーに commit していない変更がある"
  echo "  (a) main にいて、どのブランチにもある CLAUDE.md を編集した"
  for v in o n; do prep sc-s11a$v; mdo sc-s11a$v m 'echo 手元の編集 >> CLAUDE.md'; done
  runp "S11a 対照（前の形）" sc-s11ao m control-steady-prev.sh EOF; lstate sc-s11ao m
  runp "S11a maintain-steady.sh y" sc-s11an m maintain-steady.sh 'y\n'; lstate sc-s11an m
  echo "  (b) java/base にいて、java 系列にしか無い rules/java.md を編集した"
  for v in o n; do prep sc-s11b$v; mdo sc-s11b$v m 'git switch -q java/base && echo 手元の編集 >> rules/java.md'; done
  runp "S11b 対照（前の形）" sc-s11bo m control-steady-prev.sh EOF; lstate sc-s11bo m
  runp "S11b maintain-steady.sh y" sc-s11bn m maintain-steady.sh 'y\n'
  echo "  (c) 未追跡のファイルだけがある（memo.txt）"
  prep sc-s11c; mdo sc-s11c m 'echo memo > memo.txt'
  runp "S11c maintain-steady.sh y" sc-s11c m maintain-steady.sh 'y\n'; lstate sc-s11c m
fi

if want s12; then
  hdr "S12 ② の rebase が衝突で止まる（java/design と main の PR #1 が、どちらも CLAUDE.md の末尾に足した）"
  for v in o n r; do
    prep sc-s12$v
    xdo sc-s12$v x 'git switch -q java/design && echo "design の追記" >> CLAUDE.md && git commit -qam "java/design: CLAUDE.md に追記" && git push -q origin java/design'
  done
  echo "  -- 対照（前の形）: 1 回目 → abort せずに 2 回目"
  runp "S12o 1 回目" sc-s12o m control-steady-prev.sh EOF; lstate sc-s12o m
  runp "S12o abort せずに 2 回目" sc-s12o m control-steady-prev.sh EOF; lstate sc-s12o m
  echo "  -- maintain-steady.sh: 1 回目 → abort せずに 2 回目 → abort → 状態 → 3 回目"
  runp "S12n 1 回目" sc-s12n m maintain-steady.sh 'y\n'
  echo "    衝突の時点: java/base=$(git -C "$VERIF_ROOT/sc-s12n/m" rev-parse --short java/base)（origin=$(git -C "$VERIF_ROOT/sc-s12n/m" rev-parse --short origin/java/base)）"
  lstate sc-s12n m
  runp "S12n abort せずに 2 回目" sc-s12n m maintain-steady.sh 'y\n'
  mdo sc-s12n m 'git rebase --abort'; echo "    git rebase --abort の後:"; lstate sc-s12n m
  echo "    origin と一致するか: java/base $( [ "$(git -C "$VERIF_ROOT/sc-s12n/m" rev-parse java/base)" = "$(git -C "$VERIF_ROOT/sc-s12n/m" rev-parse origin/java/base)" ] && echo 一致 || echo 不一致 ) ／ java/design $( [ "$(git -C "$VERIF_ROOT/sc-s12n/m" rev-parse java/design)" = "$(git -C "$VERIF_ROOT/sc-s12n/m" rev-parse origin/java/design)" ] && echo 一致 || echo 不一致 )"
  runp "S12n abort の後に 3 回目" sc-s12n m maintain-steady.sh 'y\n'
  mdo sc-s12n m 'git rebase --abort'
  echo "  -- 衝突を手で解いて continue した後に、もう一度実行する"
  runp "S12r 1 回目（衝突）" sc-s12r m maintain-steady.sh 'y\n'
  mdo sc-s12r m 'printf "main 初版\nmain 追記（PR #1）\ndesign の追記\n" > CLAUDE.md && git add CLAUDE.md && GIT_EDITOR=true git rebase --continue > /dev/null 2>&1'
  echo "    手で解いて continue した後:"; lstate sc-s12r m
  runp "S12r 解いた後に maintain-steady.sh" sc-s12r m maintain-steady.sh 'y\n'
  echo "  -- 選択肢: resume 付きの版（① を飛ばし、② の済んだブランチを飛ばす）"
  prep sc-s12s
  xdo sc-s12s x 'git switch -q java/design && echo "design の追記" >> CLAUDE.md && git commit -qam "java/design: CLAUDE.md に追記" && git push -q origin java/design'
  runp "S12s 1 回目（衝突）" sc-s12s m maintain-steady-resume.sh 'y\n'
  mdo sc-s12s m 'printf "main 初版\nmain 追記（PR #1）\ndesign の追記\n" > CLAUDE.md && git add CLAUDE.md && GIT_EDITOR=true git rebase --continue > /dev/null 2>&1'
  runp "S12s resume" sc-s12s m maintain-steady-resume.sh 'y\n' resume; ostate sc-s12s
  echo "    java/design の CLAUDE.md: $(git -C "$VERIF_ROOT/sc-s12s/shared.git" show java/design:CLAUDE.md | tr '\n' '|')"
  echo "    java/ut の CLAUDE.md: $(git -C "$VERIF_ROOT/sc-s12s/shared.git" show java/ut:CLAUDE.md | tr '\n' '|')"
  echo "  -- 選択肢の版: resume で、② の途中で別のメンテナーが push していた場合（lease で止まるはず）"
  prep sc-s12t
  xdo sc-s12t x 'git switch -q java/design && echo "design の追記" >> CLAUDE.md && git commit -qam "java/design: CLAUDE.md に追記" && git push -q origin java/design'
  runp "S12t 1 回目（衝突）" sc-s12t m maintain-steady-resume.sh 'y\n'
  mdo sc-s12t m 'printf "main 初版\nmain 追記（PR #1）\ndesign の追記\n" > CLAUDE.md && git add CLAUDE.md && GIT_EDITOR=true git rebase --continue > /dev/null 2>&1'
  xdo sc-s12t x 'git switch -q java/ut && echo 他 >> rules/ut.md && git commit -qam "java/ut: 他メンテナー" && git push -q origin java/ut'
  runp "S12t resume（間に他のメンテナーの push）" sc-s12t m maintain-steady-resume.sh 'y\n' resume
  echo "  -- 選択肢の版を、衝突の無い普通の場面と、2 回続けた場面で（resume なし）"
  prep sc-s12u
  runp "S12u 普通" sc-s12u m maintain-steady-resume.sh 'y\n'
  runp "S12u 2 回目" sc-s12u m maintain-steady-resume.sh 'y\n'; ostate sc-s12u
fi

if want s13; then
  hdr "S13 ③ と ④ の間（入力待ちの間）に、別のメンテナーが java/ut を push する → ④ が拒否 → もう一度実行"
  prep sc-s13
  W13="$VERIF_ROOT/sc-s13"; inst maintain-steady.sh "$W13/m" "$W13/run-maintain-steady.sh"
  xdo sc-s13 x 'true'
  out="$W13/s13.out"; : > "$out"
  echo "  \$ bash maintain-steady.sh  （stdin: 「③ の検査に合格した」が出るのを待ち、x から java/ut を push してから y）"
  ( n=0; until grep -q '③ の検査に合格した' "$out"; do sleep 0.2; n=$((n+1)); [ $n -lt 300 ] || exit 1; done
    xdo sc-s13 x 'git switch -q java/ut && echo 他メンテナーの追記 >> rules/ut.md && git commit -qam "java/ut: 他メンテナーの追記" && git push -q origin java/ut' >> "$out" 2>&1
    echo "（試験: 入力待ちの間に x が java/ut を push した）" >> "$out"; echo y ) | bash "$W13/run-maintain-steady.sh" >> "$out" 2>&1
  rc=${PIPESTATUS[1]}; sed 's/^/    | /' "$out"; echo "  #### [S13 割り込みあり] 終了コード $rc"
  echo "    origin の java/base は動いていないか（--atomic）: $(git -C "$W13/shared.git" log --oneline -1 java/base)"
  runp "S13b もう一度 y" sc-s13 m maintain-steady.sh 'y\n'
  echo "    他のメンテナーの追記は origin の java/ut に残ったか: $(git -C "$W13/shared.git" log --oneline java/ut | grep -c '他メンテナー') 件"; ostate sc-s13
fi

if want s14; then
  hdr "S14 メンテナーが別のブランチにいる・detached HEAD から始める"
  prep sc-s14a; mdo sc-s14a m 'git switch -q java/ut'
  runp "S14a java/ut にいる y" sc-s14a m maintain-steady.sh 'y\n'; ostate sc-s14a
  prep sc-s14b; mdo sc-s14b m 'git switch -q --detach HEAD~0'
  runp "S14b detached HEAD y" sc-s14b m maintain-steady.sh 'y\n'; ostate sc-s14b
fi

if want s15; then
  hdr "S15 main だけを持つ新しいクローン（git clone した直後）"
  prep sc-s15; ( verif_cd "$VERIF_ROOT/sc-s15"; git clone -q shared.git fresh ) || verif_die "clone"
  runp "S15 y" sc-s15 fresh maintain-steady.sh 'y\n'; ostate sc-s15
fi

if want s16; then
  hdr "S16 手元に、旧い命名のローカルブランチ java が残っている（D/F。origin には java/base など）"
  for v in o n; do prep sc-s16$v; ( verif_cd "$VERIF_ROOT/sc-s16$v"; git clone -q shared.git fresh ) || verif_die "clone"; mdo sc-s16$v fresh 'git branch -q java "origin/main~1"'; done
  runp "S16 対照（前の形）" sc-s16o fresh control-steady-prev.sh EOF
  runp "S16 maintain-steady.sh y" sc-s16n fresh maintain-steady.sh 'y\n'; lstate sc-s16n fresh
fi

if want s17; then
  hdr "S17 --single-branch で clone したクローン（origin/main しか取らない）"
  prep sc-s17; ( verif_cd "$VERIF_ROOT/sc-s17"; git clone -q --single-branch shared.git sb ) || verif_die "clone"
  runp "S17 maintain-steady.sh y" sc-s17 sb maintain-steady.sh 'y\n'
  echo "    sb の fetch の refspec: $(git -C "$VERIF_ROOT/sc-s17/sb" config --get-all remote.origin.fetch)"
fi

if want s18; then
  hdr "S18 push していないコミットがある（m2 の java/design）"
  prep sc-s18; mdo sc-s18 m2 'git switch -q java/design && echo 未push >> rules/design.md && git commit -qam "java/design: まだ push していない"'
  runp "S18 maintain-steady.sh y" sc-s18 m2 maintain-steady.sh 'y\n'
fi

if want s19; then
  hdr "S19 main にある資産を、既にある系列のブランチ（java/base）へ移す（§7-2 手順 2 は新しく切るブランチだけを書いている）"
  move_prep() { # $1=足場 → main に rules/move.md を足して全ブランチへ載せ、その後 PR で main から外す
    prep "$1"
    xdo "$1" pa 'mkdir -p rules && echo "移す資産" > rules/move.md && git add -A && git commit -qm "main: move.md" && git push -q origin main'
    inst maintain-steady.sh "$VERIF_ROOT/$1/m" "$VERIF_ROOT/$1/run-pre.sh"
    echo y | bash "$VERIF_ROOT/$1/run-pre.sh" > /dev/null 2>&1 || verif_die "定常手順に失敗: $1"
    xdo "$1" pb 'git rm -q rules/move.md && git commit -qm "main: move.md を外す（PR）" && git push -q origin main'
  }
  has_move() { for b in java/base java/design java/ut python/base; do printf '    origin %-12s rules/move.md: %s\n' "$b" "$(git -C "$VERIF_ROOT/$1/shared.git" cat-file -e "$b:rules/move.md" 2>/dev/null && echo ある || echo 無い)"; done; }
  echo "  (a) main から外した後に、そのまま定常手順を実行する"
  move_prep sc-s19a; has_move sc-s19a
  runp "S19a y" sc-s19a m maintain-steady.sh 'y\n'; has_move sc-s19a
  echo "  (b0) 定常手順の前に、origin の java/base へ足し直そうとする（java/base はまだ旧い main の上なので、資産は残っている）"
  move_prep sc-s19b
  ( verif_cd "$VERIF_ROOT/sc-s19b"; git clone -q shared.git pc ) || verif_die "clone pc"
  ( verif_enter_repo "$VERIF_ROOT/sc-s19b/pc"; git switch -q java/base && git checkout -q "origin/main~1" -- rules/move.md && git commit -qm "java/base: move.md を置く" 2>&1 | sed 's/^/    | /'; echo "    commit の終了コード: ${PIPESTATUS[0]}" )
  echo "  (b) 定常手順を先に通し（資産が java/* から消える）、その後に java/base へ足し直して push し、中間ブランチの手順で子へ届ける"
  runp "S19b 定常手順 y" sc-s19b m maintain-steady.sh 'y\n'; has_move sc-s19b
  xdo sc-s19b pc 'git fetch -q && git switch -q java/base && git reset -q --hard origin/java/base && git checkout -q "origin/main~1" -- rules/move.md && git commit -qm "java/base: move.md を置く" && git push -q origin java/base'
  runp "S19b 中間ブランチの手順 y" sc-s19b m maintain-middle.sh 'y\n'; has_move sc-s19b
  echo "  (c) 誤り: ③' の入力待ちの間に、m の java/base で足し直して commit し、そのまま y を入れる"
  move_prep sc-s19c
  W19="$VERIF_ROOT/sc-s19c"; inst control-steady-norecheck.sh "$W19/m" "$W19/run-norecheck.sh"; out="$W19/s19c.out"; : > "$out"
  ( n=0; until grep -q '③ の検査に合格した' "$out"; do sleep 0.2; n=$((n+1)); [ $n -lt 300 ] || exit 1; done
    mdo sc-s19c m 'git switch -q java/base && git checkout -q "main~1" -- rules/move.md && git commit -qm "java/base: move.md を置く（入力待ちの間）"' >> "$out" 2>&1
    echo "（試験: 入力待ちの間に m の java/base へ commit した）" >> "$out"; echo y ) | bash "$W19/run-norecheck.sh" >> "$out" 2>&1
  rc=${PIPESTATUS[1]}; grep -v 'Rebasing\|git clone --branch' "$out" | tr -d '\033' | sed 's/^/    | /'; echo "  #### [S19c 入力待ちの間に commit] 終了コード $rc"
  has_move sc-s19c
  for b in java/design java/ut; do echo "    origin: java/base ⊂ $b: $(git -C "$W19/shared.git" merge-base --is-ancestor java/base $b && echo YES || echo NO)"; done
  echo "  (c2) 同じ誤りを、push の直前に待つ前の値と比べ、③ をもう一度行う版（maintain-steady.sh）で"
  move_prep sc-s19d
  W19="$VERIF_ROOT/sc-s19d"; inst maintain-steady.sh "$W19/m" "$W19/run-maintain-steady.sh"; out="$W19/s19d.out"; : > "$out"
  ( n=0; until grep -q '③ の検査に合格した' "$out"; do sleep 0.2; n=$((n+1)); [ $n -lt 300 ] || exit 1; done
    mdo sc-s19d m 'git switch -q java/base && git checkout -q "main~1" -- rules/move.md && git commit -qm "java/base: move.md を置く（入力待ちの間）"' >> "$out" 2>&1
    echo "（試験: 入力待ちの間に m の java/base へ commit した）" >> "$out"; echo y ) | bash "$W19/run-maintain-steady.sh" >> "$out" 2>&1
  rc=${PIPESTATUS[1]}; grep -v 'Rebasing\|git clone --branch' "$out" | tr -d '\033' | sed 's/^/    | /'; echo "  #### [S19d 再検査の版] 終了コード $rc"
  has_move sc-s19d
fi

if want s09d; then
  hdr "S09d origin に、一覧に無く、自分のコミットも無いブランチ java/empty（旧い main を指す＝新しい main の先祖）"
  for v in o n; do prep sc-s09d$v; xdo sc-s09d$v x 'git push -q origin "origin/main~1:refs/heads/java/empty"'; done
  runp "S09d 対照（前の形）" sc-s09do m control-steady-prev.sh EOF
  runp "S09d maintain-steady.sh y" sc-s09dn m maintain-steady.sh 'y\n'; ostate sc-s09dn
fi

if want s12v; then
  hdr "S12v resume の前に、別のメンテナーの push と、m での git fetch が挟まる"
  for v in refs saved; do
    scr=maintain-steady-resume.sh; [ $v = refs ] && scr=control-steady-resume-refs.sh
    prep sc-s12v$v
    xdo sc-s12v$v x 'git switch -q java/design && echo "design の追記" >> CLAUDE.md && git commit -qam "java/design: CLAUDE.md に追記" && git push -q origin java/design'
    runp "S12v-$v 1 回目（衝突）" sc-s12v$v m $scr 'y\n'
    mdo sc-s12v$v m 'printf "main 初版\nmain 追記（PR #1）\ndesign の追記\n" > CLAUDE.md && git add CLAUDE.md && GIT_EDITOR=true git rebase --continue > /dev/null 2>&1'
    xdo sc-s12v$v x 'git switch -q java/ut && echo 他 >> rules/ut.md && git commit -qam "java/ut: 他メンテナー" && git push -q origin java/ut'
    mdo sc-s12v$v m 'git fetch -q origin'
    echo "    （試験: 別のメンテナーが java/ut を push し、m で git fetch した）"
    runp "S12v-$v resume" sc-s12v$v m $scr 'y\n' resume
    echo "    他のメンテナーの追記は origin の java/ut に残ったか: $(git -C "$VERIF_ROOT/sc-s12v$v/shared.git" log --oneline java/ut | grep -c '他メンテナー') 件"
  done
fi

if want s20; then
  hdr "S20 2 人目のメンテナー m2 が、1 人目の rebase より前の古いローカルブランチのまま実行する（maintain-steady.sh）"
  prep sc-s20
  runp "S20 m が実行 y" sc-s20 m maintain-steady.sh 'y\n'
  xdo sc-s20 pr3 'echo "main 追記（PR #3）" >> CLAUDE.md && git commit -qam "main: PR #3" && git push -q origin main'
  runp "S20 m2 が実行 y" sc-s20 m2 maintain-steady.sh 'y\n'; ostate sc-s20
fi

# ---- 中間ブランチだけを更新したとき ----
mid_prep() { # $1=足場 → 定常手順を通した後に、別のメンテナーのクローン m3 から java/base を早送りで進める（土台はメンテナーが直接 push する）
  prep "$1"
  inst maintain-steady.sh "$VERIF_ROOT/$1/m" "$VERIF_ROOT/$1/run-pre.sh"
  echo y | bash "$VERIF_ROOT/$1/run-pre.sh" > /dev/null 2>&1 || verif_die "定常手順に失敗: $1"
  xdo "$1" m3 'git switch -q java/base && echo "java 共通の追記（メンテナーの push）" >> rules/java.md && git commit -qam "java/base: 追記" && git push -q origin java/base'
}
if want m01; then
  hdr "M01 基準: java/base だけが早送りで進んだ。対照（前の形）と maintain-middle.sh"
  mid_prep sc-m01o; runp "M01 対照（前の形）" sc-m01o m control-middle-prev.sh EOF; ostate sc-m01o
  mid_prep sc-m01n; runp "M01 maintain-middle.sh y" sc-m01n m maintain-middle.sh 'y\n'; ostate sc-m01n
  runp "M01 maintain-middle.sh 2 回目 y" sc-m01n m maintain-middle.sh 'y\n'
fi
if want m02; then
  hdr "M02 手元に java/old（origin で消した旧いブランチ。java/base を含まない）が残っている"
  for v in o n; do mid_prep sc-m02$v; mdo sc-m02$v m 'git branch -q java/old "origin/main~1"'; done
  runp "M02 対照（前の形）" sc-m02o m control-middle-prev.sh EOF
  runp "M02 maintain-middle.sh y" sc-m02n m maintain-middle.sh 'y\n'
fi
if want m03; then
  hdr "M03 java/base を amend して force-push した"
  for v in a b; do
    prep sc-m03$v
    inst maintain-steady.sh "$VERIF_ROOT/sc-m03$v/m" "$VERIF_ROOT/sc-m03$v/run-pre.sh"
    echo y | bash "$VERIF_ROOT/sc-m03$v/run-pre.sh" > /dev/null 2>&1 || verif_die "定常手順に失敗"
    xdo sc-m03$v x 'git switch -q java/base && echo "java 共通（amend で直した）" > rules/java.md && git commit -q --amend -am "java/base: java 共通 rule（amend）" && git push -q --force origin java/base'
  done
  echo "  (a) m（amend の前の java/base を手元に持つ）で maintain-middle.sh"
  runp "M03a maintain-middle.sh" sc-m03a m maintain-middle.sh 'y\n'
  echo "    m の reflog から書き換え前の java/base を取れるか: origin/java/base@{1}=$(git -C "$VERIF_ROOT/sc-m03a/m" rev-parse -q --verify 'origin/java/base@{1}' | cut -c1-7)"
  echo "  (b) amend の後に clone した新しいクローンで maintain-middle.sh（素の rebase）"
  ( verif_cd "$VERIF_ROOT/sc-m03b"; git clone -q shared.git fresh ) || verif_die "clone"
  runp "M03b maintain-middle.sh（新しいクローン）" sc-m03b fresh maintain-middle.sh 'y\n'
  echo "    fresh の reflog から書き換え前の java/base を取れるか: $(git -C "$VERIF_ROOT/sc-m03b/fresh" rev-parse -q --verify 'origin/java/base@{1}' || echo 取れない)"
  lstate sc-m03b fresh
  ( verif_enter_repo "$VERIF_ROOT/sc-m03b/fresh"; git rebase --abort 2>/dev/null; true )
fi
m04_has() { # $1=足場 → origin の子に、土台の追記と main の追記（PR #9）が入ったか
  local w="$VERIF_ROOT/$1/shared.git" b
  for b in java/design java/ut; do
    echo "    origin $b: 土台の追記 $(MSYS2_ARG_CONV_EXCL='*' git -C "$w" show "$b:rules/java.md" | grep -c 'メンテナーの push') 件 ／ main の追記（PR #9）$(MSYS2_ARG_CONV_EXCL='*' git -C "$w" show "$b:CLAUDE.md" | grep -c 'PR #9') 件"
  done
}
if want m04; then
  hdr "M04 java/base と main の両方が進んでいる → 中間ブランチの手順 → 続けて定常手順"
  mid_prep sc-m04; xdo sc-m04 pr3 'echo "main 追記（PR #9）" >> CLAUDE.md && git commit -qam "main: PR #9" && git push -q origin main'
  runp "M04 maintain-middle.sh" sc-m04 m maintain-middle.sh 'y\n'; m04_has sc-m04
  runp "M04 続けて maintain-steady.sh" sc-m04 m maintain-steady.sh 'y\n'; ostate sc-m04; m04_has sc-m04
fi
if want m04d; then
  hdr "M04d 同じ状態で、先に定常手順を実行する → ③ で止まる → そのまま中間ブランチの手順 → 手元のブランチを捨てる → 中間ブランチの手順 → 定常手順"
  mid_prep sc-m04d; xdo sc-m04d pr3 'echo "main 追記（PR #9）" >> CLAUDE.md && git commit -qam "main: PR #9" && git push -q origin main'
  runp "M04d maintain-steady.sh（先に）" sc-m04d m maintain-steady.sh 'y\n'
  echo "    中断の後の HEAD: $(git -C "$VERIF_ROOT/sc-m04d/m" rev-parse --abbrev-ref HEAD)"
  runp "M04d そのまま maintain-middle.sh" sc-m04d m maintain-middle.sh 'y\n'
  mdo sc-m04d m 'git switch -q --detach && for b in java/base java/design java/ut python/base python/coding; do git branch -q -f "$b" "origin/$b" || exit 1; done'
  echo "    （対処: git switch --detach の後、BRANCHES の各ブランチを git branch -f で origin の値に戻す）"
  runp "M04d 捨てた後に maintain-middle.sh" sc-m04d m maintain-middle.sh 'y\n'
  runp "M04d 続けて maintain-steady.sh" sc-m04d m maintain-steady.sh 'y\n'; ostate sc-m04d; m04_has sc-m04d
fi
if want s21; then
  hdr "S21 ふつうの削除: main に足して全ブランチへ載せたファイル（名前に空白と日本語）を、main で消す PR の後に定常手順 → 消えるファイルの一覧が出る → y"
  F21='rules/廃止 する.md'
  s21_has() { local b; for b in java/base java/design java/ut python/base python/coding; do printf '    origin %-14s %s: %s\n' "$b" "$F21" "$(git -C "$VERIF_ROOT/sc-s21/shared.git" cat-file -e "$b:$F21" 2>/dev/null && echo ある || echo 無い)"; done; }
  prep sc-s21
  xdo sc-s21 pa 'mkdir -p rules && echo "廃止する rule" > "$F21" && git add -A && git commit -qm "main: 廃止する rule を足す" && git push -q origin main'
  inst maintain-steady.sh "$VERIF_ROOT/sc-s21/m" "$VERIF_ROOT/sc-s21/run-pre.sh"
  echo y | bash "$VERIF_ROOT/sc-s21/run-pre.sh" > /dev/null 2>&1 || verif_die "定常手順に失敗: sc-s21"
  xdo sc-s21 pb 'git rm -q "$F21" && git commit -qm "main: 廃止する rule を消す（PR）" && git push -q origin main'
  s21_has
  runp "S21 y" sc-s21 m maintain-steady.sh 'y\n'; s21_has
fi
echo; echo "######## 終了 ########"
