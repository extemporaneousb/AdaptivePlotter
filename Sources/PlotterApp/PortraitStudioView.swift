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
  @State private var previewInkWidth: Double?
  @State private var previewHeight = 100.0

  private var displayedProgram: DrawingProgram? { model.sketches.selected?.program ?? model.currentProgram }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.recentPhotos.isEmpty || model.isCapturing {
        sourcePanel
      } else {
        DisclosureGroup("Capture or import another photo") { sourcePanel.padding(.top, 6) }
      }
      PortraitPhotoStrip(model: model, strokeStyle: strokeStyle)
      Divider()
      if model.sketches.selected == nil {
        PortraitStyleBrowser(model: model, strokeStyle: strokeStyle)
        DisclosureGroup("Adjust this style") { PortraitRenderControls(model: model) }
      } else {
        Button("Return to Current Edit") { model.sketches.selectedID = nil }
      }
      PortraitProgramPreview(program: displayedProgram,
        inkWidth: previewInkWidth ?? strokeStyle.nominalLineWidth, drawingHeight: previewHeight)
        .frame(minHeight: 220, idealHeight: 300)
        .overlay { if model.isProcessing && model.sketches.selected == nil { ProgressView() } }
      DisclosureGroup("Marker preview") {
        VStack(alignment: .leading, spacing: 8) {
          PortraitAdjustmentSlider("Marker width", value: Binding(
            get: { previewInkWidth ?? strokeStyle.nominalLineWidth }, set: { previewInkWidth = $0 }),
            range: 0.2...5, step: 0.1, unit: "mm")
          PortraitAdjustmentSlider("Drawing height", value: $previewHeight,
            range: 50...250, step: 5, unit: "mm")
          Text("Ink estimate at this size. Set actual size with Fit to Drawing Area on the plotter video.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      Text(model.sketches.selected.map { "Saved \($0.title)" } ?? model.summary)
        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      if model.sketches.selected == nil {
        Button("Keep Sketch") {
          guard let program = model.currentProgram else { return }
          submissionError = model.sketches.keep(program, title: "\(model.currentRecipe.title) · \(program.strokes.count) strokes",
            photoID: model.selectedPhotoID, recipe: model.currentRecipe)
        }
        .disabled(model.currentProgram == nil || model.isProcessing)
        .accessibilityIdentifier("portrait.keepSketch")
      }
      PortraitPreferenceControls(model: model)
      PortraitSketchStrip(collection: model.sketches)
      if let error = submissionError {
        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
      }
      Button("Show on Plotter Video") {
        guard let program = displayedProgram else { return }
        WorkbenchRequestTelemetry.nativeActionHandled("portrait.showOnPlotter")
        isSubmitting = true
        submissionError = nil
        Task {
          submissionError = await showOnPlotter(program)
          isSubmitting = false
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(displayedProgram == nil || (model.isProcessing && model.sketches.selected == nil) || isSubmitting)
      .accessibilityIdentifier("portrait.showOnPlotter")
      .accessibilityValue(isSubmitting ? "Preparing plotter preview" : submissionError ?? "Ready")
      if isSubmitting { ProgressView("Preparing plotter preview").controlSize(.small) }
    }
    .onChange(of: model.selectedPhotoID) { _, selected in
      model.sketches.selectedID = nil
      if selected != nil { showPhoto() }
    }
    .onAppear { model.configureRecipes(strokeStyle: strokeStyle) }
    .onChange(of: model.renderConfiguration) { _, _ in render() }
    .onChange(of: strokeStyle) { _, _ in
      model.configureRecipes(strokeStyle: strokeStyle)
      render()
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
      switch result {
      case .success(let url): Task { await model.importPhoto(url, strokeStyle: strokeStyle) }
      case .failure(let error): submissionError = error.localizedDescription
      }
    }
  }

  private func render() {
    model.sketches.selectedID = nil
    model.renderIfNeeded(strokeStyle: strokeStyle)
  }

  private var sourcePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
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
        if model.isCapturing {
          Button("Cancel Capture") { Task { await model.cancelRendering() } }
            .accessibilityIdentifier("portrait.cancelCapture")
        } else {
          Button("Capture Burst") { Task { await model.capture(strokeStyle: strokeStyle) } }
            .disabled(!model.cameraIsRunning)
            .accessibilityIdentifier("portrait.capture")
        }
        Picker("Duration", selection: $model.captureDuration) {
          ForEach([3.0, 4.0, 5.0], id: \.self) { Text("\(Int($0)) seconds").tag($0) }
        }.labelsHidden().frame(maxWidth: 110)
      }
      Button("Choose Photo…") { importing = true }
        .accessibilityIdentifier("portrait.choosePhoto")
      if model.isCapturing {
        ProgressView(value: model.captureProgress).accessibilityLabel("Portrait capture progress")
      }
      if let captureSummary = model.captureSummary {
        Text(captureSummary).font(.caption).foregroundStyle(.secondary)
      }
      Text("Turn slowly for several angles. The display turns white during capture; choose an angle below. For more light, raise display brightness before capturing.")
        .font(.caption).foregroundStyle(.secondary)
      Button("Show Photo", action: showPhoto).disabled(model.selectedPhoto == nil)
      if let status = model.cameraStatus {
        Text(status).font(.caption).foregroundStyle(.orange)
      }
    }
  }
}

/// Only the permanent canvas mounts this leaf. The controls do not observe frames.
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
  var inkWidth: Double?
  var drawingHeight: Double = 100
  var body: some View {
    Canvas { context, size in
      guard let program else { return }
      let scale = max(0, min((size.width-24)/program.fieldExtent.width,
                            (size.height-24)/program.fieldExtent.height))
      let origin = CGPoint(x: (size.width-program.fieldExtent.width*scale)/2,
                           y: (size.height-program.fieldExtent.height*scale)/2)
      for stroke in program.strokes {
        var path = Path()
        for (index, point) in stroke.path.points.enumerated() {
          let location = CGPoint(x: origin.x+point.x*scale,
                                 y: origin.y+(program.fieldExtent.height-point.y)*scale)
          if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        let width = (inkWidth ?? stroke.style.nominalLineWidth) * scale
          * program.fieldExtent.height / max(1, drawingHeight)
        context.stroke(path, with: .color(.black),
          style: SwiftUI.StrokeStyle(lineWidth: max(0.2, width), lineCap: .round, lineJoin: .round))
      }
    }
    .background(.white)
    .border(.quaternary)
    .accessibilityLabel("Portrait drawing preview")
  }
}
