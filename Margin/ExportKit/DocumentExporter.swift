import AppKit
import WebKit

enum DocumentExportFormat: Equatable {
  case html
  case pdf
}

enum DocumentExportError: LocalizedError {
  case webContentProcessTerminated
  case webContentLoadTimedOut

  var errorDescription: String? {
    switch self {
    case .webContentProcessTerminated:
      "The PDF renderer stopped unexpectedly. Try exporting again."
    case .webContentLoadTimedOut:
      "The document took too long to prepare for PDF export."
    }
  }
}

@MainActor
enum DocumentExporter {
  static func writeHTML(_ html: String, to destinationURL: URL) throws {
    try html.write(to: destinationURL, atomically: true, encoding: .utf8)
  }

  static func copyHTML(_ html: String, plainText: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(html, forType: .html)
    pasteboard.setString(plainText, forType: .string)
  }

  static func writePDF(_ html: String, baseURL: URL?, to destinationURL: URL) async throws {
    let renderer = WebPDFRenderer()
    try await renderer.render(html: html, baseURL: baseURL, destinationURL: destinationURL)
  }
}

@MainActor
private final class WebPDFRenderer: NSObject, WKNavigationDelegate {
  private var loadContinuation: CheckedContinuation<Void, Error>?
  private var loadTimeoutTask: Task<Void, Never>?
  private var webView: WKWebView?

  func render(html: String, baseURL: URL?, destinationURL: URL) async throws {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let webView = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 816, height: 1_056), configuration: configuration)
    webView.navigationDelegate = self
    self.webView = webView
    defer { cleanUp() }

    try await waitUntilLoaded(html: html, baseURL: baseURL, in: webView)

    webView.layoutSubtreeIfNeeded()
    let measuredHeight = try await webView.evaluateJavaScript(
      "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)"
    )
    let contentHeight = (measuredHeight as? NSNumber)?.doubleValue ?? 1_056
    let pdfConfiguration = WKPDFConfiguration()
    pdfConfiguration.rect = CGRect(
      x: 0,
      y: 0,
      width: webView.bounds.width,
      height: max(contentHeight, webView.bounds.height)
    )
    let data = try await webView.pdf(configuration: pdfConfiguration)
    try data.write(to: destinationURL, options: Data.WritingOptions.atomic)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    completeLoad(.success(()))
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    completeLoad(.failure(error))
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    completeLoad(.failure(error))
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    completeLoad(.failure(DocumentExportError.webContentProcessTerminated))
  }

  private func waitUntilLoaded(html: String, baseURL: URL?, in webView: WKWebView) async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        loadContinuation = continuation
        loadTimeoutTask = Task { @MainActor [weak self] in
          do {
            try await Task.sleep(for: .seconds(15))
          } catch {
            return
          }
          self?.completeLoad(.failure(DocumentExportError.webContentLoadTimedOut))
        }
        webView.loadHTMLString(html, baseURL: baseURL)
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        self?.completeLoad(.failure(CancellationError()))
      }
    }
  }

  private func completeLoad(_ result: Result<Void, Error>) {
    guard let continuation = loadContinuation else { return }
    loadContinuation = nil
    loadTimeoutTask?.cancel()
    loadTimeoutTask = nil
    continuation.resume(with: result)
  }

  private func cleanUp() {
    loadTimeoutTask?.cancel()
    loadTimeoutTask = nil
    if let continuation = loadContinuation {
      loadContinuation = nil
      continuation.resume(throwing: CancellationError())
    }
    webView?.stopLoading()
    webView?.navigationDelegate = nil
    webView = nil
  }
}
