import Foundation
import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Motion Preflight calibration model")
struct PreflightCalibrationTests {
  @Test("catalog covers four boundaries and both physical pen positions")
  func catalogIsCompleteAndSpeechBounded() {
    #expect(PreflightSequenceCatalog.title == "Motion Preflight")
    #expect(
      Set(PreflightSequenceCatalog.all.map(\.id))
        == Set(PreflightSequenceID.allCases)
    )

    for definition in PreflightSequenceCatalog.all {
      #expect(definition.steps.first?.action == .startSpeechListening)
      #expect(definition.steps.first?.expectedEvent == .speechListeningStarted)
      #expect(definition.steps.last?.action == .stopSpeechListening)
      #expect(definition.steps.last?.expectedEvent == .speechListeningStopped)
    }

    let boundaryDefinitions = PreflightSequenceCatalog.all.filter {
      $0.sequenceClass == .boundaryMeasurement
    }
    #expect(boundaryDefinitions.count == 4)
    #expect(boundaryDefinitions.allSatisfy { $0.voiceResponses == [.ready, .stop] })

    for id in [PreflightSequenceID.penUpConfirmation, .penDownConfirmation] {
      let definition = PreflightSequenceCatalog.definition(for: id)
      let confirmationIndex = definition.steps.firstIndex {
        if case .awaitPhysicalPenConfirmation = $0.action { return true }
        return false
      }
      let captureIndex = definition.steps.firstIndex { $0.action == .captureFreshCameraFrame }
      #expect(confirmationIndex != nil)
      #expect(captureIndex != nil)
      if let confirmationIndex, let captureIndex {
        #expect(captureIndex == confirmationIndex + 1)
      }
    }
  }

  @Test("voice responses are exact and transaction-context bound")
  func parserIsNarrow() {
    let parser = PreflightVoiceResponseParser()
    let context = PreflightVoiceContext(
      sequenceID: .penUpConfirmation,
      stepID: "confirm-physical-pen",
      expectedResponse: .penIsPhysicallyUp
    )

    #expect(parser.parse("Pen is physically up.", in: context) == .penIsPhysicallyUp)
    #expect(parser.parse("pen is physically down", in: context) == nil)
    #expect(parser.parse("yes, pen is physically up", in: context) == nil)
    #expect(parser.parse("pen is physically up now", in: context) == nil)
  }

  @Test("transaction exposes progress and keeps controller camera and operator evidence distinct")
  func transactionIsObservable() throws {
    let configurationID = CameraConfigurationID()
    var transaction = PreflightTransaction(sequenceID: .penUpConfirmation)
    try transaction.begin()
    #expect(transaction.currentStep?.action == .startSpeechListening)
    #expect(transaction.progress == 0)

    try transaction.record(.speechListeningStarted)
    try transaction.record(.promptSpoken)
    try transaction.record(
      .penCommandSettled(.raise, controllerSummary: "M3 S40 and dwell accepted")
    )
    let context = try #require(transaction.voiceContext)
    #expect(context.expectedResponse == .penIsPhysicallyUp)
    try transaction.record(
      .physicalPenConfirmed(
        .up,
        response: .penIsPhysicallyUp,
        operatorSummary: "tip visibly clear of paper"
      )
    )
    try transaction.record(
      .freshFrameCaptured(FrameID(rawValue: "pen-up-frame"), configurationID)
    )
    #expect(transaction.state == .active)
    try transaction.record(.speechListeningStopped)

    #expect(transaction.state == .succeeded)
    #expect(transaction.progress == 1)
    #expect(transaction.currentStep == nil)
    #expect(transaction.evidenceSummaries.map(\.kind).contains(.controller))
    #expect(transaction.evidenceSummaries.map(\.kind).contains(.operatorObservation))
    #expect(transaction.evidenceSummaries.map(\.kind).contains(.camera))
    #expect(!transaction.evidenceSummaries.map(\.kind).contains(.observedInk))
    let pairedFrame = try #require(
      transaction.evidenceSummaries.first { $0.kind == .camera }
    )
    #expect(pairedFrame.frameID == FrameID(rawValue: "pen-up-frame"))
    #expect(pairedFrame.cameraConfigurationID == configurationID)
  }

  @Test("cancelling an active transaction exposes speech teardown before cancellation completes")
  func cancellationStopsSpeech() throws {
    var transaction = PreflightTransaction(sequenceID: .boundaryPositiveX)
    try transaction.begin()
    try transaction.record(.speechListeningStarted)

    transaction.cancel()
    #expect(transaction.state == .cancelling)
    #expect(transaction.currentStep?.action == .stopSpeechListening)

    try transaction.record(.speechListeningStopped)
    #expect(transaction.state == .cancelled)
    #expect(transaction.currentStep == nil)
  }

  @Test("unexpected or invalid evidence does not advance the current step")
  func invalidEventDoesNotAdvance() throws {
    var transaction = PreflightTransaction(sequenceID: .boundaryNegativeY)
    try transaction.begin()

    #expect(throws: PreflightTransactionError.unexpectedEvent(stepID: "start-speech")) {
      try transaction.record(.promptSpoken)
    }
    #expect(transaction.completedStepCount == 0)
    #expect(transaction.currentStep?.id == "start-speech")
  }

  @Test("rehearsal plays the typed timeline without evidence or readiness authority")
  func rehearsalIsPresentationOnly() throws {
    var rehearsal = PreflightRehearsal(sequenceID: .boundaryPositiveY)
    let stepCount = rehearsal.definition.steps.count

    try rehearsal.start()
    #expect(rehearsal.state == .running)
    #expect(rehearsal.currentStep == rehearsal.definition.steps.first)
    #expect(rehearsal.progress == 0)
    #expect(rehearsal.voiceContext == nil)

    try rehearsal.advance()
    try rehearsal.advance()
    #expect(rehearsal.voiceContext?.expectedResponse == .ready)

    for index in 2..<stepCount {
      try rehearsal.advance()
      #expect(rehearsal.completedStepCount == index + 1)
    }

    #expect(rehearsal.state == .completed)
    #expect(rehearsal.currentStep == nil)
    #expect(rehearsal.progress == 1)
    #expect(throws: PreflightRehearsalError.notRunning) {
      try rehearsal.advance()
    }
  }

  @Test("rehearsal cancellation is terminal and does not synthesize steps")
  func rehearsalCanCancel() throws {
    var rehearsal = PreflightRehearsal(sequenceID: .penUpConfirmation)
    try rehearsal.start()
    try rehearsal.advance()
    rehearsal.cancel()

    #expect(rehearsal.state == .cancelled)
    #expect(rehearsal.completedStepCount == 1)
    #expect(rehearsal.currentStep == nil)
    #expect(throws: PreflightRehearsalError.notRunning) {
      try rehearsal.advance()
    }
  }

  @Test("supervised training needs a boundary class and current pen-up confirmation")
  func readinessRequiresTwoClassesAndPenUp() throws {
    var negativeX = PreflightTransaction(sequenceID: .boundaryNegativeX)
    var positiveX = PreflightTransaction(sequenceID: .boundaryPositiveX)
    var penUp = PreflightTransaction(sequenceID: .penUpConfirmation)
    var penDown = PreflightTransaction(sequenceID: .penDownConfirmation)
    try complete(&negativeX)
    try complete(&positiveX)

    let policy = PreflightTrainingReadinessPolicy.supervisedTraining
    var readiness = policy.evaluate(
      transactions: [negativeX, positiveX],
      currentPenState: .up
    )
    #expect(!readiness.isReady)
    #expect(readiness.successfulSequenceIDs.count == 2)
    #expect(readiness.successfulSequenceClasses == [.boundaryMeasurement])
    #expect(readiness.missingRequiredClasses == [.penPositionConfirmation])
    #expect(!readiness.hasSuccessfulPenUpConfirmation)
    #expect(!readiness.hasCurrentPenUpConfirmation)

    try complete(&penDown)
    readiness = policy.evaluate(
      transactions: [negativeX, penDown],
      currentPenState: .up
    )
    #expect(!readiness.isReady)
    #expect(readiness.successfulSequenceClasses.count == 2)
    #expect(readiness.missingRequiredClasses.isEmpty)
    #expect(!readiness.hasSuccessfulPenUpConfirmation)
    #expect(!readiness.hasCurrentPenUpConfirmation)

    try complete(&penUp)
    readiness = policy.evaluate(
      transactions: [negativeX, penDown, penUp],
      currentPenState: .unknown
    )
    #expect(!readiness.isReady)
    #expect(readiness.hasSuccessfulPenUpConfirmation)
    #expect(!readiness.hasCurrentPenUpConfirmation)

    readiness = policy.evaluate(
      transactions: [penUp, penDown, negativeX],
      currentPenState: .up
    )
    #expect(readiness.isReady)
    #expect(readiness.successfulSequenceClasses.count == 2)
    #expect(readiness.missingRequiredClasses.isEmpty)
    #expect(readiness.currentPenState == .up)
    #expect(readiness.hasSuccessfulPenUpConfirmation)
    #expect(readiness.hasCurrentPenUpConfirmation)

    readiness = policy.evaluate(
      transactions: [negativeX, penUp, penDown],
      currentPenState: .down
    )
    #expect(!readiness.isReady)
    #expect(readiness.hasSuccessfulPenUpConfirmation)
    #expect(!readiness.hasCurrentPenUpConfirmation)

    #expect(throws: PreflightReadinessPolicyError.minimumMustBeAtLeastTwo) {
      _ = try PreflightTrainingReadinessPolicy(minimumSuccessfulSequenceClasses: 1)
    }
  }

  @Test("first unique nearest edge association persists for the declared side")
  func posteriorAssociationPersists() throws {
    let configurationID = CameraConfigurationID()
    let prior = try boundaryObservation(
      frameID: FrameID(rawValue: "frame-a"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -2)
    )
    let incoming = try boundaryObservation(
      frameID: FrameID(rawValue: "frame-b"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      estimate: frameEstimate(offset: 20),
      centroid: Point2(x: 5, y: -3)
    )

    let posterior = try DrawingFramePosterior(prior: prior).adding(incoming)

    #expect(posterior.observationCount == 2)
    #expect(posterior.associations[.negativeX]?.candidateEdgeIndex == 0)
    #expect(posterior.sidePosteriors[.negativeX]?.observationCount == 2)
    #expect(posterior.estimate == nil)
    #expect(posterior.latestObservationKey.frameID == FrameID(rawValue: "frame-b"))
    #expect(posterior.observations.map(\.key.frameID.rawValue) == ["frame-a", "frame-b"])
  }

  @Test("ambiguous nearest edge association rejects only the posterior observation")
  func posteriorRejectsAmbiguousAssociation() throws {
    let observation = try boundaryObservation(
      frameID: FrameID(rawValue: "center"),
      cameraConfigurationID: CameraConfigurationID(),
      direction: .negativeX,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: 5),
      associationMargin: 1
    )
    #expect(throws: DrawingFramePosteriorError.self) {
      _ = try DrawingFramePosterior(prior: observation)
    }
  }

  @Test("nonduplicate observations narrow one side and duplicate keys replace")
  func posteriorNarrowsAndDeduplicates() throws {
    let configurationID = CameraConfigurationID()
    let first = try boundaryObservation(
      frameID: FrameID(rawValue: "same-frame"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -2)
    )
    let initial = try DrawingFramePosterior(prior: first)
    let second = try boundaryObservation(
      frameID: FrameID(rawValue: "second-frame"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -2.5)
    )
    var posterior = try initial.adding(second)
    #expect(
      try #require(posterior.sidePosteriors[.negativeX]).offsetVariance
        < #require(initial.sidePosteriors[.negativeX]).offsetVariance)
    let replacement = try boundaryObservation(
      frameID: FrameID(rawValue: "same-frame"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -3)
    )
    posterior = try posterior.adding(replacement)
    #expect(posterior.observationCount == 2)
  }

  @Test("camera reconfiguration invalidates all associations")
  func posteriorCameraInvalidation() throws {
    let firstConfiguration = CameraConfigurationID()
    let secondConfiguration = CameraConfigurationID()
    let first = try boundaryObservation(
      frameID: FrameID(rawValue: "first-camera"),
      cameraConfigurationID: firstConfiguration,
      direction: .negativeX,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -2)
    )
    let reconfigured = try boundaryObservation(
      frameID: FrameID(rawValue: "new-camera-frame"),
      cameraConfigurationID: secondConfiguration,
      direction: .positiveY,
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: -2, y: 5)
    )
    let posterior = try DrawingFramePosterior(prior: first).adding(reconfigured)
    #expect(posterior.cameraConfigurationID == secondConfiguration)
    #expect(posterior.observationCount == 1)
    #expect(posterior.associations[.negativeX] == nil)
    #expect(posterior.associations[.positiveY]?.candidateEdgeIndex == 3)
    #expect(posterior.latestObservationKey.frameID == FrameID(rawValue: "new-camera-frame"))
  }

  @Test("four side lines derive corners while missing sides remain uncertain")
  func posteriorCornersAndMissingSides() throws {
    let configurationID = CameraConfigurationID()
    let inputs: [(PreflightBoundaryDirection, Point2<CameraPixelSpace>)] = [
      (.negativeX, try Point2(x: 5, y: -2)),
      (.positiveX, try Point2(x: 12, y: 5)),
      (.negativeY, try Point2(x: 5, y: 12)),
      (.positiveY, try Point2(x: -2, y: 5)),
    ]
    let observations = try inputs.enumerated().map { index, input in
      try boundaryObservation(
        frameID: FrameID(rawValue: "corner-\(index)"),
        cameraConfigurationID: configurationID,
        direction: input.0,
        estimate: frameEstimate(offset: 0),
        centroid: input.1
      )
    }
    var posterior = try DrawingFramePosterior(prior: observations[0])
    #expect(posterior.estimate == nil)
    #expect(posterior.derivedCorners.isEmpty)
    for observation in observations.dropFirst() { posterior = try posterior.adding(observation) }
    #expect(posterior.sidePosteriors.count == 4)
    #expect(posterior.derivedCorners.count == 4)
    #expect(posterior.estimate?.geometry.points.count == 5)
  }

  @Test("controller MPos is retained provenance and does not constrain image geometry")
  func controllerPositionIsProvenanceOnly() throws {
    let configurationID = CameraConfigurationID()
    let first = try boundaryObservation(
      frameID: FrameID(rawValue: "mpos-a"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      controllerPosition: MachinePosition(x: 0, y: 0),
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -2)
    )
    let changedMPos = try boundaryObservation(
      frameID: FrameID(rawValue: "mpos-b"),
      cameraConfigurationID: configurationID,
      direction: .negativeX,
      controllerPosition: MachinePosition(x: 10_000, y: -20_000),
      estimate: frameEstimate(offset: 0),
      centroid: Point2(x: 5, y: -2)
    )
    let posterior = try DrawingFramePosterior(prior: first).adding(changedMPos)
    #expect(posterior.observations.last?.controllerPosition == changedMPos.controllerPosition)
    #expect(abs(try #require(posterior.sidePosteriors[.negativeX]).offsetPixels + 1.96078431372549) < 1e-9)
  }
}

