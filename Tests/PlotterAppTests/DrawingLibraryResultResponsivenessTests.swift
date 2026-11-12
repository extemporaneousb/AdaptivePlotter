import Foundation
import CSQLite
import os
@testable import DrawingLibrary
@testable import Drawing
@testable import PortraitCore
@testable import PortraitLibrary
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterRuntime
import Testing
@testable import PlotterApp

// A one-shot hold on a real synchronous file or codec callback. Its timeout
// turns a blocked actor into a failed assertion instead of hanging the suite.
private final class LibraryResultGate: @unchecked Sendable {
  private let condition = NSCondition()
  private var armed = false
  private var held = false
  private var expired = false

  func arm() { condition.lock(); armed = true; condition.unlock() }

  @discardableResult func holdOnce() -> Bool {
    condition.lock(); defer { condition.unlock() }
    guard armed else { return false }
    armed = false
    held = true
    let deadline = Date().addingTimeInterval(12)
    while held, condition.wait(until: deadline) {}
    expired = held
    held = false
    return true
  }

  var timedOut: Bool {
    condition.lock(); defer { condition.unlock() }
    return expired
  }

  var isHeld: Bool {
    condition.lock(); defer { condition.unlock() }
    return held
  }

  func release() {
    condition.lock(); armed = false; held = false; condition.broadcast(); condition.unlock()
  }

  func waitUntilHeld() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(8))
    while !isHeld, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(isHeld, "The selected real storage or payload operation did not enter")
  }
}

private extension DrawingLibrary {
  func observeResultStorage(_ fault: @escaping @Sendable (LibraryExchangeStorageFault) throws -> Void) throws {
    // Keep the original connection and lease. Install the same catalog's existing
    // fault callback on this disposable owner before beginning the operation.
    cachedExchangeCatalog = try LibraryExchangeCatalog(database: libraryDatabase(), storageFault: fault)
    refreshOwnership()
  }

  func installResultSQLPressure(_ digest: ExchangeDigest, armed: @escaping @Sendable (UUID) -> Bool) throws -> Int {
    let catalog = try commonCatalog(), db = catalog.database
    let pageLimit = try #require(try db.scalar("PRAGMA max_page_count").flatMap(Int.init))
    catalog.injectFault = { boundary in
      guard boundary == .beforeSQLCommit,
        let id = try db.scalar("SELECT id FROM dx_transaction WHERE package_digest=?", [digest.description]),
        let transaction = UUID(uuidString: id), armed(transaction) else { return }
      let pages = try #require(try db.scalar("PRAGMA page_count").flatMap(Int.init))
      let size = try #require(try db.scalar("PRAGMA page_size").flatMap(Int.init))
      let bytes = (pages + 1) * size
      // A blob larger than the entire disposable database cannot fit at this
      // page limit. SQLite must raise FULL and roll back the actual transaction.
      try #require(bytes > 0 && bytes < 128 * 1024 * 1024)
      try db.execute("PRAGMA max_page_count=" + String(pages))
      try db.execute("UPDATE dx_transaction SET intent=zeroblob(?) WHERE id=?", [String(bytes), id])
      Issue.record("SQLite unexpectedly accepted a blob larger than its page limit")
      throw DrawingLibraryError.invalidIdentity
    }
    return pageLimit
  }

  func restoreSQLPageLimit(_ pages: Int) throws {
    // Restore free space via the same connection, without implicitly retrying
    // the failed journal. The result-only fault remains armed for its next commit.
    let db = try libraryDatabase()
    try #require(db.isOutsideTransaction)
    try db.execute("PRAGMA max_page_count=" + String(pages))
    refreshOwnership()
  }

  func publishedTransaction(_ digest: ExchangeDigest) throws -> UUID? {
    try commonCatalog().publishedTransaction(digest)
  }

  func publicationCount(_ digest: ExchangeDigest) throws -> Int {
    let db = try libraryDatabase()
    return Int(try db.scalar("SELECT COUNT(*) FROM dx_transaction WHERE package_digest=?", [digest.description]) ?? "") ?? -1
  }
}

@Suite("Drawing Library result responsiveness", .serialized)
@MainActor struct DrawingLibraryResultResponsivenessTests {
  enum Operation: String, CaseIterable, Sendable {
    case importValidation, privateBagCopy, installedBlobCopy, inspection, reexport
  }

