import Foundation
import PlotterModel

/// Exact pre-receipt identity. This is provenance, never dispatch permission.
public struct DrawingJobIssuance: Codable, Hashable, Sendable {
  public let drawing: DrawingRef
  public let job: JobRef
  public let key: DrawingRequestKey
  public let requestDigest: ExchangeDigest
  public let issuance: UUID
  public let preparedPlan: ExchangeAsset
  public let physicalPlanID: ExecutionPlanRevisionID
  public let physicalPlanHash: ExchangeDigest
  public let options: ExchangeAsset
  public init(drawing: DrawingRef, job: JobRef, key: DrawingRequestKey,
    requestDigest: ExchangeDigest, issuance: UUID, preparedPlan: ExchangeAsset,
    physicalPlanID: ExecutionPlanRevisionID, physicalPlanHash: ExchangeDigest, options: ExchangeAsset) {
    self.drawing = drawing; self.job = job; self.key = key; self.requestDigest = requestDigest
    self.issuance = issuance; self.preparedPlan = preparedPlan; self.physicalPlanID = physicalPlanID
    self.physicalPlanHash = physicalPlanHash; self.options = options
  }
}

/// Pending is not an accepted/refused receipt. Every update retains its CAS roots.
public struct DrawingPendingJob: Codable, Equatable, Sendable {
  public let binding: DrawingJobIssuance
  public let ticket: DrawingPreparedTicket
  public var cancellationRequested: Bool
  public var proposal: ExchangeAsset?
  public var stagedRun: UUID?
  public init(binding: DrawingJobIssuance, ticket: DrawingPreparedTicket) {
    self.binding = binding; self.ticket = ticket; cancellationRequested = false
  }
}
public enum DrawingRawIssuanceLookup: Sendable, Equatable {
  case absent
  case staged(UUID, settled: Bool)
  case unknown
}
public struct DrawingJobCancellation: Sendable {
  public let acknowledged: Bool
  public let settled: Bool
  public init(acknowledged: Bool, settled: Bool) {
    self.acknowledged = acknowledged; self.settled = settled
  }
}

/// All methods enter the same short Library transition boundary. They never
/// issue effects or re-enter the service's public request operation.
@MainActor public protocol DrawingJobPublication: AnyObject, Sendable {
  func retainProposal(_ bytes: Data, for binding: DrawingJobIssuance) async throws -> ExchangeAsset
  func staged(_ binding: DrawingJobIssuance, run: UUID) async throws
  func acceptedLink(_ binding: DrawingJobIssuance, run: UUID) async throws -> DrawingJobDecision
  func refuseBeforeStage(_ binding: DrawingJobIssuance, reason: DrawingDestinationRefusal) async throws -> DrawingJobDecision
  func settle(_ binding: DrawingJobIssuance, run: UUID) async throws
  func cancellationRequested(_ binding: DrawingJobIssuance) async throws -> Bool
}
/// Immutable per-call adapter carrying the actual native request to the same Run.
public protocol DrawingDestinationIssuanceAdmission: Sendable {
  func isCurrent(_ ticket: DrawingPreparedTicket) async -> Bool
  func admit(_ binding: DrawingJobIssuance, publication: any DrawingJobPublication) async throws
}
/// Stable nominal control adapter; no per-job App registry or execution closure.
public protocol DrawingDestinationJobControl: Sendable {
  func cancel(_ binding: DrawingJobIssuance) async -> DrawingJobCancellation
  func lookup(_ binding: DrawingJobIssuance) async -> DrawingRawIssuanceLookup
  func publishedSettlement(_ binding: DrawingJobIssuance, run: UUID) async
}