private func frameEstimate(
  offset: Double,
  confidence: Double = 0.5,
  basis: String = "measured boundary with inferred frame geometry"
) throws -> DrawingFrameEstimate {
  let points: [Point2<CameraPixelSpace>] = [
    try Point2(x: offset, y: offset),
    try Point2(x: offset + 10, y: offset),
    try Point2(x: offset + 10, y: offset + 10),
    try Point2(x: offset, y: offset + 10),
    try Point2(x: offset, y: offset),
  ]
  return DrawingFrameEstimate(
    geometry: try Polyline(points: points),
    confidence: confidence,
    basis: basis
  )
}

private func boundaryObservation(
  frameID: FrameID,
  cameraConfigurationID: CameraConfigurationID,
  direction: PreflightBoundaryDirection,
  controllerPosition: MachinePosition? = nil,
  estimate: DrawingFrameEstimate,
  centroid: Point2<CameraPixelSpace>,
  observationVariance: Double = 4,
  associationMargin: Double = 1,
  broadPriorVariance: Double = 100
) throws -> DrawingFrameBoundaryObservation {
  return try DrawingFrameBoundaryObservation(
    frameID: frameID,
    frameSHA256: "sha-\(frameID.rawValue)",
    captureNanoseconds: UInt64(direction.stableTestIndex + 1),
    cameraConfigurationID: cameraConfigurationID,
    direction: direction,
    controllerPosition: controllerPosition
      ?? (try MachinePosition(x: Double(direction.stableTestIndex), y: 0)),
    observedToolCentroid: centroid,
    estimate: estimate,
    observationVariance: observationVariance,
    associationDistanceMargin: associationMargin,
    broadPriorVariance: broadPriorVariance
  )
}

