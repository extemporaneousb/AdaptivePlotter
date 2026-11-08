import AppKit
import DrawingLibrary
import Foundation
import PortraitCore
import PortraitStudioUI
import SwiftUI

/// Current-format file exchange; internal projection passes the admitted value directly.
struct DrawingTransferView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  @State private var entries: [DrawingLibraryEntry] = []
  @State private var selectedRef: DrawingRef?
  @State private var selectedDrawing: Drawing?
  @State private var cursor: DrawingLibraryCursor?
  @State private var busy = false
  @State private var failure: String?
  private var library: DrawingLibrary { application.portraitStudio.library }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Drawing Exchange").font(.title2)
        Spacer()
        Button("Import Drawing", systemImage: "square.and.arrow.down") { Task { await importDrawing() } }.disabled(busy)
        Button("Close", action: close).keyboardShortcut(.cancelAction)
      }
      HSplitView {
        VStack {
          List(entries, id: \.reference, selection: $selectedRef) { entry in
            Text(entry.title ?? "Drawing").tag(entry.reference)
          }.disabled(busy)
          if cursor != nil { Button("Load More") { Task { await loadPage(reset: false) } }.disabled(busy) }
        }.frame(minWidth: 230)
        VStack(alignment: .leading, spacing: 12) {
          if let drawing = selectedDrawing, let ref = drawing.reference {
            Text("\(drawing.program.strokes.count) strokes").foregroundStyle(.secondary)
            Text(ref.revision.uuidString).font(.caption).textSelection(.enabled)
            if drawing.capabilities.supported.contains(.preview) {
              PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource().resolve(
                program: drawing.program, nominalWidth: drawing.program.strokes.first?.style.nominalLineWidth ?? 0.4))
                .frame(minWidth: 250, minHeight: 220)
            } else {
              Text("Preview unavailable: this drawing requires unsupported features.")
                .foregroundStyle(.secondary).frame(minWidth: 250, minHeight: 220)
            }
            HStack {
              Button("Send to Drawing") {
                Task {
                  busy = true; defer { busy = false }
                  failure = await application.projectDrawing(drawing,
                    isStillCurrent: { !Task.isCancelled && selectedRef == ref })
                }
              }.disabled(!drawing.capabilities.supported.contains(.plot))
              Button("Export Drawing", systemImage: "square.and.arrow.up") { Task { await exportDrawing(ref) } }
            }.disabled(busy)
          } else { Text("Select a drawing.").foregroundStyle(.secondary) }
        }.padding()
      }
      if let failure { Text(failure).foregroundStyle(.red) }
    }.padding().frame(minWidth: 760, minHeight: 500)
      .task { await loadPage(reset: true) }
      .task(id: selectedRef) {
        selectedDrawing = nil
        guard let ref = selectedRef else { return }
        do {
          let drawing = try await library.drawing(ref)
          guard !Task.isCancelled, selectedRef == ref else { return }
          selectedDrawing = drawing
        } catch { if !Task.isCancelled { failure = error.localizedDescription } }
      }
  }
  private func loadPage(reset: Bool) async {
    do {
      let page = try await library.drawings(limit: 50, after: reset ? nil : cursor)
      entries = reset ? page.entries : entries + page.entries
      cursor = page.next
    } catch { failure = error.localizedDescription }
  }
  private func importDrawing() async {
    let panel = NSOpenPanel()
    panel.title = "Import Drawing Exchange"
    panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    guard await panel.begin() == .OK, let url = panel.url else { return }
    busy = true; defer { busy = false }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let refs = try await library.importDrawings(from: url)
      await loadPage(reset: true)
      selectedRef = refs.first
    } catch { failure = error.localizedDescription }
  }
  private func exportDrawing(_ ref: DrawingRef) async {
    let panel = NSSavePanel()
    panel.title = "Export Drawing Exchange"; panel.nameFieldStringValue = "Drawing.drawingexchange"
    guard await panel.begin() == .OK, let url = panel.url else { return }
    busy = true; defer { busy = false }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do { try await library.exportDrawing(ref, to: url) }
    catch { failure = error.localizedDescription }
  }
}
