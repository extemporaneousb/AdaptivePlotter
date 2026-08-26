import EpisodeCore
import Foundation

public enum EpisodeStoreValidationError: Error, Equatable, Sendable {
  case persistedManifestMismatch(
    expected: EpisodeManifestID,
    actual: EpisodeManifestID
  )
  case persistedEpisodeMismatch(
    expected: EpisodeID,
    actual: EpisodeID
  )
  case persistedInitialStateRevisionMismatch(
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case reducerInputEpisodeMismatch(
    index: Int,
    expected: EpisodeID,
    actual: EpisodeID
  )
  case reducerInputRevisionMismatch(
    index: Int,
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case reducerOutputEpisodeMismatch(
    index: Int,
    expected: EpisodeID,
    actual: EpisodeID
  )
  case reducerOutputRevisionMismatch(
    index: Int,
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case reducerOutputDigestMismatch(
    index: Int,
    expected: EpisodeStateDigest,
    actual: EpisodeStateDigest
  )
}

/// Serial authority for one in-memory state and its one durable event journal.
///
/// The store accepts an already-typed production reducer. It never executes or
/// retains the reducer's effects; later runtime packages own that separate lane.
/// State is published only after the versioned persistence adapter has
/// atomically committed the candidate journal.
public actor EpisodeStore<Reducer, Persistence>
where Reducer: EpisodeReducing,
      Persistence: EpisodeJournalPersisting,
      Persistence.Payload == Reducer.EventPayload {
  public typealias State = Reducer.State
  public typealias EventPayload = Reducer.EventPayload

  private let reducer: Reducer
  private let persistence: Persistence
  private var journal: EpisodeJournal<EventPayload>
  private var state: State

  private init(
    reducer: Reducer,
    persistence: Persistence,
    journal: EpisodeJournal<EventPayload>,
    state: State
  ) {
    self.reducer = reducer
    self.persistence = persistence
    self.journal = journal
    self.state = state
  }

  /// Opens the one journal at `persistence` and reconstructs state by applying
  /// the supplied reducer to every committed event in order.
  public static func open(
    manifestID: EpisodeManifestID,
    initialState: State,
    reducer: Reducer,
    persistence: Persistence
  ) throws -> EpisodeStore<Reducer, Persistence> {
    let journal: EpisodeJournal<EventPayload>
    if let persisted = try persistence.load() {
      guard persisted.manifestID == manifestID else {
        throw EpisodeStoreValidationError.persistedManifestMismatch(
          expected: manifestID,
          actual: persisted.manifestID
        )
      }
      guard persisted.episodeID == initialState.episodeID else {
        throw EpisodeStoreValidationError.persistedEpisodeMismatch(
          expected: initialState.episodeID,
          actual: persisted.episodeID
        )
      }
      guard persisted.initialStateRevision == initialState.revision else {
        throw EpisodeStoreValidationError.persistedInitialStateRevisionMismatch(
          expected: initialState.revision,
          actual: persisted.initialStateRevision
        )
      }
      journal = persisted
    } else {
      journal = try EpisodeJournal(
        manifestID: manifestID,
        episodeID: initialState.episodeID,
        initialStateRevision: initialState.revision
      )
    }

    let reconstructed = try reconstruct(
      initialState: initialState,
      journal: journal,
      reducer: reducer
    )
    return EpisodeStore(
      reducer: reducer,
      persistence: persistence,
      journal: journal,
      state: reconstructed
    )
  }

  public func currentState() -> State {
    state
  }

  public func currentJournal() -> EpisodeJournal<EventPayload> {
    journal
  }

  /// Validates one candidate event and reducer result, durably commits the
  /// extended journal, then publishes and returns the committed reduction.
  /// Effects cross this boundary only as typed data returned to the caller. A
  /// persistence failure or post-rename uncertainty publishes nothing in this
  /// actor; the caller must reopen to reconcile durable state after uncertainty.
  public func append(
    _ event: EpisodeEvent<EventPayload>
  ) throws -> EpisodeReduction<State, Reducer.Effect> {
    let eventIndex = journal.events.count
    let candidateJournal = try EpisodeJournal(
      manifestID: journal.manifestID,
      episodeID: journal.episodeID,
      initialStateRevision: journal.initialStateRevision,
      events: journal.events + [event]
    )
    let candidateReduction = try reduceAndValidate(
      state: state,
      event: event,
      index: eventIndex,
      reducer: reducer
    )

    try persistence.commit(candidateJournal, replacing: journal)
    journal = candidateJournal
    state = candidateReduction.state
    return candidateReduction
  }
}

private func reconstruct<Reducer>(
  initialState: Reducer.State,
  journal: EpisodeJournal<Reducer.EventPayload>,
  reducer: Reducer
) throws -> Reducer.State where Reducer: EpisodeReducing {
  var state = initialState
  for (index, event) in journal.events.enumerated() {
    let reduction = try reduceAndValidate(
      state: state,
      event: event,
      index: index,
      reducer: reducer
    )
    state = reduction.state
  }
  return state
}

private func reduceAndValidate<Reducer>(
  state: Reducer.State,
  event: EpisodeEvent<Reducer.EventPayload>,
  index: Int,
  reducer: Reducer
) throws -> EpisodeReduction<Reducer.State, Reducer.Effect>
where Reducer: EpisodeReducing {
  guard state.episodeID == event.episodeID else {
    throw EpisodeStoreValidationError.reducerInputEpisodeMismatch(
      index: index,
      expected: event.episodeID,
      actual: state.episodeID
    )
  }
  guard state.revision == event.preStateRevision else {
    throw EpisodeStoreValidationError.reducerInputRevisionMismatch(
      index: index,
      expected: event.preStateRevision,
      actual: state.revision
    )
  }

  let reduction = reducer.reduce(state: state, event: event)
  let reducedState = reduction.state
  guard reducedState.episodeID == event.episodeID else {
    throw EpisodeStoreValidationError.reducerOutputEpisodeMismatch(
      index: index,
      expected: event.episodeID,
      actual: reducedState.episodeID
    )
  }
  guard reducedState.revision == event.postStateRevision else {
    throw EpisodeStoreValidationError.reducerOutputRevisionMismatch(
      index: index,
      expected: event.postStateRevision,
      actual: reducedState.revision
    )
  }
  guard reducedState.canonicalDigest == event.postStateDigest else {
    throw EpisodeStoreValidationError.reducerOutputDigestMismatch(
      index: index,
      expected: event.postStateDigest,
      actual: reducedState.canonicalDigest
    )
  }
  return reduction
}
