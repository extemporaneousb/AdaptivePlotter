import Foundation
import Darwin
import DrawingLibrary
import PortraitCore
import PlotterModel
import PlotterRuntime

/// Read-only export through the same raw owner. No stage, Start or retry port.
public protocol DrawingDestinationResultSource: Sendable {
  func exportAttempt(runID: RunID) async throws -> DrawingRunAttemptExport
}
extension DrawingRunEvidenceStore: DrawingDestinationResultSource {}

struct DrawingPublishedResult: Codable, Equatable, Sendable {
  let content: ExchangeDigest
  let reference: DrawingLibraryResultRef
  let snapshot: SnapshotRef
  let fileName: String
  let sealed: Bool
}

/// Native codecs interpret existing raw bytes; the portable envelope alone can
/// never certify execution, source identity, observed ink, or permission to retry.
public enum DrawingNativeResultCodec {
  static let proposalEncoding = "adaptiveplotter.drawing-run-proposal/1"
  static let attemptEncoding = "adaptiveplotter.raw-attempt-state/1"
  static let terminalEncoding = "adaptiveplotter.raw-terminal-record/1"
  static let coverageEncoding = "adaptiveplotter.native-coverage/1"

  static var validators: [ExchangePayloadKey: ExchangePayloadValidator] {
    [
      .init(encoding: proposalEncoding, version: "1"): { context in
        let proposal = try decodeProposal(context.resolver.record(context.descriptor.asset.object))
        let facts = try proposalFacts(proposal, digest: context.descriptor.asset.object, context: context)
        return try environmentResult(facts, context: context)
      },
      .init(encoding: attemptEncoding, version: "1"): { context in
        let state = try JSONDecoder().decode(DrawingRunAttemptState.self,
          from: context.resolver.record(context.descriptor.asset.object))
        return try environmentResult(attemptFacts(state, context: context), context: context)
      },
      .init(encoding: terminalEncoding, version: "1"): { context in
        let record = try JSONDecoder().decode(DrawingRunEvidenceRecord.self,
          from: context.resolver.rawTerminalRecord(context.descriptor.asset.object))
        return try environmentResult(terminalFacts(record, source: context.descriptor.asset, context: context), context: context)
      },
      .init(encoding: coverageEncoding, version: "1"): { context in
        let bytes = try context.resolver.record(context.descriptor.asset.object)
        let json = try ExchangeJSON.validate(bytes)
        let stateAsset: ExchangeAsset = try decode(json["rawAttempt"])
        guard stateAsset.encoding == attemptEncoding else { throw DrawingExchangeError.malformed("Native coverage attempt encoding") }
        let stateBytes = try context.resolver.record(stateAsset.object)
        try stateAsset.validate(stateBytes)
        let state = try JSONDecoder().decode(DrawingRunAttemptState.self, from: stateBytes)
        var facts = try attemptFacts(state, context: context)
        var terminalBytes: Data?
        var terminal: DrawingRunEvidenceRecord?
        var rawTerminalAsset: ExchangeAsset?
        if let raw = json["rawTerminal"] {
          let asset: ExchangeAsset = try decode(raw)
          guard asset.encoding == terminalEncoding else { throw DrawingExchangeError.malformed("Native coverage terminal encoding") }
          let bytes = try context.resolver.rawTerminalRecord(asset.object)
          try asset.validate(bytes, maximumBytes: 256 * 1024 * 1024)
          let record = try JSONDecoder().decode(DrawingRunEvidenceRecord.self, from: bytes)
          guard record.attemptEvidence?.intent == state.intent else { throw DrawingExchangeError.malformed("Native raw terminal/attempt differs") }
          facts = try terminalFacts(record, source: asset, context: context)
          let inventory = try (json["entries"] as? [[String: Any]] ?? []).filter {
            ($0["kind"] as? String)?.hasPrefix("adaptiveplotter.raw-") == true
          }.map { entry -> String in
            let original: ExchangeAsset = try decode(entry["asset"]); return original.object.description
          }
          try record.validateOriginalMedia(availableDigests: Set(inventory)) { reference in
            let bytes = try context.resolver.originalMedia(ExchangeDigest(reference.frame.frameSHA256), maximumBytes: reference.byteCount)
            return try DrawingRunMediaValidation.frame(reference: reference, bytes: bytes)
          }
          terminalBytes = bytes; terminal = record; rawTerminalAsset = asset
        } else {
          guard let snapshot = context.current, !snapshot.sealed, snapshot.terminalRecord == nil,
            snapshot.state == (state.inkDispatchPossible ? "interrupted" : "staged"), snapshot.observation == "unavailable" else {
            throw DrawingExchangeError.malformed("Unsealed native snapshot claims a terminal state")
          }
        }
        guard let snapshot = context.current else { throw DrawingExchangeError.malformed("Native coverage snapshot unavailable") }
        let actualContent = try content(proposal: snapshot.intent, attempt: stateBytes, terminal: terminalBytes)
        guard rawTerminalAsset?.object == snapshot.terminalRecord,
          json["rawContent"] as? String == actualContent.description else {
          throw DrawingExchangeError.malformed("Native raw snapshot content differs")
        }
        try validateCoverage(json, state: state, terminal: terminal, attemptAsset: stateAsset,
          terminalAsset: rawTerminalAsset, frontiers: facts.frontiers, resolver: context.resolver)
        return try environmentResult(facts, context: context)
      }
    ]
  }
  static func decodeProposal(_ bytes: Data) throws -> DrawingRunIssuanceProposal {
    let value = try JSONDecoder().decode(DrawingRunIssuanceProposal.self, from: bytes)
    return try .init(body: value.body, binding: value.binding)
  }
  private static func proposalFacts(_ proposal: DrawingRunIssuanceProposal, digest: ExchangeDigest,
    context: ExchangePayloadContext) throws -> ExchangePayloadFacts {
    guard let receipt = context.receipt else { throw DrawingExchangeError.malformed("Native proposal has no receipt") }
    let b = proposal.binding
    guard b.job == receipt.handle, b.drawing == receipt.drawing, b.key.namespace == receipt.client.namespace,
      b.key.request == receipt.client.request, b.requestDigest == receipt.client.requestDigest,
      b.issuance == receipt.issuance, b.preparedPlan == receipt.preparedPlan,
      b.options == receipt.requestedMediumOptions, proposal.body.requestID == b.key.request else {
      throw DrawingExchangeError.malformed("Native proposal/receipt binding differs")
    }
    let plan = try JSONDecoder().decode(ExecutionPlanRevision.self,
      from: context.resolver.record(receipt.preparedPlan.object, maximumBytes: DrawingExchangeLimits.maximumProgramBytes))
    guard plan == proposal.body.plan, plan.revisionID == b.physicalPlanID,
      plan.contentHash.description == b.physicalPlanHash.description else {
      throw DrawingExchangeError.malformed("Native prepared/physical plan differs")
    }
    let drawingBytes = try context.resolver.record(receipt.drawing.digest)
    let drawing = try ExchangeJSON.validate(drawingBytes)
    guard let representation = drawing["representation"] as? [String: Any],
      let hash = representation["programHash"] as? String else { throw DrawingExchangeError.malformed("Native source representation") }
    let programObject: ExchangeDigest = try decode(representation["object"])
    let program = try JSONDecoder().decode(DrawingProgram.self,
      from: context.resolver.record(programObject, maximumBytes: DrawingExchangeLimits.maximumProgramBytes))
    guard let candidate = proposal.body.context.candidate, candidate.authoredDrawing == receipt.drawing,
      candidate.sourceProgram == program, candidate.programContentHash.description == hash,
      candidate.matches(proposal.body.context.program) else {
      throw DrawingExchangeError.malformed("Native authored source differs from Drawing")
    }
    return .init(job: b.job, drawing: b.drawing, clientRequestDigest: b.requestDigest,
      clientNamespace: b.key.namespace, clientRequest: b.key.request, issuance: b.issuance,
      programSemanticHash: try ExchangeDigest(hash), programObjectDigest: programObject,
      plan: b.preparedPlan.object, preMotion: digest,
      frontiers: ["planned": UInt64(plan.strokes.count)])
  }
  private static func proposal(_ context: ExchangePayloadContext) throws -> (DrawingRunIssuanceProposal, ExchangePayloadFacts) {
    guard let snapshot = context.current else { throw DrawingExchangeError.malformed("Native raw payload lacks snapshot") }
    let value = try decodeProposal(context.resolver.record(snapshot.intent))
    return (value, try proposalFacts(value, digest: snapshot.intent, context: context))
  }
  private static func attemptFacts(_ state: DrawingRunAttemptState, context: ExchangePayloadContext) throws -> ExchangePayloadFacts {
    let (proposal, initial) = try proposal(context)
    guard let snapshot = context.current, state.intent.runID.rawValue == snapshot.run,
      state.intent.body == proposal.body, state.intent.issuance == proposal.binding else {
      throw DrawingExchangeError.malformed("Native staged attempt binding differs")
    }
    _ = try DrawingRunEvidenceArchive(revision: 0, records: [], attempts: [state])
    if let prior = context.prior {
      let coverage = try ExchangeJSON.validate(context.resolver.record(prior.coverage))
      let asset: ExchangeAsset = try decode(coverage["rawAttempt"])
      guard asset.encoding == attemptEncoding else { throw DrawingExchangeError.malformed("Native predecessor raw-state encoding") }
      let previous = try JSONDecoder().decode(DrawingRunAttemptState.self, from: context.resolver.record(asset.object))
      guard previous.intent == state.intent, state.baselines.starts(with: previous.baselines),
        state.progressFrames.starts(with: previous.progressFrames),
        !previous.inkDispatchPossible || state.inkDispatchPossible else {
        throw DrawingExchangeError.malformed("Native raw attempt regressed across snapshots")
      }
    }
    for reference in state.baselines + state.progressFrames.map(\.media) {
      let digest = try ExchangeDigest(reference.frame.frameSHA256)
      guard try context.resolver.byteLength(digest) == UInt64(reference.byteCount),
        try context.resolver.assetDescriptor(digest) == mediaDescriptor(reference) else {
        throw DrawingExchangeError.malformed("Native original byte length differs")
      }
    }
    if state.inkDispatchPossible, snapshot.dispatch != "possibleInk" {
      throw DrawingExchangeError.malformed("Native possible ink was cleared")
    }
    if !state.inkDispatchPossible, snapshot.dispatch != "not-dispatched" {
      throw DrawingExchangeError.malformed("Native dispatch differs from raw marker")
    }
    var facts = initial; facts.run = state.intent.runID.rawValue
    if !state.inkDispatchPossible { facts.frontiers["commanded"] = 0; facts.frontiers["controllerCompleted"] = 0 }
    if let progress = state.progressFrames.last?.progress {
      facts.frontiers["commanded"] = UInt64(progress.commandedStrokeCount)
      facts.frontiers["controllerCompleted"] = UInt64(progress.controllerCompletedStrokeCount)
    }
    return facts
  }
  private static func terminalFacts(_ record: DrawingRunEvidenceRecord, source: ExchangeAsset, context: ExchangePayloadContext) throws -> ExchangePayloadFacts {
    guard record.attemptEvidence != nil, let snapshot = context.current else { throw DrawingExchangeError.malformed("Native terminal attempt is unavailable") }
    let coverage = try ExchangeJSON.validate(context.resolver.record(snapshot.coverage))
    let stateAsset: ExchangeAsset = try decode(coverage["rawAttempt"])
    let terminalAsset: ExchangeAsset = try decode(coverage["rawTerminal"])
    guard stateAsset.encoding == attemptEncoding, terminalAsset.encoding == terminalEncoding,
      terminalAsset == source, terminalAsset.object == snapshot.terminalRecord else {
      throw DrawingExchangeError.malformed("Native terminal raw-state/record encoding or identity")
    }
    let state = try JSONDecoder().decode(DrawingRunAttemptState.self, from: context.resolver.record(stateAsset.object))
    _ = try DrawingRunEvidenceArchive(revision: 1, records: [record], attempts: [state])
    var facts = try attemptFacts(state, context: context)
    let f = record.executionFrontiers
    facts.frontiers = ["planned": UInt64(f.plannedStrokeCount), "commanded": UInt64(f.commandedStrokeCount),
      "controllerCompleted": UInt64(f.controllerCompletedStrokeCount), "inkVerified": UInt64(f.inkVerifiedStrokeCount)]
    guard record.runID.rawValue == snapshot.run, snapshot.sealed,
      snapshot.state == stateName(record), snapshot.observation == observationName(record),
      (record.executionFrontiers.commandedStrokeCount == 0 && !state.inkDispatchPossible) || snapshot.dispatch == "possibleInk" else {
      throw DrawingExchangeError.malformed("Native terminal envelope differs from raw record")
    }
    return facts
  }
  private static func environmentResult(_ facts: ExchangePayloadFacts, context: ExchangePayloadContext) throws -> ExchangePayloadValidation {
    guard let receipt = context.receipt else { throw DrawingExchangeError.malformed("Native result receipt unavailable") }
    let options = try JSONDecoder().decode(DrawingDestinationOptions.self,
      from: context.resolver.record(receipt.requestedMediumOptions.object, maximumBytes: 65_536))
    guard let environment = options.environment else { return .unsupported(reason: "Raw execution environment was not retained") }
    if let snapshot = context.current, snapshot.environment != environment.rawValue {
      throw DrawingExchangeError.malformed("Native snapshot environment differs from original options")
    }
    return .verified(facts)
  }
  static func stateName(_ record: DrawingRunEvidenceRecord) -> String {
    switch record.executionDisposition {
    case .completed: return "completed"
    case .cancelled: return "cancelled"
    case .refused, .ambiguous, .failed: return "failed"
    }
  }
  static func observationName(_ record: DrawingRunEvidenceRecord) -> String {
    switch record.observation { case .observed: return "accepted"; case .rejected: return "rejected"; case .notAttempted: return "unavailable" }
  }
  static func decode<T: Decodable>(_ object: Any?) throws -> T {
    guard let object else { throw DrawingExchangeError.malformed("Missing native payload field") }
    return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed]))
  }

  private static func validateCoverage(_ json: [String: Any], state: DrawingRunAttemptState,
    terminal: DrawingRunEvidenceRecord?, attemptAsset: ExchangeAsset, terminalAsset: ExchangeAsset?,
    frontiers facts: [String: UInt64], resolver: ExchangePayloadResolver) throws {
    guard let declared = json["frontiers"] as? [String: [String: Any]], let entries = json["entries"] as? [[String: Any]] else {
      throw DrawingExchangeError.malformed("Native coverage inventory")
    }
    for name in ["planned", "commanded", "controllerCompleted", "inkVerified"] {
      guard let entry = declared[name] else { throw DrawingExchangeError.malformed("Missing native frontier") }
      if let count = facts[name] {
        let asset: ExchangeAsset = try decode(entry["asset"])
        let declaredCount: UInt64 = try decode(entry["count"])
        guard entry["status"] as? String == "present", declaredCount == count,
          asset == (terminalAsset ?? attemptAsset) else { throw DrawingExchangeError.malformed("Native frontier differs from raw owner") }
      } else {
        guard entry["status"] as? String == "unavailable", entry["asset"] == nil, entry["count"] == nil else {
          throw DrawingExchangeError.malformed("Unknown native frontier was fabricated")
        }
      }
    }
    let attempt = terminal?.attemptEvidence
    let expected = (attempt?.baselines ?? state.baselines).map { ("adaptiveplotter.raw-baseline", $0) }
      + (attempt?.progressFrames ?? state.progressFrames).map { ("adaptiveplotter.raw-progress", $0.media) }
      + (attempt?.terminalFrames ?? []).map { ("adaptiveplotter.raw-terminal", $0) }
    let media = entries.filter { ($0["kind"] as? String)?.hasPrefix("adaptiveplotter.raw-") == true }
    guard media.count == expected.count else { throw DrawingExchangeError.malformed("Native original inventory is incomplete") }
    for (entry, (kind, reference)) in zip(media, expected) {
      let asset: ExchangeAsset = try decode(entry["asset"])
      let expectedAsset = try mediaAsset(reference)
      guard entry["kind"] as? String == kind, entry["status"] as? String == "present",
        asset == expectedAsset, try resolver.assetDescriptor(asset.object) == mediaDescriptor(reference),
        entry["rawFrameID"] as? String == reference.frame.frameID.rawValue,
        entry["rawCaptureTicks"] as? String == String(reference.frame.captureNanoseconds),
        entry["captureClock"] as? String == "unavailable", entry["captureTime"] == nil else {
        throw DrawingExchangeError.malformed("Native original reference differs from raw record")
      }
    }
    for expected in try observationEntries(record: terminal, terminalAsset: terminalAsset) {
      guard let kind = expected["kind"] as? String,
        entries.filter({ $0["kind"] as? String == kind }).count == 1,
        let actual = entries.first(where: { $0["kind"] as? String == kind }),
        NSDictionary(dictionary: actual).isEqual(to: expected) else {
        throw DrawingExchangeError.malformed("Native observation availability differs from raw owner")
      }
    }
  }

  static func observationEntries(record: DrawingRunEvidenceRecord?, terminalAsset: ExchangeAsset?) throws -> [[String: Any]] {
    func present(_ kind: String, classification: String? = nil) throws -> [String: Any] {
      guard let terminalAsset else { throw DrawingExchangeError.malformed("Native observation lacks terminal asset") }
      var entry: [String: Any] = ["kind": kind, "status": "present", "asset": try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(terminalAsset))]
      if let classification { entry["classification"] = classification }
      return entry
    }
    let observation: [String: Any]
    if let record {
      switch record.observation {
      case .observed: observation = try present("adaptiveplotter.observation", classification: "accepted")
      case .rejected: observation = try present("adaptiveplotter.observation", classification: "rejected")
      case .notAttempted(let reason): observation = ["kind": "adaptiveplotter.observation", "status": "unavailable", "reason": reason.rawValue]
      }
    } else { observation = ["kind": "adaptiveplotter.observation", "status": "unavailable", "reason": "No terminal observation was retained at this boundary."] }
    let composite: [String: Any]
    if record?.attemptEvidence?.mediaCoverage != nil {
      composite = try present("adaptiveplotter.observation-composite")
    } else { composite = ["kind": "adaptiveplotter.observation-composite", "status": "unavailable",
      "reason": record?.attemptEvidence?.missingCoverageReason ?? "No derived composite was retained at this boundary."] }
    return [observation, composite]
  }
}

