import Foundation
import PlotterModel

public enum PhysicalObservationPhase: String, Hashable, Sendable {
  case beforeMotion
  case afterMotion
}

public enum PhysicalJogObservationFailure: Error, Hashable, Sendable {
  case liveCameraRequired
  case frameUnavailable(PhysicalObservationPhase)
  case capUnavailable(PhysicalObservationPhase)
  case measurementFailed(PhysicalObservationPhase, String)
  case invalidFrameID
  case invalidFrameHash
  case invalidCaptureTimestamp
  case frameIdentityMismatch
  case frameHashMismatch
  case measurementConfigurationMismatch
  case invalidCapConfidence
  case invalidAlgorithmRevision
  case invalidObservationID
  case cameraConfigurationChanged
  case algorithmRevisionChanged(before: String, after: String)
  case postFrameNotNewer
  case invalidControllerSampleOrder
  case beforeFrameAfterStartControllerSample(
    frameCaptureNanoseconds: UInt64,
    controllerSampleNanoseconds: UInt64
  )
  case afterFrameNotNewerThanFinalControllerSample(
    frameCaptureNanoseconds: UInt64,
    controllerSampleNanoseconds: UInt64
  )
  case controllerMotionEvidenceUnavailable
  case motionNotCompleted(MotionOutcome)

  public var actionableDescription: String {
    switch self {
    case .liveCameraRequired:
      return "Select LIVE camera mode before recording physical jog evidence."
    case .frameUnavailable(let phase):
      return "No camera frame was available \(phase.description); keep capture running and retry."
    case .capUnavailable(let phase):
      return
        "The visible tool cap was not measured \(phase.description); restore the camera view and retry."
    case .measurementFailed(let phase, let detail):
      return
        "Visible-tool measurement failed \(phase.description) (\(detail)); correct the camera input and retry."
    case .invalidFrameID, .invalidFrameHash, .invalidCaptureTimestamp:
      return "The camera frame lacked valid immutable provenance; restart capture and retry."
    case .frameIdentityMismatch, .frameHashMismatch, .measurementConfigurationMismatch:
      return
        "The visible-tool measurement did not match the exact displayed frame; capture a fresh frame."
    case .invalidCapConfidence:
      return
        "The visible-tool measurement confidence was invalid; capture and analyze a fresh frame."
    case .invalidAlgorithmRevision:
      return
        "The visible-tool measurement lacked an algorithm revision; restart analysis and retry."
    case .invalidObservationID:
      return "The physical observation lacked an identifier; retry the observation."
    case .cameraConfigurationChanged:
      return
        "The camera configuration changed during the jog; record a new observation without switching cameras."
    case .algorithmRevisionChanged:
      return
        "The vision algorithm changed during the jog; record a new observation with one analysis revision."
    case .postFrameNotNewer:
      return "No strictly newer post-jog camera frame arrived; keep capture running and retry."
    case .invalidControllerSampleOrder:
      return "Controller sample times were not ordered; probe again before retrying."
    case .beforeFrameAfterStartControllerSample:
      return
        "The before-motion camera frame was captured after the controller start sample; record a new observation."
    case .afterFrameNotNewerThanFinalControllerSample:
      return
        "The after-motion camera frame was not newer than the final controller sample; wait for a later frame."
    case .controllerMotionEvidenceUnavailable:
      return
        "The controller did not return matching start/final evidence for the completed jog; reconnect and retry."
    case .motionNotCompleted(let outcome):
      return
        "The jog did not complete unambiguously (\(outcome)); no physical observation was recorded."
    }
  }
}

extension PhysicalObservationPhase {
  fileprivate var description: String {
    switch self {
    case .beforeMotion: "before motion"
    case .afterMotion: "after motion"
    }
  }
}

