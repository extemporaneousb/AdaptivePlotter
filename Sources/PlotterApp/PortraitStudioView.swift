import PlotterModel
import PlotterRuntime
import SwiftUI
import UniformTypeIdentifiers

/// One portrait canvas, with secondary source and history browsers.
struct PortraitStudioView: View {
  @Bindable var model: PortraitStudioModel
  let strokeStyle: PlotterModel.StrokeStyle
  var previewSource = PortraitPlanePreviewSource()
  let showOnPlotter: (PortraitCandidate) async -> String?
  var selectCamera: () async -> String? = { nil }
  var openReviewer: () -> Void = {}

  @State private var savingStyle = false
  @State private var styleName = ""
  @State private var importing = false
  @State private var cameraSettings = false
  @State private var showsSource = false
  @State private var showsHistory = false
  @State var showsAdjustments = false
  @State private var submissionError: String?
  @State private var submissionErrorTitle = "Studio action failed"
  @State private var isSubmitting = false
  @State private var isStartingCapture = false

  private var candidate: PortraitCandidate? { model.selectedCandidate }
  private var previewCandidate: PortraitCandidate? {
    candidate ?? (model.isProcessing && model.completedCandidate?.photoID == model.selectedPhotoID
      ? model.completedCandidate : nil)
  }
  private var planePreview: PortraitPlanePreview {
    previewSource.resolve(program: previewCandidate?.program, nominalWidth: strokeStyle.nominalLineWidth)
  }

  private var displayedError: (title: String, detail: String)? {
    if let submissionError { return (submissionErrorTitle, submissionError) }
    if let error = model.authoringError { return ("Photo processing failed", error) }
    if let error = model.cameraStatus { return ("Camera needs attention", error) }
    return nil
  }

