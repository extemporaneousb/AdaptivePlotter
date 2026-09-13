import Foundation
import PlotterModel

public enum DrawingRunMediaCoverageError: Error, Equatable, Sendable {
  case invalidPolicy, workBudgetExceeded, frameMismatch, registrationMismatch
  case poseMismatch, invalidVisibilityEvidence, alignmentRefused, invalidRegion
}

public enum DrawingRunPixelVisibility: UInt8, Codable, Hashable, Sendable {
  case unknown = 0, visible = 1, occluded = 2
}

/// Classification is supplied by an independent producer; pose/cap predictions
/// cannot construct visible coverage. Operator evidence must name this exact frame.
public struct DrawingRunVisibilityMask: Codable, Hashable, Sendable {
  public enum Basis: Codable, Hashable, Sendable {
    case unknown
    case independentClassification(AlgorithmRevisionEvidence)
    case operatorInspection(DrawingMaterialVisibilityEvidence)
  }
  public let frame: ExactFrameProvenance
  public let source: FrameSourceIdentity
  public let pixels: [DrawingRunPixelVisibility]
  public let basis: Basis

  public init(frame: ExactFrameProvenance, source: FrameSourceIdentity,
    pixels: [DrawingRunPixelVisibility], basis: Basis) throws {
    guard frame.width > 0, frame.height > 0, frame.width <= 4_194_304 / frame.height,
      pixels.count == frame.width * frame.height else {
      throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
    }
    switch basis {
    case .unknown:
      guard pixels.allSatisfy({ $0 == .unknown }) else {
        throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
      }
    case .independentClassification(let revision):
      guard !revision.component.isEmpty, !revision.revision.isEmpty else {
        throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
      }
    case .operatorInspection(let evidence):
      guard evidence.source == source, evidence.inspectedFrames.contains(frame),
        evidence.method == "operator-confirmed-unobstructed-v1",
        evidence.confirmedAt.timeIntervalSince1970.isFinite else {
        throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
      }
    }
    self.frame = frame; self.source = source; self.pixels = pixels; self.basis = basis
  }

  public static func unknown(sample: SamePoseFrameSample) throws -> Self {
    let frame = ExactFrameProvenance(frame: sample.frame)
    guard frame.height > 0, frame.width <= 4_194_304 / frame.height else {
      throw DrawingRunMediaCoverageError.workBudgetExceeded
    }
    return try .init(frame: frame, source: sample.source,
      pixels: Array(repeating: .unknown, count: frame.width * frame.height), basis: .unknown)
  }
}

/// Owned samples are ephemeral inputs. Raw originals must also be committed by
/// DrawingRunEvidenceStore; composites are derivatives and never replace them.
public struct DrawingRunCoverageView: Sendable {
  public let viewID: UUID
  public let baseline: SamePoseFrameSample
  public let result: SamePoseFrameSample
  public let registration: TipCameraRegistration
  public let baselineVisibility: DrawingRunVisibilityMask
  public let resultVisibility: DrawingRunVisibilityMask

  public init(viewID: UUID = UUID(), baseline: SamePoseFrameSample, result: SamePoseFrameSample,
    registration: TipCameraRegistration, baselineVisibility: DrawingRunVisibilityMask? = nil,
    resultVisibility: DrawingRunVisibilityMask? = nil) throws {
    self.viewID = viewID; self.baseline = baseline; self.result = result
    self.registration = registration
    self.baselineVisibility = try baselineVisibility ?? .unknown(sample: baseline)
    self.resultVisibility = try resultVisibility ?? .unknown(sample: result)
  }
}

