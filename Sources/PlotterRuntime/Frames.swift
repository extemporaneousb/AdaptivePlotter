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

/// Bounds immutable preview creation without reducing the camera's delivery
/// rate. Exact snapshot and measurement requests may still materialize the
/// newest delivered pixels immediately.
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

/// Semantic overlay identity. Rendering and operator visibility use this typed
/// value instead of matching ad-hoc strings produced by individual algorithms.
public enum CameraOverlayKind: String, Codable, CaseIterable, Hashable, Sendable {
  case intendedPath
  case observedInk
  case residual
  case calibratedDrawableRegion
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
