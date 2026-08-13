import SwiftUI

enum PresentationMode: String, CaseIterable, Identifiable {
  case write
  case read
  case split

  var id: Self { self }

  var title: String {
    switch self {
    case .write: "Write"
    case .read: "Read"
    case .split: "Split"
    }
  }

  var symbolName: String {
    switch self {
    case .write: "pencil.line"
    case .read: "doc.richtext"
    case .split: "rectangle.split.2x1"
    }
  }
}

struct FocusedDocumentActions {
  var mode: PresentationMode
  var sidebarVisible: Bool
  var inspectorVisible: Bool
  var canFormat: Bool
  var setMode: (PresentationMode) -> Void
  var toggleSidebar: () -> Void
  var toggleInspector: () -> Void
  var showCommandPalette: () -> Void
  var quickOpen: () -> Void
  var searchWorkspace: () -> Void
  var chooseWorkspace: () -> Void
  var exportPDF: () -> Void
  var exportHTML: () -> Void
  var copyHTML: () -> Void
  var formatBold: () -> Void
  var formatItalic: () -> Void
  var formatInlineCode: () -> Void
  var insertLink: () -> Void
}

private struct FocusedDocumentActionsKey: FocusedValueKey {
  typealias Value = FocusedDocumentActions
}

extension FocusedValues {
  var marginDocumentActions: FocusedDocumentActions? {
    get { self[FocusedDocumentActionsKey.self] }
    set { self[FocusedDocumentActionsKey.self] = newValue }
  }
}
