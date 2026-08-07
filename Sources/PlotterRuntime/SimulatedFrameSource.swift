import Foundation
import PlotterModel

public struct SimulatedCameraStroke: Hashable, Sendable {
  public let start: Point2<CameraPixelSpace>
  public let end: Point2<CameraPixelSpace>
  public let green: UInt8

  public init(
    start: Point2<CameraPixelSpace>,
    end: Point2<CameraPixelSpace>,
    green: UInt8 = 180
  ) {
    self.start = start
    self.end = end
    self.green = green
  }
}

public enum SimulatedFrameSourceError: Error, Equatable, Sendable {
  case invalidDimensions
  case emptyScenarioIdentifier
  case pathPointCountMismatch
}

public enum SimulatedOverlayLayerKind: String, Codable, CaseIterable, Hashable, Sendable {
  case logical
  case predicted
  case observed
  case residuals
  case cap
  case frameSides
  case drawingFrame
  case armature
  case penState

  public var overlayKind: CameraOverlayKind? {
    switch self {
    case .logical: .intendedPath
    case .predicted: .modelPrediction
    case .observed: .observedInk
    case .residuals: .residual
    case .cap: .penCap
    case .frameSides: .measuredFrameSide
    case .drawingFrame: .drawingFrameEstimate
    case .armature: .armatureEstimate
    case .penState: nil
    }
  }

  public var overlaySource: CameraOverlaySource {
    switch self {
    case .logical: .planned
    case .predicted: .inferred
    case .observed, .residuals, .cap, .frameSides, .drawingFrame, .armature, .penState:
      .simulated
    }
  }
}

public enum SimulatedOverlayLayerData: Hashable, Sendable {
  case geometry([CameraOverlayMeasurement])
  case penState(PenState)
}

public struct SimulatedOverlayLayer: Hashable, Sendable {
  public let kind: SimulatedOverlayLayerKind
  public let data: SimulatedOverlayLayerData

  public init(kind: SimulatedOverlayLayerKind, data: SimulatedOverlayLayerData) {
    self.kind = kind
    self.data = data
  }
}

/// Input to the no-hardware model-mismatch simulator. The logical path is the
/// desired field geometry, the accepted model predicts the command outcome,
/// and the ground-truth model generates explicitly simulated observations.
public struct SimulatedModelMismatchScene: Hashable, Sendable {
  public let scenarioID: String
  public let logicalFieldPath: Polyline<FieldSpace>
  public let commandedMachinePath: Polyline<MachineSpace>
  public let acceptedModel: AcceptedDrawingModelSnapshot
  public let simulatedGroundTruthTransform: DrawingTransform
  public let capFieldPoint: Point2<FieldSpace>
  public let frameFieldBounds: AxisAlignedBounds<FieldSpace>
  public let armatureFieldBounds: AxisAlignedBounds<FieldSpace>
  public let penState: PenState

  public init(
    scenarioID: String,
    logicalFieldPath: Polyline<FieldSpace>,
    commandedMachinePath: Polyline<MachineSpace>,
    acceptedModel: AcceptedDrawingModelSnapshot,
    simulatedGroundTruthTransform: DrawingTransform,
    capFieldPoint: Point2<FieldSpace>,
    frameFieldBounds: AxisAlignedBounds<FieldSpace>,
    armatureFieldBounds: AxisAlignedBounds<FieldSpace>,
    penState: PenState
  ) throws {
    guard !scenarioID.isEmpty else { throw SimulatedFrameSourceError.emptyScenarioIdentifier }
    guard logicalFieldPath.points.count == commandedMachinePath.points.count else {
      throw SimulatedFrameSourceError.pathPointCountMismatch
    }
    self.scenarioID = scenarioID
    self.logicalFieldPath = logicalFieldPath
    self.commandedMachinePath = commandedMachinePath
    self.acceptedModel = acceptedModel
    self.simulatedGroundTruthTransform = simulatedGroundTruthTransform
    self.capFieldPoint = capFieldPoint
    self.frameFieldBounds = frameFieldBounds
    self.armatureFieldBounds = armatureFieldBounds
    self.penState = penState
  }
}

public struct SimulatedOverlaySceneContent: Hashable, Sendable {
  public static let evidenceLabel = "SIMULATED — NOT PHYSICAL EVIDENCE"

  public let scenarioID: String
  public let displayedFrame: DisplayedFrame
  public let layers: [SimulatedOverlayLayer]

