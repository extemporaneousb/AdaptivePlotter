import Foundation
import PlotterModel

/// Provenance carried by every simulator response. Simulator state and outcomes
/// are deliberately not controller, camera, motion, or ink evidence.
public struct SimulatedLearningEvidenceNotice: Hashable, Sendable {
  public static let evidenceLabel = "SIMULATED — NOT PHYSICAL EVIDENCE"
  public static let notPhysicalEvidence = SimulatedLearningEvidenceNotice()

  public let label: String

  private init() {
    label = Self.evidenceLabel
  }
}

public enum SimulatedLearningSessionState: String, Codable, Hashable, Sendable {
  case disconnected
  case connected
}

public enum SimulatedLearningMotionAuthorization: String, Codable, Hashable, Sendable {
  case disabled
  case enabled
}

public enum SimulatedLearningPenPose: String, Codable, Hashable, Sendable {
  case unknown
  case up
  case down
}

public enum SimulatedLearningValueError: Error, Hashable, Sendable {
  case nonFinitePosition
  case nonFiniteMotion
}

public struct SimulatedLearningBoundaryTruth: Codable, Hashable, Sendable {
  public let negativeXMM: Double
  public let positiveXMM: Double
  public let negativeYMM: Double
  public let positiveYMM: Double

  public init(
    negativeXMM: Double = -40,
    positiveXMM: Double = 40,
    negativeYMM: Double = -30,
    positiveYMM: Double = 30
  ) {
    precondition(negativeXMM.isFinite && positiveXMM.isFinite)
    precondition(negativeYMM.isFinite && positiveYMM.isFinite)
    precondition(negativeXMM < positiveXMM && negativeYMM < positiveYMM)
    self.negativeXMM = negativeXMM
    self.positiveXMM = positiveXMM
    self.negativeYMM = negativeYMM
    self.positiveYMM = positiveYMM
  }

  public func limit(for direction: BoundaryDirection) -> Double {
    switch direction {
    case .negativeX: negativeXMM
    case .positiveX: positiveXMM
    case .negativeY: negativeYMM
    case .positiveY: positiveYMM
    }
  }
}

public enum SimulatedWorldToCameraTransformError: Error, Hashable, Sendable {
  case invalidFrameDimensions
  case invalidPadding
  case invalidMargin
  case insufficientDrawableArea
}

/// Stable identity for one exact causal simulator viewport. It is derived from
/// the complete fit configuration, not allocated per frame or per view resize.
public struct SimulatedCameraViewportID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    precondition(!rawValue.isEmpty)
    self.rawValue = rawValue
  }
}

/// Pure, invertible machine-world to camera-pixel fit. Simulator world +X maps
/// right and simulator world +Y deliberately maps down, matching the canonical
/// top-left-origin camera convention used by the shared renderer.
public struct SimulatedWorldToCameraTransform: Codable, Hashable, Sendable {
  public let truth: SimulatedLearningBoundaryTruth
  public let frameWidth: Int
  public let frameHeight: Int
  public let paddingPixels: Double
  public let armatureMarginMM: Double
  public let protocolMarginMM: Double
  public let scalePixelsPerMillimeter: Double
  public let originX: Double
  public let originY: Double
  public let viewportID: SimulatedCameraViewportID

  public init(
    truth: SimulatedLearningBoundaryTruth,
    frameWidth: Int,
    frameHeight: Int,
    paddingPixels: Double = 28,
    armatureMarginMM: Double = 8,
    protocolMarginMM: Double = 2.5
  ) throws {
    guard frameWidth > 0, frameHeight > 0 else {
      throw SimulatedWorldToCameraTransformError.invalidFrameDimensions
    }
    guard paddingPixels.isFinite, paddingPixels >= 0 else {
      throw SimulatedWorldToCameraTransformError.invalidPadding
    }
    guard armatureMarginMM.isFinite, armatureMarginMM >= 0,
      protocolMarginMM.isFinite, protocolMarginMM >= 0
    else {
      throw SimulatedWorldToCameraTransformError.invalidMargin
    }
    let drawableWidth = Double(frameWidth) - 2 * paddingPixels
    let drawableHeight = Double(frameHeight) - 2 * paddingPixels
    guard drawableWidth > 0, drawableHeight > 0 else {
      throw SimulatedWorldToCameraTransformError.insufficientDrawableArea
    }
    let margin = armatureMarginMM + protocolMarginMM
    let fittedWidth = truth.positiveXMM - truth.negativeXMM + 2 * margin
    let fittedHeight = truth.positiveYMM - truth.negativeYMM + 2 * margin
    let scale = min(drawableWidth / fittedWidth, drawableHeight / fittedHeight)
    guard scale.isFinite, scale > 0 else {
      throw SimulatedWorldToCameraTransformError.insufficientDrawableArea
    }
    let centerX = (truth.negativeXMM + truth.positiveXMM) / 2
    let centerY = (truth.negativeYMM + truth.positiveYMM) / 2
    let originX = Double(frameWidth) / 2 - centerX * scale
    let originY = Double(frameHeight) / 2 - centerY * scale

    self.truth = truth
    self.frameWidth = frameWidth
    self.frameHeight = frameHeight
    self.paddingPixels = paddingPixels
    self.armatureMarginMM = armatureMarginMM
    self.protocolMarginMM = protocolMarginMM
    scalePixelsPerMillimeter = scale
    self.originX = originX
    self.originY = originY
    viewportID = SimulatedCameraViewportID(rawValue: Self.identity(
      truth: truth,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      paddingPixels: paddingPixels,
      armatureMarginMM: armatureMarginMM,
      protocolMarginMM: protocolMarginMM,
      scale: scale,
      originX: originX,
      originY: originY
    ))
  }

  public var fittedWorldBounds: SimulatedLearningBoundaryTruth {
    let margin = armatureMarginMM + protocolMarginMM
    return SimulatedLearningBoundaryTruth(
      negativeXMM: truth.negativeXMM - margin,
      positiveXMM: truth.positiveXMM + margin,
      negativeYMM: truth.negativeYMM - margin,
      positiveYMM: truth.positiveYMM + margin
    )
  }

  public func cameraPoint(
    for position: SimulatedLearningMPos
  ) -> Point2<CameraPixelSpace> {
    try! Point2(
      x: originX + position.xMM * scalePixelsPerMillimeter,
      y: originY + position.yMM * scalePixelsPerMillimeter
    )
  }

  public func worldPosition(
    for point: Point2<CameraPixelSpace>
  ) -> SimulatedLearningMPos {
    try! SimulatedLearningMPos(
      xMM: (point.x - originX) / scalePixelsPerMillimeter,
      yMM: (point.y - originY) / scalePixelsPerMillimeter
    )
  }

