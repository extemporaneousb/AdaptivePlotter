import Foundation
import PlotterModel

public struct ExactFrameProvenance: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let pixelFormat: FramePixelFormat

  public init(frame: StampedFrame) {
    frameID = frame.id
    frameSHA256 = frame.contentSHA256
    captureNanoseconds = frame.captureNanoseconds
    cameraConfigurationID = frame.cameraConfigurationID
    width = frame.width
    height = frame.height
    rowBytes = frame.rowBytes
    pixelFormat = frame.pixelFormat
  }
}

public struct SamePoseFrameSample: Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let frame: StampedFrame
  public let controllerPosition: MachinePosition

  public init(displayedFrame: DisplayedFrame, controllerPosition: MachinePosition) {
    source = displayedFrame.source
    frame = displayedFrame.frame
    self.controllerPosition = controllerPosition
  }

  public init(
    source: FrameSourceIdentity,
    frame: StampedFrame,
    controllerPosition: MachinePosition
  ) {
    self.source = source
    self.frame = frame
    self.controllerPosition = controllerPosition
  }
}

public struct IntegerFrameAlignment: Codable, Hashable, Sendable {
  public let shiftX: Int
  public let shiftY: Int
  public let backgroundMeanAbsoluteDifference: Double
  public let estimatorRevision: String
  public let supportRegion: PixelRect
  public let exclusionRegion: PixelRect
  public let evaluatedPixelCount: Int
}

extension VisionWorker {
  struct InkPixel: Hashable {
    let x: Int
    let y: Int
  }

  struct BackgroundResidual {
    let meanAbsoluteDifference: Double
    let pixelCount: Int
  }

  struct CancellableNewInkPixelEvaluation {
    /// Raster order is deterministic and lets association avoid sorting a large
    /// set after extraction.
    let pixels: [InkPixel]
    let evaluatedPixelCount: Int
    let cancellationCheckpointCount: Int
    let maximumEvaluationCountBetweenCancellationChecks: Int
  }

  struct PlannedIntegerFrameAlignmentEvaluation {
    let alignment: IntegerFrameAlignment
    let coarseCandidateCount: Int
    let verifiedCandidateCount: Int
    let cancellationCheckpointCount: Int
    let maximumEvaluationCountBetweenCancellationChecks: Int
  }

  enum PlannedIntegerFrameAlignmentError: Error {
    case supportUnavailable
  }

  struct AlignmentCandidate {
    let shiftX: Int
    let shiftY: Int
    let residual: Double
  }

  struct CancellableBackgroundResidualEvaluation {
    let residual: BackgroundResidual
    let cancellationBudget: CancellationCheckpointBudget
  }

  struct CancellationCheckpointBudget {
    var count = 0
    var evaluationCountSinceLastCheckpoint = 0
    var maximumEvaluationCountBetweenCheckpoints = 0

    mutating func recordEvaluations(_ count: Int) {
      evaluationCountSinceLastCheckpoint += count
    }

    mutating func recordCheckpoint() {
      maximumEvaluationCountBetweenCheckpoints = max(
        maximumEvaluationCountBetweenCheckpoints,
        evaluationCountSinceLastCheckpoint
      )
      evaluationCountSinceLastCheckpoint = 0
      count += 1
    }
  }

  static let plannedDrawingAlignmentEstimatorRevision =
    "bounded-subsampled-finalist-background-mad-v2"
  static let plannedDrawingCancellationEvaluationChunkSize = 64

  static func contains(_ region: PixelRect, in frame: StampedFrame) -> Bool {
    region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
      && region.x + region.width <= frame.width
      && region.y + region.height <= frame.height
  }

