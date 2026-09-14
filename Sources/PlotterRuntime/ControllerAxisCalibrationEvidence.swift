import Foundation

/// Durable reservation before any firmware setting may be written. The source
/// checkpoint remains in the referenced metric measurement, even after Learning
/// adopts the new geometry identity. This is evidence, never motion authority.
public struct ControllerAxisCalibrationAttempt: Codable, Hashable, Sendable {
  public let proposal: ControllerAxisCalibrationProposal
  public let recordedAt: Date

  public init(proposal: ControllerAxisCalibrationProposal, recordedAt: Date = Date()) {
    self.proposal = proposal
    self.recordedAt = recordedAt
  }
}

/// A terminal fact is appended independently of its preparation. Missing terminal
/// evidence denotes an interrupted/unpublished attempt; startup never replays it.
public struct ControllerAxisCalibrationTerminal: Codable, Hashable, Sendable {
  public let proposalID: UUID
  public let outcome: ControllerAxisCalibrationOutcome
  public let recordedAt: Date

  public init(proposalID: UUID, outcome: ControllerAxisCalibrationOutcome,
    recordedAt: Date = Date()) {
    self.proposalID = proposalID
    self.outcome = outcome
    self.recordedAt = recordedAt
  }
}
