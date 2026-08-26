import Foundation

public enum EpisodeJournalValidationError: Error, Equatable, Sendable {
  case duplicateEventID(EpisodeEventID)
  case episodeMismatch(index: Int, expected: EpisodeID, actual: EpisodeID)
  case sequenceMismatch(index: Int, expected: EpisodeEventSequence, actual: EpisodeEventSequence)
  case sequenceOverflow(index: Int)
  case preStateRevisionMismatch(
    index: Int,
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case postStateRevisionMismatch(
    index: Int,
    expected: EpisodeStateRevision,
    actual: EpisodeStateRevision
  )
  case stateRevisionOverflow(index: Int)
  case unknownCausation(index: Int, eventID: EpisodeEventID)
}

public struct EpisodeJournal<Payload>: Codable, Hashable, Sendable
where Payload: Codable & Hashable & Sendable {
  public let manifestID: EpisodeManifestID
  public let episodeID: EpisodeID
  public let initialStateRevision: EpisodeStateRevision
  public let events: [EpisodeEvent<Payload>]

  public init(
    manifestID: EpisodeManifestID,
    episodeID: EpisodeID,
    initialStateRevision: EpisodeStateRevision = .initial,
    events: [EpisodeEvent<Payload>] = []
  ) throws {
    try Self.validate(
      episodeID: episodeID,
      initialStateRevision: initialStateRevision,
      events: events
    )
    self.manifestID = manifestID
    self.episodeID = episodeID
    self.initialStateRevision = initialStateRevision
    self.events = events
  }

  private enum CodingKeys: String, CodingKey {
    case manifestID
    case episodeID
    case initialStateRevision
    case events
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let manifestID = try container.decode(EpisodeManifestID.self, forKey: .manifestID)
    let episodeID = try container.decode(EpisodeID.self, forKey: .episodeID)
    let initialStateRevision = try container.decode(
      EpisodeStateRevision.self,
      forKey: .initialStateRevision
    )
    let events = try container.decode([EpisodeEvent<Payload>].self, forKey: .events)
    try self.init(
      manifestID: manifestID,
      episodeID: episodeID,
      initialStateRevision: initialStateRevision,
      events: events
    )
  }

  private static func validate(
    episodeID: EpisodeID,
    initialStateRevision: EpisodeStateRevision,
    events: [EpisodeEvent<Payload>]
  ) throws {
    var expectedSequence = EpisodeEventSequence.first
    var expectedPreStateRevision = initialStateRevision
    var knownEventIDs: Set<EpisodeEventID> = []

    for (index, event) in events.enumerated() {
      guard !knownEventIDs.contains(event.id) else {
        throw EpisodeJournalValidationError.duplicateEventID(event.id)
      }
      guard event.episodeID == episodeID else {
        throw EpisodeJournalValidationError.episodeMismatch(
          index: index,
          expected: episodeID,
          actual: event.episodeID
        )
      }
      guard event.sequence == expectedSequence else {
        throw EpisodeJournalValidationError.sequenceMismatch(
          index: index,
          expected: expectedSequence,
          actual: event.sequence
        )
      }
      guard event.preStateRevision == expectedPreStateRevision else {
        throw EpisodeJournalValidationError.preStateRevisionMismatch(
          index: index,
          expected: expectedPreStateRevision,
          actual: event.preStateRevision
        )
      }
      guard expectedPreStateRevision.rawValue < UInt64.max else {
        throw EpisodeJournalValidationError.stateRevisionOverflow(index: index)
      }
      let expectedPostStateRevision = EpisodeStateRevision(
        rawValue: expectedPreStateRevision.rawValue + 1
      )
      guard event.postStateRevision == expectedPostStateRevision else {
        throw EpisodeJournalValidationError.postStateRevisionMismatch(
          index: index,
          expected: expectedPostStateRevision,
          actual: event.postStateRevision
        )
      }
      if let causalEventID = event.causation?.eventID,
         !knownEventIDs.contains(causalEventID) {
        throw EpisodeJournalValidationError.unknownCausation(
          index: index,
          eventID: causalEventID
        )
      }
      knownEventIDs.insert(event.id)

      expectedPreStateRevision = expectedPostStateRevision
      if index < events.count - 1 {
        guard expectedSequence.rawValue < UInt64.max else {
          throw EpisodeJournalValidationError.sequenceOverflow(index: index)
        }
        expectedSequence = EpisodeEventSequence(rawValue: expectedSequence.rawValue + 1)
      }
    }
  }
}
