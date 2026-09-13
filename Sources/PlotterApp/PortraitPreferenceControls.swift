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
  @State private var message: String?
  @State private var exportDocument: PortraitPreferenceDocument?
  @State private var exporting = false
  @State private var preparingExport = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Rate this candidate").font(.caption).bold()
      HStack(spacing: 6) {
        ForEach(1...5, id: \.self) { rating in
          Button("\(rating)") {
            if let error = model.rateSelection(rating) { message = error }
            else { message = "Saved \(rating)/5 for this frame and style." }
          }
          .frame(maxWidth: .infinity)
          .accessibilityLabel("Rate current drawing \(rating) out of 5")
        }
      }.disabled(!model.canRateSelection)
      if !model.canRateSelection && model.sketches.selected != nil {
        Text("Source frame removed; this saved drawing can still be plotted.")
          .font(.caption2).foregroundStyle(.secondary)
      }
      Text("1 = poor likeness / drawing · 5 = keep drawing like this")
        .font(.caption2).foregroundStyle(.secondary)
      if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
      DisclosureGroup("Preference examples · \(model.preferences.examples.count)") {
        VStack(alignment: .leading, spacing: 8) {
          Text("Local examples keep the source photo, recipe, vectors and score for future preference learning. This renderer uses geometry and filters; ratings do not train a GAN. Up to 32 examples / 48 MB this session. Export to retain them.")
            .font(.caption).foregroundStyle(.secondary)
          ForEach(model.preferences.examples) { example in
            HStack {
              PortraitPhotoThumbnail(data: example.photoData, id: example.id)
                .frame(width: 36, height: 40)
              PortraitProgramPreview(program: example.program).frame(width: 40, height: 44)
              Text("\(example.recipe.title) · \(example.rating)/5").font(.caption).lineLimit(2)
              Spacer()
              Button { model.preferences.remove(example.id) } label: {
                Image(systemName: "xmark").frame(width: 24, height: 24)
              }.accessibilityLabel("Remove rated \(example.recipe.title)")
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
