import AppKit
import Foundation
import PortraitCore
import UniformTypeIdentifiers

@MainActor
package enum FlowDojoFiles {
  package static func openPhotoCollection() async -> URL? {
    let panel = NSOpenPanel(); panel.title = "Import Photo Set"
    panel.message = "Choose a photo collection folder containing photo-collection.json and its images. Originals and provenance are retained."
    panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    return await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0 == .OK ? panel.url : nil) } }
  }
  package static func exportDrawing() async -> URL? {
    let panel = NSSavePanel(); panel.title = "Export Drawing"; panel.allowedContentTypes = [.zip]
    panel.nameFieldStringValue = "Drawing.zip"
    return await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0 == .OK ? panel.url : nil) } }
  }
  nonisolated package static func readImage(_ url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard metadata.isRegularFile == true, let size = metadata.fileSize,
      size > 0, size <= DrawingArtifactLimits.sourceBytes else {
      throw DrawingExchangeError.limit("Choose a PNG or JPEG photograph smaller than 32 MiB.")
    }
    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
    guard let bytes = try file.read(upToCount: DrawingArtifactLimits.sourceBytes + 1),
      bytes.count <= DrawingArtifactLimits.sourceBytes else {
      throw DrawingExchangeError.limit("Photograph exceeds 32 MiB.")
    }
    return bytes
  }
}
