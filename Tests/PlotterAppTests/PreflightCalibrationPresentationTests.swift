import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("motion preflight owns the compact calibration title")
func motionPreflightTitle() {
  #expect(PreflightCalibrationPresentation.title == "Motion Preflight")
  #expect(PreflightCalibrationPresentation.subtitle.contains("Calibrate Plotter"))
}

@Test("simulator rehearsal presentation remains distinct from physical preflight")
func simulatorRehearsalPresentation() throws {
  var rehearsal = PreflightRehearsal(sequenceID: .penUpConfirmation)
  #expect(PreflightCalibrationPresentation.phaseLabel(for: rehearsal) == "NOT REHEARSED")
  #expect(PreflightCalibrationMode.simulatorRehearsal.subtitle.contains("no microphone"))
  try rehearsal.start()
  #expect(PreflightCalibrationPresentation.phaseLabel(for: rehearsal) == "REHEARSING")
  while rehearsal.state == .running { try rehearsal.advance() }
  #expect(PreflightCalibrationPresentation.phaseLabel(for: rehearsal) == "REHEARSED")
}

@Test("runtime catalog maps to the complete operator-facing sequence list")
func preflightCatalogLabels() {
  let definitions = PreflightSequenceCatalog.all

  #expect(definitions.map(\.id) == PreflightSequenceID.allCases)
  #expect(
    definitions.map { PreflightCalibrationPresentation.title(for: $0.id) }
      == ["X− Boundary", "X+ Boundary", "Y− Boundary", "Y+ Boundary", "Pen Up", "Pen Down"]
  )
  #expect(definitions.allSatisfy { !$0.voiceResponses.isEmpty })
  #expect(
    definitions.allSatisfy {
      !PreflightCalibrationPresentation.expectedEvidenceOutput(for: $0).isEmpty
    }
  )
}

@Test("boundary timelines expose listening voice motion vision and posterior events")
func boundaryTimelineSemantics() {
  let definitions = PreflightSequenceCatalog.all.filter {
    $0.sequenceClass == .boundaryMeasurement
  }

  for definition in definitions {
    #expect(definition.steps.first?.action == .startSpeechListening)
    #expect(definition.steps.last?.action == .stopSpeechListening)
    #expect(
      PreflightCalibrationPresentation.requiredVoicePhrase(for: definition)
        == "READY → STOP"
    )
    #expect(definition.steps.map(\.participant).contains(.operatorVoice))
    #expect(definition.steps.map(\.participant).contains(.controller))
    #expect(definition.steps.map(\.participant).contains(.camera))
    #expect(definition.steps.map(\.participant).contains(.vision))
    #expect(
      PreflightCalibrationPresentation.actionDescription(definition.steps[0].action)
        == "Start speech listening for this sequence."
    )
    #expect(
      definition.steps.contains {
        PreflightCalibrationPresentation.eventDescription($0.expectedEvent).contains("MPos")
      }
    )
    #expect(
      PreflightCalibrationPresentation.eventDescription(
        definition.steps[definition.steps.count - 2].expectedEvent
      ).contains("posterior")
    )
    #expect(
      PreflightCalibrationPresentation.expectedEvidenceOutput(for: definition)
        .contains("posterior")
    )
  }
}

@Test("pen timelines require exact physical confirmation")
func penTimelineSemantics() {
  let penUp = PreflightSequenceCatalog.definition(for: .penUpConfirmation)
  let penDown = PreflightSequenceCatalog.definition(for: .penDownConfirmation)

  #expect(
    PreflightCalibrationPresentation.requiredVoicePhrase(for: penUp)
      == "PEN IS PHYSICALLY UP"
  )
  #expect(
    PreflightCalibrationPresentation.requiredVoicePhrase(for: penDown)
      == "PEN IS PHYSICALLY DOWN"
  )

  for definition in [penUp, penDown] {
    #expect(definition.steps.first?.action == .startSpeechListening)
    #expect(definition.steps.last?.action == .stopSpeechListening)
    #expect(definition.steps.map(\.participant).contains(.operatorVoice))
    #expect(definition.steps.map(\.participant).contains(.controller))
    #expect(definition.steps.map(\.participant).contains(.camera))
    #expect(
      PreflightCalibrationPresentation.actionDescription(definition.steps[0].action)
        == "Start speech listening for this sequence."
    )
    #expect(
      definition.steps.contains {
        PreflightCalibrationPresentation.actionDescription($0.action)
          .contains(PreflightCalibrationPresentation.requiredVoicePhrase(for: definition))
      }
    )
    #expect(
      PreflightCalibrationPresentation.expectedEvidenceOutput(for: definition)
        .contains("physical")
    )
  }
}

