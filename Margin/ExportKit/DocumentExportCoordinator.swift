import AppKit
import UniformTypeIdentifiers

@MainActor
enum DocumentExportCoordinator {
  static func present(
    format: DocumentExportFormat,
    fileURL: URL?,
    html: String,
    onError: @escaping (String) -> Void
  ) {
    let panel = NSSavePanel()
    panel.title = format == .pdf ? "Export PDF" : "Export HTML"
    panel.prompt = "Export"
    panel.canCreateDirectories = true
    panel.allowedContentTypes = [format == .pdf ? .pdf : .html]
    let stem = fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    panel.nameFieldStringValue = "\(stem).\(format == .pdf ? "pdf" : "html")"
    panel.directoryURL = fileURL?.deletingLastPathComponent()

    panel.begin { response in
      guard response == .OK, let destinationURL = panel.url else { return }

      Task {
        do {
          switch format {
          case .html:
            try DocumentExporter.writeHTML(html, to: destinationURL)
          case .pdf:
            try await DocumentExporter.writePDF(
              html,
              baseURL: fileURL?.deletingLastPathComponent(),
              to: destinationURL
            )
          }
        } catch {
          onError(error.localizedDescription)
        }
      }
    }
  }
}
