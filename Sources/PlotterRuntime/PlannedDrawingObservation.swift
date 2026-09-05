import Foundation
import PlotterModel

/// A bounded request to compare planned camera-space paths with new ink in one
/// exact same-pose frame pair. The pinned frame pair is evidence identity, not
/// permission to move the machine, redraw a path, or promote a model.
public struct PlannedDrawingObservationRequest: Hashable, Sendable {
  public let frames: DrawingObservationFramePair
  public let localPreDrawingBaseline: SamePoseFrameSample
  public let postDrawing: SamePoseFrameSample
  public let region: PixelRect
  public let intendedCameraPolylines: [Polyline<CameraPixelSpace>]
  public let thresholds: InkPixelThresholds
  public let controllerPositionToleranceMM: Double
  public let alignmentSearchRadiusPixels: Int
  public let maximumAlignmentShiftPixels: Int
  public let maximumBackgroundMeanAbsoluteDifference: Double
  public let minimumInkPixelsPerPolyline: Int
  public let maximumInkPixels: Int
  public let maximumRegionPixelCount: Int
  public let maximumIntendedPointCount: Int
  public let maximumAssociationEvaluationCount: Int
  public let associationAmbiguityTolerancePixels: Double
  public let centrelineSampleSpacingPixels: Double
  public let maximumCentrelineSampleCountPerPolyline: Int
  public let observerRevision: AlgorithmRevisionEvidence
  public let additionalAlgorithmRevisions: Set<AlgorithmRevisionEvidence>

  public init(
    frames: DrawingObservationFramePair,
    localPreDrawingBaseline: SamePoseFrameSample,
    postDrawing: SamePoseFrameSample,
    region: PixelRect,
    intendedCameraPolylines: [Polyline<CameraPixelSpace>],
    thresholds: InkPixelThresholds,
    controllerPositionToleranceMM: Double,
    alignmentSearchRadiusPixels: Int,
    maximumAlignmentShiftPixels: Int,
    maximumBackgroundMeanAbsoluteDifference: Double,
    minimumInkPixelsPerPolyline: Int = 3,
    maximumInkPixels: Int = 250_000,
    maximumRegionPixelCount: Int = 1_000_000,
    maximumIntendedPointCount: Int = 25_000,
    maximumAssociationEvaluationCount: Int = 5_000_000,
    associationAmbiguityTolerancePixels: Double = 0.01,
    centrelineSampleSpacingPixels: Double = 4,
    maximumCentrelineSampleCountPerPolyline: Int = 4_096,
    observerRevision: AlgorithmRevisionEvidence,
    additionalAlgorithmRevisions: Set<AlgorithmRevisionEvidence> = []
  ) {
    self.frames = frames
    self.localPreDrawingBaseline = localPreDrawingBaseline
    self.postDrawing = postDrawing
    self.region = region
    self.intendedCameraPolylines = intendedCameraPolylines
    self.thresholds = thresholds
    self.controllerPositionToleranceMM = controllerPositionToleranceMM
    self.alignmentSearchRadiusPixels = alignmentSearchRadiusPixels
    self.maximumAlignmentShiftPixels = maximumAlignmentShiftPixels
    self.maximumBackgroundMeanAbsoluteDifference = maximumBackgroundMeanAbsoluteDifference
    self.minimumInkPixelsPerPolyline = minimumInkPixelsPerPolyline
    self.maximumInkPixels = maximumInkPixels
    self.maximumRegionPixelCount = maximumRegionPixelCount
    self.maximumIntendedPointCount = maximumIntendedPointCount
    self.maximumAssociationEvaluationCount = maximumAssociationEvaluationCount
    self.associationAmbiguityTolerancePixels = associationAmbiguityTolerancePixels
    self.centrelineSampleSpacingPixels = centrelineSampleSpacingPixels
    self.maximumCentrelineSampleCountPerPolyline = maximumCentrelineSampleCountPerPolyline
    self.observerRevision = observerRevision
    self.additionalAlgorithmRevisions = additionalAlgorithmRevisions
  }
}

public struct PlannedDrawingObservation: Codable, Hashable, Sendable {
  public let evidence: DrawingObservedInkEvidence
  public let alignment: IntegerFrameAlignment
  public let overlays: [CameraOverlayMeasurement]
  public let observedPixelCount: Int
  public let computation: PlannedDrawingObservationComputationDiagnostics?

  public var diagnosticSummary: String {
    let detected = "\(observedPixelCount) newly darkened pixels measured."
    guard let residual = evidence.residual else { return detected }
    return detected + String(
      format: " Path residual RMS %.2f px; maximum %.2f px (%u samples).",
      residual.rootMeanSquarePixels, residual.maximumPixels, residual.correspondenceCount
    )
  }

