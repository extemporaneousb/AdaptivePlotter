import CoreGraphics
import EpisodeCore
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Plotter point-selection episode")
struct PlotterPointSelectionEpisodeTests {
  @Test("exact frame, source, configuration, presentation, bounds, and capacity refuse visibly")
  func exactIdentityAndCapacityRefusals() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let frame = try pointSelectionFrame(id: "exact-current")
    let stage = try await runtime.stage(
      frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select two exact-frame points",
      purpose: .toolContact,
      requiredPointCount: 2
    )

    let staleFrames = [
      replacing(stage.request.frame, frameID: "stale-frame-id"),
      replacing(stage.request.frame, frameSHA256: String(repeating: "f", count: 64)),
      replacing(stage.request.frame, source: .live(deviceID: "other-camera")),
      replacing(stage.request.frame, cameraConfigurationID: CameraConfigurationID()),
    ]
    for staleFrame in staleFrames {
      let result = try await runtime.submit(
        submission(for: stage.request, frame: staleFrame, x: 2, y: 2)
      )
      guard case let .refused(projection, reason) = result else {
        Issue.record("Expected stale exact-frame identity to be refused")
        continue
      }
      #expect(reason == "Submit the point against the exact frozen frame currently presented.")
      #expect(projection.remedy == reason)
      #expect(projection.exactPointSelection.selectedPoints.isEmpty)
    }

    let stalePresentation = try await runtime.submit(
      PlotterPointSelectionSubmission(
        selectionID: stage.request.id,
        frame: stage.request.frame,
        point: Point2(x: 2, y: 2),
        presentationTransformRevision: PlotterPresentationTransformRevision()
      )
    )
    guard case let .refused(presentationProjection, presentationReason) = stalePresentation else {
      Issue.record("Expected stale presentation revision to be refused")
      return
    }
    #expect(presentationReason == "Submit from the current unmodified point-selection presentation.")
    #expect(presentationProjection.remedy == presentationReason)

    let outside = try await runtime.submit(
      submission(for: stage.request, x: Double(stage.request.frame.width), y: 2)
    )
    guard case let .refused(boundsProjection, boundsReason) = outside else {
      Issue.record("Expected an out-of-bounds point to be refused")
      return
    }
    #expect(boundsReason == "Select a point inside the exact camera frame.")
    #expect(boundsProjection.remedy == boundsReason)

