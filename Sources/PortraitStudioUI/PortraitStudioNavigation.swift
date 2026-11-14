import SwiftUI
import PortraitArtists
import PortraitCore

/// Standalone destinations deliberately do not rename the shared Plotter route.
package enum PortraitStudioDestination: String, CaseIterable, Sendable {
  case booth, photos, drawing
  package var title: String {
    switch self { case .booth: "Photo Booth"; case .photos: "Photos"; case .drawing: "Drawing" }
  }
  package static func restored(_ value: String, route: DrawingLibraryRoute, hasSavedRoute: Bool) -> Self {
    if let destination = Self(rawValue: value) { return destination }
    guard hasSavedRoute else { return .booth }
    return route.workspace == .drawingStudio ? .drawing : .photos
  }
}

/// The production header is also hosted directly by native acceptance tests.
package struct PortraitStudioHeader: View {
  @Binding package var destination: PortraitStudioDestination
  package let canSend: Bool
  package var sendReason: String?
  package let send: () -> Void
  package init(destination: Binding<PortraitStudioDestination>, canSend: Bool, sendReason: String? = nil, send: @escaping () -> Void) {
    _destination = destination; self.canSend = canSend; self.sendReason = sendReason; self.send = send
  }
  package var body: some View {
    HStack(spacing: 6) {
      ForEach(PortraitStudioDestination.allCases, id: \.self) { item in
        Button(item.title) { destination = item }
          .buttonStyle(.bordered)
          .tint(destination == item ? .accentColor : nil)
          .accessibilityIdentifier("portraitStudio.destination.\(item.rawValue)")
          .accessibilityAddTraits(destination == item ? .isSelected : [])
      }
      Spacer(minLength: 24)
      Button("Send to Plotter", systemImage: "paperplane") { if canSend { send() } }
        .disabled(!canSend)
        .help(sendReason ?? "Open this exact drawing as a preview in Plotter.")
        .accessibilityIdentifier("portraitStudio.send")
    }.padding(12)
  }
}

package struct PortraitStudioFileActions {
  package var canImport: Bool
  package var canExport: Bool
  package var importPhotos: (Bool) -> Void
  package var export: () -> Void
  package init(canImport: Bool, canExport: Bool, importPhotos: @escaping (Bool) -> Void, export: @escaping () -> Void) {
    self.canImport = canImport; self.canExport = canExport; self.importPhotos = importPhotos; self.export = export
  }
}
private struct PortraitStudioFileActionsKey: FocusedValueKey { typealias Value = PortraitStudioFileActions }
extension FocusedValues {
  package var portraitStudioFileActions: PortraitStudioFileActions? {
    get { self[PortraitStudioFileActionsKey.self] }
    set { self[PortraitStudioFileActionsKey.self] = newValue }
  }
}
package struct PortraitStudioFileCommands: Commands {
  @FocusedValue(\.portraitStudioFileActions) private var actions
  package init() {}
  package var body: some Commands {
    CommandGroup(after: .newItem) {
      Button("Import Photo…") { actions?.importPhotos(false) }.keyboardShortcut("i", modifiers: .command)
        .disabled(actions?.canImport != true)
      Button("Import Photo Set…") { actions?.importPhotos(true) }.keyboardShortcut("i", modifiers: [.command, .shift])
        .disabled(actions?.canImport != true)
      Divider()
      Button("Export Drawing…") { actions?.export() }.disabled(actions?.canExport != true)
    }
  }
}

/// A transient generated-selection lease. Returning to the same saved drawing
/// does not revive an earlier asynchronous send intent.
@MainActor
package struct PortraitStudioGeneratedHandoffSelection {
  private let intent: UInt64
  private let candidate: UUID
  private let prune: UUID?
  private let photo: PhotoRef?
  private let options: PortraitAnalysisOptions
  package init?(model: FlowAuthoringModel) {
    guard model.canSendToPlotter, let candidate = model.candidate else { return nil }
    intent = model.generationIntentRevision; self.candidate = candidate.id
    prune = model.prune?.id; photo = model.currentPhotoRef; options = model.committedAnalysisOptions
  }
  package func isCurrent(in model: FlowAuthoringModel) -> Bool {
    model.generationIntentRevision == intent && model.candidate?.id == candidate
      && model.prune?.id == prune && model.currentPhotoRef == photo
      && model.committedAnalysisOptions == options && model.canSendToPlotter
  }
}
