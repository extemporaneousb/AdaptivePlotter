import CryptoKit
import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime

public protocol PlotterDrawingDraftPaperPersistence: Sendable {
  func load() async -> PaperCoverageObservation?
  func save(_ observation: PaperCoverageObservation) async throws
  func clear() async throws
}

public actor PlotterDrawingDraftTransientPaperPersistence:
  PlotterDrawingDraftPaperPersistence
{
  private var observation: PaperCoverageObservation?

  public init(observation: PaperCoverageObservation? = nil) {
    self.observation = observation
  }

  public func load() -> PaperCoverageObservation? { observation }

  public func save(_ observation: PaperCoverageObservation) {
    self.observation = observation
  }

  public func clear() {
    observation = nil
  }
}

/// Session-local placement context before pen-tip registration. This is a planned
/// cap-map projection, never paper coverage or accepted calibration evidence.
public struct PlotterDrawingDraftPlacementGuide: Hashable, Sendable {
  public let opticalConfiguration: CameraOpticalConfigurationIdentity
  public let machineCameraRevision: LearningArtifactRevisionID
  public let region: DrawableMachineRegion
  public let geometry: [CameraPixelGeometry]

  public init(opticalConfiguration: CameraOpticalConfigurationIdentity,
    machineCameraRevision: LearningArtifactRevisionID, region: DrawableMachineRegion,
    geometry: [CameraPixelGeometry]) {
    self.opticalConfiguration = opticalConfiguration
    self.machineCameraRevision = machineCameraRevision
    self.region = region
    self.geometry = geometry
  }

  public static let qualification = "Approximate cap-map placement: pen-tip offset is unknown and projection may extrapolate beyond camera calibration. This does not accept tip calibration or enable calibrated drawing."
}

public struct PlotterDrawingDraftSheetPlacementAssertion: Hashable, Sendable {
  public let paper: PaperRevisionContext
  public let toolAssemblyRevision: ToolAssemblyRevision
  public let frame: PlotterExactFrameReference
  public let guide: PlotterDrawingDraftPlacementGuide

  public func isCurrent(in facts: PlotterDrawingDraftExternalFactRevisions) -> Bool {
    paper == facts.paper && toolAssemblyRevision == facts.toolAssemblyRevision
      && guide == facts.placementGuide && guide.opticalConfiguration == facts.opticalConfiguration
      && frame.source == facts.displayedFrame?.source
      && frame.cameraConfigurationID == facts.displayedFrame?.cameraConfigurationID
  }
}

public struct PlotterDrawingDraftExternalFactRevisions: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let placementGuide: PlotterDrawingDraftPlacementGuide?
  public let interactiveLearningIsComplete: Bool
  public let registrationRevisionID: LearningArtifactRevisionID?
  public let opticalConfiguration: CameraOpticalConfigurationIdentity?
  public let drawableRegion: DrawableMachineRegion?
  public let drawingBorderBounds: AxisAlignedBounds<MachineSpace>?
  public let toolAssemblyRevision: ToolAssemblyRevision
  public let paper: PaperRevisionContext
  public let displayedFrame: PlotterExactFrameReference?
  public let runInProgress: Bool
  public let terminalRequiresNewPlan: Bool
  public let coverageRecordIDs: [DrawingEvidenceRecordID]
  public let drawingArchiveIsAvailable: Bool
  public let materialContextHash: PlotterModel.Digest?

  /// A sealed experiment selection consumes the current archive and physical
  /// context. A newer frame from the same stream does not change that selection.
  fileprivate func matchesExperimentSelection(_ other: Self) -> Bool {
    guard displayedFrame?.source == other.displayedFrame?.source,
      displayedFrame?.cameraConfigurationID == other.displayedFrame?.cameraConfigurationID,
      displayedFrame?.width == other.displayedFrame?.width,
      displayedFrame?.height == other.displayedFrame?.height,
      displayedFrame?.rowBytes == other.displayedFrame?.rowBytes,
      displayedFrame?.pixelFormat == other.displayedFrame?.pixelFormat else { return false }
    return replacingFrame(with: other.displayedFrame) == other
  }

  private func replacingFrame(with frame: PlotterExactFrameReference?) -> Self {
    Self(environment: environment, interactiveLearningIsComplete: interactiveLearningIsComplete,
      registrationRevisionID: registrationRevisionID, opticalConfiguration: opticalConfiguration,
      drawableRegion: drawableRegion, toolAssemblyRevision: toolAssemblyRevision,
      paper: paper, displayedFrame: frame, runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan, coverageRecordIDs: coverageRecordIDs,
      drawingArchiveIsAvailable: drawingArchiveIsAvailable, drawingBorderBounds: drawingBorderBounds,
      materialContextHash: materialContextHash, placementGuide: placementGuide)
  }

  public init(
    environment: PlotterEnvironment,
    interactiveLearningIsComplete: Bool,
    registrationRevisionID: LearningArtifactRevisionID?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    drawableRegion: DrawableMachineRegion?,
    toolAssemblyRevision: ToolAssemblyRevision,
    paper: PaperRevisionContext,
    displayedFrame: PlotterExactFrameReference?,
    runInProgress: Bool,
    terminalRequiresNewPlan: Bool,
    coverageRecordIDs: [DrawingEvidenceRecordID] = [],
    drawingArchiveIsAvailable: Bool = true,
    drawingBorderBounds: AxisAlignedBounds<MachineSpace>? = nil,
    materialContextHash: PlotterModel.Digest? = nil,
    placementGuide: PlotterDrawingDraftPlacementGuide? = nil
  ) {
    self.environment = environment
    self.placementGuide = placementGuide
    self.interactiveLearningIsComplete = interactiveLearningIsComplete
    self.registrationRevisionID = registrationRevisionID
    self.opticalConfiguration = opticalConfiguration
    self.drawingBorderBounds = drawingBorderBounds
    self.drawableRegion = drawableRegion
    self.toolAssemblyRevision = toolAssemblyRevision
    self.paper = paper
    self.displayedFrame = displayedFrame
    self.runInProgress = runInProgress
    self.terminalRequiresNewPlan = terminalRequiresNewPlan
    self.coverageRecordIDs = coverageRecordIDs
    self.drawingArchiveIsAvailable = drawingArchiveIsAvailable
    self.materialContextHash = materialContextHash
  }
}

public struct PlotterDrawingDraftExternalFacts: Hashable, Sendable {
  public let revisions: PlotterDrawingDraftExternalFactRevisions
  public let displayedFrame: DisplayedFrame?
  // Stream identity remains available when preview pixels have not been hashed.
  // It can validate existing paper context, never create exact-frame evidence.
  public let cameraSource: FrameSourceIdentity?
  public let cameraConfigurationID: CameraConfigurationID?
  public let registration: TipCameraRegistration?
  /// Existing archive records, including ordinary drawings that may occupy a sheet.
  public let coverageRecords: [DrawingRunEvidenceRecord]

  public init(
    environment: PlotterEnvironment,
    interactiveLearningIsComplete: Bool,
    displayedFrame: DisplayedFrame?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?,
    registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?,
    toolAssemblyRevision: ToolAssemblyRevision,
    paper: PaperRevisionContext,
    runInProgress: Bool,
    terminalRequiresNewPlan: Bool,
    coverageRecords: [DrawingRunEvidenceRecord] = [],
    drawingArchiveIsAvailable: Bool = true,
    drawingBorderBounds: AxisAlignedBounds<MachineSpace>? = nil,
    materialContextHash: PlotterModel.Digest? = nil,
    placementGuide: PlotterDrawingDraftPlacementGuide? = nil
  ) {
    let exactFrameReference = displayedFrame?.plotterExactFrameReferenceIfMaterialized
    self.displayedFrame = exactFrameReference == nil ? nil : displayedFrame
    cameraSource = displayedFrame?.source
    cameraConfigurationID = displayedFrame?.frame.cameraConfigurationID
    self.registration = registration
    self.coverageRecords = coverageRecords
    revisions = PlotterDrawingDraftExternalFactRevisions(
      environment: environment,
      interactiveLearningIsComplete: interactiveLearningIsComplete,
      registrationRevisionID: registration?.acceptedRevisionID,
      opticalConfiguration: opticalConfiguration,
      drawableRegion: drawableRegion,
      toolAssemblyRevision: toolAssemblyRevision,
      paper: paper,
      displayedFrame: exactFrameReference,
      runInProgress: runInProgress,
      terminalRequiresNewPlan: terminalRequiresNewPlan,
      coverageRecordIDs: coverageRecords.map(\.recordID),
      drawingArchiveIsAvailable: drawingArchiveIsAvailable,
      drawingBorderBounds: drawingBorderBounds,
      materialContextHash: materialContextHash, placementGuide: placementGuide
    )
  }
}

