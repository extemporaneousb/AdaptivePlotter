import PlotterEpisodeRuntime
import PlotterUI
import SwiftUI

struct WorkbenchVoiceView: View {
  let context: WorkbenchVoiceContext?
  let controller: WorkbenchVoiceController

  init(context: WorkbenchVoiceContext?, controller: WorkbenchVoiceController) {
    self.context = context
    self.controller = controller
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Toggle(isOn: Binding(get: { controller.isEnabled }, set: { controller.setEnabled($0) })) {
          Label("Voice", systemImage: controller.isListening ? "mic.fill" : "mic")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .help("Turn spoken cues and microphone input on or off together. Say only the currently offered replies. Uses Apple Speech; on-device recognition when available.")
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
          .disabled(!controller.canRepeatPrompt)
          .help("Repeat prompt / retry Voice")
          .accessibilityLabel("Repeat prompt or retry Voice")
        }
      }
      if controller.isEnabled {
        if let context, !context.commands.isEmpty {
          Text(context.responseHint)
            .font(.caption.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
        }
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
  }
}
