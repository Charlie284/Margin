import XCTest

@testable import Margin

final class MarkdownParserTests: XCTestCase {
  private let parser = MarkdownParser()

  func testBuildsOutlineFromHeadings() {
    let document = parser.parse("# Margin\n\n## Reader\n\n### Typography")

    XCTAssertEqual(document.outline.map(\.level), [1, 2, 3])
    XCTAssertEqual(document.outline.map(\.title), ["Margin", "Reader", "Typography"])
    XCTAssertEqual(document.blocks.count, 3)
  }

  func testParsesTaskListAndTracksCheckboxSourceRange() throws {
    let source = "- [ ] First task\n- [x] Finished task"
    let document = parser.parse(source)

    guard case .unorderedList(let items) = try XCTUnwrap(document.blocks.first).kind else {
      return XCTFail("Expected an unordered list")
    }

    XCTAssertEqual(items.map(\.taskState), [false, true])
    XCTAssertEqual(items.map(\.text), ["First task", "Finished task"])
    XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(items[0].checkboxRange)), " ")
    XCTAssertEqual((source as NSString).substring(with: try XCTUnwrap(items[1].checkboxRange)), "x")
  }

  func testParsesTableAlignmentAndRows() throws {
    let source = """
      | Name | Role | Score |
      |:-----|:----:|------:|
      | Sam  | CEO  | 10    |
      """

    let document = parser.parse(source)
    guard case .table(let table) = try XCTUnwrap(document.blocks.first).kind else {
      return XCTFail("Expected a table")
    }

    XCTAssertEqual(table.headers, ["Name", "Role", "Score"])
    XCTAssertEqual(table.alignments, [.leading, .center, .trailing])
    XCTAssertEqual(table.rows, [["Sam", "CEO", "10"]])
  }

  func testCodeFencePreservesContentAndLanguage() throws {
    let source = "```swift\nlet value = 42\nprint(value)\n```"
    let document = parser.parse(source)

    guard case .code(let language, let content) = try XCTUnwrap(document.blocks.first).kind else {
      return XCTFail("Expected a code block")
    }

    XCTAssertEqual(language, "swift")
    XCTAssertEqual(content, "let value = 42\nprint(value)")
  }

  func testHeadingPreservesCSharpNameAndStripsSpacedClosingSequence() throws {
    let document = MarkdownParser().parse("# C#\n\n## Title ##")

    XCTAssertEqual(document.outline.map(\.title), ["C#", "Title"])
  }

  func testCodeFenceDoesNotCloseOnTrailingContent() throws {
    let document = MarkdownParser().parse("```swift\nlet value = 1\n```not a close\n```\n")
    guard case .code(_, let content) = document.blocks.first?.kind else {
      return XCTFail("Expected a code block")
    }

    XCTAssertEqual(content, "let value = 1\n```not a close")
  }

  func testFullLineImageAllowsParenthesesInDestination() throws {
    let document = MarkdownParser().parse("![Chart](images/chart(1).png)")
    guard case .image(let alt, let path) = document.blocks.first?.kind else {
      return XCTFail("Expected an image")
    }

    XCTAssertEqual(alt, "Chart")
    XCTAssertEqual(path, "images/chart(1).png")
  }

  func testParsesSetextHeadings() {
    let document = MarkdownParser().parse("Title\n=====\n\nSubtitle\n---")

    XCTAssertEqual(document.outline.map(\.level), [1, 2])
    XCTAssertEqual(document.outline.map(\.title), ["Title", "Subtitle"])
  }

  func testParsesNestedAndContinuedLists() throws {
    let document = MarkdownParser().parse(
      "- Parent\n  continued text\n  1. First child\n  2. Second child\n- Sibling"
    )
    guard case .unorderedList(let items) = document.blocks.first?.kind else {
      return XCTFail("Expected an unordered list")
    }

    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].text, "Parent\ncontinued text")
    guard case .ordered(let start, let children) = try XCTUnwrap(items[0].children.first) else {
      return XCTFail("Expected an ordered child list")
    }
    XCTAssertEqual(start, 1)
    XCTAssertEqual(children.map(\.text), ["First child", "Second child"])
  }

  func testParagraphStopsBeforeAFollowingBlock() {
    let document = parser.parse("A paragraph on two\nwrapped lines.\n\n> A quote")

    XCTAssertEqual(document.blocks.count, 2)
    XCTAssertEqual(document.blocks[0].kind, .paragraph("A paragraph on two\nwrapped lines."))
    XCTAssertEqual(document.blocks[1].kind, .blockquote("A quote"))
  }
}
