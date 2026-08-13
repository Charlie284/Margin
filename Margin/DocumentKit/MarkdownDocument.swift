import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  static let marginMarkdown = UTType(
    importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
  static let readableContentTypes: [UTType] = [.marginMarkdown]
  static let writableContentTypes: [UTType] = [.marginMarkdown]

  var text: String

  init(text: String = "") {
    self.text = text
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }

    text = try MarkdownTextDecoder.decode(data)
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    guard let data = text.data(using: .utf8) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    return FileWrapper(regularFileWithContents: data)
  }
}
