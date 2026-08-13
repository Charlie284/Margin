import SwiftUI

struct InlineMarkdownText: View {
  let source: String
  var font: Font
  var color: Color = .primary
  var accent: Color = .accentColor
  var baseURL: URL?

  var body: some View {
    Text(attributedSource)
      .font(font)
      .foregroundStyle(color)
      .tint(accent)
  }

  private var attributedSource: AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace,
      failurePolicy: .returnPartiallyParsedIfPossible
    )

    return (try? AttributedString(markdown: source, options: options, baseURL: baseURL))
      ?? AttributedString(source)
  }
}
