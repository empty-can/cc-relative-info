#!/usr/bin/env bash
# 入れ子クローン .claude/ から各資産がロードされるか、共有リポの permissions.deny が効くかを測る。
# 先に nestclone-setup.sh（deny の足場）と nestclone-setup.sh nodeny（対照の足場）を実行しておくこと。
#
# usage: bash nestclone-run.sh [deny|nodeny] [root|sub]
#   deny/nodeny  使う足場（$VERIF_ROOT/nestclone か $VERIF_ROOT/nestclone-nodeny）
#   root/sub     作業リポジトリのルートから起動するか、サブディレクトリ sub/ から起動するか
#
# 1 回の実行で 2 セッション:
#   資産: CLAUDE.md・paths なし rule・settings.json の env・skill・agent（probeagent）
#         判定は init（skills・agents）とセッション記録（起動時の指示）、ツールの結果。モデルの回答は並べるだけ
#   deny: --tools Bash・--allowedTools Bash・--permission-mode default で ./denyprobe.sh を実行させ、
#         denyprobe.out が作られたか・ツールの結果が拒否か（permission_denials）で判定する。
#         指示した文字列どおりのコマンドだったかも表示する（bash ./denyprobe.sh などは rule に一致しないため）
set -uo pipefail
source "$(dirname "$0")/lib.sh" || exit 1
source "$(dirname "$0")/nestclone-lib.sh" || exit 1

MODE="${1:-deny}"; WHERE="${2:-root}"
case "$MODE" in deny) NAME=nestclone ;; nodeny) NAME=nestclone-nodeny ;; *) verif_die "第 1 引数は deny か nodeny" ;; esac

verif_enter_repo "$VERIF_ROOT/$NAME/work"
[ -d .claude/.git ] || verif_die "足場がありません。nestclone-setup.sh $MODE を先に実行してください"
case "$WHERE" in
  root) ;;
  sub)  verif_cd sub ;;
  *) verif_die "第 2 引数は root か sub" ;;
esac

nc_assets "$MODE-$WHERE"
nc_deny "$MODE-$WHERE"
