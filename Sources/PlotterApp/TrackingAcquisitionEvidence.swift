import Foundation
import PlotterModel
import PlotterRuntime

/// Diagnostic copies only. These files cannot accept Learning, supply a live
/// observation, or authorize motion. Ambient video never writes to this owner.
struct TrackingAcquisitionContext: Codable, Sendable {
  let ownerID: String?
  let attemptID: String?
  let reportedPosition: MachinePosition?
  let reportedPenState: String?
  /// Time the caller copied its cached controller snapshot, not the time its
  /// controller observed that position and not the image's capture time.
  let snapshotMonotonicNanoseconds: UInt64
  let source: String
}

enum TrackingAcquisitionPhase: String, Codable, Sendable {
  case success, failure, cancelled
}

struct TrackingDetectionEvidence: Codable, Sendable {
  struct Candidate: Codable, Sendable {
    let score: Double
    let boundingBox: PixelRect
    let anchor: Point2<CameraPixelSpace>
  }
  struct ColorCandidate: Codable, Sendable {
    let pixelCount: Int
    let boundingBox: PixelRect
    let colorSimilarity: Double
    let supportScore: Double
    let aspectRatio: Double
    let fillFraction: Double
    let confidence: Double
  }
  let disposition: String
  let reason: String
  var trackingPoint: Point2<CameraPixelSpace>?
  var centroid: Point2<CameraPixelSpace>?
  var boundingBox: PixelRect?
  var confidence: Double?
  var candidates: [Candidate] = []
  var colorCandidates: [ColorCandidate] = []
  var inspectedPixelCount: Int?
  var thresholdPixelCount: Int?
  var componentCount: Int?
  var acceptanceThreshold: Double?
  var requiredMargin: Double?
  var competitorScore: Double?
  var predictionResidualPixels: Double?
  var confirmedExampleCount: Int?
  var rejectionReason: String?

  init(_ result: PenCapDetectionResult) {
    reason = result.diagnosticReason
    let diagnostics: PenCapDiagnostics?
    switch result {
    case .found(let cap, let details):
      disposition = "found"; diagnostics = details
      trackingPoint = cap.trackingPoint; centroid = cap.centroid
      boundingBox = cap.boundingBox; confidence = cap.confidence
    case .notFound(let details): disposition = "notFound"; diagnostics = details
    case .ambiguous(_, let details): disposition = "ambiguous"; diagnostics = details
    case .failed: disposition = "failed"; diagnostics = nil
    case .notRequested: disposition = "notRequested"; diagnostics = nil
    }
    if let diagnostics {
      inspectedPixelCount = diagnostics.inspectedPixelCount
      thresholdPixelCount = diagnostics.thresholdPixelCount
      componentCount = diagnostics.componentCount
      colorCandidates = diagnostics.candidates.map {
        ColorCandidate(pixelCount: $0.pixelCount, boundingBox: $0.boundingBox,
          colorSimilarity: $0.colorSimilarity, supportScore: $0.supportScore,
          aspectRatio: $0.aspectRatio, fillFraction: $0.fillFraction, confidence: $0.confidence)
      }
      if let template = diagnostics.template {
        candidates = template.candidates.map { Candidate(score: $0.score, boundingBox: $0.boundingBox, anchor: $0.anchor) }
        acceptanceThreshold = template.acceptanceThreshold; requiredMargin = template.requiredMargin
        competitorScore = template.competitorScore; predictionResidualPixels = template.predictionResidualPixels
        confirmedExampleCount = template.confirmedExampleCount; rejectionReason = template.rejectionReason?.detail
      }
    }
  }
}