public struct DrawingRunMediaCoveragePolicy: Codable, Hashable, Sendable {
  public let maximumViewCount: Int
  public let maximumRegionPixelCount: Int
  public let maximumFramePixelCount: Int
  public let maximumAlignmentEvaluationCount: Int
  public let alignmentSearchRadiusPixels: Int
  public let maximumAlignmentShiftPixels: Int
  public let maximumBackgroundMeanAbsoluteDifference: Double
  public let controllerPositionToleranceMM: Double
  public init(maximumViewCount: Int = 3, maximumRegionPixelCount: Int = 1_000_000,
    maximumFramePixelCount: Int = 4_194_304, maximumAlignmentEvaluationCount: Int = 500_000_000,
    alignmentSearchRadiusPixels: Int = 2, maximumAlignmentShiftPixels: Int = 2,
    maximumBackgroundMeanAbsoluteDifference: Double = 15,
    controllerPositionToleranceMM: Double = 0.1) {
    self.maximumViewCount = maximumViewCount; self.maximumRegionPixelCount = maximumRegionPixelCount
    self.maximumFramePixelCount = maximumFramePixelCount
    self.maximumAlignmentEvaluationCount = maximumAlignmentEvaluationCount
    self.alignmentSearchRadiusPixels = alignmentSearchRadiusPixels
    self.maximumAlignmentShiftPixels = maximumAlignmentShiftPixels
    self.maximumBackgroundMeanAbsoluteDifference = maximumBackgroundMeanAbsoluteDifference
    self.controllerPositionToleranceMM = controllerPositionToleranceMM
  }
}

public struct DrawingRunCoverageViewEvidence: Codable, Hashable, Sendable {
  public let viewID: UUID
  public let frames: DrawingObservationFramePair
  public let baselineVisibility: DrawingRunVisibilityMask
  public let resultVisibility: DrawingRunVisibilityMask
  /// Reference baseline -> this baseline; resultAlignment maps this baseline -> result.
  public let baselineAlignment: IntegerFrameAlignment
  public let resultAlignment: IntegerFrameAlignment
}

public struct DrawingRunPixelSource: Codable, Hashable, Sendable {
  public let viewIndex: Int
  public let baselineX: Int
  public let baselineY: Int
  public let resultX: Int
  public let resultY: Int
}

/// A deterministic comparison in the first baseline's camera pixel coordinates.
/// Every opaque output pixel copies an actual input pixel with exact provenance.
/// Uncovered pixels are transparent; no resampling, fill or invented ink is used.
public struct DrawingRunMediaCoverage: Codable, Hashable, Sendable {
  public let derivationVersion: String
  public let registration: TipCameraRegistration
  public let region: PixelRect
  public let policy: DrawingRunMediaCoveragePolicy
  public let views: [DrawingRunCoverageViewEvidence]
  public let baselineRGBA: Data
  public let resultRGBA: Data
  public let uncoveredMask: [Bool]
  public let perPixelSource: [DrawingRunPixelSource?]
  public let alignmentEvaluatedPixelCount: Int
  public let compositionEvaluationCount: Int
  public var coveredPixelCount: Int { uncoveredMask.filter { !$0 }.count }

