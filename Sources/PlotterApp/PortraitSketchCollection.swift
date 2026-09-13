import Foundation
import Observation
import PlotterModel

struct PortraitSavedSketch: Identifiable {
  let id: UUID
  let program: DrawingProgram
  let title: String
  let photoID: UUID?
  let recipe: PortraitStyleRecipe?
}

/// Session-only comparisons retain immutable vectors, never extra raw photos.
@Observable @MainActor
final class PortraitSketchCollection {
  static let maximumCount = 8
  static let maximumPointCount = 200_000
  private(set) var sketches: [PortraitSavedSketch] = []
  var selectedID: UUID?
  var selected: PortraitSavedSketch? { sketches.first { $0.id == selectedID } }

  @discardableResult
  func keep(_ program: DrawingProgram, title: String, photoID: UUID? = nil, recipe: PortraitStyleRecipe? = nil) -> String? {
    if let existing = sketches.first(where: { $0.program.contentHash == program.contentHash && $0.photoID == photoID && $0.recipe == recipe }) {
      selectedID = existing.id
      return nil
    }
    let points = program.strokes.reduce(0) { $0 + $1.path.points.count }
    guard points <= Self.maximumPointCount else {
      return "This sketch is too detailed to keep. Increase simplification or reduce tonal levels."
    }
    let sketch = PortraitSavedSketch(id: UUID(), program: program, title: title, photoID: photoID, recipe: recipe)
    sketches.append(sketch)
    while sketches.count > Self.maximumCount || sketches.reduce(0, { total, item in
      total + item.program.strokes.reduce(0) { $0 + $1.path.points.count }
    }) > Self.maximumPointCount {
      sketches.removeFirst()
    }
    selectedID = sketch.id
    return nil
  }

  func remove(_ id: UUID) {
    sketches.removeAll { $0.id == id }
    if selectedID == id { selectedID = nil }
  }
}
