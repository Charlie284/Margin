import CryptoKit
import Darwin
import Foundation

private enum BuildToolError: LocalizedError {
  case commandFailed(executable: String, arguments: [String], status: Int32)
  case invalidArguments(String)
  case missingEnvironmentVariable(String)
  case missingRepository
  case validationFailed(String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let executable, let arguments, let status):
      let command = ([executable] + arguments).joined(separator: " ")
      return "Command failed with status \(status): \(command)"
    case .invalidArguments(let message), .validationFailed(let message):
      return message
    case .missingEnvironmentVariable(let name):
      return "Set \(name) before running a release."
    case .missingRepository:
      return "Run margin-build from the Margin repository or one of its subdirectories."
    }
  }
}

private struct CommandResult {
  let status: Int32
  let data: Data

  var output: String {
    String(decoding: data, as: UTF8.self)
  }
}

private enum CIStage: String, CaseIterable {
  case analyze
  case test
  case uiTest = "ui-test"
  case build
  case validateProducts = "validate-products"
  case validateCLI = "validate-cli"
}

private struct CIOptions {
  let stage: CIStage?
  let developerDirectory: URL?
}

private struct CommandRunner {
  let repositoryURL: URL
  let environment: [String: String]

  init(repositoryURL: URL, developerDirectory: URL? = nil) {
    self.repositoryURL = repositoryURL
    var environment = ProcessInfo.processInfo.environment
    if let developerDirectory {
      environment["DEVELOPER_DIR"] = developerDirectory.path
    }
    self.environment = environment
  }

  @discardableResult
  func run(
    _ executable: URL,
    arguments: [String],
    allowFailure: Bool = false
  ) throws -> Int32 {
    let process = process(executable, arguments: arguments)
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0, !allowFailure {
      throw BuildToolError.commandFailed(
        executable: executable.path,
        arguments: arguments,
        status: process.terminationStatus
      )
    }
    return process.terminationStatus
  }

  func capture(
    _ executable: URL,
    arguments: [String],
    includeStandardError: Bool = false,
    allowFailure: Bool = false
  ) throws -> CommandResult {
    let process = process(executable, arguments: arguments)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = includeStandardError ? pipe : FileHandle.standardError
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let result = CommandResult(status: process.terminationStatus, data: data)
    if result.status != 0, !allowFailure {
      throw BuildToolError.commandFailed(
        executable: executable.path,
        arguments: arguments,
        status: result.status
      )
    }
    return result
  }

  @discardableResult
  func runXcrun(
    _ tool: String,
    arguments: [String],
    allowFailure: Bool = false
  ) throws -> Int32 {
    try run(
      URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: [tool] + arguments,
      allowFailure: allowFailure
    )
  }

  func captureXcrun(
    _ tool: String,
    arguments: [String],
    includeStandardError: Bool = false,
    allowFailure: Bool = false
  ) throws -> CommandResult {
    try capture(
      URL(fileURLWithPath: "/usr/bin/xcrun"),
      arguments: [tool] + arguments,
      includeStandardError: includeStandardError,
      allowFailure: allowFailure
    )
  }

  private func process(_ executable: URL, arguments: [String]) -> Process {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.currentDirectoryURL = repositoryURL
    process.environment = environment
    return process
  }
}

private struct MarginBuildTool {
  private let fileManager = FileManager.default
  private let repositoryURL: URL

  init() throws {
    guard let repositoryURL = Self.findRepository() else {
      throw BuildToolError.missingRepository
    }
    self.repositoryURL = repositoryURL
  }

  func run(arguments: [String]) throws {
    guard let command = arguments.first else {
      throw BuildToolError.invalidArguments(Self.usage)
    }

    switch command {
    case "ci":
      let options = try parseCIOptions(arguments: Array(arguments.dropFirst()))
      try runCI(options: options)
    case "release":
      guard arguments.count == 1 else {
        throw BuildToolError.invalidArguments("release does not accept arguments.\n\n\(Self.usage)")
      }
      try runRelease()
    case "--help", "-h", "help":
      print(Self.usage)
    default:
      throw BuildToolError.invalidArguments("Unknown command: \(command)\n\n\(Self.usage)")
    }
  }

  private func runCI(options: CIOptions) throws {
    if let developerDirectory = options.developerDirectory,
      !fileManager.fileExists(atPath: developerDirectory.path)
    {
      throw BuildToolError.validationFailed(
        "Developer directory does not exist: \(developerDirectory.path)"
      )
    }

    let runner = CommandRunner(
      repositoryURL: repositoryURL,
      developerDirectory: options.developerDirectory
    )

    let stages = options.stage.map { [$0] } ?? CIStage.allCases
    for ciStage in stages {
      try run(ciStage, runner: runner)
    }
  }

