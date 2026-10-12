import AppKit
import Foundation
import PortraitCore
import UniformTypeIdentifiers

/// File panels are presentation only; codecs and the library own admission.
@MainActor
final class PortraitStudioFiles {
  private var panel: NSSavePanel?

  func cancel() { panel?.cancel(nil) }

  func chooseImport(title: String) async -> URL? {
    guard panel == nil, !Task.isCancelled else { return nil }
    let chooser = NSOpenPanel()
    chooser.title = title
    chooser.allowedContentTypes = [.json]
    chooser.allowsMultipleSelection = false
    chooser.canChooseDirectories = false
    panel = chooser
    defer { panel = nil }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        chooser.begin { response in
          continuation.resume(returning: response == .OK ? chooser.url : nil)
        }
      }
    } onCancel: {
      Task { @MainActor in chooser.cancel(nil) }
    }
  }

  func chooseExport(name: String) async -> URL? {
    guard panel == nil, !Task.isCancelled else { return nil }
    let chooser = NSSavePanel()
    chooser.title = "Export Drawing"
    chooser.allowedContentTypes = [.json]
    chooser.nameFieldStringValue = name
    panel = chooser
    defer { panel = nil }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        chooser.begin { response in
          continuation.resume(returning: response == .OK ? chooser.url : nil)
        }
      }
    } onCancel: {
      Task { @MainActor in chooser.cancel(nil) }
    }
  }

  func chooseReviewDatasetExport() async -> URL? {
    guard panel == nil, !Task.isCancelled else { return nil }
    let chooser = NSSavePanel()
    chooser.title = "Export Review Dataset Folder"
    chooser.nameFieldStringValue = "PortraitReviewExport"
    chooser.canCreateDirectories = true
    panel = chooser
    defer { panel = nil }
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        chooser.begin { response in
          continuation.resume(returning: response == .OK ? chooser.url : nil)
        }
      }
    } onCancel: {
      Task { @MainActor in chooser.cancel(nil) }
    }
  }

  nonisolated static func read(_ url: URL, maximumBytes: Int) throws -> Data {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    let metadata = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
    guard metadata.isRegularFile == true, let size = metadata.fileSize, size <= maximumBytes else {
      throw DrawingTransferError.limit("The selected file exceeds the transfer size limit or is not a regular file.")
    }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var bytes = Data()
    // Check before allocating and bound every read, including a file that grows
    // after its metadata was inspected. Never read unbounded Data(contentsOf:).
    while true {
      try Task.checkCancellation()
      let chunk = try file.read(upToCount: min(1024 * 1024, maximumBytes - bytes.count + 1)) ?? Data()
      guard !chunk.isEmpty else { return bytes }
      guard chunk.count <= maximumBytes - bytes.count else {
        throw DrawingTransferError.limit("The selected file exceeds the transfer size limit.")
      }
      bytes.append(chunk)
    }
  }

  nonisolated static func write(_ data: Data, to url: URL) throws {
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    try Task.checkCancellation()
    try data.write(to: url, options: .atomic)
  }
}