  public static func compose(views inputs: [DrawingRunCoverageView], region: PixelRect,
    policy: DrawingRunMediaCoveragePolicy = .init()) async throws -> Self {
    try Task.checkCancellation()
    guard validPolicy(policy) else { throw DrawingRunMediaCoverageError.invalidPolicy }
    guard let first = inputs.first, inputs.count <= policy.maximumViewCount,
      Set(inputs.map(\.viewID)).count == inputs.count else {
      throw DrawingRunMediaCoverageError.workBudgetExceeded
    }
    guard region.width > 0, region.height > 0, region.x >= 0, region.y >= 0,
      region.width <= policy.maximumRegionPixelCount / region.height else {
      throw DrawingRunMediaCoverageError.invalidRegion
    }
    let reference = first.baseline.frame
    let registrationHash = try first.registration.drawingEvidenceContentHash()
    let optical = first.registration.applicability.opticalConfiguration
    var evidences: [DrawingRunCoverageViewEvidence] = []
    var alignmentsEvaluated = 0
    var estimatedEvaluations = 0
    let candidateSide = policy.alignmentSearchRadiusPixels * 2 + 1
    // Deliberately conservative upper bound: all coarse candidates plus three
    // verified candidates at full frame resolution, for each alignment call.
    let perPixelAlignmentBound = candidateSide * candidateSide + 3
    for input in inputs {
      try Task.checkCancellation()
      let baseline = input.baseline, result = input.result
      guard baseline.source == first.baseline.source, result.source == baseline.source,
        baseline.source == optical.source,
        baseline.frame.cameraConfigurationID == reference.cameraConfigurationID,
        result.frame.cameraConfigurationID == reference.cameraConfigurationID,
        baseline.frame.width == reference.width, baseline.frame.height == reference.height,
        baseline.frame.pixelFormat == reference.pixelFormat,
        baseline.frame.width == optical.width, baseline.frame.height == optical.height,
        baseline.frame.pixelFormat == optical.pixelFormat else {
        throw DrawingRunMediaCoverageError.frameMismatch
      }
      guard try input.registration.drawingEvidenceContentHash() == registrationHash else {
        throw DrawingRunMediaCoverageError.registrationMismatch
      }
      let frame = baseline.frame
      guard frame.height > 0, frame.width <= policy.maximumFramePixelCount / frame.height,
        frame.bytes.count <= 32 * 1_048_576, result.frame.bytes.count <= 32 * 1_048_576 else {
        throw DrawingRunMediaCoverageError.workBudgetExceeded
      }
      guard region.x <= frame.width, region.y <= frame.height,
        region.width <= frame.width-region.x, region.height <= frame.height-region.y else {
        throw DrawingRunMediaCoverageError.invalidRegion
      }
      let pair = try DrawingObservationFramePair(source: baseline.source,
        baseline: ExactFrameProvenance(frame: frame), post: ExactFrameProvenance(frame: result.frame))
      guard baseline.controllerPosition.point.distance(to: result.controllerPosition.point)
        <= policy.controllerPositionToleranceMM else { throw DrawingRunMediaCoverageError.poseMismatch }
      for (mask, exact) in [(input.baselineVisibility, pair.baseline), (input.resultVisibility, pair.post)] {
        guard mask.frame == exact, mask.source == pair.source else {
          throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
        }
        // Revalidate decoded masks rather than trusting synthesized Codable.
        _ = try DrawingRunVisibilityMask(frame: mask.frame, source: mask.source,
          pixels: mask.pixels, basis: mask.basis)
      }
      estimatedEvaluations += frame.width * frame.height * perPixelAlignmentBound * (evidences.isEmpty ? 1 : 2)
      guard estimatedEvaluations <= policy.maximumAlignmentEvaluationCount else {
        throw DrawingRunMediaCoverageError.workBudgetExceeded
      }
      let cross: IntegerFrameAlignment
      if evidences.isEmpty {
        cross = IntegerFrameAlignment(shiftX: 0, shiftY: 0, backgroundMeanAbsoluteDifference: 0,
          estimatorRevision: "reference-frame-identity-v1",
          supportRegion: PixelRect(x: 0, y: 0, width: frame.width, height: frame.height),
          exclusionRegion: region, evaluatedPixelCount: 0)
      } else {
        cross = try await align(reference, frame, region: region, policy: policy)
      }
      let paired = try await align(frame, result.frame, region: region, policy: policy)
      alignmentsEvaluated += cross.evaluatedPixelCount + paired.evaluatedPixelCount
      evidences.append(.init(viewID: input.viewID, frames: pair,
        baselineVisibility: input.baselineVisibility, resultVisibility: input.resultVisibility,
        baselineAlignment: cross, resultAlignment: paired))
    }
    let count = region.width * region.height
    var before = [UInt8](repeating: 0, count: count * 4)
    var after = before
    var sources = [DrawingRunPixelSource?](repeating: nil, count: count)
    var uncovered = [Bool](repeating: true, count: count)
    var evaluations = 0
    for index in 0..<count {
      if index.isMultiple(of: 256) { try Task.checkCancellation(); await Task.yield() }
      let x = region.x + index % region.width, y = region.y + index / region.width
      for (viewIndex, evidence) in evidences.enumerated() {
        evaluations += 1
        let bx = x + evidence.baselineAlignment.shiftX, by = y + evidence.baselineAlignment.shiftY
        let rx = bx + evidence.resultAlignment.shiftX, ry = by + evidence.resultAlignment.shiftY
        guard bx >= 0, by >= 0, rx >= 0, ry >= 0,
          bx < reference.width, rx < reference.width, by < reference.height, ry < reference.height,
          evidence.baselineVisibility.pixels[by * reference.width + bx] == .visible,
          evidence.resultVisibility.pixels[ry * reference.width + rx] == .visible else { continue }
        copyPixel(inputs[viewIndex].baseline.frame, x: bx, y: by, to: &before, offset: index * 4)
        copyPixel(inputs[viewIndex].result.frame, x: rx, y: ry, to: &after, offset: index * 4)
        sources[index] = .init(viewIndex: viewIndex, baselineX: bx, baselineY: by, resultX: rx, resultY: ry)
        uncovered[index] = false
        break
      }
    }
    try Task.checkCancellation()
    return .init(derivationVersion: "exact-registered-visible-pair-selection-v1",
      registration: first.registration, region: region, policy: policy, views: evidences,
      baselineRGBA: Data(before), resultRGBA: Data(after), uncoveredMask: uncovered,
      perPixelSource: sources, alignmentEvaluatedPixelCount: alignmentsEvaluated,
      compositionEvaluationCount: evaluations)
  }

