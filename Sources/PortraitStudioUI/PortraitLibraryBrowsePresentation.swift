import Foundation
import PortraitLibrary

package enum PortraitLibraryBrowsePresentation {
  package static func captureDescription(_ photo: PortraitLibraryPhoto) -> String {
    photo.actualCapturedAt.map { $0.formatted(date: .abbreviated, time: .shortened) }
      ?? "Capture time unknown"
  }
}
