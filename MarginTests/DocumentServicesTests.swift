import AppKit
import XCTest

@testable import Margin

final class DocumentServicesTests: XCTestCase {
  @MainActor
  func testApplicationDelegateForwardsCustomRoutes() throws {
    let fileURL = URL(fileURLWithPath: "/tmp/Reader route.md")
    var components = URLComponents()
    components.scheme = "margin"
    components.host = "read"
    components.queryItems = [.init(name: "path", value: fileURL.path)]

    MarginAppDelegate().application(
      NSApplication.shared,
      open: [URL(string: "https://example.com")!, try XCTUnwrap(components.url)]
    )

    XCTAssertTrue(MarginURLRouter.shared.consumeReadMode(for: fileURL))
  }

  func testMarginURLRoutesDecodeReaderAndWorkspacePaths() throws {
    let fileURL = URL(fileURLWithPath: "/tmp/A file.md")
    var readerComponents = URLComponents()
    readerComponents.scheme = "margin"
    readerComponents.host = "read"
    readerComponents.queryItems = [.init(name: "path", value: fileURL.path)]

    XCTAssertEqual(MarginURLRoute(url: try XCTUnwrap(readerComponents.url)), .read(fileURL))

    readerComponents.host = "workspace"
    let bookmarkData = Data("bookmark".utf8)
    readerComponents.queryItems = [
      .init(name: "path", value: fileURL.path),
      .init(name: "bookmark", value: bookmarkData.base64EncodedString()),
    ]
    XCTAssertEqual(
      MarginURLRoute(url: try XCTUnwrap(readerComponents.url)),
      .workspace(WorkspaceAccessRequest(url: fileURL, bookmarkData: bookmarkData))
    )
    XCTAssertNil(MarginURLRoute(url: URL(string: "https://example.com")!))
  }

  func testMarkdownTextDecoderAcceptsUTF8AndUTF16() throws {
    XCTAssertEqual(try MarkdownTextDecoder.decode(Data("Hello".utf8)), "Hello")
    XCTAssertEqual(
      try MarkdownTextDecoder.decode(try XCTUnwrap("Hello".data(using: .utf16))),
      "Hello"
    )
  }

  func testExternalChangeDecisionReloadsOnlyWithoutLocalEdits() {
    XCTAssertEqual(
      ExternalChangeDecision.decide(lastKnownDisk: "old", local: "old", disk: "new"),
      .reloadFromDisk
    )
    XCTAssertEqual(
      ExternalChangeDecision.decide(lastKnownDisk: "old", local: "mine", disk: "theirs"),
      .conflict
    )
    XCTAssertEqual(
      ExternalChangeDecision.decide(lastKnownDisk: "old", local: "mine", disk: "old"),
      .unchanged
    )
  }

  func testImageImportCopiesIntoAssetsAndBuildsRelativeMarkdown() throws {
    let root = try makeDirectory()
    let sourceDirectory = try makeDirectory()
    let documentURL = root.appendingPathComponent("README.md")
    let imageURL = sourceDirectory.appendingPathComponent("hero-image.png")
    try Data(base64Encoded: onePixelPNG)!.write(to: imageURL)

    let imported = try AssetManager.importImage(
      at: imageURL,
      for: documentURL,
      strategy: .assetsFolder
    )

    XCTAssertEqual(imported.relativePath, "assets/hero-image.png")
    XCTAssertEqual(imported.markdown, "![hero image](assets/hero-image.png)")
    XCTAssertTrue(FileManager.default.fileExists(atPath: imported.destinationURL.path))
  }

  func testImageImportAvoidsOverwritingDifferentFiles() throws {
    let root = try makeDirectory()
    let sourceDirectory = try makeDirectory()
    let documentURL = root.appendingPathComponent("README.md")
    let first = sourceDirectory.appendingPathComponent("image.png")
    let second = sourceDirectory.appendingPathComponent("other/image.png")
    try FileManager.default.createDirectory(
      at: second.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data(base64Encoded: onePixelPNG)!.write(to: first)
    try (Data(base64Encoded: onePixelPNG)! + Data([0])).write(to: second)

    _ = try AssetManager.importImage(
      at: first,
      for: documentURL,
      strategy: .assetsFolder
    )
    let imported = try AssetManager.importImage(
      at: second,
      for: documentURL,
      strategy: .assetsFolder
    )

    XCTAssertEqual(imported.destinationURL.lastPathComponent, "image-2.png")
  }

  func testFileLinkUsesRelativePath() throws {
    let root = try makeDirectory()
    let document = root.appendingPathComponent("docs/README.md")
    let target = root.appendingPathComponent("images/diagram.svg")

    XCTAssertEqual(
      AssetManager.markdownLink(to: target, from: document),
      "[diagram](../images/diagram.svg)"
    )
  }

  func testMarkdownLinksEscapeSpecialFilenames() throws {
    let root = try makeDirectory()
    let document = root.appendingPathComponent("README.md")
    let target = root.appendingPathComponent("A [draft](1).md")

    XCTAssertEqual(
      AssetManager.markdownLink(to: target, from: document),
      #"[A \[draft\](1)](A%20%5Bdraft%5D%281%29.md)"#
    )
  }

  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MarginDocumentTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private var onePixelPNG: String {
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  }
}
