import CryptoKit
import Foundation
import PlotterModel

public struct DrawingMaterialApplicability: Codable, Hashable, Sendable {
  public let calibration: TipCalibrationApplicabilityContext
  public let registrationRevisionID: LearningArtifactRevisionID
  public let registrationSHA256: String
  public let paperStock: String
  public let drawingFeedMMPerMinute: Double
  public let penActuationProfile: PenActuationProfile

  public init(registration: TipCameraRegistration, paperStock: String,
    drawingFeedMMPerMinute: Double, penActuationProfile: PenActuationProfile) throws {
    guard !paperStock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      drawingFeedMMPerMinute.isFinite, drawingFeedMMPerMinute > 0,
      (0...1000).contains(penActuationProfile.raisedSpindleValue),
      (0...1000).contains(penActuationProfile.loweredSpindleValue),
      penActuationProfile.settleSeconds.isFinite, penActuationProfile.settleSeconds >= 0 else {
      throw PlotterModelError.invalidValue("Paper stock and drawing feed are required for material applicability")
    }
    calibration = registration.applicability
    registrationRevisionID = registration.acceptedRevisionID
    registrationSHA256 = try Self.registrationHash(registration)
    self.paperStock = paperStock
    self.drawingFeedMMPerMinute = drawingFeedMMPerMinute
    self.penActuationProfile = penActuationProfile
  }

  /// Sorted object keys do not sort a Set's encoded array. Normalize the one
  /// schema-known unordered collection; ordered observation evidence stays ordered.
  public static func registrationHash(_ registration: TipCameraRegistration) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    guard var object = try JSONSerialization.jsonObject(with: encoder.encode(registration)) as? [String: Any] else {
      throw PlotterModelError.invalidValue("Invalid material registration encoding")
    }
    let sessions = try registration.captureSessionIDs.map { try encoder.encode($0) }
      .sorted { $0.lexicographicallyPrecedes($1) }
    object["captureSessionIDs"] = try sessions.map { try JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
    let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

public struct DrawingMaterialVisibilityEvidence: Codable, Hashable, Sendable {
  public let inspectedFrames: [ExactFrameProvenance]
  public let source: FrameSourceIdentity
  public let confirmedAt: Date
  public let method: String

  public init(inspectedFrames: [ExactFrameProvenance], source: FrameSourceIdentity, confirmedAt: Date = Date()) {
    self.inspectedFrames = inspectedFrames; self.source = source; self.confirmedAt = confirmedAt
    method = "operator-confirmed-unobstructed-v1"
  }
}

/// Individual two-edge measurements. Width is perpendicular to the local path
/// after inverse camera geometry; inverse-mapped camera-normal length is not width.
public struct DepositedWidthSample: Codable, Hashable, Sendable {
  public let pathIndex: Int
  public let segmentIndex: Int
  public let pathFraction: Double
  public let directionRadians: Double
  public let firstEdge: Point2<CameraPixelSpace>
  public let secondEdge: Point2<CameraPixelSpace>
  public let widthMM: Double
  public let uncertaintyMM: Double
  public let edgeExtrapolationMM: Double

