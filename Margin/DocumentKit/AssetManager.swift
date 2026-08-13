import Foundation
import UniformTypeIdentifiers

enum AssetStorageStrategy: String, CaseIterable, Identifiable {
  case assetsFolder
  case besideDocument

  var id: Self { self }

  var title: String {
    switch self {
    case .assetsFolder: "Assets Folder"
    case .besideDocument: "Beside Document"
    }
  }
}

struct ImportedAsset: Equatable {
  let destinationURL: URL
  let relativePath: String
  let markdown: String
}

enum AssetManager {
  static func importImage(
    at sourceURL: URL,
    for documentURL: URL,
    strategy: AssetStorageStrategy
  ) throws -> ImportedAsset {
    let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey])
    guard values.isRegularFile == true,
      values.contentType?.conforms(to: .image) == true
    else {
      throw CocoaError(.fileReadUnsupportedScheme)
    }

    let documentDirectory = documentURL.deletingLastPathComponent()
    let destinationDirectory: URL
    switch strategy {
    case .assetsFolder:
      destinationDirectory = documentDirectory.appendingPathComponent("assets", isDirectory: true)
      try FileManager.default.createDirectory(
        at: destinationDirectory,
        withIntermediateDirectories: true
      )
    case .besideDocument:
      destinationDirectory = documentDirectory
    }

    let destination = try availableDestination(
      for: sourceURL,
      in: destinationDirectory
    )
    if sourceURL.standardizedFileURL != destination.standardizedFileURL,
      !FileManager.default.fileExists(atPath: destination.path)
    {
      try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    let relativePath = relativePath(from: documentDirectory, to: destination)
    let encodedPath = encodeMarkdownPath(relativePath)
    let alt = destination.deletingPathExtension().lastPathComponent
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")

    return ImportedAsset(
      destinationURL: destination,
      relativePath: relativePath,
      markdown: "![\(escapeLabel(alt))](\(encodedPath))"
    )
  }

  static func markdownLink(to targetURL: URL, from documentURL: URL) -> String {
    let destination = relativePath(
      from: documentURL.deletingLastPathComponent(),
      to: targetURL
    )
    let encoded = encodeMarkdownPath(destination)
    let label = targetURL.deletingPathExtension().lastPathComponent
    return "[\(escapeLabel(label))](\(encoded))"
  }

  private static func availableDestination(for sourceURL: URL, in directory: URL) throws -> URL {
    var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
    if candidate.standardizedFileURL == sourceURL.standardizedFileURL { return candidate }

    if FileManager.default.fileExists(atPath: candidate.path),
      FileManager.default.contentsEqual(atPath: sourceURL.path, andPath: candidate.path)
    {
      return candidate
    }

    let stem = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    var suffix = 2

    while FileManager.default.fileExists(atPath: candidate.path) {
      let name =
        pathExtension.isEmpty
        ? "\(stem)-\(suffix)"
        : "\(stem)-\(suffix).\(pathExtension)"
      candidate = directory.appendingPathComponent(name)
      suffix += 1
    }
    return candidate
  }

  private static func relativePath(from baseURL: URL, to targetURL: URL) -> String {
    let baseComponents = baseURL.standardizedFileURL.pathComponents
    let targetComponents = targetURL.standardizedFileURL.pathComponents
    var sharedCount = 0

    while sharedCount < min(baseComponents.count, targetComponents.count),
      baseComponents[sharedCount] == targetComponents[sharedCount]
    {
      sharedCount += 1
    }

    let parentComponents = Array(repeating: "..", count: baseComponents.count - sharedCount)
    let childComponents = targetComponents.dropFirst(sharedCount)
    let components = parentComponents + childComponents
    return components.isEmpty ? targetURL.lastPathComponent : components.joined(separator: "/")
  }

  private static func encodeMarkdownPath(_ path: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "()<>\\")
    return path.split(separator: "/", omittingEmptySubsequences: false)
      .map { component in
        let value = String(component)
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
      }
      .joined(separator: "/")
  }

  private static func escapeLabel(_ label: String) -> String {
    label
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "[", with: "\\[")
      .replacingOccurrences(of: "]", with: "\\]")
  }
}
