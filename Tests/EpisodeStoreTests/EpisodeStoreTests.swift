import Darwin
import EpisodeCore
import EpisodeRuntime
import Foundation
import Testing

@Suite("EpisodeStore atomic journal contract")
struct EpisodeStoreTests {
  @Test("append commits an ordered journal and reopen reconstructs state")
  func appendAndReopen() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }

    let store = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )
    let first = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 2,
      digest: "count-2"
    )
    let second = Fixtures.event(
      id: Fixtures.secondEventID,
      sequence: sequence(1),
      preRevision: revision(1),
      postRevision: revision(2),
      amount: 3,
      digest: "count-5",
      causation: EpisodeEventCausation(eventID: first.id)
    )

    let firstReduction = try await store.append(first)
    let committedReduction = try await store.append(second)

    #expect(firstReduction.state.count == 2)
    #expect(firstReduction.effects == [.observed(2)])
    #expect(committedReduction.state.count == 5)
    #expect(committedReduction.state.revision == revision(2))
    #expect(committedReduction.state.canonicalDigest == digest("count-5"))
    #expect(committedReduction.effects == [.observed(3)])
    #expect(try fixture.adapter.load()?.events == [first, second])

    let reopened = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )
    #expect(await reopened.currentState() == committedReduction.state)
    #expect(await reopened.currentJournal().events == [first, second])
  }

  @Test("event episode, sequence, and revision violations never reach persistence")
  func eventValidationPrecedesPersistence() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let store = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )

    let wrongEpisode = Fixtures.event(
      id: Fixtures.firstEventID,
      episodeID: Fixtures.otherEpisodeID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )
    await #expect(throws: EpisodeJournalValidationError.episodeMismatch(
      index: 0,
      expected: Fixtures.episodeID,
      actual: Fixtures.otherEpisodeID
    )) {
      try await store.append(wrongEpisode)
    }

    let wrongSequence = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: sequence(1),
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )
    await #expect(throws: EpisodeJournalValidationError.sequenceMismatch(
      index: 0,
      expected: .first,
      actual: sequence(1)
    )) {
      try await store.append(wrongSequence)
    }

    let wrongPreRevision = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: revision(7),
      postRevision: revision(8),
      amount: 1,
      digest: "count-1"
    )
    await #expect(throws: EpisodeJournalValidationError.preStateRevisionMismatch(
      index: 0,
      expected: .initial,
      actual: revision(7)
    )) {
      try await store.append(wrongPreRevision)
    }

    let wrongPostRevision = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(2),
      amount: 1,
      digest: "count-1"
    )
    await #expect(throws: EpisodeJournalValidationError.postStateRevisionMismatch(
      index: 0,
      expected: revision(1),
      actual: revision(2)
    )) {
      try await store.append(wrongPostRevision)
    }

    #expect(await store.currentState() == Fixtures.initialState)
    #expect(await store.currentJournal().events.isEmpty)
    #expect(try fixture.adapter.load() == nil)
  }

  @Test(
    "reducer episode, revision, and digest mismatches leave journal and state unchanged",
    arguments: [
      ReducerFault.wrongEpisode,
      ReducerFault.wrongRevision,
      ReducerFault.wrongDigest,
    ]
  )
  func reducerValidation(fault: ReducerFault) async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let reducer = CounterReducer(fault: fault)
    let store = try EpisodeStore<CounterReducer, FileAdapter>.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: reducer,
      persistence: fixture.adapter
    )
    let event = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )

    switch fault {
    case .wrongEpisode:
      await #expect(throws: EpisodeStoreValidationError.reducerOutputEpisodeMismatch(
        index: 0,
        expected: Fixtures.episodeID,
        actual: Fixtures.otherEpisodeID
      )) {
        try await store.append(event)
      }
    case .wrongRevision:
      await #expect(throws: EpisodeStoreValidationError.reducerOutputRevisionMismatch(
        index: 0,
        expected: revision(1),
        actual: revision(99)
      )) {
        try await store.append(event)
      }
    case .wrongDigest:
      await #expect(throws: EpisodeStoreValidationError.reducerOutputDigestMismatch(
        index: 0,
        expected: digest("count-1"),
        actual: digest("wrong-digest")
      )) {
        try await store.append(event)
      }
    }

    #expect(await store.currentState() == Fixtures.initialState)
    #expect(await store.currentJournal().events.isEmpty)
    #expect(try fixture.adapter.load() == nil)
  }

  @Test("a failed durable commit publishes neither journal nor state")
  func atomicCommitFailure() async throws {
    let persistence = RejectingPersistence()
    let store = try EpisodeStore<CounterReducer, RejectingPersistence>.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: persistence
    )
    let event = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )

    await #expect(throws: ForcedPersistenceError.commitRejected) {
      try await store.append(event)
    }

    #expect(await store.currentState() == Fixtures.initialState)
    #expect(await store.currentJournal().events.isEmpty)
    #expect(try persistence.load() == nil)
  }

  @Test("missing destination directory is refused without creating ancestry")
  func missingDestinationDirectory() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let missingDirectoryURL = fixture.directoryURL
      .appendingPathComponent("missing", isDirectory: true)
    let adapter = FileAdapter(
      fileURL: missingDirectoryURL.appendingPathComponent("episode-journal.json"),
      journalSchemaRevision: Fixtures.journalSchemaRevision
    )
    let store = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: adapter
    )
    let event = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )

    await #expect(throws: EpisodeJournalPersistenceError.destinationDirectoryMissing) {
      try await store.append(event)
    }

    #expect(!FileManager.default.fileExists(atPath: missingDirectoryURL.path))
    #expect(await store.currentState() == Fixtures.initialState)
    #expect(await store.currentJournal().events.isEmpty)
  }

  @Test("real pre-rename failure preserves prior durable journal and actor state")
  func preRenameFailurePreservesPriorCommit() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let store = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )
    let first = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )
    let successor = Fixtures.event(
      id: Fixtures.secondEventID,
      sequence: sequence(1),
      preRevision: revision(1),
      postRevision: revision(2),
      amount: 1,
      digest: "count-2",
      causation: EpisodeEventCausation(eventID: first.id)
    )
    _ = try await store.append(first)
    let committedBytes = try Data(contentsOf: fixture.fileURL)

    var directoryStatus = Darwin.stat()
    let statusResult = fixture.directoryURL.path.withCString { path in
      Darwin.lstat(path, &directoryStatus)
    }
    try #require(statusResult == 0)
    let originalMode = mode_t(directoryStatus.st_mode & mode_t(0o7777))
    var permissionsNeedRestore = true
    defer {
      if permissionsNeedRestore {
        fixture.directoryURL.path.withCString { path in
          _ = Darwin.chmod(path, originalMode)
        }
      }
    }
    let readExecuteOnly = mode_t(S_IRUSR | S_IXUSR)
    let restrictionResult = fixture.directoryURL.path.withCString { path in
      Darwin.chmod(path, readExecuteOnly)
    }
    try #require(restrictionResult == 0)

    var observedExpectedFailure = false
    do {
      _ = try await store.append(successor)
      Issue.record("non-writable destination directory should refuse temp creation")
    } catch let error as EpisodeJournalPersistenceError {
      if case .temporaryFileCreationFailed = error {
        observedExpectedFailure = true
      } else {
        Issue.record("unexpected persistence error: \(error)")
      }
    } catch {
      Issue.record("unexpected error type: \(error)")
    }

    let restorationResult = fixture.directoryURL.path.withCString { path in
      Darwin.chmod(path, originalMode)
    }
    try #require(restorationResult == 0)
    permissionsNeedRestore = false

    #expect(observedExpectedFailure)
    #expect(try Data(contentsOf: fixture.fileURL) == committedBytes)
    #expect(try fixture.adapter.load()?.events == [first])
    #expect(await store.currentJournal().events == [first])
    #expect(await store.currentState().revision == revision(1))
    #expect(await store.currentState().count == 1)
  }

  @Test("post-rename durability uncertainty does not publish actor state")
  func uncertainCommitDoesNotPublish() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let persistence = UncertainPersistence(base: fixture.adapter)
    let store = try EpisodeStore<CounterReducer, UncertainPersistence>.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: persistence
    )
    let event = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )

    let uncertainty = EpisodeJournalPersistenceError
      .postRenameDirectorySynchronizationUncertain(code: EIO)
    await #expect(throws: uncertainty) {
      try await store.append(event)
    }

    #expect(await store.currentState() == Fixtures.initialState)
    #expect(await store.currentJournal().events.isEmpty)

    let reopened = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )
    #expect(await reopened.currentState().count == 1)
    #expect(await reopened.currentJournal().events == [event])
  }

  @Test("versioned adapter refuses schema and format mismatches and corruption")
  func adapterRefusals() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let store = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )
    _ = try await store.append(Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    ))
    let originalEnvelope = try Data(contentsOf: fixture.fileURL)

    let wrongRevisionAdapter = FileAdapter(
      fileURL: fixture.fileURL,
      journalSchemaRevision: episodeRevision("journal-schema-v2")
    )
    #expect(throws: EpisodeJournalPersistenceError.journalSchemaRevisionMismatch(
      expected: episodeRevision("journal-schema-v2"),
      actual: Fixtures.journalSchemaRevision
    )) {
      _ = try wrongRevisionAdapter.load()
    }

    let decodedEnvelope = try JSONDecoder().decode(
      TestPersistedEpisodeJournalEnvelope.self,
      from: originalEnvelope
    )
    let unsupportedEnvelope = TestPersistedEpisodeJournalEnvelope(
      formatVersion: 99,
      journalSchemaRevision: decodedEnvelope.journalSchemaRevision,
      journalPayload: decodedEnvelope.journalPayload,
      payloadChecksum: decodedEnvelope.payloadChecksum
    )
    try encode(unsupportedEnvelope).write(to: fixture.fileURL, options: .atomic)
    #expect(throws: EpisodeJournalPersistenceError.unsupportedFormatVersion(
      expected: FileAdapter.currentFormatVersion,
      actual: 99
    )) {
      _ = try fixture.adapter.load()
    }

    try originalEnvelope.write(to: fixture.fileURL, options: .atomic)
    let corruptEnvelope = TestPersistedEpisodeJournalEnvelope(
      formatVersion: decodedEnvelope.formatVersion,
      journalSchemaRevision: decodedEnvelope.journalSchemaRevision,
      journalPayload: decodedEnvelope.journalPayload,
      payloadChecksum: "0000000000000000"
    )
    try encode(corruptEnvelope).write(to: fixture.fileURL, options: .atomic)
    #expect(throws: EpisodeJournalPersistenceError.payloadChecksumMismatch) {
      _ = try fixture.adapter.load()
    }

    try Data("not-an-envelope".utf8).write(to: fixture.fileURL, options: .atomic)
    #expect(throws: EpisodeJournalPersistenceError.corruptEnvelope) {
      _ = try fixture.adapter.load()
    }
  }

  @Test("duplicate append is refused before a second durable write")
  func duplicateAppend() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let store = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: fixture.adapter
    )
    let event = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )
    _ = try await store.append(event)
    let committedBytes = try Data(contentsOf: fixture.fileURL)

    await #expect(throws: EpisodeJournalValidationError.duplicateEventID(event.id)) {
      try await store.append(event)
    }

    #expect(try Data(contentsOf: fixture.fileURL) == committedBytes)
    #expect(await store.currentJournal().events == [event])
    #expect(await store.currentState().count == 1)
  }

  @Test("simultaneous stores commit exactly one successor for one journal base")
  func concurrentWriterRefusal() async throws {
    let fixture = try FileFixture()
    defer { fixture.remove() }
    let firstAdapter = FileAdapter(
      fileURL: fixture.fileURL,
      journalSchemaRevision: Fixtures.journalSchemaRevision
    )
    let secondAdapter = FileAdapter(
      fileURL: fixture.fileURL,
      journalSchemaRevision: Fixtures.journalSchemaRevision
    )
    let firstStore = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: firstAdapter
    )
    let secondStore = try FileStore.open(
      manifestID: Fixtures.manifestID,
      initialState: Fixtures.initialState,
      reducer: CounterReducer(),
      persistence: secondAdapter
    )
    let committed = Fixtures.event(
      id: Fixtures.firstEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 1,
      digest: "count-1"
    )
    let competing = Fixtures.event(
      id: Fixtures.competingEventID,
      sequence: .first,
      preRevision: .initial,
      postRevision: revision(1),
      amount: 4,
      digest: "count-4"
    )
    let barrier = StartBarrier(participantCount: 2)
    async let firstAttempt = attemptAppend(
      event: committed,
      to: firstStore,
      after: barrier
    )
    async let secondAttempt = attemptAppend(
      event: competing,
      to: secondStore,
      after: barrier
    )
    let firstResult = await firstAttempt
    let secondResult = await secondAttempt
    let attempts = [firstResult, secondResult]

    #expect(attempts.filter { $0.committed }.count == 1)
    #expect(attempts.filter { $0.conflicted }.count == 1)
    #expect(attempts.allSatisfy { $0.unexpectedError == nil })

    let durableJournal = try #require(try fixture.adapter.load())
    #expect(durableJournal.events.count == 1)
    let durableEvent = try #require(durableJournal.events.first)
    #expect(durableEvent == committed || durableEvent == competing)

    let firstState = await firstStore.currentState()
    let secondState = await secondStore.currentState()
    let committedStates = [firstState, secondState].filter { $0.revision == revision(1) }
    let unchangedStates = [firstState, secondState].filter { $0 == Fixtures.initialState }
    #expect(committedStates.count == 1)
    #expect(unchangedStates.count == 1)
    let committedState = try #require(committedStates.first)
    #expect(committedState.canonicalDigest == durableEvent.postStateDigest)
  }
}