  public init(
    evidence: DrawingObservedInkEvidence,
    alignment: IntegerFrameAlignment,
    overlays: [CameraOverlayMeasurement],
    observedPixelCount: Int,
    computation: PlannedDrawingObservationComputationDiagnostics? = nil
  ) {
    self.evidence = evidence
    self.alignment = alignment
    self.overlays = overlays
    self.observedPixelCount = observedPixelCount
    self.computation = computation
  }
}

/// Exact work counters for one successful run of the current planned-drawing
/// observer. They describe computation only and confer no evidence authority.
public struct PlannedDrawingObservationComputationDiagnostics: Codable, Hashable, Sendable {
  public let alignmentEvaluatedPixelCount: Int
  public let alignmentCoarseCandidateCount: Int
  public let alignmentVerifiedCandidateCount: Int
  public let inkEvaluatedPixelCount: Int
  public let associationEvaluationCount: Int
  public let cancellationCheckpointCount: Int
  public let maximumEvaluationCountBetweenCancellationChecks: Int

  public init(
    alignmentEvaluatedPixelCount: Int,
    alignmentCoarseCandidateCount: Int = 0,
    alignmentVerifiedCandidateCount: Int = 0,
    inkEvaluatedPixelCount: Int,
    associationEvaluationCount: Int,
    cancellationCheckpointCount: Int = 0,
    maximumEvaluationCountBetweenCancellationChecks: Int = 0
  ) {
    self.alignmentEvaluatedPixelCount = alignmentEvaluatedPixelCount
    self.alignmentCoarseCandidateCount = alignmentCoarseCandidateCount
    self.alignmentVerifiedCandidateCount = alignmentVerifiedCandidateCount
    self.inkEvaluatedPixelCount = inkEvaluatedPixelCount
    self.associationEvaluationCount = associationEvaluationCount
    self.cancellationCheckpointCount = cancellationCheckpointCount
    self.maximumEvaluationCountBetweenCancellationChecks =
      maximumEvaluationCountBetweenCancellationChecks
  }

  static let zero = PlannedDrawingObservationComputationDiagnostics(
    alignmentEvaluatedPixelCount: 0,
    alignmentCoarseCandidateCount: 0,
    alignmentVerifiedCandidateCount: 0,
    inkEvaluatedPixelCount: 0,
    associationEvaluationCount: 0,
    cancellationCheckpointCount: 0,
    maximumEvaluationCountBetweenCancellationChecks: 0
  )

  func addingAlignmentComputation(
    evaluatedPixelCount: Int,
    coarseCandidateCount: Int,
    verifiedCandidateCount: Int,
    checkpointCount: Int,
    maximumEvaluationCountBetweenChecks: Int
  ) -> Self {
    Self(
      alignmentEvaluatedPixelCount: alignmentEvaluatedPixelCount + evaluatedPixelCount,
      alignmentCoarseCandidateCount: alignmentCoarseCandidateCount + coarseCandidateCount,
      alignmentVerifiedCandidateCount: alignmentVerifiedCandidateCount + verifiedCandidateCount,
      inkEvaluatedPixelCount: inkEvaluatedPixelCount,
      associationEvaluationCount: associationEvaluationCount,
      cancellationCheckpointCount: cancellationCheckpointCount + checkpointCount,
      maximumEvaluationCountBetweenCancellationChecks: max(
        maximumEvaluationCountBetweenCancellationChecks,
        maximumEvaluationCountBetweenChecks
      )
    )
  }

  func addingInkComputation(
    evaluatedPixelCount: Int,
    checkpointCount: Int,
    maximumEvaluationCountBetweenChecks: Int
  ) -> Self {
    Self(
      alignmentEvaluatedPixelCount: alignmentEvaluatedPixelCount,
      alignmentCoarseCandidateCount: alignmentCoarseCandidateCount,
      alignmentVerifiedCandidateCount: alignmentVerifiedCandidateCount,
      inkEvaluatedPixelCount: inkEvaluatedPixelCount + evaluatedPixelCount,
      associationEvaluationCount: associationEvaluationCount,
      cancellationCheckpointCount: cancellationCheckpointCount + checkpointCount,
      maximumEvaluationCountBetweenCancellationChecks: max(
        maximumEvaluationCountBetweenCancellationChecks,
        maximumEvaluationCountBetweenChecks
      )
    )
  }

