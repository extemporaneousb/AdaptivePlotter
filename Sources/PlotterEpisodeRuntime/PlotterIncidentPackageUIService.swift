import EpisodeCore
import Foundation
import PlotterEpisodeModel

public struct PlotterIncidentPackageUIRequestID:
  RawRepresentable, Codable, Hashable, Sendable
{
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}

/// The exact source revision requested by UI. It identifies values; it is not
/// evidence that the corresponding journal, recording, frames, or artifacts
/// are available or complete.
public struct PlotterIncidentPackageUISourceIdentity: Codable, Hashable, Sendable {
  public let episodeID: EpisodeID
  public let manifestID: EpisodeManifestID
  public let definitionRevision: EpisodeRevisionIdentifier
  public let buildRevision: EpisodeRevisionIdentifier
  public let runtimeStateRevision: EpisodeStateRevision
  public let runtimeStateDigest: EpisodeStateDigest
  public let projectionRevision: PlotterProjectionRevision

  public init(
    episodeID: EpisodeID,
    manifestID: EpisodeManifestID,
    definitionRevision: EpisodeRevisionIdentifier,
    buildRevision: EpisodeRevisionIdentifier,
    runtimeStateRevision: EpisodeStateRevision,
    runtimeStateDigest: EpisodeStateDigest,
    projectionRevision: PlotterProjectionRevision
  ) {
    self.episodeID = episodeID
    self.manifestID = manifestID
    self.definitionRevision = definitionRevision
    self.buildRevision = buildRevision
    self.runtimeStateRevision = runtimeStateRevision
    self.runtimeStateDigest = runtimeStateDigest
    self.projectionRevision = projectionRevision
  }
}

public struct PlotterIncidentPackageUIRequest: Codable, Hashable, Sendable {
  public let id: PlotterIncidentPackageUIRequestID
  public let sourceIdentity: PlotterIncidentPackageUISourceIdentity

  public init(
    id: PlotterIncidentPackageUIRequestID = PlotterIncidentPackageUIRequestID(),
    sourceIdentity: PlotterIncidentPackageUISourceIdentity
  ) {
    self.id = id
    self.sourceIdentity = sourceIdentity
  }
}

public enum PlotterIncidentPackageUISourceUnavailability:
  Codable, Hashable, Sendable
{
  /// No production owner can currently provide the complete immutable source.
  case noCompleteSourceProvider
  /// A named source owner exists, but the exact requested revision is absent.
  case exactSourceUnavailable(owner: EpisodeAuthorityID, detail: String)
  /// The source owner rejected its own source before assembly.
  case sourceRejected(owner: EpisodeAuthorityID, detail: String)
}

/// An opaque, complete source value. Its initializer is deliberately internal:
/// UI and App modules can request or display it but cannot manufacture source
/// completeness. A future source owner must be implemented in this runtime
/// module and provide the existing assembler's exact source value.
public struct PlotterIncidentPackageUIExactSource: Sendable {
  public let identity: PlotterIncidentPackageUISourceIdentity
  let source: PlotterIncidentPackageSource

  init(source: PlotterIncidentPackageSource) {
    self.source = source
    identity = PlotterIncidentPackageUISourceIdentity(source: source)
  }
}

public enum PlotterIncidentPackageUISourceLoadOutcome: Sendable {
  case available(PlotterIncidentPackageUIExactSource)
  case unavailable(PlotterIncidentPackageUISourceUnavailability)
}

public protocol PlotterIncidentPackageUISourceProvider: Sendable {
  func loadExactSource(
    for request: PlotterIncidentPackageUIRequest
  ) async -> PlotterIncidentPackageUISourceLoadOutcome
}

/// Truthful default until a complete production source owner is bound.
public struct PlotterIncidentPackageUIUnavailableSourceProvider:
  PlotterIncidentPackageUISourceProvider
{
  public let unavailability: PlotterIncidentPackageUISourceUnavailability

  public init(
    unavailability: PlotterIncidentPackageUISourceUnavailability = .noCompleteSourceProvider
  ) {
    self.unavailability = unavailability
  }

  public func loadExactSource(
    for _: PlotterIncidentPackageUIRequest
  ) async -> PlotterIncidentPackageUISourceLoadOutcome {
    .unavailable(unavailability)
  }
}

