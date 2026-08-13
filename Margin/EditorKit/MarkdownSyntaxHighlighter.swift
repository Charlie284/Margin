import AppKit

final class MarkdownSyntaxHighlighter {
  var baseURL: URL?
  let baseFont = NSFont.systemFont(ofSize: 16, weight: .regular)

  init(baseURL: URL? = nil) {
    self.baseURL = baseURL
  }

  var baseAttributes: [NSAttributedString.Key: Any] {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 5
    paragraph.paragraphSpacing = 3
    return [
      .font: baseFont,
      .foregroundColor: NSColor.labelColor,
      .paragraphStyle: paragraph,
    ]
  }

  func apply(to storage: NSTextStorage, selection: NSRange) {
    let fullRange = NSRange(location: 0, length: storage.length)
    guard fullRange.length > 0 else { return }

    storage.beginEditing()
    storage.setAttributes(baseAttributes, range: fullRange)

    applyHeadings(to: storage, selection: selection)
    applyEmphasis(to: storage, selection: selection)
    applyInlineCode(to: storage, selection: selection)
    applyLinks(to: storage, selection: selection)
    applyLineSyntax(to: storage, selection: selection)
    applyCodeFences(to: storage, selection: selection)
    storage.endEditing()
  }

  private func applyHeadings(to storage: NSTextStorage, selection: NSRange) {
    enumerate(#"(?m)^(#{1,6})([\t ]+)(.+)$"#, in: storage.string) { match in
      let level = match.range(at: 1).length
      let sizes: [CGFloat] = [30, 25, 22, 19, 17, 16]
      let weights: [NSFont.Weight] = [.bold, .bold, .semibold, .semibold, .medium, .medium]
      let contentRange = match.range(at: 3)
      let markerRange = NSUnionRange(match.range(at: 1), match.range(at: 2))
      let paragraph = NSMutableParagraphStyle()
      paragraph.lineSpacing = 3
      paragraph.paragraphSpacingBefore = level < 3 ? 14 : 8
      paragraph.paragraphSpacing = level < 3 ? 7 : 4

      storage.addAttributes(
        [
          .font: NSFont.systemFont(ofSize: sizes[level - 1], weight: weights[level - 1]),
          .paragraphStyle: paragraph,
        ],
        range: contentRange
      )
      fadeSyntax(markerRange, in: storage, selection: selection)
    }
  }

  private func applyEmphasis(to storage: NSTextStorage, selection: NSRange) {
    enumerate(#"(\*\*|__)(.+?)(\1)"#, in: storage.string) { match in
      storage.addAttribute(
        .font,
        value: NSFont.systemFont(ofSize: 16, weight: .semibold),
        range: match.range(at: 2)
      )
      fadeSyntax(match.range(at: 1), in: storage, selection: selection)
      fadeSyntax(match.range(at: 3), in: storage, selection: selection)
    }

    enumerate(#"(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#, in: storage.string) { match in
      let contentRange =
        match.range(at: 1).location != NSNotFound ? match.range(at: 1) : match.range(at: 2)
      storage.addAttribute(
        .font,
        value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
        range: contentRange
      )
      let wholeRange = match.range(at: 0)
      fadeSyntax(
        NSRange(location: wholeRange.location, length: 1), in: storage, selection: selection)
      fadeSyntax(
        NSRange(location: NSMaxRange(wholeRange) - 1, length: 1), in: storage, selection: selection)
    }
  }

