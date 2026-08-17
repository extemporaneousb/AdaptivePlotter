import Foundation
import PlotterRuntime

enum PaperCoverageComposition {
  private static let key = "AdaptivePlotter.paper.coverage-observation.v1"

  static let actions = OperatorWorkspace.PaperCoverageActions(
    load: {
      guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
      return try? JSONDecoder().decode(PaperCoverageObservation.self, from: data)
    },
    save: { observation in
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      UserDefaults.standard.set(try encoder.encode(observation), forKey: key)
    },
    clear: {
      UserDefaults.standard.removeObject(forKey: key)
    }
  )
}