extension PlotterDrawingDraftExternalFacts {
  public var paperAcceptanceUnavailableReason: String? {
    Self.paperAcceptanceUnavailableReason(frame: displayedFrame,
      opticalConfiguration: revisions.opticalConfiguration, registration: registration,
      drawableRegion: revisions.drawableRegion, placementGuide: revisions.placementGuide,
      paper: revisions.paper, toolAssemblyRevision: revisions.toolAssemblyRevision,
      runInProgress: revisions.runInProgress, terminalRequiresNewPlan: revisions.terminalRequiresNewPlan)
  }

  /// Admission can inspect preview identity without hashing pixels. Submission
  /// additionally requires the materialized exact frame in ExternalFacts.
  public static func paperAcceptanceUnavailableReason(frame: DisplayedFrame?,
    opticalConfiguration: CameraOpticalConfigurationIdentity?, registration: TipCameraRegistration?,
    drawableRegion: DrawableMachineRegion?, placementGuide: PlotterDrawingDraftPlacementGuide?,
    paper: PaperRevisionContext, toolAssemblyRevision: ToolAssemblyRevision,
    runInProgress: Bool, terminalRequiresNewPlan: Bool = false) -> String? {
    guard !runInProgress else { return "Wait for the current drawing run and evidence capture to settle." }
    guard !terminalRequiresNewPlan else { return "Use Prepare Next Drawing to clear the retained terminal before editing a new plan." }
    guard let frame else { return "Show the current Plotter Video frame before accepting this sheet." }
    guard let optical = opticalConfiguration, optical.source == frame.source,
      optical.width == frame.frame.width, optical.height == frame.frame.height,
      optical.pixelFormat == frame.frame.pixelFormat else {
      return "Show the compatible calibration camera before accepting sheet coverage."
    }
    if let registration {
      guard optical == registration.applicability.opticalConfiguration,
        toolAssemblyRevision == registration.applicability.toolAssembly,
        paper.contactPlane == registration.applicability.paperContactPlane else {
        return "Show the compatible calibration camera, tool and contact plane before accepting sheet coverage."
      }
      guard drawableRegion != nil else { return "Restore the accepted Drawing Boundary before accepting sheet coverage." }
    } else {
      guard let guide = placementGuide, !guide.geometry.isEmpty,
        guide.opticalConfiguration == optical else {
        return "Display the current Boundary and compatible camera calibration guide before accepting sheet placement."
      }
    }
    return nil
  }
}

public struct PlotterDrawingDraftProjectionReference: Hashable, Sendable {
  public let environment: PlotterEnvironment
  public let draftRevision: PlotterDrawingDraftRevision
  public let externalFacts: PlotterDrawingDraftExternalFactRevisions

  public init(
    environment: PlotterEnvironment,
    draftRevision: PlotterDrawingDraftRevision,
    externalFacts: PlotterDrawingDraftExternalFactRevisions
  ) {
    self.environment = environment
    self.draftRevision = draftRevision
    self.externalFacts = externalFacts
  }
}

public struct PlotterDrawingDraftSubmission: Hashable, Sendable {
  public let requestID: PlotterDrawingDraftRequestID
  public let projection: PlotterDrawingDraftProjectionReference
  public let intent: PlotterDrawingDraftIntent

  public init(
    requestID: PlotterDrawingDraftRequestID = PlotterDrawingDraftRequestID(),
    projection: PlotterDrawingDraftProjectionReference,
    intent: PlotterDrawingDraftIntent
  ) {
    self.requestID = requestID
    self.projection = projection
    self.intent = intent
  }
}

public enum PlotterDrawingDraftRefusalReason: Hashable, Sendable {
  case staleProjection
  case cancelled
  case retainedRunOwnsMutation
  case terminalRunRequiresHandoff
  case exactFrameMismatch
  case registrationUnavailable
  case drawableRegionUnavailable
  case invalidScale
  case invalidRotation
  case coverageExperimentUnavailable
  case planningFailed(String)
  case paperPersistenceFailed(String)
}

public struct PlotterDrawingDraftRefusal: Hashable, Sendable {
  public let requestID: PlotterDrawingDraftRequestID
  public let comparedDraftRevision: PlotterDrawingDraftRevision
  public let comparedExternalFacts: PlotterDrawingDraftExternalFactRevisions
  public let owner: EpisodeAuthorityID
  public let reason: PlotterDrawingDraftRefusalReason
  public let remedy: String

  public init(
    requestID: PlotterDrawingDraftRequestID,
    comparedDraftRevision: PlotterDrawingDraftRevision,
    comparedExternalFacts: PlotterDrawingDraftExternalFactRevisions,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingDraftRefusalReason,
    remedy: String
  ) {
    self.requestID = requestID
    self.comparedDraftRevision = comparedDraftRevision
    self.comparedExternalFacts = comparedExternalFacts
    self.owner = owner
    self.reason = reason
    self.remedy = remedy
  }
}

public enum PlotterDrawingDraftPreviewStatus: Hashable, Sendable {
  case unavailable(owner: EpisodeAuthorityID, remedy: String)
  case outsideDrawableRegion(reason: String)
  case diagnosticOnly(TipApplicabilityEvidenceLimitation)
  case ready
}

public struct PlotterDrawingDraftPreview: Hashable, Sendable {
  public let displayedFrame: DisplayedFrame
  public let strokes: [Polyline<CameraPixelSpace>]
  public let bounds: AxisAlignedBounds<CameraPixelSpace>?
  public let programContentHash: PlotterModel.Digest
  public let planRevisionID: ExecutionPlanRevisionID?
  public let status: PlotterDrawingDraftPreviewStatus
}

/// Paper polygons are presentation-safe only on the exact frame whose bytes
/// the operator accepted. Assertion currentness is tracked independently.
public struct PlotterDrawingDraftPaperCoverageDisplay: Hashable, Sendable {
  public let observationID: PaperCoverageObservationID
  public let source: FrameSourceIdentity
  public let frame: ExactFrameProvenance
  public let polygon: [Point2<CameraPixelSpace>]
}

public struct PlotterDrawingDraftSnapshot: Hashable, Sendable {
  public let projection: PlotterDrawingDraftProjectionReference
  public let isTargetVisible: Bool
  public let drawBorder: Bool
  public let catalog: [DrawingProgramCatalogEntry]
  public let selectedCatalogItemID: DrawingCatalogEntryID?
  public let evidenceRole: BorderValidationEvidenceRole
  public let uniformScale: Double
  public let allowedScale: ClosedRange<Double>
  public let rotationDegrees: Double
  public let machineCenter: Point2<MachineSpace>?
  public let centerCameraPixel: Point2<CameraPixelSpace>?
  public let placementID: UUID
  public let program: DrawingProgram?
  public let plan: ExecutionPlanRevision?
  /// The existing planner's artwork result before optional border composition.
  /// Presentation consumers must still match its source program and region.
  public let artworkPlan: ExecutionPlanRevision?
  public let planningRefusal: PlotterDrawingDraftRefusal?
  public let preview: PlotterDrawingDraftPreview?
  public let sheetPlacementAssertion: PlotterDrawingDraftSheetPlacementAssertion?
  public var sheetPlacementIsCurrent: Bool { sheetPlacementAssertion?.isCurrent(in: projection.externalFacts) == true }
  public let paperCoverageObservation: PaperCoverageObservation?
  public let paperCoverageIsCurrent: Bool
  public let paperCoverageDisplay: PlotterDrawingDraftPaperCoverageDisplay?
  public let lastSubmissionRefusal: PlotterDrawingDraftRefusal?
  public let coverageExperiment: DrawingCoverageExperiment?
  public let coverageAssessment: DrawingCoverageAssessment?
  public let coverageUnavailableReason: String?
  public let residualRecords: [DrawingResidualRecordSummary]
  public let residualAnalysis: DrawingRetrospectiveResidualAnalysis?

