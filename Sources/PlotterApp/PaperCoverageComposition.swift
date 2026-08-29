import Foundation
import PlotterEpisodeRuntime
import PlotterRuntime

private actor UserDefaultsDrawingDraftPaperPersistence:
  PlotterDrawingDraftPaperPersistence
{
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "AdaptivePlotter.paper.coverage-observation.v1"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> PaperCoverageObservation? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(PaperCoverageObservation.self, from: data)
  }

  func save(_ observation: PaperCoverageObservation) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    defaults.set(try encoder.encode(observation), forKey: key)
  }

  func clear() {
    defaults.removeObject(forKey: key)
  }
}

enum PaperCoverageComposition {
  private static let paperPersistence = UserDefaultsDrawingDraftPaperPersistence()

  static let drawingDraftRuntime = PlotterDrawingDraftRuntime(
    paperPersistence: paperPersistence
  )
}
