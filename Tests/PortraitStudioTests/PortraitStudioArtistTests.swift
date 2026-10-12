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

  @Test("Wide transparent source uses uniform white pad and preserves exact retained source bytes")
  func fixedInputGeometry() throws {
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
    let prepared = try PortraitStudioArtistInput.prepare(data as Data)
    #expect(prepared.source.bytes == data as Data)
    #expect(prepared.squarePNG.pixelWidth == 1024 && prepared.squarePNG.pixelHeight == 1024)
    let metadata = try #require(try JSONSerialization.jsonObject(with: prepared.preparationJSON) as? [String: Any])
    #expect(metadata["uniform_scale"] as? Double == 128)
    #expect(metadata["pad_x"] as? Double == 0)
    #expect(metadata["pad_y"] as? Double == 256)
    #expect(metadata["mask"] as? String == "none-fixed-across-arms")
  }
}
