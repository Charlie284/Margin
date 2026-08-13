import Foundation

struct MarkdownParser {
  private struct SourceLine {
    let text: String
    let range: NSRange
  }

  private enum ListStyle: Equatable {
    case unordered
    case ordered
  }

  private struct ListMatch {
    let style: ListStyle
    let indentation: Int
    let number: Int
    let content: String
  }

  func parse(_ source: String) -> ParsedMarkdownDocument {
    let lines = sourceLines(in: source)
    var blocks: [MarkdownBlock] = []
    var outline: [OutlineEntry] = []
    var index = 0

    while index < lines.count {
      if Task.isCancelled { break }
      let line = lines[index]
      let trimmed = line.text.trimmingCharacters(in: .whitespaces)

      if trimmed.isEmpty {
        index += 1
        continue
      }

      if let fence = fenceOpening(in: line.text) {
        let result = parseCodeBlock(lines: lines, start: index, fence: fence)
        blocks.append(result.block)
        index = result.nextIndex
        continue
      }

      if let heading = setextHeading(at: index, lines: lines) {
        let range = combinedRange(lines: lines, start: index, end: index + 2)
        let id = blockID(kind: "heading", location: line.range.location)
        blocks.append(
          MarkdownBlock(
            id: id,
            sourceRange: range,
            kind: .heading(level: heading.level, text: heading.text)
          )
        )
        outline.append(OutlineEntry(id: id, level: heading.level, title: heading.text))
        index += 2
        continue
      }

      if let heading = heading(in: line.text) {
        let id = blockID(kind: "heading", location: line.range.location)
        blocks.append(
          MarkdownBlock(
            id: id,
            sourceRange: line.range,
            kind: .heading(level: heading.level, text: heading.text)
          )
        )
        outline.append(OutlineEntry(id: id, level: heading.level, title: heading.text))
        index += 1
        continue
      }

      if isThematicBreak(trimmed) {
        blocks.append(
          MarkdownBlock(
            id: blockID(kind: "rule", location: line.range.location),
            sourceRange: line.range,
            kind: .thematicBreak
          )
        )
        index += 1
        continue
      }

      if let image = fullLineImage(in: trimmed) {
        blocks.append(
          MarkdownBlock(
            id: blockID(kind: "image", location: line.range.location),
            sourceRange: line.range,
            kind: .image(alt: image.alt, path: image.path)
          )
        )
        index += 1
        continue
      }

      if let footnote = footnote(in: trimmed) {
        blocks.append(
          MarkdownBlock(
            id: blockID(kind: "footnote", location: line.range.location),
            sourceRange: line.range,
            kind: .footnote(label: footnote.label, text: footnote.text)
          )
        )
        index += 1
        continue
      }

      if isTableHeader(at: index, lines: lines) {
        let result = parseTable(lines: lines, start: index)
        blocks.append(result.block)
        index = result.nextIndex
        continue
      }

      if unorderedListMatch(in: line.text) != nil {
        let result = parseUnorderedList(lines: lines, start: index)
        blocks.append(result.block)
        index = result.nextIndex
        continue
      }

      if orderedListMatch(in: line.text) != nil {
        let result = parseOrderedList(lines: lines, start: index)
        blocks.append(result.block)
        index = result.nextIndex
        continue
      }

      if trimmed.hasPrefix(">") {
        let result = parseBlockquote(lines: lines, start: index)
        blocks.append(result.block)
        index = result.nextIndex
        continue
      }

      let result = parseParagraph(lines: lines, start: index)
      blocks.append(result.block)
      index = result.nextIndex
    }

    return ParsedMarkdownDocument(
      blocks: blocks,
      outline: outline,
      statistics: .calculate(for: source)
    )
  }

  private func sourceLines(in source: String) -> [SourceLine] {
    let components = source.components(separatedBy: "\n")
    var location = 0

    return components.map { component in
      let lineLength = (component as NSString).length
      let line = SourceLine(
        text: component.trimmingCharacters(in: CharacterSet(charactersIn: "\r")),
        range: NSRange(location: location, length: lineLength)
      )
      location += lineLength + 1
      return line
    }
  }

