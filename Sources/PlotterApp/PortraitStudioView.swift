import PlotterModel
import PlotterRuntime
import SwiftUI
import UniformTypeIdentifiers

struct PortraitStudioView: View {
  @Bindable var model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  let showOnPlotter: (DrawingProgram) async -> String?
  var selectCamera: () async -> String? = { nil }
  var showPhoto: () -> Void = {}
  @State private var importing = false
  @State private var submissionError: String?
  @State private var isSubmitting = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) {
          sourcePanel.frame(minWidth: 240)
          drawingPanel.frame(minWidth: 260)
        }
        VStack(alignment: .leading, spacing: 16) {
          sourcePanel
          drawingPanel
        }
      }
      if let error = submissionError {
        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
      }
      Button("Show on Plotter Video") {
        guard let program = model.program else { return }
        WorkbenchRequestTelemetry.nativeActionHandled("portrait.showOnPlotter")
        isSubmitting = true
        submissionError = nil
        Task {
          submissionError = await showOnPlotter(program)
          isSubmitting = false
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(model.program == nil || model.isProcessing || isSubmitting)
      .accessibilityIdentifier("portrait.showOnPlotter")
      .accessibilityValue(isSubmitting ? "Preparing plotter preview" : submissionError ?? "Ready")
      if isSubmitting { ProgressView("Preparing plotter preview").controlSize(.small) }
    }
    .onChange(of: model.photos[model.pose]) { _, photo in if photo != nil { showPhoto() } }
    .onChange(of: model.pose) { _, _ in model.render(strokeStyle: strokeStyle) }
    .onChange(of: model.style) { _, _ in model.render(strokeStyle: strokeStyle) }
    .onChange(of: model.options) { _, _ in model.analysisOptionsChanged(strokeStyle: strokeStyle) }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
      switch result {
      case .success(let url): Task { await model.importPhoto(url, strokeStyle: strokeStyle) }
      case .failure(let error): submissionError = error.localizedDescription
      }
    }
  }

  private var sourcePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("View", selection: $model.pose) {
        ForEach(PortraitPose.allCases) { pose in
          Text(pose.rawValue + (model.photos[pose] == nil ? "" : " ✓")).tag(pose)
        }
      }.pickerStyle(.segmented)
      HStack {
        Picker("Camera", selection: $model.selectedDeviceID) {
          Text("Choose camera").tag(Optional<CameraDeviceID>.none)
          ForEach(model.devices) { Text($0.name).tag(Optional($0.id)) }
        }.labelsHidden().disabled(model.cameraIsStarting)
        Button("Use Camera") {
          Task { submissionError = await selectCamera() }
        }.disabled(model.cameraIsStarting || model.selectedDeviceID == nil)
      }
      HStack {
        Button("Capture") { Task { await model.capture(strokeStyle: strokeStyle) } }
          .disabled(!model.cameraIsRunning)
          .accessibilityIdentifier("portrait.capture")
        Button("Choose Photo…") { importing = true }
          .accessibilityIdentifier("portrait.choosePhoto")
      }
      Button("Show Photo", action: showPhoto).disabled(model.photos[model.pose] == nil)
      Toggle("Crop to face", isOn: $model.options.cropToFace)
      Toggle("Remove background", isOn: $model.options.removeBackground)
      if let status = model.cameraStatus {
        Text(status).font(.caption).foregroundStyle(.orange)
      }
    }
  }

  private var drawingPanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Style", selection: Binding(get: { model.style }, set: {
        WorkbenchRequestTelemetry.nativeActionHandled("portrait.style")
        model.style = $0
      })) {
        ForEach(PortraitStyle.allCases) { Text($0.rawValue).tag($0) }
      }
      .accessibilityIdentifier("portrait.style")
      PortraitProgramPreview(program: model.program)
        .frame(minHeight: 190, idealHeight: 250)
        .overlay { if model.isProcessing { ProgressView() } }
      Text(model.summary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
    }
  }
}

/// Only the permanent canvas mounts this leaf. The portrait controls never
/// observe advancing camera frames and cannot start or stop capture themselves.
struct PortraitCameraPreview: View {
  let model: PortraitCameraPreviewModel
  var zoom: Double = 0
  @StateObject private var cache = FramePresentationImageCache()
  var body: some View {
    GeometryReader { proxy in
      if let displayed = model.frame, let image = cache.image(from: displayed.frame),
        let transform = CameraPixelToViewTransform(frameWidth: displayed.frame.width,
          frameHeight: displayed.frame.height, viewWidth: proxy.size.width, viewHeight: proxy.size.height) {
        CameraFrameLayerView(image: image, imageRect: transform.imageRect).scaleEffect(1 + zoom * 3)
      } else {
        ContentUnavailableView("Portrait Camera", systemImage: "person.crop.rectangle",
          description: Text("Choose a camera in Portrait Studio or import a photo."))
      }
    }.clipped()
  }
}

struct PortraitProgramPreview: View {
  let program: DrawingProgram?
  var body: some View {
    PortraitStrokeShape(program: program)
      .stroke(.primary, lineWidth: 0.7)
      .background(.background)
      .border(.quaternary)
      .accessibilityLabel("Portrait drawing preview")
  }
}

private struct PortraitStrokeShape: Shape {
  let program: DrawingProgram?
  func path(in rect: CGRect) -> Path {
    guard let program else { return Path() }
    let scale = min((rect.width-24)/program.fieldExtent.width, (rect.height-24)/program.fieldExtent.height)
    let origin = CGPoint(x: rect.minX+(rect.width-program.fieldExtent.width*scale)/2,
                         y: rect.minY+(rect.height-program.fieldExtent.height*scale)/2)
    var path = Path()
    for stroke in program.strokes {
      for (index, point) in stroke.path.points.enumerated() {
        let location = CGPoint(x: origin.x+point.x*scale,
                               y: origin.y+(program.fieldExtent.height-point.y)*scale)
        if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
      }
    }
    return path
  }
}