  public init(pathIndex: Int, segmentIndex: Int, pathFraction: Double, directionRadians: Double,
    firstEdge: Point2<CameraPixelSpace>, secondEdge: Point2<CameraPixelSpace>, widthMM: Double,
    uncertaintyMM: Double, edgeExtrapolationMM: Double = 0) {
    self.pathIndex = pathIndex; self.segmentIndex = segmentIndex; self.pathFraction = pathFraction
    self.directionRadians = directionRadians; self.firstEdge = firstEdge; self.secondEdge = secondEdge
    self.widthMM = widthMM; self.uncertaintyMM = uncertaintyMM; self.edgeExtrapolationMM = edgeExtrapolationMM
  }
}

public enum DrawingMaterialObservationMode: String, Codable, Hashable, Sendable {
  case pairedNewInk, existingInkLocalContrast
}

public struct DrawingMaterialMeasurementPolicy: Codable, Hashable, Sendable {
  public let maximumWidthMM: Double
  public let maximumSamples: Int
  public let minimumLuminanceDecrease: UInt8
  public let maximumEdgeExtrapolationMM: Double
  public init(maximumWidthMM: Double = 6, maximumSamples: Int = 2048,
    minimumLuminanceDecrease: UInt8 = 25, maximumEdgeExtrapolationMM: Double = 2) {
    self.maximumWidthMM = maximumWidthMM; self.maximumSamples = maximumSamples
    self.minimumLuminanceDecrease = minimumLuminanceDecrease
    self.maximumEdgeExtrapolationMM = maximumEdgeExtrapolationMM
  }
}

public struct DrawingMaterialMeasurement: Codable, Hashable, Sendable, Identifiable {
  public let id: UUID
  public let algorithmRevision: String
  public let policy: DrawingMaterialMeasurementPolicy
  public let frames: DrawingObservationFramePair?
  public let registration: TipCameraRegistration
  public let geometry: [Polyline<MachineSpace>]
  public let qualification: MaterialWidthQualification
  public let distribution: DepositedWidthDistribution?
  public let samples: [DepositedWidthSample]
  public let limitations: [String]
  public let recordedAt: Date
  public let alignment: IntegerFrameAlignment?
  public let source: FrameSourceIdentity
  public let singleFrame: ExactFrameProvenance?
  public let observationMode: DrawingMaterialObservationMode
  public let visibilityEvidence: DrawingMaterialVisibilityEvidence?

  public init(id: UUID = UUID(), algorithmRevision: String, frames: DrawingObservationFramePair? = nil,
    registration: TipCameraRegistration, geometry: [Polyline<MachineSpace>],
    qualification: MaterialWidthQualification, distribution: DepositedWidthDistribution?,
    samples: [DepositedWidthSample], limitations: [String], recordedAt: Date = Date(),
    alignment: IntegerFrameAlignment? = nil, source: FrameSourceIdentity,
    singleFrame: ExactFrameProvenance? = nil, observationMode: DrawingMaterialObservationMode = .pairedNewInk,
    visibilityEvidence: DrawingMaterialVisibilityEvidence? = nil,
    policy: DrawingMaterialMeasurementPolicy = DrawingMaterialMeasurementPolicy()) {
    self.id = id; self.algorithmRevision = algorithmRevision; self.frames = frames; self.policy = policy
    self.registration = registration; self.geometry = geometry; self.qualification = qualification
    self.distribution = distribution; self.samples = samples; self.limitations = limitations
    self.recordedAt = recordedAt; self.alignment = alignment
    self.source = source; self.singleFrame = singleFrame; self.observationMode = observationMode
    self.visibilityEvidence = visibilityEvidence
  }
}

public struct DrawingMaterialMeasurementRequest: Sendable {
  public let baseline: SamePoseFrameSample
  public let result: SamePoseFrameSample
  public let registration: TipCameraRegistration
  public let intendedPaths: [Polyline<MachineSpace>]
  /// Row-major result-frame pixels. Nil means occlusion has not been classified.
  public let occlusionMask: [Bool]?
  public let maximumWidthMM: Double
  public let thresholds: InkPixelThresholds
  public let maximumSamples: Int
  public let currentApplicability: TipCalibrationApplicabilityContext?
  public let visibilityEvidence: DrawingMaterialVisibilityEvidence?

  public init(baseline: SamePoseFrameSample, result: SamePoseFrameSample,
    registration: TipCameraRegistration, intendedPaths: [Polyline<MachineSpace>],
    occlusionMask: [Bool]? = nil, maximumWidthMM: Double = 6,
    thresholds: InkPixelThresholds = InkPixelThresholds(minimumLuminanceDecrease: 25),
    maximumSamples: Int = 2048, currentApplicability: TipCalibrationApplicabilityContext? = nil,
    visibilityEvidence: DrawingMaterialVisibilityEvidence? = nil) {
    self.baseline = baseline; self.result = result; self.registration = registration
    self.intendedPaths = intendedPaths; self.occlusionMask = occlusionMask
    self.maximumWidthMM = maximumWidthMM; self.thresholds = thresholds; self.maximumSamples = maximumSamples
    self.currentApplicability = currentApplicability
    self.visibilityEvidence = visibilityEvidence
  }
}

/// Existing marks have no invented pre-image or new-ink attribution. The
/// estimator must establish local paper contrast on both sides of every sample.
public struct DrawingMaterialExistingInkMeasurementRequest: Sendable {
  public let result: SamePoseFrameSample
  public let registration: TipCameraRegistration
  public let intendedPaths: [Polyline<MachineSpace>]
  public let occlusionMask: [Bool]?
  public let maximumWidthMM: Double
  public let thresholds: InkPixelThresholds
  public let maximumSamples: Int
  public let currentApplicability: TipCalibrationApplicabilityContext?
  public let visibilityEvidence: DrawingMaterialVisibilityEvidence?

