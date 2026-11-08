import Foundation
import Observation
import PortraitCore
import DrawingLibrary
import SwiftUI

package enum DrawingWorkspace: String, Codable, CaseIterable, Sendable {
  case library, drawingStudio, plotter
  package var title: String {
    switch self { case .library: "Library"; case .drawingStudio: "Drawing Studio"; case .plotter: "Plotter" }
  }
}
package enum DrawingLibraryCollection: String, Codable, Hashable, Sendable { case photos, drawings, children }
package struct DrawingLibraryScopeKey: Hashable, Sendable {
  let collection: DrawingLibraryCollection
  let photo: PhotoRef?
  let input: ImageInputRef?
  let parent: DrawingRef?
}

/// A persisted navigation intent. The borrowed sketch collection owns the loaded
/// Drawing; this bookmark never substitutes a value or repairs an exact ref.
package struct DrawingLibraryRoute: Codable, Equatable, Sendable {
  package var workspace: DrawingWorkspace = .library
  package var photo: PhotoRef?
  package var input: ImageInputRef?
  package var drawing: DrawingRef?
  package var collection: DrawingLibraryCollection?
  package var branchParent: DrawingRef?
  package var activeCollection: DrawingLibraryCollection { collection ?? .photos }
  package mutating func showDrawing(_ reference: DrawingRef) {
    collection = .drawings; photo = nil; input = nil; branchParent = nil; drawing = reference
  }
  @discardableResult package mutating func selectPhoto(_ reference: PhotoRef?) -> Bool {
    guard photo != reference else { return false }
    collection = .photos; photo = reference; input = nil; drawing = nil; branchParent = nil
    return true
  }
  package init() {}
  package static func restored(_ data: Data) -> Self { (try? JSONDecoder().decode(Self.self, from: data)) ?? .init() }
  package var encoded: Data { (try? JSONEncoder().encode(self)) ?? Data() }
  package var scopeKey: DrawingLibraryScopeKey {
    .init(collection: activeCollection, photo: photo, input: input, parent: branchParent)
  }
  package func validatedScope(in library: DrawingLibrary) async throws -> DrawingLibraryDrawingScope {
    if activeCollection == .drawings { return .all }
    if activeCollection == .children {
      guard let branchParent else { throw DrawingLibraryError.invalidQuery }
      _ = try await library.drawing(branchParent)
      return .children(branchParent)
    }
    if let input {
      let prepared = try await library.input(input)
      if let photo, prepared.photo.reference != photo { throw DrawingExchangeError.mismatchedParent }
      return .input(input)
    }
    return photo.map(DrawingLibraryDrawingScope.photo) ?? .all
  }
  package func validate(_ value: Drawing, in library: DrawingLibrary) async throws {
    if activeCollection == .drawings { return }
    if activeCollection == .children {
      guard let branchParent, value.parent == .present(branchParent) else { throw DrawingExchangeError.mismatchedParent }
      return
    }
    if let input {
      guard value.input == .present(input) else { throw DrawingExchangeError.mismatchedParent }
    } else if let photo {
      guard case .present(let prepared) = value.input,
        try await library.input(prepared).photo.reference == photo else { throw DrawingExchangeError.mismatchedParent }
    }
  }
}

/// Existing projected Stop remains the only execution owner. Native modal
/// pickers cannot cover an actionable Stop; inline editing stays available.
package struct DrawingPresentationPolicy: Sendable {
  package var modalUnavailableReason: String?
  package init(modalUnavailableReason: String? = nil) { self.modalUnavailableReason = modalUnavailableReason }
}
private struct DrawingPresentationPolicyKey: EnvironmentKey {
  static let defaultValue = DrawingPresentationPolicy()
}
extension EnvironmentValues {
  package var drawingPresentationPolicy: DrawingPresentationPolicy {
    get { self[DrawingPresentationPolicyKey.self] }
    set { self[DrawingPresentationPolicyKey.self] = newValue }
  }
}
