import Foundation

/// A signed normal displacement measured against one declared planned path.
/// Tangential correspondence is intentionally not inferred from camera ink.
public struct DrawingNormalResidualSample: Hashable, Sendable {
  public let plannedPoint: Point2<MachineSpace>
  public let normalX: Double
  public let normalY: Double
  public let errorMM: Double

  public init(plannedPoint: Point2<MachineSpace>, normalX: Double, normalY: Double,
              errorMM: Double) throws {
    guard normalX.isFinite, normalY.isFinite, errorMM.isFinite,
      abs(hypot(normalX, normalY) - 1) < 1e-9 else {
      throw PlotterModelError.invalidValue("invalid oriented residual")
    }
    self.plannedPoint = plannedPoint
    self.normalX = normalX
    self.normalY = normalY
    self.errorMM = errorMM
  }
}

/// An exploratory constant XY error fitted from actual path normals. This is a
/// model value, not accepted calibration or execution authority. The sealed
/// spatial/direction experiment model below retains its separate semantics.
public struct DrawingTranslationResidualCandidate: Hashable, Sendable {
  public let xMM: Double
  public let yMM: Double
  public let priorRMSMM: Double
  public let fittedRMSMM: Double
  public let sampleCount: Int

  public init(samples: [DrawingNormalResidualSample]) throws {
    guard samples.count >= 3 else { throw RegistrationError.insufficientPoints }
    var xx = 0.0, xy = 0.0, yy = 0.0, bx = 0.0, by = 0.0
    for sample in samples {
      xx += sample.normalX * sample.normalX
      xy += sample.normalX * sample.normalY
      yy += sample.normalY * sample.normalY
      bx += sample.normalX * sample.errorMM
      by += sample.normalY * sample.errorMM
    }
    let determinant = xx * yy - xy * xy
    guard determinant > 1e-6 * pow(xx + yy, 2) else {
      throw RegistrationError.degenerateGeometry
    }
    let x = (bx * yy - by * xy) / determinant
    let y = (by * xx - bx * xy) / determinant
    guard x.isFinite, y.isFinite,
      hypot(x, y) <= CrossTrackResidualCandidate.maximumCorrectionMM else {
      throw PlotterModelError.invalidValue("translation candidate exceeds 2 mm modelling range")
    }
    xMM = x
    yMM = y
    sampleCount = samples.count
    priorRMSMM = sqrt(samples.reduce(0) { $0 + $1.errorMM * $1.errorMM } / Double(samples.count))
    fittedRMSMM = sqrt(samples.reduce(0) {
      let error = $1.errorMM - $1.normalX * x - $1.normalY * y
      return $0 + error * error
    } / Double(samples.count))
  }
}

public enum DrawingTrialDirection: Int, Codable, CaseIterable, Hashable, Sendable {
  case positiveX, negativeX, positiveY, negativeY

  public var horizontal: Bool { self == .positiveX || self == .negativeX }
  public var sign: Double { self == .positiveX || self == .positiveY ? 1 : -1 }
  public var label: String {
    switch self {
    case .positiveX: "X+"
    case .negativeX: "X−"
    case .positiveY: "Y+"
    case .negativeY: "Y−"
    }
  }
}

/// One independent line, not one pixel. Coordinates are normalized to the
/// declared experiment rectangle; error is signed machine X (vertical lines)
/// or machine Y (horizontal lines). Along-track error is not identifiable here.
public struct CrossTrackResidualSample: Hashable, Sendable {
  public let trialIndex: Int
  public let region: Int
  public let direction: DrawingTrialDirection
  public let x: Double
  public let y: Double
  public let errorMM: Double

  public init(trialIndex: Int, region: Int, direction: DrawingTrialDirection,
              x: Double, y: Double, errorMM: Double) throws {
    guard (0..<4).contains(region), x.isFinite, y.isFinite, errorMM.isFinite,
      abs(x) <= 1, abs(y) <= 1 else {
      throw PlotterModelError.invalidValue("invalid cross-track sample")
    }
    self.trialIndex = trialIndex
    self.region = region
    self.direction = direction
    self.x = x
    self.y = y
    self.errorMM = errorMM
  }

