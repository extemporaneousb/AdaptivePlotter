import Foundation
import Observation
import PlotterModel
import PortraitCore
import PortraitLibrary

/// A pure stable-ID edit draft. Opening the editor never retains geometry.
@Observable @MainActor
package final class PortraitLineEditModel: Identifiable {
  package let id = UUID()
  package let openingSelectionEpoch: UInt64
  package private(set) var isClosed = false
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
  @ObservationIgnored private var outstandingIntentIDs = Set<UUID>()
  @ObservationIgnored private var saveSettlementWaiters: [CheckedContinuation<Void, Never>] = []
  package init(base: Drawing, sketches: PortraitSketchCollection) {
    self.base = base; self.sketches = sketches; openingSelectionEpoch = sketches.selectionEpoch
  }
  package func close() {
    guard !isClosed else { return }
    isClosed = true
    let intents = takeOutstandingIntents()
    guard !intents.isEmpty else { return }
    let settlement: Task<Void, Never>? = isBusy ? Task { await self.awaitSaveSettlement() } : nil
    sketches.discardStrokeEditPreparations(intents, after: settlement)
  }
  private func takeOutstandingIntents() -> Set<UUID> {
    let intents = outstandingIntentIDs; outstandingIntentIDs.removeAll(); return intents
  }
  private func awaitSaveSettlement() async {
    if isBusy { await withCheckedContinuation { saveSettlementWaiters.append($0) } }
  }
  private func didSettleSave() {
    isBusy = false
    let waiters = saveSettlementWaiters; saveSettlementWaiters = []
    for waiter in waiters { waiter.resume() }
  }
  package static func supports(_ drawing: Drawing) -> Bool { drawing.capabilities.supported.contains(.edit) }
  package var removed: Set<StrokeID> {
    var result = Set<StrokeID>()
    for operation in operations {
      if operation.action == .remove { result.formUnion(operation.strokeIDs) }
      else { result.subtract(operation.strokeIDs) }
    }
    return result
  }
  package var canUndo: Bool { !operations.isEmpty && !isBusy && !isClosed && !sketches.isClosing }
  package var canRedo: Bool { !redoOperations.isEmpty && !isBusy && !isClosed && !sketches.isClosing }
  package var remainingCount: Int { base.program.strokes.count - removed.count }
  package var hasUnsavedChanges: Bool { removed != savedMask }
  package var canSave: Bool { original != nil && Self.supports(base) && remainingCount > 0 && !isBusy && !isClosed && !sketches.isClosing }
  package var canEdit: Bool { original != nil && Self.supports(base) && !isBusy && !isClosed && !sketches.isClosing && !showsOriginal && !showsPhoto }
  package func load() async {
    guard !isClosed else { return }
    guard Self.supports(base) else { error = "Editing unavailable: this drawing requires unsupported features."; return }
    original = base
  }
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
    guard canSave, sketches.selectionEpoch == openingSelectionEpoch else { return false }
    isBusy = true; defer { didSettleSave() }
    outstandingIntentIDs.formUnion([parentIntentID, editID])
    let mask = removed
    let kept = base.program.strokes.map(\.id).filter { !mask.contains($0) }
    do {
      let saved = try await sketches.saveStrokeEdit(base: base, keptStrokeIDs: kept,
        parentIntentID: parentIntentID, editIntentID: editID)
      let obsolete = takeOutstandingIntents()
      if !obsolete.isEmpty { await sketches.discardStrokeEditPreparations(obsolete).value }
      guard !isClosed, !sketches.isClosing, !Task.isCancelled,
        sketches.selectionEpoch == openingSelectionEpoch else { return false }
      savedDrawing = saved; savedMask = mask; error = nil
      return true
    } catch {
      if !isClosed, !Task.isCancelled { self.error = error.localizedDescription }
      return false
    }
  }
}
