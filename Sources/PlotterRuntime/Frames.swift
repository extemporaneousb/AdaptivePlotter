import Foundation
import PlotterModel

public struct FrameID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public init(_ uuid: UUID = UUID()) { rawValue = uuid.uuidString.lowercased() }
}

public struct CameraDeviceID: RawRepresentable, Codable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }
}

public struct CameraDevice: Identifiable, Codable, Hashable, Sendable {
  public let id: CameraDeviceID
  public let name: String

  public init(id: CameraDeviceID, name: String) {
    self.id = id
    self.name = name
  }
}

public enum FramePixelFormat: String, Codable, Hashable, Sendable {
  case gray8
  case rgba8
  case bgra8

  public var bytesPerPixel: Int {
    switch self {
    case .gray8: 1
    case .rgba8, .bgra8: 4
    }
  }
}

public struct OwnedFrameBytes: Codable, Hashable, Sendable {
  private let storage: Data

  public init(copying source: Data) {
    storage = source.withUnsafeBytes { bytes in
      guard let base = bytes.baseAddress, !bytes.isEmpty else { return Data() }
      return Data(bytes: base, count: bytes.count)
    }
  }

  public init(_ bytes: [UInt8]) {
    storage = Data(bytes)
  }

  public var data: Data { storage }
  public var count: Int { storage.count }
  public subscript(index: Int) -> UInt8 { storage[index] }
}

public enum FrameError: Error, Equatable, Sendable {
  case invalidDimensions
  case invalidRowBytes(expectedMinimum: Int, actual: Int)
  case insufficientBytes(expected: Int, actual: Int)
  case contentHashMismatch
  case invalidRegion
  case unsupportedPixelFormat
  case invalidStabilityPolicy
}

public struct StampedFrame: Codable, Hashable, Sendable {
  public let id: FrameID
  public let sequence: UInt64
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let pixelFormat: FramePixelFormat
  public let bytes: OwnedFrameBytes
  public let contentSHA256: String

  public init(
    id: FrameID = FrameID(),
    sequence: UInt64,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    width: Int,
    height: Int,
    rowBytes: Int,
    pixelFormat: FramePixelFormat,
    bytes: OwnedFrameBytes
  ) throws {
    guard width > 0, height > 0 else { throw FrameError.invalidDimensions }
    let minimumRowBytes = width * pixelFormat.bytesPerPixel
    guard rowBytes >= minimumRowBytes else {
      throw FrameError.invalidRowBytes(expectedMinimum: minimumRowBytes, actual: rowBytes)
    }
    let expectedBytes = rowBytes * height
    guard bytes.count >= expectedBytes else {
      throw FrameError.insufficientBytes(expected: expectedBytes, actual: bytes.count)
    }
    self.id = id
    self.sequence = sequence
    self.captureNanoseconds = captureNanoseconds
    self.cameraConfigurationID = cameraConfigurationID
    self.width = width
    self.height = height
    self.rowBytes = rowBytes
    self.pixelFormat = pixelFormat
    self.bytes = bytes
    contentSHA256 = RunLedger.sha256Hex(bytes.data)
  }

  private enum CodingKeys: String, CodingKey {
    case id, sequence, captureNanoseconds, cameraConfigurationID
    case width, height, rowBytes, pixelFormat, bytes, contentSHA256
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let expectedHash = try values.decode(String.self, forKey: .contentSHA256)
    try self.init(
      id: values.decode(FrameID.self, forKey: .id),
      sequence: values.decode(UInt64.self, forKey: .sequence),
      captureNanoseconds: values.decode(UInt64.self, forKey: .captureNanoseconds),
      cameraConfigurationID: values.decode(
        CameraConfigurationID.self, forKey: .cameraConfigurationID),
      width: values.decode(Int.self, forKey: .width),
      height: values.decode(Int.self, forKey: .height),
      rowBytes: values.decode(Int.self, forKey: .rowBytes),
      pixelFormat: values.decode(FramePixelFormat.self, forKey: .pixelFormat),
      bytes: values.decode(OwnedFrameBytes.self, forKey: .bytes)
    )
    guard contentSHA256 == expectedHash else { throw FrameError.contentHashMismatch }
  }
}