  private func makeSource(_ fixture: DrawingRunEpisodeFixture, in directory: URL) async throws -> (URL, ValidatedExchangePackage) {
    let source = await drawingRunHarness(fixture: fixture, outcome: .cancelled)
    let ready = await source.runtime.synchronize(environment: .live)
    _ = await source.submit(.init(projection: ready.projection, intent: .start))
    let settled = try await issuanceSettled(source.runtime)
    let record = try #require(settled.terminal?.record)
    let binding = try #require(record.attemptEvidence?.intent.issuance)
    guard case .result(let zip) = try await source.destination.service.handle(.exportResult(binding.job)) else {
      throw DrawingLibraryError.unavailable("Native result export failed")
    }
    let copy = directory.appendingPathComponent("source.zip")
    try FileManager.default.copyItem(at: zip, to: copy)
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(copy, stagingParent: directory),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let raw = try await source.evidence.exportAttempt(runID: record.runID)
    let snapshot = try #require(admitted.index.known?.attempts.first.flatMap { admitted.attempts[$0] })
    #expect(try admitted.files.record(try #require(snapshot.terminalRecord)) == raw.recordJSON)
    await source.destination.close()
    return (copy, admitted)
  }

  private func cancelAndSettle(_ h: DrawingRunRuntimeHarness, lookup: DrawingRequestKey,
    initial: DrawingJobDecision) async throws {
    let service = h.destination.service
    guard case .decision(let current) = try await service.handle(.status(.request(lookup))) else {
      throw DrawingLibraryError.unavailable("Active job absent during result work")
    }
    #expect(current.receipt == initial.receipt)
    guard case .cancellation(let acknowledged, _) = try await service.handle(.cancel(.job(initial.job.handle))) else {
      throw DrawingLibraryError.unavailable("Cancel did not return an acknowledgement")
    }
    #expect(acknowledged)
    let settled = try await issuanceSettled(h.runtime)
    #expect(settled.terminal?.record != nil)
    #expect(await h.interpreter.stopIntents.count == 1)
    #expect(await h.interpreter.planRequests.count == 1)
    guard case .decision(let final) = try await service.handle(.status(.request(lookup))) else {
      throw DrawingLibraryError.unavailable("Settled job missing")
    }
    #expect(final.phase == .settled && final.receipt == initial.receipt)
  }

  @Test("A held browser operation permits Status, durable Cancel and lower Run settlement before release",
    arguments: Operation.allCases)
  func controlsDuringResultWork(_ operation: Operation) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let (source, original) = try await makeSource(fixture, in: directory)
    let gate = LibraryResultGate(), plan = DrawingRunPlanGate()
    defer { gate.release() }
    let key = ExchangePayloadKey(encoding: DrawingNativeResultCodec.terminalEncoding, version: "1")
    var validators = DrawingDestinationResult.payloadValidators.validators
    let native = try #require(validators[key])
    validators[key] = { context in
      if operation == .importValidation || operation == .inspection || operation == .reexport { gate.holdOnce() }
      return try native(context)
    }
    let h = await drawingRunHarness(fixture: fixture, planGate: plan, payloadValidators: .init(validators))
    let library = h.destination.library
    let known = try #require(original.index.known)
    let selected = try #require(known.attempts.first)
    let terminal = try #require(original.attempts[selected]?.terminalRecord)
    if operation == .privateBagCopy || operation == .installedBlobCopy {
      try await library.observeResultStorage { event in
        if operation == .privateBagCopy && event.boundary == .duringBagCopy ||
          operation == .installedBlobCopy && event.boundary == .afterBlobCopy && event.path == terminal.description {
          gate.holdOnce()
        }
      }
    }
    let mounted: DrawingLibraryResultMount?
    if operation == .inspection || operation == .reexport { mounted = try await library.mountResult(from: source) }
    else { mounted = nil }

