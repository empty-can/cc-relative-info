#!/usr/bin/env python3
"""Generate a meta llms.txt for the cc-extensions output folder.

Scans LLMs/work/gen-out/cc-extensions/<owner>/<repo>/[<branch>/]llms.txt
and writes LLMs/work/gen-out/cc-extensions/llms.txt.

Links use relative paths to individual llms.txt files instead of HTTP URLs,
enabling local navigation without a web server.

Usage:
    python LLMs/scripts/gen-llms-txt/gen_cc_extensions_meta.py
    python LLMs/scripts/gen-llms-txt/gen_cc_extensions_meta.py --cc-ext-dir /path/to/cc-extensions
"""

import argparse
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
_REPO_ROOT = _SCRIPT_DIR.parent.parent.parent
_DEFAULT_CC_EXT_DIR = _REPO_ROOT / 'LLMs' / 'work' / 'gen-out' / 'cc-extensions'


def _read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding='utf-8')
    except OSError:
        return None


def _extract_title(content: str) -> str | None:
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith('# ') and not stripped.startswith('## '):
            return stripped[2:].strip()
    return None


def _extract_blockquote(content: str) -> str | None:
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith('> ') and '{BLOCKQUOTE}' not in stripped:
            return stripped[2:].strip()
    return None


def collect_entries(cc_ext_dir: Path) -> list[tuple[str, str, str | None]]:
    """Return [(rel_path, title, blockquote)] for each llms.txt, sorted."""
    entries = []
    for llms_txt in sorted(cc_ext_dir.rglob('llms.txt')):
        if llms_txt.parent == cc_ext_dir:
            continue  # skip the meta file itself
        content = _read_text(llms_txt)
        if content is None:
            continue
        rel = llms_txt.relative_to(cc_ext_dir).as_posix()
        title = _extract_title(content) or str(llms_txt.parent.relative_to(cc_ext_dir))
        blockquote = _extract_blockquote(content)
        entries.append((rel, title, blockquote))
    return entries


def generate(cc_ext_dir: Path) -> None:
    entries = collect_entries(cc_ext_dir)
    if not entries:
        print(f'No llms.txt files found under {cc_ext_dir}')
        return

    lines = [
        '# Claude Code Extensions',
        '',
        '> Claude Code 拡張（Skill / Rule / Agent 等）リポジトリのローカルインデックス。'
        'generate-llms-txt --cc-extensions で生成した個別リポジトリの llms.txt へのナビゲーションファイル。',
        '',
        '## Extensions',
        '',
    ]
    for rel_path, title, blockquote in entries:
        entry = f'- [{title}]({rel_path})'
        if blockquote:
            entry += f': {blockquote}'
        lines.append(entry)
    lines.append('')

    output = cc_ext_dir / 'llms.txt'
    output.write_text('\n'.join(lines), encoding='utf-8')
    print(f'Generated: {output}')
    print(f'Indexed {len(entries)} extension(s).')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        '--cc-ext-dir', type=Path, default=_DEFAULT_CC_EXT_DIR,
        help=f'Root of cc-extensions output directory (default: {_DEFAULT_CC_EXT_DIR})',
    )
    args = parser.parse_args()

    cc_ext_dir = args.cc_ext_dir.resolve()
    if not cc_ext_dir.is_dir():
        print(f'ERROR: Not a directory: {cc_ext_dir}')
        raise SystemExit(1)

    generate(cc_ext_dir)


if __name__ == '__main__':
    main()
