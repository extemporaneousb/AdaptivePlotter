import AppKit
import Foundation
import PortraitCore
import UniformTypeIdentifiers

@MainActor
package enum FlowDojoFiles {
  package static func openPortfolio() async -> URL? {
    let panel = NSOpenPanel(); panel.title = "Open Flow Edge Portfolio"
    panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    return await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0 == .OK ? panel.url : nil) } }
  }
  package static func openPhotoCollection() async -> URL? {
    let panel = NSOpenPanel(); panel.title = "Import Photo Set"
    panel.message = "Choose a photo collection folder containing photo-collection.json and its images. Originals and provenance are retained."
    panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
    return await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0 == .OK ? panel.url : nil) } }
  }
  package static func newPortfolio() async -> URL? {
    let panel = NSSavePanel(); panel.title = "New Flow Edge Portfolio"
    panel.nameFieldStringValue = "Artist Portfolio.flowportfolio"; panel.canCreateDirectories = true
    return await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0 == .OK ? panel.url : nil) } }
  }
  package static func exportDrawing() async -> URL? {
    let panel = NSSavePanel(); panel.title = "Export Drawing"; panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Drawing.portraitdrawing.json"
    return await withCheckedContinuation { continuation in panel.begin { continuation.resume(returning: $0 == .OK ? panel.url : nil) } }
  }
  nonisolated package static func readImage(_ url: URL) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard metadata.isRegularFile == true, let size = metadata.fileSize,
      size > 0, size <= DrawingTransferLimits.sourceBytes else {
      throw DrawingTransferError.limit("Choose a PNG or JPEG photograph smaller than 32 MiB.")
    }
    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
    guard let bytes = try file.read(upToCount: DrawingTransferLimits.sourceBytes + 1),
      bytes.count <= DrawingTransferLimits.sourceBytes else {
      throw DrawingTransferError.limit("Photograph exceeds 32 MiB.")
    }
    return bytes
  }
}
