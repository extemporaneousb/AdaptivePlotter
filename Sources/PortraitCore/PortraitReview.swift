import Foundation
import PlotterModel

public enum PortraitReviewDimension: String, Codable, CaseIterable, Hashable, Sendable {
  case overall, likeness, expression, structure, tone, clutter, materialFeasibility
}

/// Choices refer only to the persisted presentation sides. Skip is never a negative label.
public enum PortraitReviewChoice: String, Codable, CaseIterable, Sendable {
  case a, b, tie, neither, skip
}

/// Human declarations, not inferred from a camera acquisition UUID or identical pixels.
public struct PortraitReviewGroups: Codable, Equatable, Sendable {
  public let subjectID: String?
  public let photoSessionID: String?
  public let declaration: String?
  public let ancestryIDs: [String]

  public init(subjectID: String? = nil, photoSessionID: String? = nil,
    declaration: String? = nil, ancestryIDs: [String] = []) {
    self.subjectID = subjectID; self.photoSessionID = photoSessionID
    self.declaration = declaration; self.ancestryIDs = ancestryIDs
  }

  public var sufficientForGroupedSplit: Bool {
    subjectID?.isEmpty == false && photoSessionID?.isEmpty == false && declaration?.isEmpty == false
  }

  public func validate() throws {
    for value in [subjectID, photoSessionID, declaration].compactMap({ $0 }) + ancestryIDs {
      guard !value.isEmpty, value.utf8.count <= 4096 else {
        throw DrawingTransferError.invalid("Review group declarations must be nonempty and bounded when known.")
      }
    }
    guard ancestryIDs.count <= 256, Set(ancestryIDs).count == ancestryIDs.count,
      (subjectID == nil && photoSessionID == nil) || declaration != nil else {
      throw DrawingTransferError.invalid("Known human groups require declaration provenance; ancestry must be unique.")
    }
  }
}

/// Nominal authored material, independently of any machine placement or ink evidence.
public struct PortraitReviewMaterial: Codable, Equatable, Sendable {
  public let widthMM: Double
  public let heightMM: Double
  public let nominalLineWidthMM: Double
  public let penIdentifier: String?
  public let provenance: String?

  public init(widthMM: Double, heightMM: Double, nominalLineWidthMM: Double,
    penIdentifier: String? = nil, provenance: String? = nil) {
    self.widthMM = widthMM; self.heightMM = heightMM; self.nominalLineWidthMM = nominalLineWidthMM
    self.penIdentifier = penIdentifier; self.provenance = provenance
  }

  public func validate() throws {
    guard [widthMM, heightMM, nominalLineWidthMM].allSatisfy({ $0.isFinite && $0 > 0 }),
      nominalLineWidthMM <= min(widthMM, heightMM),
      [penIdentifier, provenance].compactMap({ $0 }).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }) else {
      throw DrawingTransferError.invalid("Review nominal size or pen provenance is invalid.")
    }
  }
}

/// Explicit roles preserve original/derived input and preconversion curves even on failure.
public struct PortraitReviewAsset: Codable, Equatable, Sendable {
  public let role: String
  public let asset: DrawingPackageAsset
  public init(role: String, asset: DrawingPackageAsset) { self.role = role; self.asset = asset }
}

public enum PortraitReviewRecordingMode: String, Codable, Sendable {
  case nativePreGeneration, retrospectiveExternalImport
}

