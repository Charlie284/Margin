import XCTest

@testable import Margin

final class CommandMatcherTests: XCTestCase {
  func testExactAndPrefixMatchesRankAboveFuzzyMatches() throws {
    let exact = try XCTUnwrap(CommandMatcher.score(query: "read", title: "read"))
    let prefix = try XCTUnwrap(CommandMatcher.score(query: "read", title: "Reader Mode"))
    let fuzzy = try XCTUnwrap(CommandMatcher.score(query: "read", title: "Reveal Document"))

    XCTAssertGreaterThan(exact, prefix)
    XCTAssertGreaterThan(prefix, fuzzy)
  }

  func testAliasesAreSearchable() {
    XCTAssertNotNil(
      CommandMatcher.score(
        query: "preview",
        title: "Switch to Read",
        aliases: ["reader", "preview"]
      )
    )
  }

  func testNonMatchingQueryReturnsNil() {
    XCTAssertNil(CommandMatcher.score(query: "export", title: "Toggle Sidebar"))
  }

  func testMatchingIsCaseAndDiacriticInsensitive() {
    XCTAssertNotNil(CommandMatcher.score(query: "resume", title: "Résumé"))
  }
}
