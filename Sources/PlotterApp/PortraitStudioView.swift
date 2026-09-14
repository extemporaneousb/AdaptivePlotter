import PlotterModel
import PlotterRuntime
import SwiftUI
import UniformTypeIdentifiers

struct PortraitStudioView<Gallery: View>: View {
  @Bindable var model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  let previewSource: PortraitPlanePreviewSource
  let showOnPlotter: (PortraitCandidate) async -> String?
  let selectCamera: () async -> String?
  let showPhoto: () -> Void
  private let gallery: Gallery

  init(model: PortraitStudioModel, strokeStyle: PlotterModel.StrokeStyle,
    previewSource: PortraitPlanePreviewSource = .init(),
    showOnPlotter: @escaping (PortraitCandidate) async -> String?,
    selectCamera: @escaping () async -> String? = { nil },
    showPhoto: @escaping () -> Void = {}, @ViewBuilder gallery: () -> Gallery) {
    self.model = model
    self.strokeStyle = strokeStyle
    self.previewSource = previewSource
    self.showOnPlotter = showOnPlotter
    self.selectCamera = selectCamera
    self.showPhoto = showPhoto
    self.gallery = gallery()
  }
  @State private var importing = false
  @State private var submissionError: String?
  @State private var isSubmitting = false

  private var displayedProgram: DrawingProgram? { model.selectedCandidate?.program }
  private var materialContext: PortraitMaterialContext? { model.selectedCandidate?.recipe.vectorOptions.materialContext }
  private var planePreview: PortraitPlanePreview {
    previewSource.resolve(program: displayedProgram, nominalWidth: strokeStyle.nominalLineWidth)
  }
  private var needsMaterialReadaptation: Bool {
    guard displayedProgram != nil else { return false }
    guard let materialContext else { return planePreview.materialProfile != nil }
    if let height = planePreview.actualDrawingHeightMM {
      return !materialContext.matches(drawingHeightMM: height,
        profileKey: planePreview.materialProfile?.key)
    }
    return materialContext.profile.key != planePreview.materialProfile?.key
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 10) {
        if model.recentPhotos.isEmpty || model.isCapturing {
          sourcePanel
        } else {
          DisclosureGroup("Capture or import another photo") { sourcePanel.padding(.top, 6) }
        }
        PortraitPhotoStrip(model: model, strokeStyle: strokeStyle)
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.source")
      Divider()
      VStack(alignment: .leading, spacing: 8) {
        if model.sketches.selected == nil {
          PortraitStyleBrowser(model: model, strokeStyle: strokeStyle)
        } else {
          Text("Inspecting a retained drawing").font(.caption).foregroundStyle(.secondary)
          Button("Return to Current Edit") { model.sketches.selectedID = nil }
        }
        PortraitExplorationControls(model: model)
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.exploration")
      VStack(alignment: .leading, spacing: 8) {
        if model.sketches.selected == nil {
          DisclosureGroup("Adjust this style") { PortraitRenderControls(model: model) }
        }
        PortraitPlaneProgramPreview(preview: planePreview)
          .aspectRatio(planePreview.aspectRatio, contentMode: .fit)
          .overlay { if model.isProcessing && model.sketches.selected == nil { ProgressView() } }
        Text(planePreview.statusText)
          .font(.caption).foregroundStyle(.secondary)
          .accessibilityIdentifier("portrait.preview.status")
        Text(planePreview.dimensionsText)
          .font(.caption).textSelection(.enabled)
          .accessibilityIdentifier("portrait.preview.dimensions")
        DisclosureGroup("Marker preview") {
          VStack(alignment: .leading, spacing: 8) {
            Text(planePreview.inkDescription)
              .font(.caption).foregroundStyle(.secondary)
              .accessibilityIdentifier("portrait.preview.ink")
            if let profile = planePreview.materialProfile {
              Text("Active material: \(profile.name), revision \(profile.revision).")
                .font(.caption).foregroundStyle(.secondary)
              materialLimits(profile, title: "Material measurement limits")
            }
            if let materialContext {
              Text("Detail spacing adapted with \(materialContext.profile.name), revision \(materialContext.profile.revision).")
                .font(.caption).foregroundStyle(.secondary)
              if materialContext.profile.key != planePreview.materialProfile?.key {
                materialLimits(materialContext.profile, title: "Prior adaptation measurement limits")
              }
            }
            if needsMaterialReadaptation {
              Text(planePreview.actualDrawingHeightMM == nil
                ? "Project this drawing to check material adaptation at its actual size."
                : "The selected material or actual drawing height differs from this candidate’s material adaptation. Apply the material at the current drawing height to update detail spacing.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("portrait.preview.readapt")
            }
          }
        }
        Text(model.sketches.selected.map { "Retained: \($0.title)" } ?? model.summary)
          .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.preview")
      VStack(alignment: .leading, spacing: 8) {
        if model.sketches.selected == nil {
          Button("Keep Sketch") { submissionError = model.keepSelection() }
            .disabled(model.currentProgram == nil || model.isProcessing)
            .accessibilityIdentifier("portrait.keepSketch")
        }
        PortraitPreferenceControls(model: model, presentation: planePreview.presentationContext)
        PortraitArchiveStatus(collection: model.sketches)
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.ratings")
      VStack(alignment: .leading, spacing: 10) {
        PortraitSketchStrip(collection: model.sketches, scope: model.selectedStyleScope)
        gallery
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.gallery")
      VStack(alignment: .leading, spacing: 8) {
        PortraitTrainingControls(model: model)
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.training")
      VStack(alignment: .leading, spacing: 8) {
        if let error = submissionError {
          Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
        }
        Button("Show on Plotter Video") {
          guard let candidate = model.selectedCandidate else { return }
          WorkbenchRequestTelemetry.nativeActionHandled("portrait.showOnPlotter")
          isSubmitting = true
          submissionError = nil
          Task {
            submissionError = await showOnPlotter(candidate)
            isSubmitting = false
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(displayedProgram == nil || (model.isProcessing && model.sketches.selected == nil) || isSubmitting)
        .accessibilityIdentifier("portrait.showOnPlotter")
        .accessibilityValue(isSubmitting ? "Preparing plotter preview" : submissionError ?? "Ready")
        if isSubmitting { ProgressView("Preparing plotter preview").controlSize(.small) }
      }.accessibilityElement(children: .contain).accessibilityIdentifier("portrait.section.projection")
    }
    .onChange(of: model.selectedPhotoID) { _, selected in
      if selected != nil {
        model.sketches.selectedID = nil
        showPhoto()
      }
    }
    .onAppear { model.configureRecipes(strokeStyle: strokeStyle) }
    .task { await model.loadArchive() }
    .onChange(of: model.renderConfiguration) { _, _ in
      model.renderIfConfigurationChanged(strokeStyle: strokeStyle)
    }
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

  @ViewBuilder
  private func materialLimits(_ profile: DrawingMaterialProfileRevision, title: String) -> some View {
    if !profile.measurementLimitations.isEmpty {
      DisclosureGroup(title) {
        ForEach(Array(profile.measurementLimitations.enumerated()), id: \.offset) { _, limit in
          Text(limit).font(.caption2).foregroundStyle(.secondary)
        }
      }
    }
  }

  private func render() {
    model.renderIfNeeded(strokeStyle: strokeStyle)
  }

  private var sourcePanel: some View {
    VStack(alignment: .leading, spacing: 10) {
      PortraitAdaptiveRow {
        Picker("Camera", selection: $model.selectedDeviceID) {
          Text("Choose camera").tag(Optional<CameraDeviceID>.none)
          ForEach(model.devices) { Text($0.name).tag(Optional($0.id)) }
        }.labelsHidden().disabled(model.cameraIsStarting)
        Button("Use Camera") {
          Task { submissionError = await selectCamera() }
        }.disabled(model.cameraIsStarting || model.selectedDeviceID == nil)
      }
      PortraitAdaptiveRow {
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

extension PortraitStudioView where Gallery == EmptyView {
  init(model: PortraitStudioModel, strokeStyle: PlotterModel.StrokeStyle,
    previewSource: PortraitPlanePreviewSource = .init(),
    showOnPlotter: @escaping (PortraitCandidate) async -> String?,
    selectCamera: @escaping () async -> String? = { nil }, showPhoto: @escaping () -> Void = {}) {
    self.init(model: model, strokeStyle: strokeStyle, previewSource: previewSource,
      showOnPlotter: showOnPlotter,
      selectCamera: selectCamera, showPhoto: showPhoto) { EmptyView() }
  }
}

/// Preserve native controls and their shortcuts while moving whole actions onto
/// separate rows when their intrinsic widths exceed the available panel width.
struct PortraitAdaptiveRow<Content: View>: View {
  private let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 8) { content }.fixedSize(horizontal: true, vertical: false)
      VStack(alignment: .leading, spacing: 8) { content }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

/// Preview and label presentation share one resolution of explicit overrides.
/// A width override is a visual estimate, even when its source material carries
/// independently measured evidence.
enum PortraitPreviewPresentation {
  static func context(material: PortraitMaterialContext?, nominalWidthMM: Double,
    widthOverrideMM: Double? = nil, heightOverrideMM: Double? = nil) -> PortraitPresentationContext? {
    try? PortraitPresentationContext(
      drawingHeightMM: heightOverrideMM ?? material?.drawingHeightMM ?? 100,
      inkWidthMM: widthOverrideMM ?? material?.profile.conservativeWidthMM ?? nominalWidthMM,
      inkWidthIsMeasured: widthOverrideMM == nil && material?.profile.independentlyMeasured == true,
      materialRevision: material?.profile.key, objective: .screenAesthetic,
      prompt: "Rate likeness and drawing quality as displayed")
  }
}
