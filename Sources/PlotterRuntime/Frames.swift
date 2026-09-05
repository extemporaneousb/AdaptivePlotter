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

  init(copying source: UnsafeRawBufferPointer) {
    guard let base = source.baseAddress, !source.isEmpty else {
      storage = Data()
      return
    }
    storage = Data(bytes: base, count: source.count)
  }

  public var data: Data { storage }
  public var count: Int { storage.count }
  public subscript(index: Int) -> UInt8 { storage[index] }

  public func withUnsafeBytes<Result>(
    _ body: (UnsafeRawBufferPointer) throws -> Result
  ) rethrows -> Result {
    try storage.withUnsafeBytes(body)
  }
}

public enum FrameError: Error, Equatable, Sendable {
  case invalidDimensions
  case invalidRowBytes(expectedMinimum: Int, actual: Int)
  case insufficientBytes(expected: Int, actual: Int)
  case contentHashMismatch
  case invalidRegion
  case unsupportedPixelFormat
  case invalidVisionPolicy
}

/// Bounds both ordinary preview materialization and, when supported by the
/// physical camera, upstream frame delivery. Exact snapshot and measurement
/// requests may still materialize the newest delivered pixels immediately.
public struct LiveFrameMaterializationPolicy: Codable, Hashable, Sendable {
  public static let everyFrame = LiveFrameMaterializationPolicy(
    minimumPreviewIntervalNanoseconds: 0
  )
  public static let interactivePreview = LiveFrameMaterializationPolicy(
    minimumPreviewIntervalNanoseconds: 100_000_000
  )

  public let minimumPreviewIntervalNanoseconds: UInt64

  public init(minimumPreviewIntervalNanoseconds: UInt64) {
    self.minimumPreviewIntervalNanoseconds = minimumPreviewIntervalNanoseconds
  }

  public var maximumPreviewFramesPerSecond: Double? {
    guard minimumPreviewIntervalNanoseconds > 0 else { return nil }
    return 1_000_000_000 / Double(minimumPreviewIntervalNanoseconds)
  }
}

/// The boundary that deliberately seals immutable frame pixels with SHA-256.
/// A preview may remain unsealed; reading its evidence identity never performs
/// hidden work.
public enum FrameContentHashPurpose: String, Codable, Hashable, Sendable {
  case analysis
  case exactEvidence
  case serialization
}

public struct FrameContentHashMetricsSnapshot: Codable, Hashable, Sendable {
  public let analysisComputationCount: UInt64
  public let exactEvidenceComputationCount: UInt64
  public let serializationComputationCount: UInt64

  public var totalComputationCount: UInt64 {
    analysisComputationCount + exactEvidenceComputationCount
      + serializationComputationCount
  }
}

/// Shared, thread-safe accounting for the actual SHA-256 computation path.
/// CameraCapture injects one instance into its frames so downstream analysis
/// is visible in capture diagnostics without adding a second state owner.
public final class FrameContentHashMetrics: @unchecked Sendable {
  private struct State {
    var analysisComputationCount: UInt64 = 0
    var exactEvidenceComputationCount: UInt64 = 0
    var serializationComputationCount: UInt64 = 0
  }

  private let lock = NSLock()
  private var state = State()

  public init() {}

  public var snapshot: FrameContentHashMetricsSnapshot {
    lock.withLock {
      FrameContentHashMetricsSnapshot(
        analysisComputationCount: state.analysisComputationCount,
        exactEvidenceComputationCount: state.exactEvidenceComputationCount,
        serializationComputationCount: state.serializationComputationCount
      )
    }
  }

  fileprivate func record(_ purpose: FrameContentHashPurpose) {
    lock.withLock {
      switch purpose {
      case .analysis:
        state.analysisComputationCount &+= 1
      case .exactEvidence:
        state.exactEvidenceComputationCount &+= 1
      case .serialization:
        state.serializationComputationCount &+= 1
      }
    }
  }
}

private final class FrameContentDigest: @unchecked Sendable {
  private let lock = NSLock()
  private let metrics: FrameContentHashMetrics?
  private var digest: String?
  private var computationPurpose: FrameContentHashPurpose?

  init(digest: String? = nil, metrics: FrameContentHashMetrics?) {
    self.digest = digest
    self.metrics = metrics
  }

  var materializedDigest: String? {
    lock.withLock { digest }
  }

  var materializationPurpose: FrameContentHashPurpose? {
    lock.withLock { computationPurpose }
  }

  func materialize(bytes: OwnedFrameBytes, purpose: FrameContentHashPurpose) -> String {
    lock.withLock {
      if let digest { return digest }
      let computed = RunLedger.sha256Hex(bytes.data)
      digest = computed
      computationPurpose = purpose
      metrics?.record(purpose)
      return computed
    }
  }
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
  private let contentDigest: FrameContentDigest

