#!/bin/bash
# LLMs/scripts/gen-llms-txt/gen_llms.sh
#
# targets.txt に列挙された各ターゲット（GitHub URL / ローカルパス）について
# 以下を順に実施するバッチエントリ。dl_llms.sh と同じ起動方式を取る。
#
#   1. クローン または pull（GitHub URL のみ）
#   2. gen_llms_full.py で llms.txt / llms-full.txt を生成
#   3. validate.sh で生成物を検証
#
# blockquote / description プレースホルダ ({BLOCKQUOTE} / {DESCRIPTION}) は
# 機械的に決定できないため未置換のまま残る。補完は /generate-llms-txt Skill
# 経由か手動で別途実施する。
#
# 実行方法（リポジトリルートから）:
#   bash LLMs/scripts/gen-llms-txt/gen_llms.sh
#   bash LLMs/scripts/gen-llms-txt/gen_llms.sh --target-list <別のファイル.txt>
#
# 入出力:
#   入力       : <SCRIPT_DIR>/targets.txt （または --target-list で指定）
#   クローン先 : LLMs/work/tmp-clone/
#   生成物     : LLMs/work/gen-out/
#   エラーログ : LLMs/work/gen-error/ （gen_llms_full.py が書く）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TARGETS_FILE="${SCRIPT_DIR}/targets.txt"
PYTHON="${PYTHON:-python}"

while [ $# -gt 0 ]; do
    case "$1" in
        --target-list)
            TARGETS_FILE="$2"
            shift 2
            ;;
        -h|--help)
            awk 'NR==1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$TARGETS_FILE" ]; then
    echo "ERROR: Targets file not found: $TARGETS_FILE" >&2
    exit 1
fi

GEN_OUT="${REPO_ROOT}/LLMs/work/gen-out"
TMP_CLONE="${REPO_ROOT}/LLMs/work/tmp-clone"

mkdir -p "$GEN_OUT" "$TMP_CLONE"

TOTAL=0
SUCCESS=0
FAILED=0
SKIPPED=0
RESULTS=()