  public init(result: SamePoseFrameSample, registration: TipCameraRegistration,
    intendedPaths: [Polyline<MachineSpace>], occlusionMask: [Bool]? = nil,
    maximumWidthMM: Double = 6, thresholds: InkPixelThresholds = InkPixelThresholds(minimumLuminanceDecrease: 25),
    maximumSamples: Int = 2048, currentApplicability: TipCalibrationApplicabilityContext? = nil,
    visibilityEvidence: DrawingMaterialVisibilityEvidence? = nil) {
    self.result = result; self.registration = registration; self.intendedPaths = intendedPaths
    self.occlusionMask = occlusionMask; self.maximumWidthMM = maximumWidthMM
    self.thresholds = thresholds; self.maximumSamples = maximumSamples; self.currentApplicability = currentApplicability
    self.visibilityEvidence = visibilityEvidence
  }
}

/// Durable material settings and measurement provenance, independent of all
/// motion authorities. DS-06 supplies the linked raw run-media ownership.
public struct DrawingMaterialRecord: Codable, Hashable, Sendable {
  public let profile: DrawingMaterialProfileRevision
  public let applicability: DrawingMaterialApplicability?
  public let measurement: DrawingMaterialMeasurement?
  public let conditionsOrigin: String?
  public init(profile: DrawingMaterialProfileRevision, applicability: DrawingMaterialApplicability? = nil,
    measurement: DrawingMaterialMeasurement? = nil, conditionsOrigin: String? = nil) throws {
    try profile.validate()
    guard profile.createdAt.timeIntervalSince1970.isFinite,
      profile.measurementEvidenceID == measurement?.id,
      conditionsOrigin == nil || conditionsOrigin == "operator-confirmed-existing-mark-conditions-v1",
      measurement == nil || (applicability != nil && measurement?.qualification == profile.qualification
        && measurement?.distribution == profile.depositedWidth) else {
      throw PlotterModelError.invalidValue("Material measurement does not match its profile")
    }
    if let applicability {
      guard !applicability.paperStock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
        applicability.drawingFeedMMPerMinute.isFinite, applicability.drawingFeedMMPerMinute > 0,
        materialSHA256IsValid(applicability.registrationSHA256),
        (0...1000).contains(applicability.penActuationProfile.raisedSpindleValue),
        (0...1000).contains(applicability.penActuationProfile.loweredSpindleValue),
        applicability.penActuationProfile.settleSeconds.isFinite,
        applicability.penActuationProfile.settleSeconds >= 0 else {
        throw PlotterModelError.invalidValue("Invalid material applicability")
      }
      if let measurement {
        try measurement.validateMaterialEvidence()
        let expected = try DrawingMaterialApplicability(registration: measurement.registration,
          paperStock: applicability.paperStock, drawingFeedMMPerMinute: applicability.drawingFeedMMPerMinute,
          penActuationProfile: applicability.penActuationProfile)
        guard applicability == expected else {
          throw PlotterModelError.invalidValue("Material applicability does not match the measured registration")
        }
      }
    }
    self.profile = profile; self.applicability = applicability; self.measurement = measurement
    self.conditionsOrigin = conditionsOrigin
  }
  public func validate() throws {
    _ = try Self(profile: profile, applicability: applicability, measurement: measurement, conditionsOrigin: conditionsOrigin)
  }

