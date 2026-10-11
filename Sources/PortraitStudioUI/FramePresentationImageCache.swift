import CoreGraphics
import PlotterModel
import PlotterRuntime
import PortraitArtists
import SwiftUI

package struct FramePresentationIdentity: Hashable, Sendable {
  package let frameID: FrameID
  package let cameraConfigurationID: CameraConfigurationID

  package init(_ frame: StampedFrame) {
    frameID = frame.id
    cameraConfigurationID = frame.cameraConfigurationID
  }
}

/// A one-entry presentation cache. Frame identity is the evidence boundary:
/// the same frame/configuration pair denotes the same immutable canonical
/// bytes. Keeping only the current image bounds memory as live frames advance.
@MainActor
package final class FramePresentationImageCache: ObservableObject {
  package init() {}

  private var cachedIdentity: FramePresentationIdentity?
  private var cachedImage: CGImage?
  package private(set) var conversionCount = 0

  package var cachedEntryCount: Int { cachedIdentity == nil ? 0 : 1 }

  package func image(from frame: StampedFrame) -> CGImage? {
    let identity = FramePresentationIdentity(frame)
    if identity == cachedIdentity {
      return cachedImage
    }

    let image = FrameImageFactory.image(from: frame)
    cachedIdentity = identity
    cachedImage = image
    conversionCount += 1
    return image
  }
}