private enum CounterPayload: Codable, Hashable, Sendable {
  case add(Int)

  var amount: Int {
    switch self {
    case let .add(value):
      return value
    }
  }
}

private struct TestPersistedEpisodeJournalEnvelope: Codable {
  let formatVersion: UInt64
  let journalSchemaRevision: EpisodeRevisionIdentifier
  let journalPayload: Data
  let payloadChecksum: String
}

private enum CounterEffect: Codable, Hashable, Sendable {
  case observed(Int)
}

private struct CounterState: EpisodeState {
  let episodeID: EpisodeID
  let revision: EpisodeStateRevision
  let canonicalDigest: EpisodeStateDigest
  let count: Int
}

enum ReducerFault: CaseIterable, Equatable, Sendable {
  case wrongEpisode
  case wrongRevision
  case wrongDigest
}

private struct CounterReducer: EpisodeReducing {
  let fault: ReducerFault?

  init(fault: ReducerFault? = nil) {
    self.fault = fault
  }

  func reduce(
    state: CounterState,
    event: EpisodeEvent<CounterPayload>
  ) -> EpisodeReduction<CounterState, CounterEffect> {
    let amount: Int
    switch event.payload {
    case let .add(value):
      amount = value
    }
    return EpisodeReduction(
      state: CounterState(
        episodeID: fault == .wrongEpisode ? Fixtures.otherEpisodeID : state.episodeID,
        revision: fault == .wrongRevision ? revision(99) : event.postStateRevision,
        canonicalDigest: fault == .wrongDigest
          ? digest("wrong-digest")
          : event.postStateDigest,
        count: state.count + amount
      ),
      effects: [.observed(amount)]
    )
  }
}