    _ = try await runtime.submit(submission(for: stage.request, x: 2, y: 2))
    _ = try await runtime.submit(submission(for: stage.request, x: 6, y: 6))
    let overCapacity = try await runtime.submit(submission(for: stage.request, x: 4, y: 4))
    guard case let .refused(capacityProjection, capacityReason) = overCapacity else {
      Issue.record("Expected a completed selection to refuse another point")
      return
    }
    #expect(capacityReason == "Finish, undo, clear, or cancel the current point-selection request.")
    #expect(capacityProjection.remedy == capacityReason)
    #expect(capacityProjection.exactPointSelection.selectedPoints.count == 2)
  }

  @Test("production ActionSurface ingress carries the staged revision and stale requests refuse")
  func actionSurfaceIngressUsesStagedPresentationRevision() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let frame = try pointSelectionFrame(id: "action-surface-ingress")
    let first = try await runtime.stage(
      frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the current point",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    let viewport = ActionSurfaceViewportState()
    #expect(
      viewport.presentationTransformRevision.rawValue
        != first.request.presentationTransformRevision.rawValue
    )
    let oldSubmission = try #require(
      ExactFramePointSubmissionBuilder.submission(
        presentation: ActionSurfacePresentation(
          displayedFrame: frame,
          overlays: [],
          pointSelectionRequest: first.request
        ),
        viewport: viewport,
        at: CGPoint(x: 40, y: 40),
        viewSize: CGSize(width: 90, height: 90)
      )
    )
    #expect(
      oldSubmission.presentationTransformRevision
        == first.request.presentationTransformRevision
    )

    let replacementFrame = try pointSelectionFrame(
      id: "action-surface-replacement",
      captureNanoseconds: frame.frame.captureNanoseconds + 1
    )
    let replacement = try await runtime.replace(
      currentRequest: first.request,
      with: replacementFrame,
      presentationTransformRevision: PlotterPresentationTransformRevision()
    )
    let stale = try await runtime.submit(oldSubmission)
    guard case let .refused(staleProjection, staleReason) = stale else {
      Issue.record("The replaced production-ingress submission must be refused")
      return
    }
    #expect(staleReason == "Use the currently presented point-selection request.")
    #expect(staleProjection.exactPointSelection.selectedPoints.isEmpty)

    let currentSubmission = try #require(
      ExactFramePointSubmissionBuilder.submission(
        presentation: ActionSurfacePresentation(
          displayedFrame: replacementFrame,
          overlays: [],
          pointSelectionRequest: replacement.request
        ),
        viewport: viewport,
        at: CGPoint(x: 40, y: 40),
        viewSize: CGSize(width: 90, height: 90)
      )
    )
    #expect(
      currentSubmission.presentationTransformRevision
        == replacement.request.presentationTransformRevision
    )
    guard case .acceptedBatch = try await runtime.submit(currentSubmission) else {
      Issue.record("The current production-ingress submission must be admitted")
      return
    }
  }

  @Test("exact-frame replacement is atomic and requires an empty current request")
  func replacementRequiresEmptyCurrentRequest() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let initialFrame = try pointSelectionFrame(id: "replacement-initial")
    let initial = try await runtime.stage(
      frame: initialFrame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select two exact-frame points",
      purpose: .toolContact,
      requiredPointCount: 2
    )
    _ = try await runtime.submit(submission(for: initial.request, x: 2, y: 2))
    let replacementFrame = try pointSelectionFrame(
      id: "replacement-current",
      captureNanoseconds: initialFrame.frame.captureNanoseconds + 1
    )

    await #expect(throws: PlotterPointSelectionRuntimeError.replacementNotCurrent) {
      try await runtime.replace(
        currentRequest: initial.request,
        with: replacementFrame,
        presentationTransformRevision: PlotterPresentationTransformRevision()
      )
    }
    let retained = await runtime.currentProjection().exactPointSelection
    #expect(retained.request == initial.request)
    #expect(retained.selectedPoints.count == 1)

    _ = try await runtime.clear(selectionID: initial.request.id)
    let replacement = try await runtime.replace(
      currentRequest: initial.request,
      with: replacementFrame,
      presentationTransformRevision: PlotterPresentationTransformRevision()
    )
    #expect(replacement.request.id != initial.request.id)
    #expect(replacement.request.frame.captureNanoseconds > initial.request.frame.captureNanoseconds)
    #expect(replacement.projection.exactPointSelection.selectedPoints.isEmpty)

    let stale = try await runtime.submit(submission(for: initial.request, x: 3, y: 3))
    guard case let .refused(projection, reason) = stale else {
      Issue.record("The superseded request must refuse a stale click")
      return
    }
    #expect(reason == "Use the currently presented point-selection request.")
    #expect(projection.exactPointSelection.request == replacement.request)
    #expect(projection.exactPointSelection.selectedPoints.isEmpty)
  }

  @Test("accepted point commits intent, observation, evidence, and projection")
  func acceptedPointObservationEvidenceProjection() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let stage = try await runtime.stage(
      frame: pointSelectionFrame(id: "accepted-evidence"),
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select one exact point",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    let stagedRevision = stage.projection.runtimeStateRevision.rawValue
    let selected = try Point2<CameraPixelSpace>(x: 3, y: 5)

    let result = try await runtime.submit(
      submission(for: stage.request, point: selected)
    )
    guard case let .acceptedBatch(points, revision, projection) = result else {
      Issue.record("Expected the one-point batch to be accepted")
      return
    }
    #expect(points == [selected])
    #expect(revision == stage.request.presentationTransformRevision)
    #expect(projection.exactPointSelection.phase == .accepted)
    #expect(projection.exactPointSelection.selectedPoints == [selected])
    // The production path appends the admitted intent, source-bound operator
    // observation, and accepted point-identity evidence as three commits.
    #expect(projection.runtimeStateRevision.rawValue == stagedRevision + 3)
    #expect(projection.runtimeStateDigest != stage.projection.runtimeStateDigest)
  }

  @Test("pen-cap sampling archives the exact accepted frame")
  func penCapSamplingAndRecording() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "PlotterPointSelectionEpisodeTests-\(UUID().uuidString)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let recordingID = EpisodeRecordingID(rawValue: UUID())
    let recording = try EpisodeRecordingStore.open(
      directoryURL: directory,
      recordingID: recordingID,
      schemaRevision: EpisodeRecordingSchemaRevision(rawValue: "point-selection-test-v1"),
      frameRetentionPolicy: EpisodeFrameRetentionPolicy(
        maximumUniqueFrameCount: 4,
        maximumTotalUniqueFrameBytes: 1_000_000
      )
    )
    let runtime = PlotterPointSelectionRuntime(recordingStore: recording)
    let frame = try pointSelectionFrame(id: "recorded-pen-cap", red: 20, green: 80, blue: 220)
    let stage = try await runtime.stage(
      frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the pen cap",
      purpose: .penCapAppearance,
      requiredPointCount: 1
    )

    #expect(stage.recordingDiagnostic == nil)
    #expect(stage.request.frame.archivedBytes != nil)
    #expect(stage.request.frame.archivedByteLocator != nil)
    let result = try await runtime.submit(submission(for: stage.request, x: 4, y: 4))
    guard case let .acceptedPenCap(sample, acceptedFrame, projection) = result else {
      Issue.record("Expected the chromatic Pen-cap point to be sampled")
      return
    }
    #expect((sample.red, sample.green, sample.blue) == (20, 80, 220))
    #expect(acceptedFrame.frame.id == frame.frame.id)
    #expect(projection.exactPointSelection.phase == .accepted)

    let snapshot = await recording.snapshot()
    let frames = snapshot.entries.compactMap { entry -> CameraFrameRecord? in
      guard case let .camera(.frameReference(frame)) = entry.record else { return nil }
      return frame
    }
    #expect(frames.count == 1)
    let archived = try #require(frames.first)
    #expect(archived.descriptor.frameID.rawValue == frame.frame.id.rawValue)
    let archivedBytes = try await recording.frameBytes(for: archived.artifact)
    #expect(archivedBytes == frame.frame.bytes.data)

    let diagnostic = "Point-selection recording is unavailable for this test."
    let fallbackRuntime = PlotterPointSelectionRuntime(
      recordingUnavailableDiagnostic: diagnostic
    )
    let fallbackStage = try await fallbackRuntime.stage(
      frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select without a recording store",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    #expect(fallbackStage.recordingDiagnostic == diagnostic)
    let fallbackResult = try await fallbackRuntime.submit(
      submission(for: fallbackStage.request, x: 4, y: 4)
    )
    guard case let .acceptedBatch(_, _, fallbackProjection) = fallbackResult else {
      Issue.record("Recording diagnostics must not block point acceptance")
      return
    }
    #expect(fallbackProjection.exactPointSelection.phase == .accepted)
  }

  @Test("Learning Off cancels its exact continuation but unrelated Learning work refuses")
  func learningOffCancellationAndNonRevival() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let frame = try pointSelectionFrame(id: "continuation", red: 20, green: 80, blue: 220)
    let stage = try await runtime.stage(
      frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the pen cap",
      purpose: .penCapAppearance,
      requiredPointCount: 1
    )
    let accepted = try await runtime.submit(submission(for: stage.request, x: 4, y: 4))
    guard case let .acceptedPenCap(sample, _, _) = accepted else {
      Issue.record("Expected a Pen-cap sample before continuation")
      return
    }
    let port = SuspendedPointSelectionContinuationPort()
    try await runtime.beginPenCapContinuation(
      selectionID: stage.request.id,
      sample: sample,
      port: port
    )
    let active = await runtime.currentProjection()
    #expect(active.exactPointSelection.phase == .continuing)
    #expect(active.exactPointSelection.continuationIsActive)

    let pointSelectionOwner = PlotterPointSelectionActivityOwner(
      selectionID: stage.request.id,
      exerciseAttemptID: UUID()
    )
    let firstActivityFact = learningFact(pointSelectionOwner: pointSelectionOwner)
    let sharedAvailability = PlotterLearningIntentRules.modeAvailability(
      targetIsEnabled: false,
      exactPointSelection: active.exactPointSelection,
      activityFact: firstActivityFact
    )
    #expect(sharedAvailability.isAvailable)
    let learningOff = try await runtime.setLearningEnabled(
      false,
      activityFactProvider: FixedLearningActivityFactProvider(firstActivityFact)
    )
    #expect(!learningOff.learningIsEnabled)
    #expect(learningOff.exactPointSelection.phase == .idle)
    #expect(!learningOff.exactPointSelection.continuationIsActive)
    let settled = await runtime.currentProjection()
    #expect(!settled.learningIsEnabled)
    #expect(settled.exactPointSelection.phase == .idle)
    let configureCount = await port.configureCount
    #expect(configureCount == 0)

    _ = try await runtime.setLearningEnabled(
      true,
      activityFactProvider: FixedLearningActivityFactProvider(learningFact(revision: 2))
    )
    let unrelatedFact = learningFact(revision: 3, activeAttempt: true)
    let unrelatedAvailability = PlotterLearningIntentRules.modeAvailability(
      targetIsEnabled: false,
      exactPointSelection: settled.exactPointSelection,
      activityFact: unrelatedFact
    )
    #expect(!unrelatedAvailability.isAvailable)
    #expect(unrelatedAvailability.refusalOwner == unrelatedFact.owner)
    #expect(unrelatedAvailability.refusalRemedy == PlotterLearningIntentRules.learningOffRemedy)
    let refused = try await runtime.setLearningEnabled(
      false,
      activityFactProvider: FixedLearningActivityFactProvider(unrelatedFact)
    )
    #expect(refused.learningIsEnabled)
    #expect(refused.currentReason == PlotterIntentRequirement.learningWorkInactive.id.rawValue)
    #expect(refused.authoritativeOwner == unrelatedFact.owner)
    #expect(refused.remedy == PlotterLearningIntentRules.learningOffRemedy)

    let retainedPenRuntime = PlotterPointSelectionRuntime()
    let retainedPenStage = try await retainedPenRuntime.stage(
      frame: pointSelectionFrame(
        id: "retained-accepted-pen",
        red: 20,
        green: 80,
        blue: 220
      ),
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the pen cap",
      purpose: .penCapAppearance,
      requiredPointCount: 1
    )
    let retainedPenResult = try await retainedPenRuntime.submit(
      submission(for: retainedPenStage.request, x: 4, y: 4)
    )
    guard case let .acceptedPenCap(retainedSample, _, _) = retainedPenResult else {
      Issue.record("Expected a retained accepted Pen-cap request")
      return
    }
    try await retainedPenRuntime.beginPenCapContinuation(
      selectionID: retainedPenStage.request.id,
      sample: retainedSample,
      port: SuspendedPointSelectionContinuationPort()
    )
    await retainedPenRuntime.cancelContinuation(selectionID: retainedPenStage.request.id)
    let retainedPenProjection = await retainedPenRuntime.currentProjection()
    #expect(retainedPenProjection.exactPointSelection.phase == .accepted)
    #expect(!retainedPenProjection.exactPointSelection.continuationIsActive)
    let retainedPenFact = learningFact(
      revision: 4,
      pointSelectionOwner: PlotterPointSelectionActivityOwner(
        selectionID: retainedPenStage.request.id,
        exerciseAttemptID: UUID()
      ),
      activeDiscovery: true
    )
    let retainedPenAvailability = PlotterLearningIntentRules.modeAvailability(
      targetIsEnabled: false,
      exactPointSelection: retainedPenProjection.exactPointSelection,
      activityFact: retainedPenFact
    )
    #expect(!retainedPenAvailability.isAvailable)
    let retainedPenRefusal = try await retainedPenRuntime.setLearningEnabled(
      false,
      activityFactProvider: FixedLearningActivityFactProvider(retainedPenFact)
    )
    #expect(retainedPenRefusal.learningIsEnabled)
    #expect(
      retainedPenRefusal.currentReason
        == PlotterIntentRequirement.learningWorkInactive.id.rawValue
    )

    let retainedSparseRuntime = PlotterPointSelectionRuntime()
    let retainedSparseStage = try await retainedSparseRuntime.stage(
      frame: pointSelectionFrame(id: "retained-accepted-sparse"),
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the calibration point",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    let retainedSparseResult = try await retainedSparseRuntime.submit(
      submission(for: retainedSparseStage.request, x: 4, y: 4)
    )
    guard case let .acceptedBatch(_, _, retainedSparseProjection) = retainedSparseResult else {
      Issue.record("Expected a retained accepted sparse calibration batch")
      return
    }
    #expect(retainedSparseProjection.exactPointSelection.phase == .accepted)
    let retainedSparseFact = learningFact(
      revision: 5,
      pointSelectionOwner: PlotterPointSelectionActivityOwner(
        selectionID: retainedSparseStage.request.id,
        exerciseAttemptID: UUID()
      )
    )
    let retainedSparseAvailability = PlotterLearningIntentRules.modeAvailability(
      targetIsEnabled: false,
      exactPointSelection: retainedSparseProjection.exactPointSelection,
      activityFact: retainedSparseFact
    )
    #expect(!retainedSparseAvailability.isAvailable)
    let retainedSparseRefusal = try await retainedSparseRuntime.setLearningEnabled(
      false,
      activityFactProvider: FixedLearningActivityFactProvider(retainedSparseFact)
    )
    #expect(retainedSparseRefusal.learningIsEnabled)
    #expect(
      retainedSparseRefusal.currentReason
        == PlotterIntentRequirement.learningWorkInactive.id.rawValue
    )
  }

  @Test("Learning Off refuses a successor attempt for the same item after cancellation suspends")
  func learningOffReacquiresActivityAfterCancellation() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let frame = try pointSelectionFrame(
      id: "learning-fact-refresh",
      red: 20,
      green: 80,
      blue: 220
    )
    let stage = try await runtime.stage(
      frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the pen cap",
      purpose: .penCapAppearance,
      requiredPointCount: 1
    )
    let accepted = try await runtime.submit(submission(for: stage.request, x: 4, y: 4))
    guard case let .acceptedPenCap(sample, _, _) = accepted else {
      Issue.record("Expected a Pen-cap sample before the cancellation race")
      return
    }
    let port = CancellationHeldPointSelectionContinuationPort()
    try await runtime.beginPenCapContinuation(
      selectionID: stage.request.id,
      sample: sample,
      port: port
    )
    await port.waitUntilSuspended()

    let originalOwner = PlotterPointSelectionActivityOwner(
      selectionID: stage.request.id,
      exerciseAttemptID: UUID()
    )
    let provider = MutableLearningActivityFactProvider(
      learningFact(pointSelectionOwner: originalOwner)
    )
    let learningOff = Task {
      try await runtime.setLearningEnabled(false, activityFactProvider: provider)
    }
    await provider.waitForInitialRead()
    await port.waitUntilCancellationObserved()
    let successorOwner = PlotterPointSelectionActivityOwner(
      selectionID: stage.request.id,
      exerciseAttemptID: UUID()
    )
    #expect(successorOwner != originalOwner)
    let successor = learningFact(revision: 2, pointSelectionOwner: successorOwner)
    await provider.replace(with: successor)
    await port.release()

    let refused = try await learningOff.value
    #expect(refused.learningIsEnabled)
    #expect(refused.currentReason == PlotterIntentRequirement.learningWorkInactive.id.rawValue)
    #expect(refused.authoritativeOwner == successor.owner)
    #expect(refused.remedy == PlotterLearningIntentRules.learningOffRemedy)
    #expect(!refused.exactPointSelection.continuationIsActive)
    let settled = await runtime.currentProjection()
    #expect(settled.learningIsEnabled)
    #expect(!settled.exactPointSelection.continuationIsActive)
    let readCount = await provider.readCount
    #expect(readCount == 2)
  }

  @Test("concurrent selections re-evaluate capacity against the state each one commits")
  func concurrentSelectionCapacityIsSerialized() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let stage = try await runtime.stage(
      frame: pointSelectionFrame(id: "concurrent-capacity"),
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select one point",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    let first = Task {
      try await runtime.submit(submission(for: stage.request, x: 2, y: 2))
    }
    let second = Task {
      try await runtime.submit(submission(for: stage.request, x: 6, y: 6))
    }
    let firstResult = try await first.value
    let secondResult = try await second.value
    let results = [firstResult, secondResult]
    var acceptedCount = 0
    var refusedCount = 0
    for result in results {
      switch result {
      case .acceptedBatch:
        acceptedCount += 1
      case .refused:
        refusedCount += 1
      case .acceptedPoint, .acceptedPenCap:
        Issue.record("A one-point batch returned an invalid terminal result")
      }
    }
    #expect(acceptedCount == 1)
    #expect(refusedCount == 1)
    let final = await runtime.currentProjection()
    #expect(final.exactPointSelection.selectedPoints.count == 1)
    #expect(final.exactPointSelection.phase == .accepted)
  }

  @Test("public projection never exposes the middle of an accepted selection transaction")
  func publicProjectionIsTransactionComplete() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let stage = try await runtime.stage(
      frame: pointSelectionFrame(id: "atomic-publication"),
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select one point",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    let stagedRevision = stage.projection.runtimeStateRevision.rawValue
    let selection = Task {
      try await runtime.submit(submission(for: stage.request, x: 4, y: 4))
    }
    var published: [PlotterEpisodeProjection] = []
    for _ in 0..<32 {
      let projection = await runtime.currentProjection()
      published.append(projection)
      if projection.exactPointSelection.selectedPoints.count == 1 { break }
      await Task.yield()
    }
    _ = try await selection.value
    published.append(await runtime.currentProjection())
    for projection in published where !projection.exactPointSelection.selectedPoints.isEmpty {
      #expect(projection.runtimeStateRevision.rawValue >= stagedRevision + 3)
      #expect(projection.exactPointSelection.phase == .accepted)
    }
  }

  @Test("sparse-tip selection keeps one authority through undo clear and four-point acceptance")
  func sparseTipUndoClearAndAtomicAcceptance() async throws {
    let runtime = PlotterPointSelectionRuntime()
    let stage = try await runtime.stage(
      frame: pointSelectionFrame(id: "sparse-tip"),
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select four corner-circle centers",
      purpose: .toolContact,
      requiredPointCount: 4
    )
    let points = try [
      Point2<CameraPixelSpace>(x: 1, y: 1),
      Point2<CameraPixelSpace>(x: 7, y: 1),
      Point2<CameraPixelSpace>(x: 7, y: 7),
      Point2<CameraPixelSpace>(x: 1, y: 7),
    ]
    _ = try await runtime.submit(submission(for: stage.request, point: points[0]))
    _ = try await runtime.submit(submission(for: stage.request, point: points[1]))
    let undone = try await runtime.undo(selectionID: stage.request.id)
    #expect(undone.exactPointSelection.selectedPoints == [points[0]])
    let cleared = try await runtime.clear(selectionID: stage.request.id)
    #expect(cleared.exactPointSelection.selectedPoints.isEmpty)
    #expect(cleared.exactPointSelection.phase == .collecting)

    var terminal: PlotterPointSelectionSubmissionResult?
    for point in points {
      terminal = try await runtime.submit(submission(for: stage.request, point: point))
    }
    guard case let .acceptedBatch(accepted, revision, projection)? = terminal else {
      Issue.record("Expected exactly four sparse-tip points to become one accepted batch")
      return
    }
    #expect(accepted == points)
    #expect(revision == stage.request.presentationTransformRevision)
    #expect(projection.exactPointSelection.phase == .accepted)
  }

  @Test("LIVE and SIMULATED exact-frame provenance remain distinct")
  func liveAndSimulatedProvenanceSeparation() async throws {
    let liveRuntime = PlotterPointSelectionRuntime()
    let simulatedRuntime = PlotterPointSelectionRuntime()
    let live = try pointSelectionFrame(
      id: "live-frame",
      source: .live(CameraDeviceID(rawValue: "camera-live"))
    )
    let simulated = try pointSelectionFrame(id: "simulated-frame", source: .simulated)
    let liveStage = try await liveRuntime.stage(
      frame: live,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "LIVE point",
      purpose: .toolContact,
      requiredPointCount: 1
    )
    let simulatedStage = try await simulatedRuntime.stage(
      frame: simulated,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "SIMULATED point",
      purpose: .toolContact,
      requiredPointCount: 1
    )

    #expect(liveStage.request.frame.source == .live(deviceID: "camera-live"))
    #expect(liveStage.request.frame.source.environment == .live)
    #expect(simulatedStage.request.frame.source == .simulated)
    #expect(simulatedStage.request.frame.source.environment == .simulated)
    let crossProvenance = try await liveRuntime.submit(
      submission(for: liveStage.request, frame: simulatedStage.request.frame, x: 4, y: 4)
    )
    guard case let .refused(projection, reason) = crossProvenance else {
      Issue.record("Expected SIMULATED provenance to be refused by the LIVE request")
      return
    }
    #expect(reason == "Submit the point against the exact frozen frame currently presented.")
    #expect(projection.exactPointSelection.selectedPoints.isEmpty)
  }

  @Test("episode point-selection runtime has no unchecked Sendable escape hatch")
  func runtimeHasNoUncheckedSendableEscapeHatch() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let runtimeSource = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/PlotterEpisodeRuntime/PlotterPointSelectionRuntime.swift"
      ),
      encoding: .utf8
    )
    #expect(!runtimeSource.contains("@unchecked Sendable"))
  }
}

