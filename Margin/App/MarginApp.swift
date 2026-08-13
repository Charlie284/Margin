import SwiftUI

@main
struct MarginApp: App {
  @NSApplicationDelegateAdaptor(MarginAppDelegate.self) private var appDelegate
  @StateObject private var workspace = WorkspaceController()

  var body: some Scene {
    DocumentGroup(newDocument: MarkdownDocument()) { configuration in
      DocumentView(
        document: configuration.$document,
        fileURL: configuration.fileURL,
        isEditable: configuration.isEditable
      )
      .environmentObject(workspace)
    }
    .commands {
      MarginCommands()
    }
    .defaultSize(width: 1_080, height: 760)
  }
}