  static func cancellableNewInkPixelEvaluation(
    from reference: StampedFrame,
    to observation: StampedFrame,
    region: PixelRect,
    thresholds: InkPixelThresholds,
    observationShiftX: Int = 0,
    observationShiftY: Int = 0,
    baseComputation: PlannedDrawingObservationComputationDiagnostics,
    checkpointHandler: PlannedDrawingObservationCheckpointHandler?
  ) async throws -> CancellableNewInkPixelEvaluation {
    var result: [InkPixel] = []
    var evaluatedPixelCount = 0
    var budget = CancellationCheckpointBudget()

    for y in region.y..<(region.y + region.height) {
      budget.recordCheckpoint()
      try await plannedDrawingCancellationCheckpoint(
        .inkExtractionChunk,
        computation: baseComputation.addingCancellationBudget(
          checkpointCount: budget.count,
          maximumEvaluationCountBetweenChecks:
            budget.maximumEvaluationCountBetweenCheckpoints
        ),
        handler: checkpointHandler
      )
      for (columnOffset, x) in (region.x..<(region.x + region.width)).enumerated() {
        if columnOffset > 0,
          columnOffset.isMultiple(of: plannedDrawingCancellationEvaluationChunkSize)
        {
          budget.recordCheckpoint()
          try await plannedDrawingCancellationCheckpoint(
            .inkExtractionChunk,
            computation: baseComputation.addingInkComputation(
              evaluatedPixelCount: evaluatedPixelCount,
              checkpointCount: budget.count,
              maximumEvaluationCountBetweenChecks:
                budget.maximumEvaluationCountBetweenCheckpoints
            ),
            handler: checkpointHandler
          )
        }
        budget.recordEvaluations(1)
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        evaluatedPixelCount += 1
        if isNewInk(
          reference: reference,
          referenceX: x,
          referenceY: y,
          observation: observation,
          observationX: observedX,
          observationY: observedY,
          thresholds: thresholds
        ) {
          result.append(InkPixel(x: x, y: y))
        }
      }
    }
    budget.recordCheckpoint()
    try await plannedDrawingCancellationCheckpoint(
      .inkExtractionChunk,
      computation: baseComputation.addingInkComputation(
        evaluatedPixelCount: evaluatedPixelCount,
        checkpointCount: budget.count,
        maximumEvaluationCountBetweenChecks:
          budget.maximumEvaluationCountBetweenCheckpoints
      ),
      handler: checkpointHandler
    )
    return CancellableNewInkPixelEvaluation(
      pixels: result,
      evaluatedPixelCount: evaluatedPixelCount,
      cancellationCheckpointCount: budget.count,
      maximumEvaluationCountBetweenCancellationChecks:
        budget.maximumEvaluationCountBetweenCheckpoints
    )
  }

