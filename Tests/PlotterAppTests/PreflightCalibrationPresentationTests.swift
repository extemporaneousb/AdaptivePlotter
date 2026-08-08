import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("motion preflight presents questions without calibration language")
func motionPreflightTitle() {
  #expect(PreflightCalibrationPresentation.title == "Motion Preflight")
  #expect(PreflightCalibrationPresentation.subtitle.contains("Questions"))
  #expect(!PreflightCalibrationPresentation.subtitle.localizedCaseInsensitiveContains("calibrate"))
}

@Test("simulator rehearsal presentation remains distinct from physical preflight")
func simulatorRehearsalPresentation() throws {
  var rehearsal = PreflightRehearsal(sequenceID: .penCycleConfirmation)
  #expect(PreflightCalibrationPresentation.phaseLabel(for: rehearsal) == "NOT PRACTICED")
  #expect(
    PreflightCalibrationMode.simulatorRehearsal
      .subtitle(voicePracticeEnabled: false).contains("no microphone")
  )
  #expect(
    PreflightCalibrationMode.simulatorRehearsal
      .subtitle(voicePracticeEnabled: true).contains("microphone")
  )
  try rehearsal.start()
  #expect(PreflightCalibrationPresentation.phaseLabel(for: rehearsal) == "PRACTICING")
  while rehearsal.state == .running { try rehearsal.advance() }
  #expect(PreflightCalibrationPresentation.phaseLabel(for: rehearsal) == "PRACTICED")
}

@Test("runtime catalog maps to the complete operator-facing sequence list")
func preflightCatalogLabels() {
  let definitions = PreflightSequenceCatalog.all

  #expect(definitions.map(\.id) == PreflightSequenceID.allCases)
  #expect(
    definitions.map { PreflightCalibrationPresentation.title(for: $0.id) }
      == ["X− Boundary", "X+ Boundary", "Y− Boundary", "Y+ Boundary", "Pen Cycle"]
  )
  #expect(definitions.allSatisfy { !$0.voiceQuestions.isEmpty })
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
    #expect(
      PreflightCalibrationPresentation.questionSummary(for: definition)
        .contains("[YES / NO]")
    )
    #expect(
      PreflightCalibrationPresentation.questionSummary(for: definition)
        .contains("[YES / NO / STOP]")
    )
    #expect(definition.steps.map(\.participant).contains(.operatorChoice))
    #expect(definition.steps.map(\.participant).contains(.controller))
    #expect(definition.steps.map(\.participant).contains(.camera))
    #expect(definition.steps.map(\.participant).contains(.vision))
    #expect(
      PreflightCalibrationPresentation.actionDescription(definition.steps[0].action)
        .contains("Ask:")
    )
    #expect(
      definition.steps.contains {
        PreflightCalibrationPresentation.eventDescription($0.expectedEvent).contains("MPos")
      }
    )
    #expect(
      PreflightCalibrationPresentation.eventDescription(
        definition.steps[definition.steps.count - 1].expectedEvent
      ).contains("posterior")
    )
    #expect(
      PreflightCalibrationPresentation.expectedEvidenceOutput(for: definition)
        .contains("posterior")
    )
  }
}

@Test("pen timeline asks the complete cycle using only YES or NO answers")
func penTimelineSemantics() {
  let pen = PreflightSequenceCatalog.definition(for: .penCycleConfirmation)

  #expect(
    pen.voiceQuestions.map(\.prompt)
      == [
        "Is the pen currently up?",
        "Are we clear to put it down?",
        "Is the pen currently down?",
        "Is the pen up?",
      ]
  )
  #expect(pen.voiceQuestions.allSatisfy { $0.choiceLabel == "YES / NO" })
  #expect(pen.steps.map(\.participant).contains(.operatorChoice))
  #expect(pen.steps.map(\.participant).contains(.controller))
  #expect(pen.steps.map(\.participant).contains(.camera))
  #expect(
    PreflightCalibrationPresentation.expectedEvidenceOutput(for: pen)
      .contains("physical")
  )
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

  var pen = PreflightTransaction(sequenceID: .penCycleConfirmation)
  try pen.begin()
  for event in successfulPenCycleEvents() {
    try pen.record(event)
  }

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
    .questionPresented,
    .exactVoiceResponseAccepted(.yes),
    .boundaryJogStarted(.negativeX, controllerSummary: "moving"),
    .questionPresented,
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
  ]
}

private func successfulPenCycleEvents() -> [PreflightEvent] {
  let configurationID = CameraConfigurationID()
  return [
    .questionPresented,
    .physicalPenConfirmed(.up, response: .yes, operatorSummary: "initially up"),
    .questionPresented,
    .exactVoiceResponseAccepted(.yes),
    .penCommandSettled(.lower, controllerSummary: "lowered"),
    .questionPresented,
    .physicalPenConfirmed(.down, response: .yes, operatorSummary: "down"),
    .freshFrameCaptured(FrameID(rawValue: "pen-down"), configurationID),
    .penCommandSettled(.raise, controllerSummary: "raised"),
    .questionPresented,
    .physicalPenConfirmed(.up, response: .yes, operatorSummary: "finally up"),
    .freshFrameCaptured(FrameID(rawValue: "pen-up"), configurationID),
  ]
}
