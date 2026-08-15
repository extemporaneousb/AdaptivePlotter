import Foundation

@testable import PlotterModel

func uuid(_ value: String) -> UUID { UUID(uuidString: value)! }

enum IDs {
  static let program = ProgramID(uuid("00000000-0000-0000-0000-000000000001"))
  static let stroke = StrokeID(uuid("00000000-0000-0000-0000-000000000002"))
  static let pen = PenProfileID(uuid("00000000-0000-0000-0000-00000000000f"))
}

func fieldPoint(_ x: Double, _ y: Double) throws -> Point2<FieldSpace> {
  try Point2(x: x, y: y)
}

func machinePoint(_ x: Double, _ y: Double) throws -> Point2<MachineSpace> {
  try Point2(x: x, y: y)
}

func cameraPoint(_ x: Double, _ y: Double) throws -> Point2<CameraPixelSpace> {
  try Point2(x: x, y: y)
}

func drawingProgram() throws -> DrawingProgram {
  let stroke = LogicalStroke(
    id: IDs.stroke,
    path: try Polyline(points: [try fieldPoint(1, 1), try fieldPoint(4, 4)]),
    style: try StrokeStyle(nominalLineWidth: 0.5, penProfileID: IDs.pen),
    semanticRole: .trainingProbe,
    ordering: 0
  )
  return try DrawingProgram(
    id: IDs.program,
    fieldExtent: Size2(width: 100, height: 100),
    strokes: [stroke],
    source: DrawingSourceProvenance(kind: "café", sourceIdentifier: "probe-1")
  )
}