private typealias FileAdapter = EpisodeJournalPersistenceAdapter<CounterPayload>
private typealias FileStore = EpisodeStore<CounterReducer, FileAdapter>

private struct AppendAttempt: Sendable {
  let committed: Bool
  let conflicted: Bool
  let unexpectedError: String?
}

private func attemptAppend(
  event: EpisodeEvent<CounterPayload>,
  to store: FileStore,
  after barrier: StartBarrier
) async -> AppendAttempt {
  await barrier.arriveAndWait()
  do {
    let reduction = try await store.append(event)
    return AppendAttempt(
      committed: reduction.effects == [.observed(event.payload.amount)],
      conflicted: false,
      unexpectedError: nil
    )
  } catch let error as EpisodeJournalPersistenceError
    where error == .concurrentWriterConflict {
    return AppendAttempt(committed: false, conflicted: true, unexpectedError: nil)
  } catch {
    return AppendAttempt(
      committed: false,
      conflicted: false,
      unexpectedError: String(describing: error)
    )
  }
}

private actor StartBarrier {
  let participantCount: Int
  private var arrivals = 0
  private var continuations: [CheckedContinuation<Void, Never>] = []

  init(participantCount: Int) {
    self.participantCount = participantCount
  }

  func arriveAndWait() async {
    arrivals += 1
    if arrivals == participantCount {
      let waiting = continuations
      continuations.removeAll()
      for continuation in waiting {
        continuation.resume()
      }
      return
    }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }
}

