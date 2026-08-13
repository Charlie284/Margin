import AppKit
import Foundation

enum CodeSyntaxHighlighter {
  static func highlight(_ source: String, language: String?) -> AttributedString {
    var value = AttributedString(source)
    let language = language?.lowercased() ?? ""

    let keywords: [String]
    switch language {
    case "swift":
      keywords = [
        "actor", "class", "enum", "extension", "func", "import", "let", "protocol", "return",
        "struct", "var",
      ]
    case "js", "javascript", "ts", "typescript":
      keywords = [
        "async", "await", "class", "const", "export", "function", "import", "let", "return", "type",
        "var",
      ]
    case "python", "py":
      keywords = [
        "async", "await", "class", "def", "from", "import", "lambda", "return", "with", "yield",
      ]
    case "rust", "rs":
      keywords = [
        "async", "enum", "fn", "impl", "let", "match", "mod", "pub", "struct", "trait", "use",
      ]
    default:
      keywords = []
    }

    let alternation = keywords.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    guard !alternation.isEmpty,
      let expression = try? NSRegularExpression(
        pattern: "(?<![\\p{L}\\p{N}_])(?:\(alternation))(?![\\p{L}\\p{N}_])"
      )
    else { return value }

    let matches = expression.matches(
      in: source,
      range: NSRange(location: 0, length: (source as NSString).length)
    )
    for match in matches {
      guard let stringRange = Range(match.range, in: source),
        let lowerBound = AttributedString.Index(stringRange.lowerBound, within: value),
        let upperBound = AttributedString.Index(stringRange.upperBound, within: value)
      else { continue }
      let range = lowerBound..<upperBound
      value[range].foregroundColor = .purple
      value[range].font = .system(size: 13.5, weight: .semibold, design: .monospaced)
    }

    return value
  }
}
