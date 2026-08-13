import AppKit
import SwiftUI

struct MarkdownReader: View {
  let document: ParsedMarkdownDocument
  @Binding var source: String
  let baseURL: URL?
  let requestedScrollID: String?
  let isEditable: Bool

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        if document.blocks.isEmpty {
          emptyState
        } else {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(document.blocks) { block in
              blockView(block)
                .id(block.id)
            }
          }
          .padding(.horizontal, 56)
          .padding(.vertical, 54)
          .frame(maxWidth: .infinity, alignment: .topLeading)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Color(nsColor: .textBackgroundColor))
      .textSelection(.enabled)
      .onChange(of: requestedScrollID) { _, identifier in
        guard let identifier else { return }
        withAnimation(.easeOut(duration: 0.22)) {
          proxy.scrollTo(identifier, anchor: .top)
        }
      }
    }
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Nothing to Read Yet", systemImage: "doc.text")
    } description: {
      Text("Switch to Write and start with a heading or a sentence.")
    }
    .frame(maxWidth: .infinity, minHeight: 420)
    .foregroundStyle(.secondary)
  }

  @ViewBuilder
  private func blockView(_ block: MarkdownBlock) -> some View {
    switch block.kind {
    case .heading(let level, let text):
      heading(text, level: level)
    case .paragraph(let text):
      InlineMarkdownText(source: text, font: bodyFont, accent: .accentColor, baseURL: baseURL)
        .lineSpacing(6)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 18)
    case .blockquote(let text):
      blockquote(text)
    case .code(let language, let content):
      codeBlock(content, language: language)
    case .unorderedList(let items):
      unorderedList(items)
    case .orderedList(let start, let items):
      orderedList(items, start: start)
    case .table(let table):
      tableView(table)
    case .image(let alt, let path):
      MarkdownImageView(alt: alt, path: path, baseURL: baseURL)
        .padding(.vertical, 12)
    case .footnote(let label, let text):
      footnote(label: label, text: text)
    case .thematicBreak:
      Divider()
        .overlay(Color.secondary.opacity(0.25))
        .padding(.vertical, 26)
    }
  }

  private func heading(_ text: String, level: Int) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      InlineMarkdownText(
        source: text,
        font: headingFont(level: level),
        accent: .accentColor,
        baseURL: baseURL
      )
      .accessibilityAddTraits(.isHeader)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.top, level <= 2 ? 22 : 14)
    .padding(.bottom, level <= 2 ? 13 : 9)
  }

  private func blockquote(_ text: String) -> some View {
    RecursiveBlockquoteView(text: text, baseURL: baseURL)
      .padding(.vertical, 9)
      .padding(.bottom, 12)
  }

  private func codeBlock(_ content: String, language: String?) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Text(language?.uppercased() ?? "CODE")
          .font(.system(size: 10, weight: .semibold, design: .rounded))
          .tracking(0.8)
          .foregroundStyle(.secondary)

        Spacer()

        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(content, forType: .string)
        } label: {
          Label("Copy", systemImage: "doc.on.doc")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .help("Copy code")
        .accessibilityLabel("Copy code")
      }
      .padding(.horizontal, 14)
      .frame(height: 34)
      .background(Color.primary.opacity(0.035))

      Divider().opacity(0.55)

      ScrollView(.horizontal) {
        Text(CodeSyntaxHighlighter.highlight(content, language: language))
          .font(.system(size: 13.5, design: .monospaced))
          .lineSpacing(3)
          .textSelection(.enabled)
          .padding(15)
      }
    }
    .background(Color.primary.opacity(0.045))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(Color.primary.opacity(0.075), lineWidth: 1)
    }
    .padding(.vertical, 10)
    .padding(.bottom, 10)
  }

  private func unorderedList(_ items: [MarkdownListItem]) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(items) { item in
        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .firstTextBaseline, spacing: 11) {
            listMarker(for: item)
            InlineMarkdownText(
              source: item.text,
              font: bodyFont,
              color: item.taskState == true ? .secondary : .primary,
              accent: .accentColor,
              baseURL: baseURL
            )
            .strikethrough(item.taskState == true, color: .secondary)
            .fixedSize(horizontal: false, vertical: true)
          }
          if !item.children.isEmpty {
            NestedMarkdownLists(
              lists: item.children,
              source: $source,
              baseURL: baseURL,
              isEditable: isEditable
            )
            .padding(.leading, 28)
          }
        }
      }
    }
    .padding(.bottom, 18)
  }

  private func orderedList(_ items: [MarkdownListItem], start: Int) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
        VStack(alignment: .leading, spacing: 7) {
          HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(start + offset).")
              .font(bodyFont.monospacedDigit())
              .foregroundStyle(.secondary)
              .frame(minWidth: 24, alignment: .trailing)

            InlineMarkdownText(
              source: item.text,
              font: bodyFont,
              accent: .accentColor,
              baseURL: baseURL
            )
            .fixedSize(horizontal: false, vertical: true)
          }
          if !item.children.isEmpty {
            NestedMarkdownLists(
              lists: item.children,
              source: $source,
              baseURL: baseURL,
              isEditable: isEditable
            )
            .padding(.leading, 35)
          }
        }
      }
    }
    .padding(.bottom, 18)
  }

  private func tableView(_ table: MarkdownTable) -> some View {
    ScrollView(.horizontal) {
      Grid(horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          ForEach(Array(table.headers.enumerated()), id: \.offset) { index, header in
            tableCell(header, alignment: alignment(for: table.alignments[index]), isHeader: true)
          }
        }

        Divider().gridCellColumns(table.headers.count)

        ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
          GridRow {
            ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
              tableCell(cell, alignment: alignment(for: table.alignments[index]), isHeader: false)
            }
          }
          Divider().gridCellColumns(table.headers.count).opacity(0.55)
        }
      }
      .background(Color.primary.opacity(0.02))
      .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      }
    }
    .padding(.vertical, 10)
    .padding(.bottom, 10)
  }

  private func tableCell(_ source: String, alignment: Alignment, isHeader: Bool) -> some View {
    InlineMarkdownText(
      source: source,
      font: bodyFont.weight(isHeader ? .semibold : .regular),
      accent: .accentColor,
      baseURL: baseURL
    )
    .lineLimit(nil)
    .frame(minWidth: 112, maxWidth: 240, alignment: alignment)
    .padding(.horizontal, 13)
    .padding(.vertical, 10)
    .background(isHeader ? Color.primary.opacity(0.045) : Color.clear)
  }

  private func alignment(for alignment: MarkdownTableAlignment) -> Alignment {
    switch alignment {
    case .leading: .leading
    case .center: .center
    case .trailing: .trailing
    }
  }

  private func footnote(label: String, text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .font(.caption.monospacedDigit().weight(.semibold))
        .foregroundStyle(Color.accentColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))

      InlineMarkdownText(
        source: text,
        font: .footnote,
        color: .secondary,
        accent: .accentColor,
        baseURL: baseURL
      )
    }
    .padding(.top, 7)
  }

  private func toggleTask(_ item: MarkdownListItem) {
    guard let range = item.checkboxRange else { return }
    let mutable = NSMutableString(string: source)
    guard NSMaxRange(range) <= mutable.length else { return }
    mutable.replaceCharacters(in: range, with: item.taskState == true ? " " : "x")
    source = mutable as String
  }

  @ViewBuilder
  private func listMarker(for item: MarkdownListItem) -> some View {
    if let checked = item.taskState {
      Button {
        toggleTask(item)
      } label: {
        Image(systemName: checked ? "checkmark.square.fill" : "square")
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(checked ? Color.accentColor : .secondary)
      }
      .buttonStyle(.plain)
      .disabled(!isEditable)
      .accessibilityLabel(checked ? "Mark task incomplete" : "Mark task complete")
    } else {
      Circle()
        .fill(Color.primary.opacity(0.68))
        .frame(width: 5, height: 5)
        .padding(.leading, 6)
        .frame(width: 17)
    }
  }

  private var bodyFont: Font {
    .system(size: 17, design: .default)
  }

  private func headingFont(level: Int) -> Font {
    let sizes: [CGFloat] = [38, 30, 24, 20, 17, 15]
    let index = min(max(level - 1, 0), sizes.count - 1)
    return .system(size: sizes[index], weight: level < 3 ? .bold : .semibold)
  }
}

