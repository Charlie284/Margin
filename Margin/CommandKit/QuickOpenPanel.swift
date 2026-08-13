import SwiftUI

enum WorkspacePanelMode {
  case quickOpen
  case search

  var placeholder: String {
    switch self {
    case .quickOpen: "Open a document…"
    case .search: "Search workspace content…"
    }
  }

  var symbol: String {
    switch self {
    case .quickOpen: "doc.text.magnifyingglass"
    case .search: "magnifyingglass"
    }
  }
}

struct WorkspacePanel: View {
  @Binding var isPresented: Bool
  @ObservedObject var workspace: WorkspaceController
  let mode: WorkspacePanelMode
  let openFile: (WorkspaceFile) -> Void
  let openSearchResult: (WorkspaceSearchResult) -> Void
  let chooseFolder: () -> Void

  @State private var query = ""
  @State private var selectedIndex = 0
  @State private var contentSearchResponse = WorkspaceSearchResponse.empty
  @AppStorage("recentWorkspaceFiles") private var recentWorkspaceFiles = ""
  @FocusState private var searchIsFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.18)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }

      VStack(spacing: 0) {
        searchField
        Divider()

        if workspace.rootURL == nil {
          noWorkspace
        } else if case .failed(let message) = workspace.state {
          failureState(message)
        } else if workspace.state == .indexing && workspace.files.isEmpty {
          indexingState
        } else {
          results
        }

        Divider()
        footer
      }
      .frame(width: 650)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.25), radius: 28, y: 14)
      .padding(.top, 78)
    }
    .onAppear { searchIsFocused = true }
    .onChange(of: query) { _, _ in selectedIndex = 0 }
    .task(id: query) { await updateContentSearch() }
    .onKeyPress(.downArrow) {
      moveSelection(by: 1)
      return .handled
    }
    .onKeyPress(.upArrow) {
      moveSelection(by: -1)
      return .handled
    }
    .onExitCommand { dismiss() }
    .transition(
      reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
  }

  private var searchField: some View {
    HStack(spacing: 12) {
      Image(systemName: mode.symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.secondary)
        .frame(width: 20)

      TextField(mode.placeholder, text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .focused($searchIsFocused)
        .onSubmit { executeSelection() }

      if workspace.state == .indexing {
        ProgressView().controlSize(.small)
      } else if !query.isEmpty {
        Button {
          query = ""
        } label: {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear search")
      }
    }
    .padding(.horizontal, 17)
    .frame(height: 56)
  }

  private var noWorkspace: some View {
    ContentUnavailableView {
      Label("Open a Folder", systemImage: "folder")
    } description: {
      Text("Quick Open and workspace search use a local folder of Markdown files.")
    } actions: {
      Button("Choose Folder…") {
        dismiss()
        chooseFolder()
      }
    }
    .frame(height: 240)
  }

  private var indexingState: some View {
    VStack(spacing: 13) {
      ProgressView()
      Text("Indexing \(workspace.rootURL?.lastPathComponent ?? "workspace")…")
        .font(.callout)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 210)
  }

  private func failureState(_ message: String) -> some View {
    ContentUnavailableView {
      Label("Workspace Unavailable", systemImage: "exclamationmark.triangle")
    } description: {
      Text(message)
    } actions: {
      Button("Choose Another Folder…") {
        dismiss()
        chooseFolder()
      }
    }
    .frame(height: 240)
  }

  @ViewBuilder
  private var results: some View {
    if mode == .search, let errorMessage = contentSearchResponse.errorMessage {
      ContentUnavailableView {
        Label("Invalid Search", systemImage: "exclamationmark.triangle")
      } description: {
        Text(errorMessage)
      }
      .frame(height: 220)
    } else if resultCount == 0 {
      ContentUnavailableView.search(text: query)
        .frame(height: 220)
    } else {
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 3) {
            switch mode {
            case .quickOpen:
              ForEach(Array(fileResults.enumerated()), id: \.element.id) { index, file in
                fileRow(file, selected: selectedIndex == index)
                  .id(file.id)
                  .onTapGesture { execute(file) }
              }
            case .search:
              ForEach(Array(contentResults.enumerated()), id: \.element.id) { index, result in
                contentRow(result, selected: selectedIndex == index)
                  .id(result.id)
                  .onTapGesture { execute(result) }
              }
            }
          }
          .padding(7)
        }
        .frame(maxHeight: 430)
        .onChange(of: selectedIndex) { _, index in
          guard let id = resultIdentifier(at: index) else { return }
          proxy.scrollTo(id)
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      Text(workspace.rootURL?.lastPathComponent ?? "No workspace")
        .lineLimit(1)
      if workspace.state == .ready {
        Text("\(workspace.files.count) files")
      }
      if !workspace.warnings.isEmpty {
        Text("\(workspace.warnings.count) indexing warnings")
          .help(workspace.warnings.map(\.description).joined(separator: "\n"))
      }
      Spacer()
      if mode == .search {
        Text("Use /pattern/ for regex")
      }
      Text("↑↓  Navigate   ↩  Open   esc")
    }
    .font(.caption)
    .foregroundStyle(.tertiary)
    .padding(.horizontal, 15)
    .frame(height: 38)
  }

  private var fileResults: [WorkspaceFile] {
    let results = workspace.matchingFiles(query)
    guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return results }

    let recent = recentWorkspaceFiles.split(separator: "\n").map(String.init)
    return results.sorted { left, right in
      let leftIndex = recent.firstIndex(of: left.id) ?? Int.max
      let rightIndex = recent.firstIndex(of: right.id) ?? Int.max
      return leftIndex == rightIndex
        ? left.relativePath.localizedStandardCompare(right.relativePath) == .orderedAscending
        : leftIndex < rightIndex
    }
  }

  private var contentResults: [WorkspaceSearchResult] {
    contentSearchResponse.results
  }

  private func updateContentSearch() async {
    guard mode == .search else {
      contentSearchResponse = .empty
      return
    }
    do {
      try await Task.sleep(for: .milliseconds(80))
    } catch {
      return
    }
    let searchedQuery = query
    let response = await WorkspaceSearchEngine.search(workspace.searchIndex, query: searchedQuery)
    guard !Task.isCancelled, query == searchedQuery else { return }
    contentSearchResponse = response
  }

  private var resultCount: Int {
    switch mode {
    case .quickOpen: fileResults.count
    case .search: contentResults.count
    }
  }

  private func fileRow(_ file: WorkspaceFile, selected: Bool) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "doc.text")
        .foregroundStyle(selected ? Color.white : Color.secondary)
        .frame(width: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(file.name)
          .foregroundStyle(selected ? Color.white : Color.primary)
        if !file.directory.isEmpty {
          Text(file.directory)
            .font(.caption)
            .foregroundStyle(selected ? Color.white.opacity(0.7) : Color.secondary)
        }
      }
      Spacer()
    }
    .padding(.horizontal, 11)
    .frame(minHeight: file.directory.isEmpty ? 40 : 48)
    .background(selected ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .contentShape(Rectangle())
  }

  private func contentRow(_ result: WorkspaceSearchResult, selected: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "text.magnifyingglass")
        .foregroundStyle(selected ? Color.white : Color.secondary)
        .frame(width: 20)
        .padding(.top, 2)

      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 7) {
          Text(result.file.name).fontWeight(.medium)
          Text("Line \(result.line)")
            .font(.caption)
            .foregroundStyle(
              selected ? Color.white.opacity(0.68) : Color.secondary.opacity(0.72)
            )
        }
        Text(result.excerpt)
          .font(.callout)
          .lineLimit(2)
          .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
      }
      Spacer()
    }
    .padding(11)
    .background(selected ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .contentShape(Rectangle())
  }

  private func moveSelection(by offset: Int) {
    guard resultCount > 0 else { return }
    selectedIndex = (selectedIndex + offset + resultCount) % resultCount
  }

  private func executeSelection() {
    switch mode {
    case .quickOpen:
      guard fileResults.indices.contains(selectedIndex) else { return }
      execute(fileResults[selectedIndex])
    case .search:
      guard contentResults.indices.contains(selectedIndex) else { return }
      execute(contentResults[selectedIndex])
    }
  }

  private func execute(_ file: WorkspaceFile) {
    remember(file)
    dismiss()
    DispatchQueue.main.async { openFile(file) }
  }

  private func execute(_ result: WorkspaceSearchResult) {
    remember(result.file)
    dismiss()
    DispatchQueue.main.async { openSearchResult(result) }
  }

  private func remember(_ file: WorkspaceFile) {
    var recent = recentWorkspaceFiles.split(separator: "\n").map(String.init)
    recent.removeAll { $0 == file.id }
    recent.insert(file.id, at: 0)
    recentWorkspaceFiles = recent.prefix(16).joined(separator: "\n")
  }

  private func resultIdentifier(at index: Int) -> String? {
    switch mode {
    case .quickOpen:
      return fileResults.indices.contains(index) ? fileResults[index].id : nil
    case .search:
      return contentResults.indices.contains(index) ? contentResults[index].id : nil
    }
  }

  private func dismiss() {
    isPresented = false
  }
}
