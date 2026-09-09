import Foundation
import PlotterModel

public struct PaperCoverageObservationID: Codable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

public enum PaperCoverageObservationMethod: String, Codable, Hashable, Sendable {
  case visionMeasured
  /// The operator, not the polygon's projection source, supplies the paper-
  /// coverage authority. The displayed polygon may be a diagnostic affine
  /// projection and never becomes tip-map or camera/ink evidence.
  case operatorAccepted
}

public enum PaperCoverageObservationError: Error, Equatable, Sendable {
  case invalidPolygon
  case pointOutsideFrame
  case invalidTimestamp
  case emptyAlgorithmRevision
}

/// An exact-frame assertion that a particular replaceable sheet covers the
/// displayed camera polygon. With `operatorAccepted`, the polygon is the
/// proposition the operator accepts; its diagnostic projection supplies no
/// tip-map or camera/ink evidence authority. This is paper evidence only: it
/// does not replace or widen machine Boundary authority, tip-map applicability,
/// or their safety margins.
public struct PaperCoverageObservation: Codable, Hashable, Sendable {
  public let id: PaperCoverageObservationID
  public let paper: PaperRevisionContext
  public let source: FrameSourceIdentity
  public let frame: ExactFrameProvenance
  public let polygon: [Point2<CameraPixelSpace>]
  public let method: PaperCoverageObservationMethod
  public let observedAt: RuntimeTimestamp
  public let algorithmRevision: String
  public let opticalConfiguration: CameraOpticalConfigurationIdentity?
  public let drawableRegion: DrawableMachineRegion?

  public init(
    id: PaperCoverageObservationID = PaperCoverageObservationID(),
    paper: PaperRevisionContext,
    source: FrameSourceIdentity,
    frame: ExactFrameProvenance,
    polygon: [Point2<CameraPixelSpace>],
    method: PaperCoverageObservationMethod,
    observedAt: RuntimeTimestamp,
    algorithmRevision: String,
    opticalConfiguration: CameraOpticalConfigurationIdentity? = nil,
    drawableRegion: DrawableMachineRegion? = nil
  ) throws {
    guard Self.isSHA256(frame.frameSHA256), frame.width > 0, frame.height > 0,
      frame.rowBytes >= frame.width * frame.pixelFormat.bytesPerPixel,
      polygon.count >= 3, Set(polygon).count >= 3, Self.twiceArea(of: polygon) > 0
    else {
      throw PaperCoverageObservationError.invalidPolygon
    }
    guard polygon.allSatisfy({
      $0.x >= 0 && $0.x < Double(frame.width)
        && $0.y >= 0 && $0.y < Double(frame.height)
    }) else { throw PaperCoverageObservationError.pointOutsideFrame }
    guard frame.captureNanoseconds <= observedAt.monotonicNanoseconds else {
      throw PaperCoverageObservationError.invalidTimestamp
    }
    guard !algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw PaperCoverageObservationError.emptyAlgorithmRevision
    }
    self.id = id
    self.paper = paper
    self.source = source
    self.frame = frame
    self.polygon = polygon
    self.method = method
    self.observedAt = observedAt
    self.algorithmRevision = algorithmRevision
    self.opticalConfiguration = opticalConfiguration
    self.drawableRegion = drawableRegion
  }

  private enum CodingKeys: String, CodingKey {
    case id, paper, source, frame, polygon, method, observedAt, algorithmRevision
    case opticalConfiguration, drawableRegion
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(PaperCoverageObservationID.self, forKey: .id),
      paper: values.decode(PaperRevisionContext.self, forKey: .paper),
      source: values.decode(FrameSourceIdentity.self, forKey: .source),
      frame: values.decode(ExactFrameProvenance.self, forKey: .frame),
      polygon: values.decode([Point2<CameraPixelSpace>].self, forKey: .polygon),
      method: values.decode(PaperCoverageObservationMethod.self, forKey: .method),
      observedAt: values.decode(RuntimeTimestamp.self, forKey: .observedAt),
      algorithmRevision: values.decode(String.self, forKey: .algorithmRevision),
      opticalConfiguration: values.decodeIfPresent(CameraOpticalConfigurationIdentity.self, forKey: .opticalConfiguration),
      drawableRegion: values.decodeIfPresent(DrawableMachineRegion.self, forKey: .drawableRegion)
    )
  }

  private static func twiceArea(of polygon: [Point2<CameraPixelSpace>]) -> Double {
    abs(zip(polygon, polygon.dropFirst() + [polygon[0]]).reduce(0) { result, edge in
      result + edge.0.x * edge.1.y - edge.1.x * edge.0.y
    })
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.count == 64 && value.allSatisfy(\.isHexDigit)
  }
}

/// Current exact-frame identities against which paper coverage may be used.
/// Freshness policy remains with the workflow owner; this value only checks
/// identity/provenance compatibility.
public struct PaperCoverageValidationContext: Codable, Hashable, Sendable {
  public let paper: PaperRevisionContext
  public let source: FrameSourceIdentity
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID
  public let opticalConfiguration: CameraOpticalConfigurationIdentity?
  public let drawableRegion: DrawableMachineRegion?

  public init(
    paper: PaperRevisionContext,
    source: FrameSourceIdentity,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    opticalConfiguration: CameraOpticalConfigurationIdentity? = nil,
    drawableRegion: DrawableMachineRegion? = nil
  ) {
    self.paper = paper
    self.source = source
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
    self.opticalConfiguration = opticalConfiguration
    self.drawableRegion = drawableRegion
  }
}

public enum PaperCoverageValidationRejection: String, Codable, Hashable, Sendable {
  case paperInstanceMismatch
  case paperContactPlaneMismatch
  case sourceMismatch
  case frameMismatch
  case cameraConfigurationMismatch
  case opticalConfigurationMismatch
  case drawingRegionMismatch
}

public enum PaperCoverageValidationResult: Codable, Hashable, Sendable {
  case valid
  case rejected([PaperCoverageValidationRejection])
}

extension PaperCoverageObservation {
  public func validation(
    against context: PaperCoverageValidationContext
  ) -> PaperCoverageValidationResult {
    var rejections: [PaperCoverageValidationRejection] = []
    if paper.instance != context.paper.instance { rejections.append(.paperInstanceMismatch) }
    if paper.contactPlane != context.paper.contactPlane {
      rejections.append(.paperContactPlaneMismatch)
    }
    if source != context.source { rejections.append(.sourceMismatch) }
    if frame.frameID != context.frameID { rejections.append(.frameMismatch) }
    if let opticalConfiguration, let current = context.opticalConfiguration {
      if opticalConfiguration != current { rejections.append(.opticalConfigurationMismatch) }
    } else if frame.cameraConfigurationID != context.cameraConfigurationID {
      rejections.append(.cameraConfigurationMismatch)
    }
    if let drawableRegion, drawableRegion != context.drawableRegion {
      rejections.append(.drawingRegionMismatch)
    }
    return rejections.isEmpty ? .valid : .rejected(rejections)
  }
}
