import AppKit

@MainActor
final class MarginAppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme?.lowercased() == "margin" {
      MarginURLRouter.shared.handle(url)
    }
  }
}
