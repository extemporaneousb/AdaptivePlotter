import Foundation
import Testing
@testable import PlotterModel

@Suite("Bounded cross-track residual models")
struct CrossTrackResidualModelTests {
  private func samples(holdout: Bool = false,
                       error: (Double, Double, DrawingTrialDirection) -> Double = {
                         0.3 + 0.1 * $0 - 0.06 * $1 + 0.08 * $2.sign
                       }) throws -> [CrossTrackResidualSample] {
    try (0..<4).flatMap { region in
      try DrawingTrialDirection.allCases.flatMap { direction in
        try (0..<(holdout ? 1 : 2)).map { row in
          let x = (region % 2 == 0 ? -0.6 : 0.6) + Double(direction.rawValue) * 0.03
          let y = (region / 2 == 0 ? -0.6 : 0.6) + (holdout ? 0.05 : Double(row) * 0.2)
          return try CrossTrackResidualSample(
            trialIndex: (holdout ? 100 : 0) + region * 8 + direction.rawValue * 2 + row,
            region: region, direction: direction, x: x, y: y, errorMM: error(x, y, direction))
        }
      }
    }
  }

  @Test("recovers spatial and signed-direction terms and passes untouched holdouts")
  func recoversKnownModel() throws {
    let training = try samples()
    let candidate = try CrossTrackResidualCandidate(training: training)
    for fit in [candidate.horizontal, candidate.vertical] {
      for (actual, expected) in zip(fit.coefficients, [0.3, 0.1, -0.06, 0.08]) {
        #expect(abs(actual - expected) < 1e-10)
      }
      #expect(fit.residualStandardErrorMM < 1e-10)
    }
    let comparison = try CrossTrackHoldoutComparison(candidate: candidate,
      training: training, holdouts: samples(holdout: true))
    #expect(comparison.passed)
    #expect(comparison.groups.count == 24)
    #expect(comparison.holdout.candidateRMSMM < 1e-10)
  }

  @Test("holdout changes cannot change fitted coefficients")
  func holdoutsNeverFit() throws {
    let training = try samples()
    let candidate = try CrossTrackResidualCandidate(training: training)
    let hostile = try samples(holdout: true, error: { _, _, _ in -0.3 })
    let comparison = try CrossTrackHoldoutComparison(candidate: candidate,
                                                    training: training, holdouts: hostile)
    #expect(!comparison.passed)
    #expect(candidate == (try CrossTrackResidualCandidate(training: training)))
    #expect(throws: (any Error).self) {
      try CrossTrackHoldoutComparison(candidate: candidate, training: training, holdouts: training)
    }
  }

  @Test("a regressing direction prevents advancement despite global improvement")
  func rejectsLocalRegression() throws {
    let training = try samples(error: { _, _, _ in 0.4 })
    let candidate = try CrossTrackResidualCandidate(training: training)
    let holdouts = try samples(holdout: true, error: { _, _, direction in
      direction == .negativeY ? 0.01 : 0.4
    })
    let result = try CrossTrackHoldoutComparison(candidate: candidate, training: training, holdouts: holdouts)
    #expect(result.holdout.candidateRMSMM < result.holdout.priorRMSMM)
    #expect(!result.passed)
    #expect(result.groups.contains { $0.label == "Y−" && $0.candidateRMSMM > $0.priorRMSMM })
  }

  @Test("missing coverage, duplicate trials, rank deficiency and unsafe extrapolation refuse")
  func rejectsInvalidFits() throws {
    let training = try samples()
    #expect(throws: (any Error).self) { try CrossTrackResidualCandidate(training: training + [training[0]]) }
    #expect(throws: (any Error).self) { try CrossTrackResidualCandidate(training: Array(training.prefix(4))) }
    let degenerate = try training.map {
      try CrossTrackResidualSample(trialIndex: $0.trialIndex, region: $0.region,
        direction: $0.direction, x: 0, y: 0, errorMM: $0.errorMM)
    }
    #expect(throws: (any Error).self) { try CrossTrackResidualCandidate(training: degenerate) }
    #expect(throws: (any Error).self) {
      try CrossTrackResidualCandidate(training: samples(error: { x, _, _ in 1.5 + x }))
    }
    let candidate = try CrossTrackResidualCandidate(training: training)
    #expect(throws: (any Error).self) {
      try CrossTrackHoldoutComparison(candidate: candidate, training: training,
                                     holdouts: Array(samples(holdout: true).dropLast()))
    }
  }

  @Test("a zero-error prior is not replaced and noise retains finite uncertainty")
  func conservativeComparisonAndUncertainty() throws {
    let zero = try samples(error: { _, _, _ in 0 })
    let candidate = try CrossTrackResidualCandidate(training: zero)
    let result = try CrossTrackHoldoutComparison(candidate: candidate, training: zero,
      holdouts: samples(holdout: true, error: { _, _, _ in 0 }))
    #expect(!result.passed)
    let noisy = try samples(error: { x, y, direction in
      0.3 + 0.1 * x + 0.1 * direction.sign + 0.03 * sin(17 * y)
    })
    let noisyCandidate = try CrossTrackResidualCandidate(training: noisy)
    #expect(noisyCandidate.horizontal.residualStandardErrorMM > 0)
    for sample in try samples(holdout: true) {
      let uncertainty = noisyCandidate.meanStandardErrorMM(at: sample)
      #expect(uncertainty.isFinite && uncertainty > 0)
    }
  }
}