  private static func validPolicy(_ policy: DrawingRunMediaCoveragePolicy) -> Bool {
    (1...3).contains(policy.maximumViewCount)
      && (1...1_000_000).contains(policy.maximumRegionPixelCount)
      && (1...4_194_304).contains(policy.maximumFramePixelCount)
      && (1...500_000_000).contains(policy.maximumAlignmentEvaluationCount)
      && (0...4).contains(policy.alignmentSearchRadiusPixels)
      && (0...policy.alignmentSearchRadiusPixels).contains(policy.maximumAlignmentShiftPixels)
      && policy.maximumBackgroundMeanAbsoluteDifference.isFinite
      && (0...255).contains(policy.maximumBackgroundMeanAbsoluteDifference)
      && policy.controllerPositionToleranceMM.isFinite
      && (0...0.5).contains(policy.controllerPositionToleranceMM)
  }

  private static func align(_ baseline: StampedFrame, _ result: StampedFrame,
    region: PixelRect, policy: DrawingRunMediaCoveragePolicy) async throws -> IntegerFrameAlignment {
    let alignment: IntegerFrameAlignment
    do {
      alignment = try await VisionWorker.boundedSubsampledIntegerAlignment(baseline, result,
        excluding: region, searchRadius: policy.alignmentSearchRadiusPixels,
        baseComputation: .zero, checkpointHandler: nil).alignment
    } catch is CancellationError { throw CancellationError() }
    catch { throw DrawingRunMediaCoverageError.alignmentRefused }
    guard max(abs(alignment.shiftX), abs(alignment.shiftY)) <= policy.maximumAlignmentShiftPixels,
      alignment.backgroundMeanAbsoluteDifference.isFinite,
      alignment.backgroundMeanAbsoluteDifference <= policy.maximumBackgroundMeanAbsoluteDifference,
      alignment.evaluatedPixelCount > 0 else { throw DrawingRunMediaCoverageError.alignmentRefused }
    return alignment
  }

  private static func copyPixel(_ frame: StampedFrame, x: Int, y: Int,
    to output: inout [UInt8], offset: Int) {
    let input = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    switch frame.pixelFormat {
    case .gray8:
      for channel in 0..<3 { output[offset + channel] = frame.bytes[input] }
    case .rgba8:
      for channel in 0..<3 { output[offset + channel] = frame.bytes[input + channel] }
    case .bgra8:
      output[offset] = frame.bytes[input + 2]; output[offset + 1] = frame.bytes[input + 1]
      output[offset + 2] = frame.bytes[input]
    }
    output[offset + 3] = 255
  }
}

