import Foundation

struct WorkspaceFile: Identifiable, Equatable {
  let url: URL
  let relativePath: String
  let content: String
  let headings: [String]
  let modifiedAt: Date?
  let byteCount: Int

  var id: String { url.standardizedFileURL.path }
  var name: String { url.lastPathComponent }
  var directory: String {
    let value = (relativePath as NSString).deletingLastPathComponent
    return value == "." ? "" : value
  }
}

struct WorkspaceSearchResult: Identifiable, Equatable {
  let file: WorkspaceFile
  let line: Int
  let excerpt: String

  var id: String { "\(file.id):\(line):\(excerpt)" }
}

enum WorkspaceIndexWarning: Equatable {
  case unreadableFile(path: String, message: String)
  case fileLimitReached(Int)
  case contentLimitReached(Int)
  case spotlightUnavailable(String)

  var description: String {
    switch self {
    case .unreadableFile(let path, let message):
      "Couldn’t index \(path): \(message)"
    case .fileLimitReached(let limit):
      "Only the first \(limit.formatted()) Markdown files were indexed."
    case .contentLimitReached(let limit):
      "Content search was limited to \(ByteCountFormatter.string(fromByteCount: Int64(limit), countStyle: .file))."
    case .spotlightUnavailable(let message):
      "Spotlight indexing failed: \(message)"
    }
  }
}

struct WorkspaceSearchResponse: Equatable {
  let results: [WorkspaceSearchResult]
  let errorMessage: String?

  static let empty = WorkspaceSearchResponse(results: [], errorMessage: nil)
}

struct WorkspaceIndex: Equatable {
  var rootURL: URL?
  var files: [WorkspaceFile]
  var warnings: [WorkspaceIndexWarning]

  init(rootURL: URL?, files: [WorkspaceFile], warnings: [WorkspaceIndexWarning] = []) {
    self.rootURL = rootURL
    self.files = files
    self.warnings = warnings
  }

  static let empty = WorkspaceIndex(rootURL: nil, files: [])

