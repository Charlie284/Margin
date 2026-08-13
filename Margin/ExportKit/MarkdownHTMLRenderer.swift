import Foundation
import UniformTypeIdentifiers

struct MarkdownHTMLRenderer {
  func render(
    source: String,
    title fallbackTitle: String = "Markdown Document",
    baseURL: URL? = nil
  ) -> String {
    let document = MarkdownParser().parse(source)
    let title = document.outline.first(where: { $0.level == 1 })?.title ?? fallbackTitle
    var slugCounts: [String: Int] = [:]
    let body = document.blocks.map { block in
      let headingID: String?
      if case .heading(_, let text) = block.kind {
        let baseSlug = headingSlug(text)
        let count = slugCounts[baseSlug, default: 0] + 1
        slugCounts[baseSlug] = count
        headingID = count == 1 ? baseSlug : "\(baseSlug)-\(count)"
      } else {
        headingID = nil
      }
      return renderBlock(block, headingID: headingID, baseURL: baseURL)
    }.joined(separator: "\n")

    return """
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapeHTML(title))</title>
        <style>\(stylesheet)</style>
      </head>
      <body>
        <main class="document">\(body)</main>
      </body>
      </html>
      """
  }

  private func renderBlock(_ block: MarkdownBlock, headingID: String?, baseURL: URL?) -> String {
    switch block.kind {
    case .heading(let level, let text):
      let slug = headingID ?? headingSlug(text)
      return #"<h\#(level) id="\#(slug)">\#(renderInline(text, baseURL: baseURL))</h\#(level)>"#
    case .paragraph(let text):
      return "<p>\(renderInline(text, baseURL: baseURL))</p>"
    case .blockquote(let text):
      return renderBlockquote(text, baseURL: baseURL)
    case .code(let language, let content):
      let languageClass = language.map { #" class="language-\#(escapeAttribute($0))""# } ?? ""
      let label =
        language.map {
          #"<div class="code-label">\#(escapeHTML($0.uppercased()))</div>"#
        } ?? ""
      return
        #"<div class="code-block">\#(label)<pre><code\#(languageClass)>\#(escapeHTML(content))</code></pre></div>"#
    case .unorderedList(let items):
      let contents = items.map { renderListItem($0, baseURL: baseURL) }.joined()
      return "<ul>\(contents)</ul>"
    case .orderedList(let start, let items):
      let startAttribute = start == 1 ? "" : #" start="\#(start)""#
      let contents = items.map { renderListItem($0, baseURL: baseURL) }.joined()
      return "<ol\(startAttribute)>\(contents)</ol>"
    case .table(let table):
      return renderTable(table, baseURL: baseURL)
    case .image(let alt, let path):
      let source = safeResourceURL(path, baseURL: baseURL)
      return
        #"<figure><img src="\#(escapeAttribute(source))" alt="\#(escapeAttribute(alt))"><figcaption>\#(escapeHTML(alt))</figcaption></figure>"#
    case .footnote(let label, let text):
      return
        #"<p class="footnote"><sup>\#(escapeHTML(label))</sup> \#(renderInline(text, baseURL: baseURL))</p>"#
    case .thematicBreak:
      return "<hr>"
    }
  }

  private func renderBlockquote(_ text: String, baseURL: URL?) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }) {
      let nested = lines.map {
        String($0.trimmingCharacters(in: .whitespaces).dropFirst())
          .trimmingCharacters(in: .whitespaces)
      }.joined(separator: "\n")
      return "<blockquote>\(renderBlockquote(nested, baseURL: baseURL))</blockquote>"
    }
    return "<blockquote>\(renderInline(text, baseURL: baseURL))</blockquote>"
  }

  private func renderListItem(_ item: MarkdownListItem, baseURL: URL?) -> String {
    let nested = item.children.map { renderNestedList($0, baseURL: baseURL) }.joined()
    if let checked = item.taskState {
      return
        #"<li class="task \#(checked ? "checked" : "")"><span class="checkbox">\#(checked ? "✓" : "")</span><span>\#(renderInline(item.text, baseURL: baseURL))</span>\#(nested)</li>"#
    }
    return "<li>\(renderInline(item.text, baseURL: baseURL))\(nested)</li>"
  }

  private func renderNestedList(_ list: MarkdownNestedList, baseURL: URL?) -> String {
    switch list {
    case .unordered(let items):
      return "<ul>\(items.map { renderListItem($0, baseURL: baseURL) }.joined())</ul>"
    case .ordered(let start, let items):
      let startAttribute = start == 1 ? "" : #" start="\#(start)""#
      return
        "<ol\(startAttribute)>\(items.map { renderListItem($0, baseURL: baseURL) }.joined())</ol>"
    }
  }

  private func renderTable(_ table: MarkdownTable, baseURL: URL?) -> String {
    let headers = table.headers.enumerated().map { index, header in
      #"<th style="text-align:\#(alignment(table.alignments[index]))">\#(renderInline(header, baseURL: baseURL))</th>"#
    }.joined()
    let rows = table.rows.map { row in
      let cells = row.enumerated().map { index, value in
        #"<td style="text-align:\#(alignment(table.alignments[index]))">\#(renderInline(value, baseURL: baseURL))</td>"#
      }.joined()
      return "<tr>\(cells)</tr>"
    }.joined()
    return
      #"<div class="table-wrap"><table><thead><tr>\#(headers)</tr></thead><tbody>\#(rows)</tbody></table></div>"#
  }

  private func renderInline(_ source: String, baseURL: URL? = nil) -> String {
    var tokens: [String] = []
    var working = source

    working = replacingMatches(in: working, pattern: #"`([^`\n]+)`"#) { match, value in
      guard let range = Range(match.range(at: 1), in: value) else { return "" }
      return token("<code>\(escapeHTML(String(value[range])))</code>", tokens: &tokens)
    }

    working = replacingMarkdownLinks(in: working, baseURL: baseURL, tokens: &tokens)

    working = escapeHTML(working)
    working = replacingTemplate(
      in: working,
      pattern: #"\*\*(.+?)\*\*"#,
      template: "<strong>$1</strong>"
    )
    working = replacingTemplate(
      in: working,
      pattern: #"(?<![\p{L}\p{N}_])__(.+?)__(?![\p{L}\p{N}_])"#,
      template: "<strong>$1</strong>"
    )
    working = replacingTemplate(
      in: working,
      pattern: #"(?<!\*)\*([^*\n]+)\*(?!\*)"#,
      template: "<em>$1</em>"
    )
    working = replacingTemplate(
      in: working,
      pattern: #"(?<![\p{L}\p{N}_])_([^_\n]+)_(?![\p{L}\p{N}_])"#,
      template: "<em>$1</em>"
    )
    working = working.replacingOccurrences(of: "\n", with: "<br>")

    for (index, html) in tokens.enumerated() {
      working = working.replacingOccurrences(of: tokenMarker(index), with: html)
    }
    return working
  }

  private func replacingMarkdownLinks(
    in source: String,
    baseURL: URL?,
    tokens: inout [String]
  ) -> String {
    var output = ""
    var index = source.startIndex

    while index < source.endIndex {
      let isImage =
        source[index] == "!"
        && source.index(after: index) < source.endIndex
        && source[source.index(after: index)] == "["
      let isLink = source[index] == "["
      guard isImage || isLink else {
        output.append(source[index])
        index = source.index(after: index)
        continue
      }

      let labelStart = isImage ? source.index(index, offsetBy: 2) : source.index(after: index)
      guard let labelEnd = source[labelStart...].firstIndex(of: "]"),
        source.index(after: labelEnd) < source.endIndex,
        source[source.index(after: labelEnd)] == "("
      else {
        output.append(source[index])
        index = source.index(after: index)
        continue
      }

      let destinationStart = source.index(labelEnd, offsetBy: 2)
      var cursor = destinationStart
      var depth = 1
      var escaped = false
      var destinationEnd: String.Index?
      while cursor < source.endIndex {
        let character = source[cursor]
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "(" {
          depth += 1
        } else if character == ")" {
          depth -= 1
          if depth == 0 {
            destinationEnd = cursor
            break
          }
        }
        cursor = source.index(after: cursor)
      }

      guard let destinationEnd else {
        output.append(source[index])
        index = source.index(after: index)
        continue
      }

      let label = String(source[labelStart..<labelEnd])
      let destination = markdownDestination(
        String(source[destinationStart..<destinationEnd])
      )
      let html: String
      if isImage {
        let resource = safeResourceURL(destination, baseURL: baseURL)
        html =
          #"<img class="inline-image" src="\#(escapeAttribute(resource))" alt="\#(escapeAttribute(label))">"#
      } else {
        let url = safeLinkURL(destination)
        html = #"<a href="\#(escapeAttribute(url))">\#(escapeHTML(label))</a>"#
      }
      output += token(html, tokens: &tokens)
      index = source.index(after: destinationEnd)
    }
    return output
  }

  private func markdownDestination(_ rawValue: String) -> String {
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("<"), let closing = value.firstIndex(of: ">") {
      return String(value[value.index(after: value.startIndex)..<closing])
    }
    return value
  }

  private func token(_ html: String, tokens: inout [String]) -> String {
    let marker = tokenMarker(tokens.count)
    tokens.append(html)
    return marker
  }

  private func tokenMarker(_ index: Int) -> String {
    "\u{E000}MARGIN\(index)\u{E001}"
  }

  private func replacingMatches(
    in source: String,
    pattern: String,
    transform: (NSTextCheckingResult, String) -> String
  ) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
    let result = NSMutableString(string: source)
    let range = NSRange(location: 0, length: (source as NSString).length)
    for match in expression.matches(in: source, range: range).reversed() {
      result.replaceCharacters(in: match.range, with: transform(match, source))
    }
    return result as String
  }

  private func replacingTemplate(in source: String, pattern: String, template: String) -> String {
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return source }
    let range = NSRange(location: 0, length: (source as NSString).length)
    return expression.stringByReplacingMatches(in: source, range: range, withTemplate: template)
  }

  private func safeLinkURL(_ value: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "#" }
    guard let scheme = URLComponents(string: trimmed)?.scheme?.lowercased() else { return trimmed }
    return ["file", "http", "https", "mailto"].contains(scheme) ? trimmed : "#"
  }

  private func safeResourceURL(_ value: String, baseURL: URL?) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "#" }
    let decoded = trimmed.removingPercentEncoding ?? trimmed
    let resourceURL: URL
    if let scheme = URLComponents(string: trimmed)?.scheme?.lowercased() {
      guard scheme == "file", let url = URL(string: trimmed) else { return "#" }
      resourceURL = url.standardizedFileURL
    } else {
      guard let baseURL else { return trimmed }
      resourceURL = URL(fileURLWithPath: decoded, relativeTo: baseURL).standardizedFileURL
      let root = baseURL.standardizedFileURL.path
      let rootPrefix = root.hasSuffix("/") ? root : root + "/"
      guard resourceURL.path == root || resourceURL.path.hasPrefix(rootPrefix) else { return "#" }
    }

    guard let values = try? resourceURL.resourceValues(forKeys: [.fileSizeKey]),
      (values.fileSize ?? 0) <= 10_000_000,
      let data = try? Data(contentsOf: resourceURL),
      let mimeType = UTType(filenameExtension: resourceURL.pathExtension)?.preferredMIMEType
    else { return "#" }
    return "data:\(mimeType);base64,\(data.base64EncodedString())"
  }

  private func headingSlug(_ value: String) -> String {
    let allowed = value.lowercased().unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(String(scalar)) : "-"
    }
    let slug = String(allowed)
      .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return slug.isEmpty ? "section" : slug
  }

  private func alignment(_ value: MarkdownTableAlignment) -> String {
    switch value {
    case .leading: "left"
    case .center: "center"
    case .trailing: "right"
    }
  }

  private func escapeHTML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }

  private func escapeAttribute(_ value: String) -> String {
    escapeHTML(value).replacingOccurrences(of: "'", with: "&#39;")
  }

  private var stylesheet: String {
    return """
      @page { size: Letter; margin: 0.7in 0.75in 0.75in; }
      :root { color-scheme: light; --ink: #202124; --muted: #687078; --accent: #1769aa; --line: rgba(30,35,40,.14); --soft: rgba(30,35,40,.045); }
      * { box-sizing: border-box; }
      html { background: #ffffff; }
      body { margin: 0; background: #ffffff; color: var(--ink); font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif; font-size: 17px; line-height: 1.62; -webkit-font-smoothing: antialiased; }
      .document { margin: 0; padding: 56px 32px 72px; }
      h1,h2,h3,h4,h5,h6 { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; line-height: 1.18; letter-spacing: -.018em; break-after: avoid; }
      h1 { font-size: 2.28rem; margin: 0 0 1.15rem; }
      h2 { font-size: 1.78rem; margin: 2.15rem 0 .85rem; }
      h3 { font-size: 1.4rem; margin: 1.75rem 0 .7rem; }
      h4 { font-size: 1.16rem; margin: 1.45rem 0 .6rem; }
      h5,h6 { font-size: 1rem; margin: 1.3rem 0 .5rem; }
      p { margin: 0 0 1rem; orphans: 3; widows: 3; }
      a { color: var(--accent); text-decoration-thickness: .07em; text-underline-offset: .16em; }
      strong { font-weight: 650; }
      blockquote { margin: 1.4rem 0 1.55rem; padding: .15rem 0 .15rem 1.15rem; border-left: 3px solid color-mix(in srgb, var(--accent) 65%, transparent); color: var(--muted); font-style: italic; }
      ul,ol { margin: .4rem 0 1.2rem; padding-left: 1.55rem; }
      li { margin: .28rem 0; padding-left: .12rem; }
      li.task { display: flex; gap: .62rem; margin-left: -1.45rem; list-style: none; }
      li.task.checked span:last-child { color: var(--muted); text-decoration: line-through; }
      .checkbox { display: inline-grid; place-items: center; width: 1.02rem; height: 1.02rem; margin-top: .31rem; border: 1.3px solid #8a9198; border-radius: 3px; color: white; font-size: .72rem; line-height: 1; }
      .task.checked .checkbox { border-color: var(--accent); background: var(--accent); }
      code { padding: .12em .3em; border-radius: 4px; background: var(--soft); font-family: "SF Mono", ui-monospace, monospace; font-size: .86em; }
      .code-block { margin: 1.35rem 0 1.55rem; border: 1px solid var(--line); border-radius: 8px; background: var(--soft); overflow: hidden; break-inside: avoid; }
      .code-label { height: 32px; padding: 8px 14px; border-bottom: 1px solid var(--line); color: var(--muted); font: 600 10px/16px -apple-system, sans-serif; letter-spacing: .08em; }
      pre { margin: 0; padding: 15px; overflow: auto; white-space: pre-wrap; }
      pre code { padding: 0; background: transparent; font-size: 13px; line-height: 1.5; }
      .table-wrap { margin: 1.35rem 0 1.6rem; overflow-x: auto; }
      table { width: 100%; border-collapse: separate; border-spacing: 0; border: 1px solid var(--line); border-radius: 7px; overflow: hidden; font-size: .92em; }
      th,td { padding: 9px 12px; border-bottom: 1px solid var(--line); }
      th { background: var(--soft); font-weight: 650; }
      tr:last-child td { border-bottom: 0; }
      figure { margin: 1.6rem 0; text-align: center; }
      img { display: block; max-width: 100%; height: auto; margin: 0 auto; border-radius: 5px; }
      .inline-image { display: inline; max-height: 1.25em; vertical-align: text-bottom; }
      figcaption { margin-top: .55rem; color: var(--muted); font-size: .8em; }
      hr { margin: 2rem 0; border: 0; border-top: 1px solid var(--line); }
      .footnote { color: var(--muted); font-size: .82em; }
      .footnote sup { color: var(--accent); font-weight: 650; }
      @media print { body { font-size: 11.5pt; } .document { width: 100%; padding: 0; } a { color: inherit; } }
      @media (prefers-color-scheme: dark) and (not print) { html,body { background: #1c1c1e; color: #f1f1f2; } :root { --ink: #f1f1f2; --muted: #a8abb0; --line: rgba(255,255,255,.14); --soft: rgba(255,255,255,.055); } }
      """
  }
}