  var row: [Double] { [1, x, y, direction.sign] }
}

public struct CrossTrackAxisFit: Hashable, Sendable {
  /// intercept, normalized X slope, normalized Y slope, signed direction term.
  public let coefficients: [Double]
  public let residualStandardErrorMM: Double
  private let inverseR: [[Double]]

  fileprivate init(samples: [CrossTrackResidualSample]) throws {
    guard samples.count > 4 else { throw RegistrationError.insufficientPoints }
    // Modified Gram-Schmidt with a second orthogonalization pass. Reject weak
    // rank rather than hiding an unidentifiable model behind regularization.
    let rows = samples.map(\.row)
    var q: [[Double]] = []
    var r = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
    for column in 0..<4 {
      var v = rows.map { $0[column] }
      for _ in 0..<2 {
        for prior in 0..<column {
          let projection = zip(q[prior], v).reduce(0) { $0 + $1.0 * $1.1 }
          r[prior][column] += projection
          for i in v.indices { v[i] -= projection * q[prior][i] }
        }
      }
      let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
      guard norm > 1e-6 * sqrt(Double(samples.count)) else {
        throw RegistrationError.degenerateGeometry
      }
      r[column][column] = norm
      q.append(v.map { $0 / norm })
    }
    func solve(_ rhs: [Double]) -> [Double] {
      var result = rhs
      for i in (0..<4).reversed() {
        for j in (i + 1)..<4 { result[i] -= r[i][j] * result[j] }
        result[i] /= r[i][i]
      }
      return result
    }
    let coefficients = solve(q.map { column in
      zip(column, samples).reduce(0) { $0 + $1.0 * $1.1.errorMM }
    })
    self.coefficients = coefficients
    inverseR = (0..<4).map { column in
      solve((0..<4).map { $0 == column ? 1.0 : 0.0 })
    } // columns of R inverse
    let squared = samples.reduce(0) { sum, sample in
      let predicted = zip(coefficients, sample.row).reduce(0) { $0 + $1.0 * $1.1 }
      return sum + pow(sample.errorMM - predicted, 2)
    }
    residualStandardErrorMM = sqrt(squared / Double(samples.count - 4))
  }

  fileprivate func predict(_ sample: CrossTrackResidualSample) -> Double {
    zip(coefficients, sample.row).reduce(0) { $0 + $1.0 * $1.1 }
  }

  /// Standard error of the estimated mean, not an ink guarantee or a confidence gate.
  fileprivate func standardError(_ sample: CrossTrackResidualSample) -> Double {
    let transformed = inverseR.map { column in
      zip(column, sample.row).reduce(0) { $0 + $1.0 * $1.1 }
    }
    return residualStandardErrorMM * sqrt(transformed.reduce(0) { $0 + $1 * $1 })
  }
}

public struct CrossTrackResidualCandidate: Hashable, Sendable {
  public static let maximumCorrectionMM = 2.0
  public static let numericalEpsilonMM = 1e-9
  public let trainingTrialIndices: [Int]
  public let horizontal: CrossTrackAxisFit
  public let vertical: CrossTrackAxisFit

  public init(training: [CrossTrackResidualSample]) throws {
    guard Set(training.map(\.trialIndex)).count == training.count else {
      throw PlotterModelError.invalidValue("duplicate training trial")
    }
    horizontal = try CrossTrackAxisFit(samples: training.filter { $0.direction.horizontal })
    vertical = try CrossTrackAxisFit(samples: training.filter { !$0.direction.horizontal })
    // Triangle bound covers every position and signed direction in the declared
    // rectangle, including locations between samples. Do not clamp a bad fit.
    guard [horizontal, vertical].allSatisfy({
      $0.coefficients.allSatisfy(\.isFinite)
        && $0.coefficients.reduce(0, { $0 + abs($1) }) <= Self.maximumCorrectionMM + Self.numericalEpsilonMM
    }) else { throw PlotterModelError.invalidValue("candidate exceeds 2 mm correction bound") }
    trainingTrialIndices = training.map(\.trialIndex).sorted()
  }