  private static func identity(
    truth: SimulatedLearningBoundaryTruth,
    frameWidth: Int,
    frameHeight: Int,
    paddingPixels: Double,
    armatureMarginMM: Double,
    protocolMarginMM: Double,
    scale: Double,
    originX: Double,
    originY: Double
  ) -> String {
    let doubles = [
      truth.negativeXMM, truth.positiveXMM, truth.negativeYMM, truth.positiveYMM,
      paddingPixels, armatureMarginMM, protocolMarginMM, scale, originX, originY,
    ].map { String($0.bitPattern, radix: 16) }.joined(separator: "-")
    return "simulated-viewport-v1-\(frameWidth)x\(frameHeight)-\(doubles)"
  }
}

/// Immutable simulator truth for the visible cap landmark relative to the
/// hidden paper-contact point. Fractions scale with the camera frame's shorter
/// side so the same physical scenario survives viewport-resolution changes.
public struct SimulatedCapToTipOffsetTruth: Codable, Hashable, Sendable {
  public let dxShortSideFraction: Double
  public let dyShortSideFraction: Double

  public init(
    dxShortSideFraction: Double = -0.045,
    dyShortSideFraction: Double = 0.04
  ) {
    precondition(dxShortSideFraction.isFinite && dyShortSideFraction.isFinite)
    self.dxShortSideFraction = dxShortSideFraction
    self.dyShortSideFraction = dyShortSideFraction
  }

  public func pixelOffset(frameWidth: Int, frameHeight: Int) -> Vector2<CameraPixelSpace> {
    let shortSide = Double(min(frameWidth, frameHeight))
    return try! Vector2(
      dx: dxShortSideFraction * shortSide,
      dy: dyShortSideFraction * shortSide
    )
  }
}

public enum SimulatedLearningAnnotationKind: Codable, Hashable, Sendable {
  case truthEnvelope
  case directionLabel(BoundaryDirection)
  case acceptedLearnedSide(BoundaryDirection)
  case learnedCenter
  case currentCapAnchor
  case recentMotionTrail
  case currentOperation
  case ink
}

public enum SimulatedLearningAnnotationGeometry: Codable, Hashable, Sendable {
  case point(Point2<CameraPixelSpace>)
  case bounds(AxisAlignedBounds<CameraPixelSpace>)
  case polyline(Polyline<CameraPixelSpace>)
}

/// Presentation-only simulator annotation. It is exact-frame,
/// exact-configuration, and exact-viewport bound and never enters frame bytes.
public struct SimulatedLearningAnnotation: Hashable, Sendable {
  public static let algorithmRevision = "simulated-learning-annotation-v1"

  public let kind: SimulatedLearningAnnotationKind
  public let anchor: Point2<CameraPixelSpace>
  public let geometry: SimulatedLearningAnnotationGeometry
  public let visibleLabel: String
  public let accessibleValue: String
  public let algorithmRevision: String
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID
  public let viewportID: SimulatedCameraViewportID
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  public init(
    kind: SimulatedLearningAnnotationKind,
    anchor: Point2<CameraPixelSpace>,
    geometry: SimulatedLearningAnnotationGeometry,
    visibleLabel: String,
    accessibleValue: String,
    algorithmRevision: String = Self.algorithmRevision,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    viewportID: SimulatedCameraViewportID
  ) {
    self.kind = kind
    self.anchor = anchor
    self.geometry = geometry
    self.visibleLabel = visibleLabel
    self.accessibleValue = accessibleValue
    self.algorithmRevision = algorithmRevision
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
    self.viewportID = viewportID
    evidenceNotice = .notPhysicalEvidence
  }

  public func matches(
    _ displayedFrame: DisplayedFrame,
    viewportID: SimulatedCameraViewportID
  ) -> Bool {
    guard case .simulated = displayedFrame.source else { return false }
    return frameID == displayedFrame.frame.id
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
      && self.viewportID == viewportID
  }
}

public struct SimulatedLearningAnnotationContext: Hashable, Sendable {
  public let acceptedBoundaryPositions: [BoundaryDirection: SimulatedLearningMPos]
  public let learnedCenter: SimulatedLearningMPos?

  public init(
    acceptedBoundaryPositions: [BoundaryDirection: SimulatedLearningMPos] = [:],
    learnedCenter: SimulatedLearningMPos? = nil
  ) {
    self.acceptedBoundaryPositions = acceptedBoundaryPositions
    self.learnedCenter = learnedCenter
  }
}

public struct SimulatedLearningInkSegment: Codable, Hashable, Sendable {
  public let start: SimulatedLearningMPos
  public let end: SimulatedLearningMPos

  public init(start: SimulatedLearningMPos, end: SimulatedLearningMPos) {
    self.start = start
    self.end = end
  }
}

public enum SimulatedLearningFault: Codable, Hashable, Sendable {
  case refuseNextOperation
  case ambiguityBeforeNextBoundarySegment
  case cameraConfigurationChangeBeforeNextFrame
  case poseMismatchBeforeNextFrame(dxMM: Double, dyMM: Double)
  case absentInk
  case excessiveBackgroundResidual
  case shutdownDuringOperation
}

public struct SimulatedLearningSceneFrame: Hashable, Sendable {
  public let displayedFrame: DisplayedFrame
  public let controllerPosition: SimulatedLearningMPos
  public let capAnchorPoint: Point2<CameraPixelSpace>
  public let armatureBounds: AxisAlignedBounds<CameraPixelSpace>
  public let inkSegmentCount: Int
  public let toolPaperRevision: UUID
  public let worldToCameraTransform: SimulatedWorldToCameraTransform
  public let viewportID: SimulatedCameraViewportID
  public let annotations: [SimulatedLearningAnnotation]
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    displayedFrame: DisplayedFrame,
    controllerPosition: SimulatedLearningMPos,
    capAnchorPoint: Point2<CameraPixelSpace>,
    armatureBounds: AxisAlignedBounds<CameraPixelSpace>,
    inkSegmentCount: Int,
    toolPaperRevision: UUID,
    worldToCameraTransform: SimulatedWorldToCameraTransform,
    annotations: [SimulatedLearningAnnotation]
  ) {
    self.displayedFrame = displayedFrame
    self.controllerPosition = controllerPosition
    self.capAnchorPoint = capAnchorPoint
    self.armatureBounds = armatureBounds
    self.inkSegmentCount = inkSegmentCount
    self.toolPaperRevision = toolPaperRevision
    self.worldToCameraTransform = worldToCameraTransform
    viewportID = worldToCameraTransform.viewportID
    self.annotations = annotations
    evidenceNotice = .notPhysicalEvidence
  }
}

