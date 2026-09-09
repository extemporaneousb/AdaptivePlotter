import CryptoKit
import Foundation
import PlotterModel

/// Sealed design/policy v1. Persisted inside each program's existing source
/// provenance, so the drawing archive remains the only trial evidence store.
public struct DrawingCoverageExperiment: Hashable, Codable, Sendable {
  public static let sourceKind = "adaptive-coverage-v1"
  public let id: UUID
  public let region: DrawableMachineRegion
  public let bounds: AxisAlignedBounds<MachineSpace>
  public let prior: DrawingPlanningProvenance
  public let tip: DrawingTipCalibrationEvidenceReference
  public let paper: PaperRevisionContext
  public let style: StrokeStyle

  public init(id: UUID = UUID(), region: DrawableMachineRegion,
              registration: TipCameraRegistration, prior: DrawingPlanningProvenance,
              paper: PaperRevisionContext, style: StrokeStyle) throws {
    let a = region.effectiveBounds
    let b = registration.applicabilityRectangle
    let bounds = try AxisAlignedBounds<MachineSpace>(
      minX: max(a.minX, b.minX) + 2, minY: max(a.minY, b.minY) + 2,
      maxX: min(a.maxX, b.maxX) - 2, maxY: min(a.maxY, b.maxY) - 2)
    try Self.validate(bounds: bounds, region: region)
    self.id = id
    self.region = region
    self.bounds = bounds
    self.prior = prior
    tip = try DrawingTipCalibrationEvidenceReference(
      acceptedRevisionID: registration.acceptedRevisionID,
      registrationEvidenceSHA256: prior.registrationContentHash.description,
      applicability: registration.applicability, estimatorRevision: registration.estimatorRevision)
    self.paper = paper
    self.style = style
  }

  private static func validate(bounds: AxisAlignedBounds<MachineSpace>,
                               region: DrawableMachineRegion) throws {
    let a = region.effectiveBounds
    // Eight columns and six rows; every cell has a >= 4 mm line and >= 5 mm
    // separation to a neighbouring line. No trial overlaps another trial.
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    guard bounds.maxX - bounds.minX >= 72 - epsilon,
      bounds.maxY - bounds.minY >= 54 - epsilon,
      bounds.minX >= a.minX, bounds.maxX <= a.maxX,
      bounds.minY >= a.minY, bounds.maxY <= a.maxY else {
      throw PlotterModelError.invalidValue("Coverage trials need at least 72 × 54 mm of applicable area, plus a 2 mm inset.")
    }
  }

  public var center: Point2<MachineSpace> {
    try! Point2(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2)
  }
  public var extent: Size2<FieldSpace> {
    try! Size2(width: bounds.maxX - bounds.minX, height: bounds.maxY - bounds.minY)
  }
  public var placement: DrawingPlacement {
    try! DrawingPlacement(fieldAnchor: Point2(x: extent.width / 2, y: extent.height / 2),
                          machineAnchor: center, uniformScale: 1)
  }

  public var trials: [DrawingCoverageTrial] {
    (0..<48).map { index in
      let quadrant = index / 12
      let local = index % 12
      let direction = DrawingTrialDirection(rawValue: local % 4)!
      let row = local / 4
      let column = quadrant % 2 * 4 + local % 4
      let globalRow = quadrant / 2 * 3 + row
      let x = (Double(column) + 0.5) / 8
      let y = (Double(globalRow) + 0.5) / 6
      return DrawingCoverageTrial(index: index, region: quadrant, direction: direction,
        role: row == 1 ? .reservedHoldout : .training,
        fieldCenter: try! Point2(x: x * extent.width, y: y * extent.height),
        normalizedX: x * 2 - 1, normalizedY: y * 2 - 1,
        lengthMM: min(12, min(extent.width / 8, extent.height / 6) - 5))
    }
  }

