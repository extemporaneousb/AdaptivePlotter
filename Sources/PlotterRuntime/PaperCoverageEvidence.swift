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
  case operatorAccepted
}

public enum PaperCoverageObservationError: Error, Equatable, Sendable {
  case invalidPolygon
  case pointOutsideFrame
  case invalidTimestamp
  case emptyAlgorithmRevision
}

/// Exact-frame evidence that a particular replaceable sheet covers a camera
/// polygon. This is paper evidence only: it does not replace or widen machine
/// Boundary authority, tip-map applicability, or their safety margins.
public struct PaperCoverageObservation: Codable, Hashable, Sendable {
  public let id: PaperCoverageObservationID
  public let paper: PaperRevisionContext
  public let source: FrameSourceIdentity
  public let frame: ExactFrameProvenance
  public let polygon: [Point2<CameraPixelSpace>]
  public let method: PaperCoverageObservationMethod
  public let observedAt: RuntimeTimestamp
  public let algorithmRevision: String

  public init(
    id: PaperCoverageObservationID = PaperCoverageObservationID(),
    paper: PaperRevisionContext,
    source: FrameSourceIdentity,
    frame: ExactFrameProvenance,
    polygon: [Point2<CameraPixelSpace>],
    method: PaperCoverageObservationMethod,
    observedAt: RuntimeTimestamp,
    algorithmRevision: String
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
  }

  private enum CodingKeys: String, CodingKey {
    case id, paper, source, frame, polygon, method, observedAt, algorithmRevision
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
      algorithmRevision: values.decode(String.self, forKey: .algorithmRevision)
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

  public init(
    paper: PaperRevisionContext,
    source: FrameSourceIdentity,
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID
  ) {
    self.paper = paper
    self.source = source
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
  }
}

public enum PaperCoverageValidationRejection: String, Codable, Hashable, Sendable {
  case paperInstanceMismatch
  case paperContactPlaneMismatch
  case sourceMismatch
  case frameMismatch
  case cameraConfigurationMismatch
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
    if frame.cameraConfigurationID != context.cameraConfigurationID {
      rejections.append(.cameraConfigurationMismatch)
    }
    return rejections.isEmpty ? .valid : .rejected(rejections)
  }
}
