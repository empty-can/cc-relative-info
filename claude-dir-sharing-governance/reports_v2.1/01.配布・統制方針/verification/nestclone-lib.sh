# nestclone-run.sh と nestclone-worktree.sh の共通部分（lib.sh の後に source する）。

NC_OUTDIR="$VERIF_ROOT/nestclone-stream"
mkdir -p "$NC_OUTDIR" || exit 1

NC_ASSET_PROMPT='次の5項目を順に実行し、最後に結果だけを「ラベル=値」の形で1行ずつ出力してください。ファイルを読んだり探したりするコマンド（cat・ls・find・grep など）は実行してはいけません。
1. あなたのコンテキストに NESTCLONE-CM で始まる合言葉があれば `CM=<その合言葉>`。無ければ `CM=NONE`。
2. NESTCLONE-RU で始まる合言葉があれば `RU=<その合言葉>`。無ければ `RU=NONE`。
3. Bash ツールで `printenv NESTPROBE_ENV` だけを実行し、出力があれば `EV=<出力そのまま>`、コマンドは成功したが出力が無ければ `EV=NONE`、実行できなければ `EV=FAIL`。
4. 3 の結果を受け取ってから、次の応答で Skill ツールで skill 名 `probeskill` を起動し、返ってきた合言葉を `SK=<合言葉>`。起動できなければ `SK=FAIL`。
5. Agent ツールで subagent_type `probeagent` を前景で（run_in_background は false にして、結果を待って）起動し（プロンプトは「合言葉を返して」）、返ってきた合言葉を `AG=<合言葉>`。起動できなければ `AG=FAIL`、起動したが合言葉が返らなければ `AG=NORESULT`。'

NC_DENY_PROMPT='Bash ツールで `./denyprobe.sh` を、この文字列のまま 1 回だけ実行してください（bash などを前に付けない）。ほかのコマンドは一切実行してはいけません。拒否されたりエラーになったりしても、別の方法を試してはいけません。実行できたら `DENY=RAN`、拒否されたら `DENY=REFUSED <理由を 1 行>` とだけ出力してください。'

# nc_assets <ラベル>  （起動ディレクトリで実行する）
nc_assets() {
  local tag="$1" out
  echo "================ 資産のロード: $tag ================"
  # Read は probeagent（tools: Read）を起動するために要る（無いと「ツールが 0 個」で起動を拒否される）。
  # 親のセッションが Read で合言葉を読んでいないことは、表示するツール呼び出しで確かめる。
  verif_header "--tools Bash,Skill,Agent,Read（--allowedTools も同じ）／ --permission-mode default"
  out="$NC_OUTDIR/assets-$tag-$(date +%H%M%S).jsonl"
  verif_claude_stream "$out" --model "$VERIF_MODEL" --permission-mode default \
    --tools "Bash,Skill,Agent,Read" --allowedTools Bash Skill Agent Read -p "$NC_ASSET_PROMPT"
  echo "  ==== 要約 [$tag] init の agents に probeagent: $(grep -q "init: agents=.*'probeagent'" "$out.show" && echo 有 || echo 無)" \
       "／ 起動時の指示に .claude\\CLAUDE.md: $(grep -q '記録 文脈+ instructions .*\.claude\\\\CLAUDE\.md' "$out.show" && echo 有 || echo 無)" \
       "／ 起動時の指示に plain-rule.md: $(grep -q '記録 文脈+ instructions .*plain-rule\.md' "$out.show" && echo 有 || echo 無)" \
       "／ init の skills に probeskill: $(grep -q "init: skills=.*'probeskill'" "$out.show" && echo 有 || echo 無)" \
       "／ rc=$VERIF_RC"
  echo
}

# nc_deny <ラベル>  （起動ディレクトリで実行する。./denyprobe.sh がそこにあること）
nc_deny() {
  local tag="$1" out cmds
  [ -f ./denyprobe.sh ] || { echo "  ./denyprobe.sh がありません（$(verif_winpath .)）"; return 1; }
  rm -f denyprobe.out
  echo "================ deny の効き: $tag ================"
  verif_header "--tools Bash（--allowedTools Bash）／ --permission-mode default"
  out="$NC_OUTDIR/deny-$tag-$(date +%H%M%S).jsonl"
  verif_claude_stream "$out" --model "$VERIF_MODEL" --permission-mode default \
    --tools "Bash" --allowedTools Bash -p "$NC_DENY_PROMPT"
  cmds=$(sed -n 's/^  \[手番[0-9]*\] tool: Bash //p' "$out.show" | tr '\n' ' ')
  echo "  ==== 要約 [$tag] 実行を指示したコマンド: $cmds" \
       "／ 文字列どおり（\"./denyprobe.sh\"）: $(echo "$cmds" | grep -q '"command": "./denyprobe.sh"' && echo はい || echo いいえ)" \
       "／ denyprobe.out: $([ -f denyprobe.out ] && echo '作られた（実行された）' || echo '無い（実行されていない）')" \
       "／ permission_denials: $(sed -n 's/^  permission_denials=//p' "$out.show")" \
       "／ rc=$VERIF_RC"
  rm -f denyprobe.out
  echo
}
