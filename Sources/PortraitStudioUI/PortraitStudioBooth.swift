import AppKit
import SwiftUI
import PortraitArtists
import PortraitCore
import PlotterRuntime

/// A still is immutable; draft region gestures invalidate send immediately and
/// only Apply commits analysis. Live video never drives drawing generation.
package struct PortraitStudioBooth: View {
  @Bindable package var model: FlowAuthoringModel
  @Bindable package var camera: PortraitStudioModel
  package var showsSource = true
  package var showsCaptureLight = true
  package var openDrawing: () -> Void
  package var photoSelected: (PhotoRef) -> Void
  @State private var image: NSImage?
  @State private var draft: PortraitNormalizedRegion?
  @State private var dirty = false
  @State private var draftEpoch: UInt64 = 0
  @State private var applying = false
  @State private var selectionOnly = false
  @State private var live = false
  @State private var cameraTask: Task<Void, Never>?
  package init(model: FlowAuthoringModel, camera: PortraitStudioModel, showsSource: Bool = true, showsCaptureLight: Bool = true, photoSelected: @escaping (PhotoRef) -> Void = { _ in }, openDrawing: @escaping () -> Void) {
    self.model = model; self.camera = camera; self.openDrawing = openDrawing; self.photoSelected = photoSelected; self.showsSource = showsSource; self.showsCaptureLight = showsCaptureLight
  }
  package var body: some View {
    HSplitView {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text(live ? "Live camera" : (showsSource ? model.selectedSource.map(model.photoName) : nil) ?? "Choose a photo").font(.title2.weight(.semibold))
          Spacer()
          Button(live ? "Use still photo" : "Live preview") {
            live.toggle()
            if !live { stopCamera() }
          }.accessibilityIdentifier("portraitStudio.livePreview")
        }
        if live { liveCamera }
        else if showsSource, let image {
          PortraitPhotoRegionView(image: image, region: $draft, selectionOnly: selectionOnly) {
            markDraftChanged()
          }.frame(maxWidth: .infinity, maxHeight: .infinity)
          Picker("Photo view", selection: $selectionOnly) { Text("Whole photo").tag(false); Text("Selection").tag(true) }
            .pickerStyle(.segmented).frame(maxWidth: 260)
          HStack {
            Button("Auto face") { draft = nil; markDraftChanged() }
            Button("Whole photo") { draft = .init(x: 0, y: 0, width: 1, height: 1); markDraftChanged() }
            Spacer(minLength: 4)
            Button("Apply region") { Task { await applyRegion() } }.buttonStyle(.borderedProminent)
              .disabled(!dirty || applying || model.needsRecovery)
              .accessibilityIdentifier("portraitStudio.applyRegion")
          }
          Text("Drag to select a region. Move it from inside; resize from a corner. Apply once to update the drawing.")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ContentUnavailableView("Choose your source", systemImage: "photo", description: Text("Open a photo from Photos, use File → Import Photo, or choose Live preview and a camera."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }.padding(16).frame(minWidth: 430, idealWidth: 650, maxWidth: .infinity, maxHeight: .infinity)
      VStack(alignment: .leading, spacing: 12) {
        Text(showsSource && model.isRecommendationPredictedFavorite ? "Predicted favorite" : "Suggested drawing").font(.title2.weight(.semibold))
        Text(showsSource && model.isRecommendationPredictedFavorite ? "Selected from this set by your active preference checkpoint." : "An initial drawing for this photo and region. Explore to find the direction you prefer.")
          .font(.callout).foregroundStyle(.secondary)
        if !showsSource { ContentUnavailableView("Choose a photo", systemImage: "photo", description: Text("Open a photo from Photos, import an original, or capture one.")) }
        else if dirty { ContentUnavailableView("Apply your region", systemImage: "crop", description: Text("The previous suggestion is no longer current.")) }
        else if let candidate = model.recommendationCandidate {
          Button {
            openDrawing()
            Task { await model.exploreRecommendation() }
          } label: {
            VStack(spacing: 10) {
              FlowAuthoringImage(data: model.previews[candidate.id], identity: model.previewIdentity(candidate: candidate))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
              Text("Explore this drawing").font(.headline)
            }.contentShape(Rectangle())
          }.buttonStyle(.plain).disabled(model.isBusy || model.needsRecovery)
            .accessibilityIdentifier("portraitStudio.suggestion")
            .help("Open broad Drawing exploration. Automatic recommendation records no preference.")
        } else if model.isBusy { VStack { ProgressView(); Text("Preparing the drawing…").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
        else {
          ContentUnavailableView("No drawing yet", systemImage: "pencil.and.outline", description: Text(model.recommendationError ?? model.error ?? "Select a photo to prepare its suggestion."))
          if model.selectedSource != nil { Button("Retry suggestion") { Task { await model.ensureRecommendation() } } }
        }
        if model.needsRecovery { Button("Recover autosave") { Task { await model.recoverAutosave() } } }
      }.padding(16).frame(minWidth: 350, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
    }
    .task(id: showsSource ? model.currentPhotoRef?.digest.description : nil) {
      draftEpoch &+= 1; applying = false
      dirty = false; draft = model.committedAnalysisOptions.manualRegion; image = nil
      let ref = model.currentPhotoRef
      guard showsSource else { return }
      if let data = model.sourceData, let source = model.selectedSource {
        let decoded = await FlowPresentationImageCache.shared.load(data: data, identity: source.image.sha256)
        guard !Task.isCancelled, model.currentPhotoRef == ref else { return }
        image = decoded
      }
      await model.ensureRecommendation()
    }
    .onDisappear { if dirty { model.discardRegionPreview() }; stopCamera() }
    .background {
      if showsCaptureLight { PortraitScreenIllumination(isActive: camera.screenIlluminationActive) { Task { await camera.cancelRendering() } } }
    }
  }
  private var liveCamera: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker("Camera", selection: $camera.selectedDeviceID) {
        Text("Choose camera").tag(Optional<CameraDeviceID>.none)
        ForEach(camera.devices) { Text($0.name).tag(Optional($0.id)) }
      }.disabled(camera.isCapturing || camera.cameraIsStarting)
        .onChange(of: camera.selectedDeviceID) { _, _ in stopCamera() }
      PortraitCameraPreview(model: camera.preview).environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black.opacity(0.9))
      Text(camera.capturePhase ?? camera.cameraStatus ?? (camera.devices.isEmpty ? "No camera is available. Refresh cameras or import a photo from File." : "Choose a camera explicitly, then start the preview."))
        .font(.callout).foregroundStyle(.secondary)
      HStack {
        Button("Refresh cameras") { Task { await camera.discover(excluding: nil) } }
          .disabled(camera.isCapturing || camera.cameraIsStarting)
        Button(camera.cameraIsRunning ? "Restart preview" : "Start preview") {
          cameraTask = Task { await camera.stopCamera(); guard !Task.isCancelled else { return }; await camera.startCamera() }
        }.disabled(camera.selectedDeviceID == nil || camera.isCapturing || camera.cameraIsStarting)
          .accessibilityIdentifier("portraitStudio.startPreview")
        Spacer()
        Button(camera.isCapturing ? "Cancel capture" : "Capture photo") {
          if camera.isCapturing { Task { await camera.cancelRendering() }; return }
          cameraTask = Task {
            if let photo = await camera.captureForPortfolio(strokeStyle: model.strokeStyle) {
              guard !Task.isCancelled else { return }
              await model.addCapturedPhoto(photo, title: model.nextPhotoTitle(capturedAt: photo.capturedAt))
              if let ref = model.currentPhotoRef, model.error == nil { photoSelected(ref) }
              await model.ensureRecommendation()
            }
          }
        }.buttonStyle(.borderedProminent).disabled(!camera.isCapturing && !camera.cameraIsRunning)
          .accessibilityIdentifier("portraitStudio.capture")
      }
    }.task { await camera.discover(excluding: nil) }
  }
  private func stopCamera() {
    cameraTask?.cancel(); cameraTask = nil
    Task { await camera.cancelRendering(); await camera.stopCamera() }
  }
  private func markDraftChanged() {
    draftEpoch &+= 1
    if !dirty || applying { model.invalidateRegionPreview() }
    dirty = true; applying = false
  }
  private func applyRegion() async {
    let epoch = draftEpoch, source = model.currentPhotoRef, committedDraft = draft
    applying = true
    await model.commitRegion(committedDraft)
    guard epoch == draftEpoch, model.currentPhotoRef == source else { return }
    applying = false
    guard !model.needsRecovery, !model.regionPreviewPending else { return }
    dirty = false; draft = model.committedAnalysisOptions.manualRegion
    await model.ensureRecommendation()
  }
}