struct TrackingAcquisitionEvidence: Codable, Sendable {
  struct Camera: Codable, Sendable {
    let source: FrameSourceIdentity
    let frameID: FrameID
    let sequence: UInt64
    let captureNanoseconds: UInt64
    let cameraConfigurationID: CameraConfigurationID
    let width: Int, height: Int, rowBytes: Int
    let pixelFormat: FramePixelFormat
    let contentSHA256: String
    let pixelsFile: String
    init(_ frame: DisplayedFrame) {
      source = frame.source; frameID = frame.frame.id; sequence = frame.frame.sequence
      captureNanoseconds = frame.frame.captureNanoseconds
      cameraConfigurationID = frame.frame.cameraConfigurationID
      width = frame.frame.width; height = frame.frame.height; rowBytes = frame.frame.rowBytes
      pixelFormat = frame.frame.pixelFormat
      contentSHA256 = frame.frame.materializingContentHash(for: .serialization).contentSHA256
      pixelsFile = "analyzed-frame.pixels"
    }
  }
  struct Options: Codable, Sendable {
    let capSearchRegion: PixelRect
    let penCapColor: PenCapColor
    let algorithmRevision: String
    let boundReferenceIdentity: String?
    let boundCaptureConfigurationID: CameraConfigurationID?
    let boundOpticalConfiguration: CameraOpticalConfigurationIdentity?
    let armatureHalfWidthFraction: Double
    let armatureTopMarginFraction: Double
    let armatureHeightFraction: Double
    init(_ priors: PlotterSceneVisionPriors) {
      capSearchRegion = priors.capSearchRegion; penCapColor = priors.penCapColor
      algorithmRevision = priors.algorithmRevision
      boundReferenceIdentity = priors.referenceBinding?.referenceIdentity
      boundCaptureConfigurationID = priors.referenceBinding?.cameraConfigurationID
      boundOpticalConfiguration = priors.referenceBinding?.opticalConfiguration
      armatureHalfWidthFraction = priors.armatureHalfWidthFraction
      armatureTopMarginFraction = priors.armatureTopMarginFraction
      armatureHeightFraction = priors.armatureHeightFraction
    }
  }
  let format: String
  let acquisitionID: UUID
  let exportedAt: Date
  let phase: TrackingAcquisitionPhase
  let camera: Camera
  let reference: PenCapVisualReference?
  let markerReference: SampledColorMarkerReference?
  /// Monotonic time around the exact analysis await, including its scheduling.
  let analysisElapsedNanoseconds: UInt64?
  let referenceIdentity: String?
  let referenceRevision: String
  let detection: TrackingDetectionEvidence?
  let searchCenter: Point2<CameraPixelSpace>?
  let newerThanNanoseconds: UInt64
  let options: Options?
  let ownerEvidence: [String: String]
  let context: TrackingAcquisitionContext?
  let limitations: [String]
}

