import AppKit
import SwiftUI
import PortraitLibrary

package struct PortraitLineEditor: View {
  @Environment(\.dismiss) private var dismiss
  @State private var model: PortraitLineEditModel
  @State private var confirmsClose = false
  @State private var isHandingOff = false
  @State private var handoffError: String?
  private let didSave: (SavedDrawing) -> Void
  private let handoffTitle: String
  private let handoff: ((SavedDrawing) async -> String?)?

  package init(drawing: SavedDrawing, sketches: PortraitSketchCollection,
    handoffTitle: String = "Export Drawing", handoff: ((SavedDrawing) async -> String?)? = nil,
    didSave: @escaping (SavedDrawing) -> Void = { _ in }) {
    _model = State(initialValue: PortraitLineEditModel(base: drawing, sketches: sketches))
    self.didSave = didSave
    self.handoffTitle = handoffTitle; self.handoff = handoff
  }

  package var body: some View {
    VStack(spacing: 10) {
      HStack {
        Text(model.base.title).font(.headline).lineLimit(1).help(model.base.title)
        Spacer()
        Button("Close") {
          if model.hasUnsavedChanges { confirmsClose = true } else { dismiss() }
        }.disabled(model.isBusy)
        Button("Save Edited Drawing") { Task { await save() } }
          .disabled(!model.canSave).buttonStyle(.borderedProminent)
          .accessibilityIdentifier("portrait.lineEditor.save")
      }
      HStack {
        Picker("Tool", selection: $model.tool) {
          ForEach(PortraitLineEditModel.Tool.allCases, id: \.self) { tool in Text(tool.rawValue).tag(tool) }
        }.pickerStyle(.segmented).frame(width: 305).disabled(!model.canEdit)
        Button("Delete Selected (\(model.selection.count))", systemImage: "trash") { model.remove(model.selection) }
          .disabled(!model.canEdit || model.selection.isEmpty || model.tool == .restore)
          .accessibilityIdentifier("portrait.lineEditor.deleteSelected")
        Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }.disabled(!model.canUndo)
          .keyboardShortcut("z", modifiers: .command)
          .help("Undo last line edit (⌘Z)")
          .accessibilityIdentifier("portrait.lineEditor.undo")
        Button("Redo", systemImage: "arrow.uturn.forward") { model.redo() }.disabled(!model.canRedo)
          .keyboardShortcut("z", modifiers: [.command, .shift])
          .help("Redo line edit (⇧⌘Z)")
        Spacer()
      }.controlSize(.small)
      HStack {
        Toggle("Original", isOn: $model.showsOriginal).toggleStyle(.button)
          .disabled(model.showsPhoto).accessibilityIdentifier("portrait.lineEditor.original")
        Toggle("Photo", isOn: $model.showsPhoto).toggleStyle(.button)
        Text("\(model.remainingCount) lines · \(model.removed.count) removed").font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text("Zoom").font(.caption)
        Slider(value: $model.zoom, in: 1...4).frame(width: 120)
        Button("Fit") { model.zoom = 1 }
      }.controlSize(.small)
      GeometryReader { area in
        if let original = model.original {
          if model.showsPhoto, let image = NSImage(data: original.source.bytes) {
            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
          } else {
            ScrollView([.horizontal, .vertical]) {
              PortraitLineEditorCanvas(model: model, program: original.program)
                .frame(width: max(1, area.size.width - 16) * model.zoom,
                  height: max(1, area.size.height - 16) * model.zoom)
            }
          }
        } else if model.isBusy { ProgressView("Retaining original…").frame(maxWidth: .infinity, maxHeight: .infinity) }
      }
      HStack {
        Text(model.tool == .restore ? "Click a gray removed line to restore it. Undo and Redo apply to both tools."
          : model.tool == .erase ? "Click removes a whole line. Undo restores it." : "Lasso selects every line it touches. Shift adds to selection; Delete removes the group.")
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        if model.isBusy { ProgressView().controlSize(.small) }
      }
      if model.remainingCount == 0, model.original != nil {
        Text("All lines removed. Undo to keep at least one line before saving a plot target.").font(.caption).foregroundStyle(.orange)
      }
      if let error = model.error {
        HStack {
          Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
          if model.original == nil { Button("Retry") { Task { await model.load() } } }
        }
      } else if model.savedDrawing != nil && !model.hasUnsavedChanges {
        HStack {
          Text("Saved in Drawings · original and edit data retained").font(.caption).foregroundStyle(.secondary)
          Spacer()
          if let handoff, let drawing = model.savedDrawing {
            Button(handoffTitle) {
              isHandingOff = true; handoffError = nil
              Task { handoffError = await handoff(drawing); isHandingOff = false }
            }.accessibilityIdentifier("portrait.lineEditor.handoff")
          }
        }
      }
      if let handoffError { Text(handoffError).font(.caption).foregroundStyle(.red) }
    }.padding(16).frame(minWidth: 880, idealWidth: 1120, minHeight: 620, idealHeight: 800)
      .disabled(isHandingOff)
      .interactiveDismissDisabled(model.hasUnsavedChanges || model.isBusy || isHandingOff)
      .task { await model.load() }
      .onChange(of: model.tool) { _, _ in model.selection = [] }
      .confirmationDialog("Save this edit before closing?", isPresented: $confirmsClose, titleVisibility: .visible) {
        Button("Save Edited Drawing") { Task { if await save() { dismiss() } } }.disabled(!model.canSave)
        Button("Discard Unsaved Changes", role: .destructive) { dismiss() }
        Button("Cancel", role: .cancel) { }
      }
  }

  @discardableResult private func save() async -> Bool {
    guard await model.save(), let drawing = model.savedDrawing else { return false }
    didSave(drawing); return true
  }
}