# GitHub URL を owner / repo / branch に分解する
# 出力: PG_OWNER / PG_REPO / PG_BRANCH（branch なしのとき PG_BRANCH は空）
parse_github_url() {
    local url="$1"
    local path="${url#https://github.com/}"
    path="${path%/}"
    PG_OWNER="${path%%/*}"
    local rest="${path#*/}"
    if [[ "$rest" == */tree/* ]]; then
        PG_REPO="${rest%%/tree/*}"
        local b="${rest#*/tree/}"
        PG_BRANCH="${b%%/*}"
    else
        PG_REPO="${rest%%/*}"
        PG_BRANCH=""
    fi
    PG_REPO="${PG_REPO%.git}"
}

# git remote URL（https or git@）から owner / repo を抽出する
# GitHub 以外は非ゼロを返す
parse_remote_url() {
    local url="$1"
    local rpath
    if [[ "$url" == git@github.com:* ]]; then
        rpath="${url#git@github.com:}"
    elif [[ "$url" == https://github.com/* ]]; then
        rpath="${url#https://github.com/}"
    else
        return 1
    fi
    rpath="${rpath%.git}"
    PR_OWNER="${rpath%%/*}"
    local rest="${rpath#*/}"
    PR_REPO="${rest%%/*}"
    return 0
}

process_target() {
    local target="$1"
    shift

    local extract_sigs=false
    local cc_extensions=false
    local base_url=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --extract-sigs)  extract_sigs=true;  shift ;;
            --cc-extensions) cc_extensions=true; shift ;;
            --base-url)      base_url="$2";      shift 2 ;;
            *)
                echo "  WARN    : Unknown per-line option ignored: $1" >&2
                shift
                ;;
        esac
    done

    local repo_path
    local out_dir_rel
    local resolved_base_url="$base_url"
    local clone_url=""
    local branch=""

    if [[ "$target" == https://github.com/* ]]; then
        parse_github_url "$target"
        local owner="$PG_OWNER" repo="$PG_REPO"
        branch="$PG_BRANCH"

        clone_url="https://github.com/${owner}/${repo}.git"
        repo_path="${TMP_CLONE}/${owner}/${repo}"

        if [ "$cc_extensions" = true ]; then
            out_dir_rel="cc-extensions/${owner}/${repo}"
        else
            out_dir_rel="${owner}/${repo}"
        fi
        if [ -n "$branch" ] && [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
            out_dir_rel="${out_dir_rel}/${branch}"
        fi

        if [ -z "$resolved_base_url" ]; then
            local br="${branch:-main}"
            resolved_base_url="https://github.com/${owner}/${repo}/blob/${br}/"
        fi
    else
        if [ ! -d "$target" ]; then
            echo "  ERROR   : Local target is not a directory: $target" >&2
            RESULTS+=("FAILED  ${target}  (local dir not found)")
            FAILED=$((FAILED + 1))
            return
        fi
        repo_path="$(cd "$target" && pwd)"

        local remote_url=""
        remote_url="$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)"

        if parse_remote_url "$remote_url"; then
            if [ "$cc_extensions" = true ]; then
                out_dir_rel="cc-extensions/${PR_OWNER}/${PR_REPO}"
            else
                out_dir_rel="${PR_OWNER}/${PR_REPO}"
            fi
            if [ -z "$resolved_base_url" ]; then
                resolved_base_url="https://github.com/${PR_OWNER}/${PR_REPO}/blob/main/"
            fi
        else
            if [ -z "$resolved_base_url" ]; then
                echo "  ERROR   : --base-url required for non-GitHub local target: $target" >&2
                RESULTS+=("FAILED  ${target}  (--base-url required)")
                FAILED=$((FAILED + 1))
                return
            fi
            out_dir_rel="$(basename "$repo_path")"
        fi
    fi

    local out_dir="${GEN_OUT}/${out_dir_rel}"

    echo "----------------------------------------"
    echo "[${TOTAL}] Target : $target"
    echo "  Repo    : $repo_path"
    echo "  Out dir : $out_dir"
    echo "  Base url: $resolved_base_url"
    echo "  Flags   : extract-sigs=$extract_sigs cc-extensions=$cc_extensions"

    if [ -n "$clone_url" ]; then
        if [ -d "$repo_path/.git" ]; then
            # shallow clone は pull が ref 不足で失敗しやすいので fetch + reset で更新する。
            # tmp-clone/ は gitignore 配下の作業領域でローカル編集を行わない前提のため reset --hard は安全。
            local fetch_ref="${branch:-HEAD}"
            echo "  Update  : git fetch --depth=1 origin $fetch_ref && reset --hard FETCH_HEAD"
            if git -C "$repo_path" fetch --depth=1 origin "$fetch_ref" >/dev/null 2>&1; then
                if ! git -C "$repo_path" reset --hard FETCH_HEAD >/dev/null 2>&1; then
                    echo "  WARN    : reset failed (working tree may be stale)"
                fi
            else
                echo "  WARN    : fetch failed (continuing with existing checkout)"
            fi
        else
            mkdir -p "$(dirname "$repo_path")"
            local -a clone_args=(--depth=1)
            if [ -n "$branch" ]; then
                clone_args+=(--branch "$branch")
            fi
            echo "  Clone   : git clone ${clone_args[*]} $clone_url"
            if ! git clone "${clone_args[@]}" "$clone_url" "$repo_path" >/dev/null 2>&1; then
                echo "  ERROR   : clone failed"
                RESULTS+=("FAILED  ${target}  (clone failed)")
                FAILED=$((FAILED + 1))
                return
            fi
        fi
    fi

    local -a py_args=("$repo_path" --base-url "$resolved_base_url" --output "$out_dir" --skip-if-unchanged)
    if [ "$extract_sigs" = true ]; then
        py_args+=(--extract-sigs)
    fi
    if [ "$cc_extensions" = true ]; then
        py_args+=(--cc-extensions)
    fi

    echo "  Generate: $PYTHON gen_llms_full.py ${py_args[*]}"
    local py_output py_exit
    py_output=$("$PYTHON" "${SCRIPT_DIR}/gen_llms_full.py" "${py_args[@]}" 2>&1)
    py_exit=$?

    if [ $py_exit -ne 0 ]; then
        echo "$py_output"
        echo "  ERROR   : generation failed (exit=$py_exit)"
        RESULTS+=("FAILED  ${target}  (generation failed)")
        FAILED=$((FAILED + 1))
        return
    fi

    # gen_llms_full.py は変更なしで終わる場合 'SKIPPED:' を先頭行に出して exit 0
    if printf '%s\n' "$py_output" | head -1 | grep -q '^SKIPPED:'; then
        echo "$py_output"
        RESULTS+=("SKIPPED ${target}")
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    echo "$py_output"

    echo "  Validate: bash validate.sh ${out_dir}/llms.txt"
    if bash "${SCRIPT_DIR}/validate.sh" "${out_dir}/llms.txt"; then
        RESULTS+=("SUCCESS ${target}  -> ${out_dir}/llms.txt")
        SUCCESS=$((SUCCESS + 1))
    else
        RESULTS+=("FAILED  ${target}  (validation failed)")
        FAILED=$((FAILED + 1))
    fi
}

while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [ -z "$line" ] && continue
    [ "${line:0:1}" = "#" ] && continue

    TOTAL=$((TOTAL + 1))

    # shellcheck disable=SC2206
    tokens=($line)
    target="${tokens[0]}"
    if [ "${#tokens[@]}" -gt 1 ]; then
        process_target "$target" "${tokens[@]:1}"
    else
        process_target "$target"
    fi
done < "$TARGETS_FILE"

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total   : $TOTAL"
echo "Success : $SUCCESS"
echo "Skipped : $SKIPPED"
echo "Failed  : $FAILED"
echo ""
if [ "${#RESULTS[@]}" -gt 0 ]; then
    for r in "${RESULTS[@]}"; do
        echo "  $r"
    done
fi

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