public enum PlotterIncidentPackageUIProgressPhase:
  String, Codable, Hashable, Sendable
{
  case loadingExactSource
  case assemblingCanonicalEnvelope
  case terminal
}

/// Progress is deliberately fixed to two units and at most three publications
/// per admitted request: source loaded, envelope assembled, terminal result.
public struct PlotterIncidentPackageUIProgress: Codable, Hashable, Sendable {
  public static let totalUnitCount: UInt8 = 2

  public let requestID: PlotterIncidentPackageUIRequestID
  public let sourceIdentity: PlotterIncidentPackageUISourceIdentity
  public let phase: PlotterIncidentPackageUIProgressPhase
  public let completedUnitCount: UInt8
  public let totalUnitCount: UInt8

  init(
    request: PlotterIncidentPackageUIRequest,
    phase: PlotterIncidentPackageUIProgressPhase,
    completedUnitCount: UInt8
  ) {
    precondition(completedUnitCount <= Self.totalUnitCount)
    requestID = request.id
    sourceIdentity = request.sourceIdentity
    self.phase = phase
    self.completedUnitCount = completedUnitCount
    totalUnitCount = Self.totalUnitCount
  }
}

public enum PlotterIncidentPackageUICanonicalEncoding:
  String, Codable, Hashable, Sendable
{
  case canonicalJSONV1
}

/// Confirms only that the existing assembler produced one canonical envelope
/// with the reported exact byte count and digest. It does not revalidate source
/// recording integrity/completeness, frame bytes, artifact availability, or any
/// physical effect or evidence.
public enum PlotterIncidentPackageUIIntegrityScope:
  String, Codable, Hashable, Sendable
{
  case canonicalEnvelopeOnly
}

public struct PlotterIncidentPackageUIResultMetadata:
  Codable, Hashable, Sendable
{
  public let requestID: PlotterIncidentPackageUIRequestID
  public let sourceIdentity: PlotterIncidentPackageUISourceIdentity
  public let formatVersion: UInt64
  public let encoding: PlotterIncidentPackageUICanonicalEncoding
  public let exactByteCount: Int
  public let payloadSHA256: String
  public let integrityScope: PlotterIncidentPackageUIIntegrityScope
  public let physicalEvidenceClaimed: Bool
}

public enum PlotterIncidentPackageUIRefusalReason: Hashable, Sendable {
  case requestInProgress(activeRequestID: PlotterIncidentPackageUIRequestID)
  case sourceUnavailable(PlotterIncidentPackageUISourceUnavailability)
  case sourceIdentityMismatch(
    expected: PlotterIncidentPackageUISourceIdentity,
    actual: PlotterIncidentPackageUISourceIdentity
  )
  case assemblerRejected(PlotterIncidentPackageRefusal)
}

public enum PlotterIncidentPackageUIRemedy: Hashable, Sendable {
  case waitForActiveRequest(PlotterIncidentPackageUIRequestID)
  case provideCompleteSource
  case refreshExactSource
  case repairExactSource
  case reduceSourceToBoundedLimits
  case reportRuntimeIntegrityFailure
}

public struct PlotterIncidentPackageUIRefusal: Hashable, Sendable {
  public let requestID: PlotterIncidentPackageUIRequestID
  public let sourceIdentity: PlotterIncidentPackageUISourceIdentity
  public let reason: PlotterIncidentPackageUIRefusalReason
  public let remedy: PlotterIncidentPackageUIRemedy
}

public enum PlotterIncidentPackageUIResult: Hashable, Sendable {
  case completed(PlotterIncidentPackageUIResultMetadata)
  case refused(PlotterIncidentPackageUIRefusal)
}

/// One request-owned, strictly bounded update sequence. An admitted request
/// publishes at most two nonterminal progress values followed by exactly one
/// terminal progress/result pair, then finishes the stream.
public enum PlotterIncidentPackageUIRequestUpdate: Hashable, Sendable {
  case progress(PlotterIncidentPackageUIProgress)
  case terminal(
    progress: PlotterIncidentPackageUIProgress,
    result: PlotterIncidentPackageUIResult
  )
}

public enum PlotterIncidentPackageUIRequestAdmission: Sendable {
  case accepted(AsyncStream<PlotterIncidentPackageUIRequestUpdate>)
  case refused(PlotterIncidentPackageUIRefusal)
}

