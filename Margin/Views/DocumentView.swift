import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
  @Binding var document: MarkdownDocument
  let fileURL: URL?
  let isEditable: Bool

  @State private var mode: PresentationMode
  @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
  @State private var inspectorVisible = false
  @State private var commandPaletteVisible = false
  @State private var quickOpenVisible = false
  @State private var workspaceSearchVisible = false
  @State private var requestedScrollID: String?
  @State private var openDocumentError: String?
  @State private var externalConflictContent: String?
  @State private var lastKnownDiskContent = ""
  @State private var parsedDocument: ParsedMarkdownDocument
  @State private var parsedSource: String
  @State private var dropTargeted = false
  @AppStorage("assetStorageStrategy") private var assetStorage = AssetStorageStrategy.assetsFolder
  @EnvironmentObject private var workspace: WorkspaceController
  @StateObject private var externalFileMonitor = ExternalFileMonitor()
  @StateObject private var supportingFileAccess = SupportingFileAccess()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.openDocument) private var openDocument

  init(document: Binding<MarkdownDocument>, fileURL: URL?, isEditable: Bool) {
    _document = document
    self.fileURL = fileURL
    self.isEditable = isEditable
    _mode = State(initialValue: fileURL == nil ? .write : .read)
    let source = document.wrappedValue.text
    _parsedDocument = State(initialValue: MarkdownParser().parse(source))
    _parsedSource = State(initialValue: source)
  }

  var body: some View {
    NavigationSplitView(columnVisibility: $columnVisibility) {
      DocumentSidebar(
        fileURL: fileURL,
        outline: parsedDocument.outline,
        workspace: workspace,
        selectOutlineEntry: selectOutlineEntry,
        chooseWorkspace: chooseWorkspace,
        openFile: openWorkspaceFile
      )
    } detail: {
      presentation(parsedDocument)
        .onDrop(
          of: [UTType.fileURL.identifier, UTType.image.identifier, UTType.plainText.identifier],
          isTargeted: $dropTargeted,
          perform: handleDrop
        )
        .overlay {
          if dropTargeted {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
              .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
              .padding(10)
              .background(Color.accentColor.opacity(0.045))
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
        }
        .inspector(isPresented: $inspectorVisible) {
          DocumentInspector(
            assetStorage: $assetStorage,
            statistics: parsedDocument.statistics,
            outline: parsedDocument.outline,
            backlinks: workspace.backlinks(to: fileURL),
            selectOutlineEntry: selectOutlineEntry,
            openFile: openWorkspaceFile
          )
        }
    }
    .navigationSplitViewStyle(.balanced)
    .navigationTitle(fileURL?.lastPathComponent ?? "Untitled")
    .toolbar { toolbar }
    .overlay {
      if commandPaletteVisible {
        CommandPalette(
          isPresented: $commandPaletteVisible,
          commands: paletteCommands
        )
      } else if quickOpenVisible {
        WorkspacePanel(
          isPresented: $quickOpenVisible,
          workspace: workspace,
          mode: .quickOpen,
          openFile: openWorkspaceFile,
          openSearchResult: openWorkspaceSearchResult,
          chooseFolder: chooseWorkspace
        )
      } else if workspaceSearchVisible {
        WorkspacePanel(
          isPresented: $workspaceSearchVisible,
          workspace: workspace,
          mode: .search,
          openFile: openWorkspaceFile,
          openSearchResult: openWorkspaceSearchResult,
          chooseFolder: chooseWorkspace
        )
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: commandPaletteVisible)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: quickOpenVisible)
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: workspaceSearchVisible)
    .focusedSceneValue(\.marginDocumentActions, focusedActions)
    .task { workspace.restoreLastWorkspaceIfAvailable() }
    .task { consumePendingRoute() }
    .task(id: document.text) { await updateParsedDocument() }
    .task(id: fileURL) { startExternalFileMonitoring() }
    .task(id: fileURL) { supportingFileAccess.restore(for: fileURL) }
    .onChange(of: externalFileMonitor.state) { _, state in
      if case .failed(let message) = state { openDocumentError = message }
    }
    .onReceive(NotificationCenter.default.publisher(for: .marginURLRoute)) { notification in
      guard let route = notification.object as? MarginURLRoute else { return }
      apply(route)
    }
    .onReceive(NotificationCenter.default.publisher(for: .marginWorkspaceNavigation)) {
      notification in
      guard let request = notification.object as? WorkspaceNavigationRequest,
        request.url.standardizedFileURL == fileURL?.standardizedFileURL
      else { return }
      _ = MarginURLRouter.shared.consumeNavigationLine(for: fileURL)
      navigateToLine(request.line)
    }
    .onDisappear {
      externalFileMonitor.stop()
      supportingFileAccess.stop()
    }
    .alert("Couldn’t Open Document", isPresented: openDocumentErrorIsPresented) {
      Button("OK", role: .cancel) { openDocumentError = nil }
    } message: {
      Text(openDocumentError ?? "The document could not be opened.")
    }
    .alert("File Changed on Disk", isPresented: externalConflictIsPresented) {
      Button("Reload from Disk", role: .destructive) { reloadExternalContent() }
      Button("Keep My Changes") { keepLocalContent() }
    } message: {
      Text(
        "This document changed in another app while Margin had local edits. Choose which version to keep."
      )
    }
  }

  private func updateParsedDocument() async {
    let source = document.text
    guard source != parsedSource else { return }

    try? await Task.sleep(for: .milliseconds(source.utf8.count > 50_000 ? 100 : 45))
    guard !Task.isCancelled else { return }
    let parsingTask = Task.detached(priority: .userInitiated) {
      MarkdownParser().parse(source)
    }
    let parsed = await withTaskCancellationHandler {
      await parsingTask.value
    } onCancel: {
      parsingTask.cancel()
    }
    guard !Task.isCancelled, document.text == source else { return }
    parsedDocument = parsed
    parsedSource = source
  }

  private func consumePendingRoute() {
    if MarginURLRouter.shared.consumeReadMode(for: fileURL) { mode = .read }
    if let workspaceRequest = MarginURLRouter.shared.consumeWorkspace() {
      workspace.open(workspaceRequest)
    }
    if let line = MarginURLRouter.shared.consumeNavigationLine(for: fileURL) {
      navigateToLine(line)
    }
  }

  private func apply(_ route: MarginURLRoute) {
    switch route {
    case .read(let url):
      if fileURL?.standardizedFileURL == url.standardizedFileURL { mode = .read }
    case .workspace(let request):
      workspace.open(request)
    }
  }

  @ViewBuilder
  private func presentation(_ parsedDocument: ParsedMarkdownDocument) -> some View {
    switch mode {
    case .write:
      editorCanvas
    case .read:
      readerCanvas(parsedDocument)
    case .split:
      HSplitView {
        editorCanvas
          .frame(minWidth: 330)
        readerCanvas(parsedDocument)
          .frame(minWidth: 330)
      }
    }
  }

  private var editorCanvas: some View {
    GeometryReader { geometry in
      ZStack(alignment: .topLeading) {
        Color(nsColor: .textBackgroundColor)

        MarkdownEditor(
          text: $document.text,
          isEditable: isEditable,
          baseURL: fileURL?.deletingLastPathComponent()
        )
        .padding(.horizontal, max(28, (geometry.size.width - 800) / 2))

        if document.text.isEmpty {
          Text("Start writing…")
            .font(.system(size: 16))
            .foregroundStyle(.tertiary)
            .padding(.top, 49)
            .padding(.leading, max(32, (geometry.size.width - 800) / 2 + 4))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityElement(children: .contain)
  }

  private func readerCanvas(_ parsedDocument: ParsedMarkdownDocument) -> some View {
    MarkdownReader(
      document: parsedDocument,
      source: $document.text,
      baseURL: fileURL?.deletingLastPathComponent(),
      requestedScrollID: requestedScrollID,
      isEditable: isEditable
    )
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem(placement: .principal) {
      Picker("Presentation", selection: $mode) {
        ForEach(PresentationMode.allCases) { mode in
          Label(mode.title, systemImage: mode.symbolName)
            .labelStyle(.titleOnly)
            .tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .fixedSize(horizontal: true, vertical: false)
      .accessibilityLabel("Document presentation")
    }

    ToolbarItemGroup(placement: .primaryAction) {
      if let fileURL {
        ShareLink(item: fileURL) {
          Image(systemName: "square.and.arrow.up")
        }
        .help("Share Document")
        .accessibilityLabel("Share document")
      }

      Button {
        inspectorVisible.toggle()
      } label: {
        Image(systemName: "sidebar.right")
      }
      .help(inspectorVisible ? "Hide Inspector" : "Show Inspector")
      .accessibilityLabel(inspectorVisible ? "Hide inspector" : "Show inspector")

      Menu {
        Button("Open Folder…") { chooseWorkspace() }

        if workspace.rootURL != nil {
          Button("Refresh Workspace") { workspace.refresh() }
        }

        Divider()

        Button("Open in Finder") {
          if let fileURL { NSWorkspace.shared.activateFileViewerSelecting([fileURL]) }
        }
        .disabled(fileURL == nil)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .help("Document Options")
      .accessibilityLabel("Document options")
    }
  }

  private var focusedActions: FocusedDocumentActions {
    FocusedDocumentActions(
      mode: mode,
      sidebarVisible: columnVisibility != .detailOnly,
      inspectorVisible: inspectorVisible,
      canFormat: isEditable && (mode == .write || mode == .split),
      setMode: { mode = $0 },
      toggleSidebar: toggleSidebar,
      toggleInspector: { inspectorVisible.toggle() },
      showCommandPalette: { commandPaletteVisible = true },
      quickOpen: quickOpen,
      searchWorkspace: searchWorkspace,
      chooseWorkspace: chooseWorkspace,
      exportPDF: { exportDocument(.pdf) },
      exportHTML: { exportDocument(.html) },
      copyHTML: copyRenderedHTML,
      formatBold: { sendTextAction(#selector(MarginTextView.marginToggleBold(_:))) },
      formatItalic: { sendTextAction(#selector(MarginTextView.marginToggleItalic(_:))) },
      formatInlineCode: { sendTextAction(#selector(MarginTextView.marginToggleInlineCode(_:))) },
      insertLink: { sendTextAction(#selector(MarginTextView.marginInsertLink(_:))) }
    )
  }

  private var paletteCommands: [PaletteCommand] {
    DocumentPaletteCommands.make(
      sidebarVisible: columnVisibility != .detailOnly,
      inspectorVisible: inspectorVisible,
      fileURL: fileURL,
      actions: .init(
        setMode: { mode = $0 },
        toggleSidebar: toggleSidebar,
        toggleInspector: { inspectorVisible.toggle() },
        quickOpen: quickOpen,
        searchWorkspace: searchWorkspace,
        chooseWorkspace: chooseWorkspace,
        exportPDF: { exportDocument(.pdf) },
        exportHTML: { exportDocument(.html) },
        copyHTML: copyRenderedHTML,
        formatBold: { focusEditorAndSend(#selector(MarginTextView.marginToggleBold(_:))) },
        formatItalic: { focusEditorAndSend(#selector(MarginTextView.marginToggleItalic(_:))) }
      )
    )
  }

  private func selectOutlineEntry(_ entry: OutlineEntry) {
    if mode == .write { mode = .read }
    requestedScrollID = nil
    DispatchQueue.main.async { requestedScrollID = entry.id }
  }

  private func toggleSidebar() {
    columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
  }

  private func quickOpen() {
    commandPaletteVisible = false
    workspaceSearchVisible = false
    quickOpenVisible = true
  }

  private func searchWorkspace() {
    commandPaletteVisible = false
    quickOpenVisible = false
    workspaceSearchVisible = true
  }

  private func chooseWorkspace() {
    let panel = NSOpenPanel()
    panel.title = "Open Markdown Workspace"
    panel.prompt = "Open"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = workspace.rootURL ?? fileURL?.deletingLastPathComponent()

    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      workspace.open(url)
      columnVisibility = .all
    }
  }

  private func openWorkspaceFile(_ file: WorkspaceFile) {
    Task {
      do {
        try await openDocument(at: file.url)
      } catch {
        openDocumentError = error.localizedDescription
      }
    }
  }

  private func openWorkspaceSearchResult(_ result: WorkspaceSearchResult) {
    MarginURLRouter.shared.requestNavigation(to: result.file.url, line: result.line)
    openWorkspaceFile(result.file)
  }

  private func navigateToLine(_ line: Int) {
    let lines = document.text.components(separatedBy: "\n")
    let boundedLine = min(max(1, line), max(1, lines.count))
    let prefix = lines.prefix(boundedLine - 1).joined(separator: "\n")
    let location = (prefix as NSString).length + (boundedLine > 1 ? 1 : 0)
    guard
      let block = parsedDocument.blocks.first(where: {
        location >= $0.sourceRange.location && location <= NSMaxRange($0.sourceRange)
      })
    else { return }
    mode = .read
    requestedScrollID = nil
    DispatchQueue.main.async { requestedScrollID = block.id }
  }

  private func exportDocument(_ format: DocumentExportFormat) {
    DocumentExportCoordinator.present(
      format: format,
      fileURL: fileURL,
      html: renderedHTML,
      onError: { openDocumentError = $0 }
    )
  }

  private func copyRenderedHTML() {
    DocumentExporter.copyHTML(renderedHTML, plainText: document.text)
  }

  private var renderedHTML: String {
    MarkdownHTMLRenderer().render(
      source: document.text,
      title: fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled",
      baseURL: fileURL?.deletingLastPathComponent()
    )
  }

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    DocumentDropCoordinator(
      documentURL: fileURL,
      assetStorage: assetStorage,
      workspaceGrantsAccess: workspace.grantsAccess,
      supportingFileAccess: supportingFileAccess,
      openWorkspace: {
        workspace.open($0)
        columnVisibility = .all
      },
      insertMarkdown: insertMarkdown,
      reportError: { openDocumentError = $0 }
    ).accept(providers)
  }

  private func insertMarkdown(_ markdown: String) {
    guard isEditable else {
      openDocumentError = "This document is read-only."
      return
    }
    let prefix = document.text.isEmpty || document.text.hasSuffix("\n") ? "" : "\n"
    let insertion = prefix + markdown
    if mode == .read { mode = .write }
    DispatchQueue.main.async {
      if let editor = NSApp.keyWindow?.firstResponder as? MarginTextView {
        NSApp.sendAction(
          #selector(MarginTextView.marginInsertMarkdown(_:)),
          to: editor,
          from: insertion
        )
      } else {
        document.text += insertion
      }
    }
  }

  private func startExternalFileMonitoring() {
    guard let fileURL else {
      externalFileMonitor.stop()
      return
    }

    lastKnownDiskContent = (try? MarkdownTextDecoder.read(from: fileURL)) ?? document.text
    externalFileMonitor.start(url: fileURL) {
      inspectExternalFileChange()
    }
  }

  private func inspectExternalFileChange() {
    guard let fileURL else { return }
    Task {
      try? await Task.sleep(for: .milliseconds(180))
      do {
        let diskContent = try MarkdownTextDecoder.read(from: fileURL)

        switch ExternalChangeDecision.decide(
          lastKnownDisk: lastKnownDiskContent,
          local: document.text,
          disk: diskContent
        ) {
        case .unchanged:
          lastKnownDiskContent = diskContent
        case .reloadFromDisk:
          document.text = diskContent
          lastKnownDiskContent = diskContent
          workspace.refresh()
        case .conflict:
          externalConflictContent = diskContent
        }
      } catch {
        openDocumentError =
          "Margin couldn’t read an external file change: \(error.localizedDescription)"
      }
    }
  }

  private func reloadExternalContent() {
    guard let externalConflictContent else { return }
    document.text = externalConflictContent
    lastKnownDiskContent = externalConflictContent
    self.externalConflictContent = nil
    workspace.refresh()
  }

  private func keepLocalContent() {
    if let externalConflictContent {
      lastKnownDiskContent = externalConflictContent
    }
    externalConflictContent = nil
  }

  private func sendTextAction(_ selector: Selector) {
    guard isEditable, mode == .write || mode == .split,
      let editor = NSApp.keyWindow?.firstResponder as? MarginTextView
    else { return }
    NSApp.sendAction(selector, to: editor, from: nil)
  }

  private func focusEditorAndSend(_ selector: Selector) {
    guard isEditable else { return }
    if mode == .read { mode = .write }
    DispatchQueue.main.async { sendTextAction(selector) }
  }

  private var openDocumentErrorIsPresented: Binding<Bool> {
    Binding(
      get: { openDocumentError != nil },
      set: { if !$0 { openDocumentError = nil } }
    )
  }

  private var externalConflictIsPresented: Binding<Bool> {
    Binding(
      get: { externalConflictContent != nil },
      set: { _ in }
    )
  }
}
