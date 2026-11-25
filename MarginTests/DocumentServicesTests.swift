import AppKit
import SwiftUI
import UniformTypeIdentifiers
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

  func testMarkdownTextDecoderDetectsBOMsAndBOMlessUTF16() throws {
    var utf8WithBOM = Data([0xEF, 0xBB, 0xBF])
    utf8WithBOM.append(Data("# Hi".utf8))
    let decodedUTF8 = try MarkdownTextDecoder.decodeDetailed(utf8WithBOM)
    XCTAssertEqual(decodedUTF8.text, "# Hi")
    XCTAssertEqual(decodedUTF8.encoding, .utf8)
    XCTAssertTrue(decodedUTF8.hasBOM)

    var utf16LEWithBOM = Data([0xFF, 0xFE])
    utf16LEWithBOM.append(try XCTUnwrap("# Hi".data(using: .utf16LittleEndian)))
    let decodedLE = try MarkdownTextDecoder.decodeDetailed(utf16LEWithBOM)
    XCTAssertEqual(decodedLE.text, "# Hi")
    XCTAssertEqual(decodedLE.encoding, .utf16LittleEndian)
    XCTAssertTrue(decodedLE.hasBOM)

    var utf16BEWithBOM = Data([0xFE, 0xFF])
    utf16BEWithBOM.append(try XCTUnwrap("# Hi".data(using: .utf16BigEndian)))
    let decodedBE = try MarkdownTextDecoder.decodeDetailed(utf16BEWithBOM)
    XCTAssertEqual(decodedBE.text, "# Hi")
    XCTAssertEqual(decodedBE.encoding, .utf16BigEndian)
    XCTAssertTrue(decodedBE.hasBOM)

    let bomlessLE = try XCTUnwrap("# Heading\nSome text here.".data(using: .utf16LittleEndian))
    let decodedBomlessLE = try MarkdownTextDecoder.decodeDetailed(bomlessLE)
    XCTAssertEqual(decodedBomlessLE.text, "# Heading\nSome text here.")
    XCTAssertEqual(decodedBomlessLE.encoding, .utf16LittleEndian)
    XCTAssertFalse(decodedBomlessLE.hasBOM)

    let bomlessBE = try XCTUnwrap("# Heading\nSome text here.".data(using: .utf16BigEndian))
    let decodedBomlessBE = try MarkdownTextDecoder.decodeDetailed(bomlessBE)
    XCTAssertEqual(decodedBomlessBE.text, "# Heading\nSome text here.")
    XCTAssertEqual(decodedBomlessBE.encoding, .utf16BigEndian)
    XCTAssertFalse(decodedBomlessBE.hasBOM)
  }

  func testDocumentRoundTripPreservesEncodingAndBOM() throws {
    var source = Data([0xFF, 0xFE])
    source.append(try XCTUnwrap("# Café".data(using: .utf16LittleEndian)))

    let decoded = try MarkdownTextDecoder.decodeDetailed(source)
    XCTAssertEqual(decoded.text, "# Café")
    XCTAssertEqual(decoded.encoding, .utf16LittleEndian)
    XCTAssertTrue(decoded.hasBOM)

    var edited = MarkdownDocument(text: decoded.text + "\n\nNew paragraph.")
    edited.encoding = decoded.encoding
    edited.hasBOM = decoded.hasBOM
    let written = try edited.fileData()

    XCTAssertEqual(
      Array(written.prefix(2)),
      [0xFF, 0xFE],
      "Save should restore the UTF-16LE byte order mark"
    )
    XCTAssertEqual(
      try MarkdownTextDecoder.decode(written),
      "# Café\n\nNew paragraph."
    )
  }

  func testDocumentRoundTripPreservesUTF8BOM() throws {
    var source = Data([0xEF, 0xBB, 0xBF])
    source.append(Data("# Hi".utf8))

    let decoded = try MarkdownTextDecoder.decodeDetailed(source)
    XCTAssertEqual(decoded.encoding, .utf8)
    XCTAssertTrue(decoded.hasBOM)

    var document = MarkdownDocument(text: decoded.text)
    document.encoding = decoded.encoding
    document.hasBOM = decoded.hasBOM
    let written = try document.fileData()
    XCTAssertEqual(Array(written.prefix(3)), [0xEF, 0xBB, 0xBF])
    XCTAssertEqual(Data(written.suffix(4)), Data("# Hi".utf8))
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
