import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

struct DrawingRunMediaCoverageTests {
  private let region = PixelRect(x: 100, y: 100, width: 4, height: 2)
  private var zeroShift: DrawingRunMediaCoveragePolicy {
    .init(alignmentSearchRadiusPixels: 0, maximumAlignmentShiftPixels: 0)
  }

  @Test("Production unknown masks preserve originals without manufacturing visible coverage")
  func unknownIsUnknown() async throws {
    let fixture = try Fixture()
    let view = try fixture.view(index: 0)
    let report = try await DrawingRunMediaCoverage.compose(views: [view], region: region, policy: zeroShift)
    #expect(report.coveredPixelCount == 0)
    #expect(report.uncoveredMask == Array(repeating: true, count: 8))
    #expect(report.perPixelSource.allSatisfy { $0 == nil })
    #expect(report.resultRGBA.allSatisfy { $0 == 0 })
    #expect(report.views[0].frames.baseline == ExactFrameProvenance(frame: view.baseline.frame))
    #expect(view.result.frame.bytes[100 * 640 + 100] == 10)
    #expect(report.derivationVersion == "exact-registered-visible-pair-selection-v1")
  }

  @Test("Partial overlapping views select actual matched pixels and retain exact source provenance")
  func partialOverlapAndProvenance() async throws {
    let fixture = try Fixture()
    let first = try fixture.view(index: 0, visibleColumns: [100, 101])
    let second = try fixture.view(index: 1, visibleColumns: [101, 102])
    let report = try await DrawingRunMediaCoverage.compose(views: [first, second], region: region, policy: zeroShift)
    #expect(report.coveredPixelCount == 6)
    #expect(report.uncoveredMask == [false, false, false, true, false, false, false, true])
    #expect(report.perPixelSource.map { $0?.viewIndex } == [0, 0, 1, nil, 0, 0, 1, nil])
    #expect(report.resultRGBA[0] == 10)
    #expect(report.resultRGBA[4] == 10) // deterministic first-view choice on overlap
    #expect(report.resultRGBA[8] == 20)
    #expect(report.resultRGBA[15] == 0)
    #expect(report.perPixelSource[2]?.baselineX == 102)
    #expect(report.perPixelSource[2]?.resultX == 102)
    #expect(report.compositionEvaluationCount <= 8 * 2)
    #expect(try JSONDecoder().decode(DrawingRunMediaCoverage.self,
      from: JSONEncoder().encode(report)) == report)
  }

  @Test("One visible frame and an occluded partner never form a visible comparison")
  func matchedVisibilityIsMandatory() async throws {
    let fixture = try Fixture()
    let view = try fixture.view(index: 0, visibleColumns: [100, 101, 102, 103])
    var pixels = view.resultVisibility.pixels
    pixels[100 * 640 + 101] = .occluded
    let mask = try DrawingRunVisibilityMask(frame: view.resultVisibility.frame, source: fixture.source,
      pixels: pixels, basis: view.resultVisibility.basis)
    let partial = try DrawingRunCoverageView(baseline: view.baseline, result: view.result,
      registration: view.registration, baselineVisibility: view.baselineVisibility, resultVisibility: mask)
    let report = try await DrawingRunMediaCoverage.compose(views: [partial], region: region, policy: zeroShift)
    #expect(report.coveredPixelCount == 7)
    #expect(report.uncoveredMask[1])
    #expect(report.views[0].resultVisibility.pixels[100 * 640 + 101] == .occluded)
  }

  @Test("Pair alignment remaps the mask and source coordinates rather than inventing pixels")
  func translatedPair() async throws {
    let fixture = try Fixture()
    let view = try fixture.view(index: 0, visibleColumns: [100, 101, 102, 103], resultShift: 2)
    let report = try await DrawingRunMediaCoverage.compose(views: [view], region: region)
    #expect(report.views[0].resultAlignment.shiftX == 2)
    #expect(report.coveredPixelCount == 8)
    #expect(report.perPixelSource[0]?.baselineX == 100)
    #expect(report.perPixelSource[0]?.resultX == 102)
    #expect(report.resultRGBA[0] == view.result.frame.bytes[100 * 640 + 102])
  }

  @Test("Cross-view alignment keeps matched baseline/result coordinates in the reference grid")
  func translatedSecondView() async throws {
    let fixture = try Fixture()
    let first = try fixture.view(index: 0, visibleColumns: [100])
    let second = try fixture.view(index: 1, visibleColumns: [101, 102], baselineShift: 2)
    let report = try await DrawingRunMediaCoverage.compose(views: [first, second], region: region)
    #expect(report.views[1].baselineAlignment.shiftX == 2)
    #expect(report.views[1].resultAlignment.shiftX == 0)
    #expect(report.coveredPixelCount == 6)
    #expect(report.perPixelSource[1]?.viewIndex == 1)
    #expect(report.perPixelSource[1]?.baselineX == 103)
    #expect(report.perPixelSource[1]?.resultX == 103)
    #expect(report.resultRGBA[4] == 20)
  }

  @Test("Durable derivative decode rejects forged uncovered-pixel provenance")
  func corruptDerivativeRefuses() async throws {
    let fixture = try Fixture()
    let report = try await DrawingRunMediaCoverage.compose(views: [fixture.view(index: 0)], region: region, policy: zeroShift)
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])
    object["uncoveredMask"] = Array(repeating: false, count: 8)
    let data = try JSONSerialization.data(withJSONObject: object)
    #expect(throws: DrawingRunMediaCoverageError.invalidVisibilityEvidence) {
      try JSONDecoder().decode(DrawingRunMediaCoverage.self, from: data)
    }
  }

  @Test("Misregistration, source/configuration changes and unmatched poses refuse comparison")
  func refusalBoundaries() async throws {
    let fixture = try Fixture()
    let view = try fixture.view(index: 0)
    let shifted = try fixture.view(index: 1, resultShift: 3)
    await #expect(throws: DrawingRunMediaCoverageError.alignmentRefused) {
      try await DrawingRunMediaCoverage.compose(views: [shifted], region: region,
        policy: .init(alignmentSearchRadiusPixels: 3, maximumAlignmentShiftPixels: 2))
    }
    let foreign = try DrawingRunCoverageView(baseline: view.baseline,
      result: SamePoseFrameSample(source: .simulated, frame: view.result.frame,
        controllerPosition: view.result.controllerPosition), registration: fixture.registration)
    await #expect(throws: DrawingRunMediaCoverageError.frameMismatch) {
      try await DrawingRunMediaCoverage.compose(views: [foreign], region: region, policy: zeroShift)
    }
    let wrongPose = try DrawingRunCoverageView(baseline: view.baseline,
      result: SamePoseFrameSample(source: fixture.source, frame: view.result.frame,
        controllerPosition: MachinePosition(x: 20, y: 20)), registration: fixture.registration)
    await #expect(throws: DrawingRunMediaCoverageError.poseMismatch) {
      try await DrawingRunMediaCoverage.compose(views: [wrongPose], region: region, policy: zeroShift)
    }
    let other = try Fixture()
    let foreignConfig = try other.view(index: 1)
    await #expect(throws: DrawingRunMediaCoverageError.frameMismatch) {
      try await DrawingRunMediaCoverage.compose(views: [view, foreignConfig], region: region, policy: zeroShift)
    }
    let changedRegistration = try DrawingRunCoverageView(baseline: view.baseline, result: view.result,
      registration: other.registration)
    await #expect(throws: DrawingRunMediaCoverageError.registrationMismatch) {
      try await DrawingRunMediaCoverage.compose(views: [view, changedRegistration], region: region, policy: zeroShift)
    }
  }

  @Test("Unknown basis cannot bless pixels and operator evidence is exact-frame bound")
  func visibilityEvidenceCannotBeInventedByUnknownBasis() throws {
    let fixture = try Fixture(), view = try fixture.view(index: 0)
    let exact = ExactFrameProvenance(frame: view.baseline.frame)
    let pixels = Array(repeating: DrawingRunPixelVisibility.visible, count: 640 * 480)
    #expect(throws: DrawingRunMediaCoverageError.invalidVisibilityEvidence) {
      try DrawingRunVisibilityMask(frame: exact, source: fixture.source, pixels: pixels, basis: .unknown)
    }
    let operatorEvidence = DrawingMaterialVisibilityEvidence(
      inspectedFrames: [ExactFrameProvenance(frame: view.result.frame)], source: fixture.source)
    #expect(throws: DrawingRunMediaCoverageError.invalidVisibilityEvidence) {
      try DrawingRunVisibilityMask(frame: exact, source: fixture.source, pixels: pixels,
        basis: .operatorInspection(operatorEvidence))
    }
  }

  @Test("Region/view/alignment work budgets and cancellation are finite and explicit")
  func finiteWorkAndCancellation() async throws {
    let fixture = try Fixture(), view = try fixture.view(index: 0)
    await #expect(throws: DrawingRunMediaCoverageError.workBudgetExceeded) {
      try await DrawingRunMediaCoverage.compose(views: [view], region: region,
        policy: .init(maximumAlignmentEvaluationCount: 10))
    }
    await #expect(throws: DrawingRunMediaCoverageError.workBudgetExceeded) {
      try await DrawingRunMediaCoverage.compose(views: [view, view], region: region)
    }
    await #expect(throws: DrawingRunMediaCoverageError.invalidRegion) {
      try await DrawingRunMediaCoverage.compose(views: [view],
        region: PixelRect(x: Int.max, y: 0, width: 1, height: 1))
    }
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try await DrawingRunMediaCoverage.compose(views: [view], region: region)
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  private struct Fixture {
    let source: FrameSourceIdentity
    let configuration: CameraConfigurationID
    let registration: TipCameraRegistration
    init() throws {
      let authority = try TipAuthorityFixture()
      source = authority.source; configuration = authority.cameraConfigurationID
      registration = try authority.registration()
    }
    func view(index: Int, visibleColumns: Set<Int>? = nil, resultShift: Int = 0, baselineShift: Int = 0) throws -> DrawingRunCoverageView {
      let w = 640, h = 480
      var before = [UInt8](repeating: 0, count: w * h)
      for y in 0..<h { for x in 0..<w {
        // A nonperiodic spatial hash makes integer registration identifiable.
        let hash = ((x &* 73_856_093) ^ (y &* 19_349_663)) & 127
        before[y * w + x] = UInt8(128 + hash)
      } }
      var unshifted = before
      for y in 100..<102 { for x in 100..<104 { unshifted[y * w + x] = UInt8(10 + index * 10) } }
      func shifted(_ pixels: [UInt8], by shift: Int) -> [UInt8] {
        guard shift != 0 else { return pixels }
        var output = pixels
        for y in 0..<h { for x in 0..<w {
          output[y * w + x] = pixels[y * w + max(0, x-shift)]
        } }
        return output
      }
      let after = shifted(unshifted, by: baselineShift + resultShift)
      before = shifted(before, by: baselineShift)
      let baseline = try StampedFrame(sequence: UInt64(index * 2 + 1), captureNanoseconds: UInt64(index * 2 + 1),
        cameraConfigurationID: configuration, width: w, height: h, rowBytes: w,
        pixelFormat: .gray8, bytes: OwnedFrameBytes(before))
      let result = try StampedFrame(sequence: UInt64(index * 2 + 2), captureNanoseconds: UInt64(index * 2 + 2),
        cameraConfigurationID: configuration, width: w, height: h, rowBytes: w,
        pixelFormat: .gray8, bytes: OwnedFrameBytes(after))
      let pose = try MachinePosition(x: Double(index * 10), y: 0)
      let baselineSample = SamePoseFrameSample(source: source, frame: baseline, controllerPosition: pose)
      let resultSample = SamePoseFrameSample(source: source, frame: result, controllerPosition: pose)
      func mask(_ sample: SamePoseFrameSample, shift: Int) throws -> DrawingRunVisibilityMask? {
        guard let visibleColumns else { return nil }
        var pixels = [DrawingRunPixelVisibility](repeating: .unknown, count: w * h)
        for y in 100..<102 { for x in visibleColumns { pixels[y * w + x + shift] = .visible } }
        return try .init(frame: ExactFrameProvenance(frame: sample.frame), source: source,
          pixels: pixels, basis: .independentClassification(
            AlgorithmRevisionEvidence(component: "synthetic-ground-truth-visibility", revision: "fixture-v1")))
      }
      return try DrawingRunCoverageView(baseline: baselineSample, result: resultSample,
        registration: registration, baselineVisibility: mask(baselineSample, shift: baselineShift),
        resultVisibility: mask(resultSample, shift: baselineShift + resultShift))
    }
  }
}