  /// Scores the complete bounded shift envelope on a deterministic lattice,
  /// then uses full-resolution scores for the small finalist set only. Coarse
  /// scores never become acceptance evidence.
  static func boundedSubsampledIntegerAlignment(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    searchRadius: Int,
    baseComputation: PlannedDrawingObservationComputationDiagnostics,
    checkpointHandler: PlannedDrawingObservationCheckpointHandler?
  ) async throws -> PlannedIntegerFrameAlignmentEvaluation {
    let coarseSampleStride = 2
    let maximumVerifiedCandidateCount = 3
    var evaluatedPixelCount = 0
    var coarseCandidates: [AlignmentCandidate] = []
    var budget = CancellationCheckpointBudget()
    let candidateCount = (searchRadius * 2 + 1) * (searchRadius * 2 + 1)
    coarseCandidates.reserveCapacity(candidateCount)

    for shiftY in (-searchRadius)...searchRadius {
      for shiftX in (-searchRadius)...searchRadius {
        budget.recordCheckpoint()
        try await plannedDrawingCancellationCheckpoint(
          .alignmentCandidate,
          computation: baseComputation.addingAlignmentComputation(
            evaluatedPixelCount: evaluatedPixelCount,
            coarseCandidateCount: coarseCandidates.count,
            verifiedCandidateCount: 0,
            checkpointCount: budget.count,
            maximumEvaluationCountBetweenChecks:
              budget.maximumEvaluationCountBetweenCheckpoints
          ),
          handler: checkpointHandler
        )
        let evaluation = try await cancellableBackgroundMeanAbsoluteDifference(
          baseline,
          observation,
          excluding: region,
          observationShiftX: shiftX,
          observationShiftY: shiftY,
          sampleStride: coarseSampleStride,
          evaluatedPixelBase: evaluatedPixelCount,
          coarseCandidateCount: coarseCandidates.count,
          verifiedCandidateCount: 0,
          baseComputation: baseComputation,
          cancellationBudget: budget,
          checkpointHandler: checkpointHandler
        )
        budget = evaluation.cancellationBudget
        evaluatedPixelCount += evaluation.residual.pixelCount
        coarseCandidates.append(
          AlignmentCandidate(
            shiftX: shiftX,
            shiftY: shiftY,
            residual: evaluation.residual.meanAbsoluteDifference
          ))
      }
    }
    budget.recordCheckpoint()
    try await plannedDrawingCancellationCheckpoint(
      .alignmentCandidate,
      computation: baseComputation.addingAlignmentComputation(
        evaluatedPixelCount: evaluatedPixelCount,
        coarseCandidateCount: coarseCandidates.count,
        verifiedCandidateCount: 0,
        checkpointCount: budget.count,
        maximumEvaluationCountBetweenChecks:
          budget.maximumEvaluationCountBetweenCheckpoints
      ),
      handler: checkpointHandler
    )

    guard evaluatedPixelCount > 0 else {
      throw PlannedIntegerFrameAlignmentError.supportUnavailable
    }
    let rankedCoarse = coarseCandidates.sorted(by: alignmentCandidateIsBetter)
    let finalists = Array(rankedCoarse.prefix(maximumVerifiedCandidateCount))
    var verifiedCandidates: [AlignmentCandidate] = []
    verifiedCandidates.reserveCapacity(finalists.count)

    for finalist in finalists {
      budget.recordCheckpoint()
      try await plannedDrawingCancellationCheckpoint(
        .alignmentCandidate,
        computation: baseComputation.addingAlignmentComputation(
          evaluatedPixelCount: evaluatedPixelCount,
          coarseCandidateCount: coarseCandidates.count,
          verifiedCandidateCount: verifiedCandidates.count,
          checkpointCount: budget.count,
          maximumEvaluationCountBetweenChecks:
            budget.maximumEvaluationCountBetweenCheckpoints
        ),
        handler: checkpointHandler
      )
      let evaluation = try await cancellableBackgroundMeanAbsoluteDifference(
        baseline,
        observation,
        excluding: region,
        observationShiftX: finalist.shiftX,
        observationShiftY: finalist.shiftY,
        sampleStride: 1,
        evaluatedPixelBase: evaluatedPixelCount,
        coarseCandidateCount: coarseCandidates.count,
        verifiedCandidateCount: verifiedCandidates.count,
        baseComputation: baseComputation,
        cancellationBudget: budget,
        checkpointHandler: checkpointHandler
      )
      budget = evaluation.cancellationBudget
      evaluatedPixelCount += evaluation.residual.pixelCount
      verifiedCandidates.append(
        AlignmentCandidate(
          shiftX: finalist.shiftX,
          shiftY: finalist.shiftY,
          residual: evaluation.residual.meanAbsoluteDifference
        ))
    }
    budget.recordCheckpoint()
    try await plannedDrawingCancellationCheckpoint(
      .alignmentCandidate,
      computation: baseComputation.addingAlignmentComputation(
        evaluatedPixelCount: evaluatedPixelCount,
        coarseCandidateCount: coarseCandidates.count,
        verifiedCandidateCount: verifiedCandidates.count,
        checkpointCount: budget.count,
        maximumEvaluationCountBetweenChecks:
          budget.maximumEvaluationCountBetweenCheckpoints
      ),
      handler: checkpointHandler
    )

    let selected =
      verifiedCandidates.sorted(by: alignmentCandidateIsBetter).first
      ?? AlignmentCandidate(shiftX: 0, shiftY: 0, residual: 0)
    return PlannedIntegerFrameAlignmentEvaluation(
      alignment: IntegerFrameAlignment(
        shiftX: selected.shiftX,
        shiftY: selected.shiftY,
        backgroundMeanAbsoluteDifference: selected.residual,
        estimatorRevision: plannedDrawingAlignmentEstimatorRevision,
        supportRegion: PixelRect(x: 0, y: 0, width: baseline.width, height: baseline.height),
        exclusionRegion: region,
        evaluatedPixelCount: evaluatedPixelCount
      ),
      coarseCandidateCount: coarseCandidates.count,
      verifiedCandidateCount: verifiedCandidates.count,
      cancellationCheckpointCount: budget.count,
      maximumEvaluationCountBetweenCancellationChecks:
        budget.maximumEvaluationCountBetweenCheckpoints
    )
  }