private extension PreflightBoundaryDirection {
  var stableTestIndex: Int {
    switch self {
    case .negativeX: 0
    case .positiveX: 1
    case .negativeY: 2
    case .positiveY: 3
    }
  }
}

private func complete(_ transaction: inout PreflightTransaction) throws {
  try transaction.begin()
  while let step = transaction.currentStep {
    try transaction.record(try event(for: step.action))
  }
  #expect(transaction.state == .succeeded)
}

private func event(for action: PreflightAction) throws -> PreflightEvent {
  let frameID = FrameID(rawValue: "completion-frame")
  let configurationID = CameraConfigurationID()
  return switch action {
  case .startSpeechListening:
    .speechListeningStarted
  case .stopSpeechListening:
    .speechListeningStopped
  case .speakPrompt:
    .promptSpoken
  case .awaitVoice(let response):
    .exactVoiceResponseAccepted(response)
  case .startBoundaryJog(let direction):
    .boundaryJogStarted(direction, controllerSummary: "jog accepted")
  case .cancelBoundaryJogAndAwaitIdle(let direction):
    .boundaryJogCancelled(
      direction,
      finalPosition: try MachinePosition(x: 1, y: 2),
      controllerSummary: "jog cancelled at Idle"
    )
  case .captureFreshCameraFrame:
    .freshFrameCaptured(frameID, configurationID)
  case .measureBoundary(let direction):
    .boundaryMeasured(
      direction,
      controllerPosition: try MachinePosition(x: 1, y: 2),
      observedToolCentroid: try Point2(x: 5, y: 0),
      frameID: frameID,
      cameraConfigurationID: configurationID,
      confidence: 0.8,
      summary: "measured visible edge"
    )
  case .adjustDrawingFramePosterior(let direction):
    .drawingFramePosteriorAdjusted(
      direction,
      frameID: frameID,
      cameraConfigurationID: configurationID,
      observationCount: 1
    )
  case .actuatePen(let command):
    .penCommandSettled(command, controllerSummary: "pen command settled")
  case .awaitPhysicalPenConfirmation(let state, let response):
    .physicalPenConfirmed(
      state,
      response: response,
      operatorSummary: "operator confirmed physical position"
    )
  }
}
