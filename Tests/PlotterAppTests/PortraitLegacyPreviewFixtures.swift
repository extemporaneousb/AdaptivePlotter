// Historical fixture-only rendering. Production uses PortraitPlaneProgramPreview.
import PlotterModel
import SwiftUI
@testable import PlotterApp

struct PortraitProgramPreview: View {
  let program: DrawingProgram?
  var inkWidth: Double?
  var drawingHeight: Double = 100
  var body: some View {
    Canvas { context, size in
      guard let program else { return }
      let scale = max(0, min((size.width-24)/program.fieldExtent.width,
                            (size.height-24)/program.fieldExtent.height))
      let origin = CGPoint(x: (size.width-program.fieldExtent.width*scale)/2,
                           y: (size.height-program.fieldExtent.height*scale)/2)
      for stroke in program.strokes {
        var path = Path()
        for (index, point) in stroke.path.points.enumerated() {
          let location = CGPoint(x: origin.x+point.x*scale,
                                 y: origin.y+(program.fieldExtent.height-point.y)*scale)
          if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        let width = (inkWidth ?? stroke.style.nominalLineWidth) * scale
          * program.fieldExtent.height / max(1, drawingHeight)
        context.stroke(path, with: .color(.black),
          style: SwiftUI.StrokeStyle(lineWidth: max(0.2, width), lineCap: .round, lineJoin: .round))
      }
    }
    .background(.white)
    .border(.quaternary)
    .accessibilityLabel("Portrait drawing preview")
  }
}

/// Preview and label presentation share one resolution of explicit overrides.
/// A width override is a visual estimate, even when its source material carries
/// independently measured evidence.
enum PortraitPreviewPresentation {
  static func context(material: PortraitMaterialContext?, nominalWidthMM: Double,
    widthOverrideMM: Double? = nil, heightOverrideMM: Double? = nil) -> PortraitPresentationContext? {
    try? PortraitPresentationContext(
      drawingHeightMM: heightOverrideMM ?? material?.drawingHeightMM ?? 100,
      inkWidthMM: widthOverrideMM ?? material?.profile.conservativeWidthMM ?? nominalWidthMM,
      inkWidthIsMeasured: widthOverrideMM == nil && material?.profile.independentlyMeasured == true,
      materialRevision: material?.profile.key, objective: .screenAesthetic,
      prompt: "Rate likeness and drawing quality as displayed")
  }
}