    let ready = await h.runtime.synchronize(environment: .live)
    let ack = await h.runtime.submit(.init(projection: ready.projection, intent: .start))
    try #require(ack.disposition == .applied)
    await plan.waitUntilStarted()
    let lookup = try #require(h.destination.lastKey)
    let service = h.destination.service
    guard case .decision(let initial) = try await service.handle(.status(.request(lookup))) else {
      throw DrawingLibraryError.unavailable("Active job missing")
    }
    let output = directory.appendingPathComponent("reexport.zip")
    gate.arm()
    let result = Task { () throws -> ValidatedExchangePackage in
      switch operation {
      case .inspection:
        return try await library.result(#require(mounted).reference)
      case .reexport:
        try await library.exportResult(#require(mounted).reference, to: output)
        return try ExchangeAdmission.validate(DrawingExchangeCarrier.stageZIP(output, stagingParent: directory),
          payloadValidators: DrawingDestinationResult.payloadValidators)
      default:
        let value = try await library.mountResult(from: source)
        #expect(!value.wasAlreadyMounted)
        return try await library.result(value.reference)
      }
    }
    try await gate.waitUntilHeld()
    try await cancelAndSettle(h, lookup: lookup, initial: initial)
    #expect(!gate.timedOut)
    #expect(gate.isHeld, "Status, durable Cancel and lower settlement must complete before the bulk operation resumes")
    gate.release()
    let admitted = try await result.value
    #expect(admitted.capabilities.supported.contains(.interpretResults))
    #expect(admitted.files.entries.mapValues(\.digest) == original.files.entries.mapValues(\.digest))
    #expect(admitted.index.originalJSON == original.index.originalJSON)
    #expect(try admitted.files.record(terminal) == original.files.record(terminal))
    #expect(Set(admitted.attempts.keys) == Set(original.attempts.keys))
    #expect(Set(admitted.receipts.keys) == Set(original.receipts.keys))
    let duplicate = try await library.mountResult(from: source)
    #expect(duplicate.wasAlreadyMounted && duplicate.reference.indexDigest == .hash(original.index.originalJSON))
    #expect(try await library.publicationCount(duplicate.reference.packageDigest) == 1)
    await h.destination.close()
  }

  @Test("Concurrent equal installs keep one publication and close drains the retained lease")
  func duplicateAndClose() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (zip, original) = try await makeSource(DrawingRunEpisodeFixtureCache.load(), in: directory)
    let root = directory.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: root, payloadValidators: DrawingDestinationResult.payloadValidators)
    let next = DrawingLibrary(directoryURL: root, payloadValidators: DrawingDestinationResult.payloadValidators)
    let gate = LibraryResultGate()
    defer { gate.release() }
    var seen = Set<ExchangeDigest>()
    let last = try #require(original.files.entries.values.sorted { $0.path < $1.path }.filter { seen.insert($0.digest).inserted }.last)
    let ownBarrier = OSAllocatedUnfairLock(initialState: false)
    try await owner.observeResultStorage { event in
      if event.boundary == .afterBlobInstall, event.path == last.digest.description { gate.holdOnce() }
      if event.boundary == .afterBlobDirectorySync, event.path == "objects/sha256", gate.isHeld {
        ownBarrier.withLock { $0 = true }
      }
    }
    gate.arm()
    let first = Task { try await owner.mountResult(from: zip) }
    try await gate.waitUntilHeld()
    let second = try await owner.mountResult(from: zip)
    #expect(!second.wasAlreadyMounted && gate.isHeld)
    #expect(ownBarrier.withLock { $0 }, "The second installer must sync its CAS directory before acknowledgement even when every object name exists")
    let closing = Task { await owner.closeLibrary() }
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !(await owner.closed), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(await owner.closed)
    do { try await next.open(); Issue.record("Close released the writer while its object install was active") }
    catch DrawingLibraryError.writerBusy {}
    #expect(gate.isHeld && !gate.timedOut)
    gate.release()
    let replay = try await first.value
    #expect(replay.wasAlreadyMounted && replay.reference == second.reference)
    await closing.value
    try await next.open()
    #expect(try await next.publicationCount(replay.reference.packageDigest) == 1)
    #expect(try await next.result(replay.reference).index.originalJSON == original.index.originalJSON)
    let remaining = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("exchange-staging").path)
    #expect(remaining.isEmpty)
    await next.closeLibrary()
  }

  @Test("A persistent result CAS or SQLite capacity failure leaves live control available and retries the exact journal",
    arguments: [false, true])
  func persistentInstallFailure(sqlPressure: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fixture = try await DrawingRunEpisodeFixtureCache.load()
    let (source, original) = try await makeSource(fixture, in: directory)
    let selected = try #require(original.index.known?.attempts.first)
    let terminal = try #require(original.attempts[selected]?.terminalRecord)
    let failure = OSAllocatedUnfairLock(initialState: (armed: true, ids: [UUID](), installRetries: 0))
    let plan = DrawingRunPlanGate()
    let h = await drawingRunHarness(fixture: fixture, planGate: plan)
    let library = h.destination.library
    try await library.observeResultStorage { event in
      guard let id = event.transactionID else { return }
      try failure.withLock { value in
        guard value.armed else { return }
        if event.boundary == .afterBlobDirectorySync, event.path == "objects/sha256", value.ids.contains(id) {
          value.installRetries += 1
        }
        if !sqlPressure, event.boundary == .afterBlobCopy, event.path == terminal.description {
          value.ids.append(id)
          throw CocoaError(.fileWriteOutOfSpace)
        }
      }
    }
    let pageLimit: Int?
    if sqlPressure {
      let digest = LibraryExchangeCatalog.inventoryDigest(original.files.entries.values.map {
        .init(path: $0.path, digest: $0.digest, byteLength: $0.byteLength)
      })
      pageLimit = try await library.installResultSQLPressure(digest) { id in
        failure.withLock { value in
          guard value.armed else { return false }
          value.ids.append(id)
          return true
        }
      }
    } else { pageLimit = nil }
    func failMount() async throws {
      do {
        _ = try await library.mountResult(from: source)
        Issue.record("Result unexpectedly published with its storage fault armed")
      } catch DrawingLibraryDatabaseError.retryableSQLite(let code, _) where sqlPressure {
        #expect(code == SQLITE_FULL)
      } catch let error as CocoaError where !sqlPressure {
        #expect(error.code == .fileWriteOutOfSpace)
      }
      if let pageLimit { try await library.restoreSQLPageLimit(pageLimit) }
    }
    let ready = await h.runtime.synchronize(environment: .live)
    try #require(await h.runtime.submit(.init(projection: ready.projection, intent: .start)).disposition == .applied)
    await plan.waitUntilStarted()
    let lookup = try #require(h.destination.lastKey)
    guard case .decision(let initial) = try await h.destination.service.handle(.status(.request(lookup))) else {
      throw DrawingLibraryError.unavailable("Active job missing")
    }
    try await failMount()
    let id = try #require(failure.withLock { $0.ids.first })
    try await cancelAndSettle(h, lookup: lookup, initial: initial)
    #expect(failure.withLock { $0.ids } == [id], "Live controls must not retry the unrelated failed result install")
    #expect(failure.withLock { $0.installRetries } == 0)
    try await failMount()
    #expect(failure.withLock { $0.ids } == [id, id])
    if sqlPressure { #expect(failure.withLock { $0.installRetries } == 1) }
    failure.withLock { $0.armed = false }
    let resumed = try await library.mountResult(from: source)
    #expect(!resumed.wasAlreadyMounted)
    #expect(try await library.publishedTransaction(resumed.reference.packageDigest) == id)
    #expect(try await library.publicationCount(resumed.reference.packageDigest) == 1)
    let admitted = try await library.result(resumed.reference)
    #expect(admitted.index.originalJSON == original.index.originalJSON)
    #expect(admitted.files.entries.mapValues(\.digest) == original.files.entries.mapValues(\.digest))
    #expect(try FileManager.default.contentsOfDirectory(atPath: library.directoryURL.appendingPathComponent("exchange-staging").path).isEmpty)
    await h.destination.close()
  }

  @Test("An abandoned duplicate with a damaged durable bag fails same-owner and cold recovery")
  func damagedPendingDuplicate() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (source, original) = try await makeSource(DrawingRunEpisodeFixtureCache.load(), in: directory)
    let root = directory.appendingPathComponent("library")
    let owner = DrawingLibrary(directoryURL: root, payloadValidators: DrawingDestinationResult.payloadValidators)
    let pending = OSAllocatedUnfairLock<UUID?>(initialState: nil)
    let gate = LibraryResultGate()
    defer { gate.release() }
    try await owner.observeResultStorage { event in
      if event.boundary == .afterBlobCopy, gate.holdOnce() {
        pending.withLock { $0 = event.transactionID }
        throw CocoaError(.fileWriteOutOfSpace)
      }
    }
    gate.arm()
    let originalMount = Task { try await owner.mountResult(from: source) }
    try await gate.waitUntilHeld()
    let winner = try await owner.mountResult(from: source)
    #expect(!winner.wasAlreadyMounted && gate.isHeld && !gate.timedOut)
    gate.release()
    await #expect(throws: CocoaError.self) { try await originalMount.value }
    let id = try #require(pending.withLock { $0 })
    let journal = root.appendingPathComponent("exchange-staging/" + id.uuidString.lowercased())
    try Data("damaged pending file".utf8).write(to: journal.appendingPathComponent("bag/bagit.txt"), options: .atomic)
    await #expect(throws: (any Error).self) { try await owner.mountResult(from: source) }
    await #expect(throws: (any Error).self) { try await owner.recover() }
    #expect(try await owner.result(winner.reference).index.originalJSON == original.index.originalJSON)
    await owner.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: root)
    await #expect(throws: (any Error).self) { try await reopened.open() }
    #expect(FileManager.default.fileExists(atPath: journal.appendingPathComponent("journal.json").path))
    await reopened.closeLibrary()
  }
}