private struct FileFixture {
  let directoryURL: URL
  let fileURL: URL
  let adapter: FileAdapter

  init() throws {
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("EpisodeStoreTests-\(UUID().uuidString)", isDirectory: true)
    fileURL = directoryURL.appendingPathComponent("episode-journal.json")
    try FileManager.default.createDirectory(
      at: directoryURL,
      withIntermediateDirectories: true
    )
    adapter = FileAdapter(
      fileURL: fileURL,
      journalSchemaRevision: Fixtures.journalSchemaRevision
    )
  }

  func remove() {
    try? FileManager.default.removeItem(at: directoryURL)
  }
}

private enum ForcedPersistenceError: Error, Equatable, Sendable {
  case commitRejected
}

private struct RejectingPersistence: EpisodeJournalPersisting {
  let journalSchemaRevision = Fixtures.journalSchemaRevision

  func load() throws -> EpisodeJournal<CounterPayload>? {
    nil
  }

  func commit(
    _: EpisodeJournal<CounterPayload>,
    replacing _: EpisodeJournal<CounterPayload>
  ) throws {
    throw ForcedPersistenceError.commitRejected
  }
}

private struct UncertainPersistence: EpisodeJournalPersisting {
  let base: FileAdapter

  var journalSchemaRevision: EpisodeRevisionIdentifier {
    base.journalSchemaRevision
  }

