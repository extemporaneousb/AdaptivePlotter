import Foundation
import Observation
import DrawingLibrary
import PortraitCore
import PortraitLibrary

/// Plotter owns immutable received inputs and execution history. Authoring and
/// source-photo selection belong to the separate Portrait Studio application.
@Observable @MainActor
final class ReceivedDrawingStore {
  let library: DrawingLibrary
  let sketches: PortraitSketchCollection
  private(set) var projectedDrawing: Drawing?
  private(set) var selectionEpoch: UInt64 = 0
  private var closed = false
  private let selectionDefaults: UserDefaults?
  private let selectionKey: String
  private(set) var restoredReference: DrawingRef?

  init(library: DrawingLibrary = DrawingLibrary(directoryURL: DrawingLibrary.defaultDirectoryURL), selectionDefaults: UserDefaults? = nil) {
    self.library = library
    self.selectionDefaults = selectionDefaults
    selectionKey = "AdaptivePlotter.receivedDrawing.v1." + library.directoryURL.standardizedFileURL.path
    if let data = selectionDefaults?.data(forKey: selectionKey) {
      restoredReference = try? JSONDecoder().decode(DrawingRef.self, from: data)
    }
    sketches = PortraitSketchCollection(library: library)
  }

  func projectDrawing(_ drawing: Drawing, isStillCurrent: @MainActor () -> Bool = { true }) async throws {
    guard !closed, !Task.isCancelled, isStillCurrent(), let ref = drawing.reference else { throw CancellationError() }
    selectionEpoch &+= 1
    let epoch = selectionEpoch, collection = sketches.selectionEpoch
    let exact = try await library.drawing(ref)
    guard !closed, !Task.isCancelled, isStillCurrent(), selectionEpoch == epoch,
      sketches.selectionEpoch == collection else { throw CancellationError() }
    guard exact.reference == ref, exact.program == drawing.program else { throw DrawingExchangeError.mismatchedParent }
    try sketches.selectLoaded(exact)
    projectedDrawing = exact
    restoredReference = ref
    if let data = try? DrawingArtifactCoding.encoder().encode(ref) { selectionDefaults?.set(data, forKey: selectionKey) }
    selectionEpoch &+= 1
  }

  func clearDrawingSelection() {
    selectionEpoch &+= 1; projectedDrawing = nil; sketches.clearSelection()
    restoredReference = nil; selectionDefaults?.removeObject(forKey: selectionKey)
  }

  func receiveForInspection(_ drawing: Drawing, isStillCurrent: @MainActor () -> Bool = { true }) async throws -> Drawing {
    let retained = try await sketches.retain(drawing, reason: "received")
    try await projectDrawing(retained, isStillCurrent: isStillCurrent)
    return retained
  }

  func shutdown() async { closed = true; selectionEpoch &+= 1; await sketches.shutdown() }
}
