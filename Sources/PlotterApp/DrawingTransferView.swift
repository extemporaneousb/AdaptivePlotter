import PortraitStudioUI
import PortraitCore
import SwiftUI

/// The embedded route borrows the application's existing collection. Shared UI
/// owns only its sheet/request lifetime, never another drawing selection.
struct DrawingTransferView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  @Binding var route: DrawingLibraryRoute
  var openStudio: (PhotoRef) async -> String? = { _ in nil }
  var projected: () -> Void = {}
  init(application: PlotterApplicationRuntime, close: @escaping () -> Void,
    route: Binding<DrawingLibraryRoute> = .constant(.init()),
    openStudio: @escaping (PhotoRef) async -> String? = { _ in nil }, projected: @escaping () -> Void = {}) {
    self.application = application; self.close = close; _route = route
    self.openStudio = openStudio; self.projected = projected
  }
  var browser: DrawingLibraryBrowser {
    DrawingLibraryBrowser(sketches: application.portraitStudio.sketches, close: close, handoff: { drawing, request in
      let error = await application.projectDrawing(drawing, isStillCurrent: { request.isCurrent })
      if error == nil, request.isCurrent { projected() }
      return error
    }, route: $route, openStudio: openStudio, review: { drawing in
      AnyView(DrawingReviewerView(application: application, drawing: drawing).id(drawing.reference))
    })
  }
  var body: some View { browser }
}
