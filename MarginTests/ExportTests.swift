import XCTest

@testable import Margin

final class ExportTests: XCTestCase {
  func testHTMLRendererProducesSemanticDocument() {
    let source = """
      # Margin

      A **native** [editor](https://example.com).

      - [x] Read
      - [ ] Write

      | Mode | State |
      |------|------:|
      | Read | Fast |

      ```swift
      let value = 1 < 2
      ```
      """
    let html = MarkdownHTMLRenderer().render(source: source)

    XCTAssertTrue(html.contains(#"<h1 id="margin">Margin</h1>"#))
    XCTAssertTrue(html.contains("<strong>native</strong>"))
    XCTAssertTrue(html.contains(#"<a href="https://example.com">editor</a>"#))
    XCTAssertTrue(html.contains(#"class="task checked""#))
    XCTAssertTrue(html.contains("<table>"))
    XCTAssertTrue(html.contains("let value = 1 &lt; 2"))
  }

  func testHTMLRendererEscapesContentAndUnsafeURLs() {
    let source =
      "<script>alert('no')</script>\n\n[unsafe](javascript:alert(1)) [custom](margin://open)"
    let html = MarkdownHTMLRenderer().render(source: source)

    XCTAssertFalse(html.contains("<script>alert"))
    XCTAssertTrue(html.contains("&lt;script&gt;"))
    XCTAssertFalse(html.contains(#"href="javascript:"#))
    XCTAssertFalse(html.contains(#"href="margin:"#))
  }

  func testHTMLRendererBlocksRemoteImageRequestsButKeepsWebLinks() {
    let source = #"[website](https://example.com) ![tracker](https://example.com/pixel.png)"#
    let html = MarkdownHTMLRenderer().render(source: source)

    XCTAssertTrue(html.contains(#"href="https://example.com""#))
    XCTAssertFalse(html.contains(#"src="https://example.com/pixel.png""#))
  }

  func testHTMLRendererDoesNotExposeBaseURLAndIncludesNativeStyles() {
    let baseURL = URL(fileURLWithPath: "/tmp/Margin Documents", isDirectory: true)
    let html = MarkdownHTMLRenderer().render(
      source: "# Margin",
      baseURL: baseURL
    )

    XCTAssertFalse(html.contains("<base href="))
    XCTAssertFalse(html.contains("/tmp/Margin Documents"))
    XCTAssertTrue(html.contains("#202124"))
    XCTAssertTrue(html.contains("SF Pro Text"))
  }

  func testHTMLRendererHandlesParenthesizedLinksAndIntrawordUnderscores() {
    let html = MarkdownHTMLRenderer().render(
      source: "[reference](https://example.com/a_(b)) and snake_case_value"
    )

    XCTAssertTrue(html.contains(#"href="https://example.com/a_(b)""#))
    XCTAssertTrue(html.contains("snake_case_value"))
    XCTAssertFalse(html.contains("snake<em>case</em>value"))
  }

  func testHTMLRendererGeneratesUniqueHeadingIdentifiers() {
    let html = MarkdownHTMLRenderer().render(source: "# Repeat\n\n## Repeat\n\n# 🎉")

    XCTAssertTrue(html.contains(#"id="repeat""#))
    XCTAssertTrue(html.contains(#"id="repeat-2""#))
    XCTAssertTrue(html.contains(#"id="section""#))
  }

  func testHTMLRendererEmbedsLocalImages() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("MarginHTML-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    try Data(base64Encoded: onePixelPNG)!.write(to: directory.appendingPathComponent("pixel.png"))

    let html = MarkdownHTMLRenderer().render(
      source: "![Pixel](pixel.png)",
      baseURL: directory
    )

    XCTAssertTrue(html.contains("src=\"data:image/png;base64,"))
    XCTAssertFalse(html.contains(directory.path))
  }

  @MainActor
  func testPDFExporterProducesPDFData() async throws {
    let html = MarkdownHTMLRenderer().render(
      source: "# Export\n\nA real PDF document."
    )
    let destination = FileManager.default.temporaryDirectory
      .appendingPathComponent("MarginExport-\(UUID().uuidString).pdf")
    addTeardownBlock { try? FileManager.default.removeItem(at: destination) }

    try await DocumentExporter.writePDF(html, baseURL: nil, to: destination)

    let data = try Data(contentsOf: destination)
    XCTAssertGreaterThan(data.count, 1_000)
    XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "%PDF")
  }

  private var onePixelPNG: String {
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
  }
}
