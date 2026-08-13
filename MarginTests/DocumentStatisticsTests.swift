import XCTest

@testable import Margin

final class DocumentStatisticsTests: XCTestCase {
  func testCountsWordsCharactersAndReadingTime() {
    let source = "Margin is a quiet, native Markdown reader."
    let statistics = DocumentStatistics.calculate(for: source)

    XCTAssertEqual(statistics.words, 7)
    XCTAssertEqual(statistics.characters, source.count)
    XCTAssertEqual(statistics.readingMinutes, 1)
  }

  func testEmptyDocumentHasNoReadingTime() {
    XCTAssertEqual(
      DocumentStatistics.calculate(for: ""),
      DocumentStatistics(words: 0, characters: 0, readingMinutes: 0)
    )
  }

  func testReadingTimeRoundsUp() {
    let source = Array(repeating: "word", count: 226).joined(separator: " ")
    XCTAssertEqual(DocumentStatistics.calculate(for: source).readingMinutes, 2)
  }
}
