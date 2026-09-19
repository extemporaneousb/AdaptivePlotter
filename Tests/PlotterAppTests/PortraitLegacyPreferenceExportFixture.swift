import Foundation
import Observation
@testable import PlotterApp

enum PortraitPreferenceError: LocalizedError {
  case emptyCollection
  var errorDescription: String? { "Rate a completed portrait before exporting examples." }
}

@Observable @MainActor
final class LegacyPortraitPreferenceExportFixture {
  let collection: PortraitSketchCollection
  init(collection: PortraitSketchCollection) { self.collection = collection }

  var examples: [PortraitPreferenceExample] {
    let withdrawn = collection.archive.withdrawnLabelIDs
    let candidates = Dictionary(uniqueKeysWithValues: collection.entries.map { ($0.id, $0.candidate) })
    return collection.labels.compactMap { label in
      guard !withdrawn.contains(label.id.uuidString), let candidate = candidates[label.candidateID] else { return nil }
      return PortraitPreferenceExample(candidate: candidate, label: label)
    }
  }

  var retainedBytes: Int { collection.retainedBytes }

  func remove(_ id: UUID) { collection.withdrawLabel(id) }

  func exportData() throws -> Data { try Self.exportData(examples: examples) }

  nonisolated static func exportData(examples: [PortraitPreferenceExample]) throws -> Data {
    guard !examples.isEmpty else { throw PortraitPreferenceError.emptyCollection }
    return try PortraitCandidateCoding.encoder().encode(PortraitPreferenceExport(examples: examples))
  }
}