/// A simulator-only position. It is intentionally not `MachinePosition` and
/// cannot be inserted into controller or physical-evidence paths.
public struct SimulatedLearningMPos: Codable, Hashable, Sendable {
  public static let zero = SimulatedLearningMPos(uncheckedXMM: 0, yMM: 0)

  public let xMM: Double
  public let yMM: Double

  public init(xMM: Double, yMM: Double) throws {
    guard xMM.isFinite, yMM.isFinite else {
      throw SimulatedLearningValueError.nonFinitePosition
    }
    self.init(uncheckedXMM: xMM, yMM: yMM)
  }

  private init(uncheckedXMM xMM: Double, yMM: Double) {
    self.xMM = xMM
    self.yMM = yMM
  }

  fileprivate func applying(_ delta: SimulatedLearningMotionVector) -> Self? {
    let resultX = xMM + delta.dxMM
    let resultY = yMM + delta.dyMM
    guard resultX.isFinite, resultY.isFinite else { return nil }
    return Self(uncheckedXMM: resultX, yMM: resultY)
  }
}

/// A simulator-only displacement in millimetres.
public struct SimulatedLearningMotionVector: Codable, Hashable, Sendable {
  public let dxMM: Double
  public let dyMM: Double

  public init(dxMM: Double, dyMM: Double) throws {
    guard dxMM.isFinite, dyMM.isFinite else {
      throw SimulatedLearningValueError.nonFiniteMotion
    }
    self.dxMM = dxMM
    self.dyMM = dyMM
  }

  fileprivate init(uncheckedDXMM dxMM: Double, dyMM: Double) {
    self.dxMM = dxMM
    self.dyMM = dyMM
  }
}

public struct SimulatedLearningOperationID: Codable, Hashable, Sendable {
  public let sequence: UInt64

  public init(sequence: UInt64) {
    self.sequence = sequence
  }
}

public enum SimulatedLearningOperationKind: Hashable, Sendable {
  case manualJog(SimulatedLearningMotionVector)
  case boundary(direction: BoundaryDirection, finiteSegmentLengthMM: Double)
  case drawing(SimulatedLearningMotionVector)
}

