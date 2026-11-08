import SwiftUI
import PortraitCore

/// Stable-ID membership controls share the same native canvas as Flow pruning.
/// Cancel invalidates the sheet; only explicit Done requests persistence.
@MainActor
package struct DrawingMembershipEditor: View {
  @Bindable package var model: PortraitLineEditModel
  private let completion: () -> Void
  private let cancel: () -> Void
  package init(model: PortraitLineEditModel, completion: @escaping () -> Void, cancel: @escaping () -> Void) {
    self.model = model; self.completion = completion; self.cancel = cancel
  }
  package var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Edit Drawing").font(.title2)
        Spacer()
        Text("\(model.remainingCount) of \(model.base.program.strokes.count) strokes").foregroundStyle(.secondary)
      }
      HStack {
        Picker("Tool", selection: $model.tool) {
          ForEach(PortraitLineEditModel.Tool.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.frame(maxWidth: 380).accessibilityIdentifier("drawing.membershipEditor.tool").disabled(!model.canEdit)
        Toggle("Original", isOn: $model.showsOriginal).toggleStyle(.checkbox).accessibilityIdentifier("drawing.membershipEditor.original").disabled(model.isBusy)
        Spacer()
        Button("Undo") { model.undo() }.disabled(!model.canUndo)
        Button("Redo") { model.redo() }.disabled(!model.canRedo)
      }
      if let original = model.original, PortraitLineEditModel.supports(original),
        original.capabilities.supported.contains(.preview) {
        PortraitLineEditorCanvas(model: model, program: original.program)
          .frame(minWidth: 600, minHeight: 320)
      } else {
        Text("Preview unavailable: this drawing requires unsupported features.")
          .foregroundStyle(.secondary).frame(minWidth: 600, minHeight: 320)
      }
      HStack {
        Button("Delete Selected") { model.remove(model.selection) }.disabled(!model.canEdit || model.selection.isEmpty)
        Button("Restore All") { model.restore(model.removed) }.disabled(!model.canEdit || model.removed.isEmpty)
        Spacer()
        Button(model.isBusy ? "Close" : "Cancel") { model.close(); cancel() }.keyboardShortcut(.cancelAction)
          .accessibilityIdentifier("drawing.membershipEditor.cancel")
        Button("Done") {
          Task { if await model.save() { completion() } }
        }.keyboardShortcut(.defaultAction).accessibilityIdentifier("drawing.membershipEditor.done").disabled(!model.canSave)
      }
      if model.isBusy { ProgressView("Saving drawing…").controlSize(.small) }
      if let error = model.error { Text(error).foregroundStyle(.red) }
    }.padding().frame(minWidth: 740, minHeight: 500).accessibilityIdentifier("drawing.membershipEditor")
      .task { await model.load() }
      .onDisappear { model.close() }
  }
}
