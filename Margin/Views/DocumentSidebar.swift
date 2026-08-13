import SwiftUI

struct DocumentSidebar: View {
  let fileURL: URL?
  let outline: [OutlineEntry]
  @ObservedObject var workspace: WorkspaceController
  let selectOutlineEntry: (OutlineEntry) -> Void
  let chooseWorkspace: () -> Void
  let openFile: (WorkspaceFile) -> Void

  @State private var filter = ""

  var body: some View {
    List {
      Section("Workspace") {
        if let rootURL = workspace.rootURL {
          Label {
            VStack(alignment: .leading, spacing: 2) {
              Text(rootURL.lastPathComponent)
                .fontWeight(.medium)
                .lineLimit(1)
              Text("\(workspace.files.count) Markdown files")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          } icon: {
            Image(systemName: "folder.fill")
              .foregroundStyle(.secondary)
          }
          .contextMenu {
            Button("Refresh") { workspace.refresh() }
            Button("Close Workspace") { workspace.close() }
          }

          if workspace.state == .indexing {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text("Indexing…").foregroundStyle(.secondary)
            }
            .font(.caption)
          }

          if case .failed(let message) = workspace.state {
            Label(message, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
          } else if !workspace.warnings.isEmpty {
            Label(
              "\(workspace.warnings.count) indexing warnings",
              systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(workspace.warnings.map(\.description).joined(separator: "\n"))
          }

          ForEach(filteredWorkspaceFiles.prefix(150)) { file in
            Button {
              openFile(file)
            } label: {
              HStack(spacing: 8) {
                Image(systemName: "doc.text")
                  .foregroundStyle(.tertiary)
                VStack(alignment: .leading, spacing: 1) {
                  Text(file.name).lineLimit(1)
                  if !file.directory.isEmpty {
                    Text(file.directory)
                      .font(.caption2)
                      .foregroundStyle(.tertiary)
                      .lineLimit(1)
                  }
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        } else {
          Button {
            chooseWorkspace()
          } label: {
            Label("Open Folder…", systemImage: "folder.badge.plus")
          }
        }
      }

      Section("Document") {
        Label {
          VStack(alignment: .leading, spacing: 2) {
            Text(fileURL?.lastPathComponent ?? "Untitled")
              .lineLimit(1)
            if let path = fileURL?.deletingLastPathComponent().lastPathComponent {
              Text(path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }
        } icon: {
          Image(systemName: "doc.text")
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
      }

      Section("Outline") {
        if outline.isEmpty {
          Text("Add a heading to build an outline.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .listRowSeparator(.hidden)
            .padding(.vertical, 4)
        } else {
          ForEach(outline) { entry in
            Button {
              selectOutlineEntry(entry)
            } label: {
              Text(entry.title)
                .lineLimit(1)
                .padding(.leading, CGFloat(max(0, entry.level - 1)) * 11)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go to \(entry.title), heading level \(entry.level)")
          }
        }
      }
    }
    .listStyle(.sidebar)
    .searchable(text: $filter, placement: .sidebar, prompt: "Filter files")
    .navigationSplitViewColumnWidth(min: 185, ideal: 224, max: 310)
    .accessibilityLabel("Document sidebar")
  }

  private var filteredWorkspaceFiles: [WorkspaceFile] {
    workspace.matchingFiles(filter)
  }
}
