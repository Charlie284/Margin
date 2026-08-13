import Foundation

struct WorkspaceAccessRequest: Equatable {
  let url: URL
  let bookmarkData: Data?
}

struct WorkspaceNavigationRequest: Equatable {
  let url: URL
  let line: Int
}

enum MarginURLRoute: Equatable {
  case read(URL)
  case workspace(WorkspaceAccessRequest)

  init?(url: URL) {
    guard url.scheme == "margin",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      let path = components.queryItems?.first(where: { $0.name == "path" })?.value
    else { return nil }

    let fileURL = URL(fileURLWithPath: path).standardizedFileURL
    switch components.host {
    case "read": self = .read(fileURL)
    case "workspace":
      let encodedBookmark = components.queryItems?.first(where: { $0.name == "bookmark" })?.value
      self = .workspace(
        WorkspaceAccessRequest(
          url: fileURL,
          bookmarkData: encodedBookmark.flatMap { Data(base64Encoded: $0) }
        )
      )
    default: return nil
    }
  }
}

extension Notification.Name {
  static let marginURLRoute = Notification.Name("Margin.URLRoute")
  static let marginWorkspaceNavigation = Notification.Name("Margin.WorkspaceNavigation")
  static let marginRouteAcknowledged = Notification.Name("com.marginapp.Margin.RouteAcknowledged")
}

@MainActor
final class MarginURLRouter {
  static let shared = MarginURLRouter()

  private var pendingReadPaths: Set<String> = []
  private var pendingWorkspaceRequest: WorkspaceAccessRequest?
  private var pendingNavigationLines: [String: Int] = [:]

  func handle(_ url: URL) {
    guard let route = MarginURLRoute(url: url) else { return }
    let requestID = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first(where: { $0.name == "request" })?.value
    switch route {
    case .read(let fileURL):
      pendingReadPaths.insert(fileURL.path)
    case .workspace(let request):
      pendingWorkspaceRequest = request
    }
    NotificationCenter.default.post(name: .marginURLRoute, object: route)
    if let requestID {
      DistributedNotificationCenter.default().postNotificationName(
        .marginRouteAcknowledged,
        object: requestID,
        userInfo: nil,
        deliverImmediately: true
      )
    }
  }

  func consumeReadMode(for fileURL: URL?) -> Bool {
    guard let path = fileURL?.standardizedFileURL.path else { return false }
    return pendingReadPaths.remove(path) != nil
  }

  func consumeWorkspace() -> WorkspaceAccessRequest? {
    defer { pendingWorkspaceRequest = nil }
    return pendingWorkspaceRequest
  }

  func requestNavigation(to url: URL, line: Int) {
    let request = WorkspaceNavigationRequest(url: url.standardizedFileURL, line: max(1, line))
    pendingNavigationLines[request.url.path] = request.line
    NotificationCenter.default.post(name: .marginWorkspaceNavigation, object: request)
  }

  func consumeNavigationLine(for fileURL: URL?) -> Int? {
    guard let path = fileURL?.standardizedFileURL.path else { return nil }
    return pendingNavigationLines.removeValue(forKey: path)
  }
}
