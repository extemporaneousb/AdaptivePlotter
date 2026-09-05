import PlotterEpisodeRuntime
import PlotterUI
import SwiftUI

struct WorkbenchVoiceView: View {
  let context: WorkbenchVoiceContext?
  @State private var controller: WorkbenchVoiceController

  init(
    context: WorkbenchVoiceContext?,
    speech: PlotterSpeechEffectRuntime,
    sink: any PlotterUIIntentSink
  ) {
    self.context = context
    _controller = State(initialValue: WorkbenchVoiceController(speech: speech) { request in
      await sink.submitPlotterUIRequest(request)
    })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Toggle(isOn: Binding(get: { controller.isEnabled }, set: { controller.setEnabled($0) })) {
          Label("Voice", systemImage: controller.isListening ? "mic.fill" : "mic")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help("Read the current prompt and listen for answers such as yes, no, move, or stop. Uses Apple Speech; on-device recognition when available.")
        if controller.isEnabled {
          Text(controller.status)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          Button { controller.repeatPrompt() } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .help("Repeat prompt / retry Voice")
          .accessibilityLabel("Repeat prompt or retry Voice")
        }
      }
      if controller.isEnabled {
        if controller.isListening {
          ProgressView(value: Double(controller.inputLevel))
            .progressViewStyle(.linear)
            .accessibilityLabel("Microphone input level")
        }
        if !controller.transcript.isEmpty {
          Text("“\(controller.transcript)”")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        }
      }
    }
    .onChange(of: context, initial: true) { _, value in controller.update(value) }
    .onDisappear { controller.stop() }
  }
}