  func addingAssociationComputation(
    evaluationCount: Int,
    checkpointCount: Int,
    maximumEvaluationCountBetweenChecks: Int
  ) -> Self {
    Self(
      alignmentEvaluatedPixelCount: alignmentEvaluatedPixelCount,
      alignmentCoarseCandidateCount: alignmentCoarseCandidateCount,
      alignmentVerifiedCandidateCount: alignmentVerifiedCandidateCount,
      inkEvaluatedPixelCount: inkEvaluatedPixelCount,
      associationEvaluationCount: associationEvaluationCount + evaluationCount,
      cancellationCheckpointCount: cancellationCheckpointCount + checkpointCount,
      maximumEvaluationCountBetweenCancellationChecks: max(
        maximumEvaluationCountBetweenCancellationChecks,
        maximumEvaluationCountBetweenChecks
      )
    )
  }

  func addingCancellationBudget(
    checkpointCount: Int,
    maximumEvaluationCountBetweenChecks: Int
  ) -> Self {
    Self(
      alignmentEvaluatedPixelCount: alignmentEvaluatedPixelCount,
      alignmentCoarseCandidateCount: alignmentCoarseCandidateCount,
      alignmentVerifiedCandidateCount: alignmentVerifiedCandidateCount,
      inkEvaluatedPixelCount: inkEvaluatedPixelCount,
      associationEvaluationCount: associationEvaluationCount,
      cancellationCheckpointCount: cancellationCheckpointCount + checkpointCount,
      maximumEvaluationCountBetweenCancellationChecks: max(
        maximumEvaluationCountBetweenCancellationChecks,
        maximumEvaluationCountBetweenChecks
      )
    )
  }
}

enum PlannedDrawingObservationCheckpointStage: Hashable, Sendable {
  case beforeAlignment
  case alignmentCandidate
  case alignmentRow
  case alignmentCompleted
  case inkExtractionChunk
  case inkScanCompleted
  case associationChunk
  case associationCompleted
  case observationCompleted
}

struct PlannedDrawingObservationCheckpoint: Hashable, Sendable {
  let stage: PlannedDrawingObservationCheckpointStage
  let computation: PlannedDrawingObservationComputationDiagnostics
  let taskWasCancelled: Bool
}

typealias PlannedDrawingObservationCheckpointHandler =
  @Sendable (PlannedDrawingObservationCheckpoint) async -> Void

public enum PlannedDrawingObservationOutcome: Codable, Hashable, Sendable {
  case observed(PlannedDrawingObservation)
  case rejected(DrawingObservationRejection)
}

extension VisionWorker {
  public static let plannedDrawingObserverRevision = "nearest-polyline-residual-v2"

  static func plannedDrawingCancellationCheckpoint(
    _ stage: PlannedDrawingObservationCheckpointStage,
    computation: PlannedDrawingObservationComputationDiagnostics,
    handler: PlannedDrawingObservationCheckpointHandler?
  ) async throws {
    if let handler {
      await handler(
        PlannedDrawingObservationCheckpoint(
          stage: stage,
          computation: computation,
          taskWasCancelled: Task.isCancelled
        ))
    }
    try Task.checkCancellation()
  }