/// One exact visible-tool measurement from a physical camera frame.
///
/// This records the centroid of the visible cap. It makes no claim about pen
/// height, pen contact, completed machine motion, or observed ink.
public struct VisibleToolFrameObservation: Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let capCentroid: Point2<CameraPixelSpace>
  public let capConfidence: Double
  public let algorithmRevision: String

  /// Attests that the measurement came from the exact displayed physical
  /// camera frame. Only CameraCapture can construct the required attestation,
  /// so presentation pixels cannot be relabeled as physical evidence.
  public init(
    phase: PhysicalObservationPhase,
    attestation: LiveCameraFrameAttestation,
    measurement: PlotterSceneMeasurement
  ) throws {
    try self.init(
      phase: phase,
      frame: attestation.frame,
      measurement: measurement
    )
  }

  /// Test-only seam for exercising rejected presentation provenance. This is
  /// internal so PlotterApp and other production clients cannot use a
  /// DisplayedFrame to create physical evidence.
  init(
    phase: PhysicalObservationPhase,
    displayedFrame: DisplayedFrame,
    measurement: PlotterSceneMeasurement
  ) throws {
    guard case .live = displayedFrame.source else {
      throw PhysicalJogObservationFailure.liveCameraRequired
    }
    try self.init(
      phase: phase,
      frame: displayedFrame.frame,
      measurement: measurement
    )
  }

  private init(
    phase: PhysicalObservationPhase,
    frame: StampedFrame,
    measurement: PlotterSceneMeasurement
  ) throws {
    guard measurement.frameID == frame.id else {
      throw PhysicalJogObservationFailure.frameIdentityMismatch
    }
    guard measurement.frameSHA256 == frame.contentSHA256 else {
      throw PhysicalJogObservationFailure.frameHashMismatch
    }
    guard measurement.cameraConfigurationID == frame.cameraConfigurationID else {
      throw PhysicalJogObservationFailure.measurementConfigurationMismatch
    }
    guard let cap = measurement.cap else {
      throw PhysicalJogObservationFailure.capUnavailable(phase)
    }
    try self.init(
      frameID: frame.id,
      frameSHA256: frame.contentSHA256,
      captureNanoseconds: frame.captureNanoseconds,
      cameraConfigurationID: frame.cameraConfigurationID,
      capCentroid: cap.centroid,
      capConfidence: cap.confidence,
      algorithmRevision: measurement.algorithmRevision
    )
  }

  private init(
    frameID: FrameID,
    frameSHA256: String,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    capCentroid: Point2<CameraPixelSpace>,
    capConfidence: Double,
    algorithmRevision: String
  ) throws {
    guard !frameID.rawValue.isEmpty else {
      throw PhysicalJogObservationFailure.invalidFrameID
    }
    guard Self.isSHA256(frameSHA256) else {
      throw PhysicalJogObservationFailure.invalidFrameHash
    }
    guard captureNanoseconds > 0 else {
      throw PhysicalJogObservationFailure.invalidCaptureTimestamp
    }
    guard capConfidence.isFinite, (0...1).contains(capConfidence) else {
      throw PhysicalJogObservationFailure.invalidCapConfidence
    }
    guard !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PhysicalJogObservationFailure.invalidAlgorithmRevision
    }
    self.frameID = frameID
    self.frameSHA256 = frameSHA256
    self.captureNanoseconds = captureNanoseconds
    self.cameraConfigurationID = cameraConfigurationID
    self.capCentroid = capCentroid
    self.capConfidence = capConfidence
    self.algorithmRevision = algorithmRevision
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
      }
  }
}

public struct PhysicalJogObservationRequest: Hashable, Sendable {
  public let motion: RelativeJogRequest
  public let split: ModelObservationSplit

  public init(motion: RelativeJogRequest, split: ModelObservationSplit) {
    self.motion = motion
    self.split = split
  }
}

public struct PhysicalJogModelObservationPair: Hashable, Sendable {
  public let beforeEvidence: PhysicalModelObservationEvidence
  public let afterEvidence: PhysicalModelObservationEvidence
  public let beforeObservation: DrawingModelTrainingObservation
  public let afterObservation: DrawingModelTrainingObservation

  public init(
    beforeEvidence: PhysicalModelObservationEvidence,
    afterEvidence: PhysicalModelObservationEvidence,
    beforeObservation: DrawingModelTrainingObservation,
    afterObservation: DrawingModelTrainingObservation
  ) {
    self.beforeEvidence = beforeEvidence
    self.afterEvidence = afterEvidence
    self.beforeObservation = beforeObservation
    self.afterObservation = afterObservation
  }
}

/// Paired controller and camera evidence around one accepted-and-completed jog.
/// Motion authority remains in `MotionOutcome`; this value only records an
/// observation after that independent outcome is known to be completed.
public struct PhysicalJogObservation: Hashable, Sendable {
  public let observationID: String
  public let request: PhysicalJogObservationRequest
  public let startPosition: MachinePosition
  public let startControllerSampleNanoseconds: UInt64
  public let finalPosition: MachinePosition
  public let finalControllerSampleNanoseconds: UInt64
  public let before: VisibleToolFrameObservation
  public let after: VisibleToolFrameObservation

  public var cameraDelta: Vector2<CameraPixelSpace> {
    // Construction validates both finite points, so this cannot fail.
    try! before.capCentroid.vector(to: after.capCentroid)
  }