private struct FixedLearningActivityFactProvider: PlotterLearningActivityFactProviding {
  let fact: PlotterLearningActivityFact

  init(_ fact: PlotterLearningActivityFact) {
    self.fact = fact
  }

  func currentLearningActivityFact() async -> PlotterLearningActivityFact {
    fact
  }
}

private actor MutableLearningActivityFactProvider: PlotterLearningActivityFactProviding {
  private var fact: PlotterLearningActivityFact
  private var initialReadWaiters: [CheckedContinuation<Void, Never>] = []
  private(set) var readCount = 0

  init(_ fact: PlotterLearningActivityFact) {
    self.fact = fact
  }

  func currentLearningActivityFact() async -> PlotterLearningActivityFact {
    readCount += 1
    let waiters = initialReadWaiters
    initialReadWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
    return fact
  }

  func waitForInitialRead() async {
    guard readCount == 0 else { return }
    await withCheckedContinuation { initialReadWaiters.append($0) }
  }

  func replace(with fact: PlotterLearningActivityFact) {
    self.fact = fact
  }
}

private actor CancellationHeldPointSelectionContinuationPort:
  PlotterPointSelectionContinuationPort
{
  private var suspension: CheckedContinuation<Void, Never>?
  private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
  private var cancellationWasObserved = false
  private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

  func beginPenCapDiscovery(selectionID _: PlotterPointSelectionID) async throws {
    try await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        suspension = continuation
        let waiters = suspensionWaiters
        suspensionWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
      }
      try Task.checkCancellation()
    } onCancel: {
      Task { await self.recordCancellation() }
    }
  }

  func configurePenCapVision(
    selectionID _: PlotterPointSelectionID,
    sample _: PlotterAcceptedPenCapSample
  ) async throws {}

  func waitUntilSuspended() async {
    guard suspension == nil else { return }
    await withCheckedContinuation { suspensionWaiters.append($0) }
  }

  func waitUntilCancellationObserved() async {
    guard !cancellationWasObserved else { return }
    await withCheckedContinuation { cancellationWaiters.append($0) }
  }

  func release() {
    let continuation = suspension
    suspension = nil
    continuation?.resume()
  }

  private func recordCancellation() {
    cancellationWasObserved = true
    let waiters = cancellationWaiters
    cancellationWaiters.removeAll()
    for waiter in waiters { waiter.resume() }
  }
}

