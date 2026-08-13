import AppKit
import Darwin
import Foundation

private enum MarginCLIError: LocalizedError {
  case usage(String)
  case applicationNotFound
  case invalidInput(String)

  var errorDescription: String? {
    switch self {
    case .usage(let message), .invalidInput(let message): message
    case .applicationNotFound:
      "Margin.app could not be found. Set MARGIN_APP_PATH or install the CLI from Margin."
    }
  }
}

private enum CLIExportFormat {
  case pdf
  case html
}

private struct OpenInvocation {
  let input: String?
  let readMode: Bool

  init(arguments: [String]) throws {
    var input: String?
    var readMode = false
    var parsesOptions = true

    for argument in arguments {
      if parsesOptions, argument == "--" {
        parsesOptions = false
      } else if parsesOptions, argument == "--read" {
        guard !readMode else { throw MarginCLIError.usage("--read may be specified once.") }
        readMode = true
      } else if parsesOptions, argument.hasPrefix("-") {
        throw MarginCLIError.usage("Unknown option: \(argument)")
      } else if input == nil {
        input = argument
      } else {
        throw MarginCLIError.usage("Expected one file or folder, not \(argument).")
      }
    }

    self.input = input
    self.readMode = readMode
  }
}

private struct ExportInvocation {
  let input: String
  let format: CLIExportFormat
  let output: String?
  let force: Bool

  init(arguments: [String]) throws {
    var input: String?
    var format: CLIExportFormat?
    var output: String?
    var force = false
    var parsesOptions = true
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]
      if parsesOptions, argument == "--" {
        parsesOptions = false
      } else if parsesOptions, argument == "--pdf" || argument == "--html" {
        guard format == nil else {
          throw MarginCLIError.usage("Choose exactly one export format: --pdf or --html.")
        }
        format = argument == "--pdf" ? .pdf : .html
      } else if parsesOptions, argument == "--output" {
        guard output == nil else { throw MarginCLIError.usage("--output may be specified once.") }
        index += 1
        guard index < arguments.count else {
          throw MarginCLIError.usage("--output requires a path.")
        }
        output = arguments[index]
      } else if parsesOptions, argument == "--force" {
        guard !force else { throw MarginCLIError.usage("--force may be specified once.") }
        force = true
      } else if parsesOptions, argument.hasPrefix("-") {
        throw MarginCLIError.usage("Unknown option: \(argument)")
      } else if input == nil {
        input = argument
      } else {
        throw MarginCLIError.usage("Expected one input file, not \(argument).")
      }
      index += 1
    }

    guard let input else {
      throw MarginCLIError.usage(
        "Usage: margin export <file> (--pdf | --html) [--output <path>] [--force]")
    }
    guard let format else {
      throw MarginCLIError.usage("Choose exactly one export format: --pdf or --html.")
    }
    self.input = input
    self.format = format
    self.output = output
    self.force = force
  }
}

@MainActor
private final class RouteAcknowledgementWaiter {
  private let requestID: String
  private var observer: NSObjectProtocol?
  private var continuation: CheckedContinuation<Void, Error>?
  private var timeoutTask: Task<Void, Never>?
  private var acknowledged = false

  init(requestID: String) {
    self.requestID = requestID
    observer = DistributedNotificationCenter.default().addObserver(
      forName: .marginRouteAcknowledged,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard notification.object as? String == self?.requestID else { return }
      Task { @MainActor [weak self] in self?.finish(.success(())) }
    }
  }

  deinit {
    if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    timeoutTask?.cancel()
  }

  func wait() async throws {
    if acknowledged { return }
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      timeoutTask = Task { @MainActor [weak self] in
        do {
          try await Task.sleep(for: .seconds(5))
        } catch {
          return
        }
        self?.finish(
          .failure(
            MarginCLIError.invalidInput(
              "Margin launched but did not acknowledge the request. Try the command again."
            )
          )
        )
      }
    }
  }

  private func finish(_ result: Result<Void, Error>) {
    acknowledged = result.isSuccess
    timeoutTask?.cancel()
    timeoutTask = nil
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }
}

extension Result where Success == Void, Failure == Error {
  fileprivate var isSuccess: Bool {
    if case .success = self { return true }
    return false
  }
}

@main
@MainActor
struct MarginCLI {
  static func main() async {
    do {
      try await run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      FileHandle.standardError.write(Data("margin: \(error.localizedDescription)\n".utf8))
      exit(EXIT_FAILURE)
    }
  }

  private static func run(_ arguments: [String]) async throws {
    purgeStaleStandardInput()
    if arguments == ["--help"] || arguments == ["-h"] {
      print(usage)
      return
    }
    if arguments == ["--version"] {
      print("margin \(applicationVersion ?? "development")")
      return
    }
    if arguments.first == "export" {
      try await export(Array(arguments.dropFirst()))
      return
    }

    let invocation = try OpenInvocation(arguments: arguments)
    let inputURL: URL

    if let value = invocation.input {
      inputURL =
        URL(
          fileURLWithPath: value,
          relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        )
        .standardizedFileURL
    } else if isatty(STDIN_FILENO) == 0 {
      inputURL = try persistStandardInput()
    } else {
      throw MarginCLIError.usage(usage)
    }

    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory) else {
      throw MarginCLIError.invalidInput("No file or folder exists at \(inputURL.path)")
    }