public struct SimulatedLearningOperation: Hashable, Sendable {
  public let id: SimulatedLearningOperationID
  public let kind: SimulatedLearningOperationKind
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(id: SimulatedLearningOperationID, kind: SimulatedLearningOperationKind) {
    self.id = id
    self.kind = kind
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum SimulatedLearningAmbiguityContext: Codable, Hashable, Sendable {
  case boundarySegment(BoundaryDirection)
}

public struct SimulatedLearningStickyAmbiguity: Codable, Hashable, Sendable {
  public let operationID: SimulatedLearningOperationID
  public let context: SimulatedLearningAmbiguityContext

  public init(
    operationID: SimulatedLearningOperationID,
    boundaryDirection: BoundaryDirection
  ) {
    self.operationID = operationID
    context = .boundarySegment(boundaryDirection)
  }
}

public struct SimulatedLearningSnapshot: Hashable, Sendable {
  public let session: SimulatedLearningSessionState
  public let motionAuthorization: SimulatedLearningMotionAuthorization
  public let penPose: SimulatedLearningPenPose
  public let mpos: SimulatedLearningMPos
  public let currentOperation: SimulatedLearningOperation?
  public let stickyAmbiguity: SimulatedLearningStickyAmbiguity?
  public let boundaryTruth: SimulatedLearningBoundaryTruth
  public let cameraConfigurationID: CameraConfigurationID
  public let viewportID: SimulatedCameraViewportID
  public let frameSequence: UInt64
  public let persistentInkSegmentCount: Int
  public let toolPaperRevision: UUID
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    session: SimulatedLearningSessionState,
    motionAuthorization: SimulatedLearningMotionAuthorization,
    penPose: SimulatedLearningPenPose,
    mpos: SimulatedLearningMPos,
    currentOperation: SimulatedLearningOperation?,
    stickyAmbiguity: SimulatedLearningStickyAmbiguity?,
    boundaryTruth: SimulatedLearningBoundaryTruth,
    cameraConfigurationID: CameraConfigurationID,
    viewportID: SimulatedCameraViewportID,
    frameSequence: UInt64,
    persistentInkSegmentCount: Int,
    toolPaperRevision: UUID
  ) {
    self.session = session
    self.motionAuthorization = motionAuthorization
    self.penPose = penPose
    self.mpos = mpos
    self.currentOperation = currentOperation
    self.stickyAmbiguity = stickyAmbiguity
    self.boundaryTruth = boundaryTruth
    self.cameraConfigurationID = cameraConfigurationID
    self.viewportID = viewportID
    self.frameSequence = frameSequence
    self.persistentInkSegmentCount = persistentInkSegmentCount
    self.toolPaperRevision = toolPaperRevision
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum SimulatedLearningOperationIntent: String, Codable, Hashable, Sendable {
  case stop
  case cancel
  case shutdown
}

public enum SimulatedLearningOperationDisposition: String, Codable, Hashable, Sendable {
  case stopped
  case cancelled
  case naturallyCompleted
  case failed
  case shutdown
}

public struct SimulatedLearningOperationOutcome: Hashable, Sendable {
  public let operation: SimulatedLearningOperation
  public let disposition: SimulatedLearningOperationDisposition
  public let finalMPos: SimulatedLearningMPos
  public let completedBoundarySegmentCount: Int
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    operation: SimulatedLearningOperation,
    disposition: SimulatedLearningOperationDisposition,
    finalMPos: SimulatedLearningMPos,
    completedBoundarySegmentCount: Int
  ) {
    self.operation = operation
    self.disposition = disposition
    self.finalMPos = finalMPos
    self.completedBoundarySegmentCount = completedBoundarySegmentCount
    evidenceNotice = .notPhysicalEvidence
  }
}

public struct SimulatedBoundarySegmentContinuation: Hashable, Sendable {
  public let operationID: SimulatedLearningOperationID
  public let completedSegmentCount: Int
  public let mpos: SimulatedLearningMPos
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(
    operationID: SimulatedLearningOperationID,
    completedSegmentCount: Int,
    mpos: SimulatedLearningMPos
  ) {
    self.operationID = operationID
    self.completedSegmentCount = completedSegmentCount
    self.mpos = mpos
    evidenceNotice = .notPhysicalEvidence
  }
}

public enum SimulatedLearningRefusal: Error, Hashable, Sendable {
  case sessionDisconnected
  case sessionAlreadyConnected
  case sessionAlreadyDisconnected
  case motionAuthorizationDisabled
  case operationAlreadyActive(SimulatedLearningOperationID)
  case operationAlreadySettled(
    SimulatedLearningOperationID,
    SimulatedLearningOperationDisposition
  )
  case staleOperation(
    requested: SimulatedLearningOperationID,
    active: SimulatedLearningOperationID?
  )
  case penMustBeUp
  case penMustBeDown
  case invalidBoundarySegmentLength
  case resultingPositionNonFinite
  case operationIsNotBoundary
  case boundaryRequiresStopOrCancel
  case injectedRefusal
  case stickyAmbiguity(SimulatedLearningStickyAmbiguity)
  case frameRenderingFailed(String)
}

/// Every simulator call returns this wrapper so simulated provenance cannot be
/// lost when an admission is refused.
public struct SimulatedLearningResponse<Value: Sendable>: Sendable {
  public let result: Result<Value, SimulatedLearningRefusal>
  public let evidenceNotice: SimulatedLearningEvidenceNotice

  fileprivate init(result: Result<Value, SimulatedLearningRefusal>) {
    self.result = result
    evidenceNotice = .notPhysicalEvidence
  }

  fileprivate static func accepted(_ value: Value) -> Self {
    Self(result: .success(value))
  }

  fileprivate static func refused(_ refusal: SimulatedLearningRefusal) -> Self {
    Self(result: .failure(refusal))
  }
}

/// Suspension policy for causal simulated execution. Every suspension is an
/// operator-intent boundary: after it returns, the runtime rechecks that the
/// same logical owner is still current before applying another causal action.
public protocol SimulatedLearningExecutionPacing: Sendable {
  func suspendBetweenSteps() async
}

public struct SimulatedLearningInteractivePacing: SimulatedLearningExecutionPacing, Sendable {
  public let stepDelay: Duration

  public init(stepDelay: Duration = .milliseconds(250)) {
    precondition(stepDelay >= .zero)
    self.stepDelay = stepDelay
  }

  public func suspendBetweenSteps() async {
    try? await Task.sleep(for: stepDelay)
  }
}

public struct SimulatedLearningImmediatePacing: SimulatedLearningExecutionPacing, Sendable {
  public init() {}

  public func suspendBetweenSteps() async {
    await Task.yield()
  }
}

/// Deterministic, nonphysical state machine for exercising the operator path.
/// It owns no serial session, `MachineController`, `MachineActions`, camera, or
/// evidence-producing type. Callers explicitly drive natural completions and
/// finite Boundary segment completions.
public actor SimulatedLearningRuntime {
  private var session: SimulatedLearningSessionState = .disconnected
  private var motionAuthorization: SimulatedLearningMotionAuthorization = .disabled
  private var penPose: SimulatedLearningPenPose = .up
  private var mpos: SimulatedLearningMPos
  private var currentOperation: SimulatedLearningOperation?
  private var stickyAmbiguity: SimulatedLearningStickyAmbiguity?
  private var nextOperationSequence: UInt64 = 1
  private var completedBoundarySegmentCounts: [SimulatedLearningOperationID: Int] = [:]
  private var outcomes: [SimulatedLearningOperationID: SimulatedLearningOperationOutcome] = [:]
  private let boundaryTruth: SimulatedLearningBoundaryTruth
  private var cameraConfigurationID: CameraConfigurationID
  private var frameSequence: UInt64 = 1
  private var frameTimestamp: UInt64 = 1
  private var inkSegments: [SimulatedLearningInkSegment] = []
  private var toolPaperRevision: UUID
  private var recentMotionTrail: [SimulatedLearningMPos]
  private var injectedFaults: [SimulatedLearningFault] = []
  private var cooperativeExecutionOperationID: SimulatedLearningOperationID?
  private var worldToCameraTransform: SimulatedWorldToCameraTransform
  private let capToTipOffsetTruth: SimulatedCapToTipOffsetTruth
  private var latestCausalSceneFrame: SimulatedLearningSceneFrame?
  private var outcomeWaiters:
    [SimulatedLearningOperationID: [CheckedContinuation<SimulatedLearningOperationOutcome, Never>]] =
      [:]

  public init(
    initialMPos: SimulatedLearningMPos = .zero,
    boundaryTruth: SimulatedLearningBoundaryTruth = SimulatedLearningBoundaryTruth(),
    frameWidth: Int = 640,
    frameHeight: Int = 480,
    paddingPixels: Double = 28,
    armatureMarginMM: Double = 8,
    protocolMarginMM: Double = 2.5,
    capToTipOffsetTruth: SimulatedCapToTipOffsetTruth = SimulatedCapToTipOffsetTruth(),
    toolPaperRevision: UUID = UUID()
  ) {
    let transform = try! SimulatedWorldToCameraTransform(
      truth: boundaryTruth,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      paddingPixels: paddingPixels,
      armatureMarginMM: armatureMarginMM,
      protocolMarginMM: protocolMarginMM
    )
    mpos = initialMPos
    recentMotionTrail = [initialMPos]
    self.boundaryTruth = boundaryTruth
    worldToCameraTransform = transform
    self.capToTipOffsetTruth = capToTipOffsetTruth
    self.toolPaperRevision = toolPaperRevision
    cameraConfigurationID = CameraConfigurationID()
  }

  public func snapshot() -> SimulatedLearningSnapshot {
    makeSnapshot()
  }

  public func injectFault(_ fault: SimulatedLearningFault) {
    injectedFaults.append(fault)
  }

  public func persistentInk() -> [SimulatedLearningInkSegment] {
    inkSegments
  }

  public func cameraViewport() -> SimulatedWorldToCameraTransform {
    worldToCameraTransform
  }

  public func capToTipPixelOffsetTruth() -> Vector2<CameraPixelSpace> {
    capToTipOffsetTruth.pixelOffset(
      frameWidth: worldToCameraTransform.frameWidth,
      frameHeight: worldToCameraTransform.frameHeight
    )
  }

  public func latestPublishedCausalFrame() -> SimulatedLearningSceneFrame? {
    latestCausalSceneFrame
  }

  /// A true camera refit changes optical identity. SwiftUI view resizing never
  /// calls this; it remains a presentation-only aspect-fit operation.
  @discardableResult
  public func refitCamera(
    frameWidth: Int,
    frameHeight: Int,
    paddingPixels: Double = 28,
    armatureMarginMM: Double = 8,
    protocolMarginMM: Double = 2.5
  ) throws -> SimulatedLearningSnapshot {
    let replacement = try SimulatedWorldToCameraTransform(
      truth: boundaryTruth,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      paddingPixels: paddingPixels,
      armatureMarginMM: armatureMarginMM,
      protocolMarginMM: protocolMarginMM
    )
    if replacement != worldToCameraTransform {
      worldToCameraTransform = replacement
      cameraConfigurationID = CameraConfigurationID()
      latestCausalSceneFrame = nil
    }
    return makeSnapshot()
  }

  /// Explicit simulated human fact. It clears only the causal paper scene and
  /// rotates paper compatibility; camera configuration remains a separate
  /// optical identity.
  public func recordPaperReplaced() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    inkSegments.removeAll()
    toolPaperRevision = UUID()
    return .accepted(makeSnapshot())
  }

  public func connect() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .disconnected else {
      return .refused(.sessionAlreadyConnected)
    }
    session = .connected
    return .accepted(makeSnapshot())
  }

