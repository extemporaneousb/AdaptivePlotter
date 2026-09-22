import EpisodeCore
import EpisodeRuntime
import Foundation
import PlotterEpisodeModel
import PlotterModel
import PlotterRuntime
import os

public struct PlotterAcceptedPenCapSample: Codable, Hashable, Sendable {
  public let visualReference: PenCapVisualReference?
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8
  public let clickPoint: Point2<CameraPixelSpace>
  public let usableSampleCount: Int
  public let totalSampleCount: Int
  public let algorithmRevision: String

  public init(
    red: UInt8,
    green: UInt8,
    blue: UInt8,
    clickPoint: Point2<CameraPixelSpace>,
    usableSampleCount: Int,
    totalSampleCount: Int,
    algorithmRevision: String,
    visualReference: PenCapVisualReference? = nil
  ) {
    self.visualReference = visualReference
    self.red = red
    self.green = green
    self.blue = blue
    self.clickPoint = clickPoint
    self.usableSampleCount = usableSampleCount
    self.totalSampleCount = totalSampleCount
    self.algorithmRevision = algorithmRevision
  }
}

public enum PlotterPointSelectionSamplingError: LocalizedError, Equatable, Sendable {
  case staleExactFrame
  case unsupportedPixelFormat(FramePixelFormat)

  public var errorDescription: String? {
    switch self {
    case .staleExactFrame:
      "The point did not belong to the frozen exact frame. Start the selection again."
    case .unsupportedPixelFormat(let format):
      "Pen-cap reference sampling requires an exact RGBA or BGRA frame; \(format.rawValue) is unsupported."
    }
  }
}

public enum PlotterPenCapPointSampler {
  public static func sample(
    frame: DisplayedFrame,
    submission: PlotterPointSelectionSubmission
  ) throws -> PlotterAcceptedPenCapSample {
    guard exactFrame(submission.frame, matches: frame),
      submission.point.x >= 0, submission.point.x < Double(frame.frame.width),
      submission.point.y >= 0, submission.point.y < Double(frame.frame.height)
    else { throw PlotterPointSelectionSamplingError.staleExactFrame }
    guard frame.frame.pixelFormat == .rgba8 || frame.frame.pixelFormat == .bgra8 else {
      throw PlotterPointSelectionSamplingError.unsupportedPixelFormat(frame.frame.pixelFormat)
    }

    guard let bounds = submission.referenceRegion,
      bounds.minX >= 0, bounds.minY >= 0,
      submission.point.x >= bounds.minX, submission.point.x < bounds.maxX,
      submission.point.y >= bounds.minY, submission.point.y < bounds.maxY,
      bounds.maxX <= Double(frame.frame.width), bounds.maxY <= Double(frame.frame.height)
    else { throw PenCapReferenceError.invalidRegion }
    let region = PixelRect(x: Int(floor(bounds.minX)), y: Int(floor(bounds.minY)),
      width: Int(ceil(bounds.maxX)) - Int(floor(bounds.minX)),
      height: Int(ceil(bounds.maxY)) - Int(floor(bounds.minY)))
    let reference = try PenCapVisualReference.capture(frame: frame.frame,
      region: region, anchor: submission.point)
    // RGB is legacy display metadata only. Recognition uses the complete patch.
    let count = reference.rgb.count / 3
    let means = (0..<3).map { channel in
      UInt8(stride(from: channel, to: reference.rgb.count, by: 3)
        .reduce(0) { $0 + Int(reference.rgb[$1]) } / count)
    }
    return PlotterAcceptedPenCapSample(red: means[0], green: means[1], blue: means[2],
      clickPoint: submission.point, usableSampleCount: count, totalSampleCount: count,
      algorithmRevision: PenCapVisualReference.revision, visualReference: reference)
  }

  private static func exactFrame(
    _ expected: PlotterExactFrameReference,
    matches frame: DisplayedFrame
  ) -> Bool {
    guard let contentSHA256 = frame.frame.materializedContentSHA256 else { return false }
    return expected.frameID == frame.frame.id.rawValue
      && expected.frameSHA256 == contentSHA256
      && expected.cameraConfigurationID == frame.frame.cameraConfigurationID
      && expected.width == frame.frame.width
      && expected.height == frame.frame.height
      && expected.rowBytes == frame.frame.rowBytes
      && expected.pixelFormat.rawValue == frame.frame.pixelFormat.rawValue
      && expected.source == frame.source.pointSelectionSource
  }
}

public protocol PlotterPointSelectionContinuationPort: Sendable {
  func beginPenCapDiscovery(selectionID: PlotterPointSelectionID) async throws
  func configurePenCapVision(
    selectionID: PlotterPointSelectionID,
    sample: PlotterAcceptedPenCapSample
  ) async throws
}

public protocol PlotterLearningActivityFactProviding: Sendable {
  func currentLearningActivityFact() async -> PlotterLearningActivityFact
}

