#!/usr/bin/env bash
# §5-4・§5-7・§7-2 の定常手順（maintain-steady.sh）が止まる場面で、本紙に書いた対処をしてからもう一度実行し、通るかを見る。
# あわせて、① の「origin にあって BRANCHES に無いブランチ」の検査を、PR のブランチの形（squash・rebase マージ・開いている PR など）で通す。
# 後半（R-STALE〜R-S24B）は、origin がほかのメンテナーの手順で進んだ・書き換わった後の対処、2 人の定常手順が重なったとき、§5-7 の戻し方、土台のコミットが衝突するときを見る。入力待ちの間の操作は coproc で行う（wrun）。
# claude は起動しない。各場面は自分の足場（$VERIF_ROOT/rm-<場面>）を maintain-setup.sh で作る（毎回作り直す）。
#   bash maintain-remedy.sh [場面...]   （既定は全部。場面の名前は下の ALL）
# 手順のスクリプトは、置き換える行（REPO・URL）以外は変えずに使う（diff の行数で確かめる）。
# メンテナーが「BRANCHES・PAIRS・② に足す」「BRANCHES を直す」を行った形は、写しのファイルを書き換えて作り、変えた行を diff で表示する。
# r-path だけは pwsh を使う（表示された clone のコマンドを PowerShell に貼る場面）。
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
S="$(cd "$(dirname "$0")" && pwd)" || verif_die "スクリプトの場所へ移れません"