private struct RecursiveBlockquoteView: View {
  let text: String
  let baseURL: URL?

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      RoundedRectangle(cornerRadius: 1)
        .fill(Color.accentColor.opacity(0.58))
        .frame(width: 3)

      if let nestedText {
        RecursiveBlockquoteView(text: nestedText, baseURL: baseURL)
      } else {
        InlineMarkdownText(
          source: text,
          font: .system(size: 17).italic(),
          color: .secondary,
          accent: .accentColor,
          baseURL: baseURL
        )
        .lineSpacing(6)
        .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private var nestedText: String? {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") })
    else { return nil }
    return lines.map {
      String($0.trimmingCharacters(in: .whitespaces).dropFirst())
        .trimmingCharacters(in: .whitespaces)
    }.joined(separator: "\n")
  }
}

private struct NestedMarkdownLists: View {
  let lists: [MarkdownNestedList]
  @Binding var source: String
  let baseURL: URL?
  let isEditable: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(Array(lists.enumerated()), id: \.offset) { _, list in
        switch list {
        case .unordered(let items):
          ForEach(items) { item in
            nestedItem(item, marker: "•")
          }
        case .ordered(let start, let items):
          ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
            nestedItem(item, marker: "\(start + offset).")
          }
        }
      }
    }
  }

  private func nestedItem(_ item: MarkdownListItem, marker: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 9) {
        if let checked = item.taskState {
          Button {
            toggleTask(item)
          } label: {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
          }
          .buttonStyle(.plain)
          .disabled(!isEditable)
        } else {
          Text(marker).foregroundStyle(.secondary).frame(minWidth: 18, alignment: .trailing)
        }
        InlineMarkdownText(
          source: item.text,
          font: .system(size: 17),
          accent: .accentColor,
          baseURL: baseURL
        )
      }
      if !item.children.isEmpty {
        NestedMarkdownLists(
          lists: item.children,
          source: $source,
          baseURL: baseURL,
          isEditable: isEditable
        )
        .padding(.leading, 27)
      }
    }
  }

  private func toggleTask(_ item: MarkdownListItem) {
    guard let range = item.checkboxRange else { return }
    let mutable = NSMutableString(string: source)
    guard NSMaxRange(range) <= mutable.length else { return }
    mutable.replaceCharacters(in: range, with: item.taskState == true ? " " : "x")
    source = mutable as String
  }
}
