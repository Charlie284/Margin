import XCTest

@testable import Margin

final class WorkspaceIndexTests: XCTestCase {
  func testIndexerFindsMarkdownAndSkipsIgnoredDirectories() throws {
    let root = try makeWorkspace()
    try write("# Readme\n\nArchitecture overview", to: root.appendingPathComponent("README.md"))
    try write("plain text", to: root.appendingPathComponent("notes.txt"))

    let ignored = root.appendingPathComponent("node_modules")
    try FileManager.default.createDirectory(at: ignored, withIntermediateDirectories: true)
    try write("# Dependency", to: ignored.appendingPathComponent("DEPENDENCY.md"))

    let index = try WorkspaceIndexer.indexSynchronously(root)

    XCTAssertEqual(index.files.map(\.relativePath), ["README.md"])
    XCTAssertEqual(index.files.first?.headings, ["Readme"])
  }

  func testIndexerReadsUTF16Markdown() throws {
    let root = try makeWorkspace()
    let url = root.appendingPathComponent("UTF16.md")
    try XCTUnwrap("# Encoded\n\nSearchable content".data(using: .utf16)).write(to: url)

    let index = try WorkspaceIndexer.indexSynchronously(root)

    XCTAssertEqual(index.files.first?.headings, ["Encoded"])
    XCTAssertEqual(index.searchContent("Searchable").first?.file.url, url)
  }

  func testQuickOpenMatchesFilenamesPathsAndHeadings() throws {
    let root = try makeWorkspace()
    let file = WorkspaceFile(
      url: root.appendingPathComponent("docs/system.md"),
      relativePath: "docs/system.md",
      content: "# Renderer",
      headings: ["Renderer"],
      modifiedAt: nil,
      byteCount: 10
    )
    let index = WorkspaceIndex(rootURL: root, files: [file])

    XCTAssertEqual(index.matchingFiles("rend").first?.id, file.id)
    XCTAssertEqual(index.matchingFiles("docs sys").first?.id, file.id)
    XCTAssertTrue(index.matchingFiles("database").isEmpty)
  }

  func testContentSearchReturnsLineAndExcerpt() throws {
    let root = try makeWorkspace()
    let file = WorkspaceFile(
      url: root.appendingPathComponent("Architecture.md"),
      relativePath: "Architecture.md",
      content: "# Architecture\n\nThe renderer uses native views.",
      headings: ["Architecture"],
      modifiedAt: nil,
      byteCount: 45
    )
    let index = WorkspaceIndex(rootURL: root, files: [file])

    let result = try XCTUnwrap(index.searchContent("native").first)
    XCTAssertEqual(result.line, 3)
    XCTAssertEqual(result.excerpt, "The renderer uses native views.")
    XCTAssertEqual(index.searchContent("/render.*native/").count, 1)
    XCTAssertNotNil(index.searchContentResponse("/[invalid/").errorMessage)
  }

  func testBacklinksResolveCanonicalPathsAndRejectAmbiguousWikiNames() throws {
    let root = try makeWorkspace()
    let target = workspaceFile(root: root, path: "docs/Architecture.md", content: "")
    let duplicate = workspaceFile(root: root, path: "other/Architecture.md", content: "")
    let relativeLink = workspaceFile(
      root: root,
      path: "notes/Review.md",
      content: "See [Architecture](../docs/Architecture.md#overview)."
    )
    let ambiguousWiki = workspaceFile(
      root: root,
      path: "Roadmap.md",
      content: "Continue in [[Architecture]]."
    )
    let index = WorkspaceIndex(
      rootURL: root,
      files: [target, duplicate, relativeLink, ambiguousWiki]
    )

    XCTAssertEqual(index.backlinks(to: target.url).map(\.name), ["Review.md"])
  }

  func testBacklinksRecognizeMarkdownAndWikiLinks() throws {
    let root = try makeWorkspace()
    let target = workspaceFile(root: root, path: "docs/Architecture.md", content: "# Architecture")
    let markdownLink = workspaceFile(
      root: root,
      path: "README.md",
      content: "See [Architecture](docs/Architecture.md)."
    )
    let wikiLink = workspaceFile(
      root: root,
      path: "Roadmap.md",
      content: "Continue in [[Architecture]]."
    )
    let index = WorkspaceIndex(rootURL: root, files: [target, markdownLink, wikiLink])

    XCTAssertEqual(Set(index.backlinks(to: target.url).map(\.name)), ["README.md", "Roadmap.md"])
  }

  func testSpotlightMetadataIncludesSearchableContentAndStableDomain() throws {
    let root = try makeWorkspace()
    let file = workspaceFile(
      root: root,
      path: "docs/Architecture.md",
      content: "# Architecture\n\nNative rendering details."
    )

    let document = SpotlightDocument(file: file, rootURL: root)
    let duplicate = SpotlightDocument(file: file, rootURL: root)

    XCTAssertEqual(document, duplicate)
    XCTAssertEqual(document.title, "Architecture")
    XCTAssertEqual(document.relativePath, "docs/Architecture.md")
    XCTAssertEqual(document.headings, ["Architecture"])
    XCTAssertTrue(document.domainIdentifier.hasPrefix("com.marginapp.workspace."))
    XCTAssertEqual(document.searchableItem.attributeSet.textContent, file.content)
    XCTAssertEqual(document.searchableItem.attributeSet.contentURL, file.url)
  }

  private func makeWorkspace() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("MarginTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }

  private func write(_ content: String, to url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try XCTUnwrap(content.data(using: .utf8)).write(to: url)
  }

  private func workspaceFile(root: URL, path: String, content: String) -> WorkspaceFile {
    WorkspaceFile(
      url: root.appendingPathComponent(path),
      relativePath: path,
      content: content,
      headings: MarkdownParser().parse(content).outline.map(\.title),
      modifiedAt: nil,
      byteCount: content.utf8.count
    )
  }
}
