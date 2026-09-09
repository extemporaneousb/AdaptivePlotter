import Foundation
import PlotterModel

public struct DrawingResidualRecordSummary: Hashable, Sendable {
  public let recordID: DrawingEvidenceRecordID
  public let role: BorderValidationEvidenceRole
  public let title: String
  public let detail: String
  public let isSelected: Bool

  public init(record: DrawingRunEvidenceRecord, isSelected: Bool) {
    recordID = record.recordID
    role = record.role
    title = "\(record.program.source?.kind ?? "Drawing") · \(record.recordID.rawValue.uuidString.prefix(8))"
    if case .observed(let observed) = record.observation, let residual = observed.residual {
      detail = String(format: "Measured %.2f px RMS · %d strokes", residual.rootMeanSquarePixels,
        observed.observedInk.count)
    } else {
      detail = "\(record.executionDisposition) · \(record.evidenceDisposition)"
    }
    self.isSelected = isSelected
  }
}

/// Retains the existing immutable archive identity alongside each measured
/// constraint. Analysis never rewrites a record's declared trial role.
public struct DrawingResidualConstraint: Hashable, Sendable {
  public let recordID: DrawingEvidenceRecordID
  public let planRevisionID: ExecutionPlanRevisionID
  public let planContentHash: Digest
  public let registration: DrawingTipCalibrationEvidenceReference
  public let frames: DrawingObservationFramePair
  public let strokeIndex: Int
  public let sample: DrawingNormalResidualSample
}

public struct DrawingRetrospectiveResidualAnalysis: Hashable, Sendable {
  public let selectedRecordIDs: [DrawingEvidenceRecordID]
  public let constraints: [DrawingResidualConstraint]
  public let supportedStrokeCount: Int
  public let candidate: DrawingTranslationResidualCandidate?
  public let summary: String

  public static func evaluate(records: [DrawingRunEvidenceRecord],
                              registration: TipCameraRegistration?) -> Self {
    evaluate(records: records, registration: registration, samplingCheckpoint: nil)
  }

  /// Internal synchronous checkpoint for deterministic cancellation verification.
  /// It is never retained and is absent from the public production entry point.
  static func evaluate(records: [DrawingRunEvidenceRecord],
                       registration: TipCameraRegistration?,
                       samplingCheckpoint: ((Int, DrawingNormalResidualSample) -> Void)?) -> Self {
    var constraints: [DrawingResidualConstraint] = []
    var limitations: [String] = []
    var geometries: [(record: DrawingRunEvidenceRecord, frames: DrawingObservationFramePair, index: Int,
      intended: Polyline<MachineSpace>, measured: Polyline<MachineSpace>)] = []
    let prior = try? registration?.drawingEvidenceContentHash()
    for record in records {
      if Task.isCancelled { break }
      do {
        guard record.role == .ordinaryDrawing || record.role == .training else {
          throw PlotterModelError.invalidValue("Reserved and evaluation holdouts retain their original role and are excluded from fitting")
        }
        guard let registration, let prior else {
          throw PlotterModelError.invalidValue("The archived registration differs from the current accepted calibration")
        }
        let (plan, observed) = try record.attributableResidualGeometry(
          using: registration, registrationContentHash: prior)
        let inverse = try registration.cameraFromMachine.inverted()
        var recordConstraints: [DrawingResidualConstraint] = []
        var recordGeometry: [(record: DrawingRunEvidenceRecord, frames: DrawingObservationFramePair, index: Int,
          intended: Polyline<MachineSpace>, measured: Polyline<MachineSpace>)] = []
        for index in plan.strokes.indices {
          if Task.isCancelled { break }
          let intended = plan.strokes[index].path
          let measured = try inverse.applying(to: observed.observedInk[index])
          let samples = try normalSamples(intended: intended, measured: measured,
            iteration: 0, samplingCheckpoint: samplingCheckpoint)
          recordGeometry.append((record, observed.frames, index, intended, measured))
          if samples.isEmpty { continue }
          recordConstraints += samples.map { DrawingResidualConstraint(recordID: record.recordID,
            planRevisionID: record.plan.revisionID, planContentHash: record.plan.contentHash,
            registration: record.tipCalibration, frames: observed.frames,
            strokeIndex: index, sample: $0) }
        }
        if Task.isCancelled { break }
        constraints += recordConstraints
        geometries += recordGeometry
      } catch {
        limitations.append("\(record.recordID.rawValue.uuidString.prefix(8)): \(error)")
      }
    }
    var candidate: DrawingTranslationResidualCandidate?
    var detail: String
    do {
      try Task.checkCancellation()
      var fit = try DrawingTranslationResidualCandidate(samples: constraints.map(\.sample))
      var converged = false
      // Recompute correspondence around the estimate, while errors always use
      // the original measured points. A single linearization biases curved
      // paths when translation changes their nearest tangent substantially.
      for iteration in 1...32 {
        try Task.checkCancellation()
        var nextConstraints: [DrawingResidualConstraint] = []
        for geometry in geometries {
          let samples = try normalSamples(intended: geometry.intended, measured: geometry.measured,
            referenceX: fit.xMM, referenceY: fit.yMM,
            iteration: iteration, samplingCheckpoint: samplingCheckpoint)
          nextConstraints += samples.map { DrawingResidualConstraint(recordID: geometry.record.recordID,
            planRevisionID: geometry.record.plan.revisionID,
            planContentHash: geometry.record.plan.contentHash,
            registration: geometry.record.tipCalibration,
            frames: geometry.frames,
            strokeIndex: geometry.index, sample: $0) }
        }
        let next = try DrawingTranslationResidualCandidate(samples: nextConstraints.map(\.sample))
        constraints = nextConstraints
        let change = hypot(next.xMM - fit.xMM, next.yMM - fit.yMM)
        fit = next
        if change <= 1e-6 { converged = true; break }
      }
      guard converged else {
        throw PlotterModelError.invalidValue("normal correspondence did not converge within 32 iterations")
      }
      try Task.checkCancellation()
      candidate = fit
      detail = String(format: "Estimated constant XY error: X %+.3f mm, Y %+.3f mm. Normal RMS %.3f → %.3f mm.",
        fit.xMM, fit.yMM, fit.priorRMSMM, fit.fittedRMSMM)
    } catch {
      candidate = nil
      let samples = constraints.map(\.sample)
      if !samples.isEmpty {
        let rms = sqrt(samples.reduce(0) { $0 + $1.errorMM * $1.errorMM } / Double(samples.count))
        detail = String(format: "Measured normal RMS %.3f mm. Constant XY fitting is unidentifiable, outside the 2 mm range or unconverged: %@.", rms, String(describing: error))
      } else {
        detail = "No reusable measured paths in the selected records."
      }
    }
    let supportedByRecord = constraints.reduce(into: [DrawingEvidenceRecordID: Set<Int>]()) {
      $0[$1.recordID, default: []].insert($1.strokeIndex)
    }
    let supported = supportedByRecord.values.reduce(0) { $0 + $1.count }
    detail += " \(supported) strokes from \(Set(constraints.map(\.recordID)).count) drawings. Tangential error, spatial warping and direction effects are not estimated. This exploratory fit has no independent holdout and is not applied to drawing."
    if !limitations.isEmpty { detail += " " + limitations.joined(separator: "; ") }
    if Task.isCancelled {
      candidate = nil
      detail = "Residual analysis was cancelled. No candidate was produced."
    }
    return Self(selectedRecordIDs: records.map(\.recordID), constraints: constraints,
      supportedStrokeCount: supported, candidate: candidate, summary: detail)
  }