actor TrackingAcquisitionEvidenceRecorder {
  static let shared = TrackingAcquisitionEvidenceRecorder()
  private let directory: URL
  private let maximumEntries: Int
  private let maximumBytes: Int

  init(directory: URL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/AdaptivePlotter/TrackingAcquisitions", isDirectory: true),
    maximumEntries: Int = 12, maximumBytes: Int = 128 * 1_024 * 1_024) {
    self.directory = directory; self.maximumEntries = maximumEntries; self.maximumBytes = maximumBytes
  }

  /// Returns a visible diagnostic on failure; never substitutes for the original
  /// acquisition outcome. Call at bounded workflow boundaries, not per video frame.
  func record(frame: DisplayedFrame, reference: PenCapVisualReference?,
    detection: PenCapDetectionResult?, searchCenter: Point2<CameraPixelSpace>?,
    phase: TrackingAcquisitionPhase, acquisitionID: UUID, newerThanNanoseconds: UInt64,
    ownerEvidence: [String: String] = [:], priors: PlotterSceneVisionPriors? = nil,
    context: TrackingAcquisitionContext? = nil,
    markerReference: SampledColorMarkerReference? = nil, analysisElapsedNanoseconds: UInt64? = nil) -> String? {
    do {
      _ = try write(frame: frame, reference: reference, detection: detection,
        searchCenter: searchCenter, phase: phase, acquisitionID: acquisitionID,
        newerThanNanoseconds: newerThanNanoseconds, ownerEvidence: ownerEvidence, priors: priors, context: context,
        markerReference: markerReference, analysisElapsedNanoseconds: analysisElapsedNanoseconds)
      return nil
    } catch {
      return "Tracking acquisition evidence could not be saved: \(error.localizedDescription)"
    }
  }

  func write(frame: DisplayedFrame, reference: PenCapVisualReference?,
    detection: PenCapDetectionResult?, searchCenter: Point2<CameraPixelSpace>?,
    phase: TrackingAcquisitionPhase, acquisitionID: UUID, newerThanNanoseconds: UInt64,
    ownerEvidence: [String: String] = [:], priors: PlotterSceneVisionPriors? = nil,
    context: TrackingAcquisitionContext? = nil,
    markerReference: SampledColorMarkerReference? = nil, analysisElapsedNanoseconds: UInt64? = nil) throws -> URL {
    let fm = FileManager.default
    let camera = TrackingAcquisitionEvidence.Camera(frame)
    let evidence = TrackingAcquisitionEvidence(format: "adaptiveplotter.tracking-acquisition.v1",
      acquisitionID: acquisitionID, exportedAt: Date(), phase: phase, camera: camera,
      reference: reference, markerReference: markerReference, analysisElapsedNanoseconds: analysisElapsedNanoseconds,
      referenceIdentity: markerReference?.identity ?? reference?.identity,
      referenceRevision: markerReference == nil ? PenCapVisualReference.revision : SampledColorMarkerReference.revision,
      detection: detection.map(TrackingDetectionEvidence.init), searchCenter: searchCenter,
      newerThanNanoseconds: newerThanNanoseconds, options: priors.map(TrackingAcquisitionEvidence.Options.init),
      ownerEvidence: ownerEvidence, context: context, limitations: [
        "Exact analyzed raw pixels; no overlays or PNG conversion.",
        "Controller pose, pen state and owner identity are unknown unless explicitly supplied. Context is a cached pre-acquisition snapshot, not an exact frame-synchronized or visually measured pose.",
        "Diagnostic copy only; does not prove ink, settle motion, accept Learning or authorize replay.",
        "Bounded retention evicts oldest acquisition folders; this is not continuous video or a complete incident archive."
      ])
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let metadata = try encoder.encode(evidence)
    let pixels = frame.frame.bytes.data
    guard maximumEntries > 0, maximumBytes > 0,
      pixels.count <= maximumBytes, metadata.count <= maximumBytes - pixels.count else {
      throw CocoaError(.fileWriteOutOfSpace)
    }
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let pending = directory.appendingPathComponent(".pending-\(UUID().uuidString)", isDirectory: true)
    try fm.createDirectory(at: pending, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: pending) }
    try pixels.write(to: pending.appendingPathComponent(camera.pixelsFile), options: .atomic)
    try metadata.write(to: pending.appendingPathComponent("manifest.json"), options: .atomic)
    let required = pixels.count + metadata.count
    var retained: [(url: URL, date: Date, bytes: Int)] = []
    for url in try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]) {
      let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey])
      guard url.lastPathComponent.hasPrefix("acquisition-"), values.isDirectory == true,
        values.isSymbolicLink != true else { continue }
      var bytes = 0
      for asset in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) {
        let properties = try asset.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
        guard properties.isSymbolicLink != true else { throw CocoaError(.fileReadInvalidFileName) }
        bytes += properties.fileSize ?? 0
      }
      retained.append((url, values.creationDate ?? .distantPast, bytes))
    }
    retained.sort { $0.date < $1.date }
    var total = retained.reduce(0) { $0 + $1.bytes }
    while retained.count >= maximumEntries || total > maximumBytes - required {
      guard !retained.isEmpty else { throw CocoaError(.fileWriteOutOfSpace) }
      let oldest = retained.removeFirst()
      try fm.removeItem(at: oldest.url); total -= oldest.bytes
    }
    let destination = directory.appendingPathComponent("acquisition-\(UUID().uuidString)", isDirectory: true)
    try fm.moveItem(at: pending, to: destination)
    return destination.appendingPathComponent("manifest.json")
  }
}
