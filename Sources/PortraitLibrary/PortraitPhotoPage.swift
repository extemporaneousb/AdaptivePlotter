import PortraitArtists
import Foundation
import PlotterRuntime

/// Advisory browse state. It cannot be submitted to the archive writer.
package struct PortraitPhotoPage: Sendable {
  package let photos: [PortraitPhotoReference]
  package let next: PortraitPhotoPageCursor?
  package let savedStyles: [PortraitSavedStyle]
  package let candidateRecordsRead: Int

  package init(
    photos: [PortraitPhotoReference],
    next: PortraitPhotoPageCursor? = nil,
    savedStyles: [PortraitSavedStyle],
    candidateRecordsRead: Int
  ) {
    self.photos = photos
    self.next = next
    self.savedStyles = savedStyles
    self.candidateRecordsRead = candidateRecordsRead
  }
}

package struct PortraitPhotoPageCursor: Sendable {
  package let indexState: VerifiedFileState
  package var sourceOffset = 0
  package var candidateOffset = 0
  package var seen = Set<UUID>()

  package init(
    indexState: VerifiedFileState,
    sourceOffset: Int = 0,
    candidateOffset: Int = 0,
    seen: Set<UUID> = Set<UUID>()
  ) {
    self.indexState = indexState
    self.sourceOffset = sourceOffset
    self.candidateOffset = candidateOffset
    self.seen = seen
  }
}

package enum PortraitPhotoBrowserError: Error, LocalizedError {
  case archiveChanged, sourceUnavailable
  package var errorDescription: String? {
    switch self {
    case .archiveChanged: "Photo history changed. Reload the photo list."
    case .sourceUnavailable: "This retained source is no longer available."
    }
  }
}

package struct PortraitPhotoListItem: Identifiable {
  package let id: UUID
  package let label: String

  package init(id: UUID, label: String) {
    self.id = id
    self.label = label
  }
}
