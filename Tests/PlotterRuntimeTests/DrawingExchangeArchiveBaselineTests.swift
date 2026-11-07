import CryptoKit
import Darwin
import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

@Suite("Drawing Exchange legacy archive baseline", .serialized)
struct DrawingExchangeArchiveBaselineTests {
  private struct Seed: Codable { let record: DrawingRunEvidenceRecord; let intent: DrawingRunIntent; let baseline: DrawingRunMediaReference }
  private struct Times: Decodable { let records: [Date]; let attempts: [Date] }
  private struct Envelope: Codable { let schemaVersion: UInt16; let payload: Data; let payloadSHA256: String }

  @Test("prepare or read frozen legacy evidence without mutating it", .enabled(if:
    ProcessInfo.processInfo.environment["DX_ARCHIVE_ROOT"] != nil))
  func archive() async throws {
    let env = ProcessInfo.processInfo.environment
    let root = URL(fileURLWithPath: try #require(env["DX_ARCHIVE_ROOT"]))
    try #require(root.path.hasPrefix("/tmp/adaptiveplotter-dx01-") || root.path.hasPrefix("/private/tmp/adaptiveplotter-dx01-"))
    let phase = env["DX_BASELINE_PHASE"] ?? "read"
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    if phase == "seed" {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      try encoder.encode(makeSeed()).write(to: root.appendingPathComponent("archive-seed.json"))
      return
    }
    let url = root.appendingPathComponent("legacy.json")
    if phase == "prepare" {
      try #require(!FileManager.default.fileExists(atPath: root.path))
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      let seed = try JSONDecoder().decode(Seed.self, from: Data(contentsOf:
        URL(fileURLWithPath: try #require(env["DX_ARCHIVE_SEED"]))))
      let count = Int(env["DX_ARCHIVE_RECORDS"] ?? "100")!
      let interrupted = Int(env["DX_ARCHIVE_INTERRUPTED"] ?? "10")!
      let times = try JSONDecoder().decode(Times.self, from: Data(contentsOf:
        URL(fileURLWithPath: try #require(env["DX_ARCHIVE_TIMES"]))))
      try #require(times.records.count == count && times.attempts.count == interrupted)
      // RuntimeTimestamp otherwise defaults its wallTime to Date(). These
      // captured binary64 reference-date values preserve the original corpus.
      let start = ProcessInfo.processInfo.systemUptime
      let records = try (0..<count).map { n in
        let s = seed.record
        return try DrawingRunEvidenceRecord(recordID: .init(uuid(n + 1)), runID: .init(uuid(n + 1_000_001)),
          requestID: uuid(n + 2_000_001), role: s.role, evidenceDisposition: s.evidenceDisposition,
          requestFrontier: s.requestFrontier, executionFrontiers: s.executionFrontiers,
          executionDisposition: s.executionDisposition, program: s.program, placement: s.placement,
          plan: s.plan, planningProvenance: s.planningProvenance, tipCalibration: s.tipCalibration,
          paper: s.paper, observation: s.observation, recordedAt: .init(monotonicNanoseconds: UInt64(n + 4), wallTime: times.records[n]))
      }
      let attempts = try (0..<interrupted).map { n in
        let s = seed.intent
        let intent = try DrawingRunIntent(runID: .init(uuid(n + 3_000_001)), requestID: uuid(n + 4_000_001),
          plan: s.plan, placementID: s.placementID, role: s.role, context: s.context,
          recordedAt: .init(monotonicNanoseconds: UInt64(n + 1), wallTime: times.attempts[n]))
        return DrawingRunAttemptState(intent: intent, baselines: [seed.baseline], inkDispatchPossible: n % 2 == 0)
      }
      let archive = try DrawingRunEvidenceArchive(archiveID: uuid(9_000_001), revision: UInt64(count),
        records: records, attempts: attempts)
      let payload = try encoder.encode(archive)
      let envelope = Envelope(schemaVersion: 1, payload: payload, payloadSHA256: digest(payload))
      try encoder.encode(envelope).write(to: url)
      func installPixels(for archiveName: String) throws {
        let media = root.appendingPathComponent(archiveName + ".media")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        try Data(repeating: 240, count: 640 * 480)
          .write(to: media.appendingPathComponent(seed.baseline.frame.frameSHA256 + ".pixels"))
      }
      try installPixels(for: "legacy.json")
      // Existing whole-archive snapshots, deliberately not the future exchange chain.
      for (name, length) in [("snapshot-early.json", min(10, count)), ("snapshot-middle.json", count / 2)] {
        let snapshot = try DrawingRunEvidenceArchive(archiveID: archive.archiveID,
          revision: UInt64(length), records: Array(records.prefix(length)), attempts: attempts)
        let bytes = try encoder.encode(snapshot)
        try encoder.encode(Envelope(schemaVersion: 1, payload: bytes, payloadSHA256: digest(bytes)))
          .write(to: root.appendingPathComponent(name))
        try installPixels(for: name)
      }
      try encoder.encode(["legacySHA256": digest(try Data(contentsOf: url))])
        .write(to: root.appendingPathComponent("selection.json"))
      try output(["phase": phase, "legacyTerminalRecords": count, "interruptedAttempts": interrupted,
        "possibleInkInterruptedAttempts": (interrupted + 1) / 2, "sharedRawFrameBytes": 640 * 480,
        "payloadBytes": payload.count, "legacySHA256": digest(try Data(contentsOf: url)),
        "prepareMS": (ProcessInfo.processInfo.systemUptime - start) * 1000], env)
      return
    }
    if phase == "negative" {
      let copy = root.appendingPathComponent("negative.json")
      defer { try? FileManager.default.removeItem(at: copy) }
      let bytes = try Data(contentsOf: url)
      let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
      try encoder.encode(Envelope(schemaVersion: 1, payload: Data("corrupt payload".utf8),
        payloadSHA256: envelope.payloadSHA256)).write(to: copy)
      guard case .rejected(.integrityMismatch) = DrawingRunEvidenceStore(fileURL: copy).loadSnapshot() else {
        Issue.record("Corrupt claimed payload must fail integrity admission"); return
      }
      try FileManager.default.removeItem(at: copy)
      guard case .absent = DrawingRunEvidenceStore(fileURL: copy).loadSnapshot() else {
        Issue.record("Missing archive must remain absent"); return
      }
      let mediaCopy = root.deletingLastPathComponent().appendingPathComponent("negative-media-" + UUID().uuidString)
      try FileManager.default.copyItem(at: root, to: mediaCopy)
      defer { try? FileManager.default.removeItem(at: mediaCopy) }
      let mediaDirectory = mediaCopy.appendingPathComponent("legacy.json.media")
      let pixel = try #require(FileManager.default.contentsOfDirectory(at: mediaDirectory,
        includingPropertiesForKeys: nil).first)
      try Data("corrupt claimed pixels".utf8).write(to: pixel)
      guard case .rejected(.invalidMedia) = DrawingRunEvidenceStore(fileURL: mediaCopy.appendingPathComponent("legacy.json")).loadSnapshot() else {
        Issue.record("Corrupt claimed raw pixels must fail"); return
      }
      try FileManager.default.removeItem(at: pixel)
      guard case .rejected(.invalidMedia) = DrawingRunEvidenceStore(fileURL: mediaCopy.appendingPathComponent("legacy.json")).loadSnapshot() else {
        Issue.record("Missing claimed raw pixels must fail"); return
      }
      #expect(try Data(contentsOf: url) == bytes)
      try output(["phase": phase, "corruptPayloadRejected": true, "missingArchiveAbsent": true,
        "corruptRawPixelsRejected": true, "missingRawPixelsRejected": true,
        "legacyExactBytesPreserved": true], env)
      return
    }
    let trials = Int(env["DX_BASELINE_TRIALS"] ?? "30")!
    let selection = try JSONDecoder().decode([String: String].self,
      from: Data(contentsOf: root.appendingPathComponent("selection.json")))
    let before = try #require(selection["legacySHA256"])
    let store = DrawingRunEvidenceStore(fileURL: url)
    if trials > 1 { guard case .loaded = store.loadSnapshot() else { Issue.record("Warmup rejected corpus"); return } }
    var times: [Double] = [], recordCount = 0, attemptCount = 0
    for trial in 0..<trials {
      let start = ProcessInfo.processInfo.systemUptime
      guard case .loaded(let archive) = store.loadSnapshot() else { Issue.record("Rejected frozen legacy corpus"); return }
      times.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
      recordCount = archive.records.count; attemptCount = archive.attempts.count
      if env["DX_BASELINE_PROGRESS"] == "1" {
        let marker = "DX01_ARCHIVE_TRIAL index=\(trial) total=\(trials) milliseconds=\(times.last!) records=\(recordCount) attempts=\(attemptCount)\n"
        FileHandle.standardOutput.write(Data(marker.utf8))
      }
    }
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    try output(["phase": phase, "operation": "legacy-loadSnapshot", "milliseconds": times,
      "legacyTerminalRecords": recordCount, "interruptedAttempts": attemptCount,
      "processPeakRSSBytes": usage.ru_maxrss, "legacySHA256": before,
      "mallocSnapshot": dx01RawMallocSnapshot(),
      "cache": trials == 1 ? "process-cold; filesystem cache uncontrolled" : "one warm-up; filesystem cache uncontrolled",
      "queryCount": NSNull(), "decodeCount": NSNull(), "allocations": NSNull(),
      "readBytes": NSNull(), "writeBytes": NSNull(),
      "counterScope": "actor counters do not instrument nonisolated loadSnapshot; zero is not zero I/O proof",
      "mediaBytesVerifiedCounter": await store.mediaBytesVerified,
      "componentBytesEncodedCounter": await store.componentBytesEncoded], env)
  }

  private func makeSeed() throws -> Seed {
    let authority = try TipAuthorityFixture(), registration = try authority.registration()
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(uuid(90)))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 0, y: 0), machineAnchor: Point2(x: 0, y: 0), uniformScale: 1)
    let hash = try DrawingMaterialApplicability.registrationHash(registration)
    let bytes = stride(from: 0, to: hash.count, by: 2).map { UInt8(hash.dropFirst($0).prefix(2), radix: 16)! }
    let provenance = DrawingPlanningProvenance(modelRevisionID: DrawingModelRevisionID(registration.acceptedRevisionID.rawValue),
      modelContentHash: try Digest(bytes: bytes), registrationRevisionID: DrawingRegistrationRevisionID(registration.acceptedRevisionID.rawValue),
      registrationContentHash: try Digest(bytes: bytes))
    let plan = try DrawingPlanner.plan(program: program, placement: placement,
      drawableRegion: DrawableMachineRegion(bounds: AxisAlignedBounds(minX: 0, minY: 0, maxX: 200, maxY: 200)), provenance: provenance)
    let context = try DrawingRunAttemptContext(program: program, registration: registration, paperStock: "DX01 synthetic stock",
      drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults,
      paper: PaperRevisionContext(instance: PaperInstanceRevision(), contactPlane: authority.paper))
    let intent = try DrawingRunIntent(runID: RunID(uuid(91)), requestID: uuid(92), plan: plan, placementID: uuid(93),
      role: .ordinaryDrawing, context: context, recordedAt: .init(monotonicNanoseconds: 1))
    let record = try DrawingRunEvidenceRecord(recordID: .init(uuid(94)), runID: intent.runID, requestID: intent.requestID,
      role: .ordinaryDrawing, evidenceDisposition: .cancelled, requestFrontier: .admitted,
      executionFrontiers: .init(plannedStrokeCount: UInt32(plan.strokes.count), commandedStrokeCount: 1,
        controllerCompletedStrokeCount: 0, inkVerifiedStrokeCount: 0), executionDisposition: .cancelled(reason: "Synthetic operator stop"),
      program: .init(program: program), placement: .init(placementID: intent.placementID, placement: placement),
      plan: .init(plan: plan), planningProvenance: provenance,
      tipCalibration: .init(acceptedRevisionID: registration.acceptedRevisionID,
        registrationEvidenceSHA256: hash, applicability: registration.applicability, estimatorRevision: registration.estimatorRevision),
      paper: context.paper, observation: .notAttempted(.executionCancelledBeforeObservation), recordedAt: .init(monotonicNanoseconds: 4))
    let frame = try StampedFrame(sequence: 1, captureNanoseconds: 2,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes(Array(repeating: 240, count: 640 * 480)))
    return Seed(record: record, intent: intent, baseline: DrawingRunMediaReference(frame: frame, source: authority.source))
  }
  private func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "73010001-0000-0000-0000-%012llx", Int64(n)))! }
  private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
  private func output(_ object: [String: Any], _ env: [String: String]) throws {
    var reported = object
    if object["mallocSnapshot"] != nil { reported["mallocSnapshotScope"] = "all process malloc zones after timing; live state and sum of zone highwater touched bytes; not cumulative allocation events, simultaneous peak, RSS, VM or cache memory" }
    let data = try JSONSerialization.data(withJSONObject: reported, options: [.prettyPrinted, .sortedKeys])
    if let path = env["DX_BASELINE_OUTPUT"] { try data.write(to: URL(fileURLWithPath: path), options: .atomic) }
    print("DX01_ARCHIVE " + String(decoding: data, as: UTF8.self))
  }
}

// Separate test target: the app-test helper cannot be imported here. Public
// all-zone snapshot is not cumulative allocation events, VM bytes or RSS.
private func dx01RawMallocSnapshot() -> [String: UInt64] {
  var stats = malloc_statistics_t(); malloc_zone_statistics(nil, &stats)
  return ["liveAllZoneMallocBlocks": UInt64(stats.blocks_in_use),
    "liveAllZoneMallocBytes": UInt64(stats.size_in_use),
    "sumZoneHighwaterTouchedBytes": UInt64(stats.max_size_in_use),
    "allZoneMallocReservedBytes": UInt64(stats.size_allocated)]
}
