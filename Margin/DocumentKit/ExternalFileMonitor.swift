import Darwin
import Foundation

enum ExternalChangeDecision: Equatable {
  case unchanged
  case reloadFromDisk
  case conflict

  static func decide(lastKnownDisk: String, local: String, disk: String) -> Self {
    if disk == lastKnownDisk || disk == local { return .unchanged }
    if local == lastKnownDisk { return .reloadFromDisk }
    return .conflict
  }
}

@MainActor
final class ExternalFileMonitor: ObservableObject {
  enum State: Equatable {
    case stopped
    case monitoring
    case failed(String)
  }

  @Published private(set) var state: State = .stopped
  private var source: DispatchSourceFileSystemObject?
  private var monitoredURL: URL?
  private var changeHandler: (() -> Void)?

  func start(url: URL, onChange: @escaping () -> Void) {
    stop()
    monitoredURL = url.standardizedFileURL
    changeHandler = onChange
    installSource()
  }

  func stop() {
    source?.cancel()
    source = nil
    monitoredURL = nil
    changeHandler = nil
    state = .stopped
  }

  private func installSource() {
    guard let monitoredURL else { return }
    let descriptor = Darwin.open(monitoredURL.path, O_EVTONLY)
    guard descriptor >= 0 else {
      let message = String(cString: strerror(errno))
      state = .failed("External change monitoring is unavailable: \(message)")
      return
    }

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor,
      eventMask: [.write, .delete, .rename, .attrib, .extend],
      queue: DispatchQueue.global(qos: .utility)
    )

    source.setEventHandler { [weak self, weak source] in
      let event = source?.data ?? []
      Task { @MainActor [weak self] in
        guard let self else { return }
        changeHandler?()

        if event.contains(.delete) || event.contains(.rename) {
          self.source?.cancel()
          self.source = nil
          try? await Task.sleep(for: .milliseconds(350))
          self.installSource()
        }
      }
    }
    source.setCancelHandler { Darwin.close(descriptor) }
    self.source = source
    source.resume()
    state = .monitoring
  }
}
