import Foundation
import ImageIO
import PlotterModel
import PlotterRuntime
import UniformTypeIdentifiers

struct StartupFrameRecorder: Sendable {
  struct Manifest: Codable, Equatable, Sendable {
    struct Sample: Codable, Equatable, Sendable {
      let filename: String
      let sequence: UInt64
      let captureNanoseconds: UInt64
      let frameID: String
      let contentSHA256: String
      let width: Int
      let height: Int
      let rowBytes: Int
      let pixelFormat: FramePixelFormat
    }

    let purpose: String
    let cameraDeviceID: String
    let cameraName: String
    let cameraConfigurationID: String
    let samples: [Sample]
  }

  enum RecordingError: LocalizedError {
    case invalidSampleCount
    case noMatchingFrames
    case imageConversionFailed(sequence: UInt64)
    case imageDestinationFailed(URL)
    case imageWriteFailed(URL)

    var errorDescription: String? {
      switch self {
      case .invalidSampleCount:
        "Startup camera sample count must be greater than zero."
      case .noMatchingFrames:
        "Camera stopped before any matching startup frames could be saved."
      case let .imageConversionFailed(sequence):
        "Could not convert startup camera frame \(sequence) to an image."
      case let .imageDestinationFailed(url):
        "Could not create the PNG destination at \(url.path)."
      case let .imageWriteFailed(url):
        "Could not finalize the PNG at \(url.path)."
      }
    }
  }

  let rootDirectory: URL
  let sampleCount: Int
  let minimumIntervalNanoseconds: UInt64

  init(
    rootDirectory: URL = Self.defaultRootDirectory(),
    sampleCount: Int = 3,
    minimumIntervalNanoseconds: UInt64 = 750_000_000
  ) {
    self.rootDirectory = rootDirectory
    self.sampleCount = sampleCount
    self.minimumIntervalNanoseconds = minimumIntervalNanoseconds
  }

  func record(
    frames: AsyncStream<DisplayedFrame>,
    device: CameraDevice
  ) async throws -> URL {
    guard sampleCount > 0 else { throw RecordingError.invalidSampleCount }
    let directory = rootDirectory.appendingPathComponent(
      Self.runDirectoryName(prefix: "startup"),
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    var samples: [Manifest.Sample] = []
    var firstConfigurationID: CameraConfigurationID?
    var lastCaptureNanoseconds: UInt64?

    for await displayedFrame in frames {
      try Task.checkCancellation()
      guard case .live(let sourceDeviceID) = displayedFrame.source,
        sourceDeviceID == device.id
      else { continue }
      let frame = displayedFrame.frame
      if let firstConfigurationID {
        guard frame.cameraConfigurationID == firstConfigurationID else { continue }
      } else {
        firstConfigurationID = frame.cameraConfigurationID
      }
      if let lastCaptureNanoseconds {
        guard frame.captureNanoseconds >= lastCaptureNanoseconds,
          frame.captureNanoseconds - lastCaptureNanoseconds >= minimumIntervalNanoseconds
        else { continue }
      }

      let filename = String(format: "frame-%02d-seq-%llu.png", samples.count + 1, frame.sequence)
      let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
      try Self.writePNG(frame, to: fileURL)
      samples.append(
        Manifest.Sample(
          filename: filename,
          sequence: frame.sequence,
          captureNanoseconds: frame.captureNanoseconds,
          frameID: frame.id.rawValue,
          contentSHA256: frame.contentSHA256,
          width: frame.width,
          height: frame.height,
          rowBytes: frame.rowBytes,
          pixelFormat: frame.pixelFormat
        ))
      lastCaptureNanoseconds = frame.captureNanoseconds
      if samples.count == sampleCount { break }
    }

    guard let configurationID = firstConfigurationID, !samples.isEmpty else {
      throw RecordingError.noMatchingFrames
    }
    let manifest = Manifest(
      purpose: "startup scene samples for offline vision analysis; not calibration evidence",
      cameraDeviceID: device.id.rawValue,
      cameraName: device.name,
      cameraConfigurationID: configurationID.rawValue.uuidString.lowercased(),
      samples: samples
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
      to: directory.appendingPathComponent("manifest.json"),
      options: .atomic
    )
    return directory
  }

  func recordSnapshot(_ displayedFrame: DisplayedFrame, device: CameraDevice) throws -> URL {
    guard case .live(let sourceDeviceID) = displayedFrame.source,
      sourceDeviceID == device.id
    else { throw RecordingError.noMatchingFrames }
    let frame = displayedFrame.frame
    let directory = rootDirectory.appendingPathComponent(
      Self.runDirectoryName(prefix: "snapshot"),
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let filename = String(format: "frame-seq-%llu.png", frame.sequence)
    try Self.writePNG(frame, to: directory.appendingPathComponent(filename))
    let manifest = Manifest(
      purpose: "operator-requested scene snapshot for offline vision analysis; not calibration evidence",
      cameraDeviceID: device.id.rawValue,
      cameraName: device.name,
      cameraConfigurationID: frame.cameraConfigurationID.rawValue.uuidString.lowercased(),
      samples: [
        Manifest.Sample(
          filename: filename,
          sequence: frame.sequence,
          captureNanoseconds: frame.captureNanoseconds,
          frameID: frame.id.rawValue,
          contentSHA256: frame.contentSHA256,
          width: frame.width,
          height: frame.height,
          rowBytes: frame.rowBytes,
          pixelFormat: frame.pixelFormat
        )
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(
      to: directory.appendingPathComponent("manifest.json"),
      options: .atomic
    )
    return directory
  }

  static func defaultRootDirectory() -> URL {
    let base = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first ?? FileManager.default.temporaryDirectory
    return base
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
      .appendingPathComponent("CameraSamples", isDirectory: true)
  }

  private static func runDirectoryName(prefix: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
    return "\(prefix)-\(timestamp)-\(UUID().uuidString.lowercased())"
  }

  private static func writePNG(_ frame: StampedFrame, to url: URL) throws {
    guard let image = FrameImageFactory.image(from: frame) else {
      throw RecordingError.imageConversionFailed(sequence: frame.sequence)
    }
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw RecordingError.imageDestinationFailed(url)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw RecordingError.imageWriteFailed(url)
    }
  }
}
