import SwiftUI

struct DocumentInspector: View {
  @Binding var assetStorage: AssetStorageStrategy
  let statistics: DocumentStatistics
  let outline: [OutlineEntry]
  let backlinks: [WorkspaceFile]
  let selectOutlineEntry: (OutlineEntry) -> Void
  let openFile: (WorkspaceFile) -> Void

  var body: some View {
    Form {
      Section("Images") {
        Picker("Storage", selection: $assetStorage) {
          ForEach(AssetStorageStrategy.allCases) { strategy in
            Text(strategy.title).tag(strategy)
          }
        }
      }

      Section("Statistics") {
        LabeledContent("Words", value: statistics.words.formatted())
        LabeledContent("Characters", value: statistics.characters.formatted())
        LabeledContent(
          "Reading",
          value: statistics.readingMinutes == 0
            ? "—"
            : "\(statistics.readingMinutes) min"
        )
      }

      if !outline.isEmpty {
        Section("Outline") {
          ForEach(outline) { entry in
            Button {
              selectOutlineEntry(entry)
            } label: {
              Text(entry.title)
                .lineLimit(1)
                .padding(.leading, CGFloat(max(0, entry.level - 1)) * 9)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }

      if !backlinks.isEmpty {
        Section("Linked From") {
          ForEach(backlinks) { file in
            Button {
              openFile(file)
            } label: {
              Label(file.name, systemImage: "arrow.turn.down.right")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .formStyle(.grouped)
    .inspectorColumnWidth(min: 250, ideal: 280, max: 340)
    .accessibilityLabel("Document inspector")
  }
}