    let applicationURL = try locateApplication()
    if isDirectory.boolValue {
      try await launch(applicationURL)
      let bookmarkData = try? inputURL.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      try await openRoute(
        .workspace(WorkspaceAccessRequest(url: inputURL, bookmarkData: bookmarkData)),
        with: applicationURL
      )
    } else {
      try await open(inputURL, with: applicationURL)
      if invocation.readMode { try await openRoute(.read(inputURL), with: applicationURL) }
    }
  }

  private static func export(_ arguments: [String]) async throws {
    let invocation = try ExportInvocation(arguments: arguments)
    let inputURL = URL(
      fileURLWithPath: invocation.input,
      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      throw MarginCLIError.invalidInput("No input file exists at \(inputURL.path)")
    }
    let source = try MarkdownTextDecoder.read(from: inputURL)
    let html = MarkdownHTMLRenderer().render(
      source: source,
      title: inputURL.deletingPathExtension().lastPathComponent,
      baseURL: inputURL.deletingLastPathComponent()
    )
    let outputExtension = invocation.format == .pdf ? "pdf" : "html"
    let outputURL = URL(
      fileURLWithPath: invocation.output
        ?? inputURL.deletingPathExtension().appendingPathExtension(outputExtension).path,
      relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ).standardizedFileURL
    guard outputURL != inputURL else {
      throw MarginCLIError.invalidInput(
        "Refusing to overwrite the input file. Choose another --output path.")
    }
    if FileManager.default.fileExists(atPath: outputURL.path), !invocation.force {
      throw MarginCLIError.invalidInput(
        "Output already exists at \(outputURL.path). Pass --force to replace it."
      )
    }

    if invocation.format == .pdf {
      try await DocumentExporter.writePDF(
        html,
        baseURL: inputURL.deletingLastPathComponent(),
        to: outputURL
      )
    } else {
      try DocumentExporter.writeHTML(html, to: outputURL)
    }
    print(outputURL.path)
  }

  private static func persistStandardInput() throws -> URL {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard !data.isEmpty else { throw MarginCLIError.invalidInput("standard input was empty") }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Margin-CLI", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("Pasted-\(UUID().uuidString.prefix(8)).md")
    try data.write(to: url, options: .atomic)
    return url
  }

  private static func purgeStaleStandardInput() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "Margin-CLI", isDirectory: true)
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey]
      )
    else { return }
    let cutoff = Date().addingTimeInterval(-86_400)
    for file in files {
      guard
        let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey])
          .contentModificationDate,
        modified < cutoff
      else { continue }
      try? FileManager.default.removeItem(at: file)
    }
  }

  private static var applicationVersion: String? {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    var candidates = [URL]()
    if let enclosingApplicationURL = enclosingApplicationURL(for: executableURL) {
      candidates.append(enclosingApplicationURL)
    }
    candidates.append(
      executableURL.deletingLastPathComponent().appendingPathComponent("Margin.app")
    )
    if let installed = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.marginapp.Margin")
    {
      candidates.append(installed)
    }
    return candidates.lazy.compactMap { Bundle(url: $0) }.compactMap {
      $0.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }.first
  }

  private static func locateApplication() throws -> URL {
    if let configuredPath = ProcessInfo.processInfo.environment["MARGIN_APP_PATH"] {
      let url = URL(fileURLWithPath: configuredPath)
      if FileManager.default.fileExists(atPath: url.path) { return url }
    }

    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    if let embeddedCandidate = enclosingApplicationURL(for: executableURL),
      FileManager.default.fileExists(atPath: embeddedCandidate.path)
    {
      return embeddedCandidate
    }

    let siblingCandidate = executableURL.deletingLastPathComponent().appendingPathComponent(
      "Margin.app")
    if FileManager.default.fileExists(atPath: siblingCandidate.path) { return siblingCandidate }
    if let installed = NSWorkspace.shared.urlForApplication(
      withBundleIdentifier: "com.marginapp.Margin")
    {
      return installed
    }
    throw MarginCLIError.applicationNotFound
  }

  private static func enclosingApplicationURL(for executableURL: URL) -> URL? {
    var candidate = executableURL.deletingLastPathComponent()
    while candidate.path != "/" {
      if candidate.pathExtension.lowercased() == "app" { return candidate }
      candidate.deleteLastPathComponent()
    }
    return nil
  }

  private static func open(_ url: URL, with applicationURL: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    try await NSWorkspace.shared.open(
      [url],
      withApplicationAt: applicationURL,
      configuration: configuration
    )
  }

  private static func launch(_ applicationURL: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
  }

  private static func openRoute(_ route: MarginURLRoute, with applicationURL: URL) async throws {
    let requestID = UUID().uuidString
    let waiter = RouteAcknowledgementWaiter(requestID: requestID)
    var components = URLComponents()
    components.scheme = "margin"
    switch route {
    case .read(let url):
      components.host = "read"
      components.queryItems = [.init(name: "path", value: url.path)]
    case .workspace(let request):
      components.host = "workspace"
      components.queryItems = [
        .init(name: "path", value: request.url.path),
        request.bookmarkData.map { .init(name: "bookmark", value: $0.base64EncodedString()) },
      ].compactMap { $0 }
    }
    components.queryItems?.append(.init(name: "request", value: requestID))
    guard let url = components.url else {
      throw MarginCLIError.invalidInput("Margin did not accept the requested route.")
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    try await NSWorkspace.shared.open(
      [url],
      withApplicationAt: applicationURL,
      configuration: configuration
    )
    try await waiter.wait()
  }

  static let usage = """
    Usage:
      margin <file>
      margin <folder>
      margin --read <file>
      margin export <file> --pdf [--output <path>] [--force]
      margin export <file> --html [--output <path>] [--force]
      cat README.md | margin
    """
}