public struct PlotterPointSelectionStage: Sendable {
  public let request: PlotterPointSelectionRequest
  public let projection: PlotterEpisodeProjection
  public let recordingDiagnostic: String?
}

public enum PlotterPointSelectionSubmissionResult: Sendable {
  case refused(projection: PlotterEpisodeProjection, reason: String)
  case acceptedPoint(projection: PlotterEpisodeProjection)
  case acceptedPenCap(
    sample: PlotterAcceptedPenCapSample,
    frame: DisplayedFrame,
    projection: PlotterEpisodeProjection
  )
  case acceptedBatch(
    points: [Point2<CameraPixelSpace>],
    presentationTransformRevision: PlotterPresentationTransformRevision,
    projection: PlotterEpisodeProjection
  )
}

private final class PointSelectionJournalPersistence: EpisodeJournalPersisting, Sendable {
  typealias Payload = PlotterEpisodeEventPayload

  let journalSchemaRevision = EpisodeRevisionIdentifier(
    rawValue: "plotter-point-selection-journal-v1"
  )
  private let journal = OSAllocatedUnfairLock<EpisodeJournal<Payload>?>(initialState: nil)

  func load() throws -> EpisodeJournal<Payload>? {
    journal.withLock { $0 }
  }

  func commit(
    _ candidate: EpisodeJournal<Payload>,
    replacing expected: EpisodeJournal<Payload>
  ) throws {
    try journal.withLock { journal in
      if let journal {
        guard journal == expected else {
          throw EpisodeJournalPersistenceError.concurrentWriterConflict
        }
      } else {
        guard expected.events.isEmpty else {
          throw EpisodeJournalPersistenceError.concurrentWriterConflict
        }
      }
      journal = candidate
    }
  }
}

package enum PointSelectionOperationLane: Hashable, Sendable {
  case machine
  case exactWorkflow
  case background
  case durable
}

package enum PointSelectionAwaitedResult: Hashable, Sendable {
  case discoveryQuestion
  case visionConfiguration
}

package struct PointSelectionOperationContext: PlotterOperationContext {
  package typealias IntentIdentity = PlotterPointSelectionIntent
  package typealias Environment = PlotterEnvironment
  package typealias AwaitedResult = PointSelectionAwaitedResult

  package let owningSubsystem: EpisodeAuthorityID
  package let resultCurrentlyAwaited: PointSelectionAwaitedResult
}

package enum PointSelectionContinuationDisposition: Hashable, Sendable {
  case completed
  case cancelled
  case failed(String)
}

package actor PointSelectionContinuationHandle: PlotterOperationHandle {
  package typealias OperationContext = PointSelectionOperationContext
  package typealias TerminalDisposition = PointSelectionContinuationDisposition

  private let identity: PlotterOperationIdentity<PointSelectionOperationContext>
  private let selectionID: PlotterPointSelectionID
  private let sample: PlotterAcceptedPenCapSample
  private let port: any PlotterPointSelectionContinuationPort
  private var task: Task<PointSelectionContinuationDisposition, Never>?

  package init(
    identity: PlotterOperationIdentity<PointSelectionOperationContext>,
    selectionID: PlotterPointSelectionID,
    sample: PlotterAcceptedPenCapSample,
    port: any PlotterPointSelectionContinuationPort
  ) {
    self.identity = identity
    self.selectionID = selectionID
    self.sample = sample
    self.port = port
  }

  package func start() {
    guard task == nil else { return }
    task = Task { [port, sample, selectionID] in
      await Task.yield()
      guard !Task.isCancelled else { return .cancelled }
      do {
        try await port.beginPenCapDiscovery(selectionID: selectionID)
        guard !Task.isCancelled else { return .cancelled }
        try await port.configurePenCapVision(selectionID: selectionID, sample: sample)
        guard !Task.isCancelled else { return .cancelled }
        return .completed
      } catch is CancellationError {
        return .cancelled
      } catch {
        return .failed(String(describing: error))
      }
    }
  }

  package func requestCancellation() async {
    task?.cancel()
  }

  package func waitForSettlement() async
    -> PlotterOperationResult<PointSelectionOperationContext, PointSelectionContinuationDisposition>
  {
    let disposition = await task?.value ?? .cancelled
    return PlotterOperationResult(
      identity: identity,
      disposition: disposition,
      settledAt: Date()
    )
  }
}

private struct ActivePointSelectionContinuation: Sendable {
  let selectionID: PlotterPointSelectionID
  let stopCapability: StopCapability<PointSelectionOperationContext>
  let handle: PointSelectionContinuationHandle
}

