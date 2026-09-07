import PlotterModel
import PlotterRuntime
import SwiftUI
import UniformTypeIdentifiers

struct PortraitStudioView: View {
  @Bindable var model: PortraitStudioModel
  let plotterCameraID: CameraDeviceID?
  let strokeStyle: PlotterModel.StrokeStyle
  let useProgram: (DrawingProgram) async -> String?
  @Environment(\.dismiss) private var dismiss
  @State private var importing = false
  @State private var submissionError: String?
  @State private var isSubmitting = false

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Portrait").font(.title2.bold())
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      HStack(alignment: .top, spacing: 20) {
        sourcePanel
        drawingPanel
      }
    }
    .padding(20)
    .frame(width: 760, height: 610)
    .task { await model.discover(excluding: plotterCameraID) }
    .onChange(of: model.pose) { _, _ in model.render(strokeStyle: strokeStyle) }
    .onChange(of: model.style) { _, _ in model.render(strokeStyle: strokeStyle) }
    .onChange(of: model.options) { _, _ in model.analysisOptionsChanged(strokeStyle: strokeStyle) }
    .onChange(of: plotterCameraID) { _, _ in
      Task {
        if model.selectedDeviceID == plotterCameraID { await model.stopCamera() }
        await model.discover(excluding: plotterCameraID)
      }
    }
    .onDisappear { Task { await model.stopCamera() } }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
      switch result {
      case .success(let url): Task { await model.importPhoto(url, strokeStyle: strokeStyle) }
      case .failure(let error): submissionError = error.localizedDescription
      }
    }
  }

  private var sourcePanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("View", selection: $model.pose) {
        ForEach(PortraitPose.allCases) { pose in
          Text(pose.rawValue + (model.photos[pose] == nil ? "" : " ✓")).tag(pose)
        }
      }.pickerStyle(.segmented)
      Group {
        if !model.cameraIsRunning, let data = model.photos[model.pose] {
          PortraitPhotoPreview(data: data)
        } else {
          PortraitCameraPreview(model: model.preview)
        }
      }
      .frame(height: 180)
      HStack {
        Picker("Camera", selection: $model.selectedDeviceID) {
          Text("Choose camera").tag(Optional<CameraDeviceID>.none)
          ForEach(model.devices) { device in
            Text(device.name).tag(Optional(device.id))
          }
        }.labelsHidden().disabled(model.cameraIsRunning || model.cameraIsStarting)
        Button(model.cameraIsRunning ? "Stop Camera" : "Start Camera") {
          Task {
            if model.cameraIsRunning { await model.stopCamera() }
            else { await model.startCamera() }
          }
        }.disabled(model.cameraIsStarting || (!model.cameraIsRunning && model.selectedDeviceID == nil))
      }
      HStack {
        Button("Capture \(model.pose.rawValue)") {
          Task { await model.capture(strokeStyle: strokeStyle) }
        }.disabled(!model.cameraIsRunning)
        Button("Choose Photo…") { importing = true }
      }
      if let status = model.cameraStatus {
        Text(status).font(.caption).foregroundStyle(.secondary)
      }
      if model.cameraIsRunning, let data = model.photos[model.pose] {
        PortraitPhotoPreview(data: data).frame(height: 90)
      }
      Toggle("Crop to face", isOn: $model.options.cropToFace)
      Toggle("Remove background", isOn: $model.options.removeBackground)
      Text("Left, front, and right are separate captures. Select a view to compare its drawing styles.")
        .font(.caption).foregroundStyle(.secondary)
    }.frame(width: 300)
  }

  private var drawingPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Picker("Style", selection: $model.style) {
        ForEach(PortraitStyle.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented)
      PortraitProgramPreview(program: model.program)
        .frame(minHeight: 280)
        .overlay { if model.isProcessing { ProgressView() } }
      Text(model.summary).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      if let submissionError { Text(submissionError).font(.caption).foregroundStyle(.red) }
      HStack {
        Spacer()
        Button("Use Portrait") {
          guard let program = model.program else { return }
          isSubmitting = true
          Task {
            submissionError = await useProgram(program)
            isSubmitting = false
            if submissionError == nil { dismiss() }
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.program == nil || model.isProcessing || isSubmitting)
      }
    }.frame(minWidth: 360)
  }

}

/// Only this child reads camera frames; preview delivery never enters the
/// application projection, Learning, Drawing Draft, or the vectorizer.
private struct PortraitCameraPreview: View {
  let model: PortraitCameraPreviewModel
  @StateObject private var cache = FramePresentationImageCache()
  var body: some View {
    ZStack {
      Rectangle().fill(.quaternary)
      if let frame = model.frame, let image = cache.image(from: frame.frame) {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        ContentUnavailableView("Portrait Camera", systemImage: "person.crop.rectangle",
                               description: Text("Start a camera or choose a photo."))
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

private struct PortraitPhotoPreview: View {
  let data: Data
  @State private var image: CGImage?
  var body: some View {
    HStack {
      if let image { Image(decorative: image, scale: 1).resizable().scaledToFit() }
      Text("Captured photo").font(.caption).foregroundStyle(.secondary)
    }
    .task(id: data) {
      image = try? await Task.detached { try PortraitImageAnalyzer.image(from: data) }.value
    }
  }
}