private actor SuspendedPointSelectionContinuationPort: PlotterPointSelectionContinuationPort {
  private(set) var configureCount = 0

  func beginPenCapDiscovery(selectionID _: PlotterPointSelectionID) async throws {
    try await Task.sleep(nanoseconds: 30_000_000_000)
  }

  func configurePenCapVision(
    selectionID _: PlotterPointSelectionID,
    sample _: PlotterAcceptedPenCapSample
  ) async throws {
    configureCount += 1
  }
}

private func learningFact(
  revision: UInt64 = 1,
  pointSelectionOwner: PlotterPointSelectionActivityOwner? = nil,
  activeAttempt: Bool = false,
  activeDiscovery: Bool = false
) -> PlotterLearningActivityFact {
  PlotterLearningActivityFact(
    owner: EpisodeAuthorityID(rawValue: "PlotterPointSelectionEpisodeTests"),
    revision: CapabilityFactRevision(rawValue: revision),
    activeCameraCalibration: false,
    activeAttempt: activeAttempt || pointSelectionOwner != nil,
    activeDiscovery: activeDiscovery,
    activeExploration: false,
    activeLearningMotion: false,
    pointSelectionOwner: pointSelectionOwner
  )
}

private func pointSelectionFrame(
  id: String,
  source: FrameSourceIdentity = .simulated,
  configuration: CameraConfigurationID = CameraConfigurationID(),
  captureNanoseconds: UInt64 = 10,
  red: UInt8 = 20,
  green: UInt8 = 80,
  blue: UInt8 = 220
) throws -> DisplayedFrame {
  let width = 9
  let height = 9
  let pixel = [red, green, blue, UInt8(255)]
  return DisplayedFrame(
    source: source,
    frame: try StampedFrame(
      id: FrameID(rawValue: id),
      sequence: 1,
      captureNanoseconds: captureNanoseconds,
      cameraConfigurationID: configuration,
      width: width,
      height: height,
      rowBytes: width * pixel.count,
      pixelFormat: .rgba8,
      bytes: OwnedFrameBytes(Array(repeating: pixel, count: width * height).flatMap { $0 })
    )
  )
}

