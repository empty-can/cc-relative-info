"""Derive the light version of an update-summary from the detail version.

Reads `<dir>/latest-detail.md` and writes `<dir>/latest.md`.

The light version is built by:
  1. copying the frontmatter (`--- ... ---`)
  2. taking the title (`# ...`) and stripping a trailing " - 詳細版" suffix
  3. extracting each `<!-- light:<name>:start --> ... <!-- light:<name>:end -->` block
  4. for the highlight / new-pages / updated-pages blocks, wrapping the bold
     `**<title>**` in each bullet with a Markdown link pointing to
     `./latest-detail.md#<anchor>` (GFM-style anchor)
  5. copying the `## 関連リンク` block as-is
  6. copying the trailing HTML comment that holds the run metadata
     (`base_commit` / `head_commit` / `generated_at_full`)

Run:
    python derive_light.py <path/to/latest-detail.md>

Exit codes: 0 on success, 1 on missing/invalid input, 2 on usage error.
"""
import re
import sys
from pathlib import Path

DETAIL_FILENAME = 'latest-detail.md'
LIGHT_FILENAME = 'latest.md'

# Marker names whose bullets contain internal links (#anchor) that should be
# rewritten to point at the detail file (./latest-detail.md#anchor).
LINKED_SECTIONS = frozenset({'highlight-list', 'new-pages', 'updated-pages', 'whats-new'})

# Section header to emit before the extracted content for each marker name.
# An empty string means "no header" (used for the summary blockquote).
SECTION_HEADERS = {
    'summary':        '',
    'highlight-list': '## ハイライト',
    'new-pages':      '## 新規追加されたページ',
    'updated-pages':  '## 大幅に更新されたページ',
    'minor-updates':  '## 軽微な更新',
    'whats-new':      '## 新着情報',
}


def make_anchor(text: str) -> str:
    """GFM-style anchor: lowercase, spaces->hyphens, strip non-word/non-hyphen.

    Japanese (and other non-ASCII letters) are preserved because `\\w` with
    re.UNICODE matches them.
    """
    s = text.strip().lower()
    s = re.sub(r'\s+', '-', s)
    s = re.sub(r'[^\w\-]', '', s, flags=re.UNICODE)
    return s


def extract_frontmatter(text: str) -> tuple[str, str]:
    m = re.match(r'^(---\n.*?\n---\n)', text, re.DOTALL)
    if not m:
        return '', text
    return m.group(1), text[m.end():]


def extract_footer(text: str) -> tuple[str, str]:
    """Strip the trailing run-metadata HTML comment and return it separately."""
    m = re.search(r'(<!--\s*\nbase_commit:.*?-->)\s*$', text, re.DOTALL)
    if not m:
        return text.rstrip() + '\n', ''
    return text[:m.start()].rstrip() + '\n', m.group(1)


def extract_marker_regions(text: str) -> list[tuple[str, str]]:
    """Return [(name, inner_content), ...] preserving file order."""
    pattern = re.compile(
        r'<!--\s*light:([a-zA-Z\-]+):start\s*-->\s*\n(.*?)\n<!--\s*light:\1:end\s*-->',
        re.DOTALL,
    )
    return [(m.group(1), m.group(2)) for m in pattern.finditer(text)]


def linkify_bullets(content: str) -> str:
    """Convert internal links to point at the detail file.

    The detail-side template uses internal anchors (`[label](#anchor)`) for headings
    that link to other sections within the same detail file. In the light version,
    those same labels need to point at the detail file, so we rewrite each `(#anchor)`
    to `(./latest-detail.md#anchor)`.

    Bare bullets in the form `- **<title>**:` (no link) are also wrapped retroactively
    as a fallback, so a malformed detail still produces a usable light version.
    """
    # Pass 1: rewrite internal anchor refs to point at the detail file
    content = re.sub(r'\]\(#([^)]+)\)', rf'](./{DETAIL_FILENAME}#\1)', content)

    # Pass 2: fallback — if a bullet starts with a bare `**<title>**` (no link), wrap it.
    # Matches both `- **...**` and `N. **...**` so numbered highlight lists are also handled.
    def repl(m: re.Match) -> str:
        marker = m.group(1)
        title = m.group(2)
        rest = m.group(3)
        anchor = make_anchor(title)
        return f'{marker}[**{title}**](./{DETAIL_FILENAME}#{anchor}){rest}'

    return re.sub(r'^(- |\d+\. )\*\*([^*\n]+)\*\*(?!\])(.*)$', repl, content, flags=re.MULTILINE)


def extract_related_links(text: str) -> str:
    """Pull the `## 関連リンク` section verbatim (used outside the light: markers)."""
    m = re.search(
        r'^## 関連リンク\s*\n.*?(?=^##|\Z)',
        text, re.MULTILINE | re.DOTALL,
    )
    return m.group(0).rstrip() if m else ''


def derive(detail_text: str) -> str:
    frontmatter, body = extract_frontmatter(detail_text)
    body, footer = extract_footer(body)

    title_match = re.search(r'^# (.+)$', body, re.MULTILINE)
    if not title_match:
        raise SystemExit('ERROR: No top-level title (# ...) found in detail file')
    light_title = '# ' + re.sub(r'\s*-\s*詳細版\s*$', '', title_match.group(1))

    regions = extract_marker_regions(body)
    if not regions:
        raise SystemExit('ERROR: No <!-- light:*:start --> markers found in detail file')

    # 概要件数 <= ハイライト件数 を保証する。概要(summary blockquote の `> N.`)が
    # ハイライト(`N.`)より多いと、読み手が件数差を不審に思うため、ここで弾く。
    region_map = dict(regions)
    n_summary = len(re.findall(r'^>\s*\d+\.\s', region_map.get('summary', ''), re.MULTILINE))
    n_highlight = len(re.findall(r'^\d+\.\s', region_map.get('highlight-list', ''), re.MULTILINE))
    if n_summary > n_highlight:
        raise SystemExit(
            f'ERROR: 概要項目数({n_summary}) > ハイライト項目数({n_highlight})。'
            '概要はハイライトと同集合(同数)にしてください。'
        )

    related = extract_related_links(body)

    parts: list[str] = []
    if frontmatter:
        parts.append(frontmatter.rstrip())
        parts.append('')
    parts.append(light_title)
    parts.append('')

    for name, inner in regions:
        header = SECTION_HEADERS.get(name, f'## {name}')
        if name in LINKED_SECTIONS:
            inner = linkify_bullets(inner)
        if header:
            parts.append(header)
            parts.append('')
        parts.append(inner)
        parts.append('')

    if related:
        parts.append(related)
        parts.append('')

    if footer:
        parts.append(footer)

    return '\n'.join(parts).rstrip() + '\n'


def main() -> int:
    if len(sys.argv) != 2:
        print(f'Usage: python {Path(sys.argv[0]).name} <path/to/{DETAIL_FILENAME}>',
              file=sys.stderr)
        return 2

    detail_path = Path(sys.argv[1]).resolve()
    if not detail_path.is_file():
        print(f'ERROR: File not found: {detail_path}', file=sys.stderr)
        return 1
    if detail_path.name != DETAIL_FILENAME:
        print(f'WARNING: Expected file named {DETAIL_FILENAME}, got {detail_path.name}',
              file=sys.stderr)

    light_path = detail_path.parent / LIGHT_FILENAME
    light_content = derive(detail_path.read_text(encoding='utf-8'))
    light_path.write_text(light_content, encoding='utf-8')
    print(f'Generated: {light_path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