  public func program(for trial: DrawingCoverageTrial) throws -> DrawingProgram {
    guard trials.contains(trial) else { throw PlotterModelError.invalidValue("unknown coverage trial") }
    let descriptor = DrawingCoverageTrialDescriptor(experiment: self, trialIndex: trial.index)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let source = String(decoding: try encoder.encode(descriptor), as: UTF8.self)
    let data = Array(SHA256.hash(data: Data(source.utf8)))
    let uuid = UUID(uuid: (data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
                           data[8], data[9], data[10], data[11], data[12], data[13], data[14], data[15]))
    let dx = trial.direction.horizontal ? trial.lengthMM / 2 * trial.direction.sign : 0
    let dy = trial.direction.horizontal ? 0 : trial.lengthMM / 2 * trial.direction.sign
    let path = try Polyline<FieldSpace>(points: [
      Point2(x: trial.fieldCenter.x - dx, y: trial.fieldCenter.y - dy),
      Point2(x: trial.fieldCenter.x + dx, y: trial.fieldCenter.y + dy),
    ])
    return try DrawingProgram(id: ProgramID(uuid), fieldExtent: extent,
      strokes: [LogicalStroke(id: StrokeID(uuid), path: path, style: style,
                              semanticRole: .drawing, ordering: 0)],
      source: DrawingSourceProvenance(kind: Self.sourceKind, sourceIdentifier: source))
  }

  public func isCurrent(registration: TipCameraRegistration, prior: DrawingPlanningProvenance,
                        region: DrawableMachineRegion, paper: PaperRevisionContext) -> Bool {
    self.prior == prior && self.region == region && self.paper == paper
      && tip.acceptedRevisionID == registration.acceptedRevisionID
      && tip.applicability == registration.applicability
      && tip.registrationEvidenceSHA256 == prior.registrationContentHash.description
  }

  private enum CodingKeys: String, CodingKey { case id, region, bounds, prior, tip, paper, style }
  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    region = try c.decode(DrawableMachineRegion.self, forKey: .region)
    bounds = try c.decode(AxisAlignedBounds<MachineSpace>.self, forKey: .bounds)
    prior = try c.decode(DrawingPlanningProvenance.self, forKey: .prior)
    tip = try c.decode(DrawingTipCalibrationEvidenceReference.self, forKey: .tip)
    paper = try c.decode(PaperRevisionContext.self, forKey: .paper)
    style = try c.decode(StrokeStyle.self, forKey: .style)
    try Self.validate(bounds: bounds, region: region)
  }
}

public struct DrawingCoverageTrial: Hashable, Sendable {
  public let index: Int
  public let region: Int
  public let direction: DrawingTrialDirection
  public let role: BorderValidationEvidenceRole
  public let fieldCenter: Point2<FieldSpace>
  public let normalizedX: Double
  public let normalizedY: Double
  public let lengthMM: Double

  public var label: String {
    "Trial \(index + 1) · Region \(region + 1) · \(direction.label) · \(role == .training ? "Training" : "Reserved holdout")"
  }

  func sample(errorMM: Double) throws -> CrossTrackResidualSample {
    try CrossTrackResidualSample(trialIndex: index, region: region, direction: direction,
                                 x: normalizedX, y: normalizedY, errorMM: errorMM)
  }
}

public struct DrawingCoverageTrialDescriptor: Hashable, Codable, Sendable {
  public let experiment: DrawingCoverageExperiment
  public let trialIndex: Int

  public static func decode(_ source: DrawingSourceProvenance?) -> Self? {
    guard let source, source.kind == DrawingCoverageExperiment.sourceKind,
      source.sourceIdentifier.utf8.count <= 32_768,
      let value = try? JSONDecoder().decode(Self.self, from: Data(source.sourceIdentifier.utf8)),
      (0..<48).contains(value.trialIndex) else { return nil }
    return value
  }
}

public struct DrawingCoverageAssessment: Hashable, Sendable {
  public let trainingCount: Int
  public let holdoutCount: Int
  public let attemptedIndices: Set<Int>
  public let nextTrial: DrawingCoverageTrial?
  public let candidate: CrossTrackResidualCandidate?
  public let comparison: CrossTrackHoldoutComparison?
  public let blocker: String?

