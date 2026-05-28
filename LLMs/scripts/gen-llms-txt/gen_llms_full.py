#!/usr/bin/env python3
"""Generate llms-full.txt and llms.txt from a local repository.

Type A: documentation files (.md / .mdx / .rst)
Type C: source code signatures via codesigs (add --extract-sigs)
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

# Default output base: LLMs/work/gen-out/ inside this repository
_SCRIPT_DIR = Path(__file__).resolve().parent          # gen-llms-txt/
_REPO_ROOT = _SCRIPT_DIR.parent.parent.parent          # cc-relative-info/
_DEFAULT_OUTPUT_BASE = _REPO_ROOT / 'LLMs' / 'work' / 'gen-out'
# Error logs mirror the gen-out tree under a sibling gen-error/ directory.
_DEFAULT_ERROR_BASE = _REPO_ROOT / 'LLMs' / 'work' / 'gen-error'

# Generation warnings collected during a run, flushed to the error log at the end.
_WARNINGS: list[str] = []


def _warn(msg: str) -> None:
    """Print a warning to stderr and record it for the error log."""
    _WARNINGS.append(msg)
    print(f'WARNING: {msg}', file=sys.stderr)


def _infer_output_dir(base_url: str, repo_path: Path, cc_extensions: bool = False) -> Path:
    """Compute default output directory from base_url.

    Normal mode:        LLMs/work/gen-out/<owner>/<repo>/
    CC extensions mode: LLMs/work/gen-out/cc-extensions/<owner>/<repo>/
    """
    root = _DEFAULT_OUTPUT_BASE / 'cc-extensions' if cc_extensions else _DEFAULT_OUTPUT_BASE
    m = re.match(r'https://github\.com/([^/]+)/([^/]+?)(?:/|$)', base_url)
    if m:
        return root / m.group(1) / m.group(2)
    return root / repo_path.name

# ---------------------------------------------------------------------------
# CC Extensions mode: section map for .claude/ subdirectories
# Add entries here to support new .claude/ subdirectory types.
# ---------------------------------------------------------------------------
CC_SECTION_MAP: dict[str, str] = {
    'plugins':   'Plugins',
    'skills':    'Skills',
    'rules':     'Rules',
    'agents':    'Agents',
    'templates': 'Templates',
    'hooks':     'Hooks',
    'scripts':   'Optional',
}
# Sections whose subdirectories each contain a SKILL.md (one entry per subdirectory)
CC_SKILL_LIKE_SECTIONS = {'skills', 'plugins'}
CC_SECTION_ORDER = ['Plugins', 'Skills', 'Rules', 'Agents', 'Templates', 'Hooks', 'Optional', 'Guide']

SECTION_RULES = [
    (['install', 'setup', 'quickstart', 'getting-started', 'getting_started', 'start'], 'Getting Started'),
    (['api', 'reference', 'spec'], 'API Reference'),
    (['guide', 'tutorial', 'how-to', 'how_to', 'howto', 'example'], 'Guide'),
    (['changelog', 'release', 'faq', 'contributing', 'license', 'security', 'migration'], 'Optional'),
]
SECTION_ORDER = ['Getting Started', 'Guide', 'API Reference', 'Optional']
DOC_EXTENSIONS = ('.md', '.mdx', '.rst', '.adoc', '.asciidoc', '.ipynb')
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


def _try_frontmatter_name(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    # 'name:' is used in Skill frontmatter (vs 'title:' in MDX docs)
    return parse_frontmatter(content).get('name') or None


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


def _try_asciidoc_h1(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    """Return the AsciiDoc level-0 document title (a line starting with '= ')."""
    for line in lines[fm_end:fm_end + H1_SEARCH_WINDOW]:
        stripped = line.strip()
        if stripped.startswith('= '):
            return stripped[2:].strip()
    return None


def _try_notebook_h1(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    """First Markdown H1 in a converted notebook, ignoring '#' inside code blocks.

    Notebooks often place export/import code cells before the title cell, so the
    document H1 can appear well past the usual head window.
    """
    in_code = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            continue
        if not in_code and stripped.startswith('# ') and not stripped.startswith('## '):
            return stripped[2:].strip()
    return None


def _try_filename_title(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    return file_path.stem.replace('-', ' ').replace('_', ' ').title()


# Extension → ordered title extractors (first non-None wins)
_TITLE_EXTRACTORS: dict[str, list] = {
    # .md: check 'title:' then 'name:' (used in SKILL.md frontmatter) then H1
    '.md':  [_try_frontmatter_title, _try_frontmatter_name, _try_head_h1, _try_filename_title],
    '.mdx': [_try_frontmatter_title, _try_head_h1,  _try_filename_title],
    '.rst': [_try_rst_h1,            _try_filename_title],
    '.adoc':     [_try_asciidoc_h1, _try_filename_title],
    '.asciidoc': [_try_asciidoc_h1, _try_filename_title],
    '.ipynb':    [_try_notebook_h1, _try_filename_title],
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


def _clean_asciidoc_prose(text: str) -> str:
    """Strip common AsciiDoc inline formatting from a prose string."""
    text = re.sub(r'(?:link|xref):[^\[\]\s]*\[([^\]]*)\]', r'\1', text)  # link:url[text]
    text = re.sub(r'https?://\S*?\[([^\]]*)\]', r'\1', text)             # https://url[text]
    text = re.sub(r'`(.+?)`', r'\1', text)
    text = re.sub(r'\*(.+?)\*', r'\1', text)
    text = re.sub(r'_(.+?)_', r'\1', text)
    return text


def _try_asciidoc_first_sentence(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    """First prose sentence in an AsciiDoc file, skipping headings/attributes/macros."""
    paragraph: list[str] = []
    for raw in lines[fm_end:]:
        stripped = raw.strip()
        if not stripped:
            if paragraph:
                break
            continue
        if (stripped.startswith('=')          # doc title or section heading
                or stripped.startswith(':')   # attribute entry
                or stripped.startswith('//')  # comment
                or stripped.startswith('[')   # block attribute / anchor
                or stripped.startswith('*')   # list item / nav
                or stripped.startswith('.')   # block title / ordered list
                or stripped.startswith('|')   # table cell
                or stripped.startswith('image:')
                or stripped.startswith('xref:')
                or stripped.startswith('include::')  # transclusion directive
                or re.match(r'^[-=~^*_.+]{3,}$', stripped)):  # block delimiter
            if paragraph:
                break
            continue
        paragraph.append(stripped)

    if not paragraph:
        return None

    text = _clean_asciidoc_prose(' '.join(paragraph))
    m = re.match(r'(.+?[.!?])(?:\s|$)', text)
    if m:
        return m.group(1).strip()
    return (text[:150] + '…').strip() if len(text) > 150 else text.strip()


def _try_notebook_desc(
    file_path: Path, content: str, lines: list[str], fm_end: int
) -> str | None:
    """Description for a converted notebook.

    Prefers the nbdev-style '> summary' blockquote right after the title; falls
    back to the first prose sentence. '#' inside code blocks is ignored.
    """
    seen_h1 = False
    in_code = False
    paragraph: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code = not in_code
            if paragraph:
                break
            continue
        if in_code:
            continue
        if not seen_h1:
            if stripped.startswith('# ') and not stripped.startswith('## '):
                seen_h1 = True
            continue
        if stripped.startswith('> '):
            return _clean_prose(stripped[2:].strip())
        if not stripped:
            if paragraph:
                break
            continue
        if (stripped.startswith('#')
                or stripped.startswith('- ') or stripped.startswith('* ')
                or _is_non_prose(stripped)):
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
    '.adoc':     [_try_asciidoc_first_sentence],
    '.asciidoc': [_try_asciidoc_first_sentence],
    '.ipynb':    [_try_notebook_desc],
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


# Antora navigation files are pure menus (xref link lists) with no prose content.
_DOC_NOISE_NAMES = {'nav.adoc', 'local-nav.adoc'}


def _is_noise_doc(f: Path) -> bool:
    """Skip navigation-only docs that carry no standalone prose."""
    return f.name.lower() in _DOC_NOISE_NAMES


_NBFORMAT = None  # cached nbformat module; False once an import attempt has failed


def _get_nbformat():
    """Lazily import nbformat, warning once if it is unavailable."""
    global _NBFORMAT
    if _NBFORMAT is None:
        try:
            import nbformat
            _NBFORMAT = nbformat
        except ImportError:
            _NBFORMAT = False
            _warn('nbformat not installed — .ipynb files skipped. Install: pip install nbformat')
    return _NBFORMAT or None


def _render_notebook(path: Path) -> str | None:
    """Convert a Jupyter notebook to Markdown for indexing.

    Markdown cells verbatim, code cells in fenced blocks, short text outputs.
    Logic mirrors AnswerDotAI nbs2ctx (render_notebook_to_markdown); reimplemented
    here so .ipynb support needs no extra runtime dependency beyond nbformat.
    """
    nbformat = _get_nbformat()
    if not nbformat:
        return None
    try:
        nb = nbformat.read(str(path), as_version=4)
    except Exception:
        return None
    language = nb.metadata.get('kernelspec', {}).get('language', 'python')
    parts: list[str] = []
    for cell in nb.cells:
        if cell.cell_type == 'markdown':
            parts.append(''.join(cell.source))
        elif cell.cell_type == 'code':
            code = ''.join(cell.source)
            if not code.strip():
                continue
            parts.append(f'```{language}\n{code}\n```')
            outputs: list[str] = []
            for output in cell.get('outputs', []):
                otype = output.get('output_type')
                if otype == 'stream':
                    text = ''.join(output.get('text', ''))
                elif otype in ('execute_result', 'display_data'):
                    text = ''.join(output.get('data', {}).get('text/plain', ''))
                else:
                    continue
                if text:
                    outputs.append(text[:200] + (' … (truncated)' if len(text) > 200 else ''))
            if outputs:
                parts.append('**Outputs:**\n' + '\n'.join(outputs))
    return '\n\n'.join(parts)


def _read_doc_content(f: Path) -> str | None:
    """Read a doc file as text, converting notebooks to Markdown."""
    if f.suffix == '.ipynb':
        return _render_notebook(f)
    try:
        return f.read_text(encoding='utf-8', errors='replace')
    except OSError:
        return None


def collect_doc_sections(repo_path: Path) -> list[tuple[str, list[tuple[Path, str]]]]:
    """Return [(section_name, [(file_path, content)])] ordered by SECTION_ORDER."""
    buckets: dict[str, list[tuple[Path, str]]] = {s: [] for s in SECTION_ORDER}

    for ext in DOC_EXTENSIONS:
        for f in sorted(repo_path.rglob(f'*{ext}')):
            rel = f.relative_to(repo_path)
            if _is_skipped(rel.parts[:-1]):
                continue
            if _is_noise_doc(f):
                continue
            section = classify_section(f, repo_path)
            if section is None:
                continue
            content = _read_doc_content(f)
            if content and content.strip():
                buckets[section].append((f, content))

    return [(s, buckets[s]) for s in SECTION_ORDER if buckets[s]]


def find_readme(repo_path: Path) -> tuple[Path | None, str]:
    for name in ('README.md', 'readme.md', 'README.rst', 'readme.rst'):
        p = repo_path / name
        if p.exists():
            return p, p.read_text(encoding='utf-8', errors='replace')
    return None, ''


def _read_md(path: Path) -> str | None:
    """Read a Markdown file, return None on error or empty content."""
    try:
        content = path.read_text(encoding='utf-8', errors='replace')
        return content if content.strip() else None
    except OSError:
        return None


def _scan_cc_base(base: Path, buckets: dict[str, list[tuple[Path, str]]]) -> None:
    """Scan one base directory (root or .claude/) for CC extension files.

    Layout handled:
    - skills/<name>/SKILL.md  → Skills section (primary entry per skill)
    - rules/*.md              → Rules section
    - agents/*.md             → Agents section
    - templates/*.md          → Templates section
    - hooks/*.md / scripts/*  → Optional section
    """
    if not base.is_dir():
        return

    for section_key, section_name in CC_SECTION_MAP.items():
        section_dir = base / section_key
        if not section_dir.is_dir():
            continue

        if section_key in CC_SKILL_LIKE_SECTIONS:
            # Each subdirectory is one skill/plugin; SKILL.md is the canonical entry.
            for skill_dir in sorted(d for d in section_dir.iterdir() if d.is_dir()):
                skill_md = skill_dir / 'SKILL.md'
                if skill_md.exists():
                    content = _read_md(skill_md)
                    if content:
                        buckets[section_name].append((skill_md, content))
        else:
            # Other sections: collect .md files directly in the section directory.
            for ext in DOC_EXTENSIONS:
                for f in sorted(section_dir.glob(f'*{ext}')):
                    content = _read_md(f)
                    if content:
                        buckets[section_name].append((f, content))


def collect_cc_sections(repo_path: Path) -> list[tuple[str, list[tuple[Path, str]]]]:
    """Collect Claude Code extension files for search-optimized indexing.

    Supports two common layouts automatically:

    Standalone extension repo (e.g. anthropics/skills):
      skills/<name>/SKILL.md, rules/*.md, agents/*.md at repo root

    Project-embedded (e.g. .claude/ inside a project):
      .claude/skills/<name>/SKILL.md, .claude/rules/*.md, etc.
    """
    buckets: dict[str, list[tuple[Path, str]]] = {s: [] for s in CC_SECTION_ORDER}

    # Pattern A: standalone extension repo (skills/ at repo root)
    _scan_cc_base(repo_path, buckets)

    # Pattern B: embedded in project (.claude/ directory)
    _scan_cc_base(repo_path / '.claude', buckets)

    if not any(buckets.values()):
        _warn('No CC extension files found '
              '(checked skills/, .claude/skills/, rules/, .claude/rules/)')

    return [(s, buckets[s]) for s in CC_SECTION_ORDER if buckets[s]]


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
        _warn('codesigs not installed — skipping --extract-sigs.')
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

def generate(
    repo_path: Path,
    base_url: str,
    output_dir: Path,
    extract_sigs: bool = False,
    cc_extensions: bool = False,
) -> None:
    readme_path, readme_content = find_readme(repo_path)
    project_name = (
        (extract_h1(readme_path, readme_content) if readme_path else None)
        or repo_path.name.replace('-', ' ').replace('_', ' ').title()
    )

    if cc_extensions:
        sections = collect_cc_sections(repo_path)
        src_secs = collect_source_sections(repo_path, base_url)  # always enabled in CC mode
        if not sections:
            _warn('No .claude/ files found.')
    else:
        sections = collect_doc_sections(repo_path)
        if not sections:
            _warn('No documentation files found.')
        src_secs = collect_source_sections(repo_path, base_url) if extract_sigs else []

    _write_llms_full(project_name, sections, src_secs, base_url, repo_path, output_dir)
    _write_llms_txt(project_name, sections, src_secs, base_url, repo_path, output_dir)

    total_docs = sum(len(files) for _, files in sections)
    mode_label = 'CC extension file(s)' if cc_extensions else 'doc file(s)'
    print(f'Processed {total_docs} {mode_label} across {len(sections)} section(s)'
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
# Error log (mirrored under gen-error/, sibling of gen-out/)
# ---------------------------------------------------------------------------

def _error_log_dir(output_dir: Path) -> Path:
    """Mirror output_dir under the gen-error tree so logs never collide with output."""
    try:
        rel = output_dir.relative_to(_DEFAULT_OUTPUT_BASE)
        return _DEFAULT_ERROR_BASE / rel
    except ValueError:
        # Custom --output not under the default gen-out base.
        parts = list(output_dir.parts)
        if 'gen-out' in parts:
            parts[parts.index('gen-out')] = 'gen-error'
            return Path(*parts)
        # Last resort: a gen-error sibling next to the output directory.
        return output_dir.parent / 'gen-error' / output_dir.name


def _write_error_log(output_dir: Path, *, cc_extensions: bool, extract_sigs: bool) -> None:
    """Flush collected warnings to error-log.md under the gen-error tree."""
    error_dir = _error_log_dir(output_dir)
    error_dir.mkdir(parents=True, exist_ok=True)
    try:
        target_id = output_dir.relative_to(_DEFAULT_OUTPUT_BASE).as_posix()
    except ValueError:
        target_id = output_dir.name
    lines = [
        f'# Error Log: {target_id}',
        f'CC_EXTENSIONS={str(cc_extensions).lower()}',
        f'EXTRACT_SIGS={str(extract_sigs).lower()}',
        '',
    ]
    if _WARNINGS:
        lines += [f'## Result: completed with {len(_WARNINGS)} warning(s)', '', '## Warnings']
        lines += [f'- {w}' for w in _WARNINGS]
    else:
        lines += ['## Result: SUCCESS (no warnings)', '',
                  'No errors encountered. Generation completed successfully.']
    lines.append('')
    (error_dir / 'error-log.md').write_text('\n'.join(lines), encoding='utf-8')
    print(f'Error log: {error_dir / "error-log.md"}')


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
                        help='Output directory '
                             '(default: LLMs/work/gen-out/<owner>/<repo>/ for GitHub URLs, '
                             'LLMs/work/gen-out/<repo_name>/ otherwise)')
    parser.add_argument('--extract-sigs', action='store_true',
                        help='Extract source code signatures via codesigs (Type C)')
    parser.add_argument('--cc-extensions', action='store_true',
                        help='Index .claude/ Skills/Rules/Agents for Claude Code extension search')
    parser.add_argument('--skip-if-unchanged', action='store_true',
                        help='Skip generation if llms.txt is newer than the latest commit')
    args = parser.parse_args()

    repo_path = args.repo_path.resolve()
    if not repo_path.is_dir():
        print(f'ERROR: Not a directory: {repo_path}', file=sys.stderr)
        sys.exit(1)

    output_dir = (args.output or _infer_output_dir(args.base_url, repo_path, args.cc_extensions)).resolve()

    if args.skip_if_unchanged:
        llms_txt = output_dir / 'llms.txt'
        if llms_txt.exists():
            try:
                result = subprocess.run(
                    ['git', '-C', str(repo_path), 'log', '-1', '--format=%ct'],
                    capture_output=True, text=True, check=True,
                )
                commit_ts = int(result.stdout.strip())
                if llms_txt.stat().st_mtime > commit_ts:
                    print(f'SKIPPED: {llms_txt.name} is up to date'
                          f' (commit={commit_ts}, mtime={int(llms_txt.stat().st_mtime)})')
                    sys.exit(0)
            except Exception:
                pass  # fall through to normal generation on any error

    output_dir.mkdir(parents=True, exist_ok=True)

    generate(repo_path, args.base_url, output_dir,
             extract_sigs=args.extract_sigs, cc_extensions=args.cc_extensions)

    _write_error_log(output_dir, cc_extensions=args.cc_extensions,
                     extract_sigs=args.extract_sigs)


if __name__ == '__main__':
    main()
