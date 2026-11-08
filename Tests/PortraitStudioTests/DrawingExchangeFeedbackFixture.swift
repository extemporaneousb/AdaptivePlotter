import Foundation
import DrawingLibrary
import PortraitArtists
import PortraitCore
@testable import PortraitLibrary
import Testing

/// Current synthetic observations only. The producer receipt explicitly names
/// synthetic geometry; it does not claim native rendering or physical evidence.
struct DrawingExchangeFeedbackFixture {
  let library: DrawingLibrary
  let store: FlowPortfolioStore
  let sources: [FlowPortfolioSource]
  let candidates: [[FlowPortfolioCandidate]]

  static func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx09-feedback-" + UUID().uuidString)
  }
  static func make(directory: URL, sourceCount: Int = 1, candidateCount: Int = 3) async throws -> Self {
    let library = DrawingLibrary(directoryURL: directory)
    let store = FlowPortfolioStore(directory: directory, purpose: .validationFixture, library: library)
    try await store.loadRecords()
    var sources: [FlowPortfolioSource] = [], candidates: [[FlowPortfolioCandidate]] = []
    for index in 0..<sourceCount {
      let source = try await store.addSource(data: FlowDojoFixture.image(index + 1), title: "Synthetic source \(index)")
      sources.append(source)
      candidates.append(try await round(store: store, source: source.id, count: candidateCount))
    }
    return .init(library: library, store: store, sources: sources, candidates: candidates)
  }
  static func round(store: FlowPortfolioStore, source: UUID, count: Int = 3) async throws -> [FlowPortfolioCandidate] {
    let recipes = (0..<count).map { slot -> FlowArtistRecipe in
      var values = FlowArtistRecipe.standard.values
      values[0] = Double(slot) / Double(max(1, count))
      return FlowArtistRecipe(values: values)
    }
    let round = try await store.beginRound(sourceID: source, recipes: recipes)
    let program = try FlowPortfolioTests.program()
    let preview = try PortraitDrawingPreview.png(program)
    var result: [FlowPortfolioCandidate] = []
    for slot in 0..<count {
      let production = try StudioDrawingFixture.production(program: program, raster: FlowPortfolioTests.raster)
      result.append(try await store.completeCandidate(roundID: round.id, slot: slot, production: production, previewPNG: preview))
    }
    try await store.finishRound(round.id)
    return result
  }
  static func freezeInputs(_ store: FlowPortfolioStore) async throws
    -> (examples: [FlowArtistExample], rankings: [FlowArtistRanking]) {
    let snapshot = try await store.freezeTrainingSnapshot()
    let inputs = try await store.trainingInputs(snapshotID: snapshot.id)
    return (inputs.examples, inputs.rankings)
  }
  static func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
  }
}

enum DrawingExchangeFeedbackFailure: Error { case boundary }
extension DrawingLibrary {
  func feedbackFault(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let boundary else { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == boundary { throw DrawingExchangeFeedbackFailure.boundary } }
  }
}

final class DrawingFeedbackSecondPublicationFailure: @unchecked Sendable {
  private let lock = NSLock()
  private var publications = 0
  func inspect(_ boundary: LibraryExchangeCatalogBoundary) throws {
    guard boundary == .beforeSQLPublication else { return }
    lock.lock(); publications += 1; let count = publications; lock.unlock()
    if count == 2 { throw DrawingExchangeFeedbackFailure.boundary }
  }
}
extension DrawingLibrary {
  func failFeedbackAfterAuthoredRetention() throws {
    let failure = DrawingFeedbackSecondPublicationFailure()
    let catalog = try commonCatalog()
    catalog.injectFault = { try failure.inspect($0) }
  }
}