  /// Returns only an already materialized evidence identity. Analysis, exact
  /// evidence, and serialization must first name their explicit boundary with
  /// `materializingContentHash(for:)`.
  public var contentSHA256: String {
    guard let digest = contentDigest.materializedDigest else {
      preconditionFailure(
        "Unsealed preview frame has no content SHA-256; materialize it at an analysis or evidence boundary first."
      )
    }
    return digest
  }

  public var materializedContentSHA256: String? {
    contentDigest.materializedDigest
  }

  public var contentHashIsMaterialized: Bool {
    contentDigest.materializedDigest != nil
  }

  public var contentHashMaterializationPurpose: FrameContentHashPurpose? {
    contentDigest.materializationPurpose
  }

  public init(
    id: FrameID = FrameID(),
    sequence: UInt64,
    captureNanoseconds: UInt64,
    cameraConfigurationID: CameraConfigurationID,
    width: Int,
    height: Int,
    rowBytes: Int,
    pixelFormat: FramePixelFormat,
    bytes: OwnedFrameBytes,
    eagerlyMaterializeContentHash: Bool = true,
    contentHashMetrics: FrameContentHashMetrics? = nil,
    contentHashPurpose: FrameContentHashPurpose = .exactEvidence
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
    contentDigest = FrameContentDigest(metrics: contentHashMetrics)
    if eagerlyMaterializeContentHash {
      _ = contentDigest.materialize(bytes: bytes, purpose: contentHashPurpose)
    }
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

  public func materializingContentHash(
    for purpose: FrameContentHashPurpose
  ) -> StampedFrame {
    _ = contentDigest.materialize(bytes: bytes, purpose: purpose)
    return self
  }

  public func materializingEvidenceContentHash() -> StampedFrame {
    materializingContentHash(for: .exactEvidence)
  }

  public func encode(to encoder: any Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(id, forKey: .id)
    try values.encode(sequence, forKey: .sequence)
    try values.encode(captureNanoseconds, forKey: .captureNanoseconds)
    try values.encode(cameraConfigurationID, forKey: .cameraConfigurationID)
    try values.encode(width, forKey: .width)
    try values.encode(height, forKey: .height)
    try values.encode(rowBytes, forKey: .rowBytes)
    try values.encode(pixelFormat, forKey: .pixelFormat)
    try values.encode(bytes, forKey: .bytes)
    let sealed = materializingContentHash(for: .serialization)
    try values.encode(sealed.contentSHA256, forKey: .contentSHA256)
  }

  public static func == (lhs: StampedFrame, rhs: StampedFrame) -> Bool {
    lhs.id == rhs.id
      && lhs.sequence == rhs.sequence
      && lhs.captureNanoseconds == rhs.captureNanoseconds
      && lhs.cameraConfigurationID == rhs.cameraConfigurationID
      && lhs.width == rhs.width
      && lhs.height == rhs.height
      && lhs.rowBytes == rhs.rowBytes
      && lhs.pixelFormat == rhs.pixelFormat
      && lhs.bytes == rhs.bytes
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(sequence)
    hasher.combine(captureNanoseconds)
    hasher.combine(cameraConfigurationID)
    hasher.combine(width)
    hasher.combine(height)
    hasher.combine(rowBytes)
    hasher.combine(pixelFormat)
    hasher.combine(bytes)
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

/// Semantic overlay identity. Rendering and operator visibility use this typed
/// value instead of matching ad-hoc strings produced by individual algorithms.
public enum CameraOverlayKind: String, Codable, CaseIterable, Hashable, Sendable {
  case intendedPath
  case observedInk
  case residual
  case acceptedBoundary
  // Preserve the durable raw value used by existing overlay archives.
  case drawingBorder = "calibratedDrawableRegion"
  case paperCoverage
  case predictedContactPoint
  case penCap
  case armatureEstimate
  case diagnostic
}

/// Describes what sort of claim an overlay makes. In particular, an inferred
/// envelope and a simulated observation must never look like direct camera
/// measurement merely because they share camera-pixel geometry.
public enum CameraOverlaySource: String, Codable, Hashable, Sendable {
  case measured
  case inferred
  case planned
  case simulated
  case diagnostic
}

public struct CameraMeasurementProvenance: Codable, Hashable, Sendable {
  public let kind: CameraOverlayKind
  public let source: CameraOverlaySource
  public let algorithmRevision: String

  public init(
    kind: CameraOverlayKind,
    source: CameraOverlaySource,
    algorithmRevision: String
  ) {
    self.kind = kind
    self.source = source
    self.algorithmRevision = algorithmRevision
  }
}

/// Retains the exact pixels from which a measurement was derived. Evidence and
/// point selection use exact matching. A live preview may display the last
/// measured geometry with its original provenance; it must not relabel that
/// geometry as a measurement of newer pixels or another camera configuration.
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
