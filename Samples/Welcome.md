# Margin

Beautiful Markdown editing **without leaving macOS**.

Margin treats your files as documents first: fast to open, calm to read, and always ordinary Markdown underneath.

## A native reading experience

Typography, spacing, and interaction belong to the platform. There is no browser shell between you and the document.

> Make it fast. Make it native. Make it quiet. Make every interaction feel deliberate.

### Today

- [x] Open Markdown files directly
- [x] Switch instantly between Write, Read, and Split
- [ ] Add this document to a workspace

| Mode | Purpose | Shortcut |
|:-----|:--------|---------:|
| Write | Edit the source | ⌘⌥1 |
| Read | Focus on the document | ⌘⌥2 |
| Split | Edit beside the preview | ⌘⌥3 |

```swift
struct MarginApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument())
    }
}
```

## Private by default

Your documents stay local. Margin has no account requirement, tracking SDK, or cloud dependency.

[^1]: The file remains valid, portable Markdown at every step.
