import AppKit
import CryptoKit
import Foundation

@MainActor
final class SupportingFileAccess: ObservableObject {
  private var directoryURL: URL?
  private var isAccessing = false

  func restore(for documentURL: URL?) {
    stop()
    guard let documentURL,
      let data = UserDefaults.standard.data(forKey: bookmarkKey(for: documentURL))
    else { return }

    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      ), url.standardizedFileURL == documentURL.deletingLastPathComponent().standardizedFileURL
    else {
      UserDefaults.standard.removeObject(forKey: bookmarkKey(for: documentURL))
      return
    }

    beginAccessing(url)
    if isStale { persist(url, for: documentURL) }
  }

  func hasAccess(to directory: URL) -> Bool {
    isAccessing && directoryURL?.standardizedFileURL == directory.standardizedFileURL
  }

  func requestAccess(for documentURL: URL) async -> Bool {
    let expectedDirectory = documentURL.deletingLastPathComponent().standardizedFileURL
    if hasAccess(to: expectedDirectory) { return true }

    let panel = NSOpenPanel()
    panel.title = "Allow Access to Document Assets"
    panel.message =
      "Choose \(expectedDirectory.lastPathComponent) so Margin can save and display files used by this document."
    panel.prompt = "Allow Access"
    panel.directoryURL = expectedDirectory
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false

    let response = await panel.begin()
    guard response == .OK, let selectedURL = panel.url?.standardizedFileURL,
      selectedURL == expectedDirectory
    else { return false }

    stop()
    beginAccessing(selectedURL)
    guard isAccessing else { return false }
    persist(selectedURL, for: documentURL)
    return true
  }

  func stop() {
    if isAccessing { directoryURL?.stopAccessingSecurityScopedResource() }
    isAccessing = false
    directoryURL = nil
  }

  private func beginAccessing(_ url: URL) {
    directoryURL = url.standardizedFileURL
    isAccessing = url.startAccessingSecurityScopedResource()
  }

  private func persist(_ directory: URL, for documentURL: URL) {
    guard
      let data = try? directory.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    else { return }
    UserDefaults.standard.set(data, forKey: bookmarkKey(for: documentURL))
  }

  private func bookmarkKey(for documentURL: URL) -> String {
    let digest = SHA256.hash(data: Data(documentURL.standardizedFileURL.path.utf8))
    let suffix = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    return "Margin.SupportingFiles.\(suffix)"
  }
}
