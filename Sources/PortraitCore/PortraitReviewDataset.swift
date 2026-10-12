import Foundation
import PlotterModel

public enum PortraitReviewDatasetSplit: String, Codable, CaseIterable, Hashable, Sendable {
  case train, validation, test, unassigned
}

public struct PortraitReviewDatasetGroup: Codable, Equatable, Sendable {
  public let requestID: UUID
  public let captureID: UUID
  public let acquisitionID: UUID?
  public let sourceSHA256: String
  public let groups: PortraitReviewGroups
  public let split: PortraitReviewDatasetSplit
  public let libraryID: UUID?
  public init(requestID: UUID, captureID: UUID, acquisitionID: UUID?, sourceSHA256: String,
    groups: PortraitReviewGroups, split: PortraitReviewDatasetSplit, libraryID: UUID? = nil) {
    self.requestID = requestID; self.captureID = captureID; self.acquisitionID = acquisitionID
    self.sourceSHA256 = sourceSHA256; self.groups = groups; self.split = split
    self.libraryID = libraryID
  }
}

/// Known artifact lineage, independent of human subject/session declarations.
public struct PortraitReviewDatasetDependency: Codable, Equatable, Sendable {
  public let origin: DrawingOriginReference
  public let sourceSHA256: String
  public let ancestryIDs: [String]
  public let derivation: String
  public init(origin: DrawingOriginReference, sourceSHA256: String, ancestryIDs: [String]) {
    self.origin = origin; self.sourceSHA256 = sourceSHA256; self.ancestryIDs = ancestryIDs
    derivation = "native-candidate-lineage-v1"
  }
  public func validate() throws {
    try origin.validate()
    guard PortraitReviewValidation.isHash(sourceSHA256), derivation == "native-candidate-lineage-v1",
      !ancestryIDs.isEmpty, ancestryIDs.count <= 256,
      Set(ancestryIDs).count == ancestryIDs.count,
      ancestryIDs.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 4096 }) else {
      throw DrawingTransferError.invalid("Derived native artifact ancestry is invalid.")
    }
  }
}

/// Enforces connected components across declared people, sessions, source bytes and ancestry.
/// Acquisition UUIDs are occurrence identities and never substitute for photographic session groups.
public enum PortraitReviewSplitValidation {
  public static func validate(_ entries: [PortraitReviewDatasetGroup],
    dependencies: [PortraitReviewDatasetDependency] = []) throws {
    guard Set(entries.map(\.requestID)).count == entries.count else {
      throw DrawingTransferError.invalid("Duplicate dataset request identity.")
    }
    var parents = Array(0..<(entries.count + dependencies.count))
    func root(_ index: Int) -> Int {
      var result = index
      while parents[result] != result { result = parents[result] }
      return result
    }
    var keyOwners: [String: Int] = [:]
    for (index, entry) in entries.enumerated() {
      try entry.groups.validate()
      guard PortraitReviewValidation.isHash(entry.sourceSHA256),
        entry.split == .unassigned || entry.groups.sufficientForGroupedSplit else {
        throw DrawingTransferError.invalid("Unknown human groups must remain unassigned.")
      }
      var keys = ["source:" + entry.sourceSHA256]
      if let libraryID = entry.libraryID {
        keys.append("capture:" + libraryID.uuidString.lowercased() + ":" + entry.captureID.uuidString.lowercased())
      }
      if let subject = entry.groups.subjectID { keys.append("subject:" + subject) }
      if let session = entry.groups.photoSessionID { keys.append("session:" + session) }
      keys += entry.groups.ancestryIDs.map { "ancestry:" + $0 }
      for key in keys {
        if let owner = keyOwners[key] { parents[root(index)] = root(owner) }
        else { keyOwners[key] = index }
      }
    }
    for (offset, dependency) in dependencies.enumerated() {
      try dependency.validate()
      let index = entries.count + offset
      let keys = ["source:" + dependency.sourceSHA256] + dependency.ancestryIDs.map { "ancestry:" + $0 }
      for key in keys {
        if let owner = keyOwners[key] { parents[root(index)] = root(owner) }
        else { keyOwners[key] = index }
      }
    }
    var splits: [Int: PortraitReviewDatasetSplit] = [:]
    for (index, entry) in entries.enumerated() where entry.split != .unassigned {
      let component = root(index)
      if let prior = splits[component], prior != entry.split {
        throw DrawingTransferError.conflict("Connected subject/session/source/ancestry groups cross dataset splits.")
      }
      splits[component] = entry.split
    }
  }
}

