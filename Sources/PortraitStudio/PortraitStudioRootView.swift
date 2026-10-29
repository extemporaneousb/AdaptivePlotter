import SwiftUI
import PortraitLibrary
import PortraitStudioUI

/// Historical composition callers enter the same dojo; experimental workspaces
/// no longer form alternative authoring paths.
struct PortraitStudioRootView: View {
  @Bindable var composition: PortraitStudioComposition
  var body: some View {
    PortraitStudioView(model: composition.model, strokeStyle: composition.strokeStyle,
      showOnPlotter: { await composition.exportDrawing(SavedDrawing(candidate: $0)) },
      showEditedOnPlotter: { await composition.exportDrawing($0) },
      selectCamera: { await composition.selectCamera() },
      handoffTitle: "Export Drawing", handoffErrorTitle: "Drawing export failed",
      handoffActionID: "portrait.exportDrawing", handoffHelp: "Export the exact drawing for AdaptivePlotter.")
  }
}
