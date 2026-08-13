import SwiftUI

struct PaletteCommand: Identifiable {
  let id: String
  let title: String
  let subtitle: String?
  let symbol: String
  let shortcut: String?
  let aliases: [String]
  let action: () -> Void

  init(
    id: String,
    title: String,
    subtitle: String? = nil,
    symbol: String,
    shortcut: String? = nil,
    aliases: [String] = [],
    action: @escaping () -> Void
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.symbol = symbol
    self.shortcut = shortcut
    self.aliases = aliases
    self.action = action
  }
}

enum CommandMatcher {
  static func score(query: String, title: String, aliases: [String] = []) -> Int? {
    let normalizedQuery = normalize(query)
    guard !normalizedQuery.isEmpty else { return 0 }

    return ([title] + aliases)
      .compactMap { fuzzyScore(query: normalizedQuery, candidate: normalize($0)) }
      .max()
  }

  private static func fuzzyScore(query: String, candidate: String) -> Int? {
    if candidate == query { return 10_000 }
    if candidate.hasPrefix(query) { return 8_000 - candidate.count }
    if candidate.contains(query) { return 6_000 - candidate.count }

    var queryIndex = query.startIndex
    var previousMatch: String.Index?
    var score = 0

    for candidateIndex in candidate.indices where queryIndex < query.endIndex {
      guard candidate[candidateIndex] == query[queryIndex] else { continue }

      score += 100
      if let previousMatch, candidate.distance(from: previousMatch, to: candidateIndex) == 1 {
        score += 45
      }
      if candidateIndex == candidate.startIndex
        || candidate[candidate.index(before: candidateIndex)] == " "
      {
        score += 35
      }

      previousMatch = candidateIndex
      query.formIndex(after: &queryIndex)
    }

    guard queryIndex == query.endIndex else { return nil }
    return score - candidate.count
  }

  private static func normalize(_ value: String) -> String {
    value
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

struct CommandPalette: View {
  @Binding var isPresented: Bool
  let commands: [PaletteCommand]

  @State private var query = ""
  @State private var selectedIndex = 0
  @AppStorage("recentCommandIdentifiers") private var recentCommandIdentifiers = ""
  @FocusState private var searchIsFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.18)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }

      VStack(spacing: 0) {
        HStack(spacing: 12) {
          Image(systemName: "command")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 20)

          TextField("Search commands…", text: $query)
            .textFieldStyle(.plain)
            .font(.system(size: 16))
            .focused($searchIsFocused)
            .onSubmit { executeSelection() }

          if !query.isEmpty {
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

        Divider()

        if filteredCommands.isEmpty {
          ContentUnavailableView.search(text: query)
            .frame(height: 180)
        } else {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(spacing: 3) {
                ForEach(Array(filteredCommands.enumerated()), id: \.element.id) { index, command in
                  commandRow(command, selected: selectedIndex == index)
                    .id(command.id)
                    .onTapGesture { execute(command) }
                }
              }
              .padding(7)
            }
            .frame(maxHeight: 360)
            .onChange(of: selectedIndex) { _, index in
              guard filteredCommands.indices.contains(index) else { return }
              proxy.scrollTo(filteredCommands[index].id)
            }
          }
        }

        Divider()

        HStack(spacing: 15) {
          paletteHint(keys: ["↑", "↓"], label: "Navigate")
          paletteHint(keys: ["↩"], label: "Open")
          Spacer()
          Text("esc")
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 15)
        .frame(height: 38)
      }
      .frame(width: 590)
      .background(.regularMaterial)
      .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .stroke(Color.primary.opacity(0.12), lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.25), radius: 28, y: 14)
      .padding(.top, 82)
    }
    .onAppear {
      searchIsFocused = true
      selectedIndex = 0
    }
    .onChange(of: query) { _, _ in selectedIndex = 0 }
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

  private var filteredCommands: [PaletteCommand] {
    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      let recent = recentCommandIdentifiers.split(separator: ",").map(String.init)
      return commands.sorted { left, right in
        let leftIndex = recent.firstIndex(of: left.id) ?? Int.max
        let rightIndex = recent.firstIndex(of: right.id) ?? Int.max
        return leftIndex == rightIndex ? left.title < right.title : leftIndex < rightIndex
      }
    }

    return commands.compactMap { command -> (PaletteCommand, Int)? in
      guard
        let score = CommandMatcher.score(
          query: query,
          title: command.title,
          aliases: command.aliases
        )
      else { return nil }
      return (command, score)
    }
    .sorted { left, right in
      left.1 == right.1 ? left.0.title < right.0.title : left.1 > right.1
    }
    .map(\.0)
  }

  private func commandRow(_ command: PaletteCommand, selected: Bool) -> some View {
    HStack(spacing: 12) {
      Image(systemName: command.symbol)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(selected ? Color.white : Color.secondary)
        .frame(width: 21)

      VStack(alignment: .leading, spacing: 2) {
        Text(command.title)
          .foregroundStyle(selected ? Color.white : Color.primary)
        if let subtitle = command.subtitle {
          Text(subtitle)
            .font(.caption)
            .foregroundStyle(selected ? Color.white.opacity(0.72) : Color.secondary)
        }
      }

      Spacer()

      if let shortcut = command.shortcut {
        Text(shortcut)
          .font(.system(size: 12, weight: .medium, design: .rounded))
          .foregroundStyle(
            selected ? Color.white.opacity(0.78) : Color.secondary.opacity(0.72)
          )
      }
    }
    .padding(.horizontal, 11)
    .frame(minHeight: command.subtitle == nil ? 40 : 48)
    .background(selected ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private func paletteHint(keys: [String], label: String) -> some View {
    HStack(spacing: 5) {
      ForEach(keys, id: \.self) { key in
        Text(key)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .frame(minWidth: 16, minHeight: 16)
          .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
      }
      Text(label).font(.caption).foregroundStyle(.secondary)
    }
  }

  private func moveSelection(by offset: Int) {
    guard !filteredCommands.isEmpty else { return }
    selectedIndex = (selectedIndex + offset + filteredCommands.count) % filteredCommands.count
  }

  private func executeSelection() {
    guard filteredCommands.indices.contains(selectedIndex) else { return }
    execute(filteredCommands[selectedIndex])
  }

  private func execute(_ command: PaletteCommand) {
    var identifiers = recentCommandIdentifiers.split(separator: ",").map(String.init)
    identifiers.removeAll { $0 == command.id }
    identifiers.insert(command.id, at: 0)
    recentCommandIdentifiers = identifiers.prefix(8).joined(separator: ",")
    dismiss()
    DispatchQueue.main.async { command.action() }
  }

  private func dismiss() {
    isPresented = false
  }
}
