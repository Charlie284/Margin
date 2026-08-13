import Foundation

enum MarkdownTextDecoder {
  static func decode(_ data: Data) throws -> String {
    if let value = String(data: data, encoding: .utf8) { return value }
    if let value = String(data: data, encoding: .utf16) { return value }
    throw CocoaError(.fileReadInapplicableStringEncoding)
  }

  static func read(from url: URL) throws -> String {
    try decode(Data(contentsOf: url))
  }
}