  public static func initial(
    environment: PlotterEnvironment,
    toolAssemblyRevision: ToolAssemblyRevision,
    paper: PaperRevisionContext
  ) -> Self {
    let facts = PlotterDrawingDraftExternalFactRevisions(
      environment: environment,
      interactiveLearningIsComplete: false,
      registrationRevisionID: nil,
      opticalConfiguration: nil,
      drawableRegion: nil,
      toolAssemblyRevision: toolAssemblyRevision,
      paper: paper,
      displayedFrame: nil,
      runInProgress: false,
      terminalRequiresNewPlan: false
    )
    return Self(
      projection: PlotterDrawingDraftProjectionReference(
        environment: environment,
        draftRevision: PlotterDrawingDraftRevision(rawValue: 0),
        externalFacts: facts
      ),
      isTargetVisible: false,
      drawBorder: false,
      catalog: DrawingProgramCatalog.entries,
      selectedCatalogItemID: .square,
      evidenceRole: .ordinaryDrawing,
      uniformScale: 0.25,
      allowedScale: 0.02...1,
      rotationDegrees: 0,
      machineCenter: nil,
      centerCameraPixel: nil,
      placementID: UUID(),
      program: nil,
      plan: nil,
      artworkPlan: nil,
      planningRefusal: nil,
      preview: nil,
      sheetPlacementAssertion: nil,
      paperCoverageObservation: nil,
      paperCoverageIsCurrent: false,
      paperCoverageDisplay: nil,
      lastSubmissionRefusal: nil,
      coverageExperiment: nil, coverageAssessment: nil, coverageUnavailableReason: nil,
      residualRecords: [], residualAnalysis: nil
    )
  }
}

public enum PlotterDrawingDraftSubmissionDisposition: Hashable, Sendable {
  case applied
  case refused(PlotterDrawingDraftRefusal)
}

public struct PlotterDrawingDraftSubmissionResult: Hashable, Sendable {
  public let disposition: PlotterDrawingDraftSubmissionDisposition
  public let snapshot: PlotterDrawingDraftSnapshot
}

public struct PlotterDrawingDraftPlanBuild: Hashable, Sendable {
  public let program: DrawingProgram?
  public let center: Point2<MachineSpace>?
  public let allowedScale: ClosedRange<Double>
  public let plan: ExecutionPlanRevision?
  public let artworkPlan: ExecutionPlanRevision?
  public let failure: String?
}

/// The only upper-layer route into `DrawingPlanner`. The planner retains all
/// geometry, containment, checkpoint, and content-addressed identity authority.
public enum PlotterDrawingPlanningAdapter {
  public static func buildDraft(
    program: DrawingProgram,
    machineCenter: Point2<MachineSpace>?,
    uniformScale: Double,
    rotationDegrees: Double,
    drawableRegion: DrawableMachineRegion,
    registration: TipCameraRegistration,
    drawBorder: Bool = false,
    drawingBorderBounds: AxisAlignedBounds<MachineSpace>? = nil,
    materialContextHash: PlotterModel.Digest? = nil
  ) -> PlotterDrawingDraftPlanBuild {
    var allowedScale = 0.02...1.0
    do {
      let cameraGeometry = try cameraGeometry(for: program, registration: registration)
      allowedScale = scaleRange(extent: program.fieldExtent,
        rotationDegrees: rotationDegrees, region: drawableRegion, cameraGeometry: cameraGeometry)
      let center: Point2<MachineSpace>
      if let machineCenter {
        center = machineCenter
      } else {
        center = try Point2<MachineSpace>(
          x: (drawableRegion.effectiveBounds.minX + drawableRegion.effectiveBounds.maxX) / 2,
          y: (drawableRegion.effectiveBounds.minY + drawableRegion.effectiveBounds.maxY) / 2
        )
      }
      let placement = try DrawingPlacement(
        fieldAnchor: Point2(
          x: program.fieldExtent.width / 2,
          y: program.fieldExtent.height / 2
        ),
        machineAnchor: center,
        uniformScale: uniformScale,
        rotationRadians: rotationDegrees * .pi / 180,
        cameraGeometry: cameraGeometry
      )
      var plan = try DrawingPlanner.plan(
        program: program,
        placement: placement,
        drawableRegion: drawableRegion,
        provenance: try planningProvenance(for: registration, materialContextHash: materialContextHash),
        boundaryPolicy: cameraGeometry == nil ? .rejectOutside : .clipToDrawableRegion
      )
      var executionProgram = program
      let artworkPlan = plan
      if drawBorder {
        guard let drawingBorderBounds else {
          throw PlotterModelError.invalidValue("The calibrated Drawing Border is unavailable.")
        }
        let composed = try includingBorder(program: program, artworkPlan: plan,
          bounds: drawingBorderBounds, region: drawableRegion)
        executionProgram = composed.program
        plan = try DrawingPlanner.plan(program: composed.program, placement: composed.placement,
          drawableRegion: drawableRegion, provenance: planningProvenance(for: registration, materialContextHash: materialContextHash),
          boundaryPolicy: cameraGeometry == nil ? .rejectOutside : .clipToDrawableRegion)
      }
      return PlotterDrawingDraftPlanBuild(
        program: executionProgram,
        center: center,
        allowedScale: allowedScale,
        plan: plan,
        artworkPlan: artworkPlan,
        failure: nil
      )
    } catch {
      return PlotterDrawingDraftPlanBuild(
        program: program,
        center: machineCenter,
        allowedScale: allowedScale,
        plan: nil,
        artworkPlan: nil,
        failure: String(describing: error)
      )
    }
  }

  /// Compose a new ordinary program while retaining all original artwork points.
  /// The accepted border geometry is supplied by its existing calibration owner;
  /// the normal planner still checks every stroke and creates every checkpoint.
  private static func includingBorder(
    program: DrawingProgram, artworkPlan: ExecutionPlanRevision,
    bounds: AxisAlignedBounds<MachineSpace>, region: DrawableMachineRegion
  ) throws -> (program: DrawingProgram, placement: DrawingPlacement) {
    let points: [Point2<MachineSpace>] = try [
      Point2(x: bounds.minX, y: bounds.minY), Point2(x: bounds.minX, y: bounds.maxY),
      Point2(x: bounds.maxX, y: bounds.maxY), Point2(x: bounds.maxX, y: bounds.minY),
      Point2(x: bounds.minX, y: bounds.minY),
    ]
    guard points.allSatisfy({ region.contains($0) }) else {
      throw PlotterModelError.invalidValue("The calibrated Drawing Border is outside the drawable region.")
    }
    let inverse = try artworkPlan.placement.fieldToMachineTransform.inverted()
    let borderPoints = try points.map { try inverse.applying(to: $0) }
    let minX = min(0, borderPoints.map(\.x).min()!), minY = min(0, borderPoints.map(\.y).min()!)
    let maxX = max(program.fieldExtent.width, borderPoints.map(\.x).max()!)
    let maxY = max(program.fieldExtent.height, borderPoints.map(\.y).max()!)
    func shifted(_ point: Point2<FieldSpace>) throws -> Point2<FieldSpace> {
      try Point2(x: point.x - minX, y: point.y - minY)
    }
    let boundsHash = try canonicalDigest(of: bounds)
    let cameraMarker = artworkPlan.placement.cameraGeometry == nil ? "" : "|camera-geometry-v1"
    let seed = "ordinary-drawing-border-v1|\(program.contentHash)|\(artworkPlan.contentHash)|\(boundsHash)"
    let bytes = Array(SHA256.hash(data: Data(seed.utf8)).prefix(16))
    let id = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
      bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    guard let style = program.strokes.first?.style else {
      throw PlotterModelError.invalidValue("The artwork has no pen style for its border.")
    }
    // The frame is the first ordinary stroke, before any artwork can be stopped.
    var strokes = [LogicalStroke(id: StrokeID(id), path: try Polyline(points: borderPoints.map(shifted)),
      style: style, semanticRole: .drawing, ordering: 0)]
    strokes += try program.strokes.enumerated().map { index, stroke in
      LogicalStroke(id: stroke.id, path: try Polyline(points: stroke.path.points.map(shifted)),
        style: stroke.style, semanticRole: stroke.semanticRole, ordering: UInt32(index + 1))
    }
    return (try DrawingProgram(id: ProgramID(id),
      fieldExtent: Size2(width: maxX - minX, height: maxY - minY),
      strokes: strokes, source: DrawingSourceProvenance(kind: program.source.kind,
        sourceIdentifier: "\(program.source.sourceIdentifier)\(cameraMarker)|draw-border-v1|artwork=\(program.contentHash)")),
      try DrawingPlacement(fieldAnchor: shifted(artworkPlan.placement.fieldAnchor),
        machineAnchor: artworkPlan.placement.machineAnchor,
        uniformScale: artworkPlan.placement.uniformScale,
        rotationRadians: artworkPlan.placement.rotationRadians,
        cameraGeometry: artworkPlan.placement.cameraGeometry))
  }