  public func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) async -> PlannedDrawingObservationOutcome {
    await observePlannedDrawingInk(request, checkpointHandler: nil)
  }

  func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest,
    checkpointHandler: PlannedDrawingObservationCheckpointHandler?
  ) async -> PlannedDrawingObservationOutcome {
    let requestedAlgorithms = request.additionalAlgorithmRevisions.union([request.observerRevision])
    var computation = PlannedDrawingObservationComputationDiagnostics.zero
    var detectedPixelCount: Int?
    func reject(
      _ reason: DrawingObservationRejectionReason,
      algorithms: Set<AlgorithmRevisionEvidence> = []
    ) -> PlannedDrawingObservationOutcome {
      let revisions = algorithms.isEmpty ? requestedAlgorithms : algorithms
      guard
        let rejection = try? DrawingObservationRejection(
          frames: request.frames,
          reason: reason,
          algorithmRevisions: revisions,
          detectedPixelCount: detectedPixelCount
        )
      else {
        // The request always carries a valid frame pair and observer revision.
        // Retain a typed failure if a future evidence contract becomes stricter.
        let fallback = try! DrawingObservationRejection(
          frames: request.frames,
          reason: .algorithmFailure(code: "rejection-construction-failed"),
          algorithmRevisions: [request.observerRevision]
        )
        return .rejected(fallback)
      }
      return .rejected(rejection)
    }

    guard Self.validPolicy(request) else {
      return reject(.algorithmFailure(code: "invalid-policy"))
    }
    guard Self.contains(request.region, in: request.localPreDrawingBaseline.frame),
      Self.contains(request.region, in: request.postDrawing.frame),
      request.region.height > 0,
      request.region.width <= request.maximumRegionPixelCount / request.region.height
    else { return reject(.algorithmFailure(code: "invalid-region")) }
    guard !request.intendedCameraPolylines.isEmpty,
      request.intendedCameraPolylines.reduce(0, { $0 + $1.points.count })
        <= request.maximumIntendedPointCount,
      request.intendedCameraPolylines.allSatisfy({
        $0.points.allSatisfy { Self.contains($0, in: request.region) }
      })
    else { return reject(.unsupportedDrawing) }
    guard Self.matchesPinnedFrames(request) else {
      return reject(.invalidFrameIdentity)
    }
    let poseDistance = request.localPreDrawingBaseline.controllerPosition.point.distance(
      to: request.postDrawing.controllerPosition.point
    )
    guard poseDistance <= request.controllerPositionToleranceMM else {
      return reject(.observationPoseMismatch)
    }

    let alignmentRevision = try! AlgorithmRevisionEvidence(
      component: "integer-frame-alignment",
      revision: Self.plannedDrawingAlignmentEstimatorRevision
    )
    let algorithms = requestedAlgorithms.union([alignmentRevision])
    do {
      try await Self.plannedDrawingCancellationCheckpoint(
        .beforeAlignment,
        computation: computation,
        handler: checkpointHandler
      )
    } catch {
      return reject(.computationCancelled, algorithms: algorithms)
    }
    let alignmentEvaluation: PlannedIntegerFrameAlignmentEvaluation
    do {
      alignmentEvaluation = try await Self.boundedSubsampledIntegerAlignment(
        request.localPreDrawingBaseline.frame,
        request.postDrawing.frame,
        excluding: request.region,
        searchRadius: request.alignmentSearchRadiusPixels,
        baseComputation: .zero,
        checkpointHandler: checkpointHandler
      )
    } catch PlannedIntegerFrameAlignmentError.supportUnavailable {
      return reject(
        .algorithmFailure(code: "alignment-support-unavailable"),
        algorithms: algorithms
      )
    } catch is CancellationError {
      return reject(.computationCancelled, algorithms: algorithms)
    } catch {
      return reject(.algorithmFailure(code: "alignment-failed"), algorithms: algorithms)
    }
    let alignment = alignmentEvaluation.alignment
    computation = PlannedDrawingObservationComputationDiagnostics(
      alignmentEvaluatedPixelCount: alignment.evaluatedPixelCount,
      alignmentCoarseCandidateCount: alignmentEvaluation.coarseCandidateCount,
      alignmentVerifiedCandidateCount: alignmentEvaluation.verifiedCandidateCount,
      inkEvaluatedPixelCount: 0,
      associationEvaluationCount: 0,
      cancellationCheckpointCount: alignmentEvaluation.cancellationCheckpointCount,
      maximumEvaluationCountBetweenCancellationChecks:
        alignmentEvaluation.maximumEvaluationCountBetweenCancellationChecks
    )
    do {
      try await Self.plannedDrawingCancellationCheckpoint(
        .alignmentCompleted,
        computation: computation,
        handler: checkpointHandler
      )
    } catch {
      return reject(.computationCancelled, algorithms: algorithms)
    }
    guard
      max(abs(alignment.shiftX), abs(alignment.shiftY))
        <= request.maximumAlignmentShiftPixels
    else { return reject(.excessiveAlignment, algorithms: algorithms) }
    guard
      alignment.backgroundMeanAbsoluteDifference
        <= request.maximumBackgroundMeanAbsoluteDifference
    else { return reject(.excessiveBackgroundResidual, algorithms: algorithms) }

    let newInkEvaluation: CancellableNewInkPixelEvaluation
    do {
      newInkEvaluation = try await Self.cancellableNewInkPixelEvaluation(
        from: request.localPreDrawingBaseline.frame,
        to: request.postDrawing.frame,
        region: request.region,
        thresholds: request.thresholds,
        observationShiftX: alignment.shiftX,
        observationShiftY: alignment.shiftY,
        baseComputation: computation,
        checkpointHandler: checkpointHandler
      )
    } catch is CancellationError {
      return reject(.computationCancelled, algorithms: algorithms)
    } catch {
      return reject(.algorithmFailure(code: "ink-extraction-failed"), algorithms: algorithms)
    }
    let newInk = newInkEvaluation.pixels
    detectedPixelCount = newInk.count
    computation = computation.addingInkComputation(
      evaluatedPixelCount: newInkEvaluation.evaluatedPixelCount,
      checkpointCount: newInkEvaluation.cancellationCheckpointCount,
      maximumEvaluationCountBetweenChecks:
        newInkEvaluation.maximumEvaluationCountBetweenCancellationChecks
    )
    do {
      try await Self.plannedDrawingCancellationCheckpoint(
        .inkScanCompleted,
        computation: computation,
        handler: checkpointHandler
      )
    } catch {
      return reject(.computationCancelled, algorithms: algorithms)
    }
    guard !newInk.isEmpty else { return reject(.inkMissing, algorithms: algorithms) }
    guard newInk.count <= request.maximumInkPixels else {
      return reject(.algorithmFailure(code: "ink-pixel-budget-exceeded"), algorithms: algorithms)
    }
    let intendedSegmentCount = request.intendedCameraPolylines.reduce(0) {
      $0 + $1.points.count - 1
    }
    guard intendedSegmentCount > 0,
      newInk.count <= request.maximumAssociationEvaluationCount / intendedSegmentCount
    else {
      return reject(
        .algorithmFailure(code: "association-budget-exceeded"),
        algorithms: algorithms
      )
    }

    let associationEvaluation: CancellablePlannedInkAssociationEvaluation
    do {
      associationEvaluation = try await Self.cancellableAssociation(
        newInk,
        with: request.intendedCameraPolylines,
        observationShiftX: alignment.shiftX,
        observationShiftY: alignment.shiftY,
        ambiguityTolerance: request.associationAmbiguityTolerancePixels,
        baseComputation: computation,
        checkpointHandler: checkpointHandler
      )
    } catch is CancellationError {
      return reject(.computationCancelled, algorithms: algorithms)
    } catch {
      return reject(.algorithmFailure(code: "association-failed"), algorithms: algorithms)
    }
    let association = associationEvaluation.association
    computation = computation.addingAssociationComputation(
      evaluationCount: associationEvaluation.evaluationCount,
      checkpointCount: associationEvaluation.cancellationCheckpointCount,
      maximumEvaluationCountBetweenChecks:
        associationEvaluation.maximumEvaluationCountBetweenCancellationChecks
    )
    do {
      try await Self.plannedDrawingCancellationCheckpoint(
        .associationCompleted,
        computation: computation,
        handler: checkpointHandler
      )
    } catch {
      return reject(.computationCancelled, algorithms: algorithms)
    }
    if association.ambiguousPixelCount > 0 {
      return reject(
        .inkAmbiguous(candidateCount: association.ambiguousPixelCount),
        algorithms: algorithms
      )
    }
    guard
      association.byPolyline.allSatisfy({
        $0.count >= request.minimumInkPixelsPerPolyline
      })
    else { return reject(.correspondenceUnavailable, algorithms: algorithms) }

    guard
      let sampled = Self.sampleObservedCentrelines(
        association.byPolyline,
        intended: request.intendedCameraPolylines,
        spacing: request.centrelineSampleSpacingPixels,
        maximumSamplesPerPolyline: request.maximumCentrelineSampleCountPerPolyline
      )
    else { return reject(.correspondenceUnavailable, algorithms: algorithms) }
    guard !Task.isCancelled else {
      return reject(.computationCancelled, algorithms: algorithms)
    }
    guard let residual = Self.residualEvidence(sampled.correspondences) else {
      return reject(.algorithmFailure(code: "residual-construction-failed"), algorithms: algorithms)
    }
    guard
      let evidence = try? DrawingObservedInkEvidence(
        frames: request.frames,
        intendedInk: request.intendedCameraPolylines,
        observedInk: sampled.polylines,
        residual: residual,
        algorithmRevisions: algorithms
      )
    else {
      return reject(.algorithmFailure(code: "evidence-construction-failed"), algorithms: algorithms)
    }
    let overlayRevision = Self.overlayRevision(algorithms)
    let overlays = Self.plannedDrawingOverlays(
      frame: request.postDrawing.frame,
      intended: request.intendedCameraPolylines,
      observed: sampled.polylines,
      correspondences: sampled.correspondences,
      algorithmRevision: overlayRevision
    )
    do {
      try await Self.plannedDrawingCancellationCheckpoint(
        .observationCompleted,
        computation: computation,
        handler: checkpointHandler
      )
    } catch {
      return reject(.computationCancelled, algorithms: algorithms)
    }
    return .observed(
      PlannedDrawingObservation(
        evidence: evidence,
        alignment: alignment,
        overlays: overlays,
        observedPixelCount: newInk.count,
        computation: computation
      ))
  }
}

