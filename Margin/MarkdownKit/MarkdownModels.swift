import Foundation

struct ParsedMarkdownDocument: Equatable, Sendable {
  var blocks: [MarkdownBlock]
  var outline: [OutlineEntry]
  var statistics: DocumentStatistics

  static let empty = ParsedMarkdownDocument(
    blocks: [],
    outline: [],
    statistics: .init(words: 0, characters: 0, readingMinutes: 0)
  )
}

struct MarkdownBlock: Equatable, Identifiable, Sendable {
  let id: String
  let sourceRange: NSRange
  let kind: Kind

  enum Kind: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case blockquote(String)
    case code(language: String?, content: String)
    case unorderedList([MarkdownListItem])
    case orderedList(start: Int, items: [MarkdownListItem])
    case table(MarkdownTable)
    case image(alt: String, path: String)
    case footnote(label: String, text: String)
    case thematicBreak
  }
}

struct MarkdownListItem: Equatable, Identifiable, Sendable {
  let id: String
  let text: String
  let taskState: Bool?
  let checkboxRange: NSRange?
  let children: [MarkdownNestedList]

  init(
    id: String,
    text: String,
    taskState: Bool?,
    checkboxRange: NSRange?,
    children: [MarkdownNestedList] = []
  ) {
    self.id = id
    self.text = text
    self.taskState = taskState
    self.checkboxRange = checkboxRange
    self.children = children
  }
}

indirect enum MarkdownNestedList: Equatable, Sendable {
  case unordered([MarkdownListItem])
  case ordered(start: Int, items: [MarkdownListItem])
}

struct MarkdownTable: Equatable, Sendable {
  let headers: [String]
  let alignments: [MarkdownTableAlignment]
  let rows: [[String]]
}

enum MarkdownTableAlignment: Equatable, Sendable {
  case leading
  case center
  case trailing
}

struct OutlineEntry: Equatable, Identifiable, Sendable {
  let id: String
  let level: Int
  let title: String
}

struct DocumentStatistics: Equatable, Sendable {
  let words: Int
  let characters: Int
  let readingMinutes: Int

  static func calculate(for source: String) -> DocumentStatistics {
    let range = NSRange(location: 0, length: (source as NSString).length)
    let expression = try? NSRegularExpression(
      pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)?"#
    )
    let words = expression?.numberOfMatches(in: source, range: range) ?? 0
    let minutes = words == 0 ? 0 : max(1, Int(ceil(Double(words) / 225.0)))

    return DocumentStatistics(
      words: words,
      characters: source.count,
      readingMinutes: minutes
    )
  }
}