public struct PortraitReviewDatasetFile: Codable, Equatable, Sendable {
  public let path: String
  public let sha256: String
  public let byteCount: Int
  public let mediaType: String
  public init(path: String, bytes: Data, mediaType: String) {
    self.path = path; sha256 = DrawingPackageCodec.sha256(bytes)
    byteCount = bytes.count; self.mediaType = mediaType
  }
}

public struct PortraitReviewDatasetResult: Codable, Equatable, Sendable {
  public let origin: DrawingOriginReference
  public let packageSHA256: String
  public let sourceSHA256: String
  public let artistInputSHA256: String
  public let previewSHA256: String
  public let programSHA256: String
  public let programContentHash: String
  public let resultRecordSHA256: String
  public let artistSettingsSHA256: String
  public let material: PortraitReviewMaterial
  public let nominalLineWidthsMM: [Double]
  public let requestID: UUID?
  public let split: PortraitReviewDatasetSplit
  public init(origin: DrawingOriginReference, packageSHA256: String, sourceSHA256: String,
    artistInputSHA256: String, previewSHA256: String, programSHA256: String, programContentHash: String,
    resultRecordSHA256: String, artistSettingsSHA256: String, material: PortraitReviewMaterial,
    nominalLineWidthsMM: [Double], requestID: UUID?, split: PortraitReviewDatasetSplit) {
    self.origin = origin; self.packageSHA256 = packageSHA256; self.sourceSHA256 = sourceSHA256
    self.artistInputSHA256 = artistInputSHA256; self.previewSHA256 = previewSHA256
    self.programSHA256 = programSHA256; self.programContentHash = programContentHash
    self.resultRecordSHA256 = resultRecordSHA256; self.artistSettingsSHA256 = artistSettingsSHA256
    self.material = material; self.nominalLineWidthsMM = nominalLineWidthsMM
    self.requestID = requestID; self.split = split
  }
}

public struct PortraitReviewDatasetRecord: Codable, Equatable, Sendable {
  public let id: UUID
  public let kind: String
  public let fileSHA256: String
  public let terminalStatus: PortraitReviewGenerationStatus?
  public init(id: UUID, kind: String, fileSHA256: String, terminalStatus: PortraitReviewGenerationStatus? = nil) {
    self.id = id; self.kind = kind; self.fileSHA256 = fileSHA256; self.terminalStatus = terminalStatus
  }
}

public struct PortraitReviewDatasetCounts: Codable, Equatable, Sendable {
  public let requests: Int
  public let pending: Int
  public let succeeded: Int
  public let failed: Int
  public let cancelled: Int
  public let skipped: Int
  public let unsupported: Int
  public let drawingResults: Int
  public let comparisons: Int
  public let labelRevisions: Int
  public let ratedComparisonHeads: Int
  public let skippedComparisonHeads: Int
  public let unlabeledComparisons: Int
  public let declaredSubjects: Int
  public let declaredPhotoSessions: Int
  public let unassignedRequests: Int
  public let groupDeclarations: Int
  public let unassignedResults: Int
  public let plotAttachments: Int
  public init(requests: Int, pending: Int, succeeded: Int, failed: Int, cancelled: Int, skipped: Int,
    unsupported: Int, drawingResults: Int, comparisons: Int, labelRevisions: Int,
    ratedComparisonHeads: Int, skippedComparisonHeads: Int, unlabeledComparisons: Int,
    declaredSubjects: Int, declaredPhotoSessions: Int, unassignedRequests: Int,
    groupDeclarations: Int, unassignedResults: Int, plotAttachments: Int) {
    self.requests = requests; self.pending = pending; self.succeeded = succeeded; self.failed = failed
    self.cancelled = cancelled; self.skipped = skipped; self.unsupported = unsupported
    self.drawingResults = drawingResults; self.comparisons = comparisons; self.labelRevisions = labelRevisions
    self.ratedComparisonHeads = ratedComparisonHeads; self.skippedComparisonHeads = skippedComparisonHeads
    self.unlabeledComparisons = unlabeledComparisons; self.declaredSubjects = declaredSubjects
    self.declaredPhotoSessions = declaredPhotoSessions; self.unassignedRequests = unassignedRequests
    self.groupDeclarations = groupDeclarations; self.unassignedResults = unassignedResults; self.plotAttachments = plotAttachments
  }
}

