import Foundation
import DrawingLibrary
import PortraitCore
import PlotterModel

/// Library metadata transitions are serialized, not whole runs or artifact work.
@MainActor public final class DrawingDestinationService: DrawingDestination, DrawingJobPublication {
  public typealias Prepare = @MainActor (DrawingRef, UUID, @escaping @MainActor () -> Bool) async throws -> DrawingPreparation?
  public typealias Current = @MainActor (DrawingPreparedFacts) async throws -> DrawingPreparedFacts?
  private let library: DrawingLibrary
  private let prepare: Prepare
  private let current: Current
  private let control: (any DrawingDestinationJobControl)?
  private let returns: URL
  package private(set) var inFlightOperationCount = 0
  private var closing = false
  private var tail: Task<Void, Never>?
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  private static let identityID = UUID(uuidString: "0e161f7d-8b65-4e83-8ee5-d58a40dde052")!
  private static let clientID = UUID(uuidString: "10974a70-ab26-45ca-a2e6-20344c36a403")!
  private let identityKind = "adaptiveplotter.destination.engine"
  private let preparedKind = "adaptiveplotter.destination.prepared"
  private let jobKind = "adaptiveplotter.destination.job"
  private let pendingKind = "adaptiveplotter.destination.job-pending"
  private struct Identity: Codable, Sendable { let engine: UUID }
  private struct Admission: Codable, Sendable {
    let digest: ExchangeDigest
    let ticket: DrawingPreparedTicket
    var decision: DrawingJobDecision?
    var pending: DrawingPendingJob?
  }
  public init(library: DrawingLibrary, returnDirectory: URL, prepare: @escaping Prepare,
    current: @escaping Current, control: (any DrawingDestinationJobControl)? = nil) {
    self.library = library; returns = returnDirectory; self.prepare = prepare; self.current = current; self.control = control
  }
  private func transition<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
    let prior = tail
    let task = Task { @MainActor in
      await prior?.value
      return try await operation()
    }
    tail = Task { @MainActor in _ = try? await task.value }
    return try await task.value
  }
  public func handle(_ request: DrawingDestinationRequest) async throws -> DrawingDestinationReply {
    try await handle(request, context: .init())
  }
  public func handle(_ request: DrawingDestinationRequest, isStillCurrent: @escaping @MainActor () -> Bool) async throws -> DrawingDestinationReply {
    try await handle(request, context: .init(isStillCurrent: isStillCurrent))
  }
  public func handle(_ request: DrawingDestinationRequest, context: DrawingPreparationContext) async throws -> DrawingDestinationReply {
    try await handle(request, context: context, admission: nil)
  }
  public func handle(_ request: DrawingDestinationRequest, admission: any DrawingDestinationIssuanceAdmission) async throws -> DrawingDestinationReply {
    try await handle(request, context: .init(), admission: admission)
  }
  public func handle(_ request: DrawingDestinationRequest, context: DrawingPreparationContext,
    admission: (any DrawingDestinationIssuanceAdmission)?) async throws -> DrawingDestinationReply {
    guard !closing else { throw DrawingLibraryError.closed }
    inFlightOperationCount += 1
    defer {
      inFlightOperationCount -= 1
      if inFlightOperationCount == 0 { let waiting = drainWaiters; drainWaiters.removeAll(); waiting.forEach { $0.resume() } }
    }
    let engine = try await transition { try await self.engine() }
    switch request {
    case .describe: return .description(.init(engine: engine, executionAvailable: control != nil))
    case .prepare(let ref):
      let valid = { @MainActor in !self.closing && context.isStillCurrent() && !Task.isCancelled }
      guard valid(), context.mayBegin() else { return .refused(.preparationUnavailable) }
      let drawing = try await library.drawing(ref)
      if context.nativePreparation != nil, !drawing.capabilities.supported.contains(.plot) { return .refused(.unsupportedDrawing) }
      guard valid(), context.mayBegin() else { return .refused(.preparationUnavailable) }
      let preparation: DrawingPreparation?
      if let native = context.nativePreparation { preparation = native }
      else { preparation = try await prepare(ref, engine, valid) }
      guard valid(), let preparation, preparation.facts.drawing == ref,
        preparation.facts.destination == engine else { return .refused(.preparationUnavailable) }
      let ticket = DrawingPreparedTicket(facts: preparation.facts)
      let assets = Self.assets(preparation)
      try await transition {
        try await self.library.commitRecords([.init(kind: self.preparedKind, id: ticket.id,
          payload: try DrawingArtifactCoding.encoder().encode(ticket), drawings: [ref], assets: assets.map { $0.descriptor.asset.object })], assets: assets)
      }
      return .prepared(ticket)
    case .submit(let key, let ticket):
      let digest = ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(ticket))
      // Lookup precedes readiness and may recover an acknowledgement after all
      // live facts changed. Only the first exact reservation invokes admission.
      if let previous = try await transition({ try await self.readAdmission(key) }) {
        guard previous.digest == digest else { return .refused(.requestConflict) }
        return try await recoverReply(previous)
      }
      let live: Bool
      if let admission { live = await admission.isCurrent(ticket) }
      else { live = (try await current(ticket.facts)) == ticket.facts }
      let reserved: (Admission, Bool) = try await transition {
        if let previous = try await self.readAdmission(key) {
          guard previous.digest == digest else { throw DrawingDestinationRefusal.requestConflict }
          return (previous, false)
        }
        guard ticket.facts.destination == engine,
          let original = try await self.read(DrawingPreparedTicket.self, kind: self.preparedKind, id: ticket.id), original == ticket else {
          throw DrawingDestinationRefusal.preparationUnavailable
        }
        if !live {
          let stale = Admission(digest: digest, ticket: ticket)
          try await self.save(stale, key: key)
          return (stale, false)
        }
        let binding = DrawingJobIssuance(drawing: ticket.facts.drawing, job: .init(engine: engine, job: UUID()),
          key: key, requestDigest: digest, issuance: UUID(), preparedPlan: ticket.facts.plan,
          physicalPlanID: ticket.facts.planID, physicalPlanHash: ticket.facts.planHash, options: ticket.facts.options)
        if admission == nil {
          let refused = try self.makeDecision(binding, ticket: ticket, reason: self.control == nil ? .issuanceSeamUnavailable : .nativePlotRequired, run: nil)
          let value = Admission(digest: digest, ticket: ticket, decision: refused)
          try await self.save(value, key: key)
          return (value, false)
        }
        let value = Admission(digest: digest, ticket: ticket, pending: .init(binding: binding, ticket: ticket))
        try await self.save(value, key: key)
        return (value, true)
      }
      guard reserved.1, let pending = reserved.0.pending, let admission else {
        return try await recoverReply(reserved.0)
      }
      // No transition lock is held across raw staging, portrait proof or Run.
      do { try await admission.admit(pending.binding, publication: self) }
      catch {
        // Durable pending survives disconnect/uncertainty. It is not re-issued.
        if let recovered = try? await transition({ try await self.readAdmission(key) }) { return reply(recovered) }
        throw error
      }
      guard let decided = try await transition({ try await self.readAdmission(key) }) else { throw DrawingDestinationRefusal.unknownJob }
      return reply(decided)
    case .status(let lookup):
      return try await transition {
        guard let value = try await self.lookup(lookup, engine: engine) else { return .refused(.unknownJob) }
        return self.reply(value)
      }
    case .cancel(let lookup):
      let value: Admission? = try await transition {
        guard var value = try await self.lookup(lookup, engine: engine) else { return nil }
        if value.decision?.phase == .refused || value.decision?.phase == .settled { return value }
        value.pending?.cancellationRequested = true
        if let decision = value.decision { value.decision = Self.phase(decision, .cancelRequested) }
        guard let key = value.pending?.binding.key ?? value.decision?.key else { return value }
        try await self.save(value, key: key)
        return value
      }
      guard let value else { return .refused(.unknownJob) }
      if value.decision?.phase == .refused || value.decision?.phase == .settled { return .cancellation(acknowledged: false, settled: true) }
      guard let binding = value.pending?.binding, let control else { return .cancellation(acknowledged: true, settled: false) }
      let cancellation = await control.cancel(binding)
      return .cancellation(acknowledged: true, settled: cancellation.settled)
    case .exportResult(let job):
      let value = try await transition { try await self.lookup(.job(job), engine: engine) }
      guard let decision = value?.decision, decision.phase == .refused else { return .refused(.preparationUnavailable) }
      let returns = self.returns, library = self.library
      let destination = returns.appendingPathComponent(job.job.uuidString.lowercased() + ".zip")
      try await Task.detached {
        try FileManager.default.createDirectory(at: returns, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try await DrawingDestinationResult.export(decision, library: library, to: destination)
      }.value
      return .result(destination)
    }
  }
  public func closeAdmission() { closing = true }
  public func close() async {
    closeAdmission()
    if inFlightOperationCount > 0 { await withCheckedContinuation { drainWaiters.append($0) } }
    await tail?.value
  }
  public func nativeIdentity() async throws -> (engine: UUID, namespace: UUID) {
    guard !closing else { throw DrawingLibraryError.closed }
    return try await transition {
      let engine = try await self.engine()
      let kind = "adaptiveplotter.destination.native-client"
      if let identity = try await self.read(Identity.self, kind: kind, id: Self.clientID) { return (engine, identity.engine) }
      let client = Identity(engine: UUID())
      try await self.library.commitRecords([.init(kind: kind, id: Self.clientID, payload: try DrawingArtifactCoding.encoder().encode(client))])
      return (engine, client.engine)
    }
  }
  public func retainProposal(_ bytes: Data, for binding: DrawingJobIssuance) async throws -> ExchangeAsset {
    let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: "adaptiveplotter.drawing-run-proposal/1")
    return try await transition {
      var value = try await self.bound(binding)
      guard var pending = value.pending else { throw DrawingDestinationRefusal.unknownJob }
      if let old = pending.proposal { guard old == asset else { throw DrawingDestinationRefusal.requestConflict }; return old }
      guard value.decision == nil else { throw DrawingDestinationRefusal.alreadySettled }
      pending.proposal = asset; value.pending = pending
      try await self.save(value, key: binding.key, assets: [.init(descriptor: .init(asset: asset), bytes: bytes)])
      return asset
    }
  }
  public func staged(_ binding: DrawingJobIssuance, run: UUID) async throws {
    try await transition {
      var value = try await self.bound(binding)
      guard var pending = value.pending, pending.stagedRun == nil || pending.stagedRun == run else { throw DrawingDestinationRefusal.requestConflict }
      pending.stagedRun = run; value.pending = pending
      try await self.save(value, key: binding.key)
    }
  }
  public func acceptedLink(_ binding: DrawingJobIssuance, run: UUID) async throws -> DrawingJobDecision {
    try await transition {
      var value = try await self.bound(binding)
      if let existing = value.decision {
        guard existing.reason == nil, value.pending?.stagedRun == run else { throw DrawingDestinationRefusal.requestConflict }
        return existing
      }
      guard var pending = value.pending, pending.proposal != nil, pending.stagedRun == nil || pending.stagedRun == run else { throw DrawingDestinationRefusal.preparationUnavailable }
      pending.stagedRun = run; value.pending = pending
      let decision = try self.makeDecision(binding, ticket: value.ticket, reason: nil, run: run)
      value.decision = pending.cancellationRequested ? Self.phase(decision, .cancelRequested) : decision
      try await self.save(value, key: binding.key)
      return value.decision!
    }
  }
  public func refuseBeforeStage(_ binding: DrawingJobIssuance, reason: DrawingDestinationRefusal) async throws -> DrawingJobDecision {
    try await transition {
      var value = try await self.bound(binding)
      if let decision = value.decision { return decision }
      guard value.pending?.stagedRun == nil else { throw DrawingDestinationRefusal.alreadySettled }
      let decision = try self.makeDecision(binding, ticket: value.ticket, reason: reason, run: nil)
      value.decision = decision
      try await self.save(value, key: binding.key)
      return decision
    }
  }
  public func settle(_ binding: DrawingJobIssuance, run: UUID) async throws {
    try await transition {
      var value = try await self.bound(binding)
      guard let decision = value.decision, decision.reason == nil, value.pending?.stagedRun == run else { throw DrawingDestinationRefusal.requestConflict }
      if decision.phase == .settled { return }
      value.decision = Self.phase(decision, .settled)
      try await self.save(value, key: binding.key)
    }
  }
  public func cancellationRequested(_ binding: DrawingJobIssuance) async throws -> Bool {
    try await transition { try await self.bound(binding).pending?.cancellationRequested ?? false }
  }
  private func recoverReply(_ value: Admission) async throws -> DrawingDestinationReply {
    guard let pending = value.pending, let control,
      value.decision?.phase != .refused else { return reply(value) }
    if value.decision?.phase == .settled {
      // The decision is already durable. Repair only the original live Run's
      // lost terminal-link acknowledgement; historical jobs need no artwork
      // load, raw proof replay or new publication/admission.
      if let run = pending.stagedRun {
        await control.publishedSettlement(pending.binding, run: run)
      }
      return reply(value)
    }
    return try await reconcile(pending.binding)
  }
  /// Startup observes only retained current job metadata. Raw lookup/proof may
  /// repair its publication; it cannot stage, admit or acquire live permission.
  public func recoverPendingJobs() async throws {
    guard !closing else { throw DrawingLibraryError.closed }
    inFlightOperationCount += 1
    defer {
      inFlightOperationCount -= 1
      if inFlightOperationCount == 0 {
        let waiting = drainWaiters; drainWaiters.removeAll(); waiting.forEach { $0.resume() }
      }
    }
    let values: [Admission] = try await transition {
      try await self.library.records(kind: self.pendingKind).map {
        try JSONDecoder().decode(Admission.self, from: $0.payload)
      }
    }
    for value in values {
      guard !closing, !Task.isCancelled else { return }
      _ = try await recoverReply(value)
    }
  }
  /// Recovery is observation/publication only. It never invokes an admission port.
  public func reconcile(_ binding: DrawingJobIssuance) async throws -> DrawingDestinationReply {
    guard let control else { return .refused(.issuanceSeamUnavailable) }
    switch await control.lookup(binding) {
    case .unknown: break
    case .absent:
      let staged = try await transition { try await self.bound(binding).pending?.stagedRun }
      if staged == nil { _ = try await refuseBeforeStage(binding, reason: .interrupted) }
    case .staged(let run, let settled):
      _ = try await acceptedLink(binding, run: run)
      if settled {
        try await settle(binding, run: run)
        await control.publishedSettlement(binding, run: run)
      }
      else {
        try await transition {
          var value = try await self.bound(binding)
          if let decision = value.decision, decision.phase != .settled && decision.phase != .cancelRequested {
            value.decision = Self.phase(decision, .reconciling); try await self.save(value, key: binding.key)
          }
        }
      }
    }
    return try await transition { self.reply(try await self.bound(binding)) }
  }
  private func bound(_ binding: DrawingJobIssuance) async throws -> Admission {
    guard let value = try await readAdmission(binding.key), value.pending?.binding == binding else { throw DrawingDestinationRefusal.requestConflict }
    return value
  }
  private func engine() async throws -> UUID {
    try await library.open()
    if let record = try await read(Identity.self, kind: identityKind, id: Self.identityID) { return record.engine }
    let identity = Identity(engine: UUID())
    try await library.commitRecords([.init(kind: identityKind, id: Self.identityID, payload: try DrawingArtifactCoding.encoder().encode(identity))])
    return identity.engine
  }
  private func read<T: Decodable>(_ type: T.Type, kind: String, id: UUID) async throws -> T? {
    guard let record = try await library.record(.init(kind: kind, id: id)) else { return nil }
    return try JSONDecoder().decode(type, from: record.payload)
  }
  private func readAdmission(_ key: DrawingRequestKey) async throws -> Admission? { try await read(Admission.self, kind: key.recordKind, id: key.request) }
  private func lookup(_ lookup: DrawingJobLookup, engine: UUID) async throws -> Admission? {
    switch lookup {
    case .request(let key): return try await readAdmission(key)
    case .job(let job):
      guard job.engine == engine else { return nil }
      if let decision = try await read(DrawingJobDecision.self, kind: jobKind, id: job.job) {
        return try await readAdmission(decision.key) ?? Admission(digest: decision.requestDigest, ticket: decision.ticket, decision: decision)
      }
      return try await read(Admission.self, kind: pendingKind, id: job.job)
    }
  }
  private func reply(_ value: Admission) -> DrawingDestinationReply {
    if let decision = value.decision { return .decision(decision) }
    if let pending = value.pending { return .pending(pending) }
    return .refused(.stalePreview)
  }
  private func save(_ value: Admission, key: DrawingRequestKey, assets: [DrawingLibraryClosureAsset] = []) async throws {
    let refs = [value.ticket.facts.plan.object, value.ticket.facts.options.object] + [value.pending?.proposal?.object].compactMap { $0 }
    let payload = try DrawingArtifactCoding.encoder().encode(value)
    var records = [DrawingLibraryRecord(kind: key.recordKind, id: key.request, payload: payload, drawings: [value.ticket.facts.drawing], assets: refs)]
    if let pending = value.pending { records.append(.init(kind: pendingKind, id: pending.binding.job.job, payload: payload, drawings: [pending.binding.drawing], assets: refs)) }
    if let decision = value.decision { records.append(.init(kind: jobKind, id: decision.job.handle.job, payload: try DrawingArtifactCoding.encoder().encode(decision), drawings: [value.ticket.facts.drawing], assets: refs)) }
    try await library.commitRecords(records, assets: assets)
  }
  private static func phase(_ decision: DrawingJobDecision, _ phase: DrawingJobPhase) -> DrawingJobDecision {
    .init(key: decision.key, requestDigest: decision.requestDigest, job: decision.job, ticket: decision.ticket,
      reason: decision.reason, receipt: decision.receipt, phase: phase)
  }
  static func assets(_ preparation: DrawingPreparation) -> [DrawingLibraryClosureAsset] {
    [.init(descriptor: .init(asset: preparation.facts.plan), bytes: preparation.planBytes), .init(descriptor: .init(asset: preparation.facts.options), bytes: preparation.optionsBytes)]
  }
  private func makeDecision(_ binding: DrawingJobIssuance, ticket: DrawingPreparedTicket, reason: DrawingDestinationRefusal?, run: UUID?) throws -> DrawingJobDecision {
    let encoder = DrawingArtifactCoding.encoder()
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
    var json: [String: Any] = ["profile": "adaptiveplotter.plot-job-receipt/1", "requiredFeatures": [String](),
      "handle": try object(binding.job), "client": ["namespace": binding.key.namespace.uuidString.lowercased(), "request": binding.key.request.uuidString.lowercased(), "requestDigest": binding.requestDigest.description],
      "drawing": try object(binding.drawing), "preparedPlan": try object(binding.preparedPlan), "requestedMediumOptions": try object(binding.options),
      "issuedAt": ["wallTime": ISO8601DateFormatter().string(from: Date())], "disposition": reason == nil ? "accepted" : "refused"]
    if let reason { json["reason"] = reason.rawValue }
    else { json["issuance"] = binding.issuance.uuidString.lowercased(); json["reason"] = "native-plot-admitted" }
    let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
    _ = try ExchangeJobReceipt(originalJSON: bytes)
    return .init(key: binding.key, requestDigest: binding.requestDigest, job: .init(handle: binding.job, receiptDigest: .hash(bytes)), ticket: ticket,
      reason: reason, receipt: bytes, phase: reason == nil ? .accepted : .refused)
  }
}