  public static func evaluate(experiment: DrawingCoverageExperiment,
                              records: [DrawingRunEvidenceRecord],
                              registration: TipCameraRegistration) -> Self {
    var training: [CrossTrackResidualSample] = []
    var holdouts: [CrossTrackResidualSample] = []
    var attempted: Set<Int> = []
    var blocker: String?
    var frames: Set<FrameID> = []
    guard let registrationHash = try? registration.drawingEvidenceContentHash(),
      registrationHash == experiment.prior.registrationContentHash else {
      return Self(trainingCount: 0, holdoutCount: 0, attemptedIndices: [], nextTrial: nil,
        candidate: nil, comparison: nil, blocker: "Exact registration evidence changed.")
    }
    // Archive order is causal order. Holdout admission is checked before fitting;
    // a restarted process cannot silently use training collected after holdouts.
    for record in records {
      if record.paper == experiment.paper {
        if record.program.source?.kind == DrawingCoverageExperiment.sourceKind,
          DrawingCoverageTrialDescriptor.decode(record.program.source)?.experiment.id != experiment.id {
          blocker = "Another coverage experiment already uses this sheet. Use a new sheet."
          break
        }
        if record.role == .ordinaryDrawing && record.executionFrontiers.commandedStrokeCount > 0 {
          blocker = "Ordinary drawing ink occupies this sheet. Use a new sheet for coverage trials."
          break
        }
      }
      guard let descriptor = DrawingCoverageTrialDescriptor.decode(record.program.source),
        descriptor.experiment.id == experiment.id else { continue }
      let trial = experiment.trials[descriptor.trialIndex]
      guard attempted.insert(trial.index).inserted else {
        blocker = "A coverage location was attempted twice; this experiment cannot be evaluated."
        break
      }
      guard descriptor.experiment == experiment else {
        blocker = "The sealed experiment definition changed."; break
      }
      if trial.role == .reservedHoldout && training.count != 32 {
        blocker = "A holdout was observed before the training set was sealed."; break
      }
      do {
        if case .observed(let observed) = record.observation {
          guard frames.insert(observed.frames.baseline.frameID).inserted,
            frames.insert(observed.frames.post.frameID).inserted else {
            throw PlotterModelError.invalidValue("An exact observation frame was reused by another trial")
          }
        }
        let sample = try measuredSample(record: record, trial: trial,
          experiment: experiment, registration: registration, registrationHash: registrationHash)
        if trial.role == .training { training.append(sample) } else { holdouts.append(sample) }
      } catch {
        blocker = "\(trial.label): \(error). Retain the record and use a new sheet for a new experiment."
        break
      }
    }
    var candidate: CrossTrackResidualCandidate?
    var comparison: CrossTrackHoldoutComparison?
    if training.count == 32 && blocker == nil {
      do {
        candidate = try CrossTrackResidualCandidate(training: training)
        if holdouts.count == 16, let candidate {
          comparison = try CrossTrackHoldoutComparison(candidate: candidate,
                                                       training: training, holdouts: holdouts)
        }
      } catch { blocker = "Candidate fit is inconclusive: \(error). The affine prior remains current." }
    }
    let next: DrawingCoverageTrial?
    if blocker != nil || comparison != nil { next = nil }
    else {
      let eligible = experiment.trials.filter {
        !attempted.contains($0.index) && $0.role == (training.count == 32 ? .reservedHoldout : .training)
      }
      // Balance direction/region first, then maximize distance from measured
      // same-direction locations. Once identifiable, prefer predicted mean
      // uncertainty. Outcome values never change the sealed split or locations.
      let provisional = try? CrossTrackResidualCandidate(training: training)
      func score(_ trial: DrawingCoverageTrial) -> Double {
        let peers = training.filter { $0.direction == trial.direction }
        let covered = peers.filter { $0.region == trial.region }.count
        let distance = peers.map { hypot($0.x - trial.normalizedX, $0.y - trial.normalizedY) }.min() ?? 4
        let uncertainty = (try? trial.sample(errorMM: 0)).flatMap {
          provisional?.meanStandardErrorMM(at: $0)
        } ?? 0
        return -Double(covered) * 100 + distance + min(uncertainty, 2)
      }
      next = eligible.sorted {
        let lhs = score($0), rhs = score($1)
        return lhs == rhs ? $0.index < $1.index : lhs > rhs
      }.first
    }
    return Self(trainingCount: training.count, holdoutCount: holdouts.count,
                attemptedIndices: attempted, nextTrial: next, candidate: candidate,
                comparison: comparison, blocker: blocker)
  }