  public func disconnect() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionAlreadyDisconnected)
    }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    session = .disconnected
    motionAuthorization = .disabled
    penPose = .up
    stickyAmbiguity = nil
    return .accepted(makeSnapshot())
  }

  public func enableMotion() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    motionAuthorization = .enabled
    return .accepted(makeSnapshot())
  }

  public func disableMotion() -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    motionAuthorization = .disabled
    return .accepted(makeSnapshot())
  }

  public func setPenPose(
    _ pose: SimulatedLearningPenPose
  ) -> SimulatedLearningResponse<SimulatedLearningSnapshot> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    guard motionAuthorization == .enabled else {
      return .refused(.motionAuthorizationDisabled)
    }
    if let stickyAmbiguity { return .refused(.stickyAmbiguity(stickyAmbiguity)) }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    penPose = pose
    return .accepted(makeSnapshot())
  }

  /// Simulator rendering support for one generic stationary contact tap. The
  /// workspace calls this only after separate simulated Pen Down and Pen Up
  /// settlements; it is not a compound runtime owner or physical evidence.
  public func recordStationaryContactMark()
    -> SimulatedLearningResponse<SimulatedLearningSnapshot>
  {
    guard session == .connected else { return .refused(.sessionDisconnected) }
    guard motionAuthorization == .enabled else {
      return .refused(.motionAuthorizationDisabled)
    }
    if let stickyAmbiguity { return .refused(.stickyAmbiguity(stickyAmbiguity)) }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    guard penPose == .up else { return .refused(.penMustBeUp) }
    inkSegments.append(SimulatedLearningInkSegment(start: mpos, end: mpos))
    return .accepted(makeSnapshot())
  }

  public func beginManualJog(
    delta: SimulatedLearningMotionVector
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    beginOperation(kind: .manualJog(delta), requiredPenPose: .up)
  }

  public func beginBoundary(
    direction: BoundaryDirection,
    finiteSegmentLengthMM: Double
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    guard finiteSegmentLengthMM.isFinite, finiteSegmentLengthMM > 0 else {
      return .refused(.invalidBoundarySegmentLength)
    }
    return beginOperation(
      kind: .boundary(
        direction: direction,
        finiteSegmentLengthMM: finiteSegmentLengthMM
      ),
      requiredPenPose: .up
    )
  }

  public func beginDrawing(
    delta: SimulatedLearningMotionVector
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    beginOperation(kind: .drawing(delta), requiredPenPose: .down)
  }

  /// The first Stop or Cancel accepted for an operation is its only terminal
  /// disposition. Actor isolation is the intent latch.
  public func request(
    _ intent: SimulatedLearningOperationIntent,
    for operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(
        .operationAlreadySettled(operationID, outcome.disposition)
      )
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    let disposition: SimulatedLearningOperationDisposition =
      switch intent {
      case .stop: .stopped
      case .cancel: .cancelled
      case .shutdown: .shutdown
      }
    switch operation.kind {
    case .drawing:
      if penPose == .down { penPose = .up }
    default:
      break
    }
    return .accepted(settle(operation, disposition: disposition))
  }

  public func stop(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    request(.stop, for: operationID)
  }

  public func cancel(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    request(.cancel, for: operationID)
  }

  public func shutdown(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    request(.shutdown, for: operationID)
  }

  /// Models one unambiguous finite wire segment completing beneath the same
  /// logical Boundary owner. It updates simulated MPos but never settles the
  /// Boundary operation or manufactures Boundary success.
  public func recordBoundarySegmentCompletion(
    for operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedBoundarySegmentContinuation> {
    if let outcome = outcomes[operationID] {
      return .refused(
        .operationAlreadySettled(operationID, outcome.disposition)
      )
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    guard case .boundary(let direction, let segmentLengthMM) = operation.kind else {
      return .refused(.operationIsNotBoundary)
    }
    if consumeInjectedShutdown() {
      _ = settle(operation, disposition: .shutdown)
      return .refused(.sessionDisconnected)
    }
    let proposedDelta = Self.boundaryDelta(direction, lengthMM: segmentLengthMM)
    guard let proposedMPos = mpos.applying(proposedDelta)
    else {
      return .refused(.resultingPositionNonFinite)
    }
    let limit = boundaryTruth.limit(for: direction)
    let reachesTruth: Bool = switch direction {
    case .negativeX: proposedMPos.xMM <= limit
    case .positiveX: proposedMPos.xMM >= limit
    case .negativeY: proposedMPos.yMM <= limit
    case .positiveY: proposedMPos.yMM >= limit
    }
    if reachesTruth {
      let clampedPosition = switch direction {
      case .negativeX, .positiveX: try! SimulatedLearningMPos(xMM: limit, yMM: mpos.yMM)
      case .negativeY, .positiveY: try! SimulatedLearningMPos(xMM: mpos.xMM, yMM: limit)
      }
      updateMPos(clampedPosition)
    } else {
      updateMPos(proposedMPos)
    }
    let completedCount = completedBoundarySegmentCounts[operationID, default: 0] + 1
    completedBoundarySegmentCounts[operationID] = completedCount
    return .accepted(
      SimulatedBoundarySegmentContinuation(
        operationID: operationID,
        completedSegmentCount: completedCount,
      mpos: mpos
      )
    )
  }

  /// Manual and drawing operations may complete naturally. Boundary is
  /// intentionally excluded because a finite segment is not exercise success.
  public func completeNaturally(
    _ operationID: SimulatedLearningOperationID
  ) -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(
        .operationAlreadySettled(operationID, outcome.disposition)
      )
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    if consumeInjectedShutdown() {
      return .accepted(settle(operation, disposition: .shutdown))
    }
    switch operation.kind {
    case .boundary:
      return .refused(.boundaryRequiresStopOrCancel)
    case .manualJog(let delta):
      guard let updatedMPos = mpos.applying(delta) else {
        return .refused(.resultingPositionNonFinite)
      }
      updateMPos(updatedMPos)
      return .accepted(settle(operation, disposition: .naturallyCompleted))
    case .drawing(let delta):
      guard let updatedMPos = mpos.applying(delta) else {
        return .refused(.resultingPositionNonFinite)
      }
      let start = mpos
      updateMPos(updatedMPos)
      if removeFirstFault(matching: {
        if case .absentInk = $0 { return true }
        return false
      }) == nil {
        inkSegments.append(SimulatedLearningInkSegment(start: start, end: updatedMPos))
      }
      return .accepted(settle(operation, disposition: .naturallyCompleted))
    }
  }

  /// Drives an admitted finite operation with cooperative pacing. The default
  /// pacing is deliberately visible to a human operator. Tests may inject an
  /// immediate or controlled pacer without changing simulator causality.
  public func executeNaturally(
    _ operationID: SimulatedLearningOperationID,
    pacing: any SimulatedLearningExecutionPacing = SimulatedLearningInteractivePacing()
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(.operationAlreadySettled(operationID, outcome.disposition))
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(.staleOperation(requested: operationID, active: currentOperation?.id))
    }
    guard cooperativeExecutionOperationID == nil else {
      return .refused(.operationAlreadyActive(cooperativeExecutionOperationID!))
    }
    cooperativeExecutionOperationID = operationID
    defer {
      if cooperativeExecutionOperationID == operationID {
        cooperativeExecutionOperationID = nil
      }
    }

    switch operation.kind {
    case .boundary:
      return .refused(.boundaryRequiresStopOrCancel)
    case .manualJog, .drawing:
      if let terminal = await suspendAndRecheck(
        operation,
        pacing: pacing
      ) {
        return terminal
      }
      let completion = completeNaturally(operationID)
      if case .success = completion.result,
        case .success(let frame) = renderSceneFrame(
          annotationContext: SimulatedLearningAnnotationContext()
        )
      {
        latestCausalSceneFrame = frame
      }
      return completion
    }
  }

  /// Cooperatively renews finite simulator segments beneath one logical
  /// operator-stopped Boundary owner. Segment motion and causal-frame
  /// publication have separate intent boundaries so Stop/Cancel/shutdown can
  /// win without a later position or frame mutation. Reaching truth parks the
  /// owner on its outcome continuation instead of spinning or succeeding.
  public func executeBoundaryCooperatively(
    _ operationID: SimulatedLearningOperationID,
    pacing: any SimulatedLearningExecutionPacing = SimulatedLearningInteractivePacing()
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .refused(.operationAlreadySettled(operationID, outcome.disposition))
    }
    guard let operation = currentOperation, operation.id == operationID else {
      return .refused(.staleOperation(requested: operationID, active: currentOperation?.id))
    }
    guard case .boundary(let direction, _) = operation.kind else {
      return .refused(.operationIsNotBoundary)
    }
    guard cooperativeExecutionOperationID == nil else {
      return .refused(.operationAlreadyActive(cooperativeExecutionOperationID!))
    }
    cooperativeExecutionOperationID = operationID
    defer {
      if cooperativeExecutionOperationID == operationID {
        cooperativeExecutionOperationID = nil
      }
    }

    while true {
      if atBoundaryTruth(direction) {
        return await waitForOutcome(of: operationID)
      }
      if let terminal = await suspendAndRecheck(
        operation,
        pacing: pacing
      ) {
        return terminal
      }
      if removeFirstFault(matching: {
        if case .ambiguityBeforeNextBoundarySegment = $0 { return true }
        return false
      }) != nil {
        stickyAmbiguity = SimulatedLearningStickyAmbiguity(
          operationID: operationID,
          boundaryDirection: direction
        )
        return .accepted(settle(operation, disposition: .failed))
      }
      let continuation = recordBoundarySegmentCompletion(for: operationID)
      if case .failure(let refusal) = continuation.result {
        return .refused(refusal)
      }

      if let terminal = await suspendAndRecheck(
        operation,
        pacing: pacing
      ) {
        return terminal
      }
      switch renderSceneFrame(annotationContext: SimulatedLearningAnnotationContext()) {
      case .success(let frame):
        latestCausalSceneFrame = frame
      case .failure(let refusal):
        return .refused(refusal)
      }
    }
  }

  private func suspendAndRecheck(
    _ operation: SimulatedLearningOperation,
    pacing: any SimulatedLearningExecutionPacing
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome>? {
    await pacing.suspendBetweenSteps()
    if let outcome = outcomes[operation.id] {
      return .accepted(outcome)
    }
    guard currentOperation?.id == operation.id else {
      return .refused(
        .staleOperation(requested: operation.id, active: currentOperation?.id)
      )
    }
    if consumeInjectedShutdown() {
      return .accepted(settle(
        operation,
        disposition: .shutdown
      ))
    }
    return nil
  }

  public func captureSceneFrame(
    annotationContext: SimulatedLearningAnnotationContext = SimulatedLearningAnnotationContext(),
    newerThanCaptureNanoseconds: UInt64 = 0
  ) -> SimulatedLearningResponse<SimulatedLearningSceneFrame> {
    if frameTimestamp <= newerThanCaptureNanoseconds {
      frameTimestamp = newerThanCaptureNanoseconds &+ 1
    }
    if removeFirstFault(matching: {
      if case .cameraConfigurationChangeBeforeNextFrame = $0 { return true }
      return false
    }) != nil {
      cameraConfigurationID = CameraConfigurationID()
    }
    var renderedPosition = mpos
    if let fault = removeFirstFault(matching: {
      if case .poseMismatchBeforeNextFrame = $0 { return true }
      return false
    }), case .poseMismatchBeforeNextFrame(let dx, let dy) = fault,
      let shifted = renderedPosition.applying(
        SimulatedLearningMotionVector(uncheckedDXMM: dx, dyMM: dy)
      )
    {
      renderedPosition = shifted
    }
    let result = renderSceneFrame(
      renderedPosition: renderedPosition,
      annotationContext: annotationContext
    )
    if case .success(let frame) = result {
      latestCausalSceneFrame = frame
    }
    return SimulatedLearningResponse(result: result)
  }

  private func renderSceneFrame(
    renderedPosition: SimulatedLearningMPos? = nil,
    annotationContext: SimulatedLearningAnnotationContext
  ) -> Result<SimulatedLearningSceneFrame, SimulatedLearningRefusal> {
    let renderedPosition = renderedPosition ?? mpos
    let transform = worldToCameraTransform
    let frameWidth = transform.frameWidth
    let frameHeight = transform.frameHeight
    do {
      let capToTipOffset = capToTipOffsetTruth.pixelOffset(
        frameWidth: frameWidth,
        frameHeight: frameHeight
      )
      let capAnchor = transform.cameraPoint(for: renderedPosition)
      let armatureTopLeft = transform.cameraPoint(for: try SimulatedLearningMPos(
        xMM: renderedPosition.xMM - 1.75,
        yMM: renderedPosition.yMM - 7.5
      ))
      let armatureBottomRight = transform.cameraPoint(for: try SimulatedLearningMPos(
        xMM: renderedPosition.xMM + 1.75,
        yMM: renderedPosition.yMM
      ))
      let armature = try AxisAlignedBounds<CameraPixelSpace>(
        minX: armatureTopLeft.x,
        minY: armatureTopLeft.y,
        maxX: armatureBottomRight.x,
        maxY: armatureBottomRight.y
      )
      var strokes = inkSegments.map {
        SimulatedCameraStroke(
          start: try! transform.cameraPoint(for: $0.start).translated(by: capToTipOffset),
          end: try! transform.cameraPoint(for: $0.end).translated(by: capToTipOffset)
        )
      }
      // The simulated armature is visible in the same pixels as the paper. Its
      // bottom-center is the visible cap anchor used by registration; it is
      // not asserted to be the hidden paper-contact point.
      let armatureVerticalCount = max(1, Int(armature.maxX - armature.minX))
      for offset in 0...armatureVerticalCount {
        let x = armature.minX + Double(offset)
        strokes.append(SimulatedCameraStroke(
          start: try Point2(x: x, y: armature.minY),
          end: try Point2(x: x, y: armature.maxY),
          green: 150
        ))
      }
      if removeFirstFault(matching: {
        if case .excessiveBackgroundResidual = $0 { return true }
        return false
      }) != nil {
        strokes.append(SimulatedCameraStroke(
          start: try Point2(x: 0, y: 0),
          end: try Point2(x: Double(frameWidth - 1), y: Double(frameHeight - 1)),
          green: 220
        ))
      }
      var source = try SimulatedFrameSource(
        width: frameWidth,
        height: frameHeight,
        fieldToCamera: AffineTransform2<FieldSpace, CameraPixelSpace>(
          m11: 1, m12: 0, m21: 0, m22: 1, tx: 0, ty: 0
        ),
        cameraConfigurationID: cameraConfigurationID,
        initialSequence: frameSequence
      )
      let displayed = try source.render(strokes: strokes, captureNanoseconds: frameTimestamp)
      frameSequence &+= 1
      frameTimestamp &+= 1
      let annotations = try makeAnnotations(
        displayedFrame: displayed,
        renderedPosition: renderedPosition,
        capAnchor: capAnchor,
        armature: armature,
        context: annotationContext
      )
      return .success(SimulatedLearningSceneFrame(
        displayedFrame: displayed,
        controllerPosition: renderedPosition,
        capAnchorPoint: capAnchor,
        armatureBounds: armature,
        inkSegmentCount: inkSegments.count,
        toolPaperRevision: toolPaperRevision,
        worldToCameraTransform: transform,
        annotations: annotations
      ))
    } catch {
      return .failure(.frameRenderingFailed(String(describing: error)))
    }
  }

  private func makeAnnotations(
    displayedFrame: DisplayedFrame,
    renderedPosition: SimulatedLearningMPos,
    capAnchor: Point2<CameraPixelSpace>,
    armature: AxisAlignedBounds<CameraPixelSpace>,
    context: SimulatedLearningAnnotationContext
  ) throws -> [SimulatedLearningAnnotation] {
    let transform = worldToCameraTransform
    let capToTipOffset = capToTipOffsetTruth.pixelOffset(
      frameWidth: transform.frameWidth,
      frameHeight: transform.frameHeight
    )
    let frameID = displayedFrame.frame.id
    let configurationID = displayedFrame.frame.cameraConfigurationID
    let viewportID = transform.viewportID
    func annotation(
      _ kind: SimulatedLearningAnnotationKind,
      anchor: Point2<CameraPixelSpace>,
      geometry: SimulatedLearningAnnotationGeometry,
      label: String,
      value: String
    ) -> SimulatedLearningAnnotation {
      SimulatedLearningAnnotation(
        kind: kind,
        anchor: anchor,
        geometry: geometry,
        visibleLabel: label,
        accessibleValue: value,
        frameID: frameID,
        cameraConfigurationID: configurationID,
        viewportID: viewportID
      )
    }

    let truthMin = transform.cameraPoint(for: try SimulatedLearningMPos(
      xMM: boundaryTruth.negativeXMM,
      yMM: boundaryTruth.negativeYMM
    ))
    let truthMax = transform.cameraPoint(for: try SimulatedLearningMPos(
      xMM: boundaryTruth.positiveXMM,
      yMM: boundaryTruth.positiveYMM
    ))
    let truthBounds = try AxisAlignedBounds<CameraPixelSpace>(
      minX: truthMin.x, minY: truthMin.y, maxX: truthMax.x, maxY: truthMax.y
    )
    var result = [annotation(
      .truthEnvelope,
      anchor: truthMin,
      geometry: .bounds(truthBounds),
      label: "SIMULATED TRUTH",
      value: "Simulator truth envelope; not learned or physical evidence"
    )]

    let centerX = (boundaryTruth.negativeXMM + boundaryTruth.positiveXMM) / 2
    let centerY = (boundaryTruth.negativeYMM + boundaryTruth.positiveYMM) / 2
    for direction in BoundaryDirection.allCases {
      let world = switch direction {
      case .negativeX: try SimulatedLearningMPos(xMM: boundaryTruth.negativeXMM, yMM: centerY)
      case .positiveX: try SimulatedLearningMPos(xMM: boundaryTruth.positiveXMM, yMM: centerY)
      case .negativeY: try SimulatedLearningMPos(xMM: centerX, yMM: boundaryTruth.negativeYMM)
      case .positiveY: try SimulatedLearningMPos(xMM: centerX, yMM: boundaryTruth.positiveYMM)
      }
      let point = transform.cameraPoint(for: world)
      result.append(annotation(
        .directionLabel(direction),
        anchor: point,
        geometry: .point(point),
        label: direction.displayName,
        value: "Simulator truth direction \(direction.displayName)"
      ))
    }

    for direction in BoundaryDirection.allCases {
      guard let position = context.acceptedBoundaryPositions[direction] else { continue }
      let point = transform.cameraPoint(for: position)
      result.append(annotation(
        .acceptedLearnedSide(direction),
        anchor: point,
        geometry: .point(point),
        label: "LEARNED \(direction.displayName)",
        value: "Accepted simulated learned side \(direction.displayName)"
      ))
    }
    if let learnedCenter = context.learnedCenter {
      let point = transform.cameraPoint(for: learnedCenter)
      result.append(annotation(
        .learnedCenter,
        anchor: point,
        geometry: .point(point),
        label: "LEARNED CENTER",
        value: "Accepted simulated learned center"
      ))
    }

    result.append(annotation(
      .currentCapAnchor,
      anchor: capAnchor,
      geometry: .bounds(armature),
      label: "MPOS",
      value: "Simulated MPos X \(renderedPosition.xMM), Y \(renderedPosition.yMM)"
    ))
    if recentMotionTrail.count > 1 {
      let trail = try Polyline<CameraPixelSpace>(
        points: recentMotionTrail.map { transform.cameraPoint(for: $0) }
      )
      result.append(annotation(
        .recentMotionTrail,
        anchor: trail.start,
        geometry: .polyline(trail),
        label: "RECENT MOTION",
        value: "Bounded simulated motion trail with \(trail.points.count) positions"
      ))
    }
    if let operation = currentOperation {
      let label: String = switch operation.kind {
      case .manualJog: "MANUAL OWNER \(operation.id.sequence)"
      case .boundary(let direction, _):
        "BOUNDARY \(direction.displayName) OWNER \(operation.id.sequence)"
      case .drawing: "DRAW OWNER \(operation.id.sequence)"
      }
      result.append(annotation(
        .currentOperation,
        anchor: capAnchor,
        geometry: .point(capAnchor),
        label: label,
        value: "Current simulated operation \(label)"
      ))
    }
    for segment in inkSegments {
      let start = try transform.cameraPoint(for: segment.start).translated(by: capToTipOffset)
      let end = try transform.cameraPoint(for: segment.end).translated(by: capToTipOffset)
      let geometry: SimulatedLearningAnnotationGeometry
      if start == end {
        geometry = .point(start)
      } else {
        geometry = .polyline(try Polyline<CameraPixelSpace>(points: [start, end]))
      }
      result.append(annotation(
        .ink,
        anchor: start,
        geometry: geometry,
        label: "SIMULATED INK",
        value: "Simulated retained ink segment; not physical evidence"
      ))
    }
    return result
  }

  /// Waits for the outcome of the specified original owner. A later operation
  /// cannot satisfy this wait because waiters and outcomes are keyed by owner ID.
  public func waitForOutcome(
    of operationID: SimulatedLearningOperationID
  ) async -> SimulatedLearningResponse<SimulatedLearningOperationOutcome> {
    if let outcome = outcomes[operationID] {
      return .accepted(outcome)
    }
    guard currentOperation?.id == operationID else {
      return .refused(
        .staleOperation(requested: operationID, active: currentOperation?.id)
      )
    }
    let outcome = await withCheckedContinuation { continuation in
      outcomeWaiters[operationID, default: []].append(continuation)
    }
    return .accepted(outcome)
  }

  private func beginOperation(
    kind: SimulatedLearningOperationKind,
    requiredPenPose: SimulatedLearningPenPose
  ) -> SimulatedLearningResponse<SimulatedLearningOperation> {
    guard session == .connected else {
      return .refused(.sessionDisconnected)
    }
    guard motionAuthorization == .enabled else {
      return .refused(.motionAuthorizationDisabled)
    }
    guard currentOperation == nil else {
      return .refused(.operationAlreadyActive(currentOperation!.id))
    }
    if let stickyAmbiguity { return .refused(.stickyAmbiguity(stickyAmbiguity)) }
    guard penPose == requiredPenPose else {
      return .refused(requiredPenPose == .up ? .penMustBeUp : .penMustBeDown)
    }
    if removeFirstFault(matching: {
      if case .refuseNextOperation = $0 { return true }
      return false
    }) != nil {
      return .refused(.injectedRefusal)
    }
    let operation = SimulatedLearningOperation(
      id: SimulatedLearningOperationID(sequence: nextOperationSequence),
      kind: kind
    )
    nextOperationSequence += 1
    currentOperation = operation
    completedBoundarySegmentCounts[operation.id] = 0
    return .accepted(operation)
  }

  private func settle(
    _ operation: SimulatedLearningOperation,
    disposition: SimulatedLearningOperationDisposition
  ) -> SimulatedLearningOperationOutcome {
    let outcome = SimulatedLearningOperationOutcome(
      operation: operation,
      disposition: disposition,
      finalMPos: mpos,
      completedBoundarySegmentCount: completedBoundarySegmentCounts[operation.id, default: 0]
    )
    outcomes[operation.id] = outcome
    currentOperation = nil
    if cooperativeExecutionOperationID == operation.id {
      cooperativeExecutionOperationID = nil
    }
    completedBoundarySegmentCounts.removeValue(forKey: operation.id)
    let waiters = outcomeWaiters.removeValue(forKey: operation.id) ?? []
    for waiter in waiters {
      waiter.resume(returning: outcome)
    }
    return outcome
  }

  private func makeSnapshot() -> SimulatedLearningSnapshot {
    SimulatedLearningSnapshot(
      session: session,
      motionAuthorization: motionAuthorization,
      penPose: penPose,
      mpos: mpos,
      currentOperation: currentOperation,
      stickyAmbiguity: stickyAmbiguity,
      boundaryTruth: boundaryTruth,
      cameraConfigurationID: cameraConfigurationID,
      viewportID: worldToCameraTransform.viewportID,
      frameSequence: frameSequence,
      persistentInkSegmentCount: inkSegments.count,
      toolPaperRevision: toolPaperRevision
    )
  }

  private func removeFirstFault(
    matching predicate: (SimulatedLearningFault) -> Bool
  ) -> SimulatedLearningFault? {
    guard let index = injectedFaults.firstIndex(where: predicate) else { return nil }
    return injectedFaults.remove(at: index)
  }

  private func consumeInjectedShutdown() -> Bool {
    guard removeFirstFault(matching: {
      if case .shutdownDuringOperation = $0 { return true }
      return false
    }) != nil else { return false }
    session = .disconnected
    motionAuthorization = .disabled
    return true
  }

  private func updateMPos(_ position: SimulatedLearningMPos) {
    mpos = position
    if recentMotionTrail.last != position {
      recentMotionTrail.append(position)
      if recentMotionTrail.count > 24 {
        recentMotionTrail.removeFirst(recentMotionTrail.count - 24)
      }
    }
  }

  private func atBoundaryTruth(_ direction: BoundaryDirection) -> Bool {
    let limit = boundaryTruth.limit(for: direction)
    return switch direction {
    case .negativeX: mpos.xMM <= limit
    case .positiveX: mpos.xMM >= limit
    case .negativeY: mpos.yMM <= limit
    case .positiveY: mpos.yMM >= limit
    }
  }

  private static func boundaryDelta(
    _ direction: BoundaryDirection,
    lengthMM: Double
  ) -> SimulatedLearningMotionVector {
    // Values were validated when the Boundary operation was admitted.
    switch direction {
    case .negativeX:
      return SimulatedLearningMotionVector(uncheckedDXMM: -lengthMM, dyMM: 0)
    case .positiveX:
      return SimulatedLearningMotionVector(uncheckedDXMM: lengthMM, dyMM: 0)
    case .negativeY:
      return SimulatedLearningMotionVector(uncheckedDXMM: 0, dyMM: -lengthMM)
    case .positiveY:
      return SimulatedLearningMotionVector(uncheckedDXMM: 0, dyMM: lengthMM)
    }
  }
}