extension DrawingNativeResultCodec {
  static func content(proposal: ExchangeDigest, attempt: Data, terminal: Data?) throws -> ExchangeDigest {
    struct Basis: Encodable { let proposal: ExchangeDigest; let attempt: ExchangeDigest; let terminal: ExchangeDigest? }
    return .hash(try DrawingArtifactCoding.encoder().encode(Basis(proposal: proposal,
      attempt: .hash(attempt), terminal: terminal.map(ExchangeDigest.hash))))
  }
  static func mediaAsset(_ reference: DrawingRunMediaReference) throws -> ExchangeAsset {
    let encodings: [FramePixelFormat: String] = [.gray8: "raw-gray8", .rgba8: "raw-rgba8", .bgra8: "raw-bgra8"]
    guard let encoding = encodings[reference.frame.pixelFormat] else { throw DrawingExchangeError.malformed("Unsupported native original pixel format") }
    return try decode(["object": reference.frame.frameSHA256, "byteLength": reference.byteCount,
      "mediaType": "application/octet-stream", "encoding": encoding])
  }
  static func mediaDescriptor(_ reference: DrawingRunMediaReference) throws -> ExchangeAssetDescriptor {
    let frame = reference.frame
    var layout = try ExchangePixelLayout(width: frame.width, height: frame.height,
      bytesPerPixel: frame.pixelFormat.bytesPerPixel, rowStride: frame.rowBytes)
    if frame.pixelFormat == .bgra8 {
      layout = try .init(width: frame.width, height: frame.height, pixelFormat: "bgra", componentType: "uint8", bitDepth: 8,
        channelOrder: ["blue", "green", "red", "alpha"], rowStride: frame.rowBytes, byteOrder: "not-applicable", orientation: "up", colorInterpretation: "sRGB")
    }
    return .init(asset: try mediaAsset(reference), dimensions: .init(width: frame.width, height: frame.height), pixelLayout: layout)
  }
  static func media(_ raw: DrawingRunAttemptExport) -> [(String, DrawingRunMediaReference)] {
    let attempt = raw.record?.attemptEvidence
    return (attempt?.baselines ?? raw.attempt.baselines).map { ("adaptiveplotter.raw-baseline", $0) }
      + (attempt?.progressFrames ?? raw.attempt.progressFrames).map { ("adaptiveplotter.raw-progress", $0.media) }
      + (attempt?.terminalFrames ?? []).map { ("adaptiveplotter.raw-terminal", $0) }
  }
  static func frontierFacts(_ raw: DrawingRunAttemptExport) -> [String: UInt64] {
    if let record = raw.record {
      let f = record.executionFrontiers
      return ["planned": UInt64(f.plannedStrokeCount), "commanded": UInt64(f.commandedStrokeCount),
        "controllerCompleted": UInt64(f.controllerCompletedStrokeCount), "inkVerified": UInt64(f.inkVerifiedStrokeCount)]
    }
    var facts = ["planned": UInt64(raw.attempt.intent.plan.strokes.count)]
    if !raw.attempt.inkDispatchPossible { facts["commanded"] = 0; facts["controllerCompleted"] = 0 }
    if let p = raw.attempt.progressFrames.last?.progress {
      facts["commanded"] = UInt64(p.commandedStrokeCount); facts["controllerCompleted"] = UInt64(p.controllerCompletedStrokeCount)
    }
    return facts
  }
}

