import CoreSpotlight
import CryptoKit
import Foundation
import UniformTypeIdentifiers

struct SpotlightDocument: Equatable {
  let identifier: String
  let domainIdentifier: String
  let title: String
  let relativePath: String
  let content: String
  let headings: [String]
  let contentURL: URL

  init(file: WorkspaceFile, rootURL: URL) {
    identifier = file.url.standardizedFileURL.absoluteString
    domainIdentifier = WorkspaceSpotlightIndexer.domainIdentifier(for: rootURL)
    title = file.url.deletingPathExtension().lastPathComponent
    relativePath = file.relativePath
    content = file.content
    headings = file.headings
    contentURL = file.url
  }

  var searchableItem: CSSearchableItem {
    let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
    attributes.title = title
    attributes.displayName = contentURL.lastPathComponent
    attributes.contentDescription = relativePath
    attributes.textContent = content
    attributes.keywords = headings
    attributes.contentURL = contentURL

    return CSSearchableItem(
      uniqueIdentifier: identifier,
      domainIdentifier: domainIdentifier,
      attributeSet: attributes
    )
  }
}

enum WorkspaceSpotlightIndexer {
  static func replaceIndex(with workspace: WorkspaceIndex) async -> String? {
    guard let rootURL = workspace.rootURL else { return nil }
    let domain = domainIdentifier(for: rootURL)
    let searchableIndex = CSSearchableIndex.default()
    let storageKey = indexedIdentifiersKey(for: domain)

    do {
      let items = workspace.files.map {
        SpotlightDocument(file: $0, rootURL: rootURL).searchableItem
      }
      guard !items.isEmpty else {
        try await searchableIndex.deleteSearchableItems(withDomainIdentifiers: [domain])
        UserDefaults.standard.removeObject(forKey: storageKey)
        return nil
      }

      for start in stride(from: 0, to: items.count, by: 500) {
        let end = min(start + 500, items.count)
        try await searchableIndex.indexSearchableItems(Array(items[start..<end]))
      }

      let currentIdentifiers = Set(items.map(\.uniqueIdentifier))
      let previousIdentifiers = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
      let staleIdentifiers = Array(previousIdentifiers.subtracting(currentIdentifiers))
      if !staleIdentifiers.isEmpty {
        try await searchableIndex.deleteSearchableItems(withIdentifiers: staleIdentifiers)
      }
      UserDefaults.standard.set(Array(currentIdentifiers).sorted(), forKey: storageKey)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  static func removeIndex(for rootURL: URL?) async {
    guard let rootURL else { return }
    let domain = domainIdentifier(for: rootURL)
    try? await CSSearchableIndex.default().deleteSearchableItems(
      withDomainIdentifiers: [domain]
    )
    UserDefaults.standard.removeObject(forKey: indexedIdentifiersKey(for: domain))
  }

  static func domainIdentifier(for rootURL: URL) -> String {
    let digest = SHA256.hash(data: Data(rootURL.standardizedFileURL.path.utf8))
    let suffix = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    return "com.marginapp.workspace.\(suffix)"
  }

  private static func indexedIdentifiersKey(for domain: String) -> String {
    "Margin.SpotlightIdentifiers.\(domain)"
  }
}
