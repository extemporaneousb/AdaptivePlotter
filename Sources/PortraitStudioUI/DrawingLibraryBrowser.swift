import AppKit
import Foundation
import Observation
import DrawingLibrary
import PortraitCore
import PortraitLibrary
import SwiftUI

/// A transient UI request, not a new selection or persistence authority. Its
/// full-ref predicate tolerates the handoff's own expected selection publication.
@MainActor
package struct DrawingBrowserHandoffRequest {
  package let drawing: Drawing
  private let current: @MainActor () -> Bool
  package var isCurrent: Bool { current() }
  fileprivate init(drawing: Drawing, current: @escaping @MainActor () -> Bool) {
    self.drawing = drawing; self.current = current
  }
}
package typealias DrawingBrowserHandoff = @MainActor (Drawing, DrawingBrowserHandoffRequest) async -> String?

@Observable @MainActor
package final class DrawingLibraryBrowserModel {
  package let sketches: PortraitSketchCollection
  package private(set) var editor: PortraitLineEditModel?
  package private(set) var isBusy = false
  package private(set) var isClosed = false
  package private(set) var error: String?
  @ObservationIgnored private var requestRevision: UInt64 = 0
  @ObservationIgnored private var selectionTask: Task<Void, Never>?
  package init(sketches: PortraitSketchCollection) { self.sketches = sketches }
  private func current(_ revision: UInt64) -> Bool { !isClosed && !sketches.isClosing && revision == requestRevision }
  package func load() async {
    guard !isClosed else { return }
    await sketches.load()
    if !isClosed { error = sketches.error }
  }
  package func restore(_ route: DrawingLibraryRoute, isStillCurrent: @escaping @MainActor () -> Bool = { true }) async {
    guard !isClosed, !sketches.isClosing, !Task.isCancelled, isStillCurrent() else { return }
    let selected = route.drawing
    requestRevision &+= 1; let revision = requestRevision
    selectionTask?.cancel(); dismissEditor(); sketches.clearSelection(); sketches.invalidateBrowse()
    isBusy = true
    defer { if current(revision) { isBusy = false } }
    do {
      let scope = try await route.validatedScope(in: sketches.library)
      guard current(revision), isStillCurrent(), !Task.isCancelled else { return }
      await sketches.load(scope: scope)
      guard current(revision), isStillCurrent(), !Task.isCancelled else { return }
      if let failure = sketches.error { error = failure; return }
      if let ref = selected {
        let value = try await sketches.library.drawing(ref)
        try await route.validate(value, in: sketches.library)
        guard current(revision), isStillCurrent(), !Task.isCancelled else { return }
        try sketches.selectLoaded(value)
      }
      error = nil
    } catch { if current(revision), isStillCurrent(), !Task.isCancelled { self.error = error.localizedDescription } }
  }
  @discardableResult package func select(_ reference: DrawingRef?) -> Task<Void, Never> {
    requestRevision &+= 1
    let revision = requestRevision
    selectionTask?.cancel(); dismissEditor()
    guard current(revision) else { return Task {} }
    if reference == nil { sketches.clearSelection(); isBusy = false; return Task {} }
    isBusy = true
    sketches.clearSelection()
    let task = Task { [weak self] in
      guard let self else { return }
      defer { if self.current(revision) { self.isBusy = false } }
      guard self.current(revision), let reference else { return }
      do {
        try await self.sketches.select(reference)
        guard self.current(revision), !Task.isCancelled else { return }
        self.error = nil
      } catch {
        if self.current(revision), !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
    selectionTask = task
    return task
  }
  @discardableResult package func beginEdit() -> PortraitLineEditModel? {
    guard !isClosed, !isBusy, !sketches.isClosing, let drawing = sketches.selected else { return nil }
    guard PortraitLineEditModel.supports(drawing) else {
      error = "Editing unavailable: this drawing requires unsupported features."; return nil
    }
    requestRevision &+= 1; dismissEditor()
    let draft = PortraitLineEditModel(base: drawing, sketches: sketches)
    editor = draft; error = nil
    return draft
  }
  /// Persistence has already completed. Only this still-open sheet can adopt its
  /// result, and only before any other collection selection has taken place.
  @discardableResult package func finishEdit(_ draft: PortraitLineEditModel) -> Bool {
    guard !isClosed, !sketches.isClosing, editor === draft, !draft.isClosed, !draft.isBusy else { return false }
    guard draft.openingSelectionEpoch == sketches.selectionEpoch, !draft.hasUnsavedChanges, let saved = draft.savedDrawing else {
      error = "The selection changed. Reopen the drawing to edit it."; dismissEditor(); return false
    }
    do {
      try sketches.selectLoaded(saved)
      requestRevision &+= 1; dismissEditor(); error = nil
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
  package func dismissEditor() { editor?.close(); editor = nil }
  package func close() {
    isClosed = true; requestRevision &+= 1
    selectionTask?.cancel(); dismissEditor(); isBusy = false
  }
  package func makeHandoffRequest() -> DrawingBrowserHandoffRequest? {
    guard !isClosed, !isBusy, !sketches.isClosing,
      let drawing = sketches.selected, let ref = drawing.reference else { return nil }
    do { try drawing.capabilities.require(.plot) }
    catch { self.error = "Send unavailable: this drawing requires unsupported features."; return nil }
    requestRevision &+= 1; dismissEditor()
    let revision = requestRevision
    return .init(drawing: drawing, current: { [weak self] in
      guard let self else { return false }
      return self.current(revision) && self.sketches.selected?.reference == ref
    })
  }
  package func sendSelected(using handoff: DrawingBrowserHandoff) async {
    guard let request = makeHandoffRequest() else { return }
    let revision = requestRevision
    isBusy = true
    defer { if current(revision) { isBusy = false } }
    let failure = await handoff(request.drawing, request)
    if request.isCurrent { error = failure }
  }
  package func importDrawings(from url: URL, route: Binding<DrawingLibraryRoute>) async {
    guard !isClosed, !isBusy, !sketches.isClosing, !Task.isCancelled else { return }
    let opening = route.wrappedValue
    requestRevision &+= 1; let revision = requestRevision
    dismissEditor(); isBusy = true
    defer { if current(revision) { isBusy = false } }
    do {
      let refs = try await sketches.importDrawings(from: url)
      guard current(revision), route.wrappedValue == opening, !Task.isCancelled else { return }
      guard let first = refs.first else { error = "The package contains no authored Drawings."; return }
      var next = opening; next.showDrawing(first)
      let destination = next
      route.wrappedValue = destination
      await restore(destination, isStillCurrent: { route.wrappedValue == destination })
    } catch {
      if current(revision), route.wrappedValue == opening, !Task.isCancelled { self.error = error.localizedDescription }
    }
  }
  package func importResult(from url: URL, route: Binding<DrawingLibraryRoute>) async {
    guard !isClosed, !isBusy, !sketches.isClosing, !Task.isCancelled else { return }
    let opening = route.wrappedValue
    requestRevision &+= 1; let revision = requestRevision
    dismissEditor(); isBusy = true
    defer { if current(revision) { isBusy = false } }
    do {
      let mounted = try await sketches.library.mountResult(from: url)
      let result = try await sketches.library.result(mounted.reference)
      guard current(revision), route.wrappedValue == opening, !Task.isCancelled else { return }
      guard let reference = result.index.known?.roots.first else {
        error = "The returned result is preserved, but has no supported Drawing to reveal."; return
      }
      var next = opening; next.showDrawing(reference); next.workspace = .library
      let destination = next
      route.wrappedValue = destination
      await restore(destination, isStillCurrent: { route.wrappedValue == destination })
    } catch {
      if current(revision), route.wrappedValue == opening, !Task.isCancelled { self.error = error.localizedDescription }
    }
  }
  package func exportDrawing(_ ref: DrawingRef, to url: URL) async {
    guard !isClosed, !isBusy, !sketches.isClosing else { return }
    requestRevision &+= 1; let revision = requestRevision
    isBusy = true; defer { if current(revision) { isBusy = false } }
    do {
      try await sketches.exportDrawing(ref, to: url)
      if current(revision) { error = nil }
    } catch { if current(revision) { self.error = error.localizedDescription } }
  }
  package func exportResult(_ reference: DrawingLibraryResultRef, to url: URL) async {
    guard !isClosed, !isBusy, !sketches.isClosing else { return }
    requestRevision &+= 1; let revision = requestRevision
    isBusy = true; defer { if current(revision) { isBusy = false } }
    do {
      try await sketches.library.exportResult(reference, to: url)
      if current(revision) { error = nil }
    } catch { if current(revision) { self.error = error.localizedDescription } }
  }
  package func loadMore() async {
    guard !isClosed, !isBusy else { return }
    let revision = requestRevision
    do { try await sketches.loadMore() }
    catch { if current(revision), !Task.isCancelled { self.error = error.localizedDescription } }
  }
  package func report(_ message: String) { if !isClosed { error = message } }
}

/// Shared by the embedded and standalone applications; the borrowed collection
/// supplies rows and full-ref selection for both the browser and its editor.
@MainActor
package struct DrawingLibraryBrowser: View {
  package let sketches: PortraitSketchCollection
  package let handoff: DrawingBrowserHandoff?
  @Environment(\.drawingPresentationPolicy) private var presentationPolicy
  @Binding private var route: DrawingLibraryRoute
  private let openStudio: (PhotoRef) async -> String?
  private let review: (Drawing) -> AnyView
  private var showsPhotos: Binding<Bool> {
    Binding(get: { route.activeCollection == .photos }, set: { photos in
      model.dismissEditor(); sketches.clearSelection(); route.drawing = nil
      route.collection = photos ? .photos : .drawings
      route.branchParent = nil; route.photo = nil; route.input = nil
    })
  }
  @State private var activePanel: NSSavePanel?
  private let close: () -> Void
  @State private var model: DrawingLibraryBrowserModel
  package init(sketches: PortraitSketchCollection, close: @escaping () -> Void, handoff: DrawingBrowserHandoff? = nil,
    route: Binding<DrawingLibraryRoute> = .constant(.init()), openStudio: @escaping (PhotoRef) async -> String? = { _ in nil },
    review: @escaping (Drawing) -> AnyView = { _ in AnyView(EmptyView()) }) {
    self.sketches = sketches; self.close = close; self.handoff = handoff
    _route = route; self.openStudio = openStudio; self.review = review
    _model = State(initialValue: DrawingLibraryBrowserModel(sketches: sketches))
  }
  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Library").font(.title2)
        Picker("Collection", selection: showsPhotos) { Text("Photos").tag(true); Text("Drawings").tag(false) }
          .pickerStyle(.segmented).frame(width: 200)
        if route.activeCollection == .children {
          Button("All Drawings") { sketches.clearSelection(); route.collection = .drawings; route.branchParent = nil; route.photo = nil; route.input = nil; route.drawing = nil }
        }
        Spacer()
        Button("Import Drawing", systemImage: "square.and.arrow.down") { Task { await importDrawing() } }
          .accessibilityIdentifier("drawing.library.import").disabled(model.isBusy)
        Button("Import Result", systemImage: "tray.and.arrow.down") { Task { await importResult() } }
          .accessibilityIdentifier("drawing.library.importResult").disabled(model.isBusy)
        Button("Close") { model.close(); close() }
          .keyboardShortcut(.escape, modifiers: presentationPolicy.modalUnavailableReason == nil ? [] : [.command])
          .accessibilityIdentifier("drawing.library.close")
      }
      if let draft = model.editor {
        DrawingMembershipEditor(model: draft, completion: {
          if model.finishEdit(draft), let reference = sketches.selected?.reference {
            route.showDrawing(reference)
            let destination = route
            Task { await model.restore(destination, isStillCurrent: { route == destination }) }
          }
        }, cancel: { model.dismissEditor() })
      } else { HSplitView {
        if showsPhotos.wrappedValue {
          DrawingLibrarySourceView(sketches: sketches, route: $route, openStudio: openStudio).frame(minWidth: 420)
        }
        VStack {
          Text("\(sketches.entries.count) retained Drawings loaded").font(.caption).foregroundStyle(.secondary)
          List(sketches.error == nil ? sketches.entries : [], id: \.reference, selection: Binding(
            get: { sketches.selected?.reference }, set: { reference in _ = model.select(reference) })) { entry in
              Text(entry.title ?? "Drawing").tag(entry.reference)
            }.disabled(model.isBusy)
          if sketches.hasMore { Button("Load More") { Task { await model.loadMore() } }.disabled(model.isBusy) }
        }.frame(minWidth: 230)
        ScrollView { VStack(alignment: .leading, spacing: 12) {
          if let drawing = sketches.selected, let ref = drawing.reference {
            Text("\(drawing.program.strokes.count) strokes").foregroundStyle(.secondary)
            if drawing.capabilities.supported.contains(.preview) {
              PortraitPlaneProgramPreview(preview: PortraitPlanePreviewSource().resolve(
                program: drawing.program, nominalWidth: drawing.program.strokes.first?.style.nominalLineWidth ?? 0.4))
                .frame(minWidth: 250, minHeight: 220)
            } else {
              Text("Preview unavailable: this drawing requires unsupported features.")
                .foregroundStyle(.secondary).frame(minWidth: 250, minHeight: 220)
            }
            HStack {
              Button("Edit") { _ = model.beginEdit() }.accessibilityIdentifier("drawing.library.edit").disabled(!PortraitLineEditModel.supports(drawing))
              if let handoff {
                Button("Send to Drawing") { Task { await model.sendSelected(using: handoff) } }
                  .accessibilityIdentifier("drawing.library.send").disabled(!drawing.capabilities.supported.contains(.plot))
              }
              Button("Export Drawing", systemImage: "square.and.arrow.up") { Task { await exportDrawing(ref) } }
                .accessibilityIdentifier("drawing.library.export")
            }.disabled(model.isBusy)
            if case .present(let parent) = drawing.parent {
              Button("Parent Drawing") {
                route.showDrawing(parent)
                _ = model.select(parent)
              }
            }
            Button("Child Drawings") {
              route.collection = .children; route.branchParent = ref; route.photo = nil; route.input = nil; route.drawing = nil
            }
            if drawing.producer.id == "adaptiveplotter.historical-import", drawing.producer.version == "1" {
              HistoricalRunsView(receipt: drawing.producer.originalJSON)
            }
            DrawingResultReviewView(library: sketches.library, drawing: ref, export: exportResult).id(ref)
            review(drawing)
          } else { Text("Select a drawing.").foregroundStyle(.secondary) }
        }.padding() }
      } }
      if model.isBusy { ProgressView().controlSize(.small) }
      if let error = model.error { Text(error).foregroundStyle(.red) }
      else if let error = sketches.error { Text("Library unavailable: " + error).foregroundStyle(.red) }
    }.padding().frame(minWidth: 760, minHeight: 500).accessibilityIdentifier("drawing.library.browser")
      .task(id: route.scopeKey) {
        let requested = route
        await model.restore(requested, isStillCurrent: { route.scopeKey == requested.scopeKey })
      }
      .onChange(of: sketches.selected?.reference) { _, ref in if let ref { route.drawing = ref } }
      .onDisappear { model.close() }
      .onChange(of: presentationPolicy.modalUnavailableReason) { _, reason in if reason != nil { activePanel?.cancel(nil) } }
  }
  private func importDrawing() async {
    if let reason = presentationPolicy.modalUnavailableReason { model.report(reason); return }
    let opening = route
    let panel = NSOpenPanel(); panel.title = "Import Drawing"
    activePanel = panel; defer { activePanel = nil }
    panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    guard await panel.begin() == .OK, let url = panel.url else { return }
    guard route == opening, !Task.isCancelled, !model.isClosed else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    await model.importDrawings(from: url, route: $route)
  }
  private func importResult() async {
    if let reason = presentationPolicy.modalUnavailableReason { model.report(reason); return }
    let opening = route
    let panel = NSOpenPanel(); panel.title = "Import Returned Result"
    activePanel = panel; defer { activePanel = nil }
    panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    guard await panel.begin() == .OK, let url = panel.url else { return }
    guard route == opening, !Task.isCancelled, !model.isClosed else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    await model.importResult(from: url, route: $route)
  }
  private func exportResult(_ reference: DrawingLibraryResultRef) async {
    if let reason = presentationPolicy.modalUnavailableReason { model.report(reason); return }
    let panel = NSSavePanel(); panel.title = "Export Returned Result"; panel.nameFieldStringValue = "Drawing-Result.zip"
    activePanel = panel; defer { activePanel = nil }
    guard await panel.begin() == .OK, let url = panel.url, !model.isClosed, !Task.isCancelled else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    await model.exportResult(reference, to: url)
  }
  private func exportDrawing(_ ref: DrawingRef) async {
    if let reason = presentationPolicy.modalUnavailableReason { model.report(reason); return }
    let panel = NSSavePanel(); panel.title = "Export Drawing"; panel.nameFieldStringValue = "Drawing.drawingexchange"
    activePanel = panel; defer { activePanel = nil }
    guard await panel.begin() == .OK, let url = panel.url else { return }
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    await model.exportDrawing(ref, to: url)
  }
}

/// A read-only attribution from the imported producer receipt. Exact raw files
/// are indexed in the conversion crosswalk, outside the current Run authority.
private struct HistoricalRunsView: View {
  struct Receipt: Decodable {
    let historicalRuns: [Run]
    struct Run: Decodable, Identifiable {
      let runID: UUID
      let status: String?
      let dispatchPossible: Bool?
      let frontiers: Frontiers?
      let noInkConfirmation: Confirmation?
      var id: UUID { runID }
    }
    struct Frontiers: Decodable {
      let controllerCompletedStrokeCount: Int
      let inkVerifiedStrokeCount: Int
    }
    struct Confirmation: Decodable { let recordedAt: Date }
  }

  let receipt: Data
  var body: some View {
    if let value = try? JSONDecoder().decode(Receipt.self, from: receipt), !value.historicalRuns.isEmpty {
      DisclosureGroup("Historical plot runs (\(value.historicalRuns.count))") {
        ForEach(value.historicalRuns) { run in
          VStack(alignment: .leading) {
            Text(run.status ?? (run.dispatchPossible == true ? "Possible ink" : "Terminal status unavailable"))
            Text(run.runID.uuidString).font(.caption)
            if let counts = run.frontiers {
              Text("\(counts.controllerCompletedStrokeCount) controller-completed strokes, \(counts.inkVerifiedStrokeCount) ink-verified")
            }
            if run.noInkConfirmation != nil { Text("Operator confirmed no ink") }
          }.textSelection(.enabled)
        }
      }
    }
  }
}