extension VisionWorker {
  struct PlannedInkAssociation {
    let byPolyline: [[PlannedAssociatedInkPixel]]
    let ambiguousPixelCount: Int
  }

  struct CancellablePlannedInkAssociationEvaluation {
    let association: PlannedInkAssociation
    let evaluationCount: Int
    let cancellationCheckpointCount: Int
    let maximumEvaluationCountBetweenCancellationChecks: Int
  }

  struct PlannedAssociatedInkPixel {
    let point: Point2<CameraPixelSpace>
    let alongDistance: Double
  }

  struct PlannedPathProjection {
    let distance: Double
    let alongDistance: Double
  }

  struct PlannedSampledCorrespondence {
    let intended: Point2<CameraPixelSpace>
    let observed: Point2<CameraPixelSpace>
    let crossTrackDistance: Double
  }

  struct PlannedSampledCentrelines {
    let polylines: [Polyline<CameraPixelSpace>]
    let correspondences: [PlannedSampledCorrespondence]
  }

  static func validPolicy(_ request: PlannedDrawingObservationRequest) -> Bool {
    request.controllerPositionToleranceMM.isFinite
      && request.controllerPositionToleranceMM >= 0
      && request.alignmentSearchRadiusPixels >= 0
      && request.maximumAlignmentShiftPixels >= 0
      && request.maximumAlignmentShiftPixels <= request.alignmentSearchRadiusPixels
      && request.maximumBackgroundMeanAbsoluteDifference.isFinite
      && request.maximumBackgroundMeanAbsoluteDifference >= 0
      && request.minimumInkPixelsPerPolyline >= 2
      && request.maximumInkPixels >= request.minimumInkPixelsPerPolyline
      && request.maximumRegionPixelCount > 0
      && request.maximumIntendedPointCount >= 2
      && request.maximumAssociationEvaluationCount > 0
      && request.associationAmbiguityTolerancePixels.isFinite
      && request.associationAmbiguityTolerancePixels >= 0
      && request.centrelineSampleSpacingPixels.isFinite
      && request.centrelineSampleSpacingPixels > 0
      && request.maximumCentrelineSampleCountPerPolyline >= 2
  }