/// Native jobs commit before generation. External historical jobs preserve their original frozen
/// request/manifest bytes and truthfully record later ingestion. This grants no scheduling authority.
public struct PortraitReviewGenerationRequest: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let captureID: UUID
  public let acquisitionID: UUID?
  public let createdAt: Date
  public let source: DrawingPackageAsset
  public let inputs: [PortraitReviewAsset]
  public let groups: PortraitReviewGroups
  public let artist: DrawingPackageArtist
  public let environmentJSON: Data
  public let conversionJSON: Data
  public let seed: UInt64?
  public let material: PortraitReviewMaterial
  public let pilotID: UUID?
  public let split: PortraitReviewDatasetSplit
  public let recordingMode: PortraitReviewRecordingMode

  public init(id: UUID = UUID(), captureID: UUID, acquisitionID: UUID?, createdAt: Date = Date(),
    source: DrawingPackageAsset, inputs: [PortraitReviewAsset] = [],
    groups: PortraitReviewGroups = .init(), artist: DrawingPackageArtist,
    environmentJSON: Data, conversionJSON: Data, seed: UInt64?, material: PortraitReviewMaterial,
    pilotID: UUID? = nil, split: PortraitReviewDatasetSplit = .unassigned,
    recordingMode: PortraitReviewRecordingMode = .nativePreGeneration) throws {
    schemaVersion = 1; self.id = id; self.captureID = captureID; self.acquisitionID = acquisitionID
    self.createdAt = createdAt; self.source = source; self.inputs = inputs; self.groups = groups
    self.artist = artist; self.environmentJSON = environmentJSON; self.conversionJSON = conversionJSON
    self.seed = seed; self.material = material; self.pilotID = pilotID
    self.split = split
    self.recordingMode = recordingMode
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == 1, createdAt.timeIntervalSinceReferenceDate.isFinite,
      !artist.identifier.isEmpty, artist.identifier.utf8.count <= 256,
      !artist.revision.isEmpty, artist.revision.utf8.count <= 256,
      inputs.count <= 32, Set(inputs.map(\.role)).count == inputs.count,
      inputs.allSatisfy({ !$0.role.isEmpty && $0.role.utf8.count <= 256 }),
      inputs.reduce(source.bytes.count, { $0 + $1.asset.bytes.count }) <= DrawingTransferLimits.drawingEmbeddedBytes else {
      throw DrawingTransferError.invalid("Generation request identity, roles, or byte limits are invalid.")
    }
    try source.validate(maximumBytes: DrawingTransferLimits.sourceBytes, requireImage: true)
    for input in inputs { try input.asset.validate(maximumBytes: DrawingTransferLimits.inputBytes) }
    for data in [artist.settingsJSON, environmentJSON, conversionJSON] {
      guard data.count <= 1024 * 1024 else { throw DrawingTransferError.limit("Generation metadata exceeds its limit.") }
      try DrawingPackageCodec.validateJSON(data)
    }
    try groups.validate(); try material.validate()
    guard split == .unassigned || groups.sufficientForGroupedSplit else {
      throw DrawingTransferError.invalid("Unknown human groups must remain unassigned.")
    }
    if recordingMode == .retrospectiveExternalImport {
      guard inputs.contains(where: { $0.role == "external-frozen-request" }),
        inputs.contains(where: { $0.role == "external-frozen-manifest" }) else {
        throw DrawingTransferError.invalid("Retrospective imports must retain the original frozen external request and manifest bytes.")
      }
    }
  }
}

public enum PortraitReviewGenerationStatus: String, Codable, CaseIterable, Sendable {
  case succeeded, failed, cancelled, skipped, unsupported
}

/// Terminal generation evidence. Failed/cancelled/skipped jobs never claim a drawing origin.
public struct PortraitReviewGenerationOutcome: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let requestSHA256: String
  public let status: PortraitReviewGenerationStatus
  public let recordedAt: Date
  public let origin: DrawingOriginReference?
  public let packageSHA256: String?
  public let reason: String?
  public let outputs: [PortraitReviewAsset]
  /// Actual observed runtime metadata; nil means unknown, never copied from the planned environment.
  public let runtimeEnvironmentJSON: Data?
  public let runtimeMetricsJSON: Data?

  public init(id: UUID, requestSHA256: String, status: PortraitReviewGenerationStatus,
    recordedAt: Date = Date(), origin: DrawingOriginReference? = nil, packageSHA256: String? = nil,
    reason: String? = nil, outputs: [PortraitReviewAsset] = [],
    runtimeEnvironmentJSON: Data? = nil, runtimeMetricsJSON: Data? = nil) throws {
    schemaVersion = 1; self.id = id; self.requestSHA256 = requestSHA256; self.status = status
    self.recordedAt = recordedAt; self.origin = origin; self.packageSHA256 = packageSHA256
    self.reason = reason; self.outputs = outputs
    self.runtimeEnvironmentJSON = runtimeEnvironmentJSON; self.runtimeMetricsJSON = runtimeMetricsJSON
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == 1, PortraitReviewValidation.isHash(requestSHA256),
      recordedAt.timeIntervalSinceReferenceDate.isFinite,
      outputs.count <= 32, Set(outputs.map(\.role)).count == outputs.count,
      outputs.allSatisfy({ !$0.role.isEmpty && $0.role.utf8.count <= 256 }),
      outputs.reduce(0, { $0 + $1.asset.bytes.count }) <= DrawingTransferLimits.drawingEmbeddedBytes,
      reason.map({ !$0.isEmpty && $0.utf8.count <= 16384 }) ?? true else {
      throw DrawingTransferError.invalid("Generation outcome metadata is invalid.")
    }
    if status == .succeeded {
      guard let origin, let packageSHA256, PortraitReviewValidation.isHash(packageSHA256), reason == nil else {
        throw DrawingTransferError.invalid("Successful generation requires a complete drawing package identity.")
      }
      try origin.validate()
    } else if origin != nil || packageSHA256 != nil || reason == nil {
      throw DrawingTransferError.invalid("Non-success outcomes require a reason and cannot claim a drawing package.")
    }
    for output in outputs { try output.asset.validate(maximumBytes: DrawingTransferLimits.inputBytes) }
    for bytes in [runtimeEnvironmentJSON, runtimeMetricsJSON].compactMap({ $0 }) {
      guard bytes.count <= 1024 * 1024 else { throw DrawingTransferError.limit("Runtime metadata exceeds its limit.") }
      try DrawingPackageCodec.validateJSON(bytes)
    }
  }
}

