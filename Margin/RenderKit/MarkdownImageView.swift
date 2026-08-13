import AppKit
import ImageIO
import SwiftUI

struct MarkdownImageView: View {
  let alt: String
  let path: String
  let baseURL: URL?
  @State private var image: NSImage?
  @State private var loadFailed = false

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .accessibilityLabel(alt.isEmpty ? "Document image" : alt)
      } else if loadFailed {
        ContentUnavailableView {
          Label(alt.isEmpty ? "Image Unavailable" : alt, systemImage: "photo")
        } description: {
          Text(path)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 150)
      }
    }
    .task(id: imageURL) { await loadImage() }
  }

  private var imageURL: URL? {
    guard let baseURL else { return nil }
    let decodedPath = path.removingPercentEncoding ?? path
    return URL(fileURLWithPath: decodedPath, relativeTo: baseURL).standardizedFileURL
  }

  private func loadImage() async {
    image = nil
    loadFailed = false
    guard let imageURL else {
      loadFailed = true
      return
    }
    let loaded = await Task.detached(priority: .utility) { () -> NSImage? in
      guard let values = try? imageURL.resourceValues(forKeys: [.fileSizeKey]),
        (values.fileSize ?? 0) <= 25_000_000,
        let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil)
      else { return nil }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: 4_096,
        kCGImageSourceCreateThumbnailWithTransform: true,
      ]
      guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      else { return nil }
      return NSImage(cgImage: image, size: .zero)
    }.value
    guard !Task.isCancelled else { return }
    image = loaded
    loadFailed = loaded == nil
  }
}