  var body: some View {
    let preview = planePreview
    VStack(spacing: 10) {
      toolbar
      Divider()
      browserControls
      HStack(alignment: .top, spacing: 16) {
        VStack(spacing: 8) {
          drawingPreviewFrame(preview) {
            PortraitPlaneProgramPreview(preview: preview)
              .overlay(alignment: .topTrailing) {
                if model.isProcessing || model.isExploring {
                  ProgressView().controlSize(.small).padding(8)
                }
              }
          }
          if let candidate {
            HStack {
              PortraitAttemptFeedbackButtons(model: model, candidate: candidate)
              Text(model.burdenSummary(for: candidate)).font(.caption).foregroundStyle(.secondary)
              Spacer()
              Text(model.singlePortraitStatus ?? candidate.recipe.title)
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                .help(model.singlePortraitStatus ?? candidate.recipe.title)
            }
          }
        }
        if showsAdjustments {
          VStack(alignment: .leading, spacing: 12) {
            ScrollView {
              PortraitRenderControls(model: model)
                .disabled(model.selectedPhoto == nil || model.isCapturing)
                .padding(.trailing, 4)
            }
            .accessibilityIdentifier("portrait.adjustmentScroll")
            Divider()
            penAndMaterial(preview)
          }
          .frame(width: 284)
          .frame(maxHeight: .infinity, alignment: .top)
          .accessibilityIdentifier("portrait.adjustmentInspector")
        }
      }
      if let candidate, let treatment = PortraitRegionalTreatment.summary(raster: candidate.raster, options: candidate.recipe.vectorOptions) {
        Text(treatment).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityIdentifier("portrait.regionalStatus")
      }
      if let error = displayedError {
        HStack {
          Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
          Text(error.title).font(.caption)
          StudioHelpButton(error.title, text: error.detail)
          Spacer(minLength: 0)
        }
        .accessibilityIdentifier("portrait.error")
      }
      if case .failed(let reason) = model.sketches.persistenceState {
        HStack {
          Text("Studio history save failed").font(.caption).foregroundStyle(.orange)
          StudioHelpButton("Studio history save failed", text: reason)
          Button("Retry Save") { model.sketches.retryPersistence() }
            .accessibilityIdentifier("portrait.retryArchiveSave")
          Spacer()
        }.controlSize(.small)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.workspace")
    .onAppear {
      model.renderIfNeeded(strokeStyle: strokeStyle)
      model.setExplorationEnabled(false, strokeStyle: strokeStyle)
    }
    .onDisappear {
      model.setExplorationEnabled(false, strokeStyle: strokeStyle)
    }
    .task { await model.loadArchive() }
    .onChange(of: model.renderConfiguration) { _, _ in
      model.renderIfConfigurationChanged(strokeStyle: strokeStyle)
    }
    .onChange(of: strokeStyle) { _, _ in
      model.renderIfNeeded(strokeStyle: strokeStyle)
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.image]) { result in
      switch result {
      case .success(let url): Task { await model.importPhoto(url, strokeStyle: strokeStyle) }
      case .failure(let error):
        submissionErrorTitle = "Photo import failed"
        submissionError = error.localizedDescription
      }
    }
  }

  private var toolbar: some View {
    PortraitAdaptiveRow {
      Button {
        if model.isCapturing {
          Task { await model.cancelRendering() }
        } else {
          isStartingCapture = true
          submissionErrorTitle = "Camera capture failed"
          submissionError = nil
          Task {
            defer { isStartingCapture = false }
            submissionError = await selectCamera()
            guard submissionError == nil, model.cameraIsRunning else { return }
            await model.capture(strokeStyle: strokeStyle)
          }
        }
      } label: {
        Label(model.isCapturing ? "Cancel Capture" : "Capture Photo",
          systemImage: model.isCapturing ? "stop.fill" : "camera.fill")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!model.isCapturing && (isStartingCapture || model.cameraIsStarting || model.selectedDeviceID == nil))
      .keyboardShortcut(model.isCapturing ? .escape : KeyEquivalent("k"), modifiers: model.isCapturing ? [] : [.command, .shift])
      .accessibilityLabel(model.isCapturing ? "Cancel Capture" : "Capture Photo")
      .accessibilityIdentifier(model.isCapturing ? "portrait.cancelCapture" : "portrait.capture")
      .help(model.isCapturing ? "Cancel Capture" : "Keep still while a photo is selected from a short capture")
      Button { importing = true } label: { Image(systemName: "photo.badge.plus") }
        .accessibilityLabel("Choose Photo")
        .accessibilityIdentifier("portrait.choosePhoto")
        .help("Choose Photo")
      Button { cameraSettings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
        .accessibilityLabel("Camera settings")
        .help("Camera settings")
        .popover(isPresented: $cameraSettings, arrowEdge: .bottom) { cameraSettingsPanel }
      StudioHelpButton("Portrait Studio", text: "Capture or import a photo, then work with one portrait. Contour opens direct controls. Explorer varies the current drawing one step at a time; Next requests a new result only when no forward result is retained. Back and Forward restore exact results without rendering. History lists attempts for the current photo. Plus keeps an attempt promising; minus rejects that exact treatment. Save Imagination retains the result in Drawing Reviewer. Send to Drawing places it in Drawing; Draw there starts execution.")
      if model.isCapturing {
        Text("Keep still").font(.caption).foregroundStyle(.secondary)
        ProgressView(value: model.captureProgress).frame(width: 60)
          .accessibilityLabel("Portrait capture progress")
      } else if isStartingCapture || model.cameraIsStarting {
        ProgressView().controlSize(.small)
      }
      Spacer(minLength: 8)
      Button(role: .destructive) {
        if let id = model.selectedPhotoID { model.removePhoto(id, strokeStyle: strokeStyle) }
      } label: { Image(systemName: "trash") }
      .disabled(!model.canRemoveSelectedRecentPhoto)
      .accessibilityLabel("Delete Photo")
      .accessibilityIdentifier("portrait.deletePhoto")
      .help("Delete Photo")
      Button("Send to Drawing") {
        guard let candidate else { return }
        WorkbenchRequestTelemetry.nativeActionHandled("portrait.showOnPlotter")
        isSubmitting = true
        submissionErrorTitle = "Drawing projection failed"
        submissionError = nil
        Task {
          submissionError = await showOnPlotter(candidate)
          isSubmitting = false
        }
      }
      .disabled(candidate == nil || model.isProcessing || model.isCapturing || isStartingCapture || isSubmitting)
      .accessibilityIdentifier("portrait.showOnPlotter")
      Divider().frame(height: 20)
      Button("Save Style") {
        styleName = candidate?.recipe.title ?? "My style"
        savingStyle = true
      }
      .disabled(candidate == nil || model.isProcessing || model.isCapturing)
      .accessibilityIdentifier("portrait.saveStyle")
      .popover(isPresented: $savingStyle) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Save reusable recipe").font(.headline)
          TextField("Style name", text: $styleName)
          Button("Save Style") { model.saveStyle(name: styleName); savingStyle = false }
            .disabled(styleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.padding(12).frame(width: 260)
      }
      Button("Save Imagination") {
        submissionErrorTitle = "Imagination save failed"
        submissionError = model.keepSelection()
      }
        .disabled(candidate == nil || model.isProcessing || model.isCapturing || isStartingCapture)
        .accessibilityIdentifier("portrait.keepSketch")
      Button(action: openReviewer) { Image(systemName: "square.grid.2x2") }
        .accessibilityLabel("Drawing Reviewer")
        .accessibilityIdentifier("portrait.openReviewer")
        .help("Drawing Reviewer")
    }
    .controlSize(.regular)
    .frame(minHeight: 32)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.toolbar")
  }

  private var browserControls: some View {
    PortraitAdaptiveRow {
      Picker("Mode", selection: Binding(
        get: { model.studioMode },
        set: { mode in
          model.selectStudioMode(mode, strokeStyle: strokeStyle)
          showsAdjustments = mode == .contour
        })) {
        Text("Contour").tag(PortraitStudioMode.contour)
        Text("Explorer").tag(PortraitStudioMode.explorer)
      }
      .pickerStyle(.segmented).labelsHidden().frame(width: 180)
      .accessibilityIdentifier("portrait.mode")
      if model.studioMode == .explorer {
        Button { model.previousPortrait() } label: { Label("Back", systemImage: "chevron.left") }
          .disabled(!model.canGoBackExploration || model.isCapturing || model.isProcessing)
          .keyboardShortcut(.leftArrow, modifiers: [.command])
          .accessibilityIdentifier("portrait.exploration.back")
        Button { model.nextPortrait(strokeStyle: strokeStyle) } label: {
          Label(model.canGoForwardPortrait ? "Forward" : "Next", systemImage: "chevron.right")
        }
        .disabled(candidate == nil || model.isExploring || model.isCapturing || model.isProcessing)
        .keyboardShortcut(.rightArrow, modifiers: [.command])
        .accessibilityIdentifier("portrait.exploration.next")
        if model.isExploring {
          Button("Cancel") { model.cancelPortraitStep() }
            .accessibilityIdentifier("portrait.exploration.cancel")
        }
        Picker("Explore region", selection: $model.explorationRegion) {
          Text("Whole portrait").tag(Optional<PortraitTreatmentRegion>.none)
          ForEach(PortraitTreatmentRegion.allCases) { Text($0.rawValue).tag(Optional($0)) }
        }.labelsHidden().frame(maxWidth: 150)
          .disabled(model.isExploring)
          .accessibilityIdentifier("portrait.exploration.region")
      }
      Spacer(minLength: 0)
      Button("Photos", systemImage: "photo") { showsSource.toggle() }
        .accessibilityIdentifier("portrait.sourceToggle")
        .popover(isPresented: $showsSource, arrowEdge: .bottom) {
          VStack(alignment: .leading, spacing: 8) {
            sourcePreview.frame(width: 330, height: 360)
            PortraitPhotoStrip(model: model, strokeStyle: strokeStyle).frame(width: 330)
          }.padding(12).accessibilityIdentifier("portrait.sourceFrame")
        }
      Button("History", systemImage: "clock") { showsHistory.toggle() }
        .accessibilityIdentifier("portrait.historyToggle")
        .popover(isPresented: $showsHistory, arrowEdge: .bottom) {
          PortraitHistoryView(model: model, strokeStyle: strokeStyle) { showsHistory = false }
            .padding(12).frame(width: 380, height: 400)
        }
      if !model.sketches.savedStyles.isEmpty {
        Menu("Saved styles") {
          ForEach(model.sketches.savedStyles) { saved in
            Button(saved.name) { model.applySavedStyle(saved, strokeStyle: strokeStyle) }
          }
          Divider()
          Menu("Delete saved style") {
            ForEach(model.sketches.savedStyles) { saved in
              Button(saved.name, role: .destructive) { model.sketches.removeStyle(saved.id) }
            }
          }
        }
      }
    }.controlSize(.small)
      .accessibilityIdentifier("portrait.browserControls")
  }

  private var cameraSettingsPanel: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Camera").font(.headline)
      Picker("Camera", selection: $model.selectedDeviceID) {
        Text("Choose camera").tag(Optional<CameraDeviceID>.none)
        ForEach(model.devices) { Text($0.name).tag(Optional($0.id)) }
      }.labelsHidden().disabled(model.cameraIsStarting || model.isCapturing)
    }.padding(16).frame(width: 300)
  }