  func matchingFiles(_ query: String, limit: Int = 150) -> [WorkspaceFile] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return Array(files.prefix(limit)) }

    return files.compactMap { file -> (WorkspaceFile, Int)? in
      let candidates = [file.name, file.relativePath] + file.headings
      let bestScore = candidates.compactMap {
        WorkspaceSearchMatcher.score(query: query, candidate: $0)
      }.max()
      guard let bestScore else { return nil }
      return (file, bestScore)
    }
    .sorted { left, right in
      left.1 == right.1
        ? left.0.relativePath.localizedStandardCompare(right.0.relativePath) == .orderedAscending
        : left.1 > right.1
    }
    .prefix(limit)
    .map(\.0)
  }

  func searchContent(_ query: String, limit: Int = 120) -> [WorkspaceSearchResult] {
    searchContentResponse(query, limit: limit).results
  }

  func searchContentResponse(_ query: String, limit: Int = 120) -> WorkspaceSearchResponse {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return .empty }

    let regex: NSRegularExpression?
    let plainQuery: String?
    if query.count > 2, query.hasPrefix("/"), query.hasSuffix("/") {
      do {
        regex = try NSRegularExpression(
          pattern: String(query.dropFirst().dropLast()),
          options: [.caseInsensitive]
        )
        plainQuery = nil
      } catch {
        return WorkspaceSearchResponse(
          results: [],
          errorMessage: "Invalid regular expression: \(error.localizedDescription)"
        )
      }
    } else {
      regex = nil
      plainQuery = query
    }
    var results: [WorkspaceSearchResult] = []

    for file in files {
      if Task.isCancelled { break }
      var matchesInFile = 0
      let lines = file.content.components(separatedBy: .newlines)

      for (offset, line) in lines.enumerated() {
        if Task.isCancelled { break }
        let range = NSRange(location: 0, length: (line as NSString).length)
        let matches =
          if let regex {
            regex.firstMatch(in: line, range: range) != nil
          } else if let plainQuery {
            line.range(of: plainQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
          } else {
            false
          }

        guard matches else { continue }
        results.append(
          WorkspaceSearchResult(
            file: file,
            line: offset + 1,
            excerpt: excerpt(from: line)
          )
        )
        matchesInFile += 1

        if matchesInFile >= 4 || results.count >= limit { break }
      }

      if results.count >= limit { break }
    }

    return WorkspaceSearchResponse(results: results, errorMessage: nil)
  }

  func backlinks(to fileURL: URL) -> [WorkspaceFile] {
    guard
      let target = files.first(where: { $0.url.standardizedFileURL == fileURL.standardizedFileURL })
    else { return [] }

    return files.filter { candidate in
      guard candidate.id != target.id else { return false }
      return markdownDestinations(in: candidate.content).contains { destination in
        resolves(destination, from: candidate, to: target)
      }
        || wikiDestinations(in: candidate.content).contains { destination in
          resolvesWiki(destination, from: candidate, to: target)
        }
    }
  }

  private func markdownDestinations(in source: String) -> [String] {
    var destinations: [String] = []
    var searchStart = source.startIndex
    while let marker = source.range(of: "](", range: searchStart..<source.endIndex) {
      searchStart = marker.upperBound
      let prefix = source[..<marker.lowerBound]
      guard let openingBracket = prefix.lastIndex(of: "[") else { continue }
      if openingBracket > source.startIndex,
        source[source.index(before: openingBracket)] == "!"
      {
        continue
      }

      var index = marker.upperBound
      let destinationStart = index
      var depth = 1
      var escaped = false
      while index < source.endIndex {
        let character = source[index]
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "(" {
          depth += 1
        } else if character == ")" {
          depth -= 1
          if depth == 0 {
            let raw = String(source[destinationStart..<index])
              .trimmingCharacters(in: .whitespacesAndNewlines)
            let destination: String
            if raw.hasPrefix("<"), let closing = raw.firstIndex(of: ">") {
              destination = String(raw[raw.index(after: raw.startIndex)..<closing])
            } else {
              destination = String(raw.prefix { !$0.isWhitespace })
            }
            if !destination.isEmpty { destinations.append(destination) }
            searchStart = source.index(after: index)
            break
          }
        }
        index = source.index(after: index)
      }
    }
    return destinations
  }

  private func wikiDestinations(in source: String) -> [String] {
    guard let expression = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else {
      return []
    }
    return expression.matches(
      in: source,
      range: NSRange(location: 0, length: (source as NSString).length)
    ).compactMap { match in
      guard let range = Range(match.range(at: 1), in: source) else { return nil }
      return String(source[range]).components(separatedBy: "|").first
    }
  }

  private func resolves(
    _ rawDestination: String, from source: WorkspaceFile, to target: WorkspaceFile
  )
    -> Bool
  {
    let destination = rawDestination.components(separatedBy: "#").first ?? rawDestination
    guard !destination.isEmpty else { return false }
    if let absolute = URL(string: destination), absolute.isFileURL {
      return absolute.standardizedFileURL == target.url.standardizedFileURL
    }
    if URLComponents(string: destination)?.scheme != nil { return false }
    let decoded = destination.removingPercentEncoding ?? destination
    let resolved = URL(
      fileURLWithPath: decoded,
      relativeTo: source.url.deletingLastPathComponent()
    ).standardizedFileURL
    return resolved == target.url.standardizedFileURL
  }

  private func resolvesWiki(
    _ rawDestination: String,
    from source: WorkspaceFile,
    to target: WorkspaceFile
  ) -> Bool {
    var destination = rawDestination.components(separatedBy: "#").first ?? rawDestination
    destination = destination.removingPercentEncoding ?? destination
    destination = destination.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !destination.isEmpty else { return false }

    if destination.contains("/") {
      if (destination as NSString).pathExtension.isEmpty { destination += ".md" }
      let resolved = URL(
        fileURLWithPath: destination,
        relativeTo: source.url.deletingLastPathComponent()
      ).standardizedFileURL
      return resolved == target.url.standardizedFileURL
    }

    let stem = (destination as NSString).deletingPathExtension
    guard
      stem.caseInsensitiveCompare(target.url.deletingPathExtension().lastPathComponent)
        == .orderedSame
    else { return false }
    let matchingTargets = files.filter {
      $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame
    }
    if matchingTargets.count == 1 { return true }
    return source.url.deletingLastPathComponent() == target.url.deletingLastPathComponent()
  }

  private func excerpt(from line: String) -> String {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.count > 180 else { return trimmed }
    return String(trimmed.prefix(177)) + "…"
  }
}

enum WorkspaceSearchEngine {
  static func search(_ index: WorkspaceIndex, query: String) async -> WorkspaceSearchResponse {
    let task = Task.detached(priority: .userInitiated) {
      index.searchContentResponse(query)
    }
    return await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }
  }
}

enum WorkspaceSearchMatcher {
  static func score(query: String, candidate: String) -> Int? {
    let query = normalize(query)
    let candidate = normalize(candidate)
    guard !query.isEmpty else { return 0 }

    if candidate == query { return 10_000 }
    if candidate.hasPrefix(query) { return 8_000 - candidate.count }
    if candidate.contains(query) { return 6_000 - candidate.count }

    var queryIndex = query.startIndex
    var previousMatch: String.Index?
    var score = 0

    for candidateIndex in candidate.indices where queryIndex < query.endIndex {
      guard candidate[candidateIndex] == query[queryIndex] else { continue }
      score += 100

      if let previousMatch, candidate.distance(from: previousMatch, to: candidateIndex) == 1 {
        score += 45
      }
      if candidateIndex == candidate.startIndex
        || "/ -_".contains(candidate[candidate.index(before: candidateIndex)])
      {
        score += 35
      }

      previousMatch = candidateIndex
      query.formIndex(after: &queryIndex)
    }

    guard queryIndex == query.endIndex else { return nil }
    return score - candidate.count
  }

  private static func normalize(_ value: String) -> String {
    value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .replacingOccurrences(of: "/", with: " ")
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
