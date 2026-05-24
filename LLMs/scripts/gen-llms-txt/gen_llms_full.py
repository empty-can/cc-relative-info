#!/usr/bin/env python3
"""Generate llms-full.txt and llms.txt from a local repository.

Type A: documentation files (.md / .rst)
Type C: source code signatures via codesigs (add --extract-sigs)
"""

import argparse
import re
import sys
from pathlib import Path

SECTION_RULES = [
    (['install', 'setup', 'quickstart', 'getting-started', 'getting_started', 'start'], 'Getting Started'),
    (['api', 'reference', 'spec'], 'API Reference'),
    (['guide', 'tutorial', 'how-to', 'how_to', 'howto', 'example'], 'Guide'),
    (['changelog', 'release', 'faq', 'contributing', 'license', 'security', 'migration'], 'Optional'),
]
SECTION_ORDER = ['Getting Started', 'Guide', 'API Reference', 'Optional']
DOC_EXTENSIONS = ('.md', '.rst')
SKIP_DIRS = {
    '.git', '.github', 'node_modules', 'vendor', '__pycache__',
    '.venv', 'venv', 'dist', 'build', 'site', '.tox',
}


# ---------------------------------------------------------------------------
# Section classification
# ---------------------------------------------------------------------------

def classify_section(file_path: Path, repo_path: Path) -> str | None:
    """Return section name for a doc file, or None to skip (README)."""
    stem = file_path.stem.lower()
    if stem == 'readme':
        return None
    rel_str = ' '.join(p.lower() for p in file_path.relative_to(repo_path).parts)
    for keywords, section in SECTION_RULES:
        if any(kw in rel_str for kw in keywords):
            return section
    return 'Guide'


# ---------------------------------------------------------------------------
# Content extraction
# ---------------------------------------------------------------------------

def _md_h1(content: str) -> str | None:
    for line in content.splitlines():
        stripped = line.strip()
        if stripped.startswith('# '):
            return stripped[2:].strip()
    return None


def _rst_h1(content: str) -> str | None:
    lines = content.splitlines()
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or not stripped[0].isalpha():
            continue
        if i + 1 < len(lines):
            underline = lines[i + 1].strip()
            if underline and len(underline) >= len(stripped) and all(c in '=-~^"\'`#*+' for c in underline):
                return stripped
    return None


def extract_h1(file_path: Path, content: str) -> str | None:
    if file_path.suffix == '.rst':
        return _rst_h1(content)
    return _md_h1(content)


def extract_first_sentence(file_path: Path, content: str) -> str | None:
    """Extract first meaningful sentence from the paragraph following H1 (Markdown only)."""
    if file_path.suffix != '.md':
        return None

    lines = content.splitlines()
    after_h1 = False
    paragraph: list[str] = []

    for line in lines:
        stripped = line.strip()
        if not after_h1:
            if stripped.startswith('# '):
                after_h1 = True
            continue
        if not stripped:
            if paragraph:
                break
            continue
        # Skip badges, HTML comments, blockquotes, rules, code fences, tables, headings
        if (stripped.startswith('[![') or stripped.startswith('<!--')
                or stripped.startswith('> ') or re.match(r'^[-*_]{3,}$', stripped)
                or stripped.startswith('```') or stripped.startswith('|')
                or stripped.startswith('#')):
            if paragraph:
                break
            continue
        paragraph.append(stripped)

    if not paragraph:
        return None

    text = ' '.join(paragraph)
    # Strip markdown formatting
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'`(.+?)`', r'\1', text)
    text = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', text)

    m = re.match(r'(.+?[.!?])(?:\s|$)', text)
    if m:
        return m.group(1).strip()
    return (text[:150] + '…').strip() if len(text) > 150 else text.strip()


def link_title(file_path: Path, content: str) -> str:
    h1 = extract_h1(file_path, content)
    if h1:
        return h1
    return file_path.stem.replace('-', ' ').replace('_', ' ').title()


# ---------------------------------------------------------------------------
# File collection
# ---------------------------------------------------------------------------

def _is_skipped(rel_parts: tuple[str, ...]) -> bool:
    return any(p in SKIP_DIRS or p.startswith('.') for p in rel_parts)