  private func applyInlineCode(to storage: NSTextStorage, selection: NSRange) {
    enumerate(#"(?<!`)`([^`\n]+)`(?!`)"#, in: storage.string) { match in
      storage.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 14.5, weight: .regular),
          .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.16),
        ],
        range: match.range(at: 1)
      )
      let wholeRange = match.range(at: 0)
      fadeSyntax(
        NSRange(location: wholeRange.location, length: 1), in: storage, selection: selection)
      fadeSyntax(
        NSRange(location: NSMaxRange(wholeRange) - 1, length: 1), in: storage, selection: selection)
    }
  }

  private func applyLinks(to storage: NSTextStorage, selection: NSRange) {
    enumerate(#"!?\[([^\]]+)\]\(([^\)]+)\)"#, in: storage.string) { match in
      storage.addAttributes(
        [.foregroundColor: NSColor.controlAccentColor],
        range: match.range(at: 1)
      )
      if let destinationRange = Range(match.range(at: 2), in: storage.string),
        let url = linkURL(String(storage.string[destinationRange]))
      {
        storage.addAttribute(.link, value: url, range: match.range(at: 1))
      }

      let whole = match.range(at: 0)
      let label = match.range(at: 1)
      let prefixLength = label.location - whole.location
      fadeSyntax(
        NSRange(location: whole.location, length: prefixLength), in: storage, selection: selection)
      fadeSyntax(
        NSRange(location: NSMaxRange(label), length: NSMaxRange(whole) - NSMaxRange(label)),
        in: storage,
        selection: selection
      )
    }
  }

  private func linkURL(_ destination: String) -> URL? {
    let value = destination.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    if let absolute = URL(string: value),
      let scheme = absolute.scheme?.lowercased(),
      ["http", "https", "mailto", "file"].contains(scheme)
    {
      return absolute
    }
    guard let baseURL else { return nil }
    return URL(fileURLWithPath: value.removingPercentEncoding ?? value, relativeTo: baseURL)
      .standardizedFileURL
  }

  private func applyLineSyntax(to storage: NSTextStorage, selection: NSRange) {
    let patterns = [
      #"(?m)^(\s*[-+*]\s+)"#,
      #"(?m)^(\s*\d+[.)]\s+)"#,
      #"(?m)^(\s*>\s?)"#,
      #"(?m)^(\s*[-+*]\s+\[[ xX]\]\s+)"#,
      #"(?m)^\s*(?:-{3,}|\*{3,}|_{3,})\s*$"#,
    ]

    for pattern in patterns {
      enumerate(pattern, in: storage.string) { match in
        let range = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
        fadeSyntax(range, in: storage, selection: selection)
      }
    }
  }

  private func applyCodeFences(to storage: NSTextStorage, selection: NSRange) {
    enumerate(#"(?ms)^(```|~~~)([^\n]*)\n(.*?)(?:\n\1\s*$|\z)"#, in: storage.string) { match in
      let codeRange = match.range(at: 3)
      storage.addAttributes(
        [
          .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
          .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.12),
        ],
        range: codeRange
      )

      let firstFenceLength = match.range(at: 1).length + match.range(at: 2).length
      fadeSyntax(
        NSRange(location: match.range(at: 0).location, length: firstFenceLength),
        in: storage,
        selection: selection
      )
      let trailingLocation = NSMaxRange(codeRange)
      if trailingLocation < NSMaxRange(match.range(at: 0)) {
        fadeSyntax(
          NSRange(
            location: trailingLocation, length: NSMaxRange(match.range(at: 0)) - trailingLocation),
          in: storage,
          selection: selection
        )
      }
    }
  }

  private func fadeSyntax(_ range: NSRange, in storage: NSTextStorage, selection: NSRange) {
    guard range.location != NSNotFound, range.length > 0 else { return }
    let interactionRange = NSRange(
      location: max(0, selection.location - 1), length: selection.length + 2)
    let isInteracting = NSIntersectionRange(range, interactionRange).length > 0
    storage.addAttributes(
      [
        .foregroundColor: isInteracting ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
      ],
      range: range
    )
  }

  private func enumerate(
    _ pattern: String,
    in source: String,
    using body: (NSTextCheckingResult) -> Void
  ) {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return }
    let range = NSRange(location: 0, length: (source as NSString).length)
    expression.enumerateMatches(in: source, range: range) { match, _, _ in
      if let match { body(match) }
    }
  }
}