  static func cancellableBackgroundMeanAbsoluteDifference(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    observationShiftX: Int,
    observationShiftY: Int,
    sampleStride: Int,
    evaluatedPixelBase: Int,
    coarseCandidateCount: Int,
    verifiedCandidateCount: Int,
    baseComputation: PlannedDrawingObservationComputationDiagnostics,
    cancellationBudget initialBudget: CancellationCheckpointBudget,
    checkpointHandler: PlannedDrawingObservationCheckpointHandler?
  ) async throws -> CancellableBackgroundResidualEvaluation {
    precondition(sampleStride > 0)
    var absoluteDifference = 0.0
    var pixelCount = 0
    var budget = initialBudget
    for y in stride(from: 0, to: baseline.height, by: sampleStride) {
      budget.recordCheckpoint()
      try await plannedDrawingCancellationCheckpoint(
        .alignmentRow,
        computation: baseComputation.addingAlignmentComputation(
          evaluatedPixelCount: evaluatedPixelBase + pixelCount,
          coarseCandidateCount: coarseCandidateCount,
          verifiedCandidateCount: verifiedCandidateCount,
          checkpointCount: budget.count,
          maximumEvaluationCountBetweenChecks:
            budget.maximumEvaluationCountBetweenCheckpoints
        ),
        handler: checkpointHandler
      )
      for x in stride(from: 0, to: baseline.width, by: sampleStride) {
        let inRegion =
          x >= region.x && x < region.x + region.width
          && y >= region.y && y < region.y + region.height
        guard !inRegion else { continue }
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        budget.recordEvaluations(1)
        let baseOffset = y * baseline.rowBytes + x * baseline.pixelFormat.bytesPerPixel
        let observedOffset =
          observedY * observation.rowBytes
          + observedX * observation.pixelFormat.bytesPerPixel
        for component in 0..<baseline.pixelFormat.bytesPerPixel {
          absoluteDifference += abs(
            Double(baseline.bytes[baseOffset + component])
              - Double(observation.bytes[observedOffset + component])
          )
        }
        pixelCount += 1
      }
    }
    let byteCount = pixelCount * baseline.pixelFormat.bytesPerPixel
    return CancellableBackgroundResidualEvaluation(
      residual: BackgroundResidual(
        meanAbsoluteDifference: byteCount == 0 ? 0 : absoluteDifference / Double(byteCount),
        pixelCount: pixelCount
      ),
      cancellationBudget: budget
    )
  }

  static func alignmentCandidateIsBetter(
    _ candidate: AlignmentCandidate,
    _ current: AlignmentCandidate
  ) -> Bool {
    (
      candidate.residual,
      max(abs(candidate.shiftX), abs(candidate.shiftY)),
      abs(candidate.shiftX) + abs(candidate.shiftY),
      candidate.shiftY,
      candidate.shiftX
    ) < (
      current.residual,
      max(abs(current.shiftX), abs(current.shiftY)),
      abs(current.shiftX) + abs(current.shiftY),
      current.shiftY,
      current.shiftX
    )
  }