  package init(
    observationID: String,
    request: PhysicalJogObservationRequest,
    startPosition: MachinePosition,
    startControllerSampleNanoseconds: UInt64,
    finalPosition: MachinePosition,
    finalControllerSampleNanoseconds: UInt64,
    before: VisibleToolFrameObservation,
    after: VisibleToolFrameObservation
  ) throws {
    guard !observationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PhysicalJogObservationFailure.invalidObservationID
    }
    guard before.cameraConfigurationID == after.cameraConfigurationID else {
      throw PhysicalJogObservationFailure.cameraConfigurationChanged
    }
    guard before.algorithmRevision == after.algorithmRevision else {
      throw PhysicalJogObservationFailure.algorithmRevisionChanged(
        before: before.algorithmRevision,
        after: after.algorithmRevision
      )
    }
    guard after.frameID != before.frameID,
      after.captureNanoseconds > before.captureNanoseconds
    else {
      throw PhysicalJogObservationFailure.postFrameNotNewer
    }
    guard startControllerSampleNanoseconds > 0,
      finalControllerSampleNanoseconds >= startControllerSampleNanoseconds
    else {
      throw PhysicalJogObservationFailure.invalidControllerSampleOrder
    }
    guard before.captureNanoseconds <= startControllerSampleNanoseconds else {
      throw PhysicalJogObservationFailure.beforeFrameAfterStartControllerSample(
        frameCaptureNanoseconds: before.captureNanoseconds,
        controllerSampleNanoseconds: startControllerSampleNanoseconds
      )
    }
    guard after.captureNanoseconds > finalControllerSampleNanoseconds else {
      throw PhysicalJogObservationFailure.afterFrameNotNewerThanFinalControllerSample(
        frameCaptureNanoseconds: after.captureNanoseconds,
        controllerSampleNanoseconds: finalControllerSampleNanoseconds
      )
    }
    self.observationID = observationID
    self.request = request
    self.startPosition = startPosition
    self.startControllerSampleNanoseconds = startControllerSampleNanoseconds
    self.finalPosition = finalPosition
    self.finalControllerSampleNanoseconds = finalControllerSampleNanoseconds
    self.before = before
    self.after = after
  }

  /// Converts both exact camera observations through one supplied
  /// registration. The evidence cites that registration and the model
  /// constructors verify the same identity before applying its transform.
  public func modelObservationPair(
    using registration: FieldRegistration
  ) throws -> PhysicalJogModelObservationPair {
    let beforeEvidence = try evidence(
      visible: before,
      position: startPosition,
      controllerSampleNanoseconds: startControllerSampleNanoseconds,
      registration: registration
    )
    let afterEvidence = try evidence(
      visible: after,
      position: finalPosition,
      controllerSampleNanoseconds: finalControllerSampleNanoseconds,
      registration: registration
    )
    let beforeID = "\(observationID):before"
    let afterID = "\(observationID):after"
    let beforeObservation = try DrawingModelTrainingObservation.physical(
      evidence: beforeEvidence,
      registration: registration,
      split: request.split,
      observationID: beforeID,
      algorithmRevision: before.algorithmRevision
    )
    let afterObservation = try DrawingModelTrainingObservation.physical(
      evidence: afterEvidence,
      registration: registration,
      split: request.split,
      observationID: afterID,
      algorithmRevision: after.algorithmRevision
    )
    return PhysicalJogModelObservationPair(
      beforeEvidence: beforeEvidence,
      afterEvidence: afterEvidence,
      beforeObservation: beforeObservation,
      afterObservation: afterObservation
    )
  }

  private func evidence(
    visible: VisibleToolFrameObservation,
    position: MachinePosition,
    controllerSampleNanoseconds: UInt64,
    registration: FieldRegistration
  ) throws -> PhysicalModelObservationEvidence {
    try PhysicalModelObservationEvidence(
      frameID: visible.frameID.rawValue,
      contentSHA256: visible.frameSHA256,
      captureNanoseconds: visible.captureNanoseconds,
      cameraConfigurationID: visible.cameraConfigurationID,
      measuredCameraPoint: visible.capCentroid,
      measurementConfidence: visible.capConfidence,
      controllerPosition: position.point,
      controllerSampleNanoseconds: controllerSampleNanoseconds,
      fieldRegistrationID: registration.id
    )
  }
}

public enum PhysicalJogObservationOutcome: Hashable, Sendable {
  case recorded(PhysicalJogObservation)
  case notRecorded(
    motionOutcome: MotionOutcome?,
    failure: PhysicalJogObservationFailure
  )

  public var motionOutcome: MotionOutcome? {
    switch self {
    case .recorded(let observation):
      return .acceptedThenCompleted(finalPosition: observation.finalPosition)
    case .notRecorded(let motionOutcome, _):
      return motionOutcome
    }
  }

  public static func resolve(
    motionOutcome: MotionOutcome,
    observation: @autoclosure () throws -> PhysicalJogObservation
  ) -> Self {
    guard case .acceptedThenCompleted(let completedPosition) = motionOutcome else {
      return .notRecorded(
        motionOutcome: motionOutcome,
        failure: .motionNotCompleted(motionOutcome)
      )
    }
    do {
      let observation = try observation()
      guard observation.finalPosition == completedPosition else {
        return .notRecorded(
          motionOutcome: motionOutcome,
          failure: .motionNotCompleted(motionOutcome)
        )
      }
      return .recorded(observation)
    } catch let failure as PhysicalJogObservationFailure {
      return .notRecorded(motionOutcome: motionOutcome, failure: failure)
    } catch {
      return .notRecorded(
        motionOutcome: motionOutcome,
        failure: .motionNotCompleted(motionOutcome)
      )
    }
  }
}