public struct PortraitReviewDatasetPlot: Codable, Equatable, Sendable {
  public let origin: DrawingOriginReference
  public let producerArchiveID: UUID
  public let runID: UUID
  public let recordID: UUID
  public let recordSHA256: String
  public let attachmentSHA256: String
  public let mediaSHA256: [String]
  public init(attachment: PlotAttachment, attachmentSHA256: String) {
    origin = attachment.origin; producerArchiveID = attachment.producerArchiveID
    runID = attachment.runID; recordID = attachment.recordID; recordSHA256 = attachment.recordSHA256
    self.attachmentSHA256 = attachmentSHA256; mediaSHA256 = attachment.media.map(\.sha256)
  }
}

/// Exact byte replay/export. This manifest makes no claim of regeneration or human/model quality.
public struct PortraitReviewDatasetManifest: Codable, Equatable, Sendable {
  public let schemaVersion: Int
  public let exportedAt: Date
  public let groups: [PortraitReviewDatasetGroup]
  public let results: [PortraitReviewDatasetResult]
  public let records: [PortraitReviewDatasetRecord]
  public let files: [PortraitReviewDatasetFile]
  public let counts: PortraitReviewDatasetCounts
  public let plotOrigins: [PortraitReviewDatasetPlot]
  public let artifactDependencies: [PortraitReviewDatasetDependency]
  public let labelsAreExplicitHumanObservations: Bool
  public let splitPolicy: String
  public let replayMeaning: String

  public init(exportedAt: Date, groups: [PortraitReviewDatasetGroup],
    results: [PortraitReviewDatasetResult], records: [PortraitReviewDatasetRecord],
    files: [PortraitReviewDatasetFile], counts: PortraitReviewDatasetCounts,
    plotOrigins: [PortraitReviewDatasetPlot] = [],
    artifactDependencies: [PortraitReviewDatasetDependency] = []) throws {
    schemaVersion = 1; self.exportedAt = exportedAt; self.groups = groups
    self.results = results; self.records = records; self.files = files; self.counts = counts
    self.plotOrigins = plotOrigins
    self.artifactDependencies = artifactDependencies
    labelsAreExplicitHumanObservations = true
    splitPolicy = "Declared subject, photographic session, original source, capture, and ancestry connected components cannot cross assigned splits. Unknown groups remain unassigned."
    replayMeaning = "Exact retained bytes and metadata; not regeneration equivalence, photographic independence, model feasibility, or generalization proof."
    try validate()
  }

  public func validate() throws {
    guard schemaVersion == 1, exportedAt.timeIntervalSinceReferenceDate.isFinite,
      files.count <= 100_000, records.count <= 20_000, results.count <= 10_000,
      Set(files.map(\.path)).count == files.count,
      labelsAreExplicitHumanObservations else { throw DrawingTransferError.limit("Dataset manifest exceeds its supported limits.") }
    try PortraitReviewSplitValidation.validate(groups, dependencies: artifactDependencies)
    for dependency in artifactDependencies {
      guard results.contains(where: { $0.origin == dependency.origin && $0.sourceSHA256 == dependency.sourceSHA256 }) else {
        throw DrawingTransferError.invalid("Derived artifact ancestry has no exact retained source/result identity.")
      }
    }
    let hashes = Set(files.map(\.sha256))
    for file in files {
      guard PortraitReviewValidation.isHash(file.sha256), file.byteCount > 0,
        file.path == "assets/" + file.sha256, !file.mediaType.isEmpty else {
        throw DrawingTransferError.invalid("Dataset paths must be local content-addressed assets.")
      }
    }
    for record in records where !hashes.contains(record.fileSHA256) {
      throw DrawingTransferError.invalid("Dataset record bytes are missing: \(record.id).")
    }
    let byRequest = Dictionary(uniqueKeysWithValues: groups.map { ($0.requestID, $0) })
    for plot in plotOrigins {
      try plot.origin.validate()
      guard hashes.contains(plot.attachmentSHA256), hashes.contains(plot.recordSHA256),
        plot.mediaSHA256.allSatisfy({ hashes.contains($0) }),
        results.contains(where: { $0.origin == plot.origin }) else {
        throw DrawingTransferError.invalid("Optional plot provenance is missing exact attachment or original-media bytes.")
      }
    }
    for result in results {
      try result.origin.validate(); try result.material.validate()
      guard [result.packageSHA256, result.sourceSHA256, result.artistInputSHA256,
        result.previewSHA256, result.programSHA256, result.resultRecordSHA256,
        result.artistSettingsSHA256].allSatisfy({ hashes.contains($0) }) else {
        throw DrawingTransferError.invalid("A dataset result is missing exact source, program, settings, input, preview, or package bytes.")
      }
      if let id = result.requestID {
        guard let group = byRequest[id], result.split == group.split,
          result.sourceSHA256 == group.sourceSHA256, result.origin.captureID == group.captureID else {
          throw DrawingTransferError.invalid("Result split or capture conflicts with its generation request.")
        }
      } else if result.split != .unassigned {
        throw DrawingTransferError.invalid("Results with unknown generation groups remain unassigned.")
      }
    }
  }
}

