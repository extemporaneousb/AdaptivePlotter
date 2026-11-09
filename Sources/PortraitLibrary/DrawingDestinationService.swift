import Foundation
import DrawingLibrary
import PortraitCore
import PlotterModel

/// Disposable non-device acceptance owner. Production composition never supplies one.
@MainActor public protocol DrawingDestinationNonDeviceOwner: AnyObject {
  func issue(job: JobRef, issuance: UUID) async throws
  func cancel(job: JobRef) async throws -> (acknowledged: Bool, settled: Bool)
}

/// One local writer composition. Queueing the complete operation, including every
/// await, prevents MainActor reentrancy from creating duplicate admissions.
@MainActor public final class DrawingDestinationService: DrawingDestination {
  public typealias Prepare = @MainActor (DrawingRef, UUID, @escaping @MainActor () -> Bool) async throws -> DrawingPreparation?
  public typealias Current = @MainActor (DrawingPreparedFacts) async throws -> DrawingPreparedFacts?
  private let library: DrawingLibrary
  private let prepare: Prepare
  private let current: Current
  private let nonDeviceOwner: DrawingDestinationNonDeviceOwner?
  private let returns: URL
  package private(set) var inFlightOperationCount = 0
  private var closing = false
  private var tail: Task<DrawingDestinationReply, Error>?
  private static let identityID = UUID(uuidString: "0e161f7d-8b65-4e83-8ee5-d58a40dde052")!
  private let identityKind = "adaptiveplotter.destination.engine"
  private let preparedKind = "adaptiveplotter.destination.prepared"
  private let jobKind = "adaptiveplotter.destination.job"
  private struct Identity: Codable { let engine: UUID }
  private struct Admission: Codable {
    let digest: ExchangeDigest
    let ticket: DrawingPreparedTicket
    let decision: DrawingJobDecision?
  }
  public init(library: DrawingLibrary, returnDirectory: URL, prepare: @escaping Prepare, current: @escaping Current, nonDeviceOwner: DrawingDestinationNonDeviceOwner? = nil) {
    self.nonDeviceOwner = nonDeviceOwner
    self.library = library; returns = returnDirectory; self.prepare = prepare; self.current = current
  }
  public func handle(_ request: DrawingDestinationRequest) async throws -> DrawingDestinationReply {
    try await handle(request, context: .init())
  }
  public func handle(_ request: DrawingDestinationRequest,
    isStillCurrent: @escaping @MainActor () -> Bool) async throws -> DrawingDestinationReply {
    try await handle(request, context: .init(isStillCurrent: isStillCurrent))
  }
  public func handle(_ request: DrawingDestinationRequest, context: DrawingPreparationContext) async throws -> DrawingDestinationReply {
    guard !closing else { throw DrawingLibraryError.closed }
    inFlightOperationCount += 1
    let prior = tail
    let task = Task { @MainActor in
      defer { self.inFlightOperationCount -= 1 }
      _ = try? await prior?.value
      return try await self.perform(request, context: context)
    }
    tail = task
    return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
  }
  public func closeAdmission() { closing = true }
  public func close() async {
    closeAdmission()
    _ = try? await tail?.value
  }
  private func engine() async throws -> UUID {
    try await library.open()
    if let record = try await library.record(.init(kind: identityKind, id: Self.identityID)) {
      return try JSONDecoder().decode(Identity.self, from: record.payload).engine
    }
    let identity = Identity(engine: UUID())
    try await library.commitRecords([.init(kind: identityKind, id: Self.identityID,
      payload: try DrawingArtifactCoding.encoder().encode(identity))])
    return identity.engine
  }
  private func read<T: Decodable>(_ type: T.Type, kind: String, id: UUID) async throws -> T? {
    guard let record = try await library.record(.init(kind: kind, id: id)) else { return nil }
    return try JSONDecoder().decode(type, from: record.payload)
  }
  private func decision(_ lookup: DrawingJobLookup, engine: UUID) async throws -> DrawingJobDecision? {
    switch lookup {
    case .job(let job):
      guard job.engine == engine else { return nil }
      return try await read(DrawingJobDecision.self, kind: jobKind, id: job.job)
    case .request(let key):
      return try await read(Admission.self, kind: key.recordKind, id: key.request)?.decision
    }
  }
  private func perform(_ request: DrawingDestinationRequest, context: DrawingPreparationContext) async throws -> DrawingDestinationReply {
    let engine = try await engine()
    switch request {
    case .describe: return .description(.init(engine: engine))
    case .prepare(let ref):
      // A caller must first install the exact authored closure through this Library.
      let valid = { @MainActor in !self.closing && context.isStillCurrent() && !Task.isCancelled }
      guard valid(), context.mayBegin() else { return .refused(.preparationUnavailable) }
      _ = try await library.drawing(ref)
      guard valid(), context.mayBegin(), let preparation = try await prepare(ref, engine, valid), valid(),
        preparation.facts.drawing == ref, preparation.facts.destination == engine else {
        return .refused(.preparationUnavailable)
      }
      let facts = preparation.facts
      let ticket = DrawingPreparedTicket(facts: facts)
      let assets = Self.assets(preparation)
      try await library.commitRecords([.init(kind: preparedKind, id: ticket.id,
        payload: try DrawingArtifactCoding.encoder().encode(ticket), drawings: [ref],
        assets: assets.map { $0.descriptor.asset.object })], assets: assets)
      return .prepared(ticket)
    case .submit(let key, let ticket):
      let digest = ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(ticket))
      if let prior = try await read(Admission.self, kind: key.recordKind, id: key.request) {
        guard prior.digest == digest else { return .refused(.requestConflict) }
        if let decision = prior.decision { return .decision(decision) }
        return .refused(.stalePreview)
      }
      guard ticket.facts.destination == engine,
        let original = try await read(DrawingPreparedTicket.self, kind: preparedKind, id: ticket.id), original == ticket else {
        return .refused(.preparationUnavailable)
      }
      // Reserve even a stale request's digest: a new preview needs a new request UUID.
      guard try await current(ticket.facts) == ticket.facts else {
        let stale = Admission(digest: digest, ticket: ticket, decision: nil)
        try await library.commitRecords([.init(kind: key.recordKind, id: key.request,
          payload: try DrawingArtifactCoding.encoder().encode(stale), drawings: [ticket.facts.drawing])])
        return .refused(.stalePreview)
      }
      let handle = JobRef(engine: engine, job: UUID())
      let assets = [ticket.facts.plan, ticket.facts.options]
      let issuance = nonDeviceOwner == nil ? nil : UUID()
      let receipt = try Self.receipt(handle: handle, key: key, digest: digest, ticket: ticket, assets: assets, issuance: issuance)
      let decision = DrawingJobDecision(key: key, requestDigest: digest,
        job: .init(handle: handle, receiptDigest: .hash(receipt)), ticket: ticket,
        reason: issuance == nil ? .issuanceSeamUnavailable : .nonDeviceOwner, receipt: receipt,
        phase: issuance == nil ? .refused : .reconciling)
      let admission = Admission(digest: digest, ticket: ticket, decision: decision)
      let bytes = try DrawingArtifactCoding.encoder().encode(decision)
      let records: [DrawingLibraryRecord] = [
        .init(kind: key.recordKind, id: key.request, payload: try DrawingArtifactCoding.encoder().encode(admission),
          drawings: [ticket.facts.drawing], assets: assets.map { $0.object }),
        .init(kind: jobKind, id: handle.job, payload: bytes, drawings: [ticket.facts.drawing],
          assets: assets.map { $0.object })]
      do { try await library.commitRecords(records) }
      catch {
        // The existing writer may have committed before losing acknowledgement.
        // Recover/open through that owner and inspect the exact mapping, never reissue.
        try await library.open()
        if let recovered = try await self.decision(.request(key), engine: engine), recovered.requestDigest == digest {
          return .decision(recovered)
        }
        throw error
      }
      if let issuance, let nonDeviceOwner {
        // Durable reconciling state precedes the sole effect. A restart only
        // observes it; neither retry nor recovery calls issue again.
        try await nonDeviceOwner.issue(job: handle, issuance: issuance)
        let accepted = Self.phase(decision, .accepted)
        try await update(accepted)
        return .decision(accepted)
      }
      return .decision(decision)
    case .status(let lookup):
      if case .request(let key) = lookup,
        let admission = try await read(Admission.self, kind: key.recordKind, id: key.request), admission.decision == nil {
        return .refused(.stalePreview)
      }
      guard let decision = try await decision(lookup, engine: engine) else { return .refused(.unknownJob) }
      return .decision(decision)
    case .cancel(let lookup):
      guard let decision = try await decision(lookup, engine: engine) else { return .refused(.unknownJob) }
      if decision.phase == .refused || decision.phase == .settled { return .cancellation(acknowledged: false, settled: true) }
      guard let nonDeviceOwner else { return .cancellation(acknowledged: false, settled: false) }
      try await update(Self.phase(decision, .cancelRequested))
      let response = try await nonDeviceOwner.cancel(job: decision.job.handle)
      if response.settled { try await update(Self.phase(decision, .settled)) }
      return .cancellation(acknowledged: response.acknowledged, settled: response.settled)
    case .exportResult(let job):
      guard let decision = try await decision(.job(job), engine: engine) else { return .refused(.unknownJob) }
      guard decision.phase == .refused else { return .refused(.preparationUnavailable) }
      let returns = self.returns
      let destination = returns.appendingPathComponent(job.job.uuidString.lowercased() + ".zip")
      let library = self.library
      let artifact = Task.detached {
        try FileManager.default.createDirectory(at: returns, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try await DrawingDestinationResult.export(decision, library: library, to: destination)
      }
      try await artifact.value
      return .result(destination)
    }
  }
  private static func phase(_ decision: DrawingJobDecision, _ phase: DrawingJobPhase) -> DrawingJobDecision {
    .init(key: decision.key, requestDigest: decision.requestDigest, job: decision.job,
      ticket: decision.ticket, reason: decision.reason, receipt: decision.receipt, phase: phase)
  }
  private func update(_ decision: DrawingJobDecision) async throws {
    let admission = Admission(digest: decision.requestDigest, ticket: decision.ticket, decision: decision)
    try await library.commitRecords([
      .init(kind: decision.key.recordKind, id: decision.key.request, payload: try DrawingArtifactCoding.encoder().encode(admission), drawings: [decision.ticket.facts.drawing]),
      .init(kind: jobKind, id: decision.job.job, payload: try DrawingArtifactCoding.encoder().encode(decision), drawings: [decision.ticket.facts.drawing])])
  }
  static func assets(_ preparation: DrawingPreparation) -> [DrawingLibraryClosureAsset] {
    [.init(descriptor: .init(asset: preparation.facts.plan), bytes: preparation.planBytes),
      .init(descriptor: .init(asset: preparation.facts.options), bytes: preparation.optionsBytes)]
  }
  private static func receipt(handle: JobRef, key: DrawingRequestKey, digest: ExchangeDigest,
    ticket: DrawingPreparedTicket, assets: [ExchangeAsset], issuance: UUID?) throws -> Data {
    let encoder = DrawingArtifactCoding.encoder()
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
    var json: [String: Any] = ["profile": "adaptiveplotter.plot-job-receipt/1", "requiredFeatures": [String](),
      "handle": try object(handle), "client": ["namespace": key.namespace.uuidString.lowercased(),
        "request": key.request.uuidString.lowercased(), "requestDigest": digest.description],
      "drawing": try object(ticket.facts.drawing), "preparedPlan": try object(assets[0]),
      "requestedMediumOptions": try object(assets[1]),
      "issuedAt": ["wallTime": ISO8601DateFormatter().string(from: Date())],
      "disposition": issuance == nil ? "refused" : "accepted", "reason": issuance == nil ? DrawingDestinationRefusal.issuanceSeamUnavailable.rawValue : DrawingDestinationRefusal.nonDeviceOwner.rawValue]
    if let issuance { json["issuance"] = issuance.uuidString.lowercased() }
    let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
    _ = try ExchangeJobReceipt(originalJSON: bytes)
    return bytes
  }
}
