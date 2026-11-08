import Foundation
import Observation
import PlotterModel
import PortraitCore
import PortraitLibrary

/// A pure stable-ID edit draft. Opening the editor never retains geometry.
@Observable @MainActor
package final class PortraitLineEditModel {
  package enum Tool: String, CaseIterable { case erase = "Click to Delete", lasso = "Lasso", restore = "Restore" }
  package struct Operation: Sendable {
    package enum Action: Sendable { case remove, restore }
    package let action: Action
    package let strokeIDs: [StrokeID]
  }
  package let base: Drawing
  package private(set) var original: Drawing?
  private let sketches: PortraitSketchCollection
  package private(set) var operations: [Operation] = []
  private var redoOperations: [Operation] = []
  package var selection: Set<StrokeID> = []
  package var tool: Tool = .erase
  package var showsOriginal = false
  package var showsPhoto = false
  package var zoom = 1.0
  package private(set) var isBusy = false
  package var error: String?
  package private(set) var savedDrawing: Drawing?
  private var savedMask: Set<StrokeID> = []
  private var editID = UUID()
  private let parentIntentID = UUID()
  package init(base: Drawing, sketches: PortraitSketchCollection) { self.base = base; self.sketches = sketches }
  package static func supports(_ drawing: Drawing) -> Bool { drawing.capabilities.supported.contains(.edit) }
  package var removed: Set<StrokeID> {
    var result = Set<StrokeID>()
    for operation in operations {
      if operation.action == .remove { result.formUnion(operation.strokeIDs) }
      else { result.subtract(operation.strokeIDs) }
    }
    return result
  }
  package var canUndo: Bool { !operations.isEmpty && !isBusy }
  package var canRedo: Bool { !redoOperations.isEmpty && !isBusy }
  package var remainingCount: Int { base.program.strokes.count - removed.count }
  package var hasUnsavedChanges: Bool { removed != savedMask }
  package var canSave: Bool { original != nil && remainingCount > 0 && !isBusy && hasUnsavedChanges }
  package var canEdit: Bool { original != nil && !isBusy && !showsOriginal && !showsPhoto }
  package func load() async { original = base }
  package func remove(_ ids: Set<StrokeID>) { apply(ids, action: .remove) }
  package func restore(_ ids: Set<StrokeID>) { apply(ids, action: .restore) }
  private func apply(_ ids: Set<StrokeID>, action: Operation.Action) {
    guard canEdit else { return }
    let prior = removed
    let batch = base.program.strokes.map(\.id).filter { ids.contains($0) && (action == .remove ? !prior.contains($0) : prior.contains($0)) }
    guard !batch.isEmpty else { return }
    let target = action == .remove ? prior.union(batch) : prior.subtracting(batch)
    do {
      if target.count < base.program.strokes.count && !target.isEmpty {
        _ = try DrawingStrokeMembership.apply(.membership(base.program.strokes.map(\.id).filter { !target.contains($0) }), to: base.program, universe: base.program)
      }
      operations.append(.init(action: action, strokeIDs: batch)); redoOperations = []; selection.subtract(batch); editID = UUID()
    } catch { self.error = error.localizedDescription }
  }
  package func undo() { guard canUndo, let value = operations.popLast() else { return }; redoOperations.append(value); editID = UUID(); selection = [] }
  package func redo() { guard canRedo, let value = redoOperations.popLast() else { return }; operations.append(value); editID = UUID(); selection = [] }
  @discardableResult package func save() async -> Bool {
    guard remainingCount > 0, !isBusy else { return false }
    isBusy = true; defer { isBusy = false }
    do {
      try await sketches.library.open()
      let parent = try await sketches.library.prepareRetention(base, reason: "required-edit-parent", intent: .init(id: parentIntentID))
      if removed.isEmpty {
        _ = try await sketches.library.commitRetention(parent)
        savedDrawing = try await sketches.library.drawing(parent.reference); savedMask = []; return true
      }
      let kept = base.program.strokes.map(\.id).filter { !removed.contains($0) }
      let child = try parent.drawing.applying(.membership(kept), to: parent.reference, programID: ProgramID(editID))
      let prepared = try await sketches.library.prepareRetention(child, reason: "committed-stroke-edit", intent: .init(id: editID))
      _ = try await sketches.library.commitRetentions([parent, prepared])
      savedDrawing = try await sketches.library.drawing(prepared.reference)
      savedMask = removed; return true
    } catch { self.error = error.localizedDescription; return false }
  }
}
