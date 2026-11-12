import Foundation
import PlotterModel

/// Local control protocol. These values grant no controller or physical issuance authority.
public struct DrawingDestinationDescription: Codable, Equatable, Sendable {
  public let engine: UUID
  public let executionAvailable: Bool
  public let reason: DrawingDestinationRefusal?
  public let documentProfiles: [String]
  public let representations: [String]
  public let mediumMapping: DrawingDestinationMediumMapping
  public let preparedOptions: [DrawingDestinationOption]
  public let acceptsOptionOverrides: Bool
  public let requiresNominalPenWidth: Bool
  public init(engine: UUID, executionAvailable: Bool = false) {
    self.engine = engine; self.executionAvailable = executionAvailable; reason = executionAvailable ? nil : .issuanceSeamUnavailable
    documentProfiles = ["adaptiveplotter.exchange/1", DrawingExchangeCodec.drawingProfile]
    representations = [DrawingExchangeCodec.strokeProfile]
    mediumMapping = .preserveAuthoredStyleAndCaptureCurrentApplicability
    preparedOptions = [.currentPlacement, .currentBorderSelection, .currentMaterialApplicability, .currentReadiness]
    acceptsOptionOverrides = false; requiresNominalPenWidth = false
  }
}
public enum DrawingDestinationMediumMapping: String, Codable, Sendable {
  case preserveAuthoredStyleAndCaptureCurrentApplicability
}
public enum DrawingDestinationOption: String, Codable, Sendable {
  case currentPlacement, currentBorderSelection, currentMaterialApplicability, currentReadiness
}
/// Transient caller causality, never persisted in a ticket or sent over files.
/// Initial generation is checked before projection; dynamic validity continues
/// through the owner's own expected selection/draft transitions.
@MainActor public struct DrawingPreparationContext {
  public let mayBegin: @MainActor () -> Bool
  public let isStillCurrent: @MainActor () -> Bool
  public let nativePreparation: DrawingPreparation?
  public init(mayBegin: @escaping @MainActor () -> Bool = { true },
    isStillCurrent: @escaping @MainActor () -> Bool = { true },
    nativePreparation: DrawingPreparation? = nil) {
    self.mayBegin = mayBegin; self.isStillCurrent = isStillCurrent
    self.nativePreparation = nativePreparation
  }
}
public enum DrawingDestinationRefusal: String, Codable, Error, Sendable {
  case issuanceSeamUnavailable = "issuance-seam-unavailable"
  case nativePlotRequired = "native-plot-required"
  case preparationUnavailable = "preparation-unavailable"
  case unsupportedDrawing = "unsupported-drawing"
  case stalePreview = "stale-preview"
  case requestConflict = "request-conflict"
  case unknownJob = "unknown-job"
  case invalidDelivery = "invalid-delivery"
  case cancelled = "cancelled"
  case interrupted = "interrupted"
  case alreadySettled = "already-settled"
}
public struct DrawingRequestKey: Codable, Hashable, Sendable {
  public let namespace: UUID
  public let request: UUID
  public init(namespace: UUID, request: UUID = UUID()) { self.namespace = namespace; self.request = request }
  /// Namespace is part of the domain kind; the request UUID alone is never a key.
  public var recordKind: String { "adaptiveplotter.destination.request." + namespace.uuidString.lowercased() }
}
public enum DrawingDestinationEnvironment: String, Codable, Sendable { case live, simulation }
public struct DrawingDestinationOptions: Codable, Equatable, Sendable {
  public let drawBorder: Bool
  public let sheetPlacementIsCurrent: Bool
  public let paperCoverageIsCurrent: Bool
  public let readiness: String
  public let applicability: ExchangeDigest
  /// Captured before submission. Missing historical provenance remains unknown.
  public let environment: DrawingDestinationEnvironment?
  public init(drawBorder: Bool, sheetPlacementIsCurrent: Bool, paperCoverageIsCurrent: Bool,
    readiness: String, applicability: ExchangeDigest, environment: DrawingDestinationEnvironment? = nil) {
    self.drawBorder = drawBorder; self.sheetPlacementIsCurrent = sheetPlacementIsCurrent
    self.paperCoverageIsCurrent = paperCoverageIsCurrent; self.readiness = readiness; self.applicability = applicability
    self.environment = environment
  }
}
public struct DrawingPreparedFacts: Codable, Equatable, Sendable {
  public let drawing: DrawingRef
  public let destination: UUID
  public let draftRevision: UInt64
  public let planID: ExecutionPlanRevisionID
  public let planHash: ExchangeDigest
  public let plan: ExchangeAsset
  public let options: ExchangeAsset
  public init(drawing: DrawingRef, destination: UUID, draftRevision: UInt64,
    plan: ExecutionPlanRevision, options: DrawingDestinationOptions) throws {
    self.drawing = drawing; self.destination = destination; self.draftRevision = draftRevision
    planID = plan.revisionID; planHash = ExchangeDigest(plan.contentHash)
    self.plan = try .init(bytes: DrawingArtifactCoding.encoder().encode(plan), mediaType: "application/json", encoding: "adaptiveplotter.local-prepared-plan/1")
    self.options = try .init(bytes: DrawingArtifactCoding.encoder().encode(options), mediaType: "application/json", encoding: "adaptiveplotter.local-medium-options/1")
  }
}
/// Materialized only by the preparation owner. It never appears in status rows.
public struct DrawingPreparation: Sendable {
  public let facts: DrawingPreparedFacts
  public let planBytes: Data
  public let optionsBytes: Data
  public init(drawing: DrawingRef, destination: UUID, draftRevision: UInt64,
    plan: ExecutionPlanRevision, options: DrawingDestinationOptions) throws {
    facts = try .init(drawing: drawing, destination: destination, draftRevision: draftRevision, plan: plan, options: options)
    planBytes = try DrawingArtifactCoding.encoder().encode(plan)
    optionsBytes = try DrawingArtifactCoding.encoder().encode(options)
  }
}
public struct DrawingPreparedTicket: Codable, Equatable, Sendable {
  public let id: UUID
  public let facts: DrawingPreparedFacts
  public init(id: UUID = UUID(), facts: DrawingPreparedFacts) { self.id = id; self.facts = facts }
}
public enum DrawingJobPhase: String, Codable, Sendable { case refused, reconciling, accepted, cancelRequested, settled }
public struct DrawingJobDecision: Codable, Equatable, Sendable {
  public let key: DrawingRequestKey
  public let requestDigest: ExchangeDigest
  public let job: JobReceiptRef
  public let ticket: DrawingPreparedTicket
  public let reason: DrawingDestinationRefusal?
  public let receipt: Data
  public let phase: DrawingJobPhase
  public init(key: DrawingRequestKey, requestDigest: ExchangeDigest, job: JobReceiptRef,
    ticket: DrawingPreparedTicket, reason: DrawingDestinationRefusal?, receipt: Data, phase: DrawingJobPhase = .refused) {
    self.key = key; self.requestDigest = requestDigest; self.job = job; self.ticket = ticket
    self.reason = reason; self.receipt = receipt; self.phase = phase
  }
}
public enum DrawingJobLookup: Codable, Equatable, Sendable { case job(JobRef), request(DrawingRequestKey) }
public enum DrawingDestinationRequest: Codable, Equatable, Sendable {
  case describe
  case prepare(DrawingRef)
  case submit(DrawingRequestKey, DrawingPreparedTicket)
  case status(DrawingJobLookup)
  case cancel(DrawingJobLookup)
  case exportResult(JobRef)
}
public enum DrawingDestinationReply: Codable, Equatable, Sendable {
  case description(DrawingDestinationDescription)
  /// Authored artwork is loaded while machine placement is unavailable. Carries no execution ticket.
  case referencePreview(DrawingRef)
  case prepared(DrawingPreparedTicket)
  case decision(DrawingJobDecision)
  case pending(DrawingPendingJob)
  case refused(DrawingDestinationRefusal)
  /// Cancel acknowledgement is distinct from settlement. Refusals are already terminal.
  case cancellation(acknowledged: Bool, settled: Bool)
  /// Result URL is an engine-owned inert carrier; returning it never submits again.
  case result(URL)
}
@MainActor public protocol DrawingDestination: AnyObject {
  func handle(_ request: DrawingDestinationRequest) async throws -> DrawingDestinationReply
}