# ---- 足場と手順のスクリプトの用意（maintain-scenes.sh と同じ形） ----
prep() { bash "$S/maintain-setup.sh" "$1" > /dev/null 2>&1 || verif_die "足場を作れない: $1"; }
inst() { # inst <手順のスクリプト> <クローン> <出力するファイル>: REPO・URL の 2 行だけを差し替える
  local src="$S/$1" repo="$2" out="$3" url rw
  [ -d "$repo/.git" ] || verif_die "クローンが無い: $repo"
  verif_under_root "$repo" || verif_die "VERIF_ROOT の外: $repo"
  url="$(git -C "$repo" remote get-url origin)" || verif_die "origin が無い: $repo"
  rw="$(verif_winpath "$repo")"
  awk -v r="$rw" -v u="$url" '
    $0=="REPO='"'"'<メンテナーのクローンのパス>'"'"'" {print "REPO='"'"'" r "'"'"'"; next}
    $0=="URL='"'"'<共有リポの URL>'"'"'"           {print "URL='"'"'" u "'"'"'"; next}
    {print}' "$src" > "$out"
  [ "$(diff "$src" "$out" | grep -c '^[<>]')" = 4 ] || verif_die "差し替えの行数が合わない: $1"
}
# edit <写し> <BRANCHES に足す名前（空白区切り）> <PAIRS に足す組（"親 子" を | 区切り）> <② の後に足す行（\n 区切り）>
edit() {
  local f="$1" addb="$2" addp="$3" add2="$4" tmp="$1.tmp" pq="" p
  local IFS_OLD="$IFS"; IFS='|'; for p in $addp; do pq="$pq \"$p\""; done; IFS="$IFS_OLD"
  awk -v ab="$addb" -v ap="$pq" -v a2="$add2" '
    /^BRANCHES=\(/ && ab!="" { sub(/\)/, " " ab ")"); print; next }
    /^       "main python\/base" "python\/base python\/coding"\)/ && ap!="" { sub(/\)/, ap ")"); print; next }
    /^# ③ 取り残しが無いことを検査する/ && a2!="" { n=split(a2, L, "\n"); for (i=1;i<=n;i++) print L[i]; print ""; print; next }
    {print}' "$f" > "$tmp" && mv "$tmp" "$f" || verif_die "edit に失敗"
}
runf() { # runf <見出し> <実行するファイル> <入力（\n 区切り。EOF なら空の stdin）> [引数]
  local label="$1" f="$2" input="$3" rc; shift 3
  echo "  \$ bash $(basename "$f") $*  （stdin: $( [ "$input" = EOF ] && echo '/dev/null' || printf '%q' "$input")）"
  if [ "$input" = EOF ]; then
    bash "$f" "$@" < /dev/null 2>&1 | grep -v '^Rebasing' | tr -d '\033' | sed 's/^/    | /'; rc=${PIPESTATUS[0]}
  else
    printf '%b' "$input" | bash "$f" "$@" 2>&1 | grep -v '^Rebasing' | tr -d '\033' | sed 's/^/    | /'; rc=${PIPESTATUS[1]}
  fi
  echo "  #### [$label] 終了コード $rc"
  LAST_RC=$rc
}
runp() { # runp <見出し> <足場> <クローン名> <スクリプト> <入力> [引数]
  local label="$1" w="$VERIF_ROOT/$2" who="$3" scr="$4" input="$5"; shift 5
  local f="$w/run-$(basename "$scr" .sh).sh"
  inst "$scr" "$w/$who" "$f"
  runf "$label" "$f" "$input" "$@"
}
ostate() {
  local w="$VERIF_ROOT/$1" b
  for b in $(git -C "$w/shared.git" for-each-ref --format='%(refname:short)' refs/heads/); do
    printf '    origin %-14s %s  main を含む: %s\n' "$b" "$(git -C "$w/shared.git" rev-parse --short "$b")" \
      "$(git -C "$w/shared.git" merge-base --is-ancestor main "$b" && echo YES || echo NO)"
  done
}
xdo() { # $1=足場 $2=クローン名 以降=bash のコード（別のクローンで。無ければ clone する）
  local w="$VERIF_ROOT/$1" c="$2"; shift 2
  ( verif_cd "$w"; [ -d "$w/$c" ] || git clone -q shared.git "$c" 2>/dev/null || exit 1
    verif_enter_repo "$w/$c"; eval "$*" ) || verif_die "xdo に失敗: $1/$c: $*"
}
mdo() { # $1=足場 $2=クローン名 以降=bash のコード（メンテナーのクローンで）
  local w="$VERIF_ROOT/$1" c="$2"; shift 2
  ( verif_enter_repo "$w/$c"; eval "$*" ) || verif_die "mdo に失敗: $1/$c: $*"
}
anc() { git -C "$VERIF_ROOT/$1/shared.git" merge-base --is-ancestor "$2" main && echo YES || echo NO; }
hdr() { echo; echo "################ $*"; }
want() { case " ${SCENES[*]} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
fixc() { mdo "$1" m 'printf "main 初版\nmain 追記（PR #1）\ndesign の追記\n" > CLAUDE.md && git add CLAUDE.md && GIT_EDITOR=true git rebase --continue > /dev/null 2>&1'; }
s12prep() { prep "$1"; xdo "$1" x 'git switch -q java/design && echo "design の追記" >> CLAUDE.md && git commit -qam "java/design: CLAUDE.md に追記" && git push -q origin java/design'; }

ALL=(e0 e1 e2 e3 e4 e5 e6 e7 e8 e9 r-e6 r-e7 r-e8 r-e8b r-s10 r-s17 r-push r-s11 r-u1 r-u2 r-s18 r-s12r r-s16 r-s12a r-s12t r-s12u r-s19d r-pushrej r-ng r-path r-acc r-acc2 r-stale r-stale-base r-stale-ng r-stale-ngw r-rebased-ng r-wait-leaf r-stale-conf r-stale-conf0 r-rebased-push r-rebased-conf r-s12a-lease c-both c-both2 r-acc3 r-acc4 r-s24a r-s24p r-s24b r-s11x r-wait-tip r-wait-tip-resume r-wait-tip-middle)
SCENES=("$@"); [ ${#SCENES[@]} -gt 0 ] || SCENES=("${ALL[@]}")
echo "######## maintain-remedy.sh $(date '+%Y-%m-%d %H:%M:%S %z') ／ $(git --version) ／ bash $BASH_VERSION ／ VERIF_ROOT=$VERIF_ROOT"

# ---- ① の「origin にあって BRANCHES に無いブランチ」の検査（PR のブランチの形） ----
if want e0; then hdr "E0 基準（BRANCHES に無いブランチなし）"; prep rm-e0; runp "E0" rm-e0 m maintain-steady.sh 'y\n'; fi

if want e1; then
  hdr "E1 squash でマージした PR のブランチ pr/2 が origin に残る"
  prep rm-e1
  xdo rm-e1 pr 'git fetch -q origin && git switch -qc pr/2 origin/main && echo pr2 > rules-pr2.md && git add -A && git commit -qm "pr/2: 追加" && git push -q origin pr/2'
  xdo rm-e1 pr 'git switch -q main && git reset -q --hard origin/main && git checkout -q pr/2 -- rules-pr2.md && git commit -qm "main: pr/2 を squash マージ（#2）" && git push -q origin main'
  echo "    前提: pr/2 は origin/main の先祖か: $(anc rm-e1 pr/2)（squash なので NO）"
  runp "E1 squash" rm-e1 m maintain-steady.sh 'y\n'
fi

if want e2; then
  hdr "E2 rebase マージした PR のブランチ pr/3 が origin に残る（main は別の PR で先に進み、cherry-pick で別のハッシュになる）"
  prep rm-e2
  xdo rm-e2 pr 'git fetch -q origin && git switch -qc pr/3 origin/main && echo pr3 > rules-pr3.md && git add -A && git commit -qm "pr/3: 追加" && git push -q origin pr/3'
  xdo rm-e2 pa 'echo other > other.md && git add -A && git commit -qm "main: 別の PR（#4）" && git push -q origin main'
  xdo rm-e2 pr 'git fetch -q origin && git switch -q main && git reset -q --hard origin/main && git cherry-pick pr/3 > /dev/null && git push -q origin main'
  echo "    前提: pr/3 は origin/main の先祖か: $(anc rm-e2 pr/3)（NO）／ pr/3=$(git -C "$VERIF_ROOT/rm-e2/shared.git" rev-parse --short pr/3) main=$(git -C "$VERIF_ROOT/rm-e2/shared.git" rev-parse --short main)"
  runp "E2 rebase マージ" rm-e2 m maintain-steady.sh 'y\n'
fi

if want e3; then
  hdr "E3 開いている PR のブランチ pr/4（PR #1 の前の main から切った。マージされていない）"
  prep rm-e3
  xdo rm-e3 pr 'git fetch -q origin && git switch -qc pr/4 origin/main~1 && echo pr4 > rules-pr4.md && git add -A && git commit -qm "pr/4: 作業中" && git push -q origin pr/4'
  echo "    前提: pr/4 は origin/main の先祖か: $(anc rm-e3 pr/4)（NO）"
  runp "E3 開いている PR" rm-e3 m maintain-steady.sh 'y\n'
  echo "    origin の pr/4 は変わっていないか: $(git -C "$VERIF_ROOT/rm-e3/shared.git" log --oneline -1 pr/4)"
fi

if want e4; then
  hdr "E4 対照: merge commit でマージした PR のブランチ pr/5 が origin に残る"
  prep rm-e4
  xdo rm-e4 pr 'git fetch -q origin && git switch -qc pr/5 origin/main && echo pr5 > rules-pr5.md && git add -A && git commit -qm "pr/5: 追加" && git push -q origin pr/5'
  xdo rm-e4 pr 'git switch -q main && git reset -q --hard origin/main && git merge -q --no-ff -m "Merge pr/5（#5）" pr/5 && git push -q origin main'
  echo "    前提: pr/5 は origin/main の先祖か: $(anc rm-e4 pr/5)（YES）"
  runp "E4 merge commit" rm-e4 m maintain-steady.sh 'y\n'
fi

if want e5; then
  hdr "E5 origin で消したブランチ pr/6 が、メンテナーの手元に残る（squash でマージして origin から消した）"
  prep rm-e5
  xdo rm-e5 pr 'git fetch -q origin && git switch -qc pr/6 origin/main && echo pr6 > rules-pr6.md && git add -A && git commit -qm "pr/6" && git push -q origin pr/6'
  mdo rm-e5 m 'git fetch -q origin && git branch -q --track pr/6 origin/pr/6'
  xdo rm-e5 pr 'git switch -q main && git reset -q --hard origin/main && git checkout -q pr/6 -- rules-pr6.md && git commit -qm "main: squash（#6）" && git push -q origin main && git push -q origin --delete pr/6'
  echo "    前提: origin に pr/6: $(git -C "$VERIF_ROOT/rm-e5/shared.git" rev-parse -q --verify pr/6 || echo 無い) ／ m の手元に pr/6: $(git -C "$VERIF_ROOT/rm-e5/m" rev-parse -q --verify --short pr/6)"
  runp "E5 origin で消した" rm-e5 m maintain-steady.sh 'y\n'
fi

if want e6; then
  hdr "E6 既にある系列に足したばかりで、BRANCHES に書き忘れた java/coding（旧い java/base から切った）"
  prep rm-e6
  xdo rm-e6 x 'git switch -qc java/coding origin/java/base && echo c > rules/coding.md && git add -A && git commit -qm "java/coding" && git push -q origin java/coding'
  echo "    前提: java/coding は origin/main の先祖か: $(anc rm-e6 java/coding)"
  runp "E6 既にある系列の書き忘れ" rm-e6 m maintain-steady.sh 'y\n'; ostate rm-e6
fi

if want e7; then
  hdr "E7 丸ごと新しい系列 ts/base・ts/coding を作り、BRANCHES に書き忘れた（PR #1 の前の main から切った）"
  prep rm-e7
  xdo rm-e7 x 'git switch -qc ts/base origin/main~1 && mkdir -p rules && echo ts > rules/ts.md && git add -A && git commit -qm "ts/base" && git switch -qc ts/coding && echo tc > rules/tsc.md && git add -A && git commit -qm "ts/coding" && git push -q origin ts/base ts/coding'
  echo "    前提: ts/base は origin/main の先祖か: $(anc rm-e7 ts/base)"
  runp "E7 新しい系列の書き忘れ" rm-e7 m maintain-steady.sh 'y\n'; ostate rm-e7
fi

if want e8; then
  hdr "E8 系列の名前で始まる PR のブランチ java/fix-x（開いている。PR #1 の後の main から切った）"
  prep rm-e8
  xdo rm-e8 pr 'git fetch -q origin && git switch -qc java/fix-x origin/main && echo fx > fix.md && git add -A && git commit -qm "java/fix-x" && git push -q origin java/fix-x'
  echo "    前提: java/fix-x は origin/main の先祖か: $(anc rm-e8 java/fix-x)"
  runp "E8 系列の名前の PR のブランチ" rm-e8 m maintain-steady.sh 'y\n'
fi

if want e9; then
  hdr "E9 系列の名前で、自分のコミットが無い java/empty（旧い main を指す＝新しい main の先祖。maintain-scenes.sh の S09d と同じ形）"
  prep rm-e9
  xdo rm-e9 x 'git push -q origin "origin/main~1:refs/heads/java/empty"'
  echo "    前提: java/empty は origin/main の先祖か: $(anc rm-e9 java/empty)"
  runp "E9 java/empty" rm-e9 m maintain-steady.sh 'y\n'; ostate rm-e9
fi

# ---- 止まった後の対処 → もう一度 ----
if want r-e6; then
  hdr "R-E6 既にある系列の java/coding の書き忘れで止まる → BRANCHES・PAIRS・② に足す → もう一度"
  prep rm-r-e6
  xdo rm-r-e6 x 'git switch -qc java/coding origin/java/base && echo c > rules/coding.md && git add -A && git commit -qm "java/coding" && git push -q origin java/coding'
  runp "R-E6 1 回目" rm-r-e6 m maintain-steady.sh 'y\n'
  W="$VERIF_ROOT/rm-r-e6"; inst maintain-steady.sh "$W/m" "$W/run-e.sh"
  edit "$W/run-e.sh" "java/coding" "java/base java/coding" 'git switch -q java/coding || fail "switch"\ngit rebase --onto java/base "${OLD[java/base]}" java/coding || fail "rebase java/coding（衝突なら git rebase --abort で戻す）"'
  diff "$S/maintain-steady.sh" "$W/run-e.sh" | sed 's/^/    diff: /'
  runf "R-E6 足した後" "$W/run-e.sh" 'y\n'; ostate rm-r-e6
fi

if want r-e7; then
  hdr "R-E7 新しい系列 ts/base・ts/coding の書き忘れ（③' の前に「参考」として出る）→ 3 か所に足す → もう一度"
  prep rm-r-e7
  xdo rm-r-e7 x 'git switch -qc ts/base origin/main~1 && mkdir -p rules && echo ts > rules/ts.md && git add -A && git commit -qm "ts/base" && git switch -qc ts/coding && echo tc > rules/tsc.md && git add -A && git commit -qm "ts/coding" && git push -q origin ts/base ts/coding'
  runp "R-E7 1 回目（n で終える）" rm-r-e7 m maintain-steady.sh 'n\n'
  W="$VERIF_ROOT/rm-r-e7"; inst maintain-steady.sh "$W/m" "$W/run-e.sh"
  edit "$W/run-e.sh" "ts/base ts/coding" "main ts/base|ts/base ts/coding" 'git switch -q ts/coding || fail "switch"\ngit -c rebase.updateRefs=true rebase main || fail "rebase ts/coding（衝突なら git rebase --abort で戻す）"'
  diff "$S/maintain-steady.sh" "$W/run-e.sh" | sed 's/^/    diff: /'
  runf "R-E7 足した後" "$W/run-e.sh" 'y\n'; ostate rm-r-e7
fi

if want r-s10; then
  hdr "R-S10 BRANCHES の python/coding が origin に無い（origin で消した）→「BRANCHES を直す」"
  for v in a b c; do prep rm-r-s10$v; ( verif_enter_repo "$VERIF_ROOT/rm-r-s10$v/shared.git" bare; git branch -q -D python/coding ) || verif_die "消せない"; done
  runp "R-S10 1 回目" rm-r-s10a m maintain-steady.sh 'y\n'
  for v in a b c; do
    W="$VERIF_ROOT/rm-r-s10$v"
    [ $v = c ] && { ( verif_cd "$W"; git clone -q shared.git fresh ) || verif_die "clone"; }
    who=m; [ $v = c ] && who=fresh
    inst maintain-steady.sh "$W/$who" "$W/run-s.sh"
    sed -i 's/^\(BRANCHES=(java\/base java\/design java\/ut python\/base\) python\/coding)/\1)/' "$W/run-s.sh"
    if [ $v = b ]; then
      sed -i -e 's/ "python\/base python\/coding")/)/' \
             -e 's/^git switch -q python\/coding || fail "switch"$/git switch -q python\/base || fail "switch"/' \
             -e 's/^git -c rebase.updateRefs=true rebase main || fail "rebase python\/coding\(.*\)   # python\/base も動く$/git rebase main || fail "rebase python\/base\1/' "$W/run-s.sh"
    fi
    echo "  （対処 $v: $( [ $v = b ] && echo 'BRANCHES・PAIRS・② を直す' || echo 'BRANCHES だけを直す' )$( [ $v = c ] && echo '。python/coding を手元に持たない新しいクローン' )）"
    diff "$S/maintain-steady.sh" "$W/run-s.sh" | sed 's/^/    diff: /'
    runf "R-S10$v 直した後" "$W/run-s.sh" 'y\n'
  done
fi

if want r-s17; then
  hdr "R-S17 --single-branch のクローンで「java/base が origin に無い（BRANCHES を直す）」→ 付けずに clone し直す・git remote set-branches origin '*'"
  prep rm-r-s17; ( verif_cd "$VERIF_ROOT/rm-r-s17"; git clone -q --single-branch shared.git sb ) || verif_die "clone"
  runp "R-S17 1 回目" rm-r-s17 sb maintain-steady.sh 'y\n'
  ( verif_cd "$VERIF_ROOT/rm-r-s17"; git clone -q shared.git full ) || verif_die "clone"
  runp "R-S17 付けずに clone し直したクローン" rm-r-s17 full maintain-steady.sh 'y\n'
  prep rm-r-s17b; ( verif_cd "$VERIF_ROOT/rm-r-s17b"; git clone -q --single-branch shared.git sb ) || verif_die "clone"
  mdo rm-r-s17b sb "git remote set-branches origin '*'"; echo "    （対処: git remote set-branches origin '*'）"
  runp "R-S17b set-branches の後" rm-r-s17b sb maintain-steady.sh 'y\n'
fi

if want r-push; then
  hdr "R-PUSH §7-2 手順 3: 新しく作った土台 go/base を push し忘れた（go/coding だけ push）→ go/base を push → もう一度"
  prep rm-r-push
  mdo rm-r-push m 'git fetch -q origin && git switch -qc go/base --no-track origin/main && mkdir -p rules && echo g > rules/go.md && git add -A && git commit -qm "go/base" && git switch -qc go/coding && echo gc > rules/goc.md && git add -A && git commit -qm "go/coding" && git push -q -u origin go/coding && git switch -q --detach'
  W="$VERIF_ROOT/rm-r-push"; inst maintain-steady.sh "$W/m" "$W/run-g.sh"
  edit "$W/run-g.sh" "go/base go/coding" "main go/base|go/base go/coding" 'git switch -q go/coding || fail "switch"\ngit -c rebase.updateRefs=true rebase main || fail "rebase go/coding（衝突なら git rebase --abort で戻す）"'
  runf "R-PUSH 1 回目" "$W/run-g.sh" 'y\n'
  mdo rm-r-push m 'git push -q -u origin go/base'; echo "    （対処: git push -u origin go/base）"
  runf "R-PUSH push した後" "$W/run-g.sh" 'y\n'; ostate rm-r-push
fi

if want r-s11; then
  hdr "R-S11 commit していない変更で止まる → git stash／commit（push しない）"
  for v in as ac bc; do prep rm-r-s11$v; done
  mdo rm-r-s11as m 'echo 手元の編集 >> CLAUDE.md'; mdo rm-r-s11ac m 'echo 手元の編集 >> CLAUDE.md'
  mdo rm-r-s11bc m 'git switch -q java/base && echo 手元の編集 >> rules/java.md'
  runp "R-S11a 1 回目" rm-r-s11as m maintain-steady.sh 'y\n'
  mdo rm-r-s11as m 'git stash -q'; echo "    （対処: git stash）"
  runp "R-S11a stash の後" rm-r-s11as m maintain-steady.sh 'y\n'
  echo "    stash は残っているか: $(git -C "$VERIF_ROOT/rm-r-s11as/m" stash list | wc -l) 件"
  mdo rm-r-s11ac m 'git commit -qam "手元の編集"'; echo "    （対処: main で commit。push しない）"
  runp "R-S11a commit の後" rm-r-s11ac m maintain-steady.sh 'y\n'
  mdo rm-r-s11bc m 'git commit -qam "手元の編集"'; echo "    （対処: java/base で commit。push しない）"
  runp "R-S11b commit の後" rm-r-s11bc m maintain-steady.sh 'y\n'
fi

if want r-s18; then
  hdr "R-S18 push していないコミットで ① が止まる → 先に push する／git branch -f で捨てる／switch して reset --hard で捨てる"
  for v in p b r; do prep rm-r-s18$v; mdo rm-r-s18$v m2 'git switch -q java/design && echo 未push >> rules/design.md && git commit -qam "java/design: まだ push していない"'; done
  runp "R-S18 1 回目" rm-r-s18p m2 maintain-steady.sh 'y\n'
  mdo rm-r-s18p m2 'git log --oneline origin/java/design..java/design | sed "s/^/    log: /" && git push -q origin java/design'; echo "    （対処 p: 先に push する）"
  runp "R-S18p push の後" rm-r-s18p m2 maintain-steady.sh 'y\n'
  runp "R-S18b 1 回目" rm-r-s18b m2 maintain-steady.sh 'y\n'
  echo "    中断の後の HEAD: $(git -C "$VERIF_ROOT/rm-r-s18b/m2" rev-parse --abbrev-ref HEAD)"
  mdo rm-r-s18b m2 'git branch -q -f java/design origin/java/design'; echo "    （対処 b: git branch -f java/design origin/java/design）"
  runp "R-S18b 捨てた後" rm-r-s18b m2 maintain-steady.sh 'y\n'
  runp "R-S18r 1 回目" rm-r-s18r m2 maintain-steady.sh 'y\n'
  mdo rm-r-s18r m2 'git switch -q java/design && git reset -q --hard origin/java/design'; echo "    （対処 r: git switch java/design → git reset --hard origin/java/design）"
  runp "R-S18r 捨てた後" rm-r-s18r m2 maintain-steady.sh 'y\n'
fi

if want r-s12r; then
  hdr "R-S12r 衝突を解いて continue した後に ① で止まる → 捨てる → もう一度（同じ衝突で止まる）"
  s12prep rm-r-s12r
  runp "R-S12r 1 回目（衝突）" rm-r-s12r m maintain-steady.sh 'y\n'; fixc rm-r-s12r
  runp "R-S12r 解いた後" rm-r-s12r m maintain-steady.sh 'y\n'
  mdo rm-r-s12r m 'git branch -q -f java/design origin/java/design && git branch -q -f java/base origin/java/base'; echo "    （対処: git branch -f で origin の値に戻して捨てる）"
  runp "R-S12r 捨てた後" rm-r-s12r m maintain-steady.sh 'y\n'
  mdo rm-r-s12r m 'git rebase --abort'
  echo "  -- --abort の後に、そのままもう一度"
  runp "R-S12r --abort の後" rm-r-s12r m maintain-steady.sh 'y\n'
  mdo rm-r-s12r m 'git rebase --abort'
fi

if want r-s16; then
  hdr "R-S16 旧い名前のローカルブランチ java で「java/base を作れない」→ git branch -D java → もう一度"
  prep rm-r-s16; ( verif_cd "$VERIF_ROOT/rm-r-s16"; git clone -q shared.git fresh ) || verif_die "clone"; mdo rm-r-s16 fresh 'git branch -q java "origin/main~1"'
  runp "R-S16 1 回目" rm-r-s16 fresh maintain-steady.sh 'y\n'
  mdo rm-r-s16 fresh 'git branch -q -D java'; echo "    （対処: git branch -D java）"
  runp "R-S16 消した後" rm-r-s16 fresh maintain-steady.sh 'y\n'
fi

if want r-s12a; then
  hdr "R-S12a ② の衝突 → --abort で戻し、main の変更か末端ブランチの変更を直してからやり直す"
  for v in 1 2m 2x 3; do s12prep rm-r-s12a$v; runp "R-S12a$v 1 回目（衝突）" rm-r-s12a$v m maintain-steady.sh 'y\n'; mdo rm-r-s12a$v m 'git rebase --abort'; done
  xdo rm-r-s12a1 x 'git switch -q java/design && git pull -q && grep -v "design の追記" CLAUDE.md > c.tmp && mv c.tmp CLAUDE.md && echo "design の追記" >> rules/design.md && git commit -qam "java/design: 追記を rules/design.md へ移す" && git push -q origin java/design'
  echo "    （対処 1: 末端ブランチに、衝突する行を別のファイルへ移すコミットを足して push）"
  runp "R-S12a1 足した後" rm-r-s12a1 m maintain-steady.sh 'y\n'; mdo rm-r-s12a1 m 'git rebase --abort 2>/dev/null; true'
  mdo rm-r-s12a2m m 'git switch -q java/design && git reset -q --hard origin/java/design && git reset -q --hard HEAD~1 && echo "design の追記" >> rules/design.md && git commit -qam "java/design: 追記（rules/design.md へ）" && git push -q --force-with-lease=java/design:$(git rev-parse origin/java/design) origin java/design && git switch -q --detach'
  echo "    （対処 2m: 実行するクローン m で、末端ブランチの衝突するコミットを書き換え、値を付けた --force-with-lease で push）"
  runp "R-S12a2m 書き換えた後" rm-r-s12a2m m maintain-steady.sh 'y\n'
  xdo rm-r-s12a2x x 'git switch -q java/design && git pull -q && git reset -q --hard HEAD~1 && echo "design の追記" >> rules/design.md && git commit -qam "java/design: 追記（rules/design.md へ）" && git push -q --force-with-lease origin java/design'
  echo "    （対処 2x: 別のクローン x で同じ書き換え）"
  runp "R-S12a2x 書き換えた後（m）" rm-r-s12a2x m maintain-steady.sh 'y\n'
  mdo rm-r-s12a2x m 'git branch -q -f java/design origin/java/design'; echo "    （m で捨てる: git branch -f java/design origin/java/design）"
  runp "R-S12a2x 捨てた後" rm-r-s12a2x m maintain-steady.sh 'y\n'
  xdo rm-r-s12a3 pa 'grep -v "main 追記" CLAUDE.md > c.tmp && mv c.tmp CLAUDE.md && echo "main 追記（PR #1）" > rules-main.md && git add -A && git commit -qm "main: PR #1 の追記を rules-main.md へ移す（PR #2）" && git push -q origin main'
  echo "    （対処 3: main の変更を直す新しい PR をマージ）"
  runp "R-S12a3 main を直した後" rm-r-s12a3 m maintain-steady.sh 'y\n'
fi

if want r-s12t; then
  hdr "R-S12t resume の版で、解いている間に別のメンテナーが push して ④ が拒否 → resume を付けずにやり直す"
  s12prep rm-r-s12t
  runp "R-S12t 1 回目（衝突）" rm-r-s12t m maintain-steady-resume.sh 'y\n'; fixc rm-r-s12t
  xdo rm-r-s12t x 'git switch -q java/ut && echo 他 >> rules/ut.md && git commit -qam "java/ut: 他メンテナー" && git push -q origin java/ut'
  runp "R-S12t resume（拒否）" rm-r-s12t m maintain-steady-resume.sh 'y\n' resume
  runp "R-S12t resume を付けずにやり直す" rm-r-s12t m maintain-steady-resume.sh 'y\n'
  mdo rm-r-s12t m 'git branch -q -f java/design origin/java/design && git branch -q -f java/base origin/java/base && git branch -q -f java/ut origin/java/ut && git branch -q -f python/base origin/python/base && git branch -q -f python/coding origin/python/coding'
  echo "    （対処: BRANCHES の各ブランチを git branch -f で origin の値に戻す）"
  runp "R-S12t 戻した後（衝突する）" rm-r-s12t m maintain-steady-resume.sh 'y\n'; fixc rm-r-s12t
  runp "R-S12t 解いて resume" rm-r-s12t m maintain-steady-resume.sh 'y\n' resume
  echo "    他のメンテナーの追記は origin の java/ut に残ったか: $(git -C "$VERIF_ROOT/rm-r-s12t/shared.git" log --oneline java/ut | grep -c '他メンテナー') 件"
fi

if want r-s19d; then
  hdr "R-S19d 入力待ちの間に java/base へ commit → push の直前の、待つ前の値との比べで止まる → もう一度実行すると"
  prep rm-r-s19d
  W="$VERIF_ROOT/rm-r-s19d"; inst maintain-steady.sh "$W/m" "$W/run-maintain-steady.sh"; out="$W/s19d.out"; : > "$out"
  # sleep で待たずに、coproc で出力の行を読み、入力待ちの案内が出たところで commit してから y を送る
  coproc P { bash "$W/run-maintain-steady.sh" 2>&1; }
  ppid_="$P_PID"; exec {pin}<&"${P[0]}" {pout}>&"${P[1]}"
  while IFS= read -r line <&"$pin"; do echo "$line" >> "$out"; case "$line" in *"③ の検査に合格した"*) break ;; esac; done
  mdo rm-r-s19d m 'git switch -q java/base && echo 入力待ちの間 >> rules/java.md && git commit -qam "java/base: 入力待ちの間"' >> "$out" 2>&1
  echo "（試験: 入力待ちの間に m の java/base へ commit した）" >> "$out"
  echo y >&"$pout"; exec {pout}>&-; cat <&"$pin" >> "$out"; exec {pin}<&-; wait "$ppid_"; rc=$?
  grep -v 'Rebasing\|git clone --branch' "$out" | tr -d '\033' | sed 's/^/    | /'; echo "  #### [R-S19d 1 回目] 終了コード $rc"
  echo "    中断の後の HEAD: $(git -C "$W/m" rev-parse --abbrev-ref HEAD)"
  runp "R-S19d そのままもう一度" rm-r-s19d m maintain-steady.sh 'y\n'
  mdo rm-r-s19d m 'git switch -q --detach && git branch -q -f java/base origin/java/base'
  echo "    （対処: git switch --detach の後、動かした java/base を git branch -f java/base origin/java/base で捨てる）"
  runp "R-S19d 捨てた後" rm-r-s19d m maintain-steady.sh 'y\n'
fi

if want r-ng; then
  hdr "R-NG ③' で不合格（n）→ 末端ブランチを直して、もう一度"
  for v in 1 2; do prep rm-r-ng$v; runp "R-NG$v n" rm-r-ng$v m maintain-steady.sh 'n\n'; done
  mdo rm-r-ng1 m 'git switch -q java/design && echo 直し >> rules/design.md && git commit -qam "java/design: 直し（push しない）" && git switch -q --detach'
  echo "    （対処 1: メンテナーのクローンの rebase 済みの java/design で直しを commit し、push せずにもう一度）"
  runp "R-NG1 push せずに" rm-r-ng1 m maintain-steady.sh 'y\n'
  xdo rm-r-ng2 x 'git switch -q java/design && echo 直し >> rules/design.md && git commit -qam "java/design: 直し" && git push -q origin java/design'
  echo "    （対処 2: origin の java/design の上で直しを commit して先に push し、もう一度）"
  runp "R-NG2 先に push" rm-r-ng2 m maintain-steady.sh 'y\n'; ostate rm-r-ng2
  prep rm-r-ng3; runp "R-NG3 n" rm-r-ng3 m maintain-steady.sh 'n\n'
  mdo rm-r-ng3 m 'git switch -q --detach && git branch -q -f java/design origin/java/design && git switch -q java/design && echo 直し >> rules/design.md && git commit -qam "java/design: 直し" && git push -q origin java/design && git switch -q --detach'
  echo "    （対処 3: 同じクローンで、git switch --detach → git branch -f java/design origin/java/design → git switch java/design → 直しを commit → push してから、もう一度）"
  runp "R-NG3 同じクローンで直して push した後" rm-r-ng3 m maintain-steady.sh 'y\n'; ostate rm-r-ng3
fi

if want r-path; then
  hdr "R-PATH ③' が表示する clone のコマンドを、Git Bash と PowerShell（pwsh）に貼る"
  prep rm-r-path
  W="$VERIF_ROOT/rm-r-path"; inst maintain-steady.sh "$W/m" "$W/run.sh"
  printf 'n\n' | bash "$W/run.sh" > "$W/out.txt" 2>&1; echo "    n の終了コード: $?"
  line=$(grep -m1 'git clone --branch java/design' "$W/out.txt" | sed 's/^ *//'); echo "    表示: $line"
  verif_fresh_dir "rm-r-path/vb"; verif_fresh_dir "rm-r-path/vp"; verif_fresh_dir "rm-r-path/vw"
  cmd_b="${line/<検証用のリポジトリ>/$(verif_winpath "$W/vb")}"
  cmd_p="${line/<検証用のリポジトリ>/$(verif_winpath "$W/vp")}"
  src_u="$(cd "$W/m" && pwd)"; src_w="$(verif_winpath "$W/m")"
  cmd_w="${cmd_p/\"$src_u\"/\"$src_w\"}"; cmd_w="${cmd_w/<検証用のリポジトリ>/$(verif_winpath "$W/vw")}"; cmd_w="${cmd_w/$(verif_winpath "$W/vp")/$(verif_winpath "$W/vw")}"
  ( verif_cd "$W/vb"; eval "$cmd_b" > /dev/null 2>&1 && echo "    Git Bash に貼る: OK（$(git -C .claude rev-parse --abbrev-ref HEAD)）" || echo "    Git Bash に貼る: NG" )
  ( verif_cd "$W/vp"; pwsh -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $cmd_p; if (\$LASTEXITCODE -eq 0) { '    PowerShell に貼る（表示のまま）: OK' } else { '    PowerShell に貼る（表示のまま）: NG' }" 2>&1 | tr -d '\r' | sed 's/^/    ps| /' )
  echo "    C:/… の形に直したコマンド: $cmd_w"
  ( verif_cd "$W/vw"; pwsh -NoProfile -Command "[Console]::OutputEncoding=[Text.Encoding]::UTF8; $cmd_w; if (\$LASTEXITCODE -eq 0) { '    PowerShell に貼る（C:/… に直す）: OK' } else { '    PowerShell に貼る（C:/… に直す）: NG' }" 2>&1 | tr -d '\r' | sed 's/^/    ps| /' )
fi

if want r-acc; then
  hdr "R-ACC §5-7 誤った force-push（java/design）を、メンテナーが reflog から正しい値を探して push し直す → メンバーの同期（§5-5 の 3 コマンド）"
  prep rm-r-acc
  xdo rm-r-acc mem 'git switch -q java/design'
  right=$(git -C "$VERIF_ROOT/rm-r-acc/shared.git" rev-parse java/design)
  mdo rm-r-acc m 'git fetch -q origin'
  xdo rm-r-acc x 'git push -q --force origin "origin/java/ut:refs/heads/java/design"'; echo "    （誤り: x が java/design を java/ut の値で force-push）"
  xdo rm-r-acc mem 'git fetch -q --all --prune && git switch -q java/design && git reset -q --hard origin/java/design'
  echo "    メンバーの .claude（誤りの後）: $(git -C "$VERIF_ROOT/rm-r-acc/mem" rev-parse --abbrev-ref HEAD) / rules: $(ls "$VERIF_ROOT/rm-r-acc/mem/rules" | tr '\n' ' ')"
  mdo rm-r-acc m 'git fetch -q origin && git reflog show --format="%h %gs" origin/java/design | sed "s/^/    reflog: /"'
  good=$(git -C "$VERIF_ROOT/rm-r-acc/m" rev-parse 'origin/java/design@{1}')
  echo "    reflog の 1 つ前: ${good:0:7} ／ 誤りの前の origin の値: ${right:0:7}"
  mdo rm-r-acc m "git push -q --force-with-lease=java/design:\$(git rev-parse origin/java/design) origin $good:refs/heads/java/design"
  echo "    （対処: reflog の値を、値を付けた --force-with-lease で push し直す）"
  xdo rm-r-acc mem 'git fetch -q --all --prune && git switch -q java/design && git reset -q --hard origin/java/design'
  echo "    メンバーの .claude（戻した後）: $(git -C "$VERIF_ROOT/rm-r-acc/mem" rev-parse --abbrev-ref HEAD) / rules: $(ls "$VERIF_ROOT/rm-r-acc/mem/rules" | tr '\n' ' ') / 先頭が正しい値か: $( [ "$(git -C "$VERIF_ROOT/rm-r-acc/mem" rev-parse HEAD)" = "$right" ] && echo 一致 || echo 不一致 )"
  runp "R-ACC 戻した後の定常手順" rm-r-acc m maintain-steady.sh 'y\n'
fi

if want r-acc2; then
  hdr "R-ACC2 R-ACC と同じ戻し方で、メンテナーの最後の fetch の後に、別のメンテナーの正しい push と誤った force-push が続いたとき"
  prep rm-r-acc2
  mdo rm-r-acc2 m 'git fetch -q origin'
  xdo rm-r-acc2 x2 'git switch -q java/design && echo 正しい追記 >> rules/design.md && git commit -qam "java/design: 正しい追記（別のメンテナー）" && git push -q origin java/design'
  right=$(git -C "$VERIF_ROOT/rm-r-acc2/shared.git" rev-parse java/design)
  xdo rm-r-acc2 x 'git push -q --force origin "origin/java/ut:refs/heads/java/design"'; echo "    （正しい push の後に、x が java/design を java/ut の値で force-push）"
  mdo rm-r-acc2 m 'git fetch -q origin && git reflog show --format="%h %gs" origin/java/design | sed "s/^/    reflog: /"'
  good=$(git -C "$VERIF_ROOT/rm-r-acc2/m" rev-parse 'origin/java/design@{1}')
  echo "    reflog の 1 つ前: ${good:0:7} ／ 誤りの直前の origin の値: ${right:0:7}"
  mdo rm-r-acc2 m "git push -q --force-with-lease=java/design:\$(git rev-parse origin/java/design) origin $good:refs/heads/java/design"
  echo "    （対処: reflog の 1 つ前の値を、値を付けた --force-with-lease で push し直す）"
  echo "    origin の java/design に「正しい追記」が残ったか: $(git -C "$VERIF_ROOT/rm-r-acc2/shared.git" log --oneline java/design | grep -c '正しい追記') 件 ／ 先頭が誤りの直前の値か: $( [ "$(git -C "$VERIF_ROOT/rm-r-acc2/shared.git" rev-parse java/design)" = "$right" ] && echo 一致 || echo 不一致 )"
fi

if want r-e8; then
  hdr "R-E8 系列の名前で始まる、開いている PR のブランチ java/fix-x（PR #1 の前の main から切った）で ① が止まる → BRANCHES・PAIRS・② に足すと"
  prep rm-r-e8
  xdo rm-r-e8 pr 'git fetch -q origin && git switch -qc java/fix-x origin/main~1 && echo fx > fix.md && git add -A && git commit -qm "java/fix-x: 作業中" && git push -q origin java/fix-x'
  before=$(git -C "$VERIF_ROOT/rm-r-e8/shared.git" rev-parse --short java/fix-x)
  runp "R-E8 1 回目" rm-r-e8 m maintain-steady.sh 'y\n'
  W="$VERIF_ROOT/rm-r-e8"; inst maintain-steady.sh "$W/m" "$W/run-e.sh"
  edit "$W/run-e.sh" "java/fix-x" "main java/fix-x" 'git switch -q java/fix-x || fail "switch"\ngit rebase main || fail "rebase java/fix-x"'
  diff "$S/maintain-steady.sh" "$W/run-e.sh" | sed 's/^/    diff: /'
  runf "R-E8 足した後" "$W/run-e.sh" 'y\n'
  echo "    origin の java/fix-x: 前 $before → 後 $(git -C "$W/shared.git" rev-parse --short java/fix-x)（PR のブランチが書き換わったか）"
fi

if want r-u1; then
  hdr "R-U1 手元の main に commit した変更を PR のブランチ pr/9 にして push → マージの前に実行 → squash でマージした後に実行"
  prep rm-r-u1
  mdo rm-r-u1 m 'git switch -q main && echo u1 > u1.md && git add u1.md && git commit -qm "main: u1（手元）" && git push -q origin HEAD:refs/heads/pr/9'
  runp "R-U1 マージの前" rm-r-u1 m maintain-steady.sh 'y\n'
  xdo rm-r-u1 pa 'git fetch -q origin && git switch -q main && git reset -q --hard origin/main && git checkout -q origin/pr/9 -- u1.md && git commit -qm "main: pr/9 を squash マージ（#9）" && git push -q origin main'
  echo "    （pr/9 を squash で origin の main にマージした）"
  runp "R-U1 マージの後" rm-r-u1 m maintain-steady.sh 'y\n'
fi

if want r-u2; then
  hdr "R-U2 手元の main に 2 つのコミット → PR のブランチ pr/10 にして push → 1 つに squash してマージ → 実行（① で止まる）→ 手元の main を origin の値に合わせる → もう一度"
  prep rm-r-u2
  mdo rm-r-u2 m 'git switch -q main && echo u2a > u2.md && git add u2.md && git commit -qm "main: u2 その 1（手元）" && echo u2b >> u2.md && git commit -qam "main: u2 その 2（手元）" && git push -q origin HEAD:refs/heads/pr/10'
  xdo rm-r-u2 pa 'git fetch -q origin && git switch -q main && git reset -q --hard origin/main && git checkout -q origin/pr/10 -- u2.md && git commit -qm "main: pr/10 を 1 つに squash してマージ（#10）" && git push -q origin main'
  echo "    （pr/10 の 2 つのコミットを、1 つに squash して origin の main にマージした）"
  runp "R-U2 マージの後" rm-r-u2 m maintain-steady.sh 'y\n'
  echo "    中断の後の HEAD: $(git -C "$VERIF_ROOT/rm-r-u2/m" rev-parse --abbrev-ref HEAD)"
  mdo rm-r-u2 m 'git switch -q main'
  echo "    （メンテナーが main に戻った状態を作る: git switch main）"
  ( verif_enter_repo "$VERIF_ROOT/rm-r-u2/m"; git branch -f main origin/main 2>&1 | sed 's/^/    branch| /'; echo "    HEAD が main のままの git branch -f main origin/main の終了コード: ${PIPESTATUS[0]}" )
  mdo rm-r-u2 m 'git switch -q --detach && git branch -q -f main origin/main'
  echo "    （対処: git switch --detach の後に git branch -f main origin/main）"
  runp "R-U2 合わせた後" rm-r-u2 m maintain-steady.sh 'y\n'
fi

if want r-e8b; then
  hdr "R-E8b 系列の名前で始まる開いている PR のブランチ java/fix-x で ① が止まる → 同じ中身を pr/fix-x で出し直し、java/fix-x を origin から消す → もう一度"
  prep rm-r-e8b
  xdo rm-r-e8b pr 'git fetch -q origin && git switch -qc java/fix-x origin/main~1 && echo fx > fix.md && git add -A && git commit -qm "java/fix-x: 作業中" && git push -q origin java/fix-x'
  runp "R-E8b 1 回目" rm-r-e8b m maintain-steady.sh 'y\n'
  xdo rm-r-e8b pr 'git push -q origin java/fix-x:refs/heads/pr/fix-x && git push -q origin --delete java/fix-x'
  echo "    （対処: 同じブランチを pr/fix-x として push し、origin の java/fix-x を消した。メンテナーの手元の java/fix-x: $(git -C "$VERIF_ROOT/rm-r-e8b/m" rev-parse -q --verify --short java/fix-x || echo 無い)）"
  runp "R-E8b 出し直した後" rm-r-e8b m maintain-steady.sh 'y\n'
fi

if want r-s12u; then
  hdr "R-S12u resume の版で、解いている間に別のメンテナーが push して ④ が拒否 → git switch --detach の後に各ブランチを戻す → resume を付けずにやり直す → 解いて resume"
  s12prep rm-r-s12u
  runp "R-S12u 1 回目（衝突）" rm-r-s12u m maintain-steady-resume.sh 'y\n'; fixc rm-r-s12u
  xdo rm-r-s12u x 'git switch -q java/ut && echo 他 >> rules/ut.md && git commit -qam "java/ut: 他メンテナー" && git push -q origin java/ut'
  runp "R-S12u resume（拒否）" rm-r-s12u m maintain-steady-resume.sh 'y\n' resume
  echo "    拒否の後の HEAD: $(git -C "$VERIF_ROOT/rm-r-s12u/m" rev-parse --abbrev-ref HEAD)"
  mdo rm-r-s12u m 'git switch -q --detach && for b in java/base java/design java/ut python/base python/coding; do git branch -q -f "$b" "origin/$b" || exit 1; done'
  echo "    （対処: git switch --detach の後、BRANCHES の各ブランチを git branch -f で origin の値に戻す）"
  runp "R-S12u 付けずにやり直す（衝突する）" rm-r-s12u m maintain-steady-resume.sh 'y\n'; fixc rm-r-s12u
  runp "R-S12u 解いて resume" rm-r-s12u m maintain-steady-resume.sh 'y\n' resume
  echo "    他のメンテナーの追記は origin の java/ut に残ったか: $(git -C "$VERIF_ROOT/rm-r-s12u/shared.git" log --oneline java/ut | grep -c '他メンテナー') 件"
fi

if want r-pushrej; then
  hdr "R-PUSHREJ 載せ直した手元のブランチを、手で push する（衝突を解いた後の java/design・③' の後に commit した java/base）"
  s12prep rm-r-pushrej
  runp "R-PUSHREJ 1 回目（衝突）" rm-r-pushrej m maintain-steady.sh 'y\n'; fixc rm-r-pushrej
  runp "R-PUSHREJ 解いた後" rm-r-pushrej m maintain-steady.sh 'y\n'
  ( verif_enter_repo "$VERIF_ROOT/rm-r-pushrej/m"; git push origin java/design 2>&1 | sed 's/^/    push| /'; echo "    git push origin java/design の終了コード: ${PIPESTATUS[0]}" )
  prep rm-r-pushrej2
  runp "R-PUSHREJ2 ③' で n" rm-r-pushrej2 m maintain-steady.sh 'n\n'
  mdo rm-r-pushrej2 m 'git switch -q java/base && echo 手元の追記 >> rules/java.md && git commit -qam "java/base: 手元の追記"'
  ( verif_enter_repo "$VERIF_ROOT/rm-r-pushrej2/m"; git push origin java/base 2>&1 | sed 's/^/    push| /'; echo "    git push origin java/base の終了コード: ${PIPESTATUS[0]}" )
fi
# ---- origin がほかのメンテナーの手順で進んだ・書き換わったとき（§5-4 の ①・先頭の検査・③'・②の衝突の (a)(b)・④、§5-7 の戻し方）----
# wrun <見出し> <足場> <クローン名> <スクリプト> <入力待ちの間に実行するコード> [引数]
#   手順のスクリプトを coproc で走らせ、③ の後の入力待ちに入ったところでコードを実行してから y を送る（sleep で待たない）
#   WRUN_ANS=n を付けて呼ぶと、y の代わりに n を送る
WRUN_N=0
wrun() {
  local label="$1" w="$VERIF_ROOT/$2" who="$3" scr="$4" mid="$5" f out rc line reached=0; shift 5
  WRUN_N=$((WRUN_N+1)); f="$w/run-w$WRUN_N-$(basename "$scr" .sh).sh"; out="$w/w$WRUN_N.out"
  inst "$scr" "$w/$who" "$f"; : > "$out"
  echo "  \$ bash $(basename "$f")  （入力待ちの間に、別の操作をしてから y を送る）"
  coproc WP { bash "$f" "$@" 2>&1; }
  local wpid="$WP_PID"; exec {wpin}<&"${WP[0]}" {wpout}>&"${WP[1]}"
  while IFS= read -r line <&"$wpin"; do echo "$line" >> "$out"; case "$line" in *"③ の検査に合格した"*) reached=1; break ;; esac; done
  if [ $reached = 1 ]; then
    echo "（入力待ちの間に、次を実行した）" >> "$out"
    eval "$mid" >> "$out" 2>&1
    echo "（ここで ${WRUN_ANS:-y} を送った）" >> "$out"
    echo "${WRUN_ANS:-y}" >&"$wpout"
  fi
  exec {wpout}>&-; cat <&"$wpin" >> "$out"; exec {wpin}<&-; wait "$wpid"; rc=$?
  tr '\r' '\n' < "$out" | tr -d '\033' | grep -v '^Rebasing\|git clone --branch\|^\[K$' | sed 's/^/    | /'
  echo "  #### [$label] 終了コード $rc"
  LAST_RC=$rc
}
# rgit <足場> <クローン名> <見出し> <git の引数...>: 失敗してもよい git を 1 つ実行し、出力と終了コードを表示する
rgit() {
  local w="$VERIF_ROOT/$1" c="$2" t="$3"; shift 3
  ( verif_enter_repo "$w/$c"; git "$@" 2>&1 | tr '\r' '\n' | tr -d '\033' | grep -v '^Rebasing\|^\[K$\|^$' | sed "s/^/    $t| /"; echo "    $c: git $* の終了コード: ${PIPESTATUS[0]}" )
}
cnt() { git -C "$VERIF_ROOT/$1/shared.git" log --oneline "$2" | grep -c "$3"; }
merges() { git -C "$VERIF_ROOT/$1/shared.git" rev-list --merges --count "$2"; }
s24prep() { # 土台 java/base に、main の PR #1 と衝突するコミットを置き、中間ブランチの手順で子へ届けておく
  prep "$1"
  xdo "$1" x 'git switch -q java/base && echo "base の追記" >> CLAUDE.md && git commit -qam "java/base: CLAUDE.md に追記" && git push -q origin java/base'
  runp "$1 準備: 中間ブランチの手順で子へ届ける" "$1" m maintain-middle.sh 'y\n'
}
fixb() { mdo "$1" m 'printf "main 初版\nmain 追記（PR #1）\nbase の追記\n" > CLAUDE.md && git add CLAUDE.md && GIT_EDITOR=true git rebase --continue > /dev/null 2>&1'; }

if want r-stale; then
  hdr "R-STALE もう 1 人（m）の定常手順で origin が書き換わった後、m2 は古い手元の java/design に commit していた → ① で止まる → push → 拒否 → git fetch・git switch・git rebase origin/java/design → push → もう一度"
  prep rm-r-stale; W="$VERIF_ROOT/rm-r-stale"
  mdo rm-r-stale m2 'git switch -q java/design && echo m2 の追記 >> rules/design.md && git commit -qam "java/design: m2 の追記（古い手元のブランチの上）"'
  runp "R-STALE m の定常手順" rm-r-stale m maintain-steady.sh 'y\n'
  runp "R-STALE m2 の 1 回目" rm-r-stale m2 maintain-steady.sh 'y\n'
  echo "    中断の後の m2 の HEAD: $(git -C "$W/m2" rev-parse --abbrev-ref HEAD)"
  echo "    m2: git cherry -v origin/java/design java/design origin/main:"; git -C "$W/m2" cherry -v origin/java/design java/design origin/main | sed 's/^/      /'
  echo "    m2: git log --oneline origin/java/design..java/design:"; git -C "$W/m2" log --oneline origin/java/design..java/design | sed 's/^/      /'
  rgit rm-r-stale m2 push push origin java/design
  echo "    （対処: git fetch → git switch java/design → git rebase origin/java/design → git push origin java/design）"
  rgit rm-r-stale m2 fetch fetch origin
  rgit rm-r-stale m2 switch switch java/design
  rgit rm-r-stale m2 rebase rebase origin/java/design
  rgit rm-r-stale m2 push push origin java/design
  runp "R-STALE m2 の 2 回目" rm-r-stale m2 maintain-steady.sh 'y\n'; ostate rm-r-stale
  echo "    origin の java/design: m2 の追記 $(cnt rm-r-stale java/design 'm2 の追記') 件 ／ java/base の共通 rule のコミット $(cnt rm-r-stale java/design 'java/base: java 共通 rule') 件 ／ merge commit $(merges rm-r-stale java/design) 件"
fi

if want r-stale-base; then
  hdr "R-STALE-BASE m の定常手順の後、m2 が古い手元の java/base に commit して直接 push（中間ブランチの節）→ 拒否 → git fetch・git switch・git rebase origin/java/base → push → 中間ブランチの手順 → 定常手順"
  prep rm-r-stale-base; W="$VERIF_ROOT/rm-r-stale-base"
  mdo rm-r-stale-base m2 'git switch -q java/base && echo m2 の土台の追記 >> rules/java.md && git commit -qam "java/base: m2 の追記（古い手元のブランチの上）"'
  runp "R-STALE-BASE m の定常手順" rm-r-stale-base m maintain-steady.sh 'y\n'
  rgit rm-r-stale-base m2 push push origin java/base
  echo "    （対処: git fetch → git switch java/base → git rebase origin/java/base → git push origin java/base）"
  rgit rm-r-stale-base m2 fetch fetch origin
  rgit rm-r-stale-base m2 switch switch java/base
  rgit rm-r-stale-base m2 rebase rebase origin/java/base
  rgit rm-r-stale-base m2 push push origin java/base
  runp "R-STALE-BASE 中間ブランチの手順（m2）" rm-r-stale-base m2 maintain-middle.sh 'y\n'
  runp "R-STALE-BASE 定常手順（m2）" rm-r-stale-base m2 maintain-steady.sh 'y\n'; ostate rm-r-stale-base
  echo "    origin の m2 の土台の追記: java/base $(cnt rm-r-stale-base java/base 'm2 の追記') 件・java/design $(cnt rm-r-stale-base java/design 'm2 の追記') 件・java/ut $(cnt rm-r-stale-base java/ut 'm2 の追記') 件 ／ java/design の共通 rule のコミット $(cnt rm-r-stale-base java/design 'java/base: java 共通 rule') 件"
fi

if want r-stale-ng; then
  hdr "R-STALE-NG m が ③' で n → その間に m2 が定常手順を終える → m が本紙の「このクローンで直すとき」の手で直して push → 拒否 → git fetch・git switch・git rebase → push → もう一度"
  prep rm-r-stale-ng; W="$VERIF_ROOT/rm-r-stale-ng"
  runp "R-STALE-NG m の 1 回目（n）" rm-r-stale-ng m maintain-steady.sh 'n\n'
  runp "R-STALE-NG m2 の定常手順" rm-r-stale-ng m2 maintain-steady.sh 'y\n'
  mdo rm-r-stale-ng m 'git switch -q --detach && git branch -q -f java/design origin/java/design && git switch -q java/design && echo 直し >> rules/design.md && git commit -qam "java/design: 直し"'
  echo "    （本紙の手: git switch --detach → git branch -f java/design origin/java/design → git switch java/design → 直しを commit → push）"
  rgit rm-r-stale-ng m push push origin java/design
  echo "    （対処: git fetch → git switch java/design → git rebase origin/java/design → git push origin java/design）"
  rgit rm-r-stale-ng m fetch fetch origin
  rgit rm-r-stale-ng m switch switch java/design
  rgit rm-r-stale-ng m rebase rebase origin/java/design
  rgit rm-r-stale-ng m push push origin java/design
  runp "R-STALE-NG m の 2 回目" rm-r-stale-ng m maintain-steady.sh 'y\n'; ostate rm-r-stale-ng
  echo "    origin の java/design: 直し $(cnt rm-r-stale-ng java/design '直し') 件 ／ 共通 rule のコミット $(cnt rm-r-stale-ng java/design 'java/base: java 共通 rule') 件"
fi

if want r-stale-ngw; then
  hdr "R-STALE-NGW m の ③' の入力待ちの間に m2 が定常手順を終える → m は n で終える → 本紙の「このクローンで直すとき」の手で直して push → 拒否 → git fetch・git switch・git rebase → push → もう一度"
  prep rm-r-stale-ngw; W="$VERIF_ROOT/rm-r-stale-ngw"
  WRUN_ANS=n wrun "R-STALE-NGW m（入力待ちの間に m2 の定常手順。その後 n）" rm-r-stale-ngw m maintain-steady.sh \
    'runp "R-STALE-NGW m2 の定常手順" rm-r-stale-ngw m2 maintain-steady.sh "y\n"'
  mdo rm-r-stale-ngw m 'git switch -q --detach && git branch -q -f java/design origin/java/design && git switch -q java/design && echo 直し >> rules/design.md && git commit -qam "java/design: 直し"'
  echo "    （本紙の手: git switch --detach → git branch -f java/design origin/java/design → git switch java/design → 直しを commit → push）"
  rgit rm-r-stale-ngw m push push origin java/design
  echo "    （対処: git fetch → git switch java/design → git rebase origin/java/design → git push origin java/design）"
  rgit rm-r-stale-ngw m fetch fetch origin
  rgit rm-r-stale-ngw m switch switch java/design
  rgit rm-r-stale-ngw m rebase rebase origin/java/design
  rgit rm-r-stale-ngw m push push origin java/design
  runp "R-STALE-NGW m の 2 回目" rm-r-stale-ngw m maintain-steady.sh 'y\n'; ostate rm-r-stale-ngw
  echo "    origin の java/design: 直し $(cnt rm-r-stale-ngw java/design '直し') 件 ／ 共通 rule のコミット $(cnt rm-r-stale-ngw java/design 'java/base: java 共通 rule') 件"
fi

if want r-rebased-ng; then
  hdr "R-REBASED-NG 対照: ③' で n → 載せ直した手元の末端ブランチ java/design に commit → push（拒否）→ ① の説明の手（git fetch・git switch・git rebase origin/java/design）を当てると"
  prep rm-r-rebased-ng; W="$VERIF_ROOT/rm-r-rebased-ng"
  runp "R-REBASED-NG ③' で n" rm-r-rebased-ng m maintain-steady.sh 'n\n'
  mdo rm-r-rebased-ng m 'git switch -q java/design && echo 手元の追記 >> rules/design.md && git commit -qam "java/design: 手元の追記（載せ直したブランチの上）"'
  rgit rm-r-rebased-ng m push push origin java/design
  rgit rm-r-rebased-ng m fetch fetch origin
  rgit rm-r-rebased-ng m switch switch java/design
  rgit rm-r-rebased-ng m rebase rebase origin/java/design
  echo "    m は rebase の途中か: $( [ -d "$W/m/.git/rebase-merge" ] && echo はい || echo いいえ )"
  [ -d "$W/m/.git/rebase-merge" ] && rgit rm-r-rebased-ng m abort rebase --abort
  rgit rm-r-rebased-ng m push push origin java/design
  echo "    origin の java/design の log:"; git -C "$W/shared.git" log --oneline java/design | sed 's/^/      /'
  echo "    origin の java/design は main を含むか: $(git -C "$W/shared.git" merge-base --is-ancestor main java/design && echo YES || echo NO)"
fi

if want r-wait-leaf; then
  hdr "R-WAIT-LEAF ③' の入力待ちの間に、載せ直した手元の末端ブランチ java/design に commit → y"
  prep rm-r-wait-leaf; W="$VERIF_ROOT/rm-r-wait-leaf"
  wrun "R-WAIT-LEAF m（入力待ちの間に java/design へ commit）" rm-r-wait-leaf m maintain-steady.sh \
    'mdo rm-r-wait-leaf m "git switch -q java/design && echo 手元の追記 >> rules/design.md && git commit -qam \"java/design: 手元の追記（入力待ちの間）\"" && echo "m の java/design に commit した"'
  echo "    origin の java/design の log:"; git -C "$W/shared.git" log --oneline java/design | sed 's/^/      /'
fi

if want r-stale-conf; then
  hdr "R-STALE-CONF m2 は衝突するコミット（java/design の CLAUDE.md の追記）を手元に持ったまま自分のコミットを足した → m が (b) で衝突を解いて resume で push → m2 が ① で止まる → push → 拒否 → git fetch・git switch・git rebase origin/java/design（衝突）→ --abort → 足したコミットだけを --onto で載せ直す → push → もう一度"
  s12prep rm-r-stale-conf; W="$VERIF_ROOT/rm-r-stale-conf"
  mdo rm-r-stale-conf m2 'git fetch -q origin && git switch -q java/design && git reset -q --hard origin/java/design && echo m2 の追記 >> rules/design.md && git commit -qam "java/design: m2 の追記" && git switch -q --detach'
  runp "R-STALE-CONF m の 1 回目（衝突）" rm-r-stale-conf m maintain-steady-resume.sh 'y\n'; fixc rm-r-stale-conf
  runp "R-STALE-CONF m の resume" rm-r-stale-conf m maintain-steady-resume.sh 'y\n' resume
  runp "R-STALE-CONF m2 の 1 回目" rm-r-stale-conf m2 maintain-steady.sh 'y\n'
  echo "    m2: git cherry -v origin/java/design java/design origin/main:"; git -C "$W/m2" cherry -v origin/java/design java/design origin/main | sed 's/^/      /'
  rgit rm-r-stale-conf m2 push push origin java/design
  echo "    （対処: git fetch → git switch java/design → git rebase origin/java/design）"
  rgit rm-r-stale-conf m2 fetch fetch origin
  rgit rm-r-stale-conf m2 switch switch java/design
  rgit rm-r-stale-conf m2 rebase rebase origin/java/design
  echo "    m2 は rebase の途中か: $( [ -d "$W/m2/.git/rebase-merge" ] && echo はい || echo いいえ )"
  rgit rm-r-stale-conf m2 abort rebase --abort
  echo "    （対処: 足したコミット 1 つだけを載せ直す: git rebase --onto origin/java/design java/design~1 java/design → push）"
  rgit rm-r-stale-conf m2 rebase rebase --onto origin/java/design java/design~1 java/design
  rgit rm-r-stale-conf m2 push push origin java/design
  runp "R-STALE-CONF m2 の 2 回目" rm-r-stale-conf m2 maintain-steady.sh 'y\n'; ostate rm-r-stale-conf
  echo "    origin の java/design: m2 の追記 $(cnt rm-r-stale-conf java/design 'm2 の追記') 件 ／ CLAUDE.md: $(git -C "$W/shared.git" show java/design:CLAUDE.md | tr '\n' '/')"
fi

if want r-stale-conf0; then
  hdr "R-STALE-CONF0 m2 は衝突するコミット（java/design の CLAUDE.md の追記）を手元に持つだけで、自分では何も足していない → m が (b) で衝突を解いて resume で push → m2 が定常手順 → 捨てる → もう一度"
  s12prep rm-r-stale-conf0; W="$VERIF_ROOT/rm-r-stale-conf0"
  mdo rm-r-stale-conf0 m2 'git fetch -q origin && git switch -q java/design && git reset -q --hard origin/java/design && git switch -q --detach'
  runp "R-STALE-CONF0 m の 1 回目（衝突）" rm-r-stale-conf0 m maintain-steady-resume.sh 'y\n'; fixc rm-r-stale-conf0
  runp "R-STALE-CONF0 m の resume" rm-r-stale-conf0 m maintain-steady-resume.sh 'y\n' resume
  runp "R-STALE-CONF0 m2 の 1 回目" rm-r-stale-conf0 m2 maintain-steady.sh 'y\n'
  echo "    中断の後の m2 の HEAD: $(git -C "$W/m2" rev-parse --abbrev-ref HEAD)"
  echo "    m2: git cherry -v origin/java/design java/design origin/main:"; git -C "$W/m2" cherry -v origin/java/design java/design origin/main | sed 's/^/      /'
  mdo rm-r-stale-conf0 m2 'git branch -q -f java/design origin/java/design'; echo "    （対処: git branch -f java/design origin/java/design で捨てる）"
  runp "R-STALE-CONF0 m2 の捨てた後" rm-r-stale-conf0 m2 maintain-steady.sh 'y\n'; ostate rm-r-stale-conf0
fi

if want r-rebased-push; then
  hdr "R-REBASED-PUSH 対照: ③' の入力待ちの間に、載せ直した手元の java/base に commit → y → 待つ前の値との比べで止まる → push（拒否）→ ① の説明の手（git fetch・git switch・git rebase origin/java/base）を当てると"
  prep rm-r-rebased-push; W="$VERIF_ROOT/rm-r-rebased-push"
  wrun "R-REBASED-PUSH m（入力待ちの間に java/base へ commit）" rm-r-rebased-push m maintain-steady.sh \
    'mdo rm-r-rebased-push m "git switch -q java/base && echo 手元の追記 >> rules/java.md && git commit -qam \"java/base: 手元の追記（入力待ちの間）\"" && echo "m の java/base に commit した"'
  echo "    中断の後の m の HEAD: $(git -C "$W/m" rev-parse --abbrev-ref HEAD)"
  rgit rm-r-rebased-push m push push origin java/base
  rgit rm-r-rebased-push m fetch fetch origin
  rgit rm-r-rebased-push m switch switch java/base
  rgit rm-r-rebased-push m rebase rebase origin/java/base
  rgit rm-r-rebased-push m push push origin java/base
  echo "    origin の java/base の log:"; git -C "$W/shared.git" log --oneline java/base | sed 's/^/      /'
  echo "    origin の java/base は main を含むか: $(git -C "$W/shared.git" merge-base --is-ancestor main java/base && echo YES || echo NO)"
  mdo rm-r-rebased-push m 'git switch -q --detach'
  runp "R-REBASED-PUSH 中間ブランチの手順" rm-r-rebased-push m maintain-middle.sh 'y\n'
  runp "R-REBASED-PUSH 定常手順" rm-r-rebased-push m maintain-steady.sh 'y\n'; ostate rm-r-rebased-push
  echo "    origin の java/base の log（定常手順の後）:"; git -C "$W/shared.git" log --oneline java/base | sed 's/^/      /'
fi

if want r-rebased-conf; then
  hdr "R-REBASED-CONF 対照: 衝突を解いて continue した後に ① で止まる → push（拒否）→ ① の説明の手（git fetch・git switch・git rebase origin/java/design）を当てると"
  s12prep rm-r-rebased-conf; W="$VERIF_ROOT/rm-r-rebased-conf"
  runp "R-REBASED-CONF 1 回目（衝突）" rm-r-rebased-conf m maintain-steady.sh 'y\n'; fixc rm-r-rebased-conf
  runp "R-REBASED-CONF 解いた後" rm-r-rebased-conf m maintain-steady.sh 'y\n'
  rgit rm-r-rebased-conf m push push origin java/design
  rgit rm-r-rebased-conf m fetch fetch origin
  rgit rm-r-rebased-conf m switch switch java/design
  rgit rm-r-rebased-conf m rebase rebase origin/java/design
  echo "    m は rebase の途中か: $( [ -d "$W/m/.git/rebase-merge" ] && echo はい || echo いいえ )"
  rgit rm-r-rebased-conf m abort rebase --abort
fi

if want r-s12a-lease; then
  hdr "R-S12A-LEASE ② の衝突 → --abort → 末端ブランチの衝突するコミットを書き換える間に、別のメンテナーが java/design に push → 書き換える前の origin の値を付けた lease で push → 拒否 → fetch して origin の新しい値の上で書き換え直す → 同じ形の lease で push → もう一度"
  s12prep rm-r-s12a-lease
  runp "R-S12A-LEASE 1 回目（衝突）" rm-r-s12a-lease m maintain-steady.sh 'y\n'; mdo rm-r-s12a-lease m 'git rebase --abort'
  mdo rm-r-s12a-lease m 'git switch -q java/design && git reset -q --hard origin/java/design && git reset -q --hard HEAD~1 && echo "design の追記" >> rules/design.md && git commit -qam "java/design: 追記（rules/design.md へ）"'
  xdo rm-r-s12a-lease x 'git switch -q java/design && git pull -q && echo 別のメンテナーの追記 >> rules/design.md && git commit -qam "java/design: 別のメンテナーの追記" && git push -q origin java/design'
  echo "    （書き換えている間に、x が java/design に push した）"
  W="$VERIF_ROOT/rm-r-s12a-lease"; lv=$(git -C "$W/m" rev-parse origin/java/design)
  rgit rm-r-s12a-lease m push push "--force-with-lease=java/design:$lv" origin java/design
  echo "    （対処: git fetch → git reset --hard origin/java/design → 衝突するコミットだけを外して（git rebase --onto HEAD~2 HEAD~1）→ 書き換えた追記を commit → fetch した後の値を付けた lease で push）"
  mdo rm-r-s12a-lease m 'git fetch -q origin && git reset -q --hard origin/java/design && git log --oneline -3 | sed "s/^/    log: /" && git rebase -q --onto HEAD~2 HEAD~1 && echo "design の追記" >> rules/design.md && git commit -qam "java/design: 追記（rules/design.md へ）"'
  lv=$(git -C "$W/m" rev-parse origin/java/design)
  rgit rm-r-s12a-lease m push push "--force-with-lease=java/design:$lv" origin java/design
  runp "R-S12A-LEASE 書き換え直した後" rm-r-s12a-lease m maintain-steady.sh 'y\n'; ostate rm-r-s12a-lease
  echo "    origin の java/design: 別のメンテナーの追記 $(cnt rm-r-s12a-lease java/design '別のメンテナーの追記') 件"
fi

if want c-both; then
  hdr "C-BOTH m と m2 が同じ時に定常手順を始める（m の入力待ちの間に、m2 が最後まで通す）→ m に y → もう一度"
  prep rm-c-both
  wrun "C-BOTH m（入力待ちの間に m2 の定常手順）" rm-c-both m maintain-steady.sh \
    'runp "C-BOTH m2 の定常手順" rm-c-both m2 maintain-steady.sh "y\n"'
  before=$(git -C "$VERIF_ROOT/rm-c-both/shared.git" rev-parse java/design)
  runp "C-BOTH m のもう一度" rm-c-both m maintain-steady.sh 'y\n'; ostate rm-c-both
  echo "    m のもう一度で origin の java/design は変わったか: $( [ "$before" = "$(git -C "$VERIF_ROOT/rm-c-both/shared.git" rev-parse java/design)" ] && echo 変わらない || echo 変わった )"
fi

if want c-both2; then
  hdr "C-BOTH2 m が定常手順を始める → 入力待ちの間に PR #2 がマージされ、それをマージした m2 が定常手順を最後まで通す → m に y → もう一度"
  prep rm-c-both2
  wrun "C-BOTH2 m（入力待ちの間に PR #2 と m2 の定常手順）" rm-c-both2 m maintain-steady.sh \
    'xdo rm-c-both2 pr "git fetch -q origin && git switch -q main && git reset -q --hard origin/main && echo \"main 追記（PR #2）\" >> CLAUDE.md && git commit -qam \"main: PR #2 で追記\" && git push -q origin main" && runp "C-BOTH2 m2 の定常手順" rm-c-both2 m2 maintain-steady.sh "y\n"'
  runp "C-BOTH2 m のもう一度" rm-c-both2 m maintain-steady.sh 'y\n'; ostate rm-c-both2
fi

if want r-acc3; then
  hdr "R-ACC3 §5-7 誤った force-push の後に、メンテナーが fetch せずに reflog の値を使う → fetch してから使う"
  prep rm-r-acc3; W="$VERIF_ROOT/rm-r-acc3"
  xdo rm-r-acc3 x2 'git switch -q java/design && echo 先の追記 >> rules/design.md && git commit -qam "java/design: 先の追記（m が fetch する前）" && git push -q origin java/design'
  right=$(git -C "$W/shared.git" rev-parse java/design)
  mdo rm-r-acc3 m 'git fetch -q origin'
  xdo rm-r-acc3 x 'git push -q --force origin "origin/java/ut:refs/heads/java/design"'; echo "    （誤り: x が java/design を java/ut の値で force-push）"
  mdo rm-r-acc3 m 'git reflog show --format="%h %gs" origin/java/design | sed "s/^/    reflog（fetch の前）: /"'
  g0=$(git -C "$W/m" rev-parse 'origin/java/design@{0}'); g1=$(git -C "$W/m" rev-parse 'origin/java/design@{1}' 2>/dev/null || echo なし)
  echo "    fetch の前: @{0}=${g0:0:7} @{1}=${g1:0:7} ／ 誤りの前の origin の値: ${right:0:7}"
  rgit rm-r-acc3 m push push "--force-with-lease=java/design:$g0" origin "$g1:refs/heads/java/design"
  echo "    （上は、fetch せずに @{1} を、手元の origin/java/design（=@{0}）を lease に渡して push したもの）"
  mdo rm-r-acc3 m 'git fetch -q origin && git reflog show --format="%h %gs" origin/java/design | sed "s/^/    reflog（fetch の後）: /"'
  g1=$(git -C "$W/m" rev-parse 'origin/java/design@{1}'); cur=$(git -C "$W/m" rev-parse origin/java/design)
  rgit rm-r-acc3 m push push "--force-with-lease=java/design:$cur" origin "$g1:refs/heads/java/design"
  echo "    origin の java/design が誤りの前の値に戻ったか: $( [ "$(git -C "$W/shared.git" rev-parse java/design)" = "$right" ] && echo 一致 || echo 不一致 )"
fi

if want r-acc4; then
  hdr "R-ACC4 R-ACC2 と同じ状態（最後の fetch の後に別のメンテナーの正しい push、その後に誤り）で、正しい push をした x2 のクローンの値を使って戻す"
  prep rm-r-acc4; W="$VERIF_ROOT/rm-r-acc4"
  mdo rm-r-acc4 m 'git fetch -q origin'
  xdo rm-r-acc4 x2 'git switch -q java/design && echo 正しい追記 >> rules/design.md && git commit -qam "java/design: 正しい追記（別のメンテナー）" && git push -q origin java/design'
  right=$(git -C "$W/shared.git" rev-parse java/design)
  xdo rm-r-acc4 x 'git push -q --force origin "origin/java/ut:refs/heads/java/design"'; echo "    （正しい push の後に、x が java/design を java/ut の値で force-push）"
  mdo rm-r-acc4 m 'git fetch -q origin && git reflog show --format="%h %gs" origin/java/design | sed "s/^/    m の reflog: /"'
  echo "    m の @{1}: $(git -C "$W/m" rev-parse --short 'origin/java/design@{1}') ／ 正しい push の値: ${right:0:7}"
  echo "    x2 の手元の java/design: $(git -C "$W/x2" rev-parse --short java/design)"
  xdo rm-r-acc4 x2 'git fetch -q origin && git push -q --force-with-lease=java/design:$(git rev-parse origin/java/design) origin java/design'
  echo "    （対処: x2 で git fetch → 手元の java/design を、fetch した後の値を付けた lease で push）"
  echo "    origin の java/design が正しい push の値に戻ったか: $( [ "$(git -C "$W/shared.git" rev-parse java/design)" = "$right" ] && echo 一致 || echo 不一致 ) ／ 正しい追記 $(cnt rm-r-acc4 java/design '正しい追記') 件"
  runp "R-ACC4 戻した後の定常手順（m）" rm-r-acc4 m maintain-steady.sh 'y\n'; ostate rm-r-acc4
fi

if want r-s24a; then
  hdr "R-S24A 衝突するコミットが土台 java/base にある → --abort → 土台にコミットを足して直す（中間ブランチの節の決まり）→ 中間ブランチの手順 → もう一度"
  s24prep rm-r-s24a
  runp "R-S24A 1 回目（衝突）" rm-r-s24a m maintain-steady.sh 'y\n'; mdo rm-r-s24a m 'git rebase --abort'
  xdo rm-r-s24a x 'git switch -q java/base && git pull -q && grep -v "base の追記" CLAUDE.md > c.tmp && mv c.tmp CLAUDE.md && echo "base の追記" >> rules/java.md && git commit -qam "java/base: 追記を rules/java.md へ移す" && git push -q origin java/base'
  echo "    （対処: 土台に、衝突する行を別のファイルへ移すコミットを足して push）"
  runp "R-S24A 中間ブランチの手順" rm-r-s24a m maintain-middle.sh 'y\n'
  runp "R-S24A もう一度" rm-r-s24a m maintain-steady.sh 'y\n'; mdo rm-r-s24a m 'git rebase --abort 2>/dev/null; true'
fi

if want r-s24p; then
  hdr "R-S24P 衝突するコミットが土台 java/base にある → --abort → main を直す新しい PR → もう一度"
  s24prep rm-r-s24p
  runp "R-S24P 1 回目（衝突）" rm-r-s24p m maintain-steady.sh 'y\n'; mdo rm-r-s24p m 'git rebase --abort'
  xdo rm-r-s24p pa 'grep -v "main 追記" CLAUDE.md > c.tmp && mv c.tmp CLAUDE.md && echo "main 追記（PR #1）" > rules-main.md && git add -A && git commit -qm "main: PR #1 の追記を rules-main.md へ移す（PR #2）" && git push -q origin main'
  echo "    （対処: main の変更を直す新しい PR をマージ）"
  runp "R-S24P main を直した後" rm-r-s24p m maintain-steady.sh 'y\n'; ostate rm-r-s24p
  echo "    origin の java/ut は java/base を含むか: $(git -C "$VERIF_ROOT/rm-r-s24p/shared.git" merge-base --is-ancestor java/base java/ut && echo YES || echo NO)"
fi

if want r-s24b; then
  hdr "R-S24B 衝突するコミットが土台 java/base にある → (b) 解いて continue → resume"
  s24prep rm-r-s24b
  runp "R-S24B 1 回目（衝突）" rm-r-s24b m maintain-steady-resume.sh 'y\n'; fixb rm-r-s24b
  runp "R-S24B 解いて resume" rm-r-s24b m maintain-steady-resume.sh 'y\n' resume; ostate rm-r-s24b
  echo "    origin の java/ut は java/base を含むか: $(git -C "$VERIF_ROOT/rm-r-s24b/shared.git" merge-base --is-ancestor java/base java/ut && echo YES || echo NO) ／ java/design の CLAUDE.md: $(git -C "$VERIF_ROOT/rm-r-s24b/shared.git" show java/design:CLAUDE.md | tr '\n' '/')"
fi

# ---- 先頭の中断の案内（commit していない変更）に従う形と、従わない形（2026-11-23 に足した）----
if want r-s11x; then
  hdr "R-S11X commit していない変更 → 案内の手（変更を捨てる）／案内に無い手（末端 java/design で commit・origin に無いブランチを切って commit）→ もう一度"
  for v in r d t; do prep rm-r-s11x$v; done
  mdo rm-r-s11xr m 'echo 手元の編集 >> CLAUDE.md && git checkout -- .'; echo "    （対処 r: git checkout -- . で変更を捨てる）"
  runp "R-S11Xr 捨てた後" rm-r-s11xr m maintain-steady.sh 'y\n'
  mdo rm-r-s11xd m 'git switch -q java/design && echo 手元の編集 >> rules/design.md && git commit -qam "java/design: 手元の編集"'; echo "    （対処 d: 末端 java/design で commit。push しない）"
  runp "R-S11Xd 末端で commit の後" rm-r-s11xd m maintain-steady.sh 'y\n'
  mdo rm-r-s11xt m 'echo 手元の編集 >> CLAUDE.md && git switch -q -c topic/local && git commit -qam "topic/local: 手元の編集"'; echo "    （対処 t: origin に無いブランチ topic/local を切って commit）"
  runp "R-S11Xt origin に無いブランチで commit の後" rm-r-s11xt m maintain-steady.sh 'y\n'
  echo "    topic/local は残っているか: $(git -C "$VERIF_ROOT/rm-r-s11xt/m" rev-parse -q --verify refs/heads/topic/local > /dev/null && echo 残る || echo 無い)"
fi

# ---- ③' の入力を待つ間に、このクローンのブランチを動かしたとき（待つ前の値との比べ。2026-11-23 に足した）----
heads() { git -C "$VERIF_ROOT/$1/shared.git" for-each-ref --format='%(refname:short)=%(objectname:short)' refs/heads/ | tr '\n' ' '; }
backcmd() { sed -n 's/.*の値へ戻し（\(.*\)）、このスクリプト.*/\1/p' "$VERIF_ROOT/$1/w$WRUN_N.out" | head -1; }   # 直前の wrun の中断の文から、戻すコマンドを取り出す
wtback() { # wtback <足場>: 中断の文の案内どおりに、git switch --detach の後、案内の値へ戻す
  local c; c="$(backcmd "$1")"; [ -n "$c" ] || { echo "    （中断の文に戻すコマンドが無い）"; return 0; }
  echo "    （対処: 中断の文の案内どおり git switch --detach →$c）"
  mdo "$1" m "git switch -q --detach && $c"
}
wtcommit() { echo "mdo $1 m \"git switch -q $2 && echo 待つ間の追記 >> $3 && git commit -qam \\\"$2: 待つ間の追記\\\"\" && echo \"m の $2 に commit した\""; }
if want r-wait-tip; then
  hdr "R-WAIT-TIP ③' の入力を待つ間に、このクローンのブランチを動かす → y（push の直前に、待つ前の値と比べる）"
  for v in leaf base none n main; do prep rm-r-wt-$v; done
  echo "  (1) 末端 java/design に commit → y → そのままもう一度 → 案内どおり戻す → もう一度"
  b0=$(heads rm-r-wt-leaf)
  wrun "R-WT1 末端を動かす y" rm-r-wt-leaf m maintain-steady.sh "$(wtcommit rm-r-wt-leaf java/design rules/design.md)"
  echo "    origin は動いていないか: $( [ "$b0" = "$(heads rm-r-wt-leaf)" ] && echo 動いていない || echo 動いた )"
  runp "R-WT1 そのままもう一度" rm-r-wt-leaf m maintain-steady.sh 'y\n'
  wtback rm-r-wt-leaf
  runp "R-WT1 戻した後" rm-r-wt-leaf m maintain-steady.sh 'y\n'
  echo "    origin の java/design に待つ間の追記: $(cnt rm-r-wt-leaf java/design '待つ間の追記') 件"
  echo "  (2) 土台 java/base に commit → y → 案内どおり戻す → もう一度"
  b0=$(heads rm-r-wt-base)
  wrun "R-WT2 土台を動かす y" rm-r-wt-base m maintain-steady.sh "$(wtcommit rm-r-wt-base java/base rules/java.md)"
  echo "    origin は動いていないか: $( [ "$b0" = "$(heads rm-r-wt-base)" ] && echo 動いていない || echo 動いた )"
  wtback rm-r-wt-base
  runp "R-WT2 戻した後" rm-r-wt-base m maintain-steady.sh 'y\n'
  echo "  (3) どのブランチも動かさない（git switch java/ut で HEAD だけを動かす）→ y"
  wrun "R-WT3 動かさない y" rm-r-wt-none m maintain-steady.sh 'mdo rm-r-wt-none m "git switch -q java/ut" && echo "m で git switch java/ut した"'; ostate rm-r-wt-none
  echo "  (4) 末端 java/design に commit → n"
  b0=$(heads rm-r-wt-n)
  WRUN_ANS=n wrun "R-WT4 末端を動かす n" rm-r-wt-n m maintain-steady.sh "$(wtcommit rm-r-wt-n java/design rules/design.md)"
  echo "    origin は動いていないか: $( [ "$b0" = "$(heads rm-r-wt-n)" ] && echo 動いていない || echo 動いた )"
  echo "  (5) 載せ先 main に commit → y"
  b0=$(heads rm-r-wt-main)
  wrun "R-WT5 main を動かす y" rm-r-wt-main m maintain-steady.sh "$(wtcommit rm-r-wt-main main CLAUDE.md)"
  echo "    origin は動いていないか: $( [ "$b0" = "$(heads rm-r-wt-main)" ] && echo 動いていない || echo 動いた )"
fi
if want r-wait-tip-resume; then
  hdr "R-WAIT-TIP-RESUME 選択肢の版（maintain-steady-resume.sh）: 衝突を解いて resume → 入力を待つ間に java/ut へ commit → y → 案内どおり戻す → resume"
  s12prep rm-r-wt-resume
  runp "R-WT6 1 回目（衝突）" rm-r-wt-resume m maintain-steady-resume.sh 'y\n'; fixc rm-r-wt-resume
  b0=$(heads rm-r-wt-resume)
  wrun "R-WT6 resume、待つ間に java/ut を動かす y" rm-r-wt-resume m maintain-steady-resume.sh "$(wtcommit rm-r-wt-resume java/ut rules/ut.md)" resume
  echo "    origin は動いていないか: $( [ "$b0" = "$(heads rm-r-wt-resume)" ] && echo 動いていない || echo 動いた )"
  wtback rm-r-wt-resume
  runp "R-WT6 戻した後に resume" rm-r-wt-resume m maintain-steady-resume.sh 'y\n' resume; ostate rm-r-wt-resume
fi
if want r-wait-tip-middle; then
  hdr "R-WAIT-TIP-MIDDLE 土台の手順（maintain-middle.sh）: java/base が早送りで進んだ → 入力を待つ間に子 java/design へ commit → y → 案内どおり戻す → もう一度"
  prep rm-r-wt-middle
  xdo rm-r-wt-middle x 'git switch -q java/base && echo 土台の追記 >> rules/java.md && git commit -qam "java/base: 土台の追記" && git push -q origin java/base'
  b0=$(heads rm-r-wt-middle)
  wrun "R-WT7 子を動かす y" rm-r-wt-middle m maintain-middle.sh "$(wtcommit rm-r-wt-middle java/design rules/design.md)"
  echo "    origin は動いていないか: $( [ "$b0" = "$(heads rm-r-wt-middle)" ] && echo 動いていない || echo 動いた )"
  ( verif_enter_repo "$VERIF_ROOT/rm-r-wt-middle/m"; git switch -q --detach && git branch -q -f java/design 'java/design@{1}' ) || verif_die "R-WT7 の戻し"
  echo "    （案内に無い手: git switch --detach → 子 java/design だけを待つ前の値（java/design@{1}）へ戻す）"
  runp "R-WT7 待つ前の値へ戻した後" rm-r-wt-middle m maintain-middle.sh 'y\n'
  wtback rm-r-wt-middle
  runp "R-WT7 案内どおり戻した後" rm-r-wt-middle m maintain-middle.sh 'y\n'; ostate rm-r-wt-middle
  echo "    origin の java/design に待つ間の追記: $(cnt rm-r-wt-middle java/design '待つ間の追記') 件 ／ java/ut は java/base を含むか: $(git -C "$VERIF_ROOT/rm-r-wt-middle/shared.git" merge-base --is-ancestor java/base java/ut && echo YES || echo NO)"
fi

echo; echo "######## 終了 ########"