private func submission(
  for request: PlotterPointSelectionRequest,
  frame: PlotterExactFrameReference? = nil,
  point: Point2<CameraPixelSpace>? = nil,
  x: Double = 4,
  y: Double = 4
) throws -> PlotterPointSelectionSubmission {
  let selectedPoint: Point2<CameraPixelSpace>
  if let point {
    selectedPoint = point
  } else {
    selectedPoint = try Point2(x: x, y: y)
  }
  return PlotterPointSelectionSubmission(
    selectionID: request.id,
    frame: frame ?? request.frame,
    point: selectedPoint,
    presentationTransformRevision: request.presentationTransformRevision
  )
}

private func replacing(
  _ frame: PlotterExactFrameReference,
  frameID: String? = nil,
  frameSHA256: String? = nil,
  source: PlotterExactFrameSource? = nil,
  cameraConfigurationID: CameraConfigurationID? = nil
) -> PlotterExactFrameReference {
  PlotterExactFrameReference(
    frameID: frameID ?? frame.frameID,
    frameSHA256: frameSHA256 ?? frame.frameSHA256,
    source: source ?? frame.source,
    cameraConfigurationID: cameraConfigurationID ?? frame.cameraConfigurationID,
    captureNanoseconds: frame.captureNanoseconds,
    sequence: frame.sequence,
    width: frame.width,
    height: frame.height,
    rowBytes: frame.rowBytes,
    pixelFormat: frame.pixelFormat,
    archivedBytes: frame.archivedBytes,
    archivedByteLocator: frame.archivedByteLocator
  )
}
