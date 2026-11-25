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
  var encoding: String.Encoding
  var hasBOM: Bool

  init(text: String = "") {
    self.text = text
    self.encoding = .utf8
    self.hasBOM = false
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }

    let decoded = try MarkdownTextDecoder.decodeDetailed(data)
    text = decoded.text
    encoding = decoded.encoding
    hasBOM = decoded.hasBOM
  }

  func fileData() throws -> Data {
    guard var data = text.data(using: encoding) else {
      throw CocoaError(.fileWriteInapplicableStringEncoding)
    }
    if hasBOM {
      data.insert(contentsOf: MarkdownTextDecoder.byteOrderMark(for: encoding), at: 0)
    }
    return data
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: try fileData())
  }
}
