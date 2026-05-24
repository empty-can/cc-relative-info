#!/usr/bin/env python3
"""Generate llms-full.txt and llms.txt from a local repository.

Type A: documentation files (.md / .mdx / .rst)
Type C: source code signatures via codesigs (add --extract-sigs)
"""

import argparse
import re
import sys
from pathlib import Path

# Default output base: LLMs/work/gen-out/ inside this repository
_SCRIPT_DIR = Path(__file__).resolve().parent          # gen-llms-txt/
_REPO_ROOT = _SCRIPT_DIR.parent.parent.parent          # cc-relative-info/
_DEFAULT_OUTPUT_BASE = _REPO_ROOT / 'LLMs' / 'work' / 'gen-out'

SECTION_RULES = [
    (['install', 'setup', 'quickstart', 'getting-started', 'getting_started', 'start'], 'Getting Started'),
    (['api', 'reference', 'spec'], 'API Reference'),
    (['guide', 'tutorial', 'how-to', 'how_to', 'howto', 'example'], 'Guide'),
    (['changelog', 'release', 'faq', 'contributing', 'license', 'security', 'migration'], 'Optional'),
]
SECTION_ORDER = ['Getting Started', 'Guide', 'API Reference', 'Optional']
DOC_EXTENSIONS = ('.md', '.mdx', '.rst')
SOURCE_EXTENSIONS = (
    '.py', '.ts', '.tsx', '.js', '.jsx',
    '.go', '.rs', '.java', '.kt', '.swift', '.cs', '.rb', '.php', '.lua',
)
SKIP_DIRS = {
    '.git', '.github', 'node_modules', 'vendor', '__pycache__',
    '.venv', 'venv', 'dist', 'build', 'site', '.tox',
}


# ---------------------------------------------------------------------------
# Frontmatter helpers
# ---------------------------------------------------------------------------

def parse_frontmatter(content: str) -> dict[str, str]:
    """Extract key-value pairs from YAML frontmatter (--- block at file top)."""
    lines = content.splitlines()
    if not lines or lines[0].strip() != '---':
        return {}
    end = -1
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            end = i
            break
    if end == -1:
        return {}
    fm: dict[str, str] = {}
    for line in lines[1:end]:
        if ':' in line:
            key, _, val = line.partition(':')
            fm[key.strip()] = val.strip().strip('"\'')
    return fm


def _frontmatter_end(lines: list[str]) -> int:
    """Return index of the line *after* the closing --- of frontmatter, or 0 if none."""
    if not lines or lines[0].strip() != '---':
        return 0
    for i, line in enumerate(lines[1:], 1):
        if line.strip() == '---':
            return i + 1
    return 0


def _is_non_prose(stripped: str) -> bool:
    """Return True for lines that are not readable prose (skip in description extraction)."""
    return (
        stripped.startswith('[![')
        or stripped.startswith('<!--')
        or stripped.startswith('> ')
        or re.match(r'^[-*_]{3,}$', stripped) is not None
        or stripped.startswith('```')
        or stripped.startswith('|')
        or stripped.startswith('#')
        or bool(re.match(r'^<[A-Z/]', stripped))  # JSX / HTML block tags
    )


# ---------------------------------------------------------------------------
# Section classification
# ---------------------------------------------------------------------------

def classify_section(file_path: Path, repo_path: Path) -> str | None:
    """Return section name for a doc file, or None to skip (README)."""
    stem = file_path.stem.lower()
    if stem == 'readme':
        return None
    rel = file_path.relative_to(repo_path)
    # Split each path component by word separators to avoid substring false-matches
    # e.g. "rapid" must not match "api"; "reference" must match exactly
    segments = set(re.split(r'[\-_./]', ' '.join(p.lower() for p in rel.parts)))
    for keywords, section in SECTION_RULES:
        if any(kw in segments for kw in keywords):
            return section
    return 'Guide'