  /// Center the transformed, un-clipped artwork bounds. Using the cropped plan
  /// would make repeated Center actions drift as different strokes enter view.
  public static func centeredMachineAnchor(
    program: DrawingProgram, uniformScale: Double, rotationDegrees: Double,
    drawableRegion: DrawableMachineRegion, registration: TipCameraRegistration
  ) throws -> Point2<MachineSpace> {
    let placement = try DrawingPlacement(
      fieldAnchor: Point2(x: program.fieldExtent.width / 2, y: program.fieldExtent.height / 2),
      machineAnchor: Point2(x: 0, y: 0), uniformScale: uniformScale,
      rotationRadians: rotationDegrees * .pi / 180,
      cameraGeometry: cameraGeometry(for: program, registration: registration))
    let points = try program.strokes.flatMap { try placement.applying(to: $0.path).points }
    let region = drawableRegion.effectiveBounds
    return try Point2(x: (region.minX + region.maxX - points.map(\.x).min()! - points.map(\.x).max()!) / 2,
      y: (region.minY + region.maxY - points.map(\.y).min()! - points.map(\.y).max()!) / 2)
  }

  /// Explicit command-distance targets and the coverage experiment retain their
  /// authored controller geometry. Guided Learning has its own planning route.
  public static func cameraGeometry(
    for program: DrawingProgram?, catalogItemID: DrawingCatalogEntryID? = nil,
    registration: TipCameraRegistration
  ) throws -> DrawingCameraGeometry? {
    let controllerTargets: [DrawingCatalogEntryID] = [.metricSquare40, .metricRectangle40x20]
    if let program {
      if program.source.kind == "adaptive-coverage-v1" { return nil }
      if program.source.kind == "built-in-vector-catalog",
        controllerTargets.contains(where: {
          program.source.sourceIdentifier == DrawingProgramCatalog.entry(for: $0).sourceIdentifier
        }) { return nil }
    } else if let catalogItemID, controllerTargets.contains(catalogItemID) { return nil }
    return try DrawingCameraGeometry(cameraFromMachine: registration.cameraFromMachine)
  }

  /// The same corrected and rotated field bounds drive the slider and Fit.
  public static func scaleRange(
    extent: Size2<FieldSpace>, rotationDegrees: Double, region: DrawableMachineRegion,
    cameraGeometry: DrawingCameraGeometry? = nil
  ) -> ClosedRange<Double> {
    let angle = rotationDegrees * .pi / 180
    let c = cos(angle), s = sin(angle)
    let k = cameraGeometry?.commandCorrection
    let a = k?.m11 ?? 1, b = k?.m12 ?? 0, d = k?.m21 ?? 0, e = k?.m22 ?? 1
    let width = extent.width * abs(a * c + b * s) + extent.height * abs(-a * s + b * c)
    let height = extent.width * abs(d * c + e * s) + extent.height * abs(-d * s + e * c)
    let bounds = region.effectiveBounds
    let maximum = min((bounds.maxX - bounds.minX) / width,
      (bounds.maxY - bounds.minY) / height) * 0.9
    return min(0.02, maximum)...maximum
  }

  package static func planRetainedDrawingBorder(
    program: DrawingProgram,
    placement: DrawingPlacement,
    drawableRegion: DrawableMachineRegion,
    provenance: DrawingPlanningProvenance
  ) throws -> ExecutionPlanRevision {
    try DrawingPlanner.plan(
      program: program,
      placement: placement,
      drawableRegion: drawableRegion,
      provenance: provenance
    )
  }

  package static func planningProvenance(
    for registration: TipCameraRegistration, materialContextHash: PlotterModel.Digest? = nil
  ) throws -> DrawingPlanningProvenance {
    let digest = try registration.drawingEvidenceContentHash()
    return DrawingPlanningProvenance(
      modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: digest,
      registrationRevisionID: DrawingRegistrationRevisionID(
        registration.acceptedRevisionID.rawValue
      ),
      registrationContentHash: digest, materialContextHash: materialContextHash
    )
  }
}

