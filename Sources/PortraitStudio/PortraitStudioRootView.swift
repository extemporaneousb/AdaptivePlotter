import AppKit
import SwiftUI
import PortraitLibrary
import PortraitStudioUI

struct PortraitStudioRootView: View {
  @Bindable var composition: PortraitStudioComposition

  var body: some View {
    VStack(spacing: 0) {
      if composition.showsLibrary {
        PortraitStudioLibraryView(composition: composition)
      } else {
        PortraitStudioView(model: composition.model, strokeStyle: composition.strokeStyle,
          showOnPlotter: { candidate in
            await composition.exportDrawing(SavedDrawing(candidate: candidate))
          }, selectCamera: { await composition.selectCamera() },
          openReviewer: { _ in composition.showsLibrary = true },
          handoffTitle: "Export Drawing", handoffErrorTitle: "Drawing export failed",
          handoffActionID: "portrait.exportDrawing",
          handoffHelp: "Export Drawing writes the exact saved drawing and retained source to a portable file. Import it in AdaptivePlotter to place and review it before any machine execution.")
          .padding()
      }
    }
    .disabled(composition.isClosing)
    .background {
      PortraitScreenIllumination(isActive: composition.model.screenIlluminationActive) {
        Task { await composition.model.cancelRendering() }
      }
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Picker("Workspace", selection: $composition.showsLibrary) {
          Label("Studio", systemImage: "pencil.and.outline").tag(false)
          Label("Library", systemImage: "books.vertical").tag(true)
        }.pickerStyle(.segmented)
      }
      ToolbarItemGroup {
        Button("Import Drawing", systemImage: "square.and.arrow.down") { composition.importFile(attachment: false) }
        Button("Import Plot Attachment", systemImage: "photo.badge.arrow.down") { composition.importFile(attachment: true) }
      }
    }
    .alert("Portrait Studio", isPresented: Binding(
      get: { composition.message != nil }, set: { if !$0 { composition.message = nil } })) {
      Button("OK", role: .cancel) { composition.message = nil }
    } message: { Text(composition.message ?? "") }
  }
}