# ---------------------------------------------------------------------------
# Content extraction — chain-of-responsibility pattern
#
# Each _try_* function has the signature:
#   (file_path, content, lines, fm_end) -> str | None
# Extractors are tried in order; first non-None result wins.
#
# To support a new file format or add a heuristic:
#   1. Define a _try_* function below.
#   2. Insert it in _TITLE_EXTRACTORS or _DESC_EXTRACTORS for the target
#      extension(s). No other code needs to change.
# ---------------------------------------------------------------------------

# Number of lines from body start to search for a document-level H1.
# Intentionally short to avoid picking up headings buried inside body text.
H1_SEARCH_WINDOW = 20


# --- Title extractors -------------------------------------------------------

def _try_frontmatter_title(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    return parse_frontmatter(content).get('title') or None


def _try_head_h1(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    """Return the first H1 within H1_SEARCH_WINDOW lines after frontmatter."""
    for line in lines[fm_end:fm_end + H1_SEARCH_WINDOW]:
        stripped = line.strip()
        if stripped.startswith('# ') and not stripped.startswith('## '):
            return stripped[2:].strip()
    return None


def _try_rst_h1(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    for i, line in enumerate(lines[fm_end:fm_end + H1_SEARCH_WINDOW], fm_end):
        stripped = line.strip()
        if not stripped or not stripped[0].isalpha():
            continue
        if i + 1 < len(lines):
            underline = lines[i + 1].strip()
            if (underline and len(underline) >= len(stripped)
                    and all(c in '=-~^"\'`#*+' for c in underline)):
                return stripped
    return None


def _try_filename_title(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    return file_path.stem.replace('-', ' ').replace('_', ' ').title()


# Extension → ordered title extractors (first non-None wins)
_TITLE_EXTRACTORS: dict[str, list] = {
    '.md':  [_try_frontmatter_title, _try_head_h1,  _try_filename_title],
    '.mdx': [_try_frontmatter_title, _try_head_h1,  _try_filename_title],
    '.rst': [_try_rst_h1,            _try_filename_title],
}
_DEFAULT_TITLE_EXTRACTORS = [_try_head_h1, _try_filename_title]


# --- Description extractors -------------------------------------------------

def _try_frontmatter_desc(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    return parse_frontmatter(content).get('description') or None


def _has_real_h1(lines: list[str], start: int) -> bool:
    """Detect a real H1 outside code blocks (full-file scan, used for desc extraction)."""
    in_code = False
    for line in lines[start:]:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            continue
        if not in_code and stripped.startswith('# ') and not stripped.startswith('## '):
            return True
    return False


def _clean_prose(text: str) -> str:
    """Strip common Markdown formatting from a prose string."""
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'\*(.+?)\*',     r'\1', text)
    text = re.sub(r'`(.+?)`',       r'\1', text)
    text = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', text)
    return text


def _try_body_first_sentence(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    """First prose sentence after H1 (or body start if no H1), skipping code/JSX."""
    has_h1 = _has_real_h1(lines, fm_end)
    after_h1 = False
    in_code = False
    jsx_depth = 0
    paragraph: list[str] = []

    for line in lines[fm_end:]:
        stripped = line.strip()

        if stripped.startswith('```'):
            in_code = not in_code
            if paragraph:
                break
            continue
        if in_code:
            continue

        if re.match(r'^<[A-Z][A-Za-z]*[\s>]', stripped):
            jsx_depth += 1
            if paragraph:
                break
            continue
        if re.match(r'^</[A-Z]', stripped):
            jsx_depth = max(0, jsx_depth - 1)
            continue
        if jsx_depth > 0:
            continue

        if has_h1 and not after_h1:
            if stripped.startswith('# ') and not stripped.startswith('## '):
                after_h1 = True
            continue
        if not stripped:
            if paragraph:
                break
            continue
        if _is_non_prose(stripped):
            if paragraph:
                break
            continue
        paragraph.append(stripped)

    if not paragraph:
        return None

    text = _clean_prose(' '.join(paragraph))
    m = re.match(r'(.+?[.!?])(?:\s|$)', text)
    if m:
        return m.group(1).strip()
    return (text[:150] + '…').strip() if len(text) > 150 else text.strip()


# Extension → ordered description extractors
# Add '.rst': [...] or other extensions here to extend support.
_DESC_EXTRACTORS: dict[str, list] = {
    '.md':  [_try_frontmatter_desc, _try_body_first_sentence],
    '.mdx': [_try_frontmatter_desc, _try_body_first_sentence],
    '.rst': [],  # rst body extraction not implemented; add _try_* here to enable
}
_DEFAULT_DESC_EXTRACTORS: list = []


# --- Dispatch engine --------------------------------------------------------

def _run_extractors(
    extractors: list,
    file_path: Path,
    content: str,
    lines: list[str],
    fm_end: int,
) -> str | None:
    for extractor in extractors:
        result = extractor(file_path, content, lines, fm_end)
        if result:
            return result
    return None


def link_title(file_path: Path, content: str) -> str:
    lines = content.splitlines()
    fm_end = _frontmatter_end(lines)
    extractors = _TITLE_EXTRACTORS.get(file_path.suffix, _DEFAULT_TITLE_EXTRACTORS)
    return _run_extractors(extractors, file_path, content, lines, fm_end) or file_path.stem


def extract_first_sentence(file_path: Path, content: str) -> str | None:
    lines = content.splitlines()
    fm_end = _frontmatter_end(lines)
    extractors = _DESC_EXTRACTORS.get(file_path.suffix, _DEFAULT_DESC_EXTRACTORS)
    return _run_extractors(extractors, file_path, content, lines, fm_end)


def extract_h1(file_path: Path, content: str) -> str | None:
    """Convenience wrapper used for README project-name extraction."""
    lines = content.splitlines()
    fm_end = _frontmatter_end(lines)
    return (
        _try_rst_h1(file_path, content, lines, fm_end)
        if file_path.suffix == '.rst'
        else _try_head_h1(file_path, content, lines, fm_end)
    )


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
    if rel.endswith('.mdx'):
        rel = rel[:-4] + '.md'
    return f"{base_url.rstrip('/')}/{rel}"


# ---------------------------------------------------------------------------
# Source code signature extraction (Type C / --extract-sigs)
# ---------------------------------------------------------------------------

def _sig_name(sig: str) -> str:
    """Extract the function / class name from a codesigs signature string."""
    m = re.search(r'(?:async\s+)?(?:def|class)\s+(\w+)', sig)  # search, not match (indented methods)
    if m:
        return m.group(1)
    return sig.strip().split('(')[0].split('\n')[0].strip()


def _sig_docstring(sig: str) -> str | None:
    """Return the first non-empty line of the docstring in a signature."""
    m = re.search(r'"""(.+?)"""', sig, re.DOTALL) or re.search(r"'''(.+?)'''", sig, re.DOTALL)
    if not m:
        return None
    for line in m.group(1).splitlines():
        stripped = line.strip()
        if stripped:
            return stripped
    return None


def _module_title(file_path: Path, repo_path: Path) -> str:
    """Convert a source file path to a dotted module name (e.g. mcpdoc.main)."""
    rel = file_path.relative_to(repo_path)
    parts = list(rel.parts[:-1]) + [rel.stem]
    return '.'.join(parts)


def collect_source_sections(
    repo_path: Path,
    base_url: str,
) -> list[tuple[Path, str, str, list[tuple[str, str | None]]]]:
    """Return [(file_path, module_title, url, [(name, docstring)])] for source files
    that contain at least one public symbol.
    """
    try:
        from codesigs import file_sigs
    except ImportError:
        print('WARNING: codesigs not installed — skipping --extract-sigs.', file=sys.stderr)
        return []

    SOURCE_SKIP_DIRS = {'tests', 'test', 'spec', '__tests__', 'e2e'}
    SOURCE_SKIP_STEMS = re.compile(r'^(test_.*|.*_test|.*\.test|.*\.spec)$')

    results = []
    for ext in SOURCE_EXTENSIONS:
        for f in sorted(repo_path.rglob(f'*{ext}')):
            rel = f.relative_to(repo_path)
            if _is_skipped(rel.parts[:-1]):
                continue
            # Skip test files and test directories
            if any(p in SOURCE_SKIP_DIRS for p in rel.parts[:-1]):
                continue
            if SOURCE_SKIP_STEMS.match(f.stem.lower()):
                continue
            try:
                sigs = file_sigs(str(f))
            except Exception:
                continue
            public = [
                (_sig_name(s), _sig_docstring(s))
                for s in sigs
                if not _sig_name(s).startswith('_')
            ]
            if public:
                results.append((f, _module_title(f, repo_path), make_url(base_url, f, repo_path), public))

    return results


# ---------------------------------------------------------------------------
# Generation
# ---------------------------------------------------------------------------

def generate(repo_path: Path, base_url: str, output_dir: Path, extract_sigs: bool = False) -> None:
    readme_path, readme_content = find_readme(repo_path)
    project_name = (
        (extract_h1(readme_path, readme_content) if readme_path else None)
        or repo_path.name.replace('-', ' ').replace('_', ' ').title()
    )

    sections = collect_doc_sections(repo_path)
    if not sections:
        print('WARNING: No documentation files found.', file=sys.stderr)

    src_secs = collect_source_sections(repo_path, base_url) if extract_sigs else []

    _write_llms_full(project_name, sections, src_secs, base_url, repo_path, output_dir)
    _write_llms_txt(project_name, sections, src_secs, base_url, repo_path, output_dir)

    total_docs = sum(len(files) for _, files in sections)
    print(f'Processed {total_docs} doc file(s) across {len(sections)} section(s)'
          + (f', {len(src_secs)} source module(s).' if src_secs else '.'))
    print(f'Generated: {output_dir / "llms-full.txt"}')
    print(f'Generated: {output_dir / "llms.txt"}')
    print('Fill {BLOCKQUOTE} and {DESCRIPTION} placeholders via Skill or manually.')


def _write_llms_full(
    project_name: str,
    sections: list[tuple[str, list[tuple[Path, str]]]],
    src_secs: list[tuple[Path, str, str, list[tuple[str, str | None]]]],
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

    if src_secs:
        lines += ['---', '', '## Source Modules', '']
        for f, mod_title, url, syms in src_secs:
            rel = f.relative_to(repo_path).as_posix()
            lines += [f'### {mod_title}', '', f'*Source: {rel} | URL: {url}*', '']
            for name, doc in syms:
                entry = f'- `{name}`'
                if doc:
                    entry += f': {doc}'
                lines.append(entry)
            lines.append('')

    (output_dir / 'llms-full.txt').write_text('\n'.join(lines), encoding='utf-8')


def _write_llms_txt(
    project_name: str,
    sections: list[tuple[str, list[tuple[Path, str]]]],
    src_secs: list[tuple[Path, str, str, list[tuple[str, str | None]]]],
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

    if src_secs:
        lines += ['## Source Modules', '']
        for _f, mod_title, url, syms in src_secs:
            # Use first public symbol's docstring as the module description
            desc = next((doc for _, doc in syms if doc), None)
            entry = f'- [{mod_title}]({url})'
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
                        help='Output directory (default: LLMs/work/gen-out/<repo_name>/)')
    parser.add_argument('--extract-sigs', action='store_true',
                        help='Extract source code signatures via codesigs (Type C)')
    args = parser.parse_args()

    repo_path = args.repo_path.resolve()
    if not repo_path.is_dir():
        print(f'ERROR: Not a directory: {repo_path}', file=sys.stderr)
        sys.exit(1)

    output_dir = (args.output or (_DEFAULT_OUTPUT_BASE / repo_path.name)).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    generate(repo_path, args.base_url, output_dir, extract_sigs=args.extract_sigs)


if __name__ == '__main__':
    main()
