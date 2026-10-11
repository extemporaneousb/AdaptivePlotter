import Foundation
import PlotterModel
import PlotterRuntime
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import SwiftUI
import UniformTypeIdentifiers

/// File exchange is authoring/inspection only. Placement continues through the
/// existing Drawing handoff; terminal export reads the raw evidence owner.
struct DrawingTransferView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  @State private var selectedID: DrawingTransferSelection?
  @State private var selectedDrawing: SavedDrawing?
  @State private var importing = false
  @State private var exporting = false
  @State private var document: DrawingTransferDocument?
  @State private var exportName = "drawing.package.json"
  @State private var busy = false
  @State private var failure: String?
  @State private var operationTask: Task<Void, Never>?
  @State private var operationRevision: UInt64 = 0
  private var library: PortraitSketchCollection { application.portraitStudio.sketches }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Drawing Exchange").font(.title2)
        Spacer()
        Button("Import Drawing", systemImage: "square.and.arrow.down") { importing = true }.disabled(busy)
        Button("Close") { cancelWork(); close() }.keyboardShortcut(.cancelAction)
      }
      Text("Retain exact authored drawings and return original plot results to Portrait Studio.")
        .foregroundStyle(.secondary)
      HSplitView {
        List(selection: $selectedID) {
          ForEach(library.drawingSummaries.map(DrawingTransferRow.init)) { row in
            VStack(alignment: .leading) {
              Text(row.summary.title)
              Text(row.summary.transferOrigin == nil ? "Local drawing" : "Imported drawing")
                .font(.caption).foregroundStyle(.secondary)
            }.tag(row.id)
          }
        }.frame(minWidth: 220).disabled(busy)
        VStack(alignment: .leading, spacing: 12) {
          if let drawing = selectedDrawing {
            Text(drawing.title).font(.headline)
            Text("\(drawing.program.strokes.count) strokes").foregroundStyle(.secondary)
            HStack {
              if let data = drawing.sourceImageData, let source = NSImage(data: data) {
                Image(nsImage: source).resizable().scaledToFit().frame(width: 140, height: 170)
              }
              PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource().resolve(
                program: drawing.program, nominalWidth: drawing.program.strokes.first?.style.nominalLineWidth ?? 0.4))
                .frame(minWidth: 180, minHeight: 170).background(.white)
            }.accessibilityLabel("Retained source and exact authored drawing preview")
            if let origin = drawing.transferOrigin {
              Text("Capture \(origin.captureID.uuidString)").font(.caption).textSelection(.enabled)
            }
            if let artist = drawing.transferredPackage?.artist {
              Text("Artist: \(artist.identifier) · \(artist.revision)").font(.caption).textSelection(.enabled)
            }
            HStack {
              Button("Send to Drawing") {
                let selection = selectedID
                perform {
                  guard selectedID == selection else { throw CancellationError() }
                  if let error = await application.projectSavedDrawing(drawing,
                    isStillCurrent: { !Task.isCancelled && selectedID == selection }) {
                    throw DrawingTransferError.unavailable(error)
                  }
                }
              }
              Button("Export Drawing", systemImage: "square.and.arrow.up") {
                perform {
                  let data = try await library.exportDrawingPackage(drawing)
                  try Task.checkCancellation()
                  document = DrawingTransferDocument(data: data)
                  exportName = "drawing.package.json"; exporting = true
                }
              }
            }.disabled(busy)
            if let origin = drawing.transferOrigin {
              let records = application.drawingReviewRecords.filter {
                $0.attemptEvidence?.intent.context.candidate?.origin == origin
              }
              Text("Plot results").font(.headline)
              if records.isEmpty { Text("No retained terminal result for this drawing.").foregroundStyle(.secondary) }
              ForEach(records, id: \.recordID) { record in
                HStack {
                  Text(String(describing: record.executionDisposition)).lineLimit(2)
                  Spacer()
                  Button("Export Plot Result") {
                    perform {
                      let raw = try await application.drawingEvidencePort.exportTerminalRecord(runID: record.runID)
                      try Task.checkCancellation()
                      let attachment = try PortraitPlotAttachmentInspection.attachment(raw)
                      document = DrawingTransferDocument(data: try PlotAttachmentCodec.encode(attachment))
                      exportName = "run.plotattachment.json"; exporting = true
                    }
                  }.disabled(busy)
                }
              }
              Text("Controller outcome and retained photographs remain separate from observed ink.")
                .font(.caption).foregroundStyle(.secondary)
            }
          } else { Text("Select a drawing.").foregroundStyle(.secondary) }
          Spacer()
        }.padding().frame(minWidth: 360)
      }
      if library.drawingHasMore {
        Button("Load More") { perform { await library.loadMoreDrawings() } }.disabled(busy)
      }
      if let failure { Text(failure).foregroundStyle(.red).textSelection(.enabled) }
    }
    .padding().frame(minWidth: 720, minHeight: 450)
    .task { await library.loadDrawingBrowser(photoID: nil) }
    .onChange(of: selectedID) { _, id in
      guard let id else { selectedDrawing = nil; return }
      if selectedDrawing?.id == id.drawingID, selectedDrawing?.sourcePhotoID == id.photoID { return }
      perform {
        let drawing = try await library.drawingForBrowsing(id.drawingID, photoID: id.photoID)
        try Task.checkCancellation()
        if selectedID == id { selectedDrawing = drawing }
      }
    }
    .onDisappear { cancelWork() }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      perform {
        let url = try result.get()
        let reader = Task.detached(priority: .userInitiated) { try DrawingTransferDocument.read(url) }
        let bytes = try await withTaskCancellationHandler { try await reader.value } onCancel: { reader.cancel() }
        try Task.checkCancellation()
        let drawing = try await library.importDrawingPackage(bytes, restoreDeleted: true)
        try Task.checkCancellation()
        await library.loadDrawingBrowser(photoID: nil)
        try Task.checkCancellation()
        selectedID = .init(drawingID: drawing.id, photoID: drawing.sourcePhotoID); selectedDrawing = drawing
      }
    }
    .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: exportName) { result in
      if case .failure(let error) = result { failure = error.localizedDescription }
    }
  }

  private func perform(_ action: @escaping @MainActor () async throws -> Void) {
    guard operationTask == nil else { return }
    busy = true; failure = nil
    operationRevision &+= 1
    let revision = operationRevision
    operationTask = Task { @MainActor in
      defer { if operationRevision == revision { busy = false; operationTask = nil } }
      do { try Task.checkCancellation(); try await action() }
      catch is CancellationError {}
      catch { if operationRevision == revision, !Task.isCancelled { failure = error.localizedDescription } }
    }
  }

  private func cancelWork() {
    operationRevision &+= 1; operationTask?.cancel(); operationTask = nil; busy = false
  }
}