  /// Uniform arc-length samples prevent dense Vision bins or a dense portrait
  /// vectorization from dominating a stroke. Nearest-point normals deliberately
  /// measure only cross-track displacement, without claiming tangent matches.
  private static func normalSamples(intended: Polyline<MachineSpace>,
                                    measured: Polyline<MachineSpace>,
                                    referenceX: Double = 0, referenceY: Double = 0,
                                    iteration: Int,
                                    samplingCheckpoint: ((Int, DrawingNormalResidualSample) -> Void)?) throws -> [DrawingNormalResidualSample] {
    try Task.checkCancellation()
    guard intended.points.count >= 2, measured.points.count >= 2 else { return [] }
    let segments = Array(zip(measured.points, measured.points.dropFirst()))
    let lengths = segments.map { hypot($0.1.x - $0.0.x, $0.1.y - $0.0.y) }
    let total = lengths.reduce(0, +)
    guard total > DrawingRegionContainmentPolicy.numericalEpsilonMM else { return [] }
    var result: [DrawingNormalResidualSample] = []
    for sampleIndex in 0..<24 {
      try Task.checkCancellation()
      var distance = total * (0.1 + 0.8 * Double(sampleIndex) / 23)
      var segmentIndex = 0
      while segmentIndex + 1 < lengths.count && distance > lengths[segmentIndex] {
        distance -= lengths[segmentIndex]
        segmentIndex += 1
      }
      let segment = segments[segmentIndex]
      guard lengths[segmentIndex] > 0 else { continue }
      let t = min(1, distance / lengths[segmentIndex])
      let measuredPoint = try Point2<MachineSpace>(x: segment.0.x + (segment.1.x - segment.0.x) * t,
        y: segment.0.y + (segment.1.y - segment.0.y) * t)
      let matchingPoint = try Point2<MachineSpace>(x: measuredPoint.x - referenceX,
        y: measuredPoint.y - referenceY)
      var nearest: (point: Point2<MachineSpace>, nx: Double, ny: Double, squared: Double)?
      for (start, end) in zip(intended.points, intended.points.dropFirst()) {
        let dx = end.x - start.x, dy = end.y - start.y
        let squared = dx * dx + dy * dy
        guard squared > 1e-18 else { continue }
        let fraction = ((matchingPoint.x - start.x) * dx + (matchingPoint.y - start.y) * dy) / squared
        // Endpoint distance cannot identify cross-track error along a tangent.
        guard (0...1).contains(fraction) else { continue }
        let point = try Point2<MachineSpace>(x: start.x + fraction * dx, y: start.y + fraction * dy)
        let distanceSquared = pow(matchingPoint.x - point.x, 2) + pow(matchingPoint.y - point.y, 2)
        if nearest == nil || distanceSquared < nearest!.squared {
          let length = sqrt(squared)
          nearest = (point, -dy / length, dx / length, distanceSquared)
        }
      }
      guard let nearest, sqrt(nearest.squared) <= CrossTrackResidualCandidate.maximumCorrectionMM else { continue }
      let sample = try DrawingNormalResidualSample(plannedPoint: nearest.point,
        normalX: nearest.nx, normalY: nearest.ny,
        errorMM: (measuredPoint.x - nearest.point.x) * nearest.nx + (measuredPoint.y - nearest.point.y) * nearest.ny)
      result.append(sample)
      samplingCheckpoint?(iteration, sample)
      try Task.checkCancellation()
    }
    return result
  }
}