@Test("supervised readiness requires successful boundary and pen sequence classes")
func preflightReadinessProgress() throws {
  var boundary = PreflightTransaction(sequenceID: .boundaryNegativeX)
  try boundary.begin()
  for event in try successfulBoundaryEvents() {
    try boundary.record(event)
  }

  let policy = PreflightTrainingReadinessPolicy.supervisedTraining
  var readiness = policy.evaluate(
    transactions: [boundary],
    currentPenState: .up
  )
  #expect(!readiness.isReady)
  #expect(readiness.successfulSequenceIDs == [.boundaryNegativeX])
  #expect(readiness.missingRequiredClasses == [.penPositionConfirmation])

  var pen = PreflightTransaction(sequenceID: .penUpConfirmation)
  try pen.begin()
  try pen.record(.speechListeningStarted)
  try pen.record(.promptSpoken)
  try pen.record(.penCommandSettled(.raise, controllerSummary: "settled"))
  try pen.record(
    .physicalPenConfirmed(
      .up,
      response: .penIsPhysicallyUp,
      operatorSummary: "observed clear"
    )
  )
  try pen.record(
    .freshFrameCaptured(
      FrameID(rawValue: "pen-frame"),
      CameraConfigurationID()
    )
  )
  try pen.record(.speechListeningStopped)

  readiness = policy.evaluate(
    transactions: [boundary, pen],
    currentPenState: .unknown
  )
  #expect(!readiness.isReady)
  #expect(readiness.hasSuccessfulPenUpConfirmation)
  #expect(!readiness.hasCurrentPenUpConfirmation)

  readiness = policy.evaluate(
    transactions: [pen, boundary],
    currentPenState: .up
  )
  #expect(readiness.isReady)
  #expect(readiness.successfulSequenceClasses == [.boundaryMeasurement, .penPositionConfirmation])
  #expect(readiness.missingRequiredClasses.isEmpty)
  #expect(PreflightCalibrationPresentation.phaseLabel(for: boundary) == "COMPLETE")
  #expect(PreflightCalibrationPresentation.phaseLabel(for: pen) == "COMPLETE")
}

private func successfulBoundaryEvents() throws -> [PreflightEvent] {
  let frameID = FrameID(rawValue: "boundary-frame")
  let configurationID = CameraConfigurationID()
  let finalPosition = try MachinePosition(x: -120, y: 0)
  return [
    .speechListeningStarted,
    .promptSpoken,
    .exactVoiceResponseAccepted(.ready),
    .boundaryJogStarted(.negativeX, controllerSummary: "moving"),
    .exactVoiceResponseAccepted(.stop),
    .boundaryJogCancelled(
      .negativeX,
      finalPosition: finalPosition,
      controllerSummary: "cancelled at Idle"
    ),
    .freshFrameCaptured(frameID, configurationID),
    .boundaryMeasured(
      .negativeX,
      controllerPosition: finalPosition,
      observedToolCentroid: try Point2(x: 4, y: 5),
      frameID: frameID,
      cameraConfigurationID: configurationID,
      confidence: 0.95,
      summary: "left edge"
    ),
    .drawingFramePosteriorAdjusted(
      .negativeX,
      frameID: frameID,
      cameraConfigurationID: configurationID,
      observationCount: 1
    ),
    .speechListeningStopped,
  ]
}