  public init(
    scenarioID: String,
    displayedFrame: DisplayedFrame,
    layers: [SimulatedOverlayLayer]
  ) {
    self.scenarioID = scenarioID
    self.displayedFrame = displayedFrame
    self.layers = layers
  }

  public var overlays: [CameraOverlayMeasurement] {
    layers.flatMap { layer -> [CameraOverlayMeasurement] in
      guard case .geometry(let measurements) = layer.data else { return [] }
      return measurements
    }
  }

  public var penState: PenState? {
    layers.compactMap { layer in
      guard case .penState(let state) = layer.data else { return nil }
      return state
    }.first
  }

  public var isPhysicalEvidence: Bool { false }
}

/// A deterministic production frame source for the same renderer and vision
/// path as a live camera. It has no machine-link dependency and cannot create a
/// controller or physical-motion outcome.
public struct SimulatedFrameSource: Sendable {
  public let width: Int
  public let height: Int
  public let cameraConfigurationID: CameraConfigurationID
  public let fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>
  public private(set) var sequence: UInt64
  private var lastTimestamp: UInt64

  public init(
    width: Int,
    height: Int,
    fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>,
    cameraConfigurationID: CameraConfigurationID = CameraConfigurationID(),
    initialSequence: UInt64 = 1
  ) throws {
    guard width > 0, height > 0 else { throw SimulatedFrameSourceError.invalidDimensions }
    self.width = width
    self.height = height
    self.fieldToCamera = fieldToCamera
    self.cameraConfigurationID = cameraConfigurationID
    sequence = initialSequence
    lastTimestamp = 0
  }

  public mutating func render(
    strokes: [SimulatedCameraStroke],
    captureNanoseconds: UInt64? = nil
  ) throws -> DisplayedFrame {
    let proposedTimestamp = captureNanoseconds ?? DispatchTime.now().uptimeNanoseconds
    let timestamp = max(proposedTimestamp, lastTimestamp &+ 1)
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for stroke in strokes { draw(stroke, into: &pixels) }
    let frame = try StampedFrame(
      id: FrameID(rawValue: "simulated-\(cameraConfigurationID)-\(sequence)"),
      sequence: sequence,
      captureNanoseconds: timestamp,
      cameraConfigurationID: cameraConfigurationID,
      width: width,
      height: height,
      rowBytes: width * 4,
      pixelFormat: .bgra8,
      bytes: OwnedFrameBytes(pixels)
    )
    sequence &+= 1
    lastTimestamp = timestamp
    return DisplayedFrame(source: .simulated, frame: frame)
  }

  public func cameraPolyline(from fieldPolyline: Polyline<FieldSpace>) throws
    -> Polyline<CameraPixelSpace>
  {
    try fieldToCamera.applying(to: fieldPolyline)
  }

