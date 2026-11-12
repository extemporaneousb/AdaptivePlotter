import DrawingLibrary
import Foundation
import PortraitCore
import PortraitArtists
import SwiftUI
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Materializes only visible rows. Immutable references key loading and
/// cancellation; browsing never creates a publication or preference event.
package struct DrawingLibraryThumbnail: View {
  package enum Source: Hashable { case photo(PhotoRef), input(ImageInputRef), drawing(DrawingRef) }
  package let library: DrawingLibrary
  package let source: Source
  @State private var pixels: Data?
  @State private var loaded: Source?
  package var body: some View {
    FlowAuthoringImage(data: loaded == source ? pixels : nil, identity: String(describing: source), maximumDimension: 160)
      .background(.white, in: RoundedRectangle(cornerRadius: 3))
      .accessibilityLabel("Thumbnail")
      .task(id: source) {
        pixels = nil; loaded = nil
        do {
          let library = library, requested = source
          let key = "library:" + library.directoryURL.path + ":" + String(describing: requested)
          let data = try await FlowAuthoringThumbnailCache.shared.load(key: key) {
            switch requested {
            case .photo(let ref):
              let photo = try await library.photo(ref)
              guard let asset = photo.assets.first(where: { $0.descriptor.asset == photo.record.original }) else { throw DrawingExchangeError.malformed("Photo original unavailable") }
              return try Self.displayPixels(asset)
            case .input(let ref):
              let input = try await library.input(ref)
              guard let asset = input.assets.first(where: { $0.descriptor.asset == input.record.raster }) else { throw DrawingExchangeError.malformed("Input raster unavailable") }
              return try Self.displayPixels(asset)
            case .drawing(let ref):
              let drawing = try await library.drawing(ref)
              try drawing.capabilities.require(.preview)
              return try PortraitDrawingPreview.png(drawing.program)
            }
          }
          guard !Task.isCancelled else { return }
          pixels = data; loaded = source
        } catch { /* An unavailable original remains an explicit empty thumbnail. */ }
      }
  }
  nonisolated package static func displayPixels(_ asset: DrawingImageAsset) throws -> Data {
    let width: Int, height: Int, rowBytes: Int, pixels: Data
    switch asset.descriptor.asset.encoding {
    case "raw-gray8":
      guard let layout = asset.descriptor.pixelLayout, layout.supportedSemantics,
        layout.pixelFormat == "gray", layout.orientation == "up" else {
        throw DrawingExchangeError.unsupportedFeature("Thumbnail raw raster layout")
      }
      try layout.validate(asset.bytes)
      width = layout.width; height = layout.height; rowBytes = layout.rowStride; pixels = asset.bytes
    case "array-float64":
      guard let layout = asset.descriptor.arrayLayout, let dimensions = asset.descriptor.dimensions,
        layout.dtype == "float64", layout.layout == "row-major", layout.byteOrder == "little",
        layout.units == "normalized-luminance", layout.shape == [dimensions.height, dimensions.width],
        dimensions.width > 0, dimensions.height > 0,
        dimensions.width <= DrawingArtifactLimits.maximumImageDimension,
        dimensions.height <= DrawingArtifactLimits.maximumImageDimension,
        dimensions.width <= DrawingArtifactLimits.maximumImagePixels / dimensions.height,
        try layout.validate(asset.bytes) else {
        throw DrawingExchangeError.unsupportedFeature("Thumbnail luminance array layout")
      }
      width = dimensions.width; height = dimensions.height; rowBytes = width
      var gray = [UInt8](repeating: 0, count: try layout.elementCount())
      try asset.bytes.withUnsafeBytes { source in
        for index in gray.indices {
          let bits = UInt64(littleEndian: source.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self))
          let value = Double(bitPattern: bits)
          guard value.isFinite, (0...1).contains(value) else {
            throw DrawingExchangeError.malformed("Thumbnail luminance must be finite and normalized")
          }
          gray[index] = UInt8((value * 255).rounded())
        }
      }
      pixels = Data(gray)
    default: return asset.bytes
    }
    guard let provider = CGDataProvider(data: pixels as CFData),
      let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
        bytesPerRow: rowBytes, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
      throw DrawingExchangeError.malformed("Preview raster")
    }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
      throw DrawingExchangeError.malformed("Preview encoding")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingExchangeError.malformed("Preview encoding") }
    return data as Data
  }
}