  private func heading(in line: String) -> (level: Int, text: String)? {
    guard let match = firstMatch(pattern: #"^ {0,3}(#{1,6})(?:[\t ]+(.*?))?[\t ]*$"#, in: line),
      let markerRange = Range(match.range(at: 1), in: line)
    else { return nil }

    let rawText: String
    if match.range(at: 2).location != NSNotFound,
      let textRange = Range(match.range(at: 2), in: line)
    {
      rawText = String(line[textRange])
    } else {
      rawText = ""
    }
    let text = rawText.replacingOccurrences(
      of: #"[\t ]+#+[\t ]*$"#,
      with: "",
      options: .regularExpression
    )
    return (line[markerRange].count, text)
  }

  private func fenceOpening(in line: String) -> (marker: String, language: String?)? {
    guard let match = firstMatch(pattern: #"^ {0,3}(`{3,}|~{3,})[\t ]*([^\s`]*)?.*$"#, in: line),
      let markerRange = Range(match.range(at: 1), in: line)
    else { return nil }

    let marker = String(line[markerRange])
    var language: String?
    if match.range(at: 2).location != NSNotFound,
      let range = Range(match.range(at: 2), in: line)
    {
      let value = String(line[range]).trimmingCharacters(in: .whitespaces)
      language = value.isEmpty ? nil : value
    }
    return (marker, language)
  }

  private func setextHeading(at index: Int, lines: [SourceLine]) -> (level: Int, text: String)? {
    guard index + 1 < lines.count else { return nil }
    let text = lines[index].text.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty,
      let match = firstMatch(pattern: #"^ {0,3}(=+|-+)[\t ]*$"#, in: lines[index + 1].text),
      let markerRange = Range(match.range(at: 1), in: lines[index + 1].text)
    else { return nil }
    return (lines[index + 1].text[markerRange].first == "=" ? 1 : 2, text)
  }

  private func parseCodeBlock(
    lines: [SourceLine],
    start: Int,
    fence: (marker: String, language: String?)
  ) -> (block: MarkdownBlock, nextIndex: Int) {
    let fenceCharacter = fence.marker.first
    let minimumLength = fence.marker.count
    var index = start + 1
    var content: [String] = []

    while index < lines.count {
      if Task.isCancelled { break }
      let escapedCharacter = NSRegularExpression.escapedPattern(
        for: String(fenceCharacter ?? "`")
      )
      let closingPattern = "^ {0,3}\(escapedCharacter){\(minimumLength),}[\\t ]*$"
      if firstMatch(pattern: closingPattern, in: lines[index].text) != nil {
        index += 1
        break
      }
      content.append(lines[index].text)
      index += 1
    }

    let end =
      lines[max(start, index - 1)].range.location + lines[max(start, index - 1)].range.length
    let range = NSRange(
      location: lines[start].range.location, length: end - lines[start].range.location)
    return (
      MarkdownBlock(
        id: blockID(kind: "code", location: range.location),
        sourceRange: range,
        kind: .code(language: fence.language, content: content.joined(separator: "\n"))
      ),
      index
    )
  }

  private func parseUnorderedList(lines: [SourceLine], start: Int) -> (
    block: MarkdownBlock, nextIndex: Int
  ) {
    let result = parseNestedList(lines: lines, start: start)
    let items: [MarkdownListItem]
    if case .unordered(let parsedItems) = result.list { items = parsedItems } else { items = [] }
    let index = result.nextIndex

    let range = combinedRange(lines: lines, start: start, end: index)
    return (
      MarkdownBlock(
        id: blockID(kind: "unordered", location: range.location),
        sourceRange: range,
        kind: .unorderedList(items)
      ),
      index
    )
  }

  private func parseOrderedList(lines: [SourceLine], start: Int) -> (
    block: MarkdownBlock, nextIndex: Int
  ) {
    let result = parseNestedList(lines: lines, start: start)
    let startingNumber: Int
    let items: [MarkdownListItem]
    if case .ordered(let parsedStart, let parsedItems) = result.list {
      startingNumber = parsedStart
      items = parsedItems
    } else {
      startingNumber = 1
      items = []
    }
    let index = result.nextIndex

    let range = combinedRange(lines: lines, start: start, end: index)
    return (
      MarkdownBlock(
        id: blockID(kind: "ordered", location: range.location),
        sourceRange: range,
        kind: .orderedList(start: startingNumber, items: items)
      ),
      index
    )
  }

  private func parseNestedList(lines: [SourceLine], start: Int) -> (
    list: MarkdownNestedList, nextIndex: Int
  ) {
    guard let first = listMatch(in: lines[start].text) else {
      return (.unordered([]), start + 1)
    }
    let style = first.style
    let baseIndentation = first.indentation
    let startingNumber = first.number
    var items: [MarkdownListItem] = []
    var index = start

    while index < lines.count, let match = listMatch(in: lines[index].text),
      match.style == style, match.indentation == baseIndentation
    {
      if Task.isCancelled { break }
      let itemLine = lines[index]
      let task = style == .unordered ? taskMatch(in: match.content) : nil
      var textParts = [task?.text ?? match.content]
      var children: [MarkdownNestedList] = []
      var checkboxRange: NSRange?
      if let task,
        let marker = (itemLine.text as NSString).range(of: task.marker).nonNotFound
      {
        checkboxRange = NSRange(
          location: itemLine.range.location + marker.location + 1,
          length: 1
        )
      }
      index += 1

      while index < lines.count {
        if Task.isCancelled { break }
        if let nestedMatch = listMatch(in: lines[index].text) {
          guard nestedMatch.indentation > baseIndentation else { break }
          let nested = parseNestedList(lines: lines, start: index)
          children.append(nested.list)
          index = nested.nextIndex
          continue
        }

        let continuation = lines[index].text
        guard !continuation.trimmingCharacters(in: .whitespaces).isEmpty,
          leadingIndentation(in: continuation) > baseIndentation
        else { break }
        textParts.append(continuation.trimmingCharacters(in: .whitespaces))
        index += 1
      }

      items.append(
        MarkdownListItem(
          id: "item-\(itemLine.range.location)",
          text: textParts.joined(separator: "\n"),
          taskState: task?.checked,
          checkboxRange: checkboxRange,
          children: children
        )
      )
    }

    switch style {
    case .unordered: return (.unordered(items), index)
    case .ordered: return (.ordered(start: startingNumber, items: items), index)
    }
  }

  private func parseBlockquote(lines: [SourceLine], start: Int) -> (
    block: MarkdownBlock, nextIndex: Int
  ) {
    var quoted: [String] = []
    var index = start

    while index < lines.count {
      if Task.isCancelled { break }
      let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix(">") else { break }
      quoted.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
      index += 1
    }

    let range = combinedRange(lines: lines, start: start, end: index)
    return (
      MarkdownBlock(
        id: blockID(kind: "quote", location: range.location),
        sourceRange: range,
        kind: .blockquote(quoted.joined(separator: "\n"))
      ),
      index
    )
  }

  private func parseTable(lines: [SourceLine], start: Int) -> (block: MarkdownBlock, nextIndex: Int)
  {
    let headers = tableCells(in: lines[start].text)
    let alignmentCells = tableCells(in: lines[start + 1].text)
    let alignments = alignmentCells.map { cell -> MarkdownTableAlignment in
      let trimmed = cell.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") { return .center }
      if trimmed.hasSuffix(":") { return .trailing }
      return .leading
    }

    var rows: [[String]] = []
    var index = start + 2
    while index < lines.count {
      if Task.isCancelled { break }
      let cells = tableCells(in: lines[index].text)
      guard cells.count == headers.count, lines[index].text.contains("|") else { break }
      rows.append(cells)
      index += 1
    }

    let range = combinedRange(lines: lines, start: start, end: index)
    return (
      MarkdownBlock(
        id: blockID(kind: "table", location: range.location),
        sourceRange: range,
        kind: .table(MarkdownTable(headers: headers, alignments: alignments, rows: rows))
      ),
      index
    )
  }

  private func parseParagraph(lines: [SourceLine], start: Int) -> (
    block: MarkdownBlock, nextIndex: Int
  ) {
    var content: [String] = []
    var index = start

    while index < lines.count {
      if Task.isCancelled { break }
      let trimmed = lines[index].text.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || (index > start && isBlockStart(at: index, lines: lines)) { break }
      content.append(trimmed)
      index += 1
    }

    let range = combinedRange(lines: lines, start: start, end: index)
    return (
      MarkdownBlock(
        id: blockID(kind: "paragraph", location: range.location),
        sourceRange: range,
        kind: .paragraph(content.joined(separator: "\n"))
      ),
      index
    )
  }

  private func isBlockStart(at index: Int, lines: [SourceLine]) -> Bool {
    let line = lines[index].text
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return heading(in: line) != nil
      || fenceOpening(in: line) != nil
      || isThematicBreak(trimmed)
      || fullLineImage(in: trimmed) != nil
      || footnote(in: trimmed) != nil
      || unorderedListMatch(in: line) != nil
      || orderedListMatch(in: line) != nil
      || trimmed.hasPrefix(">")
      || isTableHeader(at: index, lines: lines)
  }

  private func unorderedListMatch(in line: String) -> (content: String, contentRange: NSRange)? {
    guard let match = listMatch(in: line), match.style == .unordered,
      match.indentation <= 3
    else { return nil }
    return (match.content, NSRange(location: 0, length: 0))
  }

  private func orderedListMatch(in line: String) -> (number: Int, content: String)? {
    guard let match = listMatch(in: line), match.style == .ordered,
      match.indentation <= 3
    else { return nil }
    return (match.number, match.content)
  }

  private func listMatch(in line: String) -> ListMatch? {
    if let match = firstMatch(pattern: #"^([\t ]*)[-+*][\t ]+(.*)$"#, in: line),
      let indentationRange = Range(match.range(at: 1), in: line),
      let contentRange = Range(match.range(at: 2), in: line)
    {
      return ListMatch(
        style: .unordered,
        indentation: indentationWidth(String(line[indentationRange])),
        number: 1,
        content: String(line[contentRange])
      )
    }
    if let match = firstMatch(pattern: #"^([\t ]*)(\d+)[.)][\t ]+(.*)$"#, in: line),
      let indentationRange = Range(match.range(at: 1), in: line),
      let numberRange = Range(match.range(at: 2), in: line),
      let contentRange = Range(match.range(at: 3), in: line)
    {
      return ListMatch(
        style: .ordered,
        indentation: indentationWidth(String(line[indentationRange])),
        number: Int(line[numberRange]) ?? 1,
        content: String(line[contentRange])
      )
    }
    return nil
  }

  private func leadingIndentation(in line: String) -> Int {
    indentationWidth(String(line.prefix { $0 == " " || $0 == "\t" }))
  }

  private func indentationWidth(_ value: String) -> Int {
    value.reduce(0) { $1 == "\t" ? $0 + 4 : $0 + 1 }
  }

  private func taskMatch(in content: String) -> (marker: String, checked: Bool, text: String)? {
    guard let match = firstMatch(pattern: #"^\[([ xX])\][\t ]+(.+)$"#, in: content),
      let stateRange = Range(match.range(at: 1), in: content),
      let textRange = Range(match.range(at: 2), in: content)
    else { return nil }
    let state = String(content[stateRange])
    return ("[\(state)]", state.lowercased() == "x", String(content[textRange]))
  }

  private func fullLineImage(in line: String) -> (alt: String, path: String)? {
    guard line.hasPrefix("!["), let marker = line.range(of: "](") else { return nil }
    let altStart = line.index(line.startIndex, offsetBy: 2)
    let alt = String(line[altStart..<marker.lowerBound])
    var index = marker.upperBound
    let pathStart = index
    var depth = 1
    var escaped = false
    while index < line.endIndex {
      let character = line[index]
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "(" {
        depth += 1
      } else if character == ")" {
        depth -= 1
        if depth == 0 {
          guard line.index(after: index) == line.endIndex else { return nil }
          return (alt, String(line[pathStart..<index]))
        }
      }
      index = line.index(after: index)
    }
    return nil
  }

  private func footnote(in line: String) -> (label: String, text: String)? {
    guard let match = firstMatch(pattern: #"^\[\^([^\]]+)\]:[\t ]+(.+)$"#, in: line),
      let labelRange = Range(match.range(at: 1), in: line),
      let textRange = Range(match.range(at: 2), in: line)
    else { return nil }
    return (String(line[labelRange]), String(line[textRange]))
  }

  private func isThematicBreak(_ line: String) -> Bool {
    firstMatch(pattern: #"^(?:\*\s*){3,}$|^(?:-\s*){3,}$|^(?:_\s*){3,}$"#, in: line) != nil
  }

  private func isTableHeader(at index: Int, lines: [SourceLine]) -> Bool {
    guard index + 1 < lines.count, lines[index].text.contains("|") else { return false }
    let headers = tableCells(in: lines[index].text)
    let alignments = tableCells(in: lines[index + 1].text)
    guard headers.count > 1, headers.count == alignments.count else { return false }
    return alignments.allSatisfy {
      firstMatch(pattern: #"^:?-{3,}:?$"#, in: $0.trimmingCharacters(in: .whitespaces)) != nil
    }
  }

  private func tableCells(in line: String) -> [String] {
    var value = line.trimmingCharacters(in: .whitespaces)
    if value.hasPrefix("|") { value.removeFirst() }
    if value.hasSuffix("|") { value.removeLast() }

    var cells: [String] = []
    var current = ""
    var escaped = false
    for character in value {
      if character == "|" && !escaped {
        cells.append(current.trimmingCharacters(in: .whitespaces))
        current = ""
      } else if character == "|" && escaped {
        if current.last == "\\" { current.removeLast() }
        current.append(character)
      } else {
        current.append(character)
      }
      escaped = character == "\\" && !escaped
      if character != "\\" { escaped = false }
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
  }

  private func combinedRange(lines: [SourceLine], start: Int, end: Int) -> NSRange {
    let lastIndex = max(start, end - 1)
    let location = lines[start].range.location
    let finalLocation = lines[lastIndex].range.location + lines[lastIndex].range.length
    return NSRange(location: location, length: finalLocation - location)
  }

  private func blockID(kind: String, location: Int) -> String {
    "\(kind)-\(location)"
  }

  private func firstMatch(pattern: String, in string: String) -> NSTextCheckingResult? {
    let expression = try? NSRegularExpression(pattern: pattern)
    let range = NSRange(location: 0, length: (string as NSString).length)
    return expression?.firstMatch(in: string, range: range)
  }
}

extension NSRange {
  fileprivate var nonNotFound: NSRange? {
    location == NSNotFound ? nil : self
  }
}
