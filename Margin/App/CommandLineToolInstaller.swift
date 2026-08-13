import AppKit
import Foundation

@MainActor
enum CommandLineToolInstaller {
  static func present() {
    guard let sourceURL = bundledToolURL else {
      showResult(
        title: "Command Line Tool Unavailable",
        message: "This copy of Margin does not contain the margin command."
      )
      return
    }

    let panel = NSSavePanel()
    panel.title = "Install Command Line Tool"
    panel.prompt = "Install"
    panel.nameFieldStringValue = "margin"
    panel.canCreateDirectories = true
    let localBin = URL(fileURLWithPath: "/usr/local/bin", isDirectory: true)
    if FileManager.default.fileExists(atPath: localBin.path) {
      panel.directoryURL = localBin
    }

    panel.begin { response in
      guard response == .OK, let destinationURL = panel.url else { return }
      do {
        try install(from: sourceURL, to: destinationURL)
        showResult(
          title: "Command Line Tool Installed",
          message: "The margin command is available at \(destinationURL.path)."
        )
      } catch {
        showResult(title: "Couldn’t Install Command Line Tool", message: error.localizedDescription)
      }
    }
  }

  private static var bundledToolURL: URL? {
    guard let sharedSupportURL = Bundle.main.sharedSupportURL else { return nil }
    let url = sharedSupportURL.appendingPathComponent("bin/margin")
    return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
  }

  private static func install(from sourceURL: URL, to destinationURL: URL) throws {
    let data = try Data(contentsOf: sourceURL)
    try data.write(to: destinationURL, options: .atomic)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: destinationURL.path
    )
  }

  private static func showResult(title: String, message: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = title.contains("Installed") ? .informational : .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
