import Foundation

enum WorkspaceIndexer {
  static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]
  static let ignoredDirectoryNames: Set<String> = [
    ".git", ".hg", ".svn", ".build", "DerivedData", "node_modules", "vendor",
  ]
  static let maximumIndexedFileSize = 2_000_000
  static let maximumIndexedFileCount = 20_000
  static let maximumIndexedContentBytes = 64_000_000

  static func index(_ rootURL: URL) async throws -> WorkspaceIndex {
    try Task.checkCancellation()
    return try indexSynchronously(rootURL)
  }

  static func indexSynchronously(_ rootURL: URL) throws -> WorkspaceIndex {
    let rootURL = rootURL.standardizedFileURL
    let resourceKeys: [URLResourceKey] = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isHiddenKey,
      .fileSizeKey,
      .contentModificationDateKey,
    ]

    var enumerationError: Error?
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsPackageDescendants],
        errorHandler: { _, error in
          enumerationError = error
          return false
        }
      )
    else {
      throw CocoaError(.fileReadUnknown)
    }

    var files: [WorkspaceFile] = []
    var warnings: [WorkspaceIndexWarning] = []
    var indexedContentBytes = 0
    var reportedContentLimit = false

    for case let url as URL in enumerator {
      try Task.checkCancellation()
      let values: URLResourceValues
      do {
        values = try url.resourceValues(forKeys: Set(resourceKeys))
      } catch {
        warnings.append(
          .unreadableFile(
            path: relativePath(for: url, rootURL: rootURL), message: error.localizedDescription)
        )
        continue
      }

      if values.isDirectory == true {
        if values.isHidden == true || ignoredDirectoryNames.contains(url.lastPathComponent) {
          enumerator.skipDescendants()
        }
        continue
      }

      guard values.isRegularFile == true,
        values.isHidden != true,
        markdownExtensions.contains(url.pathExtension.lowercased())
      else { continue }

      if files.count >= maximumIndexedFileCount {
        warnings.append(.fileLimitReached(maximumIndexedFileCount))
        break
      }

      let fileSize = values.fileSize ?? 0
      let content: String
      if fileSize <= maximumIndexedFileSize,
        indexedContentBytes + fileSize <= maximumIndexedContentBytes
      {
        do {
          content = try MarkdownTextDecoder.read(from: url)
          indexedContentBytes += fileSize
        } catch {
          content = ""
          warnings.append(
            .unreadableFile(
              path: relativePath(for: url, rootURL: rootURL),
              message: error.localizedDescription
            )
          )
        }
      } else {
        content = ""
        if indexedContentBytes + fileSize > maximumIndexedContentBytes, !reportedContentLimit {
          warnings.append(.contentLimitReached(maximumIndexedContentBytes))
          reportedContentLimit = true
        }
      }

      let relativePath = relativePath(for: url, rootURL: rootURL)
      let headings = MarkdownParser().parse(content).outline.map(\.title)
      files.append(
        WorkspaceFile(
          url: url.standardizedFileURL,
          relativePath: relativePath,
          content: content,
          headings: headings,
          modifiedAt: values.contentModificationDate,
          byteCount: fileSize
        )
      )
    }

    if let enumerationError { throw enumerationError }

    files.sort {
      $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
    }
    return WorkspaceIndex(rootURL: rootURL, files: files, warnings: warnings)
  }

  private static func relativePath(for fileURL: URL, rootURL: URL) -> String {
    let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
    guard fileURL.path.hasPrefix(rootPath) else { return fileURL.lastPathComponent }
    return String(fileURL.path.dropFirst(rootPath.count))
  }
}