/// Identifies whether displayed pixels came from a physical camera or the local
/// deterministic simulator. Simulated pixels never represent camera evidence.
public enum FrameSourceIdentity: Codable, Hashable, Sendable {
  case live(CameraDeviceID)
  case simulated
}

/// The single image contract consumed by preview and vision code.
public struct DisplayedFrame: Codable, Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let frame: StampedFrame

  public init(source: FrameSourceIdentity, frame: StampedFrame) {
    self.source = source
    self.frame = frame
  }
}

/// Geometry is expressed in canonical camera pixels: origin at the top-left,
/// +X right, +Y down. Preview-space coordinates are deliberately absent.
public enum CameraPixelGeometry: Codable, Hashable, Sendable {
  case point(Point2<CameraPixelSpace>)
  case bounds(AxisAlignedBounds<CameraPixelSpace>)
  case polyline(Polyline<CameraPixelSpace>)
}

public struct CameraMeasurementProvenance: Codable, Hashable, Sendable {
  public let operation: String
  public let algorithmRevision: String

  public init(operation: String, algorithmRevision: String) {
    self.operation = operation
    self.algorithmRevision = algorithmRevision
  }
}

/// A measurement may be drawn only over the exact pixels from which it was
/// derived. Matching both identities rejects overlays across camera
/// reconfiguration.
public struct CameraOverlayMeasurement: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let cameraConfigurationID: CameraConfigurationID
  public let geometry: CameraPixelGeometry
  public let provenance: CameraMeasurementProvenance

  public init(
    frameID: FrameID,
    cameraConfigurationID: CameraConfigurationID,
    geometry: CameraPixelGeometry,
    provenance: CameraMeasurementProvenance
  ) {
    self.frameID = frameID
    self.cameraConfigurationID = cameraConfigurationID
    self.geometry = geometry
    self.provenance = provenance
  }

  public func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    frameID == displayedFrame.frame.id
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
  }
}

public struct FrameStabilityPolicy: Codable, Hashable, Sendable {
  public let maximumMeanAbsoluteByteDelta: Double
  public let algorithmRevision: String

  public init(
    maximumMeanAbsoluteByteDelta: Double,
    algorithmRevision: String
  ) throws {
    guard maximumMeanAbsoluteByteDelta.isFinite,
      maximumMeanAbsoluteByteDelta >= 0,
      !algorithmRevision.isEmpty
    else { throw FrameError.invalidStabilityPolicy }
    self.maximumMeanAbsoluteByteDelta = maximumMeanAbsoluteByteDelta
    self.algorithmRevision = algorithmRevision
  }

  private enum CodingKeys: String, CodingKey {
    case maximumMeanAbsoluteByteDelta, algorithmRevision
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      maximumMeanAbsoluteByteDelta: values.decode(
        Double.self,
        forKey: .maximumMeanAbsoluteByteDelta
      ),
      algorithmRevision: values.decode(String.self, forKey: .algorithmRevision)
    )
  }
}

public enum StableFrameBlocker: Codable, Hashable, Sendable {
  case noFreshFrame(newerThanNanoseconds: UInt64)
  case insufficientFreshFrames(required: Int, actual: Int)
  case cameraConfigurationChanged
  case incompatibleFrameGeometry
  case nonMonotonicSequence(previous: UInt64, next: UInt64)
  case nonMonotonicTimestamp(previous: UInt64, next: UInt64)
  case windowTooWide(actualNanoseconds: UInt64, maximumNanoseconds: UInt64)
  case unstable(actualMeanAbsoluteByteDelta: Double, maximum: Double)
}