  static func contains(
    _ point: Point2<CameraPixelSpace>,
    in region: PixelRect
  ) -> Bool {
    point.x >= Double(region.x) && point.y >= Double(region.y)
      && point.x < Double(region.x + region.width)
      && point.y < Double(region.y + region.height)
  }

  static func matchesPinnedFrames(_ request: PlannedDrawingObservationRequest) -> Bool {
    let baseline = request.localPreDrawingBaseline
    let post = request.postDrawing
    return baseline.source == request.frames.source
      && post.source == request.frames.source
      && ExactFrameProvenance(frame: baseline.frame) == request.frames.baseline
      && ExactFrameProvenance(frame: post.frame) == request.frames.post
  }

  static func cancellableAssociation(
    _ orderedInk: [InkPixel],
    with intended: [Polyline<CameraPixelSpace>],
    observationShiftX: Int,
    observationShiftY: Int,
    ambiguityTolerance: Double,
    baseComputation: PlannedDrawingObservationComputationDiagnostics,
    checkpointHandler: PlannedDrawingObservationCheckpointHandler?
  ) async throws -> CancellablePlannedInkAssociationEvaluation {
    var grouped = Array(repeating: [PlannedAssociatedInkPixel](), count: intended.count)
    var ambiguous = 0
    var evaluationCount = 0
    var budget = CancellationCheckpointBudget()

    for pixel in orderedInk {
      let point = try! Point2<CameraPixelSpace>(
        x: Double(pixel.x + observationShiftX),
        y: Double(pixel.y + observationShiftY)
      )
      var ranked: [(index: Int, projection: PlannedPathProjection)] = []
      ranked.reserveCapacity(intended.count)
      for (pathIndex, path) in intended.enumerated() {
        var best: PlannedPathProjection?
        var precedingLength = 0.0
        for segmentIndex in 0..<(path.points.count - 1) {
          if evaluationCount.isMultiple(of: plannedDrawingCancellationEvaluationChunkSize) {
            budget.recordCheckpoint()
            try await plannedDrawingCancellationCheckpoint(
              .associationChunk,
              computation: baseComputation.addingAssociationComputation(
                evaluationCount: evaluationCount,
                checkpointCount: budget.count,
                maximumEvaluationCountBetweenChecks:
                  budget.maximumEvaluationCountBetweenCheckpoints
              ),
              handler: checkpointHandler
            )
          }
          budget.recordEvaluations(1)
          evaluationCount += 1
          let start = path.points[segmentIndex]
          let end = path.points[segmentIndex + 1]
          let dx = end.x - start.x
          let dy = end.y - start.y
          let squaredLength = dx * dx + dy * dy
          guard squaredLength > 0 else { continue }
          let rawT =
            ((point.x - start.x) * dx + (point.y - start.y) * dy)
            / squaredLength
          let t = min(1, max(0, rawT))
          let projected = try! Point2<CameraPixelSpace>(
            x: start.x + t * dx,
            y: start.y + t * dy
          )
          let segmentLength = sqrt(squaredLength)
          let candidate = PlannedPathProjection(
            distance: point.distance(to: projected),
            alongDistance: precedingLength + t * segmentLength
          )
          if let current = best {
            if candidate.distance < current.distance
              || (candidate.distance == current.distance
                && candidate.alongDistance < current.alongDistance)
            {
              best = candidate
            }
          } else {
            best = candidate
          }
          precedingLength += segmentLength
        }
        ranked.append(
          (
            index: pathIndex,
            projection: best ?? PlannedPathProjection(distance: .infinity, alongDistance: 0)
          ))
      }
      ranked.sort { lhs, rhs in
        if lhs.projection.distance != rhs.projection.distance {
          return lhs.projection.distance < rhs.projection.distance
        }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.projection.alongDistance < rhs.projection.alongDistance
      }
      // Distance is the quantity this observer measures. Rejecting candidates
      // beyond the predicted path would censor the residual before computing it.
      // The validated request contains at least one nondegenerate polyline.
      let nearest = ranked[0]
      if ranked.count > 1,
        ranked[1].projection.distance - nearest.projection.distance <= ambiguityTolerance
      {
        ambiguous += 1
        continue
      }
      grouped[nearest.index].append(
        PlannedAssociatedInkPixel(
          point: point,
          alongDistance: nearest.projection.alongDistance
        ))
    }
    budget.recordCheckpoint()
    try await plannedDrawingCancellationCheckpoint(
      .associationChunk,
      computation: baseComputation.addingAssociationComputation(
        evaluationCount: evaluationCount,
        checkpointCount: budget.count,
        maximumEvaluationCountBetweenChecks:
          budget.maximumEvaluationCountBetweenCheckpoints
      ),
      handler: checkpointHandler
    )
    return CancellablePlannedInkAssociationEvaluation(
      association: PlannedInkAssociation(
        byPolyline: grouped,
        ambiguousPixelCount: ambiguous
      ),
      evaluationCount: evaluationCount,
      cancellationCheckpointCount: budget.count,
      maximumEvaluationCountBetweenCancellationChecks:
        budget.maximumEvaluationCountBetweenCheckpoints
    )
  }

