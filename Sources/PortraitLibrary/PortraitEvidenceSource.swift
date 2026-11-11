import Foundation
import PortraitCore
import PlotterModel
import PlotterRuntime

/// Exact current staged proof only. No historical library reader or migration.
package struct PortraitEvidenceSource {
  package struct StagedAttemptProof {
    package let generation: String
    package let manifestURL: URL
    package let componentURL: URL
    package let componentSHA256: String

    package func assertUnchanged() throws {
      guard try DrawingArtifactCoding.sha256(Data(contentsOf:manifestURL)) == generation,
        try DrawingArtifactCoding.sha256(Data(contentsOf:componentURL)) == componentSHA256 else { throw DrawingExchangeError.mismatchedParent }
    }

    package init(generation: String, manifestURL: URL, componentURL: URL, componentSHA256: String) {
      self.generation = generation
      self.manifestURL = manifestURL
      self.componentURL = componentURL
      self.componentSHA256 = componentSHA256
    }
  }

  /// The raw owner already staged this typed archive. Pre-motion retention
  /// verifies its exact current attempt and manifest, without decoding any
  /// other historical record, attempt, media or calibration component.
  package static func proveStagedAttempt(_ intent:DrawingRunIntent,archive:DrawingRunEvidenceArchive,url:URL,
    generation:String? = nil) throws -> StagedAttemptProof {
    struct Envelope:Decodable { let schemaVersion:Int;let payloadSHA256:String;let payload:Data }
    struct Reference:Decodable { let id:UUID;let sha256:String }
    struct Manifest:Decodable { let archiveID:UUID;let revision:UInt64;let attempts:[Reference] }
    let bytes = try Data(contentsOf:url),hash = DrawingArtifactCoding.sha256(bytes)
    let envelope = try JSONDecoder().decode(Envelope.self,from:bytes)
    guard [2,3,4].contains(envelope.schemaVersion),DrawingArtifactCoding.sha256(envelope.payload) == envelope.payloadSHA256,
      generation == nil || generation == hash else { throw DrawingExchangeError.mismatchedParent }
    let manifest = try JSONDecoder().decode(Manifest.self,from:envelope.payload)
    guard manifest.archiveID == archive.archiveID,manifest.revision == archive.revision,
      Set(manifest.attempts.map(\.id)).count == manifest.attempts.count,
      let reference = manifest.attempts.first(where:{$0.id == intent.runID.rawValue}),
      let supplied = archive.attempts.first(where:{$0.intent.runID == intent.runID}),supplied.intent == intent else {
      throw DrawingExchangeError.malformed("current staged intent is unavailable")
    }
    let actual = try component(DrawingRunAttemptState.self,hash:reference.sha256,url:url)
    guard actual == supplied,actual.intent == intent else { throw DrawingExchangeError.malformed("current staged attempt differs from the raw publisher") }
    let proof = StagedAttemptProof(generation:hash,manifestURL:url,
      componentURL:url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent+".records").appendingPathComponent(reference.sha256+".json"),
      componentSHA256:reference.sha256)
    try proof.assertUnchanged()
    return proof
  }
  package static func component<T:Decodable>(_ type:T.Type,hash:String,url:URL) throws -> T {
    guard hash.count == 64,hash.allSatisfy(\.isHexDigit) else { throw DrawingExchangeError.malformed("invalid raw component hash") }
    let file = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + ".records").appendingPathComponent(hash + ".json")
    let bytes = try Data(contentsOf:file)
    guard DrawingArtifactCoding.sha256(bytes) == hash else { throw DrawingExchangeError.malformed("raw component checksum invalid") }
    return try JSONDecoder().decode(type,from:bytes)
  }
}