/// ID-only request for the current truthful state where no complete incident
/// source owner exists. This path cannot load a source or invoke the assembler.
public struct PlotterIncidentPackageUINoSourceRequest: Hashable, Sendable {
  public let id: PlotterIncidentPackageUIRequestID

  public init(
    id: PlotterIncidentPackageUIRequestID = PlotterIncidentPackageUIRequestID()
  ) {
    self.id = id
  }
}

public enum PlotterIncidentPackageUINoSourceRefusalReason: Hashable, Sendable {
  case requestInProgress(activeRequestID: PlotterIncidentPackageUIRequestID)
  case noCompleteSourceProvider
}

public struct PlotterIncidentPackageUINoSourceRefusal: Hashable, Sendable {
  public let requestID: PlotterIncidentPackageUIRequestID
  public let reason: PlotterIncidentPackageUINoSourceRefusalReason
  public let remedy: PlotterIncidentPackageUIRemedy
}

public enum PlotterIncidentPackageUINoSourceRequestUpdate: Hashable, Sendable {
  case checkingAvailability(requestID: PlotterIncidentPackageUIRequestID)
  case terminal(PlotterIncidentPackageUINoSourceRefusal)
}

public enum PlotterIncidentPackageUINoSourceRequestAdmission: Sendable {
  case accepted(AsyncStream<PlotterIncidentPackageUINoSourceRequestUpdate>)
  case refused(PlotterIncidentPackageUINoSourceRefusal)
}