  static func nearestProjection(
    of point: Point2<CameraPixelSpace>,
    onto path: Polyline<CameraPixelSpace>
  ) -> PlannedPathProjection {
    var best: PlannedPathProjection?
    var precedingLength = 0.0
    for pair in zip(path.points, path.points.dropFirst()) {
      let dx = pair.1.x - pair.0.x
      let dy = pair.1.y - pair.0.y
      let squaredLength = dx * dx + dy * dy
      guard squaredLength > 0 else { continue }
      let rawT = ((point.x - pair.0.x) * dx + (point.y - pair.0.y) * dy) / squaredLength
      let t = min(1, max(0, rawT))
      let projected = try! Point2<CameraPixelSpace>(
        x: pair.0.x + t * dx,
        y: pair.0.y + t * dy
      )
      let segmentLength = sqrt(squaredLength)
      let candidate = PlannedPathProjection(
        distance: point.distance(to: projected),
        alongDistance: precedingLength + t * segmentLength
      )
      if let current = best {
        if candidate.distance < current.distance
          || (candidate.distance == current.distance
            && candidate.alongDistance < current.alongDistance)
        {
          best = candidate
        }
      } else {
        best = candidate
      }
      precedingLength += segmentLength
    }
    return best ?? PlannedPathProjection(distance: .infinity, alongDistance: 0)
  }

  static func sampleObservedCentrelines(
    _ grouped: [[PlannedAssociatedInkPixel]],
    intended: [Polyline<CameraPixelSpace>],
    spacing: Double,
    maximumSamplesPerPolyline: Int
  ) -> PlannedSampledCentrelines? {
    var polylines: [Polyline<CameraPixelSpace>] = []
    var correspondences: [PlannedSampledCorrespondence] = []
    for (pathIndex, pixels) in grouped.enumerated() {
      let intendedPath = intended[pathIndex]
      let unboundedBinCount = intendedPath.length / spacing
      let binCount =
        unboundedBinCount >= Double(maximumSamplesPerPolyline)
        ? maximumSamplesPerPolyline
        : max(2, Int(ceil(unboundedBinCount)))
      var bins = Array(repeating: [PlannedAssociatedInkPixel](), count: binCount)
      for pixel in pixels {
        let fraction = intendedPath.length == 0 ? 0 : pixel.alongDistance / intendedPath.length
        let index = min(binCount - 1, max(0, Int(floor(fraction * Double(binCount)))))
        bins[index].append(pixel)
      }
      var points: [Point2<CameraPixelSpace>] = []
      for bin in bins where !bin.isEmpty {
        let observed = try! Point2<CameraPixelSpace>(
          x: bin.reduce(0.0) { $0 + $1.point.x } / Double(bin.count),
          y: bin.reduce(0.0) { $0 + $1.point.y } / Double(bin.count)
        )
        let meanAlong = bin.reduce(0.0) { $0 + $1.alongDistance } / Double(bin.count)
        let intendedPoint = point(on: intendedPath, at: meanAlong)
        if points.last != observed { points.append(observed) }
        correspondences.append(
          PlannedSampledCorrespondence(
            intended: intendedPoint,
            observed: observed,
            crossTrackDistance: nearestProjection(of: observed, onto: intendedPath).distance
          ))
      }
      guard let centreline = try? Polyline(points: points) else { return nil }
      polylines.append(centreline)
    }
    return PlannedSampledCentrelines(polylines: polylines, correspondences: correspondences)
  }