public actor PlotterDrawingDraftRuntime {
  private struct SourceState: Sendable {
    var revision = PlotterDrawingDraftRevision(rawValue: 0)
    var isTargetVisible = false
    var drawBorder = false
    var selectedCatalogItemID: DrawingCatalogEntryID = .square
    var suppliedProgram: DrawingProgram?
    var evidenceRole: BorderValidationEvidenceRole = .ordinaryDrawing
    var uniformScale = 0.25
    var rotationDegrees = 0.0
    var machineCenter: Point2<MachineSpace>?
    var placementID = UUID()
    var program: DrawingProgram?
    var plan: ExecutionPlanRevision?
    var artworkPlan: ExecutionPlanRevision?
    var artworkExecutionPlanHash: PlotterModel.Digest?
    var planningRefusal: PlotterDrawingDraftRefusal?
    var preview: PlotterDrawingDraftPreview?
    var sheetPlacementAssertion: PlotterDrawingDraftSheetPlacementAssertion?
    var paperCoverageObservation: PaperCoverageObservation?
    var lastSubmissionRefusal: PlotterDrawingDraftRefusal?
    var coverageExperiment: DrawingCoverageExperiment?
    var coverageAssessment: DrawingCoverageAssessment?
    var coverageRecordIDs: [DrawingEvidenceRecordID]?
    var coverageUnavailableReason: String?
    var selectedResidualRecordIDs: Set<DrawingEvidenceRecordID> = []
    var residualAnalysis: DrawingRetrospectiveResidualAnalysis?
    var derivationKey: DerivationKey?
    var previewDerivationIsAvailable = false
  }

  /// Geometry depends on artwork and calibration, not camera pixels, control
  /// progress, panel visibility, or the current Learning status.
  private struct DerivationKey: Equatable {
    let catalog: DrawingCatalogEntryID
    let suppliedProgramHash: PlotterModel.Digest?
    let drawBorder: Bool
    let drawingBorderBounds: AxisAlignedBounds<MachineSpace>?
    let center: Point2<MachineSpace>?
    let scale: Double
    let rotation: Double
    let registration: TipCameraRegistration?
    let region: DrawableMachineRegion?
    let tool: ToolAssemblyRevision
    let materialContextHash: PlotterModel.Digest?
    let paper: PaperRevisionContext
    let experiment: DrawingCoverageExperiment?
    let coverageRecords: [DrawingEvidenceRecordID]
    let opticalConfiguration: CameraOpticalConfigurationIdentity?

    init(state: SourceState, facts: PlotterDrawingDraftExternalFacts) {
      catalog = state.selectedCatalogItemID
      suppliedProgramHash = state.suppliedProgram?.contentHash
      drawBorder = state.drawBorder
      drawingBorderBounds = facts.revisions.drawingBorderBounds
      center = state.machineCenter
      scale = state.uniformScale
      rotation = state.rotationDegrees
      registration = facts.registration
      region = facts.revisions.drawableRegion
      tool = facts.revisions.toolAssemblyRevision
      materialContextHash = facts.revisions.materialContextHash
      paper = facts.revisions.paper
      experiment = state.coverageExperiment
      coverageRecords = facts.revisions.coverageRecordIDs
      opticalConfiguration = facts.revisions.opticalConfiguration
    }
  }

  package private(set) var derivationBuildCount = 0

  private enum Authority {
    static let draft = EpisodeAuthorityID(rawValue: "PlotterDrawingDraftRuntime")
    static let registration = EpisodeAuthorityID(rawValue: "TipCameraRegistration")
    static let region = EpisodeAuthorityID(rawValue: "PlotterModel.DrawableMachineRegion")
    static let camera = EpisodeAuthorityID(rawValue: "CameraEvidenceAuthority")
    static let run = EpisodeAuthorityID(rawValue: "PlotterDrawingRunAuthority")
    static let paper = EpisodeAuthorityID(rawValue: "PlotterPaperCoverageAuthority")
    static let planner = EpisodeAuthorityID(rawValue: "PlotterModel.ExecutionPlanRevision")
  }

  private let paperPersistence: any PlotterDrawingDraftPaperPersistence
  private let clock: any RuntimeClock
  private var states: [PlotterEnvironment: SourceState] = [:]
  private var latestFacts: [PlotterEnvironment: PlotterDrawingDraftExternalFacts] = [:]
  private var loadedPaperCoverage = false
  /// Actor reentrancy must not let a persistence suspension split validation
  /// from publication. Ownership stays with the current turn until it commits
  /// or refuses, and queued callers resume in arrival order.
  private var mutationBoundaryIsOccupied = false
  private struct MutationWaiter {
    let id: UUID
    let continuation: CheckedContinuation<Bool, Never>
  }
  private var mutationBoundaryWaiters: [MutationWaiter] = []
  package var pendingMutationCount: Int { mutationBoundaryWaiters.count }

  public init(
    paperPersistence: any PlotterDrawingDraftPaperPersistence =
      PlotterDrawingDraftTransientPaperPersistence(),
    clock: any RuntimeClock = SystemRuntimeClock()
  ) {
    self.paperPersistence = paperPersistence
    self.clock = clock
  }

  public func synchronize(
    _ facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSnapshot {
    guard await acquireMutationBoundary() else { return retainedSnapshot(facts: facts) }
    defer { releaseMutationBoundary() }
    guard !Task.isCancelled else { return retainedSnapshot(facts: facts) }
    return await synchronizeWithinMutationBoundary(facts)
  }

  private func synchronizeWithinMutationBoundary(
    _ facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSnapshot {
    await loadPaperCoverageIfNeeded()
    let environment = facts.revisions.environment
    latestFacts[environment] = facts
    var state = states[environment] ?? SourceState()
    rebuild(state: &state, facts: facts, requestID: nil)
    states[environment] = state
    return snapshot(state: state, facts: facts)
  }

  public func submit(
    _ submission: PlotterDrawingDraftSubmission,
    facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSubmissionResult {
    guard await acquireMutationBoundary() else { return cancelled(submission, facts: facts) }
    defer { releaseMutationBoundary() }
    guard !Task.isCancelled else { return cancelled(submission, facts: facts) }
    let current = await synchronizeWithinMutationBoundary(facts)
    guard !Task.isCancelled else { return cancelled(submission, facts: facts) }
    let environment = facts.revisions.environment
    var state = states[environment] ?? SourceState()
    let projectionMatches: Bool
    switch submission.intent {
    case .placeAtCameraPoint, .assertPaperCoverage:
      projectionMatches = submission.projection == current.projection
    case .prepareCoverageExperiment, .nextCoverageTrial:
      projectionMatches = submission.projection.environment == current.projection.environment
        && submission.projection.draftRevision == current.projection.draftRevision
        && submission.projection.externalFacts.matchesExperimentSelection(current.projection.externalFacts)
    default:
      // Artwork and absolute authoring choices do not interpret an earlier
      // camera observation or consume Learning/archive evidence. Rebuild them
      // against current facts even while those facts finish publication after
      // Apply Saved. Concurrent author edits still require their exact revision.
      projectionMatches = submission.projection.environment == current.projection.environment
        && submission.projection.draftRevision == current.projection.draftRevision
    }
    guard projectionMatches else {
      return refuse(
        submission,
        state: &state,
        facts: facts,
        owner: Authority.draft,
        reason: .staleProjection,
        remedy: "Use the current Drawing Studio projection and retry the requested edit."
      )
    }


    // Archive analysis is orthogonal to the current drawing. It does not
    // change the draft revision, placement, or any immutable run record.
    switch submission.intent {
    case .showTarget:
      state.isTargetVisible = true
    case .hideTarget:
      state.isTargetVisible = false
    case .selectResidualRecord(let id, let selected):
      if facts.coverageRecords.contains(where: { $0.recordID == id }) {
        if selected { state.selectedResidualRecordIDs.insert(id) }
        else { state.selectedResidualRecordIDs.remove(id) }
        state.residualAnalysis = nil
      }
    case .analyzeSelectedResiduals:
      let records = facts.coverageRecords.filter { state.selectedResidualRecordIDs.contains($0.recordID) }
      state.residualAnalysis = DrawingRetrospectiveResidualAnalysis.evaluate(
        records: records, registration: facts.registration)
    default: break
    }
    if submission.intent == .showTarget || submission.intent == .hideTarget {
      state.lastSubmissionRefusal = nil
      states[environment] = state
      return .init(disposition: .applied, snapshot: snapshot(state: state, facts: facts))
    }
    if case .selectResidualRecord = submission.intent {
      state.lastSubmissionRefusal = nil
      states[environment] = state
      return .init(disposition: .applied, snapshot: snapshot(state: state, facts: facts))
    }
    if submission.intent == .analyzeSelectedResiduals {
      state.lastSubmissionRefusal = nil
      states[environment] = state
      return .init(disposition: .applied, snapshot: snapshot(state: state, facts: facts))
    }

    guard !facts.revisions.runInProgress else {
      return refuse(
        submission,
        state: &state,
        facts: facts,
        owner: Authority.run,
        reason: .retainedRunOwnsMutation,
        remedy: "Wait for the current drawing run and evidence capture to settle."
      )
    }
    if facts.revisions.terminalRequiresNewPlan,
      submission.intent != .showTarget,
      submission.intent != .hideTarget
    {
      return refuse(
        submission,
        state: &state,
        facts: facts,
        owner: Authority.run,
        reason: .terminalRunRequiresHandoff,
        remedy: "Use Prepare Next Drawing to clear the retained terminal before editing a new plan."
      )
    }

    if state.coverageExperiment != nil {
      switch submission.intent {
      case .showTarget, .hideTarget, .beginNewPlan, .assertPaperCoverage,
        .nextCoverageTrial, .leaveCoverageExperiment, .prepareCoverageExperiment: break
      default:
        return refuse(submission, state: &state, facts: facts, owner: Authority.draft,
          reason: .coverageExperimentUnavailable,
          remedy: "Coverage geometry and evidence roles are sealed. Leave the experiment to author another drawing.")
      }
    }

    switch submission.intent {
    case .prepareCoverageExperiment, .nextCoverageTrial:
      do {
        guard facts.revisions.drawingArchiveIsAvailable else {
          throw PlotterModelError.invalidValue("Load the drawing archive before preparing or resuming an experiment.")
        }
        guard let registration = facts.registration,
          let region = facts.revisions.drawableRegion else {
          throw PlotterModelError.invalidValue("Restore current tip calibration and Drawing Boundary first.")
        }
        let prior = try PlotterDrawingPlanningAdapter.planningProvenance(for: registration, materialContextHash: facts.revisions.materialContextHash)
        if state.coverageExperiment == nil {
          // Resume from existing immutable source provenance. Never propose a
          // fresh overlapping design on a sheet with earlier experiment ink.
          if facts.coverageRecords.contains(where: {
            $0.paper == facts.revisions.paper && $0.role == .ordinaryDrawing
              && $0.executionFrontiers.commandedStrokeCount > 0
          }) {
            throw PlotterModelError.invalidValue("This sheet already has drawing ink. Replace the sheet before preparing coverage trials.")
          }
          if let priorRecord = facts.coverageRecords.last(where: {
            $0.paper == facts.revisions.paper && $0.program.source?.kind == DrawingCoverageExperiment.sourceKind
          }) {
            guard let descriptor = DrawingCoverageTrialDescriptor.decode(priorRecord.program.source) else {
              throw PlotterModelError.invalidValue("The sheet has unreadable experiment provenance. Use a new sheet.")
            }
            state.coverageExperiment = descriptor.experiment
          } else {
            state.coverageExperiment = try DrawingCoverageExperiment(region: region,
              registration: registration, prior: prior, paper: facts.revisions.paper,
              style: StrokeStyle(nominalLineWidth: 0.4,
                penProfileID: PenProfileID(facts.revisions.toolAssemblyRevision.rawValue)))
          }
          state.coverageRecordIDs = nil
        }
        guard let experiment = state.coverageExperiment,
          experiment.isCurrent(registration: registration, prior: prior,
            region: region, paper: facts.revisions.paper) else {
          throw PlotterModelError.invalidValue("Experiment provenance changed. Leave the experiment and use a new sheet.")
        }
        let assessment = DrawingCoverageAssessment.evaluate(experiment: experiment,
          records: facts.coverageRecords, registration: registration)
        state.coverageAssessment = assessment
        state.coverageRecordIDs = facts.revisions.coverageRecordIDs
        state.coverageUnavailableReason = nil
        if let blocker = assessment.blocker { throw PlotterModelError.invalidValue(blocker) }
        if let trial = assessment.nextTrial ?? experiment.trials.last(where: { assessment.attemptedIndices.contains($0.index) }) {
          state.suppliedProgram = try experiment.program(for: trial)
          state.isTargetVisible = true
          state.evidenceRole = trial.role
          state.machineCenter = experiment.center
          state.uniformScale = 1
          state.rotationDegrees = 0
          state.placementID = UUID()
        }
      } catch {
        if state.coverageExperiment != nil {
          state.derivationKey = nil
          state.plan = nil
          state.preview = nil
          state.coverageUnavailableReason = String(describing: error)
        }
        return refuse(submission, state: &state, facts: facts, owner: Authority.draft,
          reason: .coverageExperimentUnavailable, remedy: String(describing: error))
      }
    case .leaveCoverageExperiment:
      state.coverageExperiment = nil
      state.coverageAssessment = nil
      state.coverageRecordIDs = nil
      state.coverageUnavailableReason = nil
      state.suppliedProgram = nil
      state.evidenceRole = .ordinaryDrawing
      state.uniformScale = 0.25
      state.machineCenter = nil
      state.placementID = UUID()
    case .showTarget, .hideTarget:
      break // Applied above without changing execution identity.
    case .setDrawBorder(let enabled):
      state.drawBorder = enabled
      state.placementID = UUID()
    case .selectCatalogItem(let id):
      state.selectedCatalogItemID = id
      state.suppliedProgram = nil
      state.evidenceRole = .ordinaryDrawing
      state.placementID = UUID()
    case .selectProgram(let program):
      state.isTargetVisible = true
      state.suppliedProgram = program
      state.evidenceRole = .ordinaryDrawing
      state.uniformScale = min(state.uniformScale, allowedScale(state: state, facts: facts, includingCurrentScale: false).upperBound)
      state.placementID = UUID()
    case .placeAtCameraPoint(let placement):
      guard placement.frame == facts.revisions.displayedFrame else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.camera,
          reason: .exactFrameMismatch,
          remedy: "Place the target from the currently displayed exact frame."
        )
      }
      guard let registration = facts.registration,
        let inverse = try? registration.cameraFromMachine.inverted(),
        let point = try? inverse.applying(to: placement.point)
      else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.registration,
          reason: .registrationUnavailable,
          remedy: "Restore a current accepted pen-tip registration before placing the target."
        )
      }
      state.machineCenter = point
      state.placementID = UUID()
    case .setUniformScale(let scale):
      let allowed = allowedScale(state: state, facts: facts)
      guard scale.isFinite, scale > 0, allowed.contains(scale) else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.planner,
          reason: .invalidScale,
          remedy: "Choose a positive finite scale within the published allowed range."
        )
      }
      state.uniformScale = scale
      state.placementID = UUID()
    case .setRotationDegrees(let degrees):
      guard degrees.isFinite else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.planner,
          reason: .invalidRotation,
          remedy: "Choose a finite rotation in degrees."
        )
      }
      state.rotationDegrees = Self.normalizedDegrees(degrees)
      state.placementID = UUID()
    case .fitInDrawableRegion:
      guard let region = facts.revisions.drawableRegion else {
        return refuse(submission, state: &state, facts: facts, owner: Authority.region,
          reason: .drawableRegionUnavailable, remedy: "Restore the Drawing Boundary before fitting the target.")
      }
      // Fit changes size and position only. Rotation is authored intent and
      // must never change merely because another orientation occupies more area.
      state.uniformScale = allowedScale(state: state, facts: facts, includingCurrentScale: false).upperBound
      let bounds = region.effectiveBounds
      state.machineCenter = try? Point2(x: (bounds.minX + bounds.maxX) / 2,
        y: (bounds.minY + bounds.maxY) / 2)
      state.placementID = UUID()
    case .centerInDrawableRegion:
      guard let region = facts.revisions.drawableRegion,
        let registration = facts.registration,
        let program = authoredProgram(state: state, facts: facts),
        let center = try? PlotterDrawingPlanningAdapter.centeredMachineAnchor(
          program: program, uniformScale: state.uniformScale, rotationDegrees: state.rotationDegrees,
          drawableRegion: region, registration: registration)
      else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.region,
          reason: .drawableRegionUnavailable,
          remedy: "Restore the current accepted Drawing Boundary before centering the target."
        )
      }
      state.machineCenter = center
      state.placementID = UUID()
    case .beginNewPlan:
      state.drawBorder = false
      state.placementID = UUID()
    case .assertPaperCoverage:
      if let reason = facts.paperAcceptanceUnavailableReason {
        return refuse(submission, state: &state, facts: facts, owner: Authority.paper,
          reason: .registrationUnavailable, remedy: reason)
      }
      if facts.registration == nil, let frame = facts.revisions.displayedFrame,
        let guide = facts.revisions.placementGuide {
        state.sheetPlacementAssertion = PlotterDrawingDraftSheetPlacementAssertion(
          paper: facts.revisions.paper, toolAssemblyRevision: facts.revisions.toolAssemblyRevision,
          frame: frame, guide: guide)
        break
      }
      guard let frame = facts.displayedFrame,
        let registration = facts.registration,
        let bounds = facts.revisions.drawableRegion?.effectiveBounds
      else {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.paper,
          reason: .registrationUnavailable,
          remedy: "Display a current frame with accepted registration and Drawing Boundary first."
        )
      }
      do {
        let machineCorners: [Point2<MachineSpace>] = try [
          Point2(x: bounds.minX, y: bounds.minY),
          Point2(x: bounds.maxX, y: bounds.minY),
          Point2(x: bounds.maxX, y: bounds.maxY),
          Point2(x: bounds.minX, y: bounds.maxY),
        ]
        let polygon = try machineCorners.map {
          try registration.diagnosticProjection(at: $0).cameraPoint
        }
        let observation = try PaperCoverageObservation(
          paper: facts.revisions.paper,
          source: frame.source,
          frame: ExactFrameProvenance(frame: frame.frame),
          polygon: polygon,
          method: .operatorAccepted,
          observedAt: RuntimeTimestamp(
            monotonicNanoseconds: max(clock.nowNanoseconds(), frame.frame.captureNanoseconds)
          ),
          algorithmRevision: "operator-attested-drawing-boundary-diagnostic-projection-v3",
          opticalConfiguration: facts.revisions.opticalConfiguration,
          drawableRegion: facts.revisions.drawableRegion
        )
        if environment == .live {
          try await paperPersistence.save(observation)
        }
        state.paperCoverageObservation = observation
      } catch {
        return refuse(
          submission,
          state: &state,
          facts: facts,
          owner: Authority.paper,
          reason: .paperPersistenceFailed(String(describing: error)),
          remedy: "Resolve paper-coverage persistence and assert the current sheet again."
        )
      }
    case .selectResidualRecord, .analyzeSelectedResiduals:
      break // Handled above without changing execution identity.
    }

    state.revision = PlotterDrawingDraftRevision(rawValue: state.revision.rawValue &+ 1)
    state.lastSubmissionRefusal = nil
    rebuild(state: &state, facts: facts, requestID: submission.requestID)
    states[environment] = state
    return PlotterDrawingDraftSubmissionResult(
      disposition: .applied,
      snapshot: snapshot(state: state, facts: facts)
    )
  }

  package func clearPaperCoverageForRetainedPaperLifecycle(
    facts: PlotterDrawingDraftExternalFacts
  ) async -> PlotterDrawingDraftSubmissionResult {
    guard await acquireMutationBoundary() else {
      let current = retainedSnapshot(facts: facts)
      return cancelled(.init(projection: current.projection, intent: .assertPaperCoverage), facts: facts)
    }
    defer { releaseMutationBoundary() }
    let current = await synchronizeWithinMutationBoundary(facts)
    let request = PlotterDrawingDraftSubmission(
      projection: current.projection,
      intent: .assertPaperCoverage
    )
    let environment = facts.revisions.environment
    var state = states[environment] ?? SourceState()
    do {
      if environment == .live { try await paperPersistence.clear() }
      state.paperCoverageObservation = nil
      state.sheetPlacementAssertion = nil
      state.revision = PlotterDrawingDraftRevision(rawValue: state.revision.rawValue &+ 1)
      state.lastSubmissionRefusal = nil
      states[environment] = state
      return PlotterDrawingDraftSubmissionResult(
        disposition: .applied,
        snapshot: snapshot(state: state, facts: facts)
      )
    } catch {
      return refuse(
        request,
        state: &state,
        facts: facts,
        owner: Authority.paper,
        reason: .paperPersistenceFailed(String(describing: error)),
        remedy: "Resolve paper persistence before replacing its retained assertion."
      )
    }
  }

  private func loadPaperCoverageIfNeeded() async {
    guard !loadedPaperCoverage else { return }
    let observation = await paperPersistence.load()
    guard !loadedPaperCoverage else { return }
    loadedPaperCoverage = true
    var live = states[.live] ?? SourceState()
    live.paperCoverageObservation = observation
    states[.live] = live
  }

  private func retainedSnapshot(facts: PlotterDrawingDraftExternalFacts) -> PlotterDrawingDraftSnapshot {
    let environment = facts.revisions.environment
    return snapshot(state: states[environment] ?? SourceState(), facts: latestFacts[environment] ?? facts)
  }

  private func cancelled(_ submission: PlotterDrawingDraftSubmission,
                         facts: PlotterDrawingDraftExternalFacts) -> PlotterDrawingDraftSubmissionResult {
    let current = retainedSnapshot(facts: facts)
    return .init(disposition: .refused(.init(requestID: submission.requestID,
      comparedDraftRevision: current.projection.draftRevision,
      comparedExternalFacts: current.projection.externalFacts, owner: Authority.draft,
      reason: .cancelled, remedy: "The cancelled draft edit was not applied.")), snapshot: current)
  }

  private func acquireMutationBoundary() async -> Bool {
    guard !Task.isCancelled else { return false }
    guard mutationBoundaryIsOccupied else {
      mutationBoundaryIsOccupied = true
      return true
    }
    let id = UUID()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        if Task.isCancelled { continuation.resume(returning: false) }
        else { mutationBoundaryWaiters.append(.init(id: id, continuation: continuation)) }
      }
    } onCancel: {
      Task { await self.cancelMutationWaiter(id) }
    }
  }

  private func cancelMutationWaiter(_ id: UUID) {
    guard let index = mutationBoundaryWaiters.firstIndex(where: { $0.id == id }) else { return }
    mutationBoundaryWaiters.remove(at: index).continuation.resume(returning: false)
  }

  private func releaseMutationBoundary() {
    guard !mutationBoundaryWaiters.isEmpty else {
      mutationBoundaryIsOccupied = false
      return
    }
    mutationBoundaryWaiters.removeFirst().continuation.resume(returning: true)
  }

  private func rebuild(
    state: inout SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    requestID: PlotterDrawingDraftRequestID?
  ) {
    // A review deletion withdraws the record from future fitting. Do not retain
    // a cached fit (or hidden selection) that still includes withdrawn evidence.
    let availableRecordIDs = Set(facts.coverageRecords.map(\.recordID))
    if !state.selectedResidualRecordIDs.isSubset(of: availableRecordIDs) {
      state.selectedResidualRecordIDs.formIntersection(availableRecordIDs)
      state.residualAnalysis = nil
    }
    let key = DerivationKey(state: state, facts: facts)
    if state.derivationKey == key {
      if let refusal = state.planningRefusal {
        state.planningRefusal = issue(requestID: requestID, state: state, facts: facts,
          owner: refusal.owner, reason: refusal.reason, remedy: refusal.remedy)
      }
      guard state.previewDerivationIsAvailable else { return }
      if let frame = facts.displayedFrame, let previous = state.preview,
        previous.displayedFrame.source == frame.source,
        previous.displayedFrame.frame.cameraConfigurationID == frame.frame.cameraConfigurationID,
        previous.displayedFrame.frame.width == frame.frame.width,
        previous.displayedFrame.frame.height == frame.frame.height,
        previous.displayedFrame.frame.pixelFormat == frame.frame.pixelFormat {
        state.preview = PlotterDrawingDraftPreview(displayedFrame: frame,
          strokes: previous.strokes, bounds: previous.bounds,
          programContentHash: previous.programContentHash,
          planRevisionID: previous.planRevisionID, status: previous.status)
      } else {
        state.preview = facts.registration.flatMap {
          makePreview(state: state, facts: facts, registration: $0)
        }
      }
      return
    }
    derivationBuildCount += 1
    state.previewDerivationIsAvailable = false
    // Planning may resolve the default center. Cache its resulting inputs.
    defer { state.derivationKey = DerivationKey(state: state, facts: facts) }
    if let experiment = state.coverageExperiment {
      if let registration = facts.registration,
        let region = facts.revisions.drawableRegion,
        let prior = try? PlotterDrawingPlanningAdapter.planningProvenance(for: registration, materialContextHash: facts.revisions.materialContextHash),
        experiment.isCurrent(registration: registration, prior: prior,
          region: region, paper: facts.revisions.paper) {
        state.coverageUnavailableReason = nil
        if state.coverageRecordIDs != facts.revisions.coverageRecordIDs {
          state.coverageAssessment = DrawingCoverageAssessment.evaluate(experiment: experiment,
            records: facts.coverageRecords, registration: registration)
          state.coverageRecordIDs = facts.revisions.coverageRecordIDs
        }
      } else {
        state.coverageUnavailableReason = "Experiment provenance changed. Leave the experiment and use a new sheet."
        state.plan = nil
        state.preview = nil
        return
      }
    }
    // Artwork is independent of calibration. Retain it while planning is
    // unavailable so an authored portrait survives Learning and revalidation.
    let program = authoredProgram(state: state, facts: facts)
    state.program = program
    if let experiment = state.coverageExperiment,
      DrawingCoverageTrialDescriptor.decode(program?.source)?.experiment != experiment {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(requestID: requestID, state: state, facts: facts,
        owner: Authority.draft, reason: .coverageExperimentUnavailable,
        remedy: state.coverageAssessment?.blocker ?? "Select a current sealed experiment trial or leave the experiment.")
      return
    }
    guard let registration = facts.registration else {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(
        requestID: requestID,
        state: state,
        facts: facts,
        owner: Authority.registration,
        reason: .registrationUnavailable,
        remedy: "Restore a current accepted pen-tip registration."
      )
      return
    }
    guard let region = facts.revisions.drawableRegion else {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(
        requestID: requestID,
        state: state,
        facts: facts,
        owner: Authority.region,
        reason: .drawableRegionUnavailable,
        remedy: "Restore the current accepted Drawing Boundary."
      )
      return
    }
    guard let program else { return }
    if let assessment = state.coverageAssessment,
      let descriptor = DrawingCoverageTrialDescriptor.decode(program.source),
      assessment.blocker != nil || assessment.attemptedIndices.contains(descriptor.trialIndex) {
      state.plan = nil
      state.preview = nil
      state.planningRefusal = issue(requestID: requestID, state: state, facts: facts,
        owner: Authority.draft, reason: .coverageExperimentUnavailable,
        remedy: assessment.blocker ?? "This trial is recorded. Select Next Experiment Trial or leave the experiment.")
      return
    }
    let built = PlotterDrawingPlanningAdapter.buildDraft(
      program: program,
      machineCenter: state.machineCenter,
      uniformScale: state.uniformScale,
      rotationDegrees: state.rotationDegrees,
      drawableRegion: region,
      registration: registration,
      drawBorder: state.drawBorder && state.coverageExperiment == nil,
      drawingBorderBounds: facts.revisions.drawingBorderBounds,
      materialContextHash: facts.revisions.materialContextHash
    )
    state.machineCenter = built.center ?? state.machineCenter
    state.program = built.program
    state.plan = built.plan
    state.artworkPlan = built.artworkPlan
    state.artworkExecutionPlanHash = built.plan?.contentHash
    if let failure = built.failure {
      state.planningRefusal = issue(
        requestID: requestID,
        state: state,
        facts: facts,
        owner: Authority.planner,
        reason: .planningFailed(failure),
        remedy: "Move or resize the target so drawable artwork remains inside the accepted Drawing Boundary."
      )
    } else {
      state.planningRefusal = nil
    }
    state.previewDerivationIsAvailable = true
    state.preview = makePreview(state: state, facts: facts, registration: registration)
  }

  private func makePreview(
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    registration: TipCameraRegistration
  ) -> PlotterDrawingDraftPreview? {
    guard let frame = facts.displayedFrame, let program = state.program else { return nil }
    guard let opticalConfiguration = facts.revisions.opticalConfiguration,
      opticalConfiguration == registration.applicability.opticalConfiguration,
      frame.source.plotterEnvironment == facts.revisions.environment,
      frame.source == opticalConfiguration.source,
      frame.frame.width == opticalConfiguration.width,
      frame.frame.height == opticalConfiguration.height,
      frame.frame.pixelFormat == opticalConfiguration.pixelFormat
    else {
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: [],
        bounds: nil,
        programContentHash: program.contentHash,
        planRevisionID: state.plan?.revisionID,
        status: .unavailable(
          owner: Authority.camera,
          remedy: "Display a frame from the accepted registration's exact camera configuration."
        )
      )
    }
    guard let plan = state.plan else {
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: [],
        bounds: nil,
        programContentHash: program.contentHash,
        planRevisionID: nil,
        status: .outsideDrawableRegion(
          reason: state.planningRefusal?.remedy
            ?? "Place the target inside the accepted Drawing Boundary."
        )
      )
    }
    do {
      let evidenceProjection = try TipApplicabilityEvidencePolicy.project(
        paths: plan.strokes.map(\.path),
        using: registration
      )
      let projected = try evidenceProjection.attributableCameraPolylines ?? plan.strokes.map { stroke in
        try Polyline(points: stroke.path.points.map {
          try registration.diagnosticProjection(at: $0).cameraPoint
        })
      }
      let points = projected.flatMap(\.points)
      let bounds: AxisAlignedBounds<CameraPixelSpace>?
      if let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
        let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() {
        // Bounds are a display/hit-target rectangle. An axis-aligned line has
        // zero extent on one axis; give that axis a pixel without altering the
        // exact projected path, execution geometry, or evidence applicability.
        let padX = max(0, 1 - (maxX - minX)) / 2
        let padY = max(0, 1 - (maxY - minY)) / 2
        bounds = try AxisAlignedBounds(minX: minX - padX, minY: minY - padY,
                                       maxX: maxX + padX, maxY: maxY + padY)
      } else { bounds = nil }
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: projected,
        bounds: bounds,
        programContentHash: program.contentHash,
        planRevisionID: plan.revisionID,
        status: evidenceProjection.diagnosticLimitation.map {
          .diagnosticOnly($0)
        } ?? .ready
      )
    } catch {
      return PlotterDrawingDraftPreview(
        displayedFrame: frame,
        strokes: [],
        bounds: nil,
        programContentHash: program.contentHash,
        planRevisionID: plan.revisionID,
        status: .unavailable(
          owner: Authority.registration,
          remedy: "The current registration cannot project this exact plan: \(error)"
        )
      )
    }
  }

  private func snapshot(
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts
  ) -> PlotterDrawingDraftSnapshot {
    let coverageIsCurrent: Bool
    if let coverage = state.paperCoverageObservation,
      let source = facts.cameraSource, let configurationID = facts.cameraConfigurationID
    {
      // Freshness belongs to the paper/source/config/contact-plane context,
      // not to whichever newer exact frame currently carries that context.
      coverageIsCurrent = coverage.validation(
        against: PaperCoverageValidationContext(
          paper: facts.revisions.paper,
          source: source,
          frameID: coverage.frame.frameID,
          cameraConfigurationID: configurationID,
          opticalConfiguration: facts.revisions.opticalConfiguration,
          drawableRegion: facts.revisions.drawableRegion
        )
      ) == .valid
    } else {
      coverageIsCurrent = false
    }

    let coverageDisplay: PlotterDrawingDraftPaperCoverageDisplay?
    if let coverage = state.paperCoverageObservation,
      let frame = facts.displayedFrame,
      coverage.source == frame.source,
      coverage.frame == ExactFrameProvenance(frame: frame.frame)
    {
      coverageDisplay = PlotterDrawingDraftPaperCoverageDisplay(
        observationID: coverage.id,
        source: coverage.source,
        frame: coverage.frame,
        polygon: coverage.polygon
      )
    } else {
      coverageDisplay = nil
    }

    let centerCameraPixel: Point2<CameraPixelSpace>?
    if let center = state.machineCenter, let registration = facts.registration {
      centerCameraPixel = try? registration.diagnosticProjection(at: center).cameraPoint
    } else {
      centerCameraPixel = nil
    }
    return PlotterDrawingDraftSnapshot(
      projection: PlotterDrawingDraftProjectionReference(
        environment: facts.revisions.environment,
        draftRevision: state.revision,
        externalFacts: facts.revisions
      ),
      isTargetVisible: state.isTargetVisible,
      drawBorder: state.drawBorder && state.coverageExperiment == nil,
      catalog: DrawingProgramCatalog.entries,
      selectedCatalogItemID: state.suppliedProgram == nil ? state.selectedCatalogItemID : nil,
      evidenceRole: state.evidenceRole,
      uniformScale: state.uniformScale,
      allowedScale: allowedScale(state: state, facts: facts),
      rotationDegrees: state.rotationDegrees,
      machineCenter: state.machineCenter,
      centerCameraPixel: centerCameraPixel,
      placementID: state.placementID,
      program: state.program,
      plan: state.plan,
      artworkPlan: state.plan.flatMap {
        $0.contentHash == state.artworkExecutionPlanHash ? state.artworkPlan : nil
      },
      planningRefusal: state.planningRefusal,
      preview: state.preview,
      sheetPlacementAssertion: state.sheetPlacementAssertion,
      paperCoverageObservation: state.paperCoverageObservation,
      paperCoverageIsCurrent: coverageIsCurrent,
      paperCoverageDisplay: coverageDisplay,
      lastSubmissionRefusal: state.lastSubmissionRefusal,
      coverageExperiment: state.coverageExperiment,
      coverageAssessment: state.coverageAssessment,
      coverageUnavailableReason: state.coverageUnavailableReason,
      residualRecords: facts.coverageRecords.reversed().map {
        DrawingResidualRecordSummary(record: $0, isSelected: state.selectedResidualRecordIDs.contains($0.recordID))
      },
      residualAnalysis: state.residualAnalysis
    )
  }

  private func allowedScale(
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    includingCurrentScale: Bool = true
  ) -> ClosedRange<Double> {
    if state.coverageExperiment != nil { return 1...1 }
    guard let region = facts.revisions.drawableRegion else { return 0.02...1 }
    let extent = state.suppliedProgram?.fieldExtent
      ?? DrawingProgramCatalog.entry(for: state.selectedCatalogItemID).fieldExtent
    // An invalid response leaves only a provisional slider range. buildDraft
    // refuses the plan instead of silently using uncorrected artwork geometry.
    let cameraGeometry = facts.registration.flatMap {
      try? PlotterDrawingPlanningAdapter.cameraGeometry(for: state.suppliedProgram,
        catalogItemID: state.selectedCatalogItemID, registration: $0)
    }
    let fitted = PlotterDrawingPlanningAdapter.scaleRange(extent: extent,
      rotationDegrees: state.rotationDegrees, region: region, cameraGeometry: cameraGeometry)
    // Rotation may crop ordinary artwork without silently shrinking its size.
    // Keep that retained scale representable by the existing Size control.
    return fitted.lowerBound...max(fitted.upperBound,
      includingCurrentScale && cameraGeometry != nil ? state.uniformScale : fitted.upperBound)
  }

  private func authoredProgram(
    state: SourceState, facts: PlotterDrawingDraftExternalFacts
  ) -> DrawingProgram? {
    state.suppliedProgram ?? (try? DrawingProgramCatalog.program(
      for: state.selectedCatalogItemID,
      style: StrokeStyle(nominalLineWidth: 0.4,
        penProfileID: PenProfileID(facts.revisions.toolAssemblyRevision.rawValue))))
  }

  private func issue(
    requestID: PlotterDrawingDraftRequestID?,
    state: SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingDraftRefusalReason,
    remedy: String
  ) -> PlotterDrawingDraftRefusal {
    PlotterDrawingDraftRefusal(
      requestID: requestID ?? PlotterDrawingDraftRequestID(),
      comparedDraftRevision: state.revision,
      comparedExternalFacts: facts.revisions,
      owner: owner,
      reason: reason,
      remedy: remedy
    )
  }

  private func refuse(
    _ submission: PlotterDrawingDraftSubmission,
    state: inout SourceState,
    facts: PlotterDrawingDraftExternalFacts,
    owner: EpisodeAuthorityID,
    reason: PlotterDrawingDraftRefusalReason,
    remedy: String
  ) -> PlotterDrawingDraftSubmissionResult {
    let refusal = issue(
      requestID: submission.requestID,
      state: state,
      facts: facts,
      owner: owner,
      reason: reason,
      remedy: remedy
    )
    state.lastSubmissionRefusal = refusal
    states[facts.revisions.environment] = state
    return PlotterDrawingDraftSubmissionResult(
      disposition: .refused(refusal),
      snapshot: snapshot(state: state, facts: facts)
    )
  }

  private static func normalizedDegrees(_ degrees: Double) -> Double {
    var normalized = degrees.truncatingRemainder(dividingBy: 360)
    if normalized >= 180 { normalized -= 360 }
    if normalized < -180 { normalized += 360 }
    return normalized == 0 ? 0 : normalized
  }
}