  @ViewBuilder private var sourcePreview: some View {
    if let candidate {
      PortraitPhotoThumbnail(data: candidate.sourceData, id: candidate.photoID, maximumPixelSize: 1024)
        .id(candidate.photoID)
        .accessibilityLabel("Source photo for selected drawing")
    } else if let photo = model.selectedPhoto, let photoID = model.selectedPhotoID {
      PortraitPhotoThumbnail(data: photo, id: photoID, maximumPixelSize: 1024)
        .id(photoID)
        .accessibilityLabel("Selected portrait photo")
    } else {
      PortraitCameraPreview(model: model.preview)
    }
  }

  private func drawingPreviewFrame<Content: View>(_ preview: PortraitPlanePreview, @ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 5) {
      HStack {
        Text("Portrait").font(.headline)
        Spacer()
        Toggle(isOn: $showsAdjustments) {
          Label("Adjustments", systemImage: "slider.horizontal.3")
        }
        .toggleStyle(.button)
        .controlSize(.small)
        .accessibilityIdentifier("portrait.adjustmentsDisclosure")
        .help(showsAdjustments ? "Hide framing and algorithm adjustments" : "Show framing and algorithm adjustments")
        Text(model.isProcessing ? "Updating" : preview.evidence?.mode == .planned ? "Placed" : "Reference")
          .font(.caption).foregroundStyle(.secondary)
        StudioHelpButton("Drawing preview", text: preview.statusText + "\n\n" + preview.dimensionsText + "\n\n" + model.browserTimingSummary)
      }
      content()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(.quaternary) }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.drawingFrame")
  }

  private func penAndMaterial(_ preview: PortraitPlanePreview) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("Pen & Material").font(.headline)
        Spacer()
        StudioHelpButton("Pen & Material", text: preview.inkDescription
          + "\n\nPen width is a calibration or material setting, not a style parameter. The preview uses the available width. Change drawing detail using the style controls. Material selection, measurement and adaptation at the placed size are in Drawing.")
      }
      HStack {
        Text("\(preview.inkWidthMM, specifier: "%.2f") mm").monospacedDigit()
        Text(preview.inkWidthIsMeasured ? "Measured" : "Estimated").foregroundStyle(.secondary)
        Spacer()
      }.font(.caption)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("portrait.penMaterial")
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

/// Live frames are observed only by the preview leaf, never by editing controls.
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
        ContentUnavailableView("Portrait Camera", systemImage: "person.crop.rectangle")
      }
    }.clipped()
  }
}