  static func point(
    on path: Polyline<CameraPixelSpace>,
    at requestedDistance: Double
  ) -> Point2<CameraPixelSpace> {
    let distance = min(path.length, max(0, requestedDistance))
    var precedingLength = 0.0
    for pair in zip(path.points, path.points.dropFirst()) {
      let segmentLength = pair.0.distance(to: pair.1)
      guard segmentLength > 0 else { continue }
      if precedingLength + segmentLength >= distance {
        let t = (distance - precedingLength) / segmentLength
        return try! Point2(
          x: pair.0.x + t * (pair.1.x - pair.0.x),
          y: pair.0.y + t * (pair.1.y - pair.0.y)
        )
      }
      precedingLength += segmentLength
    }
    return path.end
  }

  static func residualEvidence(
    _ correspondences: [PlannedSampledCorrespondence]
  ) -> DrawingResidualEvidence? {
    guard !correspondences.isEmpty else { return nil }
    let squared = correspondences.map { pow($0.intended.distance(to: $0.observed), 2) }
    let crossTrackSquared = correspondences.map { pow($0.crossTrackDistance, 2) }
    let rootMeanSquare = sqrt(squared.reduce(0, +) / Double(squared.count))
    let maximum = max(rootMeanSquare, sqrt(squared.max() ?? 0))
    return try? DrawingResidualEvidence(
      correspondenceCount: UInt32(correspondences.count),
      rootMeanSquarePixels: rootMeanSquare,
      maximumPixels: maximum,
      rootMeanSquareCrossTrackPixels: sqrt(
        crossTrackSquared.reduce(0, +) / Double(crossTrackSquared.count)
      )
    )
  }

  static func plannedDrawingOverlays(
    frame: StampedFrame,
    intended: [Polyline<CameraPixelSpace>],
    observed: [Polyline<CameraPixelSpace>],
    correspondences: [PlannedSampledCorrespondence],
    algorithmRevision: String
  ) -> [CameraOverlayMeasurement] {
    let identity = (frameID: frame.id, cameraConfigurationID: frame.cameraConfigurationID)
    var overlays = intended.map {
      CameraOverlayMeasurement(
        frameID: identity.frameID,
        cameraConfigurationID: identity.cameraConfigurationID,
        geometry: .polyline($0),
        provenance: CameraMeasurementProvenance(
          kind: .intendedPath,
          source: .planned,
          algorithmRevision: algorithmRevision
        )
      )
    }
    overlays += observed.map {
      CameraOverlayMeasurement(
        frameID: identity.frameID,
        cameraConfigurationID: identity.cameraConfigurationID,
        geometry: .polyline($0),
        provenance: CameraMeasurementProvenance(
          kind: .observedInk,
          source: .measured,
          algorithmRevision: algorithmRevision
        )
      )
    }
    overlays += correspondences.map {
      let geometry: CameraPixelGeometry
      if $0.intended == $0.observed {
        geometry = .point($0.observed)
      } else {
        geometry = .polyline(try! Polyline(points: [$0.intended, $0.observed]))
      }
      return CameraOverlayMeasurement(
        frameID: identity.frameID,
        cameraConfigurationID: identity.cameraConfigurationID,
        geometry: geometry,
        provenance: CameraMeasurementProvenance(
          kind: .residual,
          source: .diagnostic,
          algorithmRevision: algorithmRevision
        )
      )
    }
    return overlays
  }

  static func overlayRevision(
    _ revisions: Set<AlgorithmRevisionEvidence>
  ) -> String {
    revisions.sorted {
      $0.component == $1.component
        ? $0.revision < $1.revision
        : $0.component < $1.component
    }.map { "\($0.component)=\($0.revision)" }.joined(separator: "|")
  }
}
