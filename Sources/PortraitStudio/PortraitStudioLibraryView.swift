import AppKit
import SwiftUI
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI

struct PortraitStudioLibraryView: View {
  @Bindable var composition: PortraitStudioComposition
  @State private var section = "Drawings"
  @State private var showsSource = false
  private var library: PortraitStudioLibraryModel { composition.browser }

  var body: some View {
    HSplitView {
      VStack {
        Picker("Library", selection: $section) {
          Text("Drawings").tag("Drawings")
          Text("Photos").tag("Photos")
          Text("Plots").tag("Plots")
        }.pickerStyle(.segmented)
        List {
          if section == "Photos" {
            ForEach(library.photos) { photo in
              Button { Task { await library.selectPhoto(photo.id) } } label: {
                VStack(alignment: .leading) {
                  Text(photo.reference.label)
                  Text("\(photo.drawingCount) drawings").font(.caption).foregroundStyle(.secondary)
                }
              }.buttonStyle(.plain)
            }
            if library.hasMorePhotos {
              Button("More Photos") { Task { await library.loadMorePhotos() } }
            }
          } else if section == "Plots" {
            ForEach(library.attachments, id: \.id) { attachment in
              attachmentButton(attachment)
            }
            if library.hasMoreAttachments {
              Button("More Plots") { Task { await library.loadMoreAttachments() } }
            }
          } else {
            ForEach(library.sketches.drawingSummaries, id: \.studioRowID) { drawing in
              Button { Task { await library.selectDrawing(drawing) } } label: {
                VStack(alignment: .leading) {
                  Text(drawing.title)
                  Text("\(drawing.strokeCount) strokes").font(.caption).foregroundStyle(.secondary)
                }
              }.buttonStyle(.plain)
            }
            if library.sketches.drawingHasMore {
              Button("More Drawings") { Task { await library.loadMoreDrawings() } }
            }
          }
        }
        if library.isLoading { ProgressView().controlSize(.small) }
      }.padding(8).frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
      VStack(alignment: .leading, spacing: 12) {
        if let attachment = library.attachment, let record = library.record {
          PortraitStudioAttachmentView(attachment: attachment, record: record)
        } else if let drawing = library.drawing {
          HStack {
            Text(drawing.title).font(.title2)
            Spacer()
            Toggle("Source", isOn: $showsSource).toggleStyle(.button)
            Button("Export Drawing") { composition.exportSelection() }.disabled(composition.isBusy)
            if drawing.portraitCandidate != nil {
              Button("Edit in Studio") { Task { await composition.editSelection() } }
            }
          }
          HStack {
            Button("Use as First Drawing") { composition.review.chooseFirst(drawing) }
            if let first = composition.review.firstDrawing {
              Text("First: \(first.title)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
              Button("Compare with First Drawing") {
                Task {
                  await composition.review.compare(with: drawing)
                  if composition.review.error == nil { composition.workspace = .review }
                  else { composition.message = composition.review.error }
                }
              }.disabled(composition.review.isLoading)
              Button("Clear First") { composition.review.clearFirst() }
            }
          }.controlSize(.small)
          PortraitStudioGroupDeclarationView(model: composition.review, drawing: drawing)
          if showsSource { sourcePreview }
          else {
            PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource()
              .resolve(program: drawing.program, nominalWidth: composition.strokeStyle.nominalLineWidth))
          }
          Text("Reference preview · physical dimensions unverified").font(.caption).foregroundStyle(.secondary)
          if let package = drawing.transferredPackage {
            Text("Imported · \(package.artist.identifier) · \(package.artist.revision)")
            Text("Imported source and artist settings are read-only.").font(.caption)
            Text("Capture \(package.origin.captureID.uuidString)").font(.caption).textSelection(.enabled)
            DisclosureGroup("Artist settings") {
              ScrollView {
                Text(String(data: package.artist.settingsJSON, encoding: .utf8) ?? "Encoded artist settings")
                  .font(.caption.monospaced()).textSelection(.enabled)
              }.frame(maxHeight: 120)
            }
          }
          Text("Program \(drawing.programContentHash)").font(.caption.monospaced()).textSelection(.enabled)
          ForEach(library.drawingAttachments, id: \.id) { attachmentButton($0) }
          if library.hasMoreAttachments {
            Button("More Plot Attachments") { Task { await library.loadMoreAttachments() } }
          }
        } else if library.sourceData != nil {
          sourcePreview
          Text("Drawings from this capture").font(.headline)
          ForEach(library.photoDrawings) { drawing in
            Button(drawing.summary.title) {
              Task { await library.selectDrawing(drawing.summary.id, identity: drawing.identity) }
            }
          }
        } else {
          ContentUnavailableView("Select a Drawing or Photo", systemImage: "books.vertical",
            description: Text("This library belongs to Portrait Studio. Import photos in Studio or import an exported drawing."))
        }
      }.padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .task { await library.reload() }
    .alert("Library needs attention", isPresented: Binding(get: { library.error != nil },
      set: { if !$0 { library.error = nil } })) {
      Button("OK", role: .cancel) { library.error = nil }
    } message: { Text(library.error ?? "") }
  }

  @ViewBuilder private var sourcePreview: some View {
    if let data = library.sourceData, let image = NSImage(data: data) {
      Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
    } else { ContentUnavailableView("Source Unavailable", systemImage: "photo") }
  }

  private func attachmentButton(_ attachment: PlotAttachmentSummary) -> some View {
    Button { Task { await library.selectAttachment(attachment.id) } } label: {
      VStack(alignment: .leading) {
        Text("Plot \(attachment.runID.uuidString.prefix(8)) · \(attachment.mediaCount) originals")
        if attachment.linkedDrawingID == nil { Text("Originating drawing not imported").font(.caption) }
      }
    }.buttonStyle(.plain)
  }
}

private struct PortraitStudioAttachmentView: View {
  let attachment: PlotAttachment
  let record: DrawingRunEvidenceRecord
  @State private var selected = 0

