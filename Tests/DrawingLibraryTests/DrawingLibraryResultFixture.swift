import Foundation
import PortraitCore
import PlotterModel

/// Fresh current-format testimony only. No native payload validator is installed:
/// the synthetic owner bytes prove closure/integrity, never physical conclusions.
struct DrawingLibraryResultFixture {
  var payload: [String: Data]
  var index: [String: Any]
  let frozen: FrozenDrawingRecord
  let job: JobReceiptRef
  let snapshots: [SnapshotRef]
  let media: ExchangeAsset

  static func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
  }
  static func wire<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value))
  }
  static func drawing() throws -> FrozenDrawingRecord {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let value = try Drawing(program: program, input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.dx06", version: "1", recordJSON: Data("{\"profile\":\"example.dx06-producer/1\"}".utf8)))
    return try DrawingExchangeCodec.freeze(value, identity: .init(issuer: UUID()),
      createdAt: Date(timeIntervalSince1970: 1_800_000_000))
  }
  init(drawing: FrozenDrawingRecord? = nil, count: Int = 3, refused: Bool = false,
       includeRefusedAttempts: Bool = false, features: [String] = [], marker: String = "first", jobID: JobRef? = nil,
       archive: UUID = UUID(), run: UUID = UUID(), changedSequence: Int? = nil) throws {
    let frozen = try drawing ?? Self.drawing()
    self.frozen = frozen
    var files: [String: Data] = [:]
    var descriptors: [ExchangeAssetDescriptor] = []
    func asset(_ bytes: Data, encoding: String = "utf8-json", mediaType: String = "application/json") throws -> ExchangeAsset {
      let value = try ExchangeAsset(bytes: bytes, mediaType: mediaType, encoding: encoding)
      files["data/objects/sha256/" + value.object.description] = bytes
      descriptors.append(.init(asset: value))
      return value
    }
    _ = try asset(frozen.originalProgramJSON, encoding: DrawingExchangeCodec.strokeProfile)
    _ = try asset(frozen.drawing.producer.originalJSON)
    let drawingRef = frozen.reference
    files["data/drawings/\(drawingRef.issuer.uuidString.lowercased())/\(drawingRef.revision.uuidString.lowercased())/drawing.json"] = frozen.originalJSON
    let plan = try asset(Self.json(["profile": "example.dx06-plan/1", "marker": marker]), encoding: "example.dx06-plan/1")
    let options = try asset(Self.json(["profile": "example.dx06-options/1"]), encoding: "example.dx06-options/1")
    let media = try asset(Data("synthetic media \(marker)".utf8), encoding: "opaque", mediaType: "application/octet-stream")
    self.media = media
    let handle = jobID ?? JobRef(engine: UUID(), job: UUID())
    var receipt: [String: Any] = ["profile": "adaptiveplotter.plot-job-receipt/1", "requiredFeatures": [String](),
      "handle": try Self.wire(handle), "client": ["namespace": UUID().uuidString.lowercased(), "request": UUID().uuidString.lowercased(), "requestDigest": ExchangeDigest.hash(Data(marker.utf8)).description],
      "drawing": try Self.wire(drawingRef), "preparedPlan": try Self.wire(plan), "requestedMediumOptions": try Self.wire(options),
      "issuedAt": try Self.wire(ExchangeTimestamp(wallTime: "2027-01-15T08:00:00Z")), "disposition": refused ? "refused" : "accepted", "reason": marker]
    if !refused { receipt["issuance"] = UUID().uuidString.lowercased() }
    let receiptBytes = try Self.json(receipt)
    let job = JobReceiptRef(handle: handle, receiptDigest: .hash(receiptBytes))
    self.job = job
    files["data/jobs/\(handle.engine.uuidString.lowercased())/\(handle.job.uuidString.lowercased())/receipt.json"] = receiptBytes
    let intent = try asset(Self.json(["profile": "example.dx06-intent/1", "marker": marker]), encoding: "example.dx06-intent/1")
    let unavailable: [String: Any] = ["kind": "example.frontier/1", "status": "unavailable", "reason": "Synthetic fixture supplies no physical proof"]
    let coverage = try asset(Self.json(["profile": "adaptiveplotter.coverage/1", "requiredFeatures": [String](), "includedAsOf": try Self.wire(ExchangeTimestamp(wallTime: "2027-01-15T08:00:00Z")),
      "entries": [["kind": "example.media/1", "status": "present", "asset": try Self.wire(media)]],
      "frontiers": Dictionary(uniqueKeysWithValues: ["planned", "commanded", "controllerCompleted", "inkVerified"].map { ($0, unavailable) })]))
    var refs: [SnapshotRef] = []
    if (!refused || includeRefusedAttempts) && count > 0 {
      for sequence in 1...count {
        var snapshot: [String: Any] = ["profile": "adaptiveplotter.plot-attempt/1", "requiredFeatures": [String](),
          "issuerArchive": archive.uuidString.lowercased(), "run": run.uuidString.lowercased(), "sequence": sequence,
          "previous": refs.last.map { $0.digest.description as Any } ?? NSNull(), "sealed": false,
          "drawing": try Self.wire(drawingRef), "job": try Self.wire(job), "environment": "simulation",
          "intent": intent.object.description, "coverage": coverage.object.description, "state": "running",
          "dispatch": "not-dispatched", "observation": "unavailable", "terminalRecord": NSNull(), "assessments": [String](), "plan": try Self.wire(plan)]
        if sequence == changedSequence { snapshot["fixtureExtension"] = "divergent immutable snapshot" }
        let bytes = try Self.json(snapshot)
        let ref = try SnapshotRef(archive: archive, run: run, sequence: UInt64(sequence), digest: .hash(bytes))
        refs.append(ref)
        files[Self.snapshotPath(ref)] = bytes
      }
    }
    snapshots = refs
    index = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": features, "kind": "result",
      "roots": try Self.wire([drawingRef]), "jobs": try Self.wire([job]), "attempts": try Self.wire(Array(refs.suffix(1))),
      "assessments": [String](), "assets": try Self.wire(descriptors), "includedAsOf": "2027-01-15T08:00:00Z", "fixtureExtension": marker]
    payload = files
  }
  static func snapshotPath(_ ref: SnapshotRef) -> String {
    "data/attempts/\(ref.archive.uuidString.lowercased())/\(ref.run.uuidString.lowercased())/\(ref.sequence)/attempt.json"
  }
  /// Rewrites only the advertised tip and its pin, preserving every earlier
  /// immutable sequence. Used for valid divergence and malformed binding cases.
  mutating func rewriteTip(_ edit: (inout [String: Any]) throws -> Void) throws {
    guard let old = snapshots.last, let bytes = payload[Self.snapshotPath(old)],
      var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
      throw DrawingExchangeError.malformed("Fixture has no tip")
    }
    try edit(&object)
    let updated = try Self.json(object)
    payload[Self.snapshotPath(old)] = updated
    let ref = try SnapshotRef(archive: old.archive, run: old.run, sequence: old.sequence, digest: .hash(updated))
    index["attempts"] = try Self.wire([ref])
  }
  func write(to directory: URL) throws {
    var files = payload
    files["data/exchange.json"] = try Self.json(index)
    files["bagit.txt"] = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    files["manifest-sha256.txt"] = Data(files.keys.filter { $0.hasPrefix("data/") }.sorted().map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    files["tagmanifest-sha256.txt"] = Data(["bagit.txt", "manifest-sha256.txt"].map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    for (path, bytes) in files {
      let target = directory.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target)
    }
  }
  static func bytes(_ package: ValidatedExchangePackage) throws -> [String: Data] {
    try Dictionary(uniqueKeysWithValues: package.files.entries.keys.sorted().map { ($0, try package.files.record(at: $0)) })
  }
}