  func load() throws -> EpisodeJournal<CounterPayload>? {
    try base.load()
  }

  func commit(
    _ journal: EpisodeJournal<CounterPayload>,
    replacing expectedJournal: EpisodeJournal<CounterPayload>
  ) throws {
    try base.commit(journal, replacing: expectedJournal)
    throw EpisodeJournalPersistenceError
      .postRenameDirectorySynchronizationUncertain(code: EIO)
  }
}

private enum Fixtures {
  static let episodeID = EpisodeID(
    rawValue: uuid("00000000-0000-0000-0000-000000000001")
  )
  static let otherEpisodeID = EpisodeID(
    rawValue: uuid("00000000-0000-0000-0000-000000000002")
  )
  static let manifestID = EpisodeManifestID(
    rawValue: uuid("00000000-0000-0000-0000-000000000010")
  )
  static let firstEventID = EpisodeEventID(
    rawValue: uuid("00000000-0000-0000-0000-000000000020")
  )
  static let secondEventID = EpisodeEventID(
    rawValue: uuid("00000000-0000-0000-0000-000000000021")
  )
  static let competingEventID = EpisodeEventID(
    rawValue: uuid("00000000-0000-0000-0000-000000000022")
  )
  static let correlationID = EpisodeCorrelationID(
    rawValue: uuid("00000000-0000-0000-0000-000000000030")
  )
  static let journalSchemaRevision = episodeRevision("journal-schema-v1")
  static let initialState = CounterState(
    episodeID: episodeID,
    revision: .initial,
    canonicalDigest: digest("count-0"),
    count: 0
  )

  static func event(
    id: EpisodeEventID,
    episodeID: EpisodeID = episodeID,
    sequence: EpisodeEventSequence,
    preRevision: EpisodeStateRevision,
    postRevision: EpisodeStateRevision,
    amount: Int,
    digest: String,
    causation: EpisodeEventCausation? = nil
  ) -> EpisodeEvent<CounterPayload> {
    EpisodeEvent(
      id: id,
      episodeID: episodeID,
      sequence: sequence,
      recordedAt: Date(timeIntervalSince1970: TimeInterval(sequence.rawValue)),
      actor: EpisodeEventActor(
        id: EpisodeActorID(rawValue: "counter-policy"),
        origin: .policy
      ),
      causation: causation,
      correlationID: correlationID,
      preStateRevision: preRevision,
      postStateRevision: postRevision,
      payload: .add(amount),
      postStateDigest: EpisodeStateDigest(rawValue: digest)
    )
  }
}

private func sequence(_ value: UInt64) -> EpisodeEventSequence {
  EpisodeEventSequence(rawValue: value)
}

private func revision(_ value: UInt64) -> EpisodeStateRevision {
  EpisodeStateRevision(rawValue: value)
}

private func digest(_ value: String) -> EpisodeStateDigest {
  EpisodeStateDigest(rawValue: value)
}

private func episodeRevision(_ value: String) -> EpisodeRevisionIdentifier {
  EpisodeRevisionIdentifier(rawValue: value)
}

private func encode<Value: Encodable>(_ value: Value) throws -> Data {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  return try encoder.encode(value)
}

private func uuid(_ value: String) -> UUID {
  guard let id = UUID(uuidString: value) else {
    preconditionFailure("invalid UUID fixture: \(value)")
  }
  return id
}
