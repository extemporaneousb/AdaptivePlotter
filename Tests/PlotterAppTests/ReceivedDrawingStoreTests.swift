import DrawingLibrary
import Foundation
import PortraitCore
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Immutable received Drawing selection")
@MainActor
struct ReceivedDrawingStoreTests {
  @Test("Cold reopen restores the exact occurrence independently of identical geometry")
  func exactReopen() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("received-reopen-" + UUID().uuidString)
    let suite = "received-reopen-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    let library = DrawingLibrary(directoryURL: root)
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(UUID()))
    let produced = try await CatalogDrawingProducer().produce(input: .square, settings: .init(style: style))
    let first = try await library.retain(produced.drawing, reason: "first occurrence").reference
    let second = try await library.retain(produced.drawing, reason: "second occurrence").reference
    #expect(first != second)
    let selected = try await library.drawing(first)
    let store = ReceivedDrawingStore(library: library, selectionDefaults: defaults)
    try await store.projectDrawing(selected)
    await store.shutdown(); await library.closeLibrary()
    let reopenedLibrary = DrawingLibrary(directoryURL: root)
    let reopened = ReceivedDrawingStore(library: reopenedLibrary, selectionDefaults: defaults)
    #expect(reopened.restoredReference == first)
    let exact = try await reopenedLibrary.drawing(try #require(reopened.restoredReference))
    try await reopened.projectDrawing(exact)
    #expect(reopened.projectedDrawing?.reference == first)
    #expect(reopened.projectedDrawing?.program == selected.program)
    await reopened.shutdown(); await reopenedLibrary.closeLibrary()
  }
}