public enum StableFrameSelection: Sendable, Equatable {
  case selected(frame: StampedFrame, supportingFrameIDs: [FrameID], maximumObservedDelta: Double)
  case blocked(StableFrameBlocker)
}

public enum StableFrameSelector {
  public static func select(
    from frames: [StampedFrame],
    requirement: StableFrameRequirement,
    policy: FrameStabilityPolicy
  ) -> StableFrameSelection {
    for (previous, next) in zip(frames, frames.dropFirst()) {
      guard next.sequence > previous.sequence else {
        return .blocked(.nonMonotonicSequence(previous: previous.sequence, next: next.sequence))
      }
      guard next.captureNanoseconds > previous.captureNanoseconds else {
        return .blocked(
          .nonMonotonicTimestamp(
            previous: previous.captureNanoseconds,
            next: next.captureNanoseconds
          )
        )
      }
    }
    let fresh =
      frames
      .filter { $0.captureNanoseconds > requirement.newerThanMonotonicNanoseconds }
    guard !fresh.isEmpty else {
      return .blocked(
        .noFreshFrame(newerThanNanoseconds: requirement.newerThanMonotonicNanoseconds))
    }
    let requiredCount = Int(requirement.minimumFrameCount)
    guard fresh.count >= requiredCount else {
      return .blocked(.insufficientFreshFrames(required: requiredCount, actual: fresh.count))
    }
    let window = Array(fresh.suffix(requiredCount))
    guard Set(window.map(\.cameraConfigurationID)).count == 1 else {
      return .blocked(.cameraConfigurationChanged)
    }
    guard let reference = window.first, let selected = window.last else {
      return .blocked(.insufficientFreshFrames(required: requiredCount, actual: window.count))
    }
    guard
      window.allSatisfy({
        $0.width == reference.width && $0.height == reference.height
          && $0.rowBytes == reference.rowBytes && $0.pixelFormat == reference.pixelFormat
      })
    else {
      return .blocked(.incompatibleFrameGeometry)
    }
    let span = selected.captureNanoseconds - reference.captureNanoseconds
    guard span <= requirement.maximumSpanNanoseconds else {
      return .blocked(
        .windowTooWide(
          actualNanoseconds: span,
          maximumNanoseconds: requirement.maximumSpanNanoseconds
        ))
    }
    var maximumDelta = 0.0
    for pair in zip(window, window.dropFirst()) {
      maximumDelta = max(maximumDelta, meanAbsoluteDelta(pair.0.bytes, pair.1.bytes))
    }
    guard maximumDelta <= policy.maximumMeanAbsoluteByteDelta else {
      return .blocked(
        .unstable(
          actualMeanAbsoluteByteDelta: maximumDelta,
          maximum: policy.maximumMeanAbsoluteByteDelta
        ))
    }
    return .selected(
      frame: selected,
      supportingFrameIDs: window.map(\.id),
      maximumObservedDelta: maximumDelta
    )
  }

  private static func meanAbsoluteDelta(_ lhs: OwnedFrameBytes, _ rhs: OwnedFrameBytes) -> Double {
    guard lhs.count == rhs.count, lhs.count > 0 else { return .infinity }
    var sum: UInt64 = 0
    for index in 0..<lhs.count {
      sum += UInt64(abs(Int(lhs[index]) - Int(rhs[index])))
    }
    return Double(sum) / Double(lhs.count)
  }
}

public struct RecordedFrameSource: Sendable {
  private let recordedFrames: [StampedFrame]

  public init(frames: [StampedFrame]) {
    recordedFrames = frames
  }

  public func frames(newerThanNanoseconds: UInt64) -> [StampedFrame] {
    recordedFrames.filter { $0.captureNanoseconds > newerThanNanoseconds }
  }

  public func stableFrame(
    requirement: StableFrameRequirement,
    policy: FrameStabilityPolicy
  ) -> StableFrameSelection {
    StableFrameSelector.select(from: recordedFrames, requirement: requirement, policy: policy)
  }
}