private struct DrawingTransferSelection: Hashable {
  let drawingID: String
  let photoID: UUID?
}
private struct DrawingTransferRow: Identifiable {
  let summary: SavedDrawingSummary
  var id: DrawingTransferSelection { .init(drawingID: summary.id, photoID: summary.photoID) }
  init(_ summary: SavedDrawingSummary) { self.summary = summary }
}

private struct DrawingTransferDocument: FileDocument {
  static var readableContentTypes: [UTType] { [.json] }
  let data: Data
  init(data: Data) { self.data = data }
  init(configuration: ReadConfiguration) throws {
    guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
    data = bytes
  }
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }

  nonisolated static func read(_ url: URL) throws -> Data {
    let granted = url.startAccessingSecurityScopedResource()
    defer { if granted { url.stopAccessingSecurityScopedResource() } }
    let limit = DrawingTransferLimits.drawingJSONBytes
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard values.isRegularFile == true, let size = values.fileSize, size <= limit else {
      throw DrawingTransferError.limit("The drawing file exceeds the import limit.")
    }
    let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
    var bytes = Data()
    while true {
      try Task.checkCancellation()
      let chunk = try handle.read(upToCount: min(1024 * 1024, limit - bytes.count + 1)) ?? Data()
      guard !chunk.isEmpty else { return bytes }
      guard chunk.count <= limit - bytes.count else { throw DrawingTransferError.limit("The drawing file exceeds the import limit.") }
      bytes.append(chunk)
    }
  }
}