  private enum CodingKeys: String, CodingKey { case profile, applicability, measurement, conditionsOrigin }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(profile: values.decode(DrawingMaterialProfileRevision.self, forKey: .profile),
      applicability: values.decodeIfPresent(DrawingMaterialApplicability.self, forKey: .applicability),
      measurement: values.decodeIfPresent(DrawingMaterialMeasurement.self, forKey: .measurement),
      conditionsOrigin: values.decodeIfPresent(String.self, forKey: .conditionsOrigin))
  }
}

extension DrawingMaterialMeasurement {
  fileprivate func validateMaterialEvidence() throws {
    func require(_ condition: Bool, _ detail: String) throws {
      guard condition else { throw PlotterModelError.invalidValue("Invalid material evidence: \(detail)") }
    }
    try require(!algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && recordedAt.timeIntervalSince1970.isFinite, "algorithm or timestamp")
    try require(policy.maximumWidthMM.isFinite && policy.maximumWidthMM > 0 && policy.maximumWidthMM <= 100
      && (1...8192).contains(policy.maximumSamples) && policy.minimumLuminanceDecrease > 0
      && policy.maximumEdgeExtrapolationMM.isFinite && (0...2).contains(policy.maximumEdgeExtrapolationMM),
      "invalid measurement policy")
    let optical = registration.applicability.opticalConfiguration
    try require(source == optical.source, "source does not match registration")
    let inspectedFrames: [ExactFrameProvenance]
    switch observationMode {
    case .pairedNewInk:
      guard let frames, singleFrame == nil else {
        throw PlotterModelError.invalidValue("Paired material evidence requires exactly one frame pair")
      }
      try Self.validateFrame(frames.baseline); try Self.validateFrame(frames.post)
      _ = try DrawingObservationFramePair(source: frames.source, baseline: frames.baseline, post: frames.post)
      try require(frames.source == source, "pair source mismatch")
      inspectedFrames = [frames.baseline, frames.post]
    case .existingInkLocalContrast:
      guard let singleFrame, frames == nil, alignment == nil else {
        throw PlotterModelError.invalidValue("Existing-ink evidence requires exactly one frame and no pair alignment")
      }
      try Self.validateFrame(singleFrame)
      inspectedFrames = [singleFrame]
    }
    for frame in inspectedFrames {
      try require(frame.width == optical.width && frame.height == optical.height
        && frame.pixelFormat == optical.pixelFormat, "frame optical configuration mismatch")
    }
    let resultFrame = inspectedFrames[inspectedFrames.count - 1]
    if let visibilityEvidence {
      try require(visibilityEvidence.method == "operator-confirmed-unobstructed-v1"
        && visibilityEvidence.source == source
        && visibilityEvidence.confirmedAt.timeIntervalSince1970.isFinite
        && visibilityEvidence.confirmedAt <= recordedAt
        && visibilityEvidence.inspectedFrames == inspectedFrames, "visibility inspection does not bind the exact inputs")
    }
    if let alignment {
      try require(alignment.backgroundMeanAbsoluteDifference.isFinite
        && alignment.backgroundMeanAbsoluteDifference >= 0
        && !alignment.estimatorRevision.isEmpty
        && alignment.evaluatedPixelCount > 0
        // This counter sums all coarse and verified shift candidates; it is
        // not a unique pixel-coverage count. The material policy searches 25
        // shifts and verifies at most three, each bounded by the image area.
        && alignment.evaluatedPixelCount <= resultFrame.width * resultFrame.height * 28
        && alignment.shiftX > -resultFrame.width && alignment.shiftX < resultFrame.width
        && alignment.shiftY > -resultFrame.height && alignment.shiftY < resultFrame.height,
        "invalid alignment")
      for region in [alignment.supportRegion, alignment.exclusionRegion] {
        try require(region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
          && region.width <= resultFrame.width && region.height <= resultFrame.height
          && region.x <= resultFrame.width - region.width
          && region.y <= resultFrame.height - region.height, "invalid alignment region")
      }
    }
    try require(!geometry.isEmpty && geometry.allSatisfy { $0.length.isFinite && $0.length > 0 },
      "geometry is missing or non-finite")
    let uncertainty = registration.uncertainty
    _ = try TipCalibrationUncertainty(affineParameterCovariance: uncertainty.affineParameterCovariance,
      rootMeanSquareResidualPixels: uncertainty.rootMeanSquareResidualPixels,
      maximumResidualPixels: uncertainty.maximumResidualPixels)
    let inverse = try registration.cameraFromMachine.inverted()
    if let distribution {
      _ = try DepositedWidthDistribution(medianMM: distribution.medianMM,
        lowerBoundMM: distribution.lowerBoundMM, upperBoundMM: distribution.upperBoundMM,
        uncertaintyMM: distribution.uncertaintyMM, sampleCount: distribution.sampleCount,
        directional: distribution.directional, exclusions: distribution.exclusions)
      try require(!samples.isEmpty && distribution.sampleCount == samples.count
        && ![.nominal, .unavailable].contains(qualification), "distribution sample count or qualification")
      var directionalCount = 0
      for direction in distribution.directional {
        _ = try DirectionalWidthEstimate(directionRadians: direction.directionRadians,
          medianMM: direction.medianMM, uncertaintyMM: direction.uncertaintyMM, sampleCount: direction.sampleCount)
        try require(direction.sampleCount <= samples.count - directionalCount
          && direction.medianMM >= distribution.lowerBoundMM
          && direction.medianMM <= distribution.upperBoundMM
          && direction.uncertaintyMM <= distribution.uncertaintyMM, "directional distribution mismatch")
        directionalCount += direction.sampleCount
      }
      try require(distribution.directional.isEmpty || directionalCount == samples.count, "directional sample count")
      try require(observationMode != .pairedNewInk || alignment != nil, "measured pair is missing alignment")
      for sample in samples {
        try require(geometry.indices.contains(sample.pathIndex), "sample path index")
        let points = geometry[sample.pathIndex].points
        try require(sample.segmentIndex >= 0 && sample.segmentIndex < points.count - 1, "sample segment index")
        try require(sample.pathFraction.isFinite && sample.pathFraction > 0 && sample.pathFraction < 1
          && sample.directionRadians.isFinite && sample.widthMM.isFinite && sample.widthMM > 0
          && sample.uncertaintyMM.isFinite && sample.uncertaintyMM >= 0
          && sample.widthMM >= distribution.lowerBoundMM && sample.widthMM <= distribution.upperBoundMM
          && sample.uncertaintyMM <= distribution.uncertaintyMM, "sample values or distribution bounds")
        for edge in [sample.firstEdge, sample.secondEdge] {
          try require(edge.x.isFinite && edge.y.isFinite && edge.x >= 0 && edge.y >= 0
            && edge.x <= Double(resultFrame.width) && edge.y <= Double(resultFrame.height), "edge outside frame")
        }
        let a = points[sample.segmentIndex], b = points[sample.segmentIndex + 1]
        let length = a.distance(to: b)
        try require(length.isFinite && length > 0, "sample references a degenerate segment")
        let dx = (b.x - a.x) / length, dy = (b.y - a.y) / length
        try require(abs(sin(sample.directionRadians) * dx - cos(sample.directionRadians) * dy) <= 1e-7,
          "sample direction does not match its path")
        let shiftX = Double(alignment?.shiftX ?? 0), shiftY = Double(alignment?.shiftY ?? 0)
        let first = try inverse.applying(to: Point2<CameraPixelSpace>(x: sample.firstEdge.x - shiftX, y: sample.firstEdge.y - shiftY))
        let second = try inverse.applying(to: Point2<CameraPixelSpace>(x: sample.secondEdge.x - shiftX, y: sample.secondEdge.y - shiftY))
        let center = try Point2<MachineSpace>(x: a.x + (b.x - a.x) * sample.pathFraction,
          y: a.y + (b.y - a.y) * sample.pathFraction)
        let domain = registration.applicabilityRectangle
        let extrapolation = max(Self.edgeExtrapolation(first, domain: domain), Self.edgeExtrapolation(second, domain: domain))
        try require(DrawingRegionContainmentPolicy.contains(center, in: domain)
          && sample.edgeExtrapolationMM.isFinite && sample.edgeExtrapolationMM >= 0
          && abs(sample.edgeExtrapolationMM-extrapolation) < 1e-7
          && extrapolation <= policy.maximumEdgeExtrapolationMM
          && (extrapolation <= 1e-9 || qualification == .bounded), "invalid conditional edge extrapolation")
        let cameraCenter = try registration.cameraFromMachine.applying(to: center)
        let cameraDX = registration.cameraFromMachine.m11 * dx + registration.cameraFromMachine.m12 * dy
        let cameraDY = registration.cameraFromMachine.m21 * dx + registration.cameraFromMachine.m22 * dy
        let cameraLength = hypot(cameraDX, cameraDY)
        let midpointX = (sample.firstEdge.x + sample.secondEdge.x) * 0.5 - shiftX
        let midpointY = (sample.firstEdge.y + sample.secondEdge.y) * 0.5 - shiftY
        let alongPathResidual = ((midpointX - cameraCenter.x) * cameraDX
          + (midpointY - cameraCenter.y) * cameraDY) / cameraLength
        try require(alongPathResidual.isFinite && abs(alongPathResidual) <= 1e-6,
          "sample edges do not correspond to the retained path fraction")
        let width = abs(-(second.x - first.x) * dy + (second.y - first.y) * dx)
        try require(width.isFinite && abs(width - sample.widthMM) <= max(1e-8, width * 1e-7),
          "sample width does not match inverse-mapped perpendicular edges")
      }
    } else {
      try require(samples.isEmpty && qualification == .unavailable, "missing distribution for measured samples")
    }
  }