public struct PortraitReviewResultReference: Codable, Equatable, Sendable {
  public let origin: DrawingOriginReference
  public let packageSHA256: String
  public let sourceSHA256: String
  public let previewSHA256: String
  public let displayPreviewSHA256: String
  public let material: PortraitReviewMaterial
  public let nominalLineWidthsMM: [Double]
  public var programHash: String { origin.programHash.description }

  public init(package: DrawingPackage, packageSHA256: String, displayPreviewSHA256: String,
    material: PortraitReviewMaterial? = nil) {
    origin = package.origin; self.packageSHA256 = packageSHA256
    sourceSHA256 = package.source.sha256; previewSHA256 = package.preview.sha256
    self.displayPreviewSHA256 = displayPreviewSHA256
    nominalLineWidthsMM = Array(Set(package.program.strokes.map { $0.style.nominalLineWidth })).sorted()
    self.material = material ?? .init(widthMM: package.program.fieldExtent.width,
      heightMM: package.program.fieldExtent.height,
      nominalLineWidthMM: package.program.strokes.first?.style.nominalLineWidth ?? 0)
  }
  public func validate() throws {
    try origin.validate()
    try material.validate()
    guard [packageSHA256, sourceSHA256, previewSHA256, displayPreviewSHA256].allSatisfy(PortraitReviewValidation.isHash) else {
      throw DrawingTransferError.invalid("Review result hashes are invalid.")
    }
    guard !nominalLineWidthsMM.isEmpty,
      nominalLineWidthsMM.allSatisfy({ $0.isFinite && $0 > 0 }),
      nominalLineWidthsMM.contains(material.nominalLineWidthMM) else {
      throw DrawingTransferError.invalid("Review pen context does not match nominal program widths.")
    }
  }
}

