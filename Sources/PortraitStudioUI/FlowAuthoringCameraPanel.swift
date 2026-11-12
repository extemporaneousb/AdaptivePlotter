import PortraitArtists
import PlotterModel
import PlotterRuntime
import SwiftUI

/// User-opened acquisition surface. The existing camera owner remains the only
/// session owner; rendering and portfolio navigation never start a camera.
package struct FlowAuthoringCameraPanel: View {
  @Bindable var camera: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  let selectCamera: () async -> String?
  let captured: (PortraitPhoto) async -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var busy = false
  @State private var issue: String?
  @State private var captureTask: Task<Void, Never>?

  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("New portrait photo").font(.title2.weight(.semibold))
      Picker("Camera", selection: $camera.selectedDeviceID) {
        Text("Choose camera").tag(Optional<CameraDeviceID>.none)
        ForEach(camera.devices) { Text($0.name).tag(Optional($0.id)) }
      }.disabled(busy || camera.isCapturing)
        .onChange(of: camera.selectedDeviceID) { _, _ in Task { await start() } }
      PortraitCameraPreview(model: camera.preview)
        .environment(\.colorScheme, .dark)
        .frame(width: 580, height: 330)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("flowAuthoring.cameraPreview")
      if let phase = camera.capturePhase {
        HStack { ProgressView().controlSize(.small); Text(phase) }
      } else if camera.cameraIsStarting || busy {
        Text("Starting portrait camera…").foregroundStyle(.secondary)
      } else {
        Text("Frame your face in the preview. Capture waits for fresh video before the short exposure.")
          .font(.callout).foregroundStyle(.secondary)
      }
      if let error = issue ?? camera.cameraStatus {
        Text(error).font(.callout).foregroundStyle(.orange).textSelection(.enabled)
      }
      HStack {
        Button("Restart Camera") { Task { await camera.stopCamera(); await start() } }
          .disabled(busy || camera.isCapturing || camera.selectedDeviceID == nil)
        Spacer()
        Button("Close") { Task { await camera.cancelRendering(); dismiss() } }.disabled(busy && !camera.isCapturing)
        Button(camera.isCapturing ? "Cancel Capture" : "Capture Photo") {
          if camera.isCapturing { Task { await camera.cancelRendering() }; return }
          captureTask = Task {
            busy = true; issue = nil
            defer { busy = false; captureTask = nil }
            if let error = await selectCamera() { issue = error; return }
            guard camera.cameraIsRunning else { issue = "Choose a camera and use Restart Camera to start its preview."; return }
            if let photo = await camera.captureForPortfolio(strokeStyle: strokeStyle) {
              await captured(photo)
              dismiss()
            } else { issue = camera.cameraStatus }
          }
        }.buttonStyle(.borderedProminent)
          .disabled(!camera.isCapturing && (busy || camera.selectedDeviceID == nil))
          .accessibilityIdentifier("flowAuthoring.capturePhoto")
      }
    }.padding(20).frame(width: 620)
      .interactiveDismissDisabled(busy || camera.isCapturing)
      .task { await start() }
      .onDisappear {
        if let ownedCapture = captureTask {
          ownedCapture.cancel()
          Task { await camera.cancelRendering() }
        }
      }
  }

  private func start() async {
    guard !busy, !camera.isCapturing else { return }
    busy = true; issue = nil
    defer { busy = false }
    issue = await selectCamera()
  }
}
