import CoreGraphics
import Foundation
import ImageIO
import PortraitCore
import Testing
import UniformTypeIdentifiers
@testable import PortraitStudio

@Suite("Standalone experimental artist preparation")
struct PortraitStudioArtistTests {
  @Test("Missing or relative runtime configuration stays unavailable")
  func explicitLocalConfiguration() {
    #expect(PortraitStudioArtistModel.localConfiguration(environment: [:], installedRuntime: nil) == nil)
    #expect(PortraitStudioArtistModel.localConfiguration(environment: [
      "PORTRAIT_SWIFTSKETCH_PYTHON": "relative-python",
      "PORTRAIT_SWIFTSKETCH_WORKER": "/local/worker.py",
      "PORTRAIT_SWIFTSKETCH_MANIFEST": "/local/manifest.json",
      "PORTRAIT_SWIFTSKETCH_PROOF": "/local/proof.json"
    ]) == nil)
    let config = PortraitStudioArtistModel.localConfiguration(environment: [
      "PORTRAIT_SWIFTSKETCH_PYTHON": "/local/python",
      "PORTRAIT_SWIFTSKETCH_WORKER": "/local/worker.py",
      "PORTRAIT_SWIFTSKETCH_MANIFEST": "/local/manifest.json",
      "PORTRAIT_SWIFTSKETCH_PROOF": "/local/proof.json",
      "PORTRAIT_SWIFTSKETCH_ATTEMPTS": "/local/attempts"
    ])
    #expect(config?.timeoutSeconds == 600)
    #expect(config?.attemptRoot.path == "/local/attempts")
  }

  @Test("An image without a confident face cannot silently become a full-source model input")
  func refusesMissingFace() throws {
    let pixels = Data(repeating: 0, count: 8 * 4 * 4)
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let source = try #require(CGImage(width: 8, height: 4, bitsPerComponent: 8,
      bitsPerPixel: 32, bytesPerRow: 8 * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, source, nil)
    #expect(CGImageDestinationFinalize(destination))
    #expect(throws: DrawingTransferError.unavailable(
      "No confident face was detected. Supply an explicit oriented face rectangle.")) {
        try PortraitStudioArtistInput.prepare(data as Data, faceDetector: { _ in [] })
    }
  }
}
