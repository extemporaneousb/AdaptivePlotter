import Foundation

public enum SwiftSketchPreprocessing: String, Codable, CaseIterable, Hashable, Sendable {
  case unchanged, gamma08, contrast115
}

public struct SwiftSketchRequest: Sendable {
  public let requestID: UUID
  /// Caller-frozen square crop/pad, orientation and fixed mask, before the paired sRGB LUT.
  public let inputPNG: Data
  public let preprocessing: SwiftSketchPreprocessing
  public let seed: Int
  public init(requestID: UUID = UUID(), inputPNG: Data,
    preprocessing: SwiftSketchPreprocessing = .unchanged, seed: Int = 42) {
    self.requestID = requestID; self.inputPNG = inputPNG
    self.preprocessing = preprocessing; self.seed = seed
  }
}

public enum SwiftSketchWorkerStatus: String, Codable, Sendable {
  case succeeded, failed, unavailable, cancelled, timedOut
}

public struct SwiftSketchWorkerResult: Sendable {
  public let requestID: UUID
  public let status: SwiftSketchWorkerStatus
  public let reason: String?
  public let rawOutputJSON: Data?
  public let artistInputPNG: Data?
  public let previewPNG: Data?
  public let provenanceJSON: Data?
  public let responseJSON: Data
  public let attemptDirectory: URL
  public init(requestID: UUID, status: SwiftSketchWorkerStatus, reason: String?,
    rawOutputJSON: Data?, artistInputPNG: Data?, previewPNG: Data?, provenanceJSON: Data?,
    responseJSON: Data, attemptDirectory: URL) {
    self.requestID = requestID; self.status = status; self.reason = reason
    self.rawOutputJSON = rawOutputJSON; self.artistInputPNG = artistInputPNG
    self.previewPNG = previewPNG; self.provenanceJSON = provenanceJSON
    self.responseJSON = responseJSON; self.attemptDirectory = attemptDirectory
  }
}

public struct SwiftSketchWorkerConfiguration: Sendable {
  public let pythonExecutable: URL
  public let workerScript: URL
  public let modelManifest: URL
  public let proofReceipt: URL
  public let attemptRoot: URL
  public let timeoutSeconds: Double
  public let maximumRSSBytes: UInt64
  public init(pythonExecutable: URL, workerScript: URL, modelManifest: URL,
    proofReceipt: URL, attemptRoot: URL, timeoutSeconds: Double = 600,
    maximumRSSBytes: UInt64 = 6 * 1024 * 1024 * 1024) {
    self.pythonExecutable = pythonExecutable; self.workerScript = workerScript
    self.modelManifest = modelManifest; self.proofReceipt = proofReceipt
    self.attemptRoot = attemptRoot; self.timeoutSeconds = timeoutSeconds
    self.maximumRSSBytes = maximumRSSBytes
  }
}

public struct SwiftSketchAvailability: Sendable, Equatable {
  public let available: Bool
  public let reason: String
  public init(available: Bool, reason: String) { self.available = available; self.reason = reason }
}

public enum SwiftSketchError: Error, LocalizedError, Sendable {
  case invalid(String), unavailable(String), busy
  public var errorDescription: String? {
    switch self {
    case .invalid(let reason), .unavailable(let reason): reason
    case .busy: "SwiftSketch already has one active request."
    }
  }
}