  public func predictedErrorMM(at sample: CrossTrackResidualSample) -> Double {
    (sample.direction.horizontal ? horizontal : vertical).predict(sample)
  }

  public func meanStandardErrorMM(at sample: CrossTrackResidualSample) -> Double {
    (sample.direction.horizontal ? horizontal : vertical).standardError(sample)
  }
}

public struct CrossTrackComparisonMetric: Hashable, Sendable {
  public let label: String
  public let count: Int
  public let priorRMSMM: Double
  public let candidateRMSMM: Double

  fileprivate init(label: String, samples: [CrossTrackResidualSample],
                   candidate: CrossTrackResidualCandidate) {
    self.label = label
    count = samples.count
    priorRMSMM = sqrt(samples.reduce(0) { $0 + pow($1.errorMM, 2) } / Double(count))
    candidateRMSMM = sqrt(samples.reduce(0) {
      $0 + pow($1.errorMM - candidate.predictedErrorMM(at: $1), 2)
    } / Double(count))
  }
}

/// Predeclared policy v1: at least 0.05 mm AND 10% RMS improvement overall,
/// with no RMS regression in any direction, quadrant, or quadrant/direction.
/// This compares predictions on prior-model ink. It does not validate executing
/// a correction, accept a model, or establish whole-stroke drawing readiness.
public struct CrossTrackHoldoutComparison: Hashable, Sendable {
  public let training: CrossTrackComparisonMetric
  public let holdout: CrossTrackComparisonMetric
  public let groups: [CrossTrackComparisonMetric]
  public let passed: Bool

  public init(candidate: CrossTrackResidualCandidate,
              training: [CrossTrackResidualSample], holdouts: [CrossTrackResidualSample]) throws {
    guard training.map(\.trialIndex).sorted() == candidate.trainingTrialIndices,
      Set(holdouts.map(\.trialIndex)).count == holdouts.count,
      Set(holdouts.map(\.trialIndex)).isDisjoint(with: candidate.trainingTrialIndices)
    else { throw PlotterModelError.invalidValue("training and holdouts must be disjoint") }
    var groups: [CrossTrackComparisonMetric] = []
    for region in 0..<4 {
      for direction in DrawingTrialDirection.allCases {
        let samples = holdouts.filter { $0.region == region && $0.direction == direction }
        guard !samples.isEmpty else { throw RegistrationError.insufficientPoints }
        groups.append(.init(label: "Region \(region + 1) \(direction.label)",
                            samples: samples, candidate: candidate))
      }
      groups.append(.init(label: "Region \(region + 1)",
                          samples: holdouts.filter { $0.region == region }, candidate: candidate))
    }
    for direction in DrawingTrialDirection.allCases {
      groups.append(.init(label: direction.label,
                          samples: holdouts.filter { $0.direction == direction }, candidate: candidate))
    }
    self.training = .init(label: "Training", samples: training, candidate: candidate)
    holdout = .init(label: "Reserved holdouts", samples: holdouts, candidate: candidate)
    self.groups = groups
    passed = holdout.priorRMSMM - holdout.candidateRMSMM >= 0.05 - CrossTrackResidualCandidate.numericalEpsilonMM
      && holdout.candidateRMSMM <= holdout.priorRMSMM * 0.9 + CrossTrackResidualCandidate.numericalEpsilonMM
      && groups.allSatisfy { $0.candidateRMSMM <= $0.priorRMSMM + CrossTrackResidualCandidate.numericalEpsilonMM }
  }
}
