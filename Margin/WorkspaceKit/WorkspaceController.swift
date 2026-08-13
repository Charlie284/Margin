import Foundation

@MainActor
final class WorkspaceController: ObservableObject {
  enum State: Equatable {
    case closed
    case indexing
    case ready
    case failed(String)
  }

  @Published private(set) var index: WorkspaceIndex = .empty
  @Published private(set) var state: State = .closed

  private let bookmarkKey = "Margin.LastWorkspaceBookmark"
  private var indexedURL: URL?
  private var isAccessingSecurityScopedResource = false
  private var indexingTask: Task<Void, Never>?
  private var generation = UUID()

  var rootURL: URL? { index.rootURL ?? indexedURL }
  var files: [WorkspaceFile] { index.files }
  var warnings: [WorkspaceIndexWarning] { index.warnings }
  var searchIndex: WorkspaceIndex { index }

  func open(_ url: URL, persist: Bool = true) {
    openResolved(url.standardizedFileURL, bookmarkData: nil, persist: persist)
  }

  func open(_ request: WorkspaceAccessRequest, persist: Bool = true) {
    guard let bookmarkData = request.bookmarkData else {
      open(request.url, persist: persist)
      return
    }

    var isStale = false
    do {
      let resolvedURL = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
      openResolved(
        resolvedURL.standardizedFileURL,
        bookmarkData: isStale ? nil : bookmarkData,
        persist: persist
      )
    } catch {
      state = .failed("Margin couldn’t use the folder permission: \(error.localizedDescription)")
    }
  }

  private func openResolved(_ url: URL, bookmarkData: Data?, persist: Bool) {
    stopAccessingCurrentWorkspace()

    let standardizedURL = url.standardizedFileURL
    indexedURL = standardizedURL
    isAccessingSecurityScopedResource = standardizedURL.startAccessingSecurityScopedResource()

    if persist {
      persistBookmark(for: standardizedURL, existingData: bookmarkData)
    }
    refresh()
  }

  func restoreLastWorkspaceIfAvailable() {
    guard rootURL == nil,
      let data = UserDefaults.standard.data(forKey: bookmarkKey)
    else { return }

    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else {
      UserDefaults.standard.removeObject(forKey: bookmarkKey)
      return
    }

    openResolved(url, bookmarkData: isStale ? nil : data, persist: isStale)
  }

  func refresh() {
    guard let rootURL = indexedURL ?? index.rootURL else { return }
    indexingTask?.cancel()
    let currentGeneration = UUID()
    generation = currentGeneration
    state = .indexing

    indexingTask = Task {
      do {
        let newIndex = try await WorkspaceIndexer.index(rootURL)
        guard !Task.isCancelled, generation == currentGeneration else { return }
        index = newIndex
        state = .ready
        if let spotlightError = await WorkspaceSpotlightIndexer.replaceIndex(with: newIndex) {
          index.warnings.append(.spotlightUnavailable(spotlightError))
        }
      } catch {
        guard !Task.isCancelled, generation == currentGeneration else { return }
        state = .failed(error.localizedDescription)
      }
    }
  }

  func close() {
    let rootURL = rootURL
    indexingTask?.cancel()
    indexingTask = nil
    stopAccessingCurrentWorkspace()
    indexedURL = nil
    index = .empty
    state = .closed
    UserDefaults.standard.removeObject(forKey: bookmarkKey)
    Task { await WorkspaceSpotlightIndexer.removeIndex(for: rootURL) }
  }

  func matchingFiles(_ query: String) -> [WorkspaceFile] {
    index.matchingFiles(query)
  }

  func backlinks(to fileURL: URL?) -> [WorkspaceFile] {
    guard let fileURL else { return [] }
    return index.backlinks(to: fileURL)
  }

  func grantsAccess(to url: URL) -> Bool {
    guard isAccessingSecurityScopedResource, let rootURL else { return false }
    let rootPath = rootURL.standardizedFileURL.path
    let candidatePath = url.standardizedFileURL.path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    return candidatePath == rootPath || candidatePath.hasPrefix(rootPrefix)
  }

  private func persistBookmark(for url: URL, existingData: Data?) {
    if let existingData {
      UserDefaults.standard.set(existingData, forKey: bookmarkKey)
      return
    }
    guard
      let data = try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    else { return }
    UserDefaults.standard.set(data, forKey: bookmarkKey)
  }

  private func stopAccessingCurrentWorkspace() {
    if isAccessingSecurityScopedResource {
      indexedURL?.stopAccessingSecurityScopedResource()
    }
    isAccessingSecurityScopedResource = false
  }
}