  private var media: [(String, DrawingRunMediaReference)] {
    guard let attempt = record.attemptEvidence else { return [] }
    return attempt.baselines.enumerated().map { ("Before \($0.offset + 1)", $0.element) }
      + attempt.progressFrames.enumerated().map { ("Progress \($0.offset + 1)", $0.element.media) }
      + attempt.terminalFrames.enumerated().map { ("After \($0.offset + 1)", $0.element) }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Returned Plot Attachment").font(.title2)
      Text("Origin library \(attachment.origin.libraryID.uuidString)").font(.caption).textSelection(.enabled)
      Text("Capture \(attachment.origin.captureID.uuidString)").font(.caption).textSelection(.enabled)
      Text("Result \(attachment.origin.resultID)").font(.caption.monospaced()).textSelection(.enabled)
      Text("Execution: \(String(describing: record.executionDisposition))")
      Text("Observation: \(String(describing: record.observation))").lineLimit(4)
      Text("Controller completion alone does not establish physical ink. These are the retained observations for this attempt.")
        .font(.caption).foregroundStyle(.secondary)
      if !media.isEmpty {
        Picker("Retained frame", selection: $selected) {
          ForEach(media.indices, id: \.self) { index in Text(media[index].0).tag(index) }
        }
        if media.indices.contains(selected),
          let frame = try? PortraitPlotAttachmentInspection.frame(attachment, reference: media[selected].1),
          let image = FrameImageFactory.image(from: frame) {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else { ContentUnavailableView("Original Frame Unavailable", systemImage: "photo") }
      } else { ContentUnavailableView("No Retained Original Frames", systemImage: "photo") }
      Text("Run \(attachment.runID.uuidString)").font(.caption.monospaced()).textSelection(.enabled)
      Text("Record \(attachment.recordSHA256)").font(.caption.monospaced()).textSelection(.enabled)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).onChange(of: attachment.id) { _, _ in selected = 0 }
  }
}
