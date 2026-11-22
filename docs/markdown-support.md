# Supported Markdown

Margin uses its own deterministic, line-oriented parser (`Margin/MarkdownKit`) rather than a
CommonMark library. It targets the Markdown people actually write in notes and documents; this
page lists exactly what is recognized so there are no surprises between Write, Read, Split,
Quick Look, and export — all of which share the same parser.

## Blocks

| Construct | Syntax | Notes |
| --- | --- | --- |
| Heading | `#` … `######` | ATX, up to 3 leading spaces; optional closing `#`s. Setext `===` / `---` underlines give levels 1 and 2. |
| Paragraph | plain text | Consecutive lines join with newlines. |
| Fenced code | ```` ``` ```` or `~~~` | Optional language tag drives syntax highlighting; the closing fence must be at least as long as the opener. |
| Blockquote | `> text` | Consecutive `>` lines join into one quote. |
| Unordered list | `-`, `+`, `*` | Nests by indentation (a tab counts as 4 spaces); up to 3 leading spaces at top level. |
| Ordered list | `1.` or `1)` | Honors the starting number; nests like unordered lists. |
| Task list | `- [ ]` / `- [x]` | Checkboxes are interactive in Read mode — clicking one edits the source. |
| Table | `\| a \| b \|` + `\| --- \| --- \|` | `:` markers set left/center/right alignment; cells may escape `\|`. |
| Image | `![alt](path)` on its own line | Local files only; remote URLs are rejected. |
| Footnote | `[^label]: text` | Renders as a footnote block. |
| Thematic break | `---`, `***`, `___` | Three or more markers. |

## Inline

Inline formatting inside paragraphs, list items, table cells, and headings is interpreted by
Foundation's Markdown `AttributedString`: **bold**, *italic*, `code`, and links. Links open
against the document's location, so relative links between files in a workspace resolve
correctly — and `[[wiki-style links]]` work for navigation and the backlinks list.

## Deliberate limits

- The parser is line-based: it does not implement every CommonMark edge case (HTML blocks,
  reference-style link definitions, hard-break backslashes, inline HTML).
- Remote resources are never fetched. `https?://` images show alt text, not pixels; local images
  render and are embedded into HTML and PDF exports.
- Ordered-list renumbering follows the first item's number, matching CommonMark.

If a construct renders literally instead of formatted, it is almost always one of the limits
above — check that the marker is at the start of a line and, for blocks, separated by a blank
line.