/// Immutable presentation assignment. Artist names are not labels; the original remains visible.
public struct PortraitReviewComparison: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let a: PortraitReviewResultReference
  public let b: PortraitReviewResultReference
  public let originalSourceSHA256: String
  public let presentationSeed: UInt64
  public let rubricVersion: String
  public let createdAt: Date
  public let originalVisible: Bool
  public let displayMaterial: PortraitReviewMaterial
  public let displayPixelWidth: Int
  public let displayPixelHeight: Int
  public let displayTransformRevision: String
  public let displayPaddingMM: Double

  public init(id: UUID = UUID(), first: PortraitReviewResultReference, second: PortraitReviewResultReference,
    presentationSeed: UInt64, rubricVersion: String, createdAt: Date = Date(),
    displayMaterial: PortraitReviewMaterial, displayPixelWidth: Int, displayPixelHeight: Int) throws {
    schemaVersion = 1; self.id = id; self.presentationSeed = presentationSeed
    self.rubricVersion = rubricVersion; self.createdAt = createdAt; originalVisible = true
    self.displayMaterial = displayMaterial; self.displayPixelWidth = displayPixelWidth
    self.displayPixelHeight = displayPixelHeight; displayTransformRevision = "portrait-review-common-field-v2-y-up"
    displayPaddingMM = (first.nominalLineWidthsMM.max() ?? 0) / 2
    // Sort before sampling so first/second caller order cannot determine A/B.
    let sorted = [first, second].sorted { $0.origin.drawingID < $1.origin.drawingID }
    var mixed = presentationSeed &+ 0x9e3779b97f4a7c15
    mixed = (mixed ^ (mixed >> 30)) &* 0xbf58476d1ce4e5b9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94d049bb133111eb
    mixed ^= mixed >> 31
    a = sorted[Int(mixed & 1)]; b = sorted[1 - Int(mixed & 1)]
    originalSourceSHA256 = first.sourceSHA256
    try validate()
  }

  public func validate() throws {
    try a.validate(); try b.validate()
    try displayMaterial.validate()
    guard schemaVersion == 1, originalVisible, a.origin != b.origin,
      a.sourceSHA256 == originalSourceSHA256, b.sourceSHA256 == originalSourceSHA256,
      a.origin.captureID == b.origin.captureID,
      a.origin.libraryID == b.origin.libraryID,
      a.nominalLineWidthsMM == b.nominalLineWidthsMM,
      displayMaterial.widthMM == max(a.material.widthMM, b.material.widthMM),
      displayMaterial.heightMM == max(a.material.heightMM, b.material.heightMM),
      a.nominalLineWidthsMM.contains(displayMaterial.nominalLineWidthMM),
      displayPixelWidth > 0, displayPixelWidth <= 1024, displayPixelHeight > 0, displayPixelHeight <= 1024,
      displayTransformRevision == "portrait-review-common-field-v2-y-up",
      displayPaddingMM == (a.nominalLineWidthsMM.max() ?? 0) / 2,
      !rubricVersion.isEmpty, rubricVersion.utf8.count <= 4096,
      createdAt.timeIntervalSinceReferenceDate.isFinite else {
      throw DrawingTransferError.invalid("Comparison must bind distinct results of the exact original capture.")
    }
  }
}

/// A full explicit revision; callers may merge displayed prior choices, never infer unentered dimensions.
public struct PortraitReviewLabelRevision: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let comparisonID: UUID
  public let comparisonSHA256: String
  public let choices: [PortraitReviewDimension: PortraitReviewChoice]
  public let reviewerID: String?
  public let recordedAt: Date
  public let supersedes: UUID?

  public init(id: UUID = UUID(), comparisonID: UUID, comparisonSHA256: String,
    choices: [PortraitReviewDimension: PortraitReviewChoice], reviewerID: String?,
    recordedAt: Date = Date(), supersedes: UUID?) throws {
    schemaVersion = 1; self.id = id; self.comparisonID = comparisonID
    self.comparisonSHA256 = comparisonSHA256; self.choices = choices; self.reviewerID = reviewerID
    self.recordedAt = recordedAt; self.supersedes = supersedes
    try validate()
  }

  public var isSkipped: Bool { choices[.overall] == .skip }
  public func validate() throws {
    guard schemaVersion == 1, PortraitReviewValidation.isHash(comparisonSHA256), choices[.overall] != nil,
      recordedAt.timeIntervalSinceReferenceDate.isFinite, supersedes != id,
      reviewerID.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true,
      !isSkipped || choices.values.allSatisfy({ $0 == .skip }) else {
      throw DrawingTransferError.invalid("Review labels require an explicit overall choice; skipped comparisons cannot carry ratings.")
    }
  }
}

public enum PortraitReviewValidation {
  public static func isHash(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
}

/// Existing artwork may be grouped explicitly without fabricating a generation job.
public struct PortraitReviewGroupDeclaration: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let origin: DrawingOriginReference
  public let sourceSHA256: String
  public let acquisitionID: UUID?
  public let groups: PortraitReviewGroups
  public let split: PortraitReviewDatasetSplit
  public let declaredAt: Date
  public init(id: UUID = UUID(), origin: DrawingOriginReference, sourceSHA256: String,
    acquisitionID: UUID?, groups: PortraitReviewGroups, split: PortraitReviewDatasetSplit,
    declaredAt: Date = Date()) throws {
    schemaVersion = 1; self.id = id; self.origin = origin; self.sourceSHA256 = sourceSHA256
    self.acquisitionID = acquisitionID; self.groups = groups; self.split = split; self.declaredAt = declaredAt
    try validate()
  }
  public func validate() throws {
    try origin.validate(); try groups.validate()
    guard schemaVersion == 1, PortraitReviewValidation.isHash(sourceSHA256),
      declaredAt.timeIntervalSinceReferenceDate.isFinite,
      split == .unassigned || groups.sufficientForGroupedSplit else {
      throw DrawingTransferError.invalid("Group declaration or frozen split is invalid.")
    }
  }
}
