import Cocoa
import Quartz
import WebKit

final class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
  private var preparationHandler: ((Error?) -> Void)?
  private var preparationTimeoutTask: Task<Void, Never>?
  private var previewDirectoryURL: URL?

  private lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = self
    webView.setValue(false, forKey: "drawsBackground")
    return webView
  }()

  override func loadView() {
    view = webView
  }

  func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
    if preparationHandler != nil {
      finishPreparation(CocoaError(.userCancelled))
    }
    webView.stopLoading()

    do {
      let source = try readMarkdown(at: url)
      let html = MarkdownHTMLRenderer().render(
        source: source,
        title: url.deletingPathExtension().lastPathComponent,
        baseURL: url.deletingLastPathComponent()
      )
      previewDirectoryURL = url.deletingLastPathComponent().standardizedFileURL
      preparationHandler = handler
      preparationTimeoutTask = Task { @MainActor [weak self] in
        do {
          try await Task.sleep(for: .seconds(15))
        } catch {
          return
        }
        self?.finishPreparation(
          NSError(
            domain: "com.marginapp.Margin.QuickLook",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The preview took too long to render."]
          )
        )
      }
      webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    } catch {
      handler(error)
    }
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finishPreparation()
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    finishPreparation(error)
  }

  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finishPreparation(
      NSError(
        domain: WKError.errorDomain,
        code: WKError.webContentProcessTerminated.rawValue,
        userInfo: [NSLocalizedDescriptionKey: "The preview renderer stopped unexpectedly."]
      )
    )
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    finishPreparation(error)
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard navigationAction.navigationType == .linkActivated,
      let url = navigationAction.request.url
    else {
      decisionHandler(.allow)
      return
    }

    if shouldOpenExternally(url) {
      NSWorkspace.shared.open(url)
    }
    decisionHandler(.cancel)
  }

  private func readMarkdown(at url: URL) throws -> String {
    try MarkdownTextDecoder.read(from: url)
  }

  private func finishPreparation(_ error: Error? = nil) {
    preparationTimeoutTask?.cancel()
    preparationTimeoutTask = nil
    preparationHandler?(error)
    preparationHandler = nil
  }

  private func shouldOpenExternally(_ url: URL) -> Bool {
    if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
      return true
    }
    guard url.isFileURL, let previewDirectoryURL else { return false }
    let directoryPath =
      previewDirectoryURL.path.hasSuffix("/")
      ? previewDirectoryURL.path
      : previewDirectoryURL.path + "/"
    let path = url.standardizedFileURL.path
    return path == previewDirectoryURL.path || path.hasPrefix(directoryPath)
  }
}
