import AppKit
import Foundation

@MainActor
enum DocumentPaletteCommands {
  struct Actions {
    let setMode: (PresentationMode) -> Void
    let toggleSidebar: () -> Void
    let toggleInspector: () -> Void
    let quickOpen: () -> Void
    let searchWorkspace: () -> Void
    let chooseWorkspace: () -> Void
    let exportPDF: () -> Void
    let exportHTML: () -> Void
    let copyHTML: () -> Void
    let formatBold: () -> Void
    let formatItalic: () -> Void
  }

  static func make(
    sidebarVisible: Bool,
    inspectorVisible: Bool,
    fileURL: URL?,
    actions: Actions
  ) -> [PaletteCommand] {
    [
      PaletteCommand(
        id: "mode-write",
        title: "Switch to Write",
        subtitle: "Edit the Markdown source",
        symbol: "pencil.line",
        shortcut: "⌘⌥1",
        aliases: ["edit", "source"],
        action: { actions.setMode(.write) }
      ),
      PaletteCommand(
        id: "mode-read",
        title: "Switch to Read",
        subtitle: "Show the rendered document",
        symbol: "doc.richtext",
        shortcut: "⌘⌥2",
        aliases: ["reader", "preview"],
        action: { actions.setMode(.read) }
      ),
      PaletteCommand(
        id: "mode-split",
        title: "Switch to Split",
        subtitle: "Edit and preview side by side",
        symbol: "rectangle.split.2x1",
        shortcut: "⌘⌥3",
        aliases: ["side by side", "preview"],
        action: { actions.setMode(.split) }
      ),
      PaletteCommand(
        id: "toggle-sidebar",
        title: sidebarVisible ? "Hide Sidebar" : "Show Sidebar",
        symbol: "sidebar.left",
        shortcut: "⌘\\",
        aliases: ["outline", "navigation"],
        action: actions.toggleSidebar
      ),
      PaletteCommand(
        id: "toggle-inspector",
        title: inspectorVisible ? "Hide Inspector" : "Show Inspector",
        symbol: "sidebar.right",
        shortcut: "⌥⌘I",
        aliases: ["statistics", "appearance"],
        action: actions.toggleInspector
      ),
      PaletteCommand(
        id: "quick-open",
        title: "Quick Open…",
        subtitle: "Open a Markdown document",
        symbol: "doc.badge.plus",
        shortcut: "⌘P",
        aliases: ["file", "open document"],
        action: actions.quickOpen
      ),
      PaletteCommand(
        id: "workspace-search",
        title: "Search Workspace…",
        subtitle: "Search inside Markdown documents",
        symbol: "text.magnifyingglass",
        shortcut: "⇧⌘F",
        aliases: ["find in files", "content", "regex"],
        action: actions.searchWorkspace
      ),
      PaletteCommand(
        id: "open-workspace",
        title: "Open Folder…",
        subtitle: "Use a folder as a Markdown workspace",
        symbol: "folder.badge.plus",
        shortcut: "⇧⌘O",
        aliases: ["workspace", "directory"],
        action: actions.chooseWorkspace
      ),
      PaletteCommand(
        id: "export-pdf",
        title: "Export as PDF…",
        subtitle: "Export the rendered document",
        symbol: "doc.richtext",
        shortcut: "⇧⌘E",
        aliases: ["print", "save pdf"],
        action: actions.exportPDF
      ),
      PaletteCommand(
        id: "export-html",
        title: "Export as HTML…",
        subtitle: "Create a standalone styled document",
        symbol: "chevron.left.forwardslash.chevron.right",
        aliases: ["web", "save html"],
        action: actions.exportHTML
      ),
      PaletteCommand(
        id: "copy-html",
        title: "Copy Rendered HTML",
        symbol: "doc.on.doc",
        aliases: ["clipboard", "rich text"],
        action: actions.copyHTML
      ),
      PaletteCommand(
        id: "format-bold",
        title: "Bold",
        symbol: "bold",
        shortcut: "⌘B",
        aliases: ["strong", "format"],
        action: actions.formatBold
      ),
      PaletteCommand(
        id: "format-italic",
        title: "Italic",
        symbol: "italic",
        shortcut: "⌘I",
        aliases: ["emphasis", "format"],
        action: actions.formatItalic
      ),
      PaletteCommand(
        id: "reveal-finder",
        title: "Reveal in Finder",
        symbol: "folder",
        aliases: ["show file", "open folder"],
        action: {
          if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
        }
      ),
    ]
  }
}
