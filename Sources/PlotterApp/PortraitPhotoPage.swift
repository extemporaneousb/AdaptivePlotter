import Foundation
import PlotterRuntime

/// Advisory browse state. It cannot be submitted to the archive writer.
struct PortraitPhotoPage: Sendable {
  let photos: [PortraitPhotoReference]
  let next: PortraitPhotoPageCursor?
  let savedStyles: [PortraitSavedStyle]
  let candidateRecordsRead: Int
}

struct PortraitPhotoPageCursor: Sendable {
  let indexState: VerifiedFileState
  var sourceOffset = 0
  var candidateOffset = 0
  var seen = Set<UUID>()
}

enum PortraitPhotoBrowserError: Error, LocalizedError {
  case archiveChanged, sourceUnavailable
  var errorDescription: String? {
    switch self {
    case .archiveChanged: "Photo history changed. Reload the photo list."
    case .sourceUnavailable: "This retained source is no longer available."
    }
  }
}

struct PortraitPhotoListItem: Identifiable {
  let id: UUID
  let label: String
}
