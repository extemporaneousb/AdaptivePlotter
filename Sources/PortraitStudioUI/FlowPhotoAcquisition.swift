import Foundation
import PortraitArtists
import PortraitCore
import PortraitLibrary

package struct FlowPhotoAcquisitionResult: Sendable {
  package var photos: [PhotoRef] = []
  package var failures: [String] = []
  package var adopted: PhotoRef?
  package var presentationIsCurrent: @Sendable @MainActor () -> Bool
  package init(photos: [PhotoRef] = [], failures: [String] = [], adopted: PhotoRef? = nil, presentationIsCurrent: @escaping @Sendable @MainActor () -> Bool = { false }) {
    self.photos = photos; self.failures = failures; self.adopted = adopted; self.presentationIsCurrent = presentationIsCurrent
  }
}

/// Shared production orchestration. Closures expose acquisition boundaries to
/// offscreen tests without opening a picker or camera.
@MainActor package enum FlowPhotoAcquisition {
  package static func capture(model: FlowAuthoringModel,
    isStillCurrent: @escaping @MainActor () -> Bool = { true },
    capture: @MainActor () async -> PortraitPhoto?) async -> FlowPhotoAcquisitionResult {
    let intent = model.beginPhotoAcquisition(isStillCurrent: isStillCurrent)
    guard let photo = await capture() else { return .init() }
    if Task.isCancelled, model.acquisitionIsCurrent(intent) { model.invalidatePhotoAcquisition() }
    // A produced immutable acquisition is retained even when its view vanished
    // or the capture Task was cancelled after the callback became available.
    return await model.addCapturedPhoto(photo, title: model.nextPhotoTitle(capturedAt: photo.capturedAt), intent: intent)
  }

  package static func importPhotos(model: FlowAuthoringModel, multiple: Bool,
    isStillCurrent: @escaping @MainActor () -> Bool = { true },
    pick: @MainActor (Bool) async -> [URL] = FlowAuthoringFiles.openPhotos,
    read: @escaping @Sendable (URL) async throws -> Data = { url in
      try await Task.detached { try FlowAuthoringFiles.readImage(url) }.value
    },
    loadCollection: @escaping @Sendable (URL) async throws -> FlowPhotoCollection = { try await FlowPhotoAcquisition.loadCollection($0) },
    isCollection: (URL) -> Bool = { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }) async -> FlowPhotoAcquisitionResult {
    let intent = model.beginPhotoAcquisition(isStillCurrent: isStillCurrent)
    let urls = await pick(multiple)
    var result = FlowPhotoAcquisitionResult(presentationIsCurrent: { model.photoAcquisitionOwnsPresentation(intent) })
    for url in urls {
      let imported: FlowPhotoAcquisitionResult
      if isCollection(url) {
        imported = await model.importPhotoCollection(url, intent: intent, adopting: false, load: loadCollection)
      } else {
        do {
          imported = await model.addPhoto(data: try await read(url), title: url.deletingPathExtension().lastPathComponent,
            mediaType: url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg", intent: intent, adopting: false)
        } catch {
          result.failures.append(url.lastPathComponent + ": " + error.localizedDescription)
          continue
        }
      }
      result.photos += imported.photos
      result.failures += imported.failures.map { url.lastPathComponent + ": " + $0 }
    }
    if Task.isCancelled, model.acquisitionIsCurrent(intent) { model.invalidatePhotoAcquisition() }
    if let reference = result.photos.last {
      let adoption = await model.adoptRetainedPhoto(reference, intent: intent)
      result.adopted = adoption.adopted; result.failures += adoption.failures
    }
    return result
  }

  nonisolated package static func loadCollection(_ directory: URL) async throws -> FlowPhotoCollection {
    try await Task.detached {
      let scoped = directory.startAccessingSecurityScopedResource()
      defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
      return try FlowPhotoCollection.load(directory: directory)
    }.value
  }
}

package enum FlowAuthoringPublicationBoundary: Equatable {
  case roundBegan(UUID)
  case candidateAdmitted(UUID)
  case terminalRefresh(UUID)
  case snapshotRead(UUID?)
  case candidateRead(UUID)
}