public actor PlotterPointSelectionRuntime {
  private typealias Store = EpisodeStore<PlotterEpisodeReducer, PointSelectionJournalPersistence>
  private typealias Registry = PlotterOperationRegistry<
    PointSelectionOperationLane,
    PointSelectionOperationContext,
    PointSelectionContinuationHandle
  >

  private let episodeID: EpisodeID
  private let store: Store
  private let gateway = PlotterIntentGateway()
  private let recordingStore: EpisodeRecordingStore?
  private let recordingUnavailableDiagnostic: String?
  private let registry: Registry
  private var projectionRevision: UInt64 = 0
  private var activeRecordedStream: CameraStreamIdentity?
  private var lastRecordingOffset: UInt64 = 0
  private var framesBySelectionID: [PlotterPointSelectionID: DisplayedFrame] = [:]
  private var activeContinuation: ActivePointSelectionContinuation?
  private var mutationPublicationBoundaryIsHeld = false
  private var mutationPublicationBoundaryWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    recordingStore: EpisodeRecordingStore? = nil,
    recordingUnavailableDiagnostic: String? = nil
  ) {
    episodeID = EpisodeID(rawValue: UUID())
    let prototype = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: EpisodeStateDigest(rawValue: "pending")
    )
    let initialDigest = try! PlotterEpisodeCanonicalDigestV1.digest(prototype)
    let initial = PlotterEpisodeState(
      episodeID: episodeID,
      canonicalDigest: initialDigest
    )
    store = try! EpisodeStore.open(
      manifestID: EpisodeManifestID(rawValue: UUID()),
      initialState: initial,
      reducer: PlotterEpisodeReducer(),
      persistence: PointSelectionJournalPersistence()
    )
    let lanes = try! PlotterOperationLaneConfiguration(
      machine: PointSelectionOperationLane.machine,
      exactWorkflowCaptureVision: .exactWorkflow,
      backgroundAnalysis: .background,
      durableAppend: .durable,
      backgroundAnalysisLimit: 2
    )
    registry = PlotterOperationRegistry(lanes: lanes)
    self.recordingStore = recordingStore
    self.recordingUnavailableDiagnostic = recordingUnavailableDiagnostic
  }

  public func currentProjection() async -> PlotterEpisodeProjection {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    return project(await store.currentState())
  }

  public func stage(
    frame: DisplayedFrame,
    presentationTransformRevision: PlotterPresentationTransformRevision,
    prompt: String,
    purpose: PlotterExactPointSelectionPurpose,
    requiredPointCount: Int
  ) async throws -> PlotterPointSelectionStage {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    if let current = (await store.currentState()).exactPointSelection.request {
      await cancelContinuationWithinBoundary(selectionID: current.id)
      _ = try await submitIntent(.pointSelection(.cancel(current.id)))
      framesBySelectionID[current.id] = nil
    }
    let recorded = try await recordExactPointSelectionFrame(frame)
    let request = PlotterPointSelectionRequest(
      frame: recorded.exactFrame,
      sourceObservationID: recorded.observationID,
      presentationTransformRevision: presentationTransformRevision,
      prompt: prompt,
      purpose: purpose,
      requiredPointCount: requiredPointCount
    )
    let committed = try await submitIntent(.pointSelection(.stage(request)))
    framesBySelectionID[request.id] = frame
    return PlotterPointSelectionStage(
      request: request,
      projection: project(committed.state),
      recordingDiagnostic: recorded.recordingDiagnostic
    )
  }

  /// Replaces one current, empty collecting request with a strictly newer
  /// exact frame. Recording and source-observation publication happen while
  /// the old request remains current; the final reducer event performs the
  /// supersession as one state transition.
  public func replace(
    currentRequest: PlotterPointSelectionRequest,
    with frame: DisplayedFrame,
    presentationTransformRevision: PlotterPresentationTransformRevision
  ) async throws -> PlotterPointSelectionStage {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let before = await store.currentState()
    guard before.exactPointSelection.request == currentRequest,
      before.exactPointSelection.phase == .collecting,
      before.exactPointSelection.selectedPoints.isEmpty,
      frame.frame.captureNanoseconds > currentRequest.frame.captureNanoseconds
    else { throw PlotterPointSelectionRuntimeError.replacementNotCurrent }

    let recorded = try await recordExactPointSelectionFrame(frame)
    let replacement = PlotterPointSelectionRequest(
      frame: recorded.exactFrame,
      sourceObservationID: recorded.observationID,
      presentationTransformRevision: presentationTransformRevision,
      prompt: currentRequest.prompt,
      purpose: currentRequest.purpose,
      requiredPointCount: currentRequest.requiredPointCount
    )
    let committed = try await submitIntent(.pointSelection(.replace(
      currentSelectionID: currentRequest.id,
      replacement: replacement
    )))
    guard committed.state.exactPointSelection.request == replacement else {
      throw PlotterPointSelectionRuntimeError.replacementNotCurrent
    }
    framesBySelectionID[currentRequest.id] = nil
    framesBySelectionID[replacement.id] = frame
    return PlotterPointSelectionStage(
      request: replacement,
      projection: project(committed.state),
      recordingDiagnostic: recorded.recordingDiagnostic
    )
  }

  private func recordExactPointSelectionFrame(
    _ frame: DisplayedFrame
  ) async throws -> (
    exactFrame: PlotterExactFrameReference,
    observationID: PlotterObservationID,
    recordingDiagnostic: String?
  ) {
    let recorded = await record(frame)
    let exactFrame = frame.pointSelectionReference(
      artifact: recorded.artifact,
      locator: recorded.locator
    )
    let observationID = PlotterObservationID(rawValue: UUID())
    let observation = try PlotterCameraFrameObservation(
      context: PlotterObservationContext(
        id: observationID,
        observedAt: Date(),
        environment: exactFrame.source.environment,
        source: exactFrame.source.environment == .live ? .camera : .causalSimulator,
        sourceRevision: EpisodeRevisionIdentifier(rawValue: "exact-displayed-frame-v1"),
        configurationRevision: EpisodeRevisionIdentifier(
          rawValue: exactFrame.cameraConfigurationID.description
        ),
        artifactReferences: exactFrame.archivedBytes.map { [$0] } ?? []
      ),
      configurationID: exactFrame.cameraConfigurationID,
      pixelWidth: UInt32(exactFrame.width),
      pixelHeight: UInt32(exactFrame.height),
      exactFrame: exactFrame
    )
    _ = try await commit(
      payload: .observationRecorded(.cameraFrame(observation)),
      origin: .environment,
      artifacts: exactFrame.archivedBytes.map { [$0] } ?? []
    )
    return (exactFrame, observationID, recorded.diagnostic)
  }

  public func submit(
    _ submission: PlotterPointSelectionSubmission
  ) async throws -> PlotterPointSelectionSubmissionResult {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let state = await store.currentState()
    let intent = PlotterIntent.pointSelection(.select(submission))
    let evaluation = try gateway.evaluate(
      requestID: IntentRequestID(rawValue: UUID()),
      intent: intent,
      state: state,
      capabilityFacts: [],
      environment: submission.frame.source.environment
    )
    guard evaluation.decision.isAdmitted else {
      let committed = try await commit(payload: evaluation.payload, origin: .operatorRequest)
      return .refused(
        projection: project(committed.state),
        reason: evaluation.decision.firstRefusalRemedy
          ?? "The point-selection request is no longer current."
      )
    }
    let request = state.exactPointSelection.request
    let sample: PlotterAcceptedPenCapSample?
    let acceptedFrame: DisplayedFrame?
    if request?.purpose == .penCapAppearance {
      guard let frame = framesBySelectionID[submission.selectionID] else {
        return try await refuseSample(
          intent: intent,
          evaluation: evaluation,
          reason: PlotterPointSelectionSamplingError.staleExactFrame.localizedDescription
        )
      }
      do {
        sample = try PlotterPenCapPointSampler.sample(frame: frame, submission: submission)
        acceptedFrame = frame
      } catch {
        return try await refuseSample(
          intent: intent,
          evaluation: evaluation,
          reason: error.localizedDescription
        )
      }
    } else {
      sample = nil
      acceptedFrame = nil
    }

    let committed = try await commit(payload: evaluation.payload, origin: .operatorRequest)
    try await recordAcceptedPoint(submission, ordinal: state.exactPointSelection.selectedPoints.count)
    let projection = project((await store.currentState()))
    if let sample, let acceptedFrame {
      return .acceptedPenCap(sample: sample, frame: acceptedFrame, projection: projection)
    }
    let points = projection.exactPointSelection.selectedPoints
    if points.count == request?.requiredPointCount {
      return .acceptedBatch(
        points: points,
        presentationTransformRevision: submission.presentationTransformRevision,
        projection: projection
      )
    }
    _ = committed
    return .acceptedPoint(projection: projection)
  }

  public func undo(selectionID: PlotterPointSelectionID) async throws -> PlotterEpisodeProjection {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let committed = try await submitIntent(.pointSelection(.undo(selectionID)))
    return project(committed.state)
  }

  public func clear(selectionID: PlotterPointSelectionID) async throws
    -> PlotterEpisodeProjection
  {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let committed = try await submitIntent(.pointSelection(.clear(selectionID)))
    return project(committed.state)
  }

  public func cancel(selectionID: PlotterPointSelectionID) async -> PlotterEpisodeProjection {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    await cancelContinuationWithinBoundary(selectionID: selectionID)
    if let committed = try? await submitIntent(.pointSelection(.cancel(selectionID))) {
      framesBySelectionID[selectionID] = nil
      return project(committed.state)
    }
    return project(await store.currentState())
  }

  public func setLearningEnabled(
    _ isEnabled: Bool,
    activityFactProvider: any PlotterLearningActivityFactProviding
  ) async throws -> PlotterEpisodeProjection {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    let intent = PlotterIntent.learning(.setEnabled(isEnabled))
    let requestID = IntentRequestID(rawValue: UUID())
    let initialState = await store.currentState()
    let initialActivityFact = await activityFactProvider.currentLearningActivityFact()
    let initialFacts = [PlotterCapabilityFact.learningActivity(initialActivityFact)]
    let environment = initialState.exactPointSelection.request?.frame.source.environment ?? .live
    let initialEvaluation = try gateway.evaluate(
      requestID: requestID,
      intent: intent,
      state: initialState,
      capabilityFacts: initialFacts,
      environment: environment
    )
    guard initialEvaluation.decision.isAdmitted else {
      let refused = try await commit(
        payload: initialEvaluation.payload,
        origin: .operatorRequest
      )
      return project(refused.state)
    }
    let pointSelectionOwner = isEnabled ? nil : initialActivityFact.pointSelectionOwner
    let settledContinuation = if let pointSelectionOwner {
      await settleContinuationOperationWithinBoundary(
        selectionID: pointSelectionOwner.selectionID
      )
    } else {
      false
    }
    let actualState = await store.currentState()
    let actualActivityFact = await activityFactProvider.currentLearningActivityFact()
    let actualFacts = [PlotterCapabilityFact.learningActivity(actualActivityFact)]
    let actualEvaluation = try gateway.evaluate(
      requestID: requestID,
      intent: intent,
      state: actualState,
      capabilityFacts: actualFacts,
      environment: environment,
      requiredLearningPointSelectionOwner: pointSelectionOwner
    )
    let committed: CommittedPointSelectionEvent
    if let pointSelectionOwner,
      settledContinuation,
      !actualEvaluation.decision.isAdmitted
    {
      try await publishContinuationInactiveWithinBoundary(
        selectionID: pointSelectionOwner.selectionID
      )
      let refusalState = await store.currentState()
      let finalRefusal = try gateway.evaluate(
        requestID: requestID,
        intent: intent,
        state: refusalState,
        capabilityFacts: actualFacts,
        environment: environment,
        requiredLearningPointSelectionOwner: pointSelectionOwner
      )
      committed = try await commit(payload: finalRefusal.payload, origin: .operatorRequest)
    } else {
      do {
        committed = try await commit(
          payload: actualEvaluation.payload,
          origin: .operatorRequest
        )
      } catch {
        if settledContinuation, let pointSelectionOwner {
          try? await publishContinuationInactiveWithinBoundary(
            selectionID: pointSelectionOwner.selectionID
          )
        }
        throw error
      }
    }
    if actualEvaluation.decision.isAdmitted, let pointSelectionOwner {
      framesBySelectionID[pointSelectionOwner.selectionID] = nil
    }
    return project(committed.state)
  }

  public func beginPenCapContinuation(
    selectionID: PlotterPointSelectionID,
    sample: PlotterAcceptedPenCapSample,
    port: any PlotterPointSelectionContinuationPort
  ) async throws {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    await cancelContinuationWithinBoundary(selectionID: activeContinuation?.selectionID)
    let continuationIntent = PlotterPointSelectionIntent.setContinuation(
      selectionID: selectionID,
      isActive: true
    )
    let intent = PlotterIntent.pointSelection(continuationIntent)
    let requestID = IntentRequestID(rawValue: UUID())
    let environment = sampleEnvironment(for: selectionID)
    let identity = PlotterOperationIdentity<PointSelectionOperationContext>(
      episodeID: episodeID,
      requestID: requestID,
      intentIdentity: continuationIntent,
      effectID: EpisodeEffectID(rawValue: UUID()),
      effectRevision: EpisodeRevisionIdentifier(rawValue: "pen-cap-continuation-v1"),
      environment: environment
    )
    let context = PointSelectionOperationContext(
      owningSubsystem: EpisodeAuthorityID(rawValue: "PlotterPointSelectionRuntime"),
      resultCurrentlyAwaited: .discoveryQuestion
    )
    let handle = PointSelectionContinuationHandle(
      identity: identity,
      selectionID: selectionID,
      sample: sample,
      port: port
    )
    let registration = try await registry.register(
      identity: identity,
      lane: .exactWorkflow,
      context: context,
      handle: handle,
      cancellationAvailable: true
    )
    let stopCapability = registration.stopCapability!
    let completionCapability = registration.completionCapability
    let state = await store.currentState()
    let evaluation = try gateway.evaluate(
      requestID: requestID,
      intent: intent,
      state: state,
      capabilityFacts: [],
      environment: environment
    )
    guard evaluation.decision.isAdmitted else {
      do {
        _ = try await commit(payload: evaluation.payload, origin: .operatorRequest)
      } catch {
        _ = await registry.stop(using: stopCapability)
        throw error
      }
      _ = await registry.stop(using: stopCapability)
      throw PlotterPointSelectionRuntimeError.operationAttributionRefused
    }
    let permit = registration.takePermit()
    let committed: CommittedPointSelectionEvent
    do {
      committed = try await commit(payload: evaluation.payload, origin: .operatorRequest)
    } catch {
      _ = await registry.stop(using: stopCapability)
      throw error
    }
    let attribution = PlotterOperationEventAttribution(
      identity: identity,
      eventID: committed.event.id,
      sequence: committed.event.sequence,
      preStateRevision: committed.event.preStateRevision,
      postStateRevision: committed.event.postStateRevision,
      recordedAt: committed.event.recordedAt
    )
    switch await registry.start(permit, for: identity, attributedTo: attribution) {
    case .accepted:
      activeContinuation = ActivePointSelectionContinuation(
        selectionID: selectionID,
        stopCapability: stopCapability,
        handle: handle
      )
      await handle.start()
      Task { [weak self] in
        let result = await handle.waitForSettlement()
        await self?.finishContinuation(
          selectionID: selectionID,
          result: result,
          completionCapability: completionCapability
        )
      }
    case .admissionClosed:
      await abandonContinuationRegistration(
        selectionID: selectionID,
        stopCapability: stopCapability
      )
      throw CancellationError()
    case .retired:
      await abandonContinuationRegistration(
        selectionID: selectionID,
        stopCapability: stopCapability
      )
      throw CancellationError()
    case .cancellationInProgress:
      await abandonContinuationRegistration(
        selectionID: selectionID,
        stopCapability: stopCapability
      )
      throw CancellationError()
    case .identityMismatch:
      await abandonContinuationRegistration(
        selectionID: selectionID,
        stopCapability: stopCapability
      )
      throw PlotterPointSelectionRuntimeError.operationAttributionRefused
    case .attributionRefused:
      await abandonContinuationRegistration(
        selectionID: selectionID,
        stopCapability: stopCapability
      )
      throw PlotterPointSelectionRuntimeError.operationAttributionRefused
    }
  }

  private func abandonContinuationRegistration(
    selectionID: PlotterPointSelectionID,
    stopCapability: StopCapability<PointSelectionOperationContext>
  ) async {
    _ = await registry.stop(using: stopCapability)
    _ = try? await submitIntent(.pointSelection(.setContinuation(
      selectionID: selectionID,
      isActive: false
    )))
  }

  public func cancelContinuation(selectionID: PlotterPointSelectionID?) async {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    await cancelContinuationWithinBoundary(selectionID: selectionID)
  }

  private func cancelContinuationWithinBoundary(selectionID: PlotterPointSelectionID?) async {
    guard let activeSelectionID = activeContinuation?.selectionID,
      await settleContinuationOperationWithinBoundary(selectionID: selectionID)
    else { return }
    try? await publishContinuationInactiveWithinBoundary(selectionID: activeSelectionID)
  }

  private func settleContinuationOperationWithinBoundary(
    selectionID: PlotterPointSelectionID?
  ) async -> Bool {
    guard let continuation = activeContinuation,
      selectionID == nil || selectionID == continuation.selectionID
    else { return false }
    _ = await registry.stop(using: continuation.stopCapability)
    if activeContinuation?.selectionID == continuation.selectionID {
      activeContinuation = nil
    }
    return true
  }

  private func publishContinuationInactiveWithinBoundary(
    selectionID: PlotterPointSelectionID
  ) async throws {
    _ = try await submitIntent(.pointSelection(.setContinuation(
      selectionID: selectionID,
      isActive: false
    )))
  }

  public func shutdown() async {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    _ = await registry.shutdown()
    activeContinuation = nil
    if let selectionID = (await store.currentState()).exactPointSelection.request?.id {
      _ = try? await submitIntent(.pointSelection(.setContinuation(
        selectionID: selectionID,
        isActive: false
      )))
    }
  }

  private func finishContinuation(
    selectionID: PlotterPointSelectionID,
    result: PlotterOperationResult<
      PointSelectionOperationContext,
      PointSelectionContinuationDisposition
    >,
    completionCapability: CompletionCapability<PointSelectionOperationContext>
  ) async {
    await acquireMutationPublicationBoundary()
    defer { releaseMutationPublicationBoundary() }
    _ = await registry.settle(result, using: completionCapability)
    guard activeContinuation?.selectionID == selectionID else { return }
    activeContinuation = nil
    _ = try? await submitIntent(.pointSelection(.setContinuation(
      selectionID: selectionID,
      isActive: false
    )))
  }

  private func refuseSample(
    intent: PlotterIntent,
    evaluation: PlotterIntentGatewayEvaluation,
    reason: String
  ) async throws -> PlotterPointSelectionSubmissionResult {
    let context = evaluation.decision.context
    let payload = PlotterEpisodeEventPayload.intentRefused(PlotterIntentRefusalRecord(
      requestID: context.requestID,
      intent: intent,
      comparedStateRevision: context.comparedStateRevision,
      comparedCapabilityFacts: context.comparedCapabilityFacts,
      failedRequirements: [
        IntentRequirementRefusal(
          requirementID: PlotterIntentRequirement.pointSampleUsable.id,
          owner: EpisodeAuthorityID(rawValue: "PlotterPointSelectionRuntime"),
          comparedCapabilityFacts: context.comparedCapabilityFacts,
          remedy: reason
        )
      ]
    ))
    let committed = try await commit(payload: payload, origin: .operatorRequest)
    return .refused(projection: project(committed.state), reason: reason)
  }

  private func recordAcceptedPoint(
    _ submission: PlotterPointSelectionSubmission,
    ordinal: Int
  ) async throws {
    let observationID = PlotterObservationID(rawValue: UUID())
    let artifacts = submission.frame.archivedBytes.map { [$0] } ?? []
    let observation = PlotterPointSelectionObservation(
      context: PlotterObservationContext(
        id: observationID,
        observedAt: Date(),
        environment: submission.frame.source.environment,
        source: .operatorAssertion,
        sourceRevision: EpisodeRevisionIdentifier(rawValue: "operator-point-selection-v1"),
        configurationRevision: EpisodeRevisionIdentifier(
          rawValue: submission.frame.cameraConfigurationID.description
        ),
        artifactReferences: artifacts
      ),
      selectionID: submission.selectionID,
      sourceFrame: submission.frame,
      point: submission.point,
      presentationTransformRevision: submission.presentationTransformRevision,
      ordinal: ordinal
    )
    _ = try await commit(
      payload: .observationRecorded(.pointSelection(observation)),
      origin: .operatorRequest,
      artifacts: artifacts
    )
    let evidence = try PlotterEvidence(
      id: PlotterEvidenceID(rawValue: UUID()),
      episodeID: episodeID,
      subject: .observation(observationID),
      question: .pointIdentity,
      inputEnvironment: submission.frame.source.environment,
      evidenceClass: .operatorAssertion,
      acceptedBy: EpisodeAuthorityID(rawValue: "PlotterPointSelectionAuthority"),
      acceptedAt: Date(),
      applicabilityRevision: EpisodeRevisionIdentifier(rawValue: "exact-frame-point-v1"),
      artifactReferences: artifacts
    )
    _ = try await commit(
      payload: .evidenceDecided(.accepted(evidence)),
      origin: .policy,
      artifacts: artifacts
    )
  }

  private func submitIntent(
    _ intent: PlotterIntent,
    facts: [PlotterCapabilityFact] = []
  ) async throws -> CommittedPointSelectionEvent {
    let state = await store.currentState()
    let environment = state.exactPointSelection.request?.frame.source.environment ?? .live
    let evaluated = try gateway.evaluate(
      requestID: IntentRequestID(rawValue: UUID()),
      intent: intent,
      state: state,
      capabilityFacts: facts,
      environment: environment
    )
    return try await commit(payload: evaluated.payload, origin: .operatorRequest)
  }

  private func commit(
    payload: PlotterEpisodeEventPayload,
    origin: EpisodeEventOrigin,
    artifacts: [EpisodeArtifactReference] = []
  ) async throws -> CommittedPointSelectionEvent {
    let preState = await store.currentState()
    let postRevision = EpisodeStateRevision(rawValue: preState.revision.rawValue + 1)
    let eventID = EpisodeEventID(rawValue: UUID())
    let recordedAt = Date()
    let actor = EpisodeEventActor(
      id: EpisodeActorID(rawValue: "PlotterPointSelectionRuntime"),
      origin: origin
    )
    let correlation = EpisodeCorrelationID(rawValue: UUID())
    let provisional = PlotterEpisodeEvent(
      id: eventID,
      episodeID: episodeID,
      sequence: EpisodeEventSequence(rawValue: preState.revision.rawValue),
      recordedAt: recordedAt,
      actor: actor,
      correlationID: correlation,
      preStateRevision: preState.revision,
      postStateRevision: postRevision,
      payload: payload,
      artifactReferences: artifacts,
      postStateDigest: EpisodeStateDigest(rawValue: "pending")
    )
    let prototype = PlotterEpisodeReducer().reduce(state: preState, event: provisional).state
    let digest = try PlotterEpisodeCanonicalDigestV1.digest(prototype)
    let event = PlotterEpisodeEvent(
      id: eventID,
      episodeID: episodeID,
      sequence: provisional.sequence,
      recordedAt: recordedAt,
      actor: actor,
      correlationID: correlation,
      preStateRevision: preState.revision,
      postStateRevision: postRevision,
      payload: payload,
      artifactReferences: artifacts,
      postStateDigest: digest
    )
    let reduction = try await store.append(event)
    return CommittedPointSelectionEvent(event: event, state: reduction.state)
  }

  private func project(_ state: PlotterEpisodeState) -> PlotterEpisodeProjection {
    projectionRevision &+= 1
    return PlotterEpisodeProjector.project(
      state: state,
      availabilities: [],
      revision: PlotterProjectionRevision(rawValue: projectionRevision),
      projectedAt: Date()
    )
  }

  private func sampleEnvironment(for selectionID: PlotterPointSelectionID)
    -> PlotterEnvironment
  {
    framesBySelectionID[selectionID]?.source.pointSelectionSource.environment ?? .live
  }

  private func acquireMutationPublicationBoundary() async {
    guard mutationPublicationBoundaryIsHeld else {
      mutationPublicationBoundaryIsHeld = true
      return
    }
    await withCheckedContinuation { continuation in
      mutationPublicationBoundaryWaiters.append(continuation)
    }
  }

  private func releaseMutationPublicationBoundary() {
    guard !mutationPublicationBoundaryWaiters.isEmpty else {
      mutationPublicationBoundaryIsHeld = false
      return
    }
    mutationPublicationBoundaryWaiters.removeFirst().resume()
  }

  private func record(_ frame: DisplayedFrame) async
    -> (artifact: EpisodeArtifactReference?, locator: String?, diagnostic: String?)
  {
    guard let recordingStore else {
      return (
        nil,
        nil,
        recordingUnavailableDiagnostic ?? "Exact frame bytes were not archived."
      )
    }
    let stream = CameraStreamIdentity(
      source: CameraSourceIdentity(rawValue: frame.source.recordingSourceIdentity),
      configuration: CameraConfigurationIdentity(rawValue: frame.frame.cameraConfigurationID.rawValue)
    )
    do {
      var offset = max(lastRecordingOffset, frame.frame.captureNanoseconds)
      if activeRecordedStream != stream {
        if let activeRecordedStream {
          _ = try await recordingStore.recordCameraLifecycle(
            .stopRequested(activeRecordedStream),
            at: offset
          )
          offset &+= 1
          _ = try await recordingStore.recordCameraLifecycle(
            .stopped(activeRecordedStream),
            at: offset
          )
          offset &+= 1
        }
        _ = try await recordingStore.recordCameraLifecycle(.startRequested(stream), at: offset)
        offset &+= 1
        _ = try await recordingStore.recordCameraLifecycle(.started(stream), at: offset)
        offset &+= 1
        activeRecordedStream = stream
      }
      let entry = try await recordingStore.recordCameraFrame(
        CameraFrameDescriptor(
          stream: stream,
          frameID: CameraFrameIdentity(rawValue: frame.frame.id.rawValue),
          sequence: frame.frame.sequence,
          captureNanoseconds: frame.frame.captureNanoseconds,
          width: frame.frame.width,
          height: frame.frame.height,
          rowBytes: frame.frame.rowBytes,
          pixelFormat: frame.frame.pixelFormat.recordingPixelFormat
        ),
        bytes: frame.frame.bytes.data,
        at: offset,
        provenance: EpisodeRecordingProvenance(
          episodeID: episodeID,
          environment: frame.source.pointSelectionSource.environment
        )
      )
      lastRecordingOffset = offset
      guard case let .camera(.frameReference(record)) = entry.record else {
        return (nil, nil, "Exact frame recording returned no frame reference.")
      }
      let artifact = EpisodeArtifactReference(
        id: EpisodeArtifactID(rawValue: record.artifact.relativePath),
        revision: EpisodeRevisionIdentifier(rawValue: "sha256-v1"),
        digest: record.artifact.contentSHA256
      )
      return (artifact, record.artifact.relativePath, nil)
    } catch {
      return (nil, nil, "Exact frame bytes were not archived: \(error)")
    }
  }
}