extension DrawingDestinationResult {
  static func prepareNative(_ decision: DrawingJobDecision, proposal: ExchangeAsset,
    raw: DrawingRunAttemptExport, previous: DrawingPublishedResult?, library: DrawingLibrary,
    directory: URL) async throws -> DrawingPublishedResult {
    DrawingDestinationArtifactObservation.shared.notify(decision.job.handle, .assemblyStarted)
    guard previous?.sealed != true else { throw DrawingDestinationRefusal.alreadySettled }
    let proposalBytes = try await library.asset(proposal.object)
    try proposal.validate(proposalBytes)
    let intent = try DrawingNativeResultCodec.decodeProposal(proposalBytes)
    guard proposal.encoding == DrawingNativeResultCodec.proposalEncoding,
      raw.attempt.intent.body == intent.body, raw.attempt.intent.issuance == intent.binding,
      intent.binding.job == decision.job.handle, intent.binding.drawing == decision.ticket.facts.drawing,
      intent.binding.key == decision.key, intent.binding.requestDigest == decision.requestDigest else {
      throw DrawingExchangeError.malformed("Selected raw attempt differs from accepted job")
    }
    let content = try DrawingNativeResultCodec.content(proposal: proposal.object, attempt: raw.attemptJSON, terminal: raw.recordJSON)
    let predecessor = previous?.snapshot
    struct PublicationKey: Encodable { let content: ExchangeDigest; let previous: SnapshotRef? }
    let key = ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(PublicationKey(content: content, previous: predecessor)))
    let fileName = decision.job.handle.job.uuidString.lowercased() + "-" + key.description + ".zip"
    let candidates = directory.appendingPathComponent(".native-candidates", isDirectory: true)
    let target = candidates.appendingPathComponent(fileName)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.createDirectory(at: candidates, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var candidateDirectory = stat()
    guard Darwin.lstat(candidates.path, &candidateDirectory) == 0,
      candidateDirectory.st_mode & S_IFMT == S_IFDIR else {
      throw DrawingExchangeError.malformed("Native candidate location is not a directory")
    }
    let temporary = directory.appendingPathComponent(".native-result-stage-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temporary) }
    if FileManager.default.fileExists(atPath: target.path) {
      return try nativeCandidate(at: target, decision: decision, content: content, previous: previous,
        archive: raw.archiveID, run: raw.attempt.intent.runID.rawValue, stagingParent: temporary)
    }
    let bag = temporary.appendingPathComponent("bag")
    if let previous {
      let source = directory.appendingPathComponent(previous.fileName)
      let priorFiles = try validatedNativePublication(previous, at: source, decision: decision, stagingParent: temporary)
      try DrawingExchangeCarrier.preserveDirectory(priorFiles.files, to: bag)
    }
    else { try await library.exportDrawing(decision.ticket.facts.drawing, to: bag) }
    var index = try ExchangeJSON.validate(Data(contentsOf: bag.appendingPathComponent("data/exchange.json")))
    var descriptors: [ExchangeAssetDescriptor] = try DrawingNativeResultCodec.decode(index["assets"])
    let encoder = DrawingArtifactCoding.encoder()
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value), options: .fragmentsAllowed) }
    func addDescriptor(_ descriptor: ExchangeAssetDescriptor) throws {
      if let old = descriptors.first(where: { $0.asset.object == descriptor.asset.object }) {
        guard old == descriptor else { throw DrawingExchangeError.malformed("Native asset descriptor conflict") }
      } else { descriptors.append(descriptor) }
    }
    func install(_ bytes: Data, encoding: String) throws -> ExchangeAsset {
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: encoding)
      try addDescriptor(.init(asset: asset))
      let path = bag.appendingPathComponent("data/objects/sha256/" + asset.object.description)
      try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: path.path) {
        let retained = try Data(contentsOf: path)
        guard retained == bytes else { throw DrawingExchangeError.digestMismatch("Native retained asset") }
      } else { try bytes.write(to: path, options: .atomic) }
      return asset
    }
    _ = try install(proposalBytes, encoding: proposal.encoding)
    for asset in [decision.ticket.facts.plan, decision.ticket.facts.options] {
      let bytes = try await library.asset(asset.object)
      guard try install(bytes, encoding: asset.encoding) == asset else { throw DrawingExchangeError.malformed("Native plan/options asset") }
    }
    let attemptAsset = try install(raw.attemptJSON, encoding: DrawingNativeResultCodec.attemptEncoding)
    let terminalAsset = try raw.recordJSON.map { try install($0, encoding: DrawingNativeResultCodec.terminalEncoding) }
    var entries: [[String: Any]] = []
    for (kind, reference) in DrawingNativeResultCodec.media(raw) {
      let descriptor = try DrawingNativeResultCodec.mediaDescriptor(reference)
      try addDescriptor(descriptor)
      let path = bag.appendingPathComponent("data/objects/sha256/" + descriptor.asset.object.description)
      if !FileManager.default.fileExists(atPath: path.path) {
        guard let original = raw.originalMedia[reference.frame.frameSHA256] else { throw DrawingExchangeError.missingAsset(reference.frame.frameSHA256) }
        DrawingDestinationArtifactObservation.shared.notify(decision.job.handle, .copyingOriginal)
        try original.copy(to: path)
      }
      entries.append(["kind": kind, "status": "present", "asset": try object(descriptor.asset),
        "rawFrameID": reference.frame.frameID.rawValue,
        "rawCaptureTicks": String(reference.frame.captureNanoseconds), "captureClock": "unavailable"])
    }
    entries += try DrawingNativeResultCodec.observationEntries(record: raw.record, terminalAsset: terminalAsset)
    for (kind, reason) in [("adaptiveplotter.capture-clock", "Raw capture ticks have no retained boot/clock identity; no cross-clock synchronization is asserted."),
      ("adaptiveplotter.local-review", "Local review notes and no-ink declarations remain with their raw owner; they cannot grant imported retry authority.")] {
      entries.append(["kind": kind, "status": "unavailable", "reason": reason])
    }
    let includedAsOf = ISO8601DateFormatter().string(from: Date())
    var frontiers: [String: Any] = [:]
    let counts = DrawingNativeResultCodec.frontierFacts(raw)
    for name in ["planned", "commanded", "controllerCompleted", "inkVerified"] {
      if let count = counts[name] {
        frontiers[name] = ["kind": "adaptiveplotter.frontier/" + name, "status": "present", "count": count,
          "asset": try object(terminalAsset ?? attemptAsset)]
      } else { frontiers[name] = ["kind": "adaptiveplotter.frontier/" + name, "status": "unavailable", "reason": "No exact retained frontier at this raw boundary."] }
    }
    var coverage: [String: Any] = ["profile": "adaptiveplotter.coverage/1", "requiredFeatures": [String](),
      "includedAsOf": ["wallTime": includedAsOf], "rawContent": content.description,
      "rawAttempt": try object(attemptAsset), "entries": entries, "frontiers": frontiers]
    if let terminalAsset { coverage["rawTerminal"] = try object(terminalAsset) }
    let coverageAsset = try install(JSONSerialization.data(withJSONObject: coverage, options: [.sortedKeys, .withoutEscapingSlashes]), encoding: DrawingNativeResultCodec.coverageEncoding)
    let sequence = (predecessor?.sequence ?? 0) + 1
    let options = try JSONDecoder().decode(DrawingDestinationOptions.self, from: await library.asset(decision.ticket.facts.options.object))
    let run = raw.attempt.intent.runID.rawValue
    let dispatch = raw.attempt.inkDispatchPossible || (raw.record?.executionFrontiers.commandedStrokeCount ?? 0) > 0
    let snapshot: [String: Any] = ["profile": "adaptiveplotter.plot-attempt/1", "requiredFeatures": [String](),
      "issuerArchive": raw.archiveID.uuidString.lowercased(), "run": run.uuidString.lowercased(), "sequence": sequence,
      "previous": predecessor.map { $0.digest.description as Any } ?? NSNull(), "sealed": raw.record != nil,
      "drawing": try object(decision.ticket.facts.drawing), "job": try object(decision.job),
      "environment": options.environment?.rawValue ?? "unknown", "intent": proposal.object.description,
      "coverage": coverageAsset.object.description, "state": raw.record.map(DrawingNativeResultCodec.stateName) ?? (raw.attempt.inkDispatchPossible ? "interrupted" : "staged"),
      "dispatch": dispatch ? "possibleInk" : "not-dispatched", "observation": raw.record.map(DrawingNativeResultCodec.observationName) ?? "unavailable",
      "terminalRecord": terminalAsset.map { $0.object.description as Any } ?? NSNull(), "assessments": [String](),
      "plan": try object(decision.ticket.facts.plan)]
    let snapshotBytes = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .withoutEscapingSlashes])
    let snapshotRef = try SnapshotRef(archive: raw.archiveID, run: run, sequence: sequence, digest: .hash(snapshotBytes))
    let snapshotPath = bag.appendingPathComponent("data/attempts/" + raw.archiveID.uuidString.lowercased() + "/" + run.uuidString.lowercased() + "/" + String(sequence) + "/attempt.json")
    try FileManager.default.createDirectory(at: snapshotPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try snapshotBytes.write(to: snapshotPath, options: .atomic)
    let receiptPath = bag.appendingPathComponent("data/jobs/" + decision.job.handle.engine.uuidString.lowercased() + "/" + decision.job.handle.job.uuidString.lowercased() + "/receipt.json")
    try FileManager.default.createDirectory(at: receiptPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try decision.receipt.write(to: receiptPath, options: .atomic)
    index["kind"] = "result"; index["includedAsOf"] = includedAsOf
    index["jobs"] = try object([decision.job]); index["attempts"] = try object([snapshotRef]); index["assets"] = try object(descriptors)
    try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try seal(bag)
    let staged = try DrawingExchangeCarrier.stageDirectory(bag, stagingParent: temporary)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: payloadValidators)
    let output = temporary.appendingPathComponent("candidate.zip")
    try DrawingExchangeCarrier.preserveZIP(admitted.files, to: output)
    let fd = Darwin.open(output.path, O_RDONLY | O_NOFOLLOW)
    guard fd >= 0 else { throw CocoaError(.fileReadUnknown) }
    let sync = Darwin.fsync(fd); Darwin.close(fd)
    guard sync == 0 else { throw CocoaError(.fileWriteUnknown) }
    DrawingDestinationArtifactObservation.shared.notify(decision.job.handle, .beforePublication)
    if Darwin.renamex_np(output.path, target.path, UInt32(RENAME_EXCL)) != 0, errno != EEXIST { throw CocoaError(.fileWriteUnknown) }
    let parent = Darwin.open(candidates.path, O_RDONLY | O_DIRECTORY)
    guard parent >= 0 else { throw CocoaError(.fileWriteUnknown) }
    let synced = Darwin.fsync(parent); Darwin.close(parent)
    guard synced == 0 else { throw CocoaError(.fileWriteUnknown) }
    return try nativeCandidate(at: target, decision: decision, content: content, previous: previous,
      archive: raw.archiveID, run: run, stagingParent: temporary)
  }

  static func nativeCandidate(at source: URL, decision: DrawingJobDecision, content: ExchangeDigest,
    previous: DrawingPublishedResult?, archive: UUID, run: UUID, stagingParent: URL) throws -> DrawingPublishedResult {
    let staged = try DrawingExchangeCarrier.stageZIP(source, stagingParent: stagingParent)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: payloadValidators)
    guard let index = admitted.index.known, index.kind == "result", index.roots == [decision.ticket.facts.drawing],
      index.jobs == [decision.job], index.attempts.count == 1, let ref = index.attempts.first,
      let snapshot = admitted.attempts[ref], snapshot.run == run, snapshot.issuerArchive == archive,
      snapshot.previous == previous?.snapshot.digest, snapshot.sequence == (previous?.snapshot.sequence ?? 0) + 1,
      admitted.receipts[decision.job]?.originalJSON == decision.receipt else { throw DrawingExchangeError.malformed("Divergent native candidate") }
    let coverage = try ExchangeJSON.validate(admitted.files.record(snapshot.coverage))
    guard coverage["rawContent"] as? String == content.description else { throw DrawingExchangeError.malformed("Native candidate content differs") }
    let inventory = LibraryExchangeCatalog.inventoryDigest(admitted.files.entries.values.map { .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) })
    return .init(content: content, reference: .init(indexDigest: .hash(index.originalJSON), packageDigest: inventory),
      snapshot: ref, fileName: source.lastPathComponent, sealed: snapshot.sealed)
  }

  /// Only the existing Admission CAS may choose a candidate. Until then its
  /// exact bytes remain hidden, so racing raw boundaries cannot publish forks.
  static func publishNativeCandidate(_ candidate: DrawingPublishedResult, decision: DrawingJobDecision,
    directory: URL) throws {
    let temporary = directory.appendingPathComponent(".native-publication-read-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: temporary) }
    let chosen = directory.appendingPathComponent(candidate.fileName)
    if FileManager.default.fileExists(atPath: chosen.path) {
      _ = try validatedNativePublication(candidate, at: chosen, decision: decision, stagingParent: temporary)
      return
    }
    let staged = directory.appendingPathComponent(".native-candidates/" + candidate.fileName)
    _ = try validatedNativePublication(candidate, at: staged, decision: decision, stagingParent: temporary)
    // Keep the immutable selected source available to all concurrent finishers.
    // A hard link is forbidden by carrier pinning; the private copy has nlink=1.
    let publication = directory.appendingPathComponent(".native-publication-" + UUID().uuidString + ".zip")
    defer { try? FileManager.default.removeItem(at: publication) }
    try FileManager.default.copyItem(at: staged, to: publication)
    let output = Darwin.open(publication.path, O_RDONLY | O_NOFOLLOW)
    guard output >= 0 else { throw CocoaError(.fileReadUnknown) }
    let fileSynchronized = Darwin.fsync(output); Darwin.close(output)
    guard fileSynchronized == 0 else { throw CocoaError(.fileWriteUnknown) }
    if Darwin.renamex_np(publication.path, chosen.path, UInt32(RENAME_EXCL)) != 0, errno != EEXIST {
      throw CocoaError(.fileWriteUnknown)
    }
    let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    let synchronized = Darwin.fsync(descriptor); Darwin.close(descriptor)
    guard synchronized == 0 else { throw CocoaError(.fileWriteUnknown) }
    _ = try validatedNativePublication(candidate, at: chosen, decision: decision, stagingParent: temporary)
  }

  /// A result reference pins one already-chosen carrier. This is inspection,
  /// not a second local mount or a new persistence authority. The receiving
  /// Library mounts it through its existing journal/CAS.
  static func validatedNativePublication(_ publication: DrawingPublishedResult, at source: URL,
    decision: DrawingJobDecision, stagingParent: URL) throws -> ValidatedExchangePackage {
    let staged = try DrawingExchangeCarrier.stageZIP(source, stagingParent: stagingParent)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: payloadValidators)
    let inventory = LibraryExchangeCatalog.inventoryDigest(admitted.files.entries.values.map { .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength) })
    guard let index = admitted.index.known, index.kind == "result", index.roots == [decision.ticket.facts.drawing],
      index.jobs == [decision.job], index.attempts == [publication.snapshot],
      admitted.receipts[decision.job]?.originalJSON == decision.receipt,
      publication.reference == DrawingLibraryResultRef(indexDigest: .hash(index.originalJSON), packageDigest: inventory) else {
      throw DrawingExchangeError.malformed("Chosen immutable result is missing or divergent")
    }
    return admitted
  }
}
