import PlotterRuntime
import Testing

@testable import PlotterApp

@Test("speech movement test presents the complete explicit activation path")
func speechMovementTestActivationCopy() {
  #expect(SpeechMovementTestPresentation.title == "SPEECH MOVEMENT TEST")
  #expect(SpeechMovementTestPresentation.cameraSteps.count == 5)
  #expect(SpeechMovementTestPresentation.cameraSteps[0].contains("PLOTTER CONNECTED"))
  #expect(SpeechMovementTestPresentation.cameraSteps[1].contains("Typed Limits"))
  #expect(SpeechMovementTestPresentation.cameraSteps[1].contains("PEN UP"))
  #expect(SpeechMovementTestPresentation.cameraSteps[2].contains("Speech On"))
  #expect(SpeechMovementTestPresentation.cameraSteps[3].contains("Start X−"))
  #expect(SpeechMovementTestPresentation.cameraSteps[4].contains("READY"))
  #expect(SpeechMovementTestPresentation.cameraSteps[4].contains("STOP"))
}

@Test("speech movement test keeps direction selection explicit")
func speechMovementTestDirectionLabels() {
  #expect(
    JogDirection.allCases.map(SpeechMovementTestPresentation.startButtonLabel(for:))
      == ["Start X− Test", "Start X+ Test", "Start Y− Test", "Start Y+ Test"]
  )
}
