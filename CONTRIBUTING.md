# Contributing to Margin

## Requirements

- macOS 15 or later
- Xcode 16 or later (Swift 6, `swift-tools-version` for the build tool)

## Build

```sh
xcodebuild \
  -project Margin.xcodeproj \
  -scheme Margin \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath build \
  build

open build/Build/Products/Release/Margin.app
```

Use `-configuration Debug` for development. `build/` is gitignored.

## Test

```sh
xcodebuild \
  -project Margin.xcodeproj \
  -scheme Margin \
  -destination 'platform=macOS' \
  -derivedDataPath build/tests \
  test
```

`MarginTests` hosts the unit suite (parser, workspace index/search, export, routing);
`MarginUITests` is a UI smoke suite that needs Xcode UI-automation permission the first time.

## Repository layout

| Path | Contents |
| --- | --- |
| `Margin/` | The app, split into `App`, `CommandKit`, `DocumentKit`, `EditorKit`, `ExportKit`, `MarkdownKit`, `RenderKit`, `Views`, `WorkspaceKit` |
| `MarginCLI/` | The `margin` command-line tool (single file, shares MarkdownKit sources) |
| `MarginQuickLook/` | Quick Look preview extension |
| `MarginTests/`, `MarginUITests/` | Test targets |
| `Tools/MarginBuild/` | Swift executable implementing CI validation and the signed/notarized release |
| `Samples/` | Sample Markdown documents |
| `docs/` | Architecture, release checklist, and user documentation |

`MarkdownModels`, `MarkdownParser`, `MarkdownTextDecoder`, and `MarkdownHTMLRenderer` are shared
sources compiled into the app, the CLI, and the Quick Look extension — see
[`docs/architecture.md`](docs/architecture.md) for the module and trust boundaries before
changing one of them.

## Conventions

- Keep changes inside the module boundary they belong to (see the architecture doc); the shared
  Markdown sources must stay dependency-free because three products compile them.
- Parser changes need unit tests in `MarginTests`; the same parse must hold in the app, Quick
  Look, the CLI, and exports.
- Update `docs/` when behavior users can see changes.

## CI and releases

`.github/workflows/ci.yml` invokes `Tools/MarginBuild` for analysis, tests, universal Release
compilation, and CLI validation. The signed, notarized release flow is manual and documented in
[`docs/release-checklist.md`](docs/release-checklist.md).
