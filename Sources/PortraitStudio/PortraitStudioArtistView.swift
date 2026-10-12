import PortraitArtists
import PortraitCore
import PortraitStudioUI
import SwiftUI

struct PortraitStudioArtistView: View {
  @Bindable var composition: PortraitStudioComposition
  @State private var artist = "SwiftSketch"
  private var model: PortraitStudioArtistModel { composition.artist }

  var body: some View {
    HSplitView {
      VStack(alignment: .leading, spacing: 12) {
        Picker("Artist", selection: $artist) {
          Text("Flow Edge").tag("Flow Edge")
          Text("Contour").tag("Contour")
          Text("Sketch").tag("Sketch")
          Text("SwiftSketch · experimental").tag("SwiftSketch")
        }
        if artist != "SwiftSketch" {
          Text("This artist uses its own Studio parameters and retained native render path.")
            .font(.caption).foregroundStyle(.secondary)
          Button("Edit in Studio") {
            let style: PortraitStyle = artist == "Flow Edge" ? .flowEdges : (artist == "Contour" ? .contours : .sketch)
            composition.model.selectStyle(style, strokeStyle: composition.strokeStyle)
            composition.workspace = .studio
          }
        } else {
          Text(model.availability.available ? "Local worker available" : "SwiftSketch unavailable").font(.headline)
          Text(model.availability.reason).font(.caption).foregroundStyle(.secondary)
          Button("Check Availability") { Task { await model.refresh() } }.disabled(model.isProcessing)
          Text("Source: \(composition.model.framePosition)").font(.caption)
          Text("Full oriented source · fixed white square pad · no mask · paired seed 42")
            .font(.caption).foregroundStyle(.secondary)
          materialFields
          preprocessingPicker
          groupFields
          HStack {
            Button("Generate SwiftSketch", systemImage: "pencil.and.outline") { Task { await model.generate() } }
              .disabled(model.isProcessing || !model.availability.available || composition.model.selectedPhotoID == nil)
            if model.isProcessing {
              Button("Cancel", role: .cancel) { Task { await model.cancel() } }
              ProgressView().controlSize(.small)
            }
          }
          Text(model.status).font(.caption).foregroundStyle(.secondary)
          if let error = model.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        Divider()
        Text("Retained generation jobs").font(.headline)
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(model.jobs) { job in
              VStack(alignment: .leading) {
                Text("\(job.artist.identifier) · \(job.status?.rawValue ?? "scheduled")")
                Text(job.id.uuidString.prefix(8)).font(.caption.monospaced()).foregroundStyle(.secondary)
                if let reason = job.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
              }
            }
          }
        }
      }.padding().frame(minWidth: 310, idealWidth: 360, maxWidth: 420)
      VStack(alignment: .leading, spacing: 12) {
        if let drawing = model.drawing {
          Text(drawing.title).font(.title2)
          PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource()
            .resolve(program: drawing.program, nominalWidth: drawing.program.strokes.first?.style.nominalLineWidth ?? 0.4))
          HStack {
            Button("View in Library") {
              Task {
                await composition.browser.reload()
                await composition.browser.selectDrawing(drawing.id)
                composition.workspace = .library
              }
            }
            Button("Export Drawing") {
              Task { composition.message = await composition.exportDrawing(drawing) }
            }.disabled(composition.isBusy)
          }
          Text("Exact converted program · reference dimensions · no physical ink qualification")
            .font(.caption).foregroundStyle(.secondary)
        } else {
          ContentUnavailableView("Experimental Artist", systemImage: "pencil.and.outline",
            description: Text("Configure the pinned local worker, select a photo in Studio, then generate one bounded result. Every scheduled job retains its outcome; only valid drawings enter the drawing library."))
        }
      }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }.task { await model.refresh() }
  }

  private var materialFields: some View {
    @Bindable var model = model
    return VStack(alignment: .leading, spacing: 6) {
      TextField("Field width (mm)", value: $model.widthMM, format: .number)
      TextField("Field height (mm)", value: $model.heightMM, format: .number)
      TextField("Nominal pen width (mm)", value: $model.nominalPenWidthMM, format: .number)
    }.textFieldStyle(.roundedBorder).disabled(model.isProcessing)
  }
  private var preprocessingPicker: some View {
    @Bindable var model = model
    return Picker("Preprocessing", selection: $model.preprocessing) {
      Text("Unchanged").tag(SwiftSketchPreprocessing.unchanged)
      Text("Gamma 0.8").tag(SwiftSketchPreprocessing.gamma08)
      Text("Contrast 1.15").tag(SwiftSketchPreprocessing.contrast115)
    }.disabled(model.isProcessing)
  }
  private var groupFields: some View {
    @Bindable var model = model
    return DisclosureGroup("Declare source groups before generation") {
      VStack(alignment: .leading, spacing: 6) {
        TextField("Subject identifier (optional)", text: $model.subjectID)
        TextField("Photographic session identifier (optional)", text: $model.photoSessionID)
        TextField("Declaration provenance", text: $model.groupProvenance)
        Text("Blank identities stay unknown and unassigned. Acquisition UUID is retained separately.")
          .font(.caption).foregroundStyle(.secondary)
      }.textFieldStyle(.roundedBorder).disabled(model.isProcessing)
    }
  }
}
