import Foundation
import Observation
import PlotterModel
import PortraitCore
import PortraitLibrary

@Observable @MainActor
package final class PortraitLineEditModel {
  package enum Tool: String, CaseIterable { case erase = "Click to Delete", lasso = "Lasso", restore = "Restore" }
  package let base: SavedDrawing
  private let sketches: PortraitSketchCollection
  package private(set) var original: DrawingPackage?
  private var originalBytes = Data()
  private var baseOrigin: DrawingOriginReference?
  private var initialRemoved: [StrokeID] = []
  private var exerciseContext: DrawingStrokeSelection.ExerciseContext?
  private var isGeneratedExercise = false
  package private(set) var operations: [DrawingStrokeSelection.Operation] = []
  package var batches: [[StrokeID]] { operations.filter { $0.action == .remove }.map(\.strokeIDs) }
  private var redoOperations: [DrawingStrokeSelection.Operation] = []
  package var selection: Set<StrokeID> = []
  package var tool: Tool = .erase
  package var showsOriginal = false
  package var showsPhoto = false
  package var zoom = 1.0
  package private(set) var isBusy = false
  package var error: String?
  package private(set) var savedDrawing: SavedDrawing?
  private var savedMask: Set<StrokeID> = []
  private var editID = UUID()
  private var editDate = Date()

  package init(base: SavedDrawing, sketches: PortraitSketchCollection) {
    self.base = base; self.sketches = sketches
  }

  package static func supports(_ drawing: SavedDrawing) -> Bool {
    drawing.portraitCandidate?.recipe.style == .flowEdges
      || drawing.transferredPackage.map {
        $0.artist.identifier == "adaptiveplotter.Flow Edge"
          || $0.artist.identifier == DrawingStrokeSelection.artistIdentifier
      } == true
  }

  package var removed: Set<StrokeID> {
    var value = Set(initialRemoved)
    for operation in operations {
      if operation.action == .remove { value.formUnion(operation.strokeIDs) }
      else { value.subtract(operation.strokeIDs) }
    }
    return value
  }
  package var canUndo: Bool { !operations.isEmpty && !isBusy }
  package var canRedo: Bool { !redoOperations.isEmpty && !isBusy }
  package var remainingCount: Int { (original?.program.strokes.count ?? 0) - removed.count }
  package var hasUnsavedChanges: Bool { original != nil && removed != savedMask }
  package var canSave: Bool {
    original != nil && remainingCount > 0 && !isBusy
      && (hasUnsavedChanges || (isGeneratedExercise && savedDrawing == nil))
  }
  package var canEdit: Bool { original != nil && !isBusy && !showsOriginal && !showsPhoto }

  package func load() async {
    guard original == nil, !isBusy else { return }
    isBusy = true; error = nil
    defer { isBusy = false }
    do {
      guard Self.supports(base) else { throw DrawingTransferError.invalid("Choose a Flow Edge drawing to edit lines.") }
      let bytes = try await sketches.exportDrawingPackage(base)
      let package = try DrawingPackageCodec.decode(bytes)
      let prior = try DrawingStrokeSelection.record(in: package)
      originalBytes = prior?.originalPackageJSON ?? bytes
      let root = try DrawingPackageCodec.decode(originalBytes)
      guard root.artist.identifier == "adaptiveplotter.Flow Edge", root.legacyCandidateJSON != nil else {
        throw DrawingTransferError.invalid("This drawing has no native Flow Edge original.")
      }
      original = root; baseOrigin = package.origin
      initialRemoved = prior?.removedStrokeIDs ?? []
      exerciseContext = prior?.exerciseContext
      isGeneratedExercise = prior?.operationSource == .exerciseProposal
      savedMask = Set(initialRemoved)
    } catch { self.error = error.localizedDescription }
  }

  package func remove(_ ids: Set<StrokeID>) {
    guard canEdit, let original else { return }
    let current = removed
    let batch = original.program.strokes.map(\.id).filter { ids.contains($0) && !current.contains($0) }
    guard !batch.isEmpty else { return }
    guard let target = validatedMembership(current.union(batch), in: original.program) else { return }
    let admittedBatch = original.program.strokes.map(\.id).filter { target.contains($0) && !current.contains($0) }
    operations.append(.init(action: .remove, strokeIDs: admittedBatch))
    redoOperations = []; selection.subtract(batch); changed()
  }

  package func restore(_ ids: Set<StrokeID>) {
    guard canEdit, let original else { return }
    let current = removed
    let batch = original.program.strokes.map(\.id).filter { ids.contains($0) && current.contains($0) }
    guard !batch.isEmpty else { return }
    guard let target = validatedMembership(current.subtracting(batch), in: original.program) else { return }
    let admittedBatch = original.program.strokes.map(\.id).filter { current.contains($0) && !target.contains($0) }
    operations.append(.init(action: .restore, strokeIDs: admittedBatch))
    redoOperations = []; selection.subtract(batch); changed()
  }

  /// The legacy editor permits an empty, unsavable draft. Every nonempty
  /// selection passes the shared stable-ID engine before becoming edit state.
  private func validatedMembership(_ removed: Set<StrokeID>, in universe: DrawingProgram) -> Set<StrokeID>? {
    let ids = universe.strokes.map(\.id).filter { !removed.contains($0) }
    if ids.isEmpty { return Set(universe.strokes.map(\.id)) }
    if ids.count == universe.strokes.count { return [] }
    do {
      let kept = try DrawingStrokeMembership.apply(.membership(ids), to: universe, universe: universe)
      return Set(universe.strokes.map(\.id)).subtracting(kept.map(\.id))
    } catch { self.error = error.localizedDescription; return nil }
  }

  package func undo() {
    guard canUndo, let operation = operations.popLast() else { return }
    redoOperations.append(operation); selection = []; changed()
  }

  package func redo() {
    guard canRedo, let operation = redoOperations.popLast() else { return }
    operations.append(operation); selection = []; changed()
  }

  private func changed() { editID = UUID(); editDate = Date(); error = nil }

  @discardableResult package func save() async -> Bool {
    guard canSave, let baseOrigin else { return false }
    isBusy = true; error = nil
    defer { isBusy = false }
    do {
      let record = try DrawingStrokeSelection(editID: editID, createdAt: editDate,
        originalPackageJSON: originalBytes, baseOrigin: baseOrigin,
        baseProgram: base.program,
        initialRemovedStrokeIDs: initialRemoved, operations: operations, exerciseContext: exerciseContext)
      savedDrawing = try await sketches.saveStrokeSelection(record, base: base)
      savedMask = removed
      return true
    } catch { self.error = error.localizedDescription; return false }
  }
}