/// A bounded feasibility protocol, frozen before outputs. It is not a training scheduler.
public struct PortraitReviewPilotSource: Codable, Equatable, Sendable {
  public let captureID: UUID
  public let acquisitionID: UUID?
  public let sourceSHA256: String
  public let groups: PortraitReviewGroups
  public let split: PortraitReviewDatasetSplit
  /// Source-dependent framing/material, frozen from source dimensions before inspecting output.
  public let material: PortraitReviewMaterial?
  public let conversionJSON: Data?
  public init(captureID: UUID, acquisitionID: UUID?, sourceSHA256: String,
    groups: PortraitReviewGroups, split: PortraitReviewDatasetSplit = .unassigned,
    material: PortraitReviewMaterial? = nil, conversionJSON: Data? = nil) {
    self.captureID = captureID; self.acquisitionID = acquisitionID; self.sourceSHA256 = sourceSHA256
    self.groups = groups; self.split = split
    self.material = material; self.conversionJSON = conversionJSON
  }
}

public struct PortraitReviewPilotArm: Codable, Equatable, Sendable {
  public let id: String
  public let artist: DrawingPackageArtist
  public let environmentJSON: Data
  public let conversionJSON: Data
  public let seed: UInt64?
  public let material: PortraitReviewMaterial
  public init(id: String, artist: DrawingPackageArtist, environmentJSON: Data,
    conversionJSON: Data, seed: UInt64?, material: PortraitReviewMaterial) {
    self.id = id; self.artist = artist; self.environmentJSON = environmentJSON
    self.conversionJSON = conversionJSON; self.seed = seed; self.material = material
  }
}

public struct PortraitReviewPilotManifest: Codable, Equatable, Identifiable, Sendable {
  public let schemaVersion: Int
  public let id: UUID
  public let createdAt: Date
  public let sources: [PortraitReviewPilotSource]
  public let arms: [PortraitReviewPilotArm]
  public let maximumJobs: Int
  public let purpose: String
  public let automaticTuningAllowed: Bool
  public init(id: UUID = UUID(), createdAt: Date = Date(), sources: [PortraitReviewPilotSource],
    arms: [PortraitReviewPilotArm]) throws {
    schemaVersion = 1; self.id = id; self.createdAt = createdAt; self.sources = sources; self.arms = arms
    maximumJobs = 18; purpose = "feasibility-only"; automaticTuningAllowed = false
    try validate()
  }
  public func validate() throws {
    guard schemaVersion == 1, (1...6).contains(sources.count), arms.count == 3, maximumJobs == 18,
      purpose == "feasibility-only", !automaticTuningAllowed,
      createdAt.timeIntervalSinceReferenceDate.isFinite,
      Set(sources.map(\.captureID)).count == sources.count, Set(arms.map(\.id)).count == 3 else {
      throw DrawingTransferError.invalid("A feasibility pilot freezes up to six capture occurrences and three fixed arms, at most 18 jobs including retries.")
    }
    try PortraitReviewSplitValidation.validate(sources.map {
      .init(requestID: $0.captureID, captureID: $0.captureID, acquisitionID: $0.acquisitionID,
        sourceSHA256: $0.sourceSHA256, groups: $0.groups, split: $0.split)
    })
    for source in sources {
      try source.material?.validate()
      if let bytes = source.conversionJSON {
        guard bytes.count <= 1024 * 1024 else { throw DrawingTransferError.limit("Pilot source transform exceeds its limit.") }
        try DrawingPackageCodec.validateJSON(bytes)
      }
    }
    for arm in arms {
      try arm.material.validate()
      guard !arm.id.isEmpty, arm.id.utf8.count <= 256,
        !arm.artist.identifier.isEmpty, !arm.artist.revision.isEmpty else {
        throw DrawingTransferError.invalid("Pilot arm identity is invalid.")
      }
      for data in [arm.artist.settingsJSON, arm.environmentJSON, arm.conversionJSON] {
        guard data.count <= 1024 * 1024 else { throw DrawingTransferError.limit("Pilot settings exceed their limit.") }
        try DrawingPackageCodec.validateJSON(data)
      }
    }
  }
}