public extension DisplayedFrame {
  var plotterExactFrameReferenceIfMaterialized: PlotterExactFrameReference? {
    guard let contentSHA256 = frame.materializedContentSHA256 else { return nil }
    return PlotterExactFrameReference(
      frameID: frame.id.rawValue,
      frameSHA256: contentSHA256,
      source: source.plotterExactFrameSource,
      cameraConfigurationID: frame.cameraConfigurationID,
      captureNanoseconds: frame.captureNanoseconds,
      sequence: frame.sequence,
      width: frame.width,
      height: frame.height,
      rowBytes: frame.rowBytes,
      pixelFormat: PlotterExactFramePixelFormat(rawValue: frame.pixelFormat.rawValue)!
    )
  }

  var plotterExactFrameReference: PlotterExactFrameReference {
    guard let reference = plotterExactFrameReferenceIfMaterialized else {
      preconditionFailure(
        "An exact frame reference requires a frame sealed by analysis or an exact evidence workflow."
      )
    }
    return reference
  }
}

private extension FrameSourceIdentity {
  var plotterExactFrameSource: PlotterExactFrameSource {
    switch self {
    case .live(let deviceID): .live(deviceID: deviceID.rawValue)
    case .simulated: .simulated
    }
  }

  var plotterEnvironment: PlotterEnvironment {
    switch self {
    case .live: .live
    case .simulated: .simulated
    }
  }
}