  static func bestIntegerAlignment(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    searchRadius: Int,
    sampleStride: Int = 1
  ) -> IntegerFrameAlignment {
    precondition(sampleStride > 0)
    var best: (shiftX: Int, shiftY: Int, residual: Double)?
    var evaluatedPixelCount = 0
    for shiftY in (-searchRadius)...searchRadius {
      for shiftX in (-searchRadius)...searchRadius {
        let residual = backgroundMeanAbsoluteDifference(
          baseline,
          observation,
          excluding: region,
          observationShiftX: shiftX,
          observationShiftY: shiftY,
          sampleStride: sampleStride
        )
        evaluatedPixelCount += residual.pixelCount
        let candidate = (
          shiftX: shiftX,
          shiftY: shiftY,
          residual: residual.meanAbsoluteDifference
        )
        if let current = best {
          let candidateRank = (
            candidate.residual,
            max(abs(candidate.shiftX), abs(candidate.shiftY)),
            abs(candidate.shiftX) + abs(candidate.shiftY),
            candidate.shiftY,
            candidate.shiftX
          )
          let currentRank = (
            current.residual,
            max(abs(current.shiftX), abs(current.shiftY)),
            abs(current.shiftX) + abs(current.shiftY),
            current.shiftY,
            current.shiftX
          )
          if candidateRank < currentRank { best = candidate }
        } else {
          best = candidate
        }
      }
    }
    let selected = best ?? (0, 0, 0)
    return IntegerFrameAlignment(
      shiftX: selected.shiftX,
      shiftY: selected.shiftY,
      backgroundMeanAbsoluteDifference: selected.residual,
      estimatorRevision: sampleStride == 1
        ? "bounded-integer-background-mad-v1"
        : "bounded-integer-background-mad-subsampled-v1",
      supportRegion: PixelRect(x: 0, y: 0, width: baseline.width, height: baseline.height),
      exclusionRegion: region,
      evaluatedPixelCount: evaluatedPixelCount
    )
  }

  static func backgroundMeanAbsoluteDifference(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    observationShiftX: Int,
    observationShiftY: Int,
    sampleStride: Int = 1
  ) -> BackgroundResidual {
    precondition(sampleStride > 0)
    var absoluteDifference = 0.0
    var pixelCount = 0
    for y in stride(from: 0, to: baseline.height, by: sampleStride) {
      for x in stride(from: 0, to: baseline.width, by: sampleStride) {
        let inRegion =
          x >= region.x && x < region.x + region.width
          && y >= region.y && y < region.y + region.height
        guard !inRegion else { continue }
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        let baseOffset = y * baseline.rowBytes + x * baseline.pixelFormat.bytesPerPixel
        let observedOffset =
          observedY * observation.rowBytes
          + observedX * observation.pixelFormat.bytesPerPixel
        for component in 0..<baseline.pixelFormat.bytesPerPixel {
          absoluteDifference += abs(
            Double(baseline.bytes[baseOffset + component])
              - Double(observation.bytes[observedOffset + component])
          )
        }
        pixelCount += 1
      }
    }
    let byteCount = pixelCount * baseline.pixelFormat.bytesPerPixel
    return BackgroundResidual(
      meanAbsoluteDifference: byteCount == 0 ? 0 : absoluteDifference / Double(byteCount),
      pixelCount: pixelCount
    )
  }

  static func isNewInk(
    reference: StampedFrame,
    referenceX: Int,
    referenceY: Int,
    observation: StampedFrame,
    observationX: Int,
    observationY: Int,
    thresholds: InkPixelThresholds
  ) -> Bool {
    let referenceLuminance = luminance(reference, x: referenceX, y: referenceY)
    let observationLuminance = luminance(
      observation,
      x: observationX,
      y: observationY
    )
    return referenceLuminance - observationLuminance
      >= Int(thresholds.minimumLuminanceDecrease)
  }

  static func luminance(_ frame: StampedFrame, x: Int, y: Int) -> Int {
    let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    let red: Int
    let green: Int
    let blue: Int
    switch frame.pixelFormat {
    case .gray8:
      return Int(frame.bytes[offset])
    case .rgba8:
      red = Int(frame.bytes[offset])
      green = Int(frame.bytes[offset + 1])
      blue = Int(frame.bytes[offset + 2])
    case .bgra8:
      blue = Int(frame.bytes[offset])
      green = Int(frame.bytes[offset + 1])
      red = Int(frame.bytes[offset + 2])
    }
    return (54 * red + 183 * green + 19 * blue) / 256
  }
}