  static func edgeExtrapolation(_ point: Point2<MachineSpace>, domain: AxisAlignedBounds<MachineSpace>) -> Double {
    hypot(max(domain.minX-point.x, 0, point.x-domain.maxX), max(domain.minY-point.y, 0, point.y-domain.maxY))
  }

  fileprivate static func validateFrame(_ frame: ExactFrameProvenance) throws {
    let bpp = frame.pixelFormat.bytesPerPixel
    guard materialSHA256IsValid(frame.frameSHA256), frame.width > 0, frame.height > 0,
      frame.width <= Int.max / bpp, frame.rowBytes >= frame.width * bpp,
      frame.rowBytes <= Int.max / frame.height else {
      throw PlotterModelError.invalidValue("Invalid exact material frame provenance")
    }
  }

  private enum CodingKeys: String, CodingKey {
    case id, algorithmRevision, frames, registration, geometry, qualification, distribution, samples,
      limitations, recordedAt, alignment, source, singleFrame, observationMode, visibilityEvidence, policy
  }
  /// Decode raw frame metadata before the pair initializer's dimension arithmetic.
  private struct FramePairFields: Decodable {
    let source: FrameSourceIdentity
    let baseline: ExactFrameProvenance
    let post: ExactFrameProvenance
  }
  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let rawPair = try values.decodeIfPresent(FramePairFields.self, forKey: .frames)
    let pair = try rawPair.map { raw in
      try Self.validateFrame(raw.baseline); try Self.validateFrame(raw.post)
      return try DrawingObservationFramePair(source: raw.source, baseline: raw.baseline, post: raw.post)
    }
    self.init(id: try values.decode(UUID.self, forKey: .id),
      algorithmRevision: try values.decode(String.self, forKey: .algorithmRevision), frames: pair,
      registration: try values.decode(TipCameraRegistration.self, forKey: .registration),
      geometry: try values.decode([Polyline<MachineSpace>].self, forKey: .geometry),
      qualification: try values.decode(MaterialWidthQualification.self, forKey: .qualification),
      distribution: try values.decodeIfPresent(DepositedWidthDistribution.self, forKey: .distribution),
      samples: try values.decode([DepositedWidthSample].self, forKey: .samples),
      limitations: try values.decode([String].self, forKey: .limitations),
      recordedAt: try values.decode(Date.self, forKey: .recordedAt),
      alignment: try values.decodeIfPresent(IntegerFrameAlignment.self, forKey: .alignment),
      source: try values.decode(FrameSourceIdentity.self, forKey: .source),
      singleFrame: try values.decodeIfPresent(ExactFrameProvenance.self, forKey: .singleFrame),
      observationMode: try values.decode(DrawingMaterialObservationMode.self, forKey: .observationMode),
      visibilityEvidence: try values.decodeIfPresent(DrawingMaterialVisibilityEvidence.self, forKey: .visibilityEvidence),
      policy: try values.decode(DrawingMaterialMeasurementPolicy.self, forKey: .policy))
    try validateMaterialEvidence()
  }
}

private func materialSHA256IsValid(_ value: String) -> Bool {
  value.utf8.count == 64 && value.utf8.allSatisfy {
    (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
  }
}
