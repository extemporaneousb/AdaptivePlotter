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

      init(
        filename: String,
        sequence: UInt64,
        captureNanoseconds: UInt64,
        frameID: String,
        contentSHA256: String,
        width: Int,
        height: Int,
        rowBytes: Int,
        pixelFormat: FramePixelFormat
      ) {
        self.filename = filename
        self.sequence = sequence
        self.captureNanoseconds = captureNanoseconds
        self.frameID = frameID
        self.contentSHA256 = contentSHA256
        self.width = width
        self.height = height
        self.rowBytes = rowBytes
        self.pixelFormat = pixelFormat
      }
    }

    let purpose: String
    let episodeID: String?
    let cameraDeviceID: String
    let cameraName: String
    let cameraConfigurationID: String
    let samples: [Sample]

    init(
      purpose: String,
      episodeID: String? = nil,
      cameraDeviceID: String,
      cameraName: String,
      cameraConfigurationID: String,
      samples: [Sample]
    ) {
      self.purpose = purpose
      self.episodeID = episodeID
      self.cameraDeviceID = cameraDeviceID
      self.cameraName = cameraName
      self.cameraConfigurationID = cameraConfigurationID
      self.samples = samples
    }
  }

  enum RecordingError: LocalizedError {
    case noMatchingFrames
    case imageConversionFailed(sequence: UInt64)
    case imageDestinationFailed(URL)
    case imageWriteFailed(URL)

    var errorDescription: String? {
      switch self {
      case .noMatchingFrames:
        "The selected camera does not own this frame."
      case let .imageConversionFailed(sequence):
        "Could not convert camera frame \(sequence) to an image."
      case let .imageDestinationFailed(url):
        "Could not create the PNG destination at \(url.path)."
      case let .imageWriteFailed(url):
        "Could not finalize the PNG at \(url.path)."
      }
    }
  }

  let rootDirectory: URL

  init(
    rootDirectory: URL = Self.defaultRootDirectory()
  ) {
    self.rootDirectory = rootDirectory
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
      purpose:
        "operator-requested scene snapshot for offline vision analysis; not motion or drawing evidence",
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
    let base =
      FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? FileManager.default.temporaryDirectory
    return
      base
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