  private static func measuredSample(record: DrawingRunEvidenceRecord, trial: DrawingCoverageTrial,
                                     experiment: DrawingCoverageExperiment,
                                     registration: TipCameraRegistration,
                                     registrationHash: PlotterModel.Digest) throws -> CrossTrackResidualSample {
    func reject(_ detail: String) throws -> Never { throw PlotterModelError.invalidValue(detail) }
    let (plan, observed) = try record.attributableResidualGeometry(
      using: registration, registrationContentHash: registrationHash)
    guard record.role == trial.role, plan.strokes.count == 1,
      record.tipCalibration == experiment.tip, record.paper == experiment.paper,
      record.planningProvenance == experiment.prior,
      plan.placement == experiment.placement, plan.drawableRegion == experiment.region,
      observed.residual != nil
    else { try reject("Trial is not attributable under the sealed role, geometry and provenance") }
    let program = try experiment.program(for: trial)
    let expected = try experiment.placement.applying(to: program.strokes[0].path)
    guard record.program.contentHash == program.contentHash, record.program.programID == program.id,
      plan.strokes[0].path == expected else {
      try reject("Exact planned and observed-request geometry does not match the sealed trial")
    }
    let inverse = try registration.cameraFromMachine.inverted()
    let points = try observed.observedInk[0].points.map { try inverse.applying(to: $0) }
    guard points.count >= 3 else { try reject("Insufficient independent line coverage") }
    let start = expected.points[0]
    let end = expected.points[1]
    // Require the central 60% to be seen. Endpoint/tangent error stays excluded.
    let along = points.map { trial.direction.horizontal ? $0.x : $0.y }
    let a = trial.direction.horizontal ? min(start.x, end.x) : min(start.y, end.y)
    let b = trial.direction.horizontal ? max(start.x, end.x) : max(start.y, end.y)
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    guard along.min()! <= a + (b - a) * 0.2 + epsilon,
      along.max()! >= b - (b - a) * 0.2 - epsilon else {
      try reject("Observed line does not cover the declared measurement span")
    }
    let errors = points.map { trial.direction.horizontal ? $0.y - start.y : $0.x - start.x }
    guard errors.allSatisfy({ $0.isFinite && abs($0) <= CrossTrackResidualCandidate.maximumCorrectionMM + epsilon }) else {
      try reject("Observed residual exceeds the declared 2 mm modelling range")
    }
    // Integrate the central span at symmetric positions. Averaging arbitrary
    // occupied Vision bins would bias a spatial slope toward the denser end.
    let ordered = zip(along, errors).sorted { $0.0 < $1.0 }
    var measurements: [Double] = []
    for i in 0...6 {
      let position = a + (b - a) * (0.2 + Double(i) * 0.1)
      if let exact = ordered.first(where: { abs($0.0 - position) <= epsilon }) {
        measurements.append(exact.1)
        continue
      }
      guard let upper = ordered.firstIndex(where: { $0.0 >= position }), upper > 0 else {
        try reject("Line sampling does not span the central measurement positions")
      }
      let left = ordered[upper - 1], right = ordered[upper]
      let gap = right.0 - left.0
      guard gap > 0, gap <= (b - a) * 0.35 + epsilon else {
        try reject("Observed line has an unresolved gap in the measurement span")
      }
      let fraction = (position - left.0) / gap
      measurements.append(left.1 + fraction * (right.1 - left.1))
    }
    return try trial.sample(errorMM: measurements.reduce(0, +) / Double(measurements.count))
  }
}

extension TipCameraRegistration {
  /// Same durable evidence hash used by planning and residual-model admission.
  public func drawingEvidenceContentHash() throws -> PlotterModel.Digest {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try PlotterModel.Digest(bytes: Array(SHA256.hash(data: encoder.encode(self))))
  }
}
