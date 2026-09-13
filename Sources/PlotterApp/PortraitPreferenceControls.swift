import SwiftUI
import UniformTypeIdentifiers

struct PortraitPreferenceDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  let data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    data = configuration.file.regularFileContents ?? Data()
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }
}

struct PortraitPreferenceControls: View {
  let model: PortraitStudioModel
  let presentation: PortraitPresentationContext?
  @State private var message: String?
  @State private var exportDocument: PortraitPreferenceDocument?
  @State private var exporting = false
  @State private var preparingExport = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Rate this candidate · \(model.selectedStyleScope.name)").font(.caption).bold()
      Text("Screen appearance · scope revision \(model.selectedStyleScope.revision)")
        .font(.caption2).foregroundStyle(.secondary)
      HStack(spacing: 6) {
        ForEach(1...5, id: \.self) { rating in
          Button("\(rating)") {
            guard let presentation else {
              message = "The displayed size or ink width is invalid."
              return
            }
            if let error = model.rateSelection(rating, presentation: presentation) { message = error }
            else { message = "Recorded \(rating)/5 for this exact drawing and preview. Archive status is below." }
          }
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Rate current drawing \(rating) out of 5")
        }
      }.disabled(!model.canRateSelection || presentation == nil)
      Text("1 = poor likeness / drawing · 5 = keep drawing like this. Every score retains the candidate.")
        .font(.caption2).foregroundStyle(.secondary)
      if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
      DisclosureGroup("Preference examples · \(model.preferences.examples.count)") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Ratings retain the exact source, analysis, drawing and displayed size / estimated ink width automatically. Revisions preserve earlier scores. Withdrawing a label excludes it from future fitting; the retained candidate remains. Export is an additional copy.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(model.preferences.examples) { example in
            HStack {
              PortraitPhotoThumbnail(data: example.photoData, id: example.id)
                .frame(width: 36, height: 40)
              PortraitProgramPreview(program: example.program,
                inkWidth: example.label.presentation.inkWidthMM,
                drawingHeight: example.label.presentation.drawingHeightMM).frame(width: 40, height: 44)
              VStack(alignment: .leading, spacing: 2) {
                Text("\(example.recipe.title) · \(example.rating)/5").lineLimit(2)
                Text("\(example.label.scope.name) · revision \(example.label.scope.revision)")
                Text("\(example.label.presentation.drawingHeightMM, specifier: "%.0f") mm high · \(example.label.presentation.inkWidthMM, specifier: "%.2f") mm ink \(example.label.presentation.inkWidthIsMeasured ? "measured" : "estimated")")
                if example.label.previousRevisionID != nil { Text("Revised score; earlier label retained") }
              }.font(.caption2)
              Spacer()
              Button { model.preferences.remove(example.id) } label: {
                Image(systemName: "xmark").frame(width: 24, height: 24)
              }.accessibilityLabel("Withdraw \(example.rating) out of 5 label for \(example.recipe.title)")
            }
          }
          Button(preparingExport ? "Preparing export…" : "Export Ratings…") {
            let examples = model.preferences.examples
            preparingExport = true
            Task {
              do {
                let data = try await Task.detached(priority: .userInitiated) {
                  try PortraitPreferenceCollection.exportData(examples: examples)
                }.value
                exportDocument = PortraitPreferenceDocument(data: data)
                exporting = true
              } catch { message = error.localizedDescription }
              preparingExport = false
            }
          }.disabled(model.preferences.examples.isEmpty || preparingExport)
        }.padding(.top, 6)
      }
    }
    .onChange(of: model.sketches.selectedID) { _, _ in message = nil }
    .onChange(of: model.selectedPhotoID) { _, _ in message = nil }
    .onChange(of: model.renderConfiguration) { _, _ in message = nil }
    .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
      defaultFilename: "portrait-preferences") { result in
      switch result {
      case .success: message = "Ratings exported with source photos and drawings."
      case .failure(let error): message = error.localizedDescription
      }
      exportDocument = nil
    }
  }
}


struct PortraitArchiveStatus: View {
  let collection: PortraitSketchCollection

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      switch collection.persistenceState {
      case .loading:
        ProgressView("Loading retained drawings…").controlSize(.small)
      case .pending:
        Text("Saving archive · \(collection.unresolvedMutations) pending changes")
      case .saved:
        Text("Archive saved")
      case .failed(let reason):
        Text("Archive save unavailable: \(reason)").foregroundStyle(.orange)
        Text("Current work remains in memory · \(collection.unresolvedMutations) unresolved changes")
        Button("Retry Archive Save") { collection.retryPersistence() }
          .accessibilityIdentifier("portrait.retryArchiveSave")
      }
      Text("\(collection.entries.count) retained drawings · \(ByteCountFormatter.string(fromByteCount: Int64(collection.retainedBytes), countStyle: .file)) owned assets")
      if !collection.persistenceIssues.isEmpty {
        DisclosureGroup("Archive recovery details") {
          ForEach(Array(collection.persistenceIssues.enumerated()), id: \.offset) { item in
            Text(item.element).textSelection(.enabled)
          }
        }
      }
    }
    .font(.caption).foregroundStyle(.secondary)
    .textSelection(.enabled)
    .accessibilityIdentifier("portrait.archiveStatus")
  }
}
