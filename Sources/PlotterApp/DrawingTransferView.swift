import PortraitStudioUI
import SwiftUI

/// The embedded route borrows the application's existing collection. Shared UI
/// owns only its sheet/request lifetime, never another drawing selection.
struct DrawingTransferView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  var browser: DrawingLibraryBrowser {
    DrawingLibraryBrowser(sketches: application.portraitStudio.sketches, close: close, handoff: { drawing, request in
      await application.projectDrawing(drawing, isStillCurrent: { request.isCurrent })
    })
  }
  var body: some View { browser }
}