/// UI-facing request/progress/result owner around the sole existing pure
/// `PlotterIncidentPackageAssembler`. Payload bytes remain local to one call and
/// are neither stored nor exported by this service.
public actor PlotterIncidentPackageUIService {
  /// Loading, optional assembly, and terminal are the only publications.
  public static let maximumBufferedUpdateCount = 3
  /// Availability check and terminal refusal are the only publications.
  public static let maximumBufferedNoSourceUpdateCount = 2

  private let sourceProvider: any PlotterIncidentPackageUISourceProvider
  private let assembler = PlotterIncidentPackageAssembler()
  private var activeRequestID: PlotterIncidentPackageUIRequestID?

  public init(
    sourceProvider: any PlotterIncidentPackageUISourceProvider =
      PlotterIncidentPackageUIUnavailableSourceProvider()
  ) {
    self.sourceProvider = sourceProvider
  }

  /// Produces the truthful unavailable lifecycle without accepting or
  /// manufacturing any manifest, build, state-digest, or projection identity.
  public func startUnavailable(
    _ request: PlotterIncidentPackageUINoSourceRequest
  ) -> PlotterIncidentPackageUINoSourceRequestAdmission {
    if let activeRequestID {
      return .refused(PlotterIncidentPackageUINoSourceRefusal(
        requestID: request.id,
        reason: .requestInProgress(activeRequestID: activeRequestID),
        remedy: .waitForActiveRequest(activeRequestID)
      ))
    }
    activeRequestID = request.id
    let pair = AsyncStream<PlotterIncidentPackageUINoSourceRequestUpdate>.makeStream(
      bufferingPolicy: .bufferingNewest(Self.maximumBufferedNoSourceUpdateCount)
    )
    pair.continuation.yield(.checkingAvailability(requestID: request.id))
    pair.continuation.yield(.terminal(PlotterIncidentPackageUINoSourceRefusal(
      requestID: request.id,
      reason: .noCompleteSourceProvider,
      remedy: .provideCompleteSource
    )))
    pair.continuation.finish()
    activeRequestID = nil
    return .accepted(pair.stream)
  }

  public func start(
    _ request: PlotterIncidentPackageUIRequest
  ) -> PlotterIncidentPackageUIRequestAdmission {
    if let activeRequestID {
      return .refused(PlotterIncidentPackageUIRefusal(
        requestID: request.id,
        sourceIdentity: request.sourceIdentity,
        reason: .requestInProgress(activeRequestID: activeRequestID),
        remedy: .waitForActiveRequest(activeRequestID)
      ))
    }
    activeRequestID = request.id
    let pair = AsyncStream<PlotterIncidentPackageUIRequestUpdate>.makeStream(
      bufferingPolicy: .bufferingNewest(Self.maximumBufferedUpdateCount)
    )
    Task {
      await execute(request, continuation: pair.continuation)
    }
    return .accepted(pair.stream)
  }

  private func execute(
    _ request: PlotterIncidentPackageUIRequest,
    continuation: AsyncStream<PlotterIncidentPackageUIRequestUpdate>.Continuation
  ) async {
    publishProgress(
      request,
      phase: .loadingExactSource,
      completedUnitCount: 0,
      continuation: continuation
    )
    let sourceOutcome = await sourceProvider.loadExactSource(for: request)
    switch sourceOutcome {
    case .unavailable(let unavailability):
      finish(
        request,
        result: .refused(PlotterIncidentPackageUIRefusal(
          requestID: request.id,
          sourceIdentity: request.sourceIdentity,
          reason: .sourceUnavailable(unavailability),
          remedy: .provideCompleteSource
        )),
        continuation: continuation
      )

    case .available(let exactSource):
      guard exactSource.identity == request.sourceIdentity else {
        finish(
          request,
          result: .refused(PlotterIncidentPackageUIRefusal(
            requestID: request.id,
            sourceIdentity: request.sourceIdentity,
            reason: .sourceIdentityMismatch(
              expected: request.sourceIdentity,
              actual: exactSource.identity
            ),
            remedy: .refreshExactSource
          )),
          continuation: continuation
        )
        return
      }
      publishProgress(
        request,
        phase: .assemblingCanonicalEnvelope,
        completedUnitCount: 1,
        continuation: continuation
      )
      let assembly = assembler.assemble(exactSource.source)
      switch assembly {
      case .assembled(let export):
        finish(
          request,
          result: .completed(PlotterIncidentPackageUIResultMetadata(
            requestID: request.id,
            sourceIdentity: request.sourceIdentity,
            formatVersion: export.formatVersion,
            encoding: .canonicalJSONV1,
            exactByteCount: export.payloadByteCount,
            payloadSHA256: export.payloadSHA256,
            integrityScope: .canonicalEnvelopeOnly,
            physicalEvidenceClaimed: false
          )),
          continuation: continuation
        )
      case .refused(let refusal):
        finish(
          request,
          result: .refused(PlotterIncidentPackageUIRefusal(
            requestID: request.id,
            sourceIdentity: request.sourceIdentity,
            reason: .assemblerRejected(refusal),
            remedy: Self.remedy(for: refusal)
          )),
          continuation: continuation
        )
      }
    }
  }

  private func publishProgress(
    _ request: PlotterIncidentPackageUIRequest,
    phase: PlotterIncidentPackageUIProgressPhase,
    completedUnitCount: UInt8,
    continuation: AsyncStream<PlotterIncidentPackageUIRequestUpdate>.Continuation
  ) {
    let progress = PlotterIncidentPackageUIProgress(
      request: request,
      phase: phase,
      completedUnitCount: completedUnitCount
    )
    continuation.yield(.progress(progress))
  }

  private func finish(
    _ request: PlotterIncidentPackageUIRequest,
    result: PlotterIncidentPackageUIResult,
    continuation: AsyncStream<PlotterIncidentPackageUIRequestUpdate>.Continuation
  ) {
    continuation.yield(.terminal(
      progress: PlotterIncidentPackageUIProgress(
        request: request,
        phase: .terminal,
        completedUnitCount: PlotterIncidentPackageUIProgress.totalUnitCount
      ),
      result: result
    ))
    continuation.finish()
    activeRequestID = nil
  }

  private static func remedy(
    for refusal: PlotterIncidentPackageRefusal
  ) -> PlotterIncidentPackageUIRemedy {
    switch refusal {
    case .countLimitExceeded, .invalidBudget, .arithmeticOverflow:
      .reduceSourceToBoundedLimits
    case .encodingFailed, .payloadByteCountMismatch, .payloadDigestMismatch,
      .unsupportedFormatVersion, .unsupportedEncoding, .noncanonicalPayload,
      .corruptPayload:
      .reportRuntimeIntegrityFailure
    default:
      .repairExactSource
    }
  }
}

extension PlotterIncidentPackageUISourceIdentity {
  init(source: PlotterIncidentPackageSource) {
    self.init(
      episodeID: source.manifest.episodeID,
      manifestID: source.manifest.id,
      definitionRevision: source.manifest.definitionRevision,
      buildRevision: source.manifest.buildRevision,
      runtimeStateRevision: source.runtimeState.revision,
      runtimeStateDigest: source.runtimeState.canonicalDigest,
      projectionRevision: source.userInterfaceProjection.projectionRevision
    )
  }
}