  private func run(_ ciStage: CIStage, runner: CommandRunner) throws {
    switch ciStage {
    case .analyze:
      try stage("Analyze") {
        try runner.runXcrun(
          "xcodebuild",
          arguments: [
            "-project", "Margin.xcodeproj",
            "-scheme", "Margin",
            "-configuration", "Debug",
            "-destination", "platform=macOS",
            "-derivedDataPath", "build/ci-analyze",
            "analyze",
            "CODE_SIGNING_ALLOWED=NO",
          ]
        )
      }
    case .test:
      try stage("Test") {
        try runner.runXcrun(
          "xcodebuild",
          arguments: [
            "-project", "Margin.xcodeproj",
            "-scheme", "Margin",
            "-configuration", "Debug",
            "-destination", "platform=macOS",
            "-derivedDataPath", "build/ci-tests",
            "test",
            "CODE_SIGNING_ALLOWED=NO",
            "-skip-testing:MarginUITests",
          ]
        )
      }
    case .uiTest:
      try stage("UI smoke test") {
        try runner.runXcrun(
          "xcodebuild",
          arguments: [
            "-project", "Margin.xcodeproj",
            "-scheme", "Margin",
            "-configuration", "Debug",
            "-destination", "platform=macOS",
            "-derivedDataPath", "build/ci-ui-tests",
            "test",
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGN_STYLE=Manual",
            "DEVELOPMENT_TEAM=",
            "-only-testing:MarginUITests/MarginUITests/testPresentationControlsSwitchModes",
          ]
        )
      }
    case .build:
      try stage("Build universal Release") {
        try runner.runXcrun(
          "xcodebuild",
          arguments: [
            "-project", "Margin.xcodeproj",
            "-scheme", "Margin",
            "-configuration", "Release",
            "-destination", "generic/platform=macOS",
            "-derivedDataPath", "build/ci-release",
            "ARCHS=arm64 x86_64",
            "ONLY_ACTIVE_ARCH=NO",
            "CODE_SIGNING_ALLOWED=NO",
            "build",
          ]
        )
      }
    case .validateProducts:
      try stage("Validate bundled products") {
        try validateBundledProducts(runner: runner)
      }
    case .validateCLI:
      try stage("Exercise CLI validation") {
        try validateCLI(runner: runner)
      }
    }
  }

  private func validateBundledProducts(runner: CommandRunner) throws {
    let productsURL = repositoryURL.appendingPathComponent(
      "build/ci-release/Build/Products/Release",
      isDirectory: true
    )
    let appURL = productsURL.appendingPathComponent("Margin.app", isDirectory: true)
    let quickLookURL = appURL.appendingPathComponent(
      "Contents/PlugIns/MarginQuickLook.appex",
      isDirectory: true
    )
    let infoURL = quickLookURL.appendingPathComponent("Contents/Info.plist")
    let infoData = try Data(contentsOf: infoURL)
    let propertyList = try PropertyListSerialization.propertyList(from: infoData, format: nil)
    guard
      let info = propertyList as? [String: Any],
      let extensionInfo = info["NSExtension"] as? [String: Any],
      let attributes = extensionInfo["NSExtensionAttributes"] as? [String: Any],
      let contentTypes = attributes["QLSupportedContentTypes"] as? [String],
      contentTypes.first == "net.daringfireball.markdown"
    else {
      throw BuildToolError.validationFailed(
        "MarginQuickLook does not declare net.daringfireball.markdown as its first content type."
      )
    }

    try requireUniversal(
      appURL.appendingPathComponent("Contents/MacOS/Margin"),
      runner: runner
    )
    try requireUniversal(
      appURL.appendingPathComponent("Contents/SharedSupport/bin/margin"),
      runner: runner
    )
    try requireUniversal(
      quickLookURL.appendingPathComponent("Contents/MacOS/MarginQuickLook"),
      runner: runner
    )
  }

  private func validateCLI(runner: CommandRunner) throws {
    let cliURL = repositoryURL.appendingPathComponent(
      "build/ci-release/Build/Products/Release/margin"
    )
    let outputURL = repositoryURL.appendingPathComponent("build/cli-check.html")
    if fileManager.fileExists(atPath: outputURL.path) {
      try fileManager.removeItem(at: outputURL)
    }

    try runner.run(cliURL, arguments: ["--help"])
    let version = try runner.capture(cliURL, arguments: ["--version"]).output
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard version != "margin development" else {
      throw BuildToolError.validationFailed("CLI could not discover the app version.")
    }

    let unknownStatus = try runner.run(
      cliURL,
      arguments: ["--unknown"],
      allowFailure: true
    )
    guard unknownStatus != 0 else {
      throw BuildToolError.validationFailed("Unknown CLI option unexpectedly succeeded.")
    }

    let exportArguments = [
      "export", "Samples/Welcome.md", "--html", "--output", "build/cli-check.html",
    ]
    try runner.run(cliURL, arguments: exportArguments)
    try requireNonemptyFile(outputURL)

    let overwriteStatus = try runner.run(
      cliURL,
      arguments: exportArguments,
      allowFailure: true
    )
    guard overwriteStatus != 0 else {
      throw BuildToolError.validationFailed(
        "Existing CLI output was overwritten without --force."
      )
    }

    try runner.run(cliURL, arguments: exportArguments + ["--force"])
    try requireNonemptyFile(outputURL)
  }