private struct CommittedPointSelectionEvent: Sendable {
  let event: PlotterEpisodeEvent
  let state: PlotterEpisodeState
}

public enum PlotterPointSelectionRuntimeError: Error, Equatable, Sendable {
  case operationAttributionRefused
  case replacementNotCurrent
}

private extension IntentDecision {
  var firstRefusalRemedy: String? {
    guard case let .refused(_, requirements) = self else { return nil }
    return requirements.first?.remedy
  }
}

private extension PlotterEpisodeEvent {
  var intentRequestID: IntentRequestID? {
    switch payload {
    case let .intentAccepted(value): value.requestID
    case let .intentRefused(value): value.requestID
    default: nil
    }
  }
}

private extension FrameSourceIdentity {
  var pointSelectionSource: PlotterExactFrameSource {
    switch self {
    case .live(let deviceID): .live(deviceID: deviceID.rawValue)
    case .simulated: .simulated
    }
  }

  var recordingSourceIdentity: String {
    switch self {
    case .live(let deviceID): "live:\(deviceID.rawValue)"
    case .simulated: "simulated"
    }
  }
}

private extension DisplayedFrame {
  func pointSelectionReference(
    artifact: EpisodeArtifactReference?,
    locator: String?
  ) -> PlotterExactFrameReference {
    PlotterExactFrameReference(
      frameID: frame.id.rawValue,
      frameSHA256: frame.contentSHA256,
      source: source.pointSelectionSource,
      cameraConfigurationID: frame.cameraConfigurationID,
      captureNanoseconds: frame.captureNanoseconds,
      sequence: frame.sequence,
      width: frame.width,
      height: frame.height,
      rowBytes: frame.rowBytes,
      pixelFormat: PlotterExactFramePixelFormat(rawValue: frame.pixelFormat.rawValue)!,
      archivedBytes: artifact,
      archivedByteLocator: locator
    )
  }
}

private extension FramePixelFormat {
  var recordingPixelFormat: CameraPixelFormat {
    switch self {
    case .gray8: .gray8
    case .rgba8: .rgba8
    case .bgra8: .bgra8
    }
  }
}
