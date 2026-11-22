# Using Margin

Margin opens a single Markdown file or a folder of them. Everything it shows comes from the
source file on disk — there is no library, import step, or account.

## Presentation modes

Each document window shows the same file in one of three modes. Switch modes from the toolbar,
the View menu, or the command palette.

| Mode | What it shows |
| --- | --- |
| Write | A TextKit 2 editor with Markdown styling, list continuation, native find, and spelling. |
| Read | The rendered document: interactive task lists, tables, highlighted code, links, and images. |
| Split | Write and Read side by side, kept in sync while you edit. |

## Sidebar and inspector

The sidebar (**⌘\\**) shows the document outline, generated from the headings in the file, and
the workspace file list when a folder is open. The inspector (**⌥⌘I**) shows document statistics
(word, character, and line counts) and document options.

## Command palette

**⌘K** opens the command palette. It lists every document command — mode switching, sidebar and
inspector toggles, Quick Open, workspace search, export, and formatting — with its keyboard
shortcut. Type part of a name or an alias (for example "preview" or "find in files") to filter,
then press Return or click a result.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Write / Read / Split | ⌘⌥1 / ⌘⌥2 / ⌘⌥3 |
| Show or hide sidebar | ⌘\\ |
| Show or hide inspector | ⌥⌘I |
| Command palette | ⌘K |
| Quick Open | ⌘P |
| Search workspace | ⇧⌘F |
| Open folder as workspace | ⇧⌘O |
| Export as PDF | ⇧⌘E |
| Bold / Italic | ⌘B / ⌘I |
| Inline code | ⇧⌘` |
| Insert link | ⇧⌘K |

The Format menu holds Bold, Italic, Inline Code, and Link; the File menu holds Open Folder,
Quick Open, Search Workspace, Export as PDF, Export as HTML, and Copy Rendered HTML.

## Workspaces

**File → Open Folder…** (⇧⌘O) opens a folder as a workspace. Margin indexes the Markdown files
inside it once, with a cap on file count and total indexed size, and keeps access alive through a
security-scoped bookmark so the folder survives relaunches. One workspace is shared by every
document window.

Inside a workspace:

- **Quick Open** (⌘P) finds files by fuzzy match against the file name, relative path, and
  headings.
- **Search Workspace** (⇧⌘F) searches file contents, case- and diacritic-insensitive. Wrap a
  query in slashes — `/foo(bar|baz)/` — to use a regular expression. Results show file and line
  and open the document at that line.
- **Backlinks** in the sidebar list the workspace files that link to the open document, whether
  by a normal Markdown link or a `[[wiki-style link]]`.
- **Spotlight** indexes workspace documents so they appear in Finder and Spotlight searches.

## Links and images

Drag a Markdown file or an image into a document to insert a link. Dropped images are copied
next to the document as assets with relative paths; if a file with the same name exists, Margin
picks a collision-free name instead of overwriting. Remote images are never loaded: only local
image files render, in the app, in Quick Look, and in exports.

## External changes

Margin watches the open file on disk. When another program modifies it, the document reloads
safely; when you have unsaved edits of your own, Margin asks you to resolve the conflict rather
than silently picking a side.

## Export

**Export as HTML** writes a standalone styled HTML file with local images embedded.
**Export as PDF** renders the same document through WebKit to a paginated PDF.
**Copy Rendered HTML** puts the rendered document on the clipboard for pasting into Mail, a
browser, or another editor. The `margin` command does the same exports from a terminal — see
[`docs/cli.md`](cli.md).

## Quick Look and the `margin` command

Selecting a Markdown file in Finder and pressing Space previews the rendered document through
Margin's Quick Look extension. The `margin` command-line tool opens files, folders, and piped
text in the app, and exports to HTML and PDF; install it from **Margin → Install Command Line
Tool…**.