def collect_doc_sections(repo_path: Path) -> list[tuple[str, list[tuple[Path, str]]]]:
    """Return [(section_name, [(file_path, content)])] ordered by SECTION_ORDER."""
    buckets: dict[str, list[tuple[Path, str]]] = {s: [] for s in SECTION_ORDER}

    for ext in DOC_EXTENSIONS:
        for f in sorted(repo_path.rglob(f'*{ext}')):
            rel = f.relative_to(repo_path)
            if _is_skipped(rel.parts[:-1]):
                continue
            section = classify_section(f, repo_path)
            if section is None:
                continue
            try:
                content = f.read_text(encoding='utf-8', errors='replace')
            except OSError:
                continue
            if content.strip():
                buckets[section].append((f, content))

    return [(s, buckets[s]) for s in SECTION_ORDER if buckets[s]]


def find_readme(repo_path: Path) -> tuple[Path | None, str]:
    for name in ('README.md', 'readme.md', 'README.rst', 'readme.rst'):
        p = repo_path / name
        if p.exists():
            return p, p.read_text(encoding='utf-8', errors='replace')
    return None, ''


# ---------------------------------------------------------------------------
# URL construction
# ---------------------------------------------------------------------------

def make_url(base_url: str, file_path: Path, repo_path: Path) -> str:
    rel = file_path.relative_to(repo_path).as_posix()
    return f"{base_url.rstrip('/')}/{rel}"


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

def generate(repo_path: Path, base_url: str, output_dir: Path) -> None:
    readme_path, readme_content = find_readme(repo_path)
    project_name = (
        (extract_h1(readme_path, readme_content) if readme_path else None)
        or repo_path.name.replace('-', ' ').replace('_', ' ').title()
    )

    sections = collect_doc_sections(repo_path)
    if not sections:
        print('WARNING: No documentation files found.', file=sys.stderr)

    _write_llms_full(project_name, sections, base_url, repo_path, output_dir)
    _write_llms_txt(project_name, sections, base_url, repo_path, output_dir)

    total = sum(len(files) for _, files in sections)
    print(f'Processed {total} file(s) across {len(sections)} section(s).')
    print(f'Generated: {output_dir / "llms-full.txt"}')
    print(f'Generated: {output_dir / "llms.txt"}')
    print('Fill {BLOCKQUOTE} and {DESCRIPTION} placeholders via Skill or manually.')


def _write_llms_full(
    project_name: str,
    sections: list[tuple[str, list[tuple[Path, str]]]],
    base_url: str,
    repo_path: Path,
    output_dir: Path,
) -> None:
    lines = [f'# {project_name}', '', '> {BLOCKQUOTE}', '', '{DESCRIPTION}', '']

    for section_name, files in sections:
        lines += ['---', '', f'## {section_name}', '']
        for f, content in files:
            url = make_url(base_url, f, repo_path)
            title = link_title(f, content)
            rel = f.relative_to(repo_path).as_posix()
            lines += [
                f'### {title}',
                '',
                f'*Source: {rel} | URL: {url}*',
                '',
                content.strip(),
                '',
            ]

    (output_dir / 'llms-full.txt').write_text('\n'.join(lines), encoding='utf-8')


def _write_llms_txt(
    project_name: str,
    sections: list[tuple[str, list[tuple[Path, str]]]],
    base_url: str,
    repo_path: Path,
    output_dir: Path,
) -> None:
    lines = [f'# {project_name}', '', '> {BLOCKQUOTE}', '', '{DESCRIPTION}', '']

    for section_name, files in sections:
        lines += [f'## {section_name}', '']
        for f, content in files:
            url = make_url(base_url, f, repo_path)
            title = link_title(f, content)
            desc = extract_first_sentence(f, content)
            entry = f'- [{title}]({url})'
            if desc:
                entry += f': {desc}'
            lines.append(entry)
        lines.append('')

    (output_dir / 'llms.txt').write_text('\n'.join(lines), encoding='utf-8')


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('repo_path', type=Path,
                        help='Path to local repository')
    parser.add_argument('--base-url', required=True,
                        help='Base URL for links '
                             '(e.g. https://github.com/org/repo/blob/main/)')
    parser.add_argument('--output', type=Path, default=None,
                        help='Output directory (default: repo_path)')
    args = parser.parse_args()

    repo_path = args.repo_path.resolve()
    if not repo_path.is_dir():
        print(f'ERROR: Not a directory: {repo_path}', file=sys.stderr)
        sys.exit(1)

    output_dir = (args.output or repo_path).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    generate(repo_path, args.base_url, output_dir)


if __name__ == '__main__':
    main()
