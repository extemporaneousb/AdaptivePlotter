import Foundation
import PlotterModel
import PlotterRuntime

/// Read-only decoder. It does not initialize the App or invoke the raw archive
/// writer's migration/repair paths, and missing pixels do not reject a valid run.
struct PortraitEvidenceSource {
  let archive: DrawingRunEvidenceArchive
  let sha256: String
  let selectedFiles: [URL: String]

  struct StagedAttemptProof {
    let generation: String
    let manifestURL: URL
    let componentURL: URL
    let componentSHA256: String

    func assertUnchanged() throws {
      guard try PortraitCandidateCoding.digest(Data(contentsOf:manifestURL)) == generation,
        try PortraitCandidateCoding.digest(Data(contentsOf:componentURL)) == componentSHA256 else { throw PortraitLibraryError.staleGeneration }
    }
  }

  /// The raw owner already staged this typed archive. Pre-motion retention
  /// verifies its exact current attempt and manifest, without decoding any
  /// other historical record, attempt, media or calibration component.
  static func proveStagedAttempt(_ intent:DrawingRunIntent,archive:DrawingRunEvidenceArchive,url:URL,
    generation:String? = nil) throws -> StagedAttemptProof {
    struct Envelope:Decodable { let schemaVersion:Int;let payloadSHA256:String;let payload:Data }
    struct Reference:Decodable { let id:UUID;let sha256:String }
    struct Manifest:Decodable { let archiveID:UUID;let revision:UInt64;let attempts:[Reference] }
    let bytes = try Data(contentsOf:url),hash = PortraitCandidateCoding.digest(bytes)
    let envelope = try JSONDecoder().decode(Envelope.self,from:bytes)
    guard [2,3].contains(envelope.schemaVersion),PortraitCandidateCoding.digest(envelope.payload) == envelope.payloadSHA256,
      generation == nil || generation == hash else { throw PortraitLibraryError.staleGeneration }
    let manifest = try JSONDecoder().decode(Manifest.self,from:envelope.payload)
    guard manifest.archiveID == archive.archiveID,manifest.revision == archive.revision,
      Set(manifest.attempts.map(\.id)).count == manifest.attempts.count,
      let reference = manifest.attempts.first(where:{$0.id == intent.runID.rawValue}),
      let supplied = archive.attempts.first(where:{$0.intent.runID == intent.runID}),supplied.intent == intent else {
      throw PortraitLibraryError.unresolvedLineage("current staged intent is unavailable")
    }
    let actual = try component(DrawingRunAttemptState.self,hash:reference.sha256,url:url)
    guard actual == supplied,actual.intent == intent else { throw PortraitLibraryError.unresolvedLineage("current staged attempt differs from the raw publisher") }
    let proof = StagedAttemptProof(generation:hash,manifestURL:url,
      componentURL:url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent+".records").appendingPathComponent(reference.sha256+".json"),
      componentSHA256:reference.sha256)
    try proof.assertUnchanged()
    return proof
  }
  static func envelopeVersion(_ url:URL) throws -> Int {
    struct Version:Decodable { let schemaVersion:Int }
    return try JSONDecoder().decode(Version.self,from:Data(contentsOf:url)).schemaVersion
  }
  static func componentHashes(_ url:URL) throws -> (records:[UUID:String],attempts:[UUID:String]) {
    struct Envelope: Decodable { let schemaVersion:Int;let payload:Data;let payloadSHA256:String }
    struct Reference: Decodable { let id:UUID;let sha256:String }
    struct Manifest: Decodable { let records:[Reference];let attempts:[Reference] }
    let envelope = try JSONDecoder().decode(Envelope.self,from:Data(contentsOf:url))
    guard [2,3].contains(envelope.schemaVersion),PortraitCandidateCoding.digest(envelope.payload) == envelope.payloadSHA256 else { throw PortraitLibraryError.database("component manifest unavailable") }
    let manifest = try JSONDecoder().decode(Manifest.self,from:envelope.payload)
    guard Set(manifest.records.map(\.id)).count == manifest.records.count,Set(manifest.attempts.map(\.id)).count == manifest.attempts.count else { throw PortraitLibraryError.database("duplicate raw component identity") }
    return (Dictionary(uniqueKeysWithValues:manifest.records.map{($0.id,$0.sha256)}),Dictionary(uniqueKeysWithValues:manifest.attempts.map{($0.id,$0.sha256)}))
  }
  static func component<T:Decodable>(_ type:T.Type,hash:String,url:URL) throws -> T {
    guard hash.count == 64,hash.allSatisfy(\.isHexDigit) else { throw PortraitLibraryError.database("invalid raw component hash") }
    let file = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".records").appendingPathComponent(hash + ".json")
    let bytes = try Data(contentsOf:file)
    guard PortraitCandidateCoding.digest(bytes) == hash else { throw PortraitLibraryError.database("raw component checksum invalid") }
    return try JSONDecoder().decode(type,from:bytes)
  }
  static func verifySelection(_ archive: DrawingRunEvidenceArchive, url: URL,
    recordHashes: [UUID:String], attemptHashes: [UUID:String]) throws -> String {
    struct Envelope: Decodable { let schemaVersion: Int; let payloadSHA256: String; let payload: Data }
    struct Reference: Decodable { let id: UUID; let sha256: String }
    struct Manifest: Decodable {
      let archiveID: UUID; let revision: UInt64
      let records: [Reference]; let attempts: [Reference]
      let deletedReviewRecordIDs: [DrawingEvidenceRecordID]
      let dismissedReviewRunIDs: [RunID]?
      let reviewNotes: [DrawingReviewNote]?
    }
    let bytes = try Data(contentsOf:url), envelope = try JSONDecoder().decode(Envelope.self,from:bytes)
    guard PortraitCandidateCoding.digest(envelope.payload) == envelope.payloadSHA256 else { throw PortraitLibraryError.staleGeneration }
    if envelope.schemaVersion == 1 {
      guard try JSONDecoder().decode(DrawingRunEvidenceArchive.self,from:envelope.payload) == archive else { throw PortraitLibraryError.staleGeneration }
    } else {
      guard [2,3].contains(envelope.schemaVersion) else { throw PortraitLibraryError.staleGeneration }
      let manifest = try JSONDecoder().decode(Manifest.self,from:envelope.payload)
      guard manifest.archiveID == archive.archiveID,manifest.revision == archive.revision,
        manifest.records.count == recordHashes.count,manifest.attempts.count == attemptHashes.count,
        manifest.records.allSatisfy({recordHashes[$0.id] == $0.sha256}),
        manifest.attempts.allSatisfy({attemptHashes[$0.id] == $0.sha256}),
        manifest.deletedReviewRecordIDs == archive.deletedReviewRecordIDs,
        manifest.dismissedReviewRunIDs ?? [] == archive.dismissedReviewRunIDs,
        manifest.reviewNotes ?? [] == archive.reviewNotes else { throw PortraitLibraryError.staleGeneration }
    }
    guard try Data(contentsOf:url) == bytes else { throw PortraitLibraryError.staleGeneration }
    return PortraitCandidateCoding.digest(bytes)
  }
  static func read(_ url: URL) throws -> Self {
    struct Envelope: Decodable { let schemaVersion: Int; let payloadSHA256: String; let payload: Data }
    let bytes = try Data(contentsOf:url)
    let envelope = try JSONDecoder().decode(Envelope.self,from:bytes)
    guard [1,2,3].contains(envelope.schemaVersion),PortraitCandidateCoding.digest(envelope.payload) == envelope.payloadSHA256 else { throw PortraitLibraryError.database("raw evidence checksum/schema invalid") }
    var files = [url:PortraitCandidateCoding.digest(bytes)]
    let archive: DrawingRunEvidenceArchive
    if envelope.schemaVersion == 1 { archive = try JSONDecoder().decode(DrawingRunEvidenceArchive.self,from:envelope.payload) }
    else {
      struct Reference: Decodable { let id:UUID;let sha256:String }
      struct Manifest: Decodable {
        let archiveID:UUID;let revision:UInt64
        let records:[Reference];let attempts:[Reference]
        let deletedReviewRecordIDs:[DrawingEvidenceRecordID]?
        let dismissedReviewRunIDs:[RunID]?;let reviewNotes:[DrawingReviewNote]?
        let noInkConfirmations:[DrawingRunNoInkConfirmation]?
        let axisMetricMeasurements:[Reference]?;let axisCalibrationAttempts:[Reference]?;let axisCalibrationTerminals:[Reference]?
      }
      let manifest = try JSONDecoder().decode(Manifest.self,from:envelope.payload)
      func selected<T:Decodable>(_ references:[Reference],as type:T.Type,identity:(T)->UUID) throws -> [T] {
        try references.map { reference in
          let value = try component(type,hash:reference.sha256,url:url)
          guard identity(value) == reference.id else { throw PortraitLibraryError.database("raw component identity mismatch") }
          let file = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".records").appendingPathComponent(reference.sha256 + ".json")
          files[file] = reference.sha256
          return value
        }
      }
      let records = try selected(manifest.records,as:DrawingRunEvidenceRecord.self,identity:{$0.recordID.rawValue})
      let attempts = try selected(manifest.attempts,as:DrawingRunAttemptState.self,identity:{$0.intent.runID.rawValue})
      let measurements = try selected(manifest.axisMetricMeasurements ?? [],as:ControllerAxisMetricMeasurement.self,identity:{$0.measurementID})
      let calibrationAttempts = try selected(manifest.axisCalibrationAttempts ?? [],as:ControllerAxisCalibrationAttempt.self,identity:{$0.proposal.proposalID})
      let calibrationTerminals = try selected(manifest.axisCalibrationTerminals ?? [],as:ControllerAxisCalibrationTerminal.self,identity:{$0.proposalID})
      // The modern wire format is a component manifest, not an encoded archive.
      // Use the same validated public constructor as the Runtime archive owner.
      archive = try DrawingRunEvidenceArchive(archiveID:manifest.archiveID,revision:manifest.revision,
        records:records,attempts:attempts,deletedReviewRecordIDs:manifest.deletedReviewRecordIDs ?? [],
        dismissedReviewRunIDs:manifest.dismissedReviewRunIDs ?? [],reviewNotes:manifest.reviewNotes ?? [],
        noInkConfirmations:manifest.noInkConfirmations ?? [],axisMetricMeasurements:measurements,
        axisCalibrationAttempts:calibrationAttempts,axisCalibrationTerminals:calibrationTerminals)
    }
    for (file,hash) in files {
      guard PortraitCandidateCoding.digest(try Data(contentsOf:file)) == hash else { throw PortraitLibraryError.staleGeneration }
    }
    return .init(archive:archive,sha256:files[url]!,selectedFiles:files)
  }
}
