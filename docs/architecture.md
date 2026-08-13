# Architecture

Margin is a document-based SwiftUI app with two bundled companion products: a Quick Look extension
and the `margin` command-line tool.

## Product boundaries

- `App` owns scene lifecycle, menu commands, URL routing, and command-line installation.
- `DocumentKit` owns file coordination, external-change monitoring, assets, and supporting-file
  permissions.
- `MarkdownKit` contains the deterministic Markdown model, decoder, and parser.
- `EditorKit` contains the TextKit editor and source highlighting.
- `RenderKit` contains native reading views, local-image decoding, and code highlighting.
- `WorkspaceKit` owns folder indexing, search, backlinks, bookmarks, and Spotlight updates.
- `ExportKit` owns standalone HTML generation and bounded WebKit PDF export.
- `CommandKit` owns the command palette and background workspace panels.

`DocumentView` composes these modules but does not own their parsing, indexing, exporting, or
permission policies. `WorkspaceController` is app-scoped so every document window sees one workspace
and one security-scoped access lifetime.

## Shared core sources

`MarkdownModels`, `MarkdownParser`, `MarkdownTextDecoder`, and `MarkdownHTMLRenderer` are compiled
into the app, Quick Look extension, and CLI from the same source files. This is deliberate: each
product remains a standalone executable bundle without a separately embedded framework, while the
parser and renderer cannot drift between products. Changes to the shared sources are validated by
the app-hosted unit suite, and the Xcode dependency graph builds both companion products whenever
the app builds.

## Trust boundaries

- Documents and workspaces are local files reached through user selection or security-scoped
  bookmarks.
- Remote images and unsafe URL schemes are rejected by the reader, Quick Look, and exports.
- Local export resources are size-bounded and embedded into standalone HTML.
- Workspace indexing is cancellable and capped by file count and aggregate content size.
- Custom CLI routes are parsed at the AppKit application boundary and acknowledged across
  processes; path and bookmark payloads are validated before use.

## Release boundaries

CI runs analysis, unit tests, a UI smoke test, universal Release compilation, and CLI validation.
Developer ID signing, notarization, stapling, Gatekeeper assessment, and clean-account acceptance are
handled by `scripts/release.sh` and the release checklist because they require release credentials
and an external installation environment.
