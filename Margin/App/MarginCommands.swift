import AppKit
import SwiftUI

struct MarginCommands: Commands {
  @FocusedValue(\.marginDocumentActions) private var actions

  var body: some Commands {
    CommandGroup(after: .appInfo) {
      Button("Install Command Line Tool…") {
        CommandLineToolInstaller.present()
      }
    }

    CommandGroup(after: .newItem) {
      Button("Open Folder…") {
        actions?.chooseWorkspace()
      }
      .keyboardShortcut("o", modifiers: [.command, .shift])
      .disabled(actions == nil)

      Button("Quick Open…") {
        actions?.quickOpen()
      }
      .keyboardShortcut("p", modifiers: .command)
      .disabled(actions == nil)

      Button("Search Workspace…") {
        actions?.searchWorkspace()
      }
      .keyboardShortcut("f", modifiers: [.command, .shift])
      .disabled(actions == nil)
    }

    CommandGroup(after: .saveItem) {
      Divider()

      Button("Export as PDF…") {
        actions?.exportPDF()
      }
      .keyboardShortcut("e", modifiers: [.command, .shift])
      .disabled(actions == nil)

      Button("Export as HTML…") {
        actions?.exportHTML()
      }
      .disabled(actions == nil)

      Button("Copy Rendered HTML") {
        actions?.copyHTML()
      }
      .disabled(actions == nil)
    }

    CommandGroup(after: .toolbar) {
      Divider()

      Button(modeTitle(.write)) {
        actions?.setMode(.write)
      }
      .keyboardShortcut("1", modifiers: [.command, .option])
      .disabled(actions == nil)

      Button(modeTitle(.read)) {
        actions?.setMode(.read)
      }
      .keyboardShortcut("2", modifiers: [.command, .option])
      .disabled(actions == nil)

      Button(modeTitle(.split)) {
        actions?.setMode(.split)
      }
      .keyboardShortcut("3", modifiers: [.command, .option])
      .disabled(actions == nil)

      Divider()

      Button(actions?.sidebarVisible == true ? "Hide Sidebar" : "Show Sidebar") {
        actions?.toggleSidebar()
      }
      .keyboardShortcut("\\", modifiers: .command)
      .disabled(actions == nil)

      Button(actions?.inspectorVisible == true ? "Hide Inspector" : "Show Inspector") {
        actions?.toggleInspector()
      }
      .keyboardShortcut("i", modifiers: [.command, .option])
      .disabled(actions == nil)

      Button("Command Palette…") {
        actions?.showCommandPalette()
      }
      .keyboardShortcut("k", modifiers: .command)
      .disabled(actions == nil)
    }

    CommandMenu("Format") {
      Button("Bold") { actions?.formatBold() }
        .keyboardShortcut("b", modifiers: .command)
        .disabled(actions?.canFormat != true)
      Button("Italic") { actions?.formatItalic() }
        .keyboardShortcut("i", modifiers: .command)
        .disabled(actions?.canFormat != true)
      Button("Inline Code") { actions?.formatInlineCode() }
        .keyboardShortcut("`", modifiers: [.command, .shift])
        .disabled(actions?.canFormat != true)

      Divider()

      Button("Link") { actions?.insertLink() }
        .keyboardShortcut("k", modifiers: [.command, .shift])
        .disabled(actions?.canFormat != true)
    }
  }

  private func modeTitle(_ mode: PresentationMode) -> String {
    actions?.mode == mode ? "✓ \(mode.title)" : mode.title
  }
}