  private func runRelease() throws {
    let environment = ProcessInfo.processInfo.environment
    let developmentTeam = try requiredEnvironment("DEVELOPMENT_TEAM", in: environment)
    let notaryProfile = try requiredEnvironment("NOTARY_PROFILE", in: environment)
    let signingIdentity = environment["SIGNING_IDENTITY"] ?? "Developer ID Application"
    let archiveURL = resolve(
      environment["ARCHIVE_PATH"] ?? "build/release/Margin.xcarchive"
    )
    let outputDirectoryURL = resolve(environment["OUTPUT_DIRECTORY"] ?? "build/release")
    let appURL = archiveURL.appendingPathComponent(
      "Products/Applications/Margin.app",
      isDirectory: true
    )
    let cliURL = appURL.appendingPathComponent("Contents/SharedSupport/bin/margin")
    let quickLookURL = appURL.appendingPathComponent(
      "Contents/PlugIns/MarginQuickLook.appex",
      isDirectory: true
    )
    let submissionURL = outputDirectoryURL.appendingPathComponent("Margin-notarization.zip")
    let releaseURL = outputDirectoryURL.appendingPathComponent("Margin.zip")
    let notarizationLogURL = outputDirectoryURL.appendingPathComponent("notarization.log")
    let runner = CommandRunner(repositoryURL: repositoryURL)

    try fileManager.createDirectory(
      at: outputDirectoryURL,
      withIntermediateDirectories: true
    )

    try stage("Archive") {
      try runner.runXcrun(
        "xcodebuild",
        arguments: [
          "-project", "Margin.xcodeproj",
          "-scheme", "Margin",
          "-configuration", "Release",
          "-destination", "generic/platform=macOS",
          "-archivePath", archiveURL.path,
          "DEVELOPMENT_TEAM=\(developmentTeam)",
          "CODE_SIGN_STYLE=Manual",
          "CODE_SIGN_IDENTITY=\(signingIdentity)",
          "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
          "OTHER_CODE_SIGN_FLAGS=--timestamp",
          "archive",
        ]
      )
    }

    try stage("Verify signing") {
      let codesignURL = URL(fileURLWithPath: "/usr/bin/codesign")
      try runner.run(
        codesignURL,
        arguments: ["--verify", "--deep", "--strict", "--verbose=2", appURL.path]
      )
      try runner.run(
        codesignURL,
        arguments: ["--verify", "--strict", "--verbose=2", cliURL.path]
      )
      try runner.run(
        codesignURL,
        arguments: ["--verify", "--strict", "--verbose=2", quickLookURL.path]
      )
      try requireUniversal(
        appURL.appendingPathComponent("Contents/MacOS/Margin"),
        runner: runner
      )
      try requireUniversal(cliURL, runner: runner)
      try requireUniversal(
        quickLookURL.appendingPathComponent("Contents/MacOS/MarginQuickLook"),
        runner: runner
      )
      try rejectDebugEntitlement(appURL, runner: runner)
      try rejectDebugEntitlement(quickLookURL, runner: runner)
    }

    try stage("Notarize") {
      let dittoURL = URL(fileURLWithPath: "/usr/bin/ditto")
      try runner.run(
        dittoURL,
        arguments: ["-c", "-k", "--keepParent", appURL.path, submissionURL.path]
      )
      let result = try runner.captureXcrun(
        "notarytool",
        arguments: [
          "submit", submissionURL.path,
          "--keychain-profile", notaryProfile,
          "--wait",
        ],
        includeStandardError: true,
        allowFailure: true
      )
      FileHandle.standardOutput.write(result.data)
      try result.data.write(to: notarizationLogURL, options: .atomic)
      guard result.status == 0 else {
        throw BuildToolError.commandFailed(
          executable: "/usr/bin/xcrun",
          arguments: ["notarytool", "submit", submissionURL.path],
          status: result.status
        )
      }
      try runner.runXcrun("stapler", arguments: ["staple", appURL.path])
      try runner.runXcrun("stapler", arguments: ["validate", appURL.path])
      try runner.run(
        URL(fileURLWithPath: "/usr/sbin/spctl"),
        arguments: ["--assess", "--type", "execute", "--verbose=4", appURL.path]
      )
    }

    try stage("Package") {
      try runner.run(
        URL(fileURLWithPath: "/usr/bin/ditto"),
        arguments: ["-c", "-k", "--keepParent", appURL.path, releaseURL.path]
      )
      try writeSHA256(for: releaseURL)
    }

    print(releaseURL.path)
  }

