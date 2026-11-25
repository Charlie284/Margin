import Foundation

enum MarkdownTextDecoder {
  struct Decoded {
    var text: String
    var encoding: String.Encoding
    var hasBOM: Bool
  }

  private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
  private static let utf16LittleEndianBOM: [UInt8] = [0xFF, 0xFE]
  private static let utf16BigEndianBOM: [UInt8] = [0xFE, 0xFF]

  static func decode(_ data: Data) throws -> String {
    try decodeDetailed(data).text
  }

  static func decodeDetailed(_ data: Data) throws -> Decoded {
    if data.starts(with: utf8BOM),
      let text = String(data: data.dropFirst(utf8BOM.count), encoding: .utf8)
    {
      return Decoded(text: text, encoding: .utf8, hasBOM: true)
    }
    if data.starts(with: utf16LittleEndianBOM),
      let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
    {
      return Decoded(text: text, encoding: .utf16LittleEndian, hasBOM: true)
    }
    if data.starts(with: utf16BigEndianBOM),
      let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
    {
      return Decoded(text: text, encoding: .utf16BigEndian, hasBOM: true)
    }
    if let encoding = bomlessUTF16Encoding(in: data),
      let text = String(data: data, encoding: encoding)
    {
      return Decoded(text: text, encoding: encoding, hasBOM: false)
    }
    if let text = String(data: data, encoding: .utf8) {
      return Decoded(text: text, encoding: .utf8, hasBOM: false)
    }
    if let text = String(data: data, encoding: .utf16) {
      return Decoded(text: text, encoding: .utf16BigEndian, hasBOM: false)
    }
    throw CocoaError(.fileReadInapplicableStringEncoding)
  }

  static func read(from url: URL) throws -> String {
    try decode(Data(contentsOf: url))
  }

  static func byteOrderMark(for encoding: String.Encoding) -> [UInt8] {
    switch encoding {
    case .utf8: utf8BOM
    case .utf16LittleEndian: utf16LittleEndianBOM
    case .utf16BigEndian: utf16BigEndianBOM
    default: []
    }
  }

  private static func bomlessUTF16Encoding(in data: Data) -> String.Encoding? {
    let sample = min(data.count, 1_024) & ~1
    guard sample >= 4 else { return nil }
    var evenZeros = 0
    var oddZeros = 0
    for offset in 0..<sample {
      guard data[offset] == 0 else { continue }
      if offset % 2 == 0 { evenZeros += 1 } else { oddZeros += 1 }
    }
    let pairs = sample / 2
    if oddZeros > pairs / 4, oddZeros > evenZeros * 4 { return .utf16LittleEndian }
    if evenZeros > pairs / 4, evenZeros > oddZeros * 4 { return .utf16BigEndian }
    return nil
  }
}
