import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class DocumentDropCoordinator {
  private let documentURL: URL?
  private let assetStorage: AssetStorageStrategy
  private let workspaceGrantsAccess: (URL) -> Bool
  private let supportingFileAccess: SupportingFileAccess
  private let openWorkspace: (URL) -> Void
  private let insertMarkdown: (String) -> Void
  private let reportError: (String) -> Void

  init(
    documentURL: URL?,
    assetStorage: AssetStorageStrategy,
    workspaceGrantsAccess: @escaping (URL) -> Bool,
    supportingFileAccess: SupportingFileAccess,
    openWorkspace: @escaping (URL) -> Void,
    insertMarkdown: @escaping (String) -> Void,
    reportError: @escaping (String) -> Void
  ) {
    self.documentURL = documentURL
    self.assetStorage = assetStorage
    self.workspaceGrantsAccess = workspaceGrantsAccess
    self.supportingFileAccess = supportingFileAccess
    self.openWorkspace = openWorkspace
    self.insertMarkdown = insertMarkdown
    self.reportError = reportError
  }

  func accept(_ providers: [NSItemProvider]) -> Bool {
    var accepted = false

    for provider in providers {
      if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        accepted = true
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
          [self] item, _ in
          let url: URL?
          if let item = item as? URL {
            url = item
          } else if let data = item as? Data {
            url = URL(dataRepresentation: data, relativeTo: nil)
          } else {
            url = nil
          }

          guard let url else { return }
          Task { @MainActor in handleDroppedFile(url) }
        }
      } else if provider.canLoadObject(ofClass: NSString.self) {
        accepted = true
        _ = provider.loadObject(ofClass: NSString.self) { [self] value, _ in
          guard let value = value as? NSString else { return }
          Task { @MainActor in insertMarkdown(value as String) }
        }
      }
    }
    return accepted
  }

  private func handleDroppedFile(_ url: URL) {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey])
    if values?.isDirectory == true {
      openWorkspace(url)
      return
    }

    guard let documentURL else {
      reportError("Save the document before adding files or images.")
      return
    }

    guard values?.contentType?.conforms(to: .image) == true else {
      insertMarkdown(AssetManager.markdownLink(to: url, from: documentURL))
      return
    }

    Task {
      do {
        let documentDirectory = documentURL.deletingLastPathComponent()
        if !workspaceGrantsAccess(documentDirectory),
          !supportingFileAccess.hasAccess(to: documentDirectory),
          !(await supportingFileAccess.requestAccess(for: documentURL))
        {
          return
        }
        let strategy = assetStorage
        let imported = try await Task.detached(priority: .userInitiated) {
          let accessed = url.startAccessingSecurityScopedResource()
          defer { if accessed { url.stopAccessingSecurityScopedResource() } }
          return try AssetManager.importImage(at: url, for: documentURL, strategy: strategy)
        }.value
        insertMarkdown(imported.markdown)
      } catch {
        reportError(error.localizedDescription)
      }
    }
  }
}