  private func requireUniversal(_ binaryURL: URL, runner: CommandRunner) throws {
    let output = try runner.captureXcrun("lipo", arguments: ["-archs", binaryURL.path]).output
    let architectures = Set(output.split(whereSeparator: \Character.isWhitespace).map(String.init))
    guard architectures.contains("arm64"), architectures.contains("x86_64") else {
      throw BuildToolError.validationFailed(
        "Expected a universal binary at \(binaryURL.path), found: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
      )
    }
  }

  private func rejectDebugEntitlement(_ productURL: URL, runner: CommandRunner) throws {
    let result = try runner.capture(
      URL(fileURLWithPath: "/usr/bin/codesign"),
      arguments: ["-d", "--entitlements", "-", productURL.path],
      includeStandardError: true
    )
    guard !result.output.contains("get-task-allow") else {
      throw BuildToolError.validationFailed(
        "Release product contains get-task-allow: \(productURL.path)"
      )
    }
  }

  private func requireNonemptyFile(_ fileURL: URL) throws {
    let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
    guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
      throw BuildToolError.validationFailed("Expected a nonempty file at \(fileURL.path).")
    }
  }

  private func writeSHA256(for fileURL: URL) throws {
    let handle = try FileHandle(forReadingFrom: fileURL)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
      hasher.update(data: data)
    }
    let digest = hasher.finalize()
    let hash = digest.map { String(format: "%02x", $0) }.joined()
    let checksum = "\(hash)  \(fileURL.lastPathComponent)\n"
    let checksumURL = URL(fileURLWithPath: fileURL.path + ".sha256")
    try Data(checksum.utf8).write(to: checksumURL, options: .atomic)
  }

  private func requiredEnvironment(
    _ name: String,
    in environment: [String: String]
  ) throws -> String {
    guard let value = environment[name], !value.isEmpty else {
      throw BuildToolError.missingEnvironmentVariable(name)
    }
    return value
  }

  private func parseCIOptions(arguments: [String]) throws -> CIOptions {
    var stage: CIStage?
    var developerDirectory: URL?
    var index = 0

    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--developer-dir" {
        guard developerDirectory == nil, index + 1 < arguments.count else {
          throw BuildToolError.invalidArguments("Invalid ci arguments.\n\n\(Self.usage)")
        }
        developerDirectory =
          URL(
            fileURLWithPath: arguments[index + 1],
            isDirectory: true
          ).standardizedFileURL
        index += 2
      } else {
        guard stage == nil, let parsedStage = CIStage(rawValue: argument) else {
          throw BuildToolError.invalidArguments("Invalid ci arguments.\n\n\(Self.usage)")
        }
        stage = parsedStage
        index += 1
      }
    }

    return CIOptions(stage: stage, developerDirectory: developerDirectory)
  }

  private func resolve(_ path: String) -> URL {
    URL(fileURLWithPath: path, relativeTo: repositoryURL).standardizedFileURL
  }

  private func stage(_ name: String, action: () throws -> Void) throws {
    print("\n==> \(name)")
    try action()
  }

  private static func findRepository() -> URL? {
    var candidate = URL(
      fileURLWithPath: FileManager.default.currentDirectoryPath,
      isDirectory: true
    ).standardizedFileURL
    while true {
      let projectURL = candidate.appendingPathComponent("Margin.xcodeproj", isDirectory: true)
      if FileManager.default.fileExists(atPath: projectURL.path) {
        return candidate
      }
      let parent = candidate.deletingLastPathComponent()
      if parent.path == candidate.path {
        return nil
      }
      candidate = parent
    }
  }

  private static let usage = """
    Usage:
      margin-build ci [STAGE] [--developer-dir PATH]
      margin-build release

    With no stage, the ci command runs every gate. A single stage may be selected from:
      analyze, test, ui-test, build, validate-products, validate-cli

    The release command requires DEVELOPMENT_TEAM and NOTARY_PROFILE. It also accepts
    SIGNING_IDENTITY, ARCHIVE_PATH, and OUTPUT_DIRECTORY through the environment.
    """
}

do {
  try MarginBuildTool().run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
  let message = "margin-build: \(error.localizedDescription)\n"
  FileHandle.standardError.write(Data(message.utf8))
  exit(EXIT_FAILURE)
}
