import AppKit
import SwiftUI

struct MarkdownEditor: NSViewRepresentable {
  @Binding var text: String
  var isEditable: Bool = true
  var baseURL: URL?

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text, baseURL: baseURL)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let contentStorage = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    contentStorage.addTextLayoutManager(layoutManager)

    let textContainer = NSTextContainer(
      size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    textContainer.widthTracksTextView = true
    layoutManager.textContainer = textContainer

    let textView = MarginTextView(frame: .zero, textContainer: textContainer)
    textView.delegate = context.coordinator
    textView.isEditable = isEditable
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = true
    textView.isGrammarCheckingEnabled = true
    textView.smartInsertDeleteEnabled = false
    textView.textContainerInset = NSSize(width: 4, height: 48)
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [NSView.AutoresizingMask.width]
    textView.drawsBackground = false
    textView.setAccessibilityLabel("Markdown editor")
    textView.string = text

    let scrollView = MarginEditorScrollView()
    scrollView.contentStorage = contentStorage
    scrollView.textLayoutManager = layoutManager
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.scrollerStyle = .overlay
    scrollView.contentView.postsBoundsChangedNotifications = true

    context.coordinator.textView = textView
    context.coordinator.highlight()
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? MarginTextView else { return }
    textView.isEditable = isEditable
    context.coordinator.highlighter.baseURL = baseURL

    if textView.string != text {
      let selectedRange = textView.selectedRange()
      context.coordinator.isApplyingExternalValue = true
      textView.string = text
      textView.setSelectedRange(
        clampedSelection(selectedRange, textLength: (text as NSString).length)
      )
      context.coordinator.isApplyingExternalValue = false
      context.coordinator.highlight(immediately: true)
    }
  }

  private func clampedSelection(_ selection: NSRange, textLength: Int) -> NSRange {
    let location = min(selection.location, textLength)
    let availableLength = max(0, textLength - location)
    return NSRange(location: location, length: min(selection.length, availableLength))
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding private var text: String
    weak var textView: MarginTextView?
    var isApplyingExternalValue = false
    let highlighter: MarkdownSyntaxHighlighter
    private var pendingHighlight: DispatchWorkItem?

    init(text: Binding<String>, baseURL: URL?) {
      _text = text
      highlighter = MarkdownSyntaxHighlighter(baseURL: baseURL)
    }

    func textDidChange(_ notification: Notification) {
      guard !isApplyingExternalValue, let textView else { return }
      text = textView.string
      highlight()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      highlight()
    }

    func highlight(immediately: Bool = false) {
      guard let textView, let textStorage = textView.textStorage else { return }
      pendingHighlight?.cancel()
      let work = DispatchWorkItem { [weak self, weak textView, weak textStorage] in
        guard let self, let textView, let textStorage else { return }
        self.highlighter.apply(to: textStorage, selection: textView.selectedRange())
        textView.typingAttributes = self.highlighter.baseAttributes
      }
      pendingHighlight = work

      if immediately {
        work.perform()
      } else {
        let delay = textStorage.length > 50_000 ? 0.09 : 0.025
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
      }
    }
  }
}

private final class MarginEditorScrollView: NSScrollView {
  var contentStorage: NSTextContentStorage?
  var textLayoutManager: NSTextLayoutManager?
}

final class MarginTextView: NSTextView {
  override func insertNewline(_ sender: Any?) {
    let source = string as NSString
    let selection = selectedRange()
    let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
    let line = source.substring(with: lineRange)

    if let continuation = listContinuation(for: line) {
      if continuation.contentIsEmpty {
        applyReplacement(
          in: NSRange(location: lineRange.location, length: continuation.prefixLength),
          with: ""
        )
        super.insertNewline(sender)
      } else {
        insertText("\n\(continuation.nextPrefix)", replacementRange: selectedRange())
      }
      return
    }

    super.insertNewline(sender)
  }

  @objc func marginToggleBold(_ sender: Any?) {
    wrapSelection(prefix: "**", suffix: "**", placeholder: "bold text")
  }

  @objc func marginToggleItalic(_ sender: Any?) {
    wrapSelection(prefix: "_", suffix: "_", placeholder: "italic text")
  }

  @objc func marginToggleInlineCode(_ sender: Any?) {
    wrapSelection(prefix: "`", suffix: "`", placeholder: "code")
  }

  @objc func marginInsertLink(_ sender: Any?) {
    let selection = selectedRange()
    let selectedText =
      selection.length > 0 ? (string as NSString).substring(with: selection) : "link text"
    let replacement = "[\(selectedText)](https://)"

    guard shouldChangeText(in: selection, replacementString: replacement) else { return }
    textStorage?.replaceCharacters(in: selection, with: replacement)
    didChangeText()

    let urlStart = selection.location + (selectedText as NSString).length + 3
    setSelectedRange(NSRange(location: urlStart, length: ("https://" as NSString).length))
  }

  @objc func marginInsertMarkdown(_ sender: Any?) {
    guard let markdown = sender as? String else { return }
    insertText(markdown, replacementRange: selectedRange())
  }

  private func wrapSelection(prefix: String, suffix: String, placeholder: String) {
    let selection = selectedRange()
    let source = string as NSString
    let selectedText = selection.length > 0 ? source.substring(with: selection) : placeholder
    let replacement = prefix + selectedText + suffix

    guard shouldChangeText(in: selection, replacementString: replacement) else { return }
    textStorage?.replaceCharacters(in: selection, with: replacement)
    didChangeText()
    setSelectedRange(
      NSRange(
        location: selection.location + (prefix as NSString).length,
        length: (selectedText as NSString).length
      )
    )
  }

  private func applyReplacement(in range: NSRange, with replacement: String) {
    guard shouldChangeText(in: range, replacementString: replacement) else { return }
    textStorage?.replaceCharacters(in: range, with: replacement)
    didChangeText()
  }

  private func listContinuation(for line: String) -> (
    nextPrefix: String, prefixLength: Int, contentIsEmpty: Bool
  )? {
    let patterns = [
      #"^(\s*[-+*]\s+(?:\[[ xX]\]\s+)?)(.*?)(?:\r?\n)?$"#,
      #"^(\s*)(\d+)([.)]\s+)(.*?)(?:\r?\n)?$"#,
    ]

    if let expression = try? NSRegularExpression(pattern: patterns[0]),
      let match = expression.firstMatch(
        in: line,
        range: NSRange(location: 0, length: (line as NSString).length)
      ),
      let prefixRange = Range(match.range(at: 1), in: line),
      let contentRange = Range(match.range(at: 2), in: line)
    {
      var prefix = String(line[prefixRange])
      prefix = prefix.replacingOccurrences(of: "[x]", with: "[ ]", options: .caseInsensitive)
      return (
        prefix, match.range(at: 1).length,
        line[contentRange].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
    }

    if let expression = try? NSRegularExpression(pattern: patterns[1]),
      let match = expression.firstMatch(
        in: line,
        range: NSRange(location: 0, length: (line as NSString).length)
      ),
      let indentationRange = Range(match.range(at: 1), in: line),
      let numberRange = Range(match.range(at: 2), in: line),
      let delimiterRange = Range(match.range(at: 3), in: line),
      let contentRange = Range(match.range(at: 4), in: line)
    {
      let nextNumber = (Int(line[numberRange]) ?? 0) + 1
      let nextPrefix = "\(line[indentationRange])\(nextNumber)\(line[delimiterRange])"
      let prefixLength = match.range(at: 4).location
      return (
        nextPrefix, prefixLength,
        line[contentRange].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      )
    }

    return nil
  }
}