  /// Renders simulated ink plus the complete overlay contract in one operation.
  /// Every measurement is bound to the exact generated frame identity.
  public mutating func renderModelMismatch(
    _ scene: SimulatedModelMismatchScene,
    captureNanoseconds: UInt64? = nil
  ) throws -> SimulatedOverlaySceneContent {
    let predicted = try scene.acceptedModel.predictedFieldPath(
      for: scene.commandedMachinePath
    )
    let observed = try scene.simulatedGroundTruthTransform.predictedFieldPath(
      for: scene.commandedMachinePath
    )
    let observedCamera = try cameraPolyline(from: observed)
    let strokes = zip(observedCamera.points, observedCamera.points.dropFirst()).map {
      SimulatedCameraStroke(start: $0.0, end: $0.1, green: 210)
    }
    let displayedFrame = try render(
      strokes: strokes,
      captureNanoseconds: captureNanoseconds
    )
    let logicalMeasurement = measurement(
      geometry: .polyline(try cameraPolyline(from: scene.logicalFieldPath)),
      kind: .logical,
      scene: scene,
      displayedFrame: displayedFrame
    )
    let predictedMeasurement = measurement(
      geometry: .polyline(try cameraPolyline(from: predicted)),
      kind: .predicted,
      scene: scene,
      displayedFrame: displayedFrame
    )
    let observedMeasurement = measurement(
      geometry: .polyline(observedCamera),
      kind: .observed,
      scene: scene,
      displayedFrame: displayedFrame
    )
    let residualMeasurements = try zip(predicted.points, observed.points).map {
      measurement(
        geometry: try residualGeometry(predicted: $0.0, observed: $0.1),
        kind: .residuals,
        scene: scene,
        displayedFrame: displayedFrame
      )
    }
    let capMeasurement = measurement(
      geometry: .point(try fieldToCamera.applying(to: scene.capFieldPoint)),
      kind: .cap,
      scene: scene,
      displayedFrame: displayedFrame
    )
    let frameCorners = scene.frameFieldBounds.corners
    let measuredFrameSides = try Polyline<FieldSpace>(
      points: [frameCorners[0], frameCorners[1], frameCorners[2]]
    )
    let frameSidesMeasurement = measurement(
      geometry: .polyline(try cameraPolyline(from: measuredFrameSides)),
      kind: .frameSides,
      scene: scene,
      displayedFrame: displayedFrame
    )
    let closedDrawingFrame = try Polyline<FieldSpace>(
      points: frameCorners + [frameCorners[0]]
    )
    let drawingFrameMeasurement = measurement(
      geometry: .polyline(try cameraPolyline(from: closedDrawingFrame)),
      kind: .drawingFrame,
      scene: scene,
      displayedFrame: displayedFrame
    )
    let closedArmature = try Polyline<FieldSpace>(
      points: scene.armatureFieldBounds.corners + [scene.armatureFieldBounds.corners[0]]
    )
    let armatureMeasurement = measurement(
      geometry: .polyline(try cameraPolyline(from: closedArmature)),
      kind: .armature,
      scene: scene,
      displayedFrame: displayedFrame
    )
    return SimulatedOverlaySceneContent(
      scenarioID: scene.scenarioID,
      displayedFrame: displayedFrame,
      layers: [
        SimulatedOverlayLayer(kind: .logical, data: .geometry([logicalMeasurement])),
        SimulatedOverlayLayer(kind: .predicted, data: .geometry([predictedMeasurement])),
        SimulatedOverlayLayer(kind: .observed, data: .geometry([observedMeasurement])),
        SimulatedOverlayLayer(kind: .residuals, data: .geometry(residualMeasurements)),
        SimulatedOverlayLayer(kind: .cap, data: .geometry([capMeasurement])),
        SimulatedOverlayLayer(kind: .frameSides, data: .geometry([frameSidesMeasurement])),
        SimulatedOverlayLayer(kind: .drawingFrame, data: .geometry([drawingFrameMeasurement])),
        SimulatedOverlayLayer(kind: .armature, data: .geometry([armatureMeasurement])),
        SimulatedOverlayLayer(kind: .penState, data: .penState(scene.penState)),
      ]
    )
  }

  private func measurement(
    geometry: CameraPixelGeometry,
    kind: SimulatedOverlayLayerKind,
    scene: SimulatedModelMismatchScene,
    displayedFrame: DisplayedFrame
  ) -> CameraOverlayMeasurement {
    guard let overlayKind = kind.overlayKind else {
      preconditionFailure("Pen state is not camera geometry.")
    }
    return CameraOverlayMeasurement(
      frameID: displayedFrame.frame.id,
      cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
      geometry: geometry,
      provenance: CameraMeasurementProvenance(
        kind: overlayKind,
        source: kind.overlaySource,
        algorithmRevision: "deterministic-model-mismatch-v1:\(scene.scenarioID)"
      )
    )
  }

  private func residualGeometry(
    predicted: Point2<FieldSpace>,
    observed: Point2<FieldSpace>
  ) throws -> CameraPixelGeometry {
    let dx = predicted.x - observed.x
    let dy = predicted.y - observed.y
    if predicted == observed || (dx * dx) + (dy * dy) <= 1e-18 {
      return .point(try fieldToCamera.applying(to: predicted))
    }
    return .polyline(
      try cameraPolyline(from: Polyline(points: [predicted, observed]))
    )
  }

  private func draw(_ stroke: SimulatedCameraStroke, into pixels: inout [UInt8]) {
    var x = Int(stroke.start.x.rounded())
    var y = Int(stroke.start.y.rounded())
    let endX = Int(stroke.end.x.rounded())
    let endY = Int(stroke.end.y.rounded())
    let dx = abs(endX - x)
    let sx = x < endX ? 1 : -1
    let dy = -abs(endY - y)
    let sy = y < endY ? 1 : -1
    var error = dx + dy
    while true {
      if x >= 0, x < width, y >= 0, y < height {
        let offset = (y * width + x) * 4
        pixels[offset] = 30
        pixels[offset + 1] = stroke.green
        pixels[offset + 2] = 20
        pixels[offset + 3] = 255
      }
      if x == endX, y == endY { break }
      let doubled = 2 * error
      if doubled >= dy {
        error += dy
        x += sx
      }
      if doubled <= dx {
        error += dx
        y += sy
      }
    }
  }
}