extension DrawingRunMediaCoverage {
  /// Structural validation for checksummed durable derivatives. Raw asset
  /// integrity/association is separately checked by the existing store owner.
  public func validate() throws {
    guard Self.validPolicy(policy), derivationVersion == "exact-registered-visible-pair-selection-v1",
      !views.isEmpty, views.count <= policy.maximumViewCount, Set(views.map(\.viewID)).count == views.count,
      region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
      region.width <= policy.maximumRegionPixelCount / region.height,
      alignmentEvaluatedPixelCount >= 0, alignmentEvaluatedPixelCount <= policy.maximumAlignmentEvaluationCount,
      compositionEvaluationCount >= 0 else { throw DrawingRunMediaCoverageError.invalidPolicy }
    let count = region.width * region.height
    guard baselineRGBA.count == count * 4, resultRGBA.count == count * 4,
      uncoveredMask.count == count, perPixelSource.count == count,
      compositionEvaluationCount <= count * views.count else {
      throw DrawingRunMediaCoverageError.invalidRegion
    }
    let optical = registration.applicability.opticalConfiguration
    let reference = views[0].frames.baseline
    guard reference.width > 0, reference.height > 0,
      reference.width <= policy.maximumFramePixelCount / reference.height,
      region.x <= reference.width, region.y <= reference.height,
      region.width <= reference.width-region.x, region.height <= reference.height-region.y else {
      throw DrawingRunMediaCoverageError.invalidRegion
    }
    for view in views {
      guard view.frames.source == optical.source,
        view.frames.baseline.cameraConfigurationID == reference.cameraConfigurationID,
        view.frames.baseline.width == optical.width, view.frames.baseline.height == optical.height,
        view.frames.baseline.pixelFormat == optical.pixelFormat else {
        throw DrawingRunMediaCoverageError.frameMismatch
      }
      for (mask, frame) in [(view.baselineVisibility, view.frames.baseline), (view.resultVisibility, view.frames.post)] {
        guard mask.frame == frame, mask.source == view.frames.source else {
          throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
        }
        _ = try DrawingRunVisibilityMask(frame: frame, source: mask.source, pixels: mask.pixels, basis: mask.basis)
      }
      for alignment in [view.baselineAlignment, view.resultAlignment] {
        guard (-policy.maximumAlignmentShiftPixels...policy.maximumAlignmentShiftPixels).contains(alignment.shiftX),
          (-policy.maximumAlignmentShiftPixels...policy.maximumAlignmentShiftPixels).contains(alignment.shiftY),
          alignment.backgroundMeanAbsoluteDifference.isFinite,
          (0...policy.maximumBackgroundMeanAbsoluteDifference).contains(alignment.backgroundMeanAbsoluteDifference),
          alignment.evaluatedPixelCount >= 0 else { throw DrawingRunMediaCoverageError.alignmentRefused }
      }
    }
    for index in 0..<count {
      guard let source = perPixelSource[index] else {
        guard uncoveredMask[index], (0..<4).allSatisfy({
          baselineRGBA[index * 4 + $0] == 0 && resultRGBA[index * 4 + $0] == 0
        }) else { throw DrawingRunMediaCoverageError.invalidVisibilityEvidence }
        continue
      }
      guard !uncoveredMask[index], views.indices.contains(source.viewIndex),
        baselineRGBA[index * 4 + 3] == 255, resultRGBA[index * 4 + 3] == 255 else {
        throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
      }
      let view = views[source.viewIndex]
      let x = region.x + index % region.width, y = region.y + index / region.width
      guard source.baselineX >= 0, source.baselineX < reference.width,
        source.resultX >= 0, source.resultX < reference.width,
        source.baselineY >= 0, source.baselineY < reference.height,
        source.resultY >= 0, source.resultY < reference.height,
        source.baselineX == x + view.baselineAlignment.shiftX,
        source.baselineY == y + view.baselineAlignment.shiftY,
        source.resultX == source.baselineX + view.resultAlignment.shiftX,
        source.resultY == source.baselineY + view.resultAlignment.shiftY,
        view.baselineVisibility.pixels[source.baselineY * reference.width + source.baselineX] == .visible,
        view.resultVisibility.pixels[source.resultY * reference.width + source.resultX] == .visible else {
        throw DrawingRunMediaCoverageError.invalidVisibilityEvidence
      }
    }
  }

  private enum CodingKeys: String, CodingKey {
    case derivationVersion, registration, region, policy, views, baselineRGBA, resultRGBA
    case uncoveredMask, perPixelSource, alignmentEvaluatedPixelCount, compositionEvaluationCount
  }

  public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(derivationVersion: c.decode(String.self, forKey: .derivationVersion),
      registration: c.decode(TipCameraRegistration.self, forKey: .registration),
      region: c.decode(PixelRect.self, forKey: .region),
      policy: c.decode(DrawingRunMediaCoveragePolicy.self, forKey: .policy),
      views: c.decode([DrawingRunCoverageViewEvidence].self, forKey: .views),
      baselineRGBA: c.decode(Data.self, forKey: .baselineRGBA),
      resultRGBA: c.decode(Data.self, forKey: .resultRGBA),
      uncoveredMask: c.decode([Bool].self, forKey: .uncoveredMask),
      perPixelSource: c.decode([DrawingRunPixelSource?].self, forKey: .perPixelSource),
      alignmentEvaluatedPixelCount: c.decode(Int.self, forKey: .alignmentEvaluatedPixelCount),
      compositionEvaluationCount: c.decode(Int.self, forKey: .compositionEvaluationCount))
    try validate()
  }
}
