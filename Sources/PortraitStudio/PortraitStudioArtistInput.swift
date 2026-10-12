import CoreGraphics
import Foundation
import ImageIO
import PortraitCore
import UniformTypeIdentifiers

struct PortraitStudioArtistInput: Sendable {
  let source: DrawingPackageAsset
  let squarePNG: DrawingPackageAsset
  let preparationJSON: Data

  static func imageAsset(_ bytes: Data) throws -> DrawingPackageAsset {
    guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      throw DrawingTransferError.invalid("Worker image dimensions could not be verified.")
    }
    let asset = DrawingPackageAsset(mediaType: "image/png", bytes: bytes, pixelWidth: width, pixelHeight: height)
    try asset.validate(maximumBytes: DrawingTransferLimits.inputBytes, requireImage: true)
    return asset
  }

  /// Full retained source, EXIF-oriented, uniform white square pad. The paired
  /// LUT runs later on these fixed bytes; there is no per-arm face mask.
  static func prepare(_ bytes: Data) throws -> Self {
    try Task.checkCancellation()
    guard bytes.count <= DrawingTransferLimits.sourceBytes,
      let source = CGImageSourceCreateWithData(bytes as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let originalWidth = properties[kCGImagePropertyPixelWidth] as? Int,
      let originalHeight = properties[kCGImagePropertyPixelHeight] as? Int,
      originalWidth > 0, originalHeight > 0,
      originalWidth <= DrawingTransferLimits.maximumImageDimension,
      originalHeight <= DrawingTransferLimits.maximumImageDimension,
      originalWidth <= DrawingTransferLimits.maximumImagePixels / originalHeight,
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: max(originalWidth, originalHeight)
      ] as CFDictionary),
      let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: 1024, height: 1024,
        bitsPerComponent: 8, bytesPerRow: 1024 * 4, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DrawingTransferError.invalid("The retained source cannot be decoded within the image bounds.")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    context.interpolationQuality = .high
    let scale = 1024 / Double(max(image.width, image.height))
    let width = Double(image.width) * scale, height = Double(image.height) * scale
    let x = (1024 - width) / 2, y = (1024 - height) / 2
    context.draw(image, in: CGRect(x: x, y: y, width: width, height: height))
    guard let prepared = context.makeImage() else { throw DrawingTransferError.invalid("Source preparation failed.") }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
      throw DrawingTransferError.invalid("Prepared source could not be encoded.")
    }
    CGImageDestinationAddImage(destination, prepared, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingTransferError.invalid("Prepared PNG encoding failed.") }
    let isPNG = bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10])
    let sourceAsset = DrawingPackageAsset(mediaType: isPNG ? "image/png" : "image/jpeg", bytes: bytes,
      pixelWidth: originalWidth, pixelHeight: originalHeight)
    let square = DrawingPackageAsset(mediaType: "image/png", bytes: output as Data, pixelWidth: 1024, pixelHeight: 1024)
    let metadata = try JSONSerialization.data(withJSONObject: [
      "revision": "studio-full-source-srgb-square-v1", "color_space": "sRGB",
      "orientation": "EXIF-applied", "crop": "full-oriented-source", "mask": "none-fixed-across-arms",
      "original_exif_orientation": properties[kCGImagePropertyOrientation] as? Int ?? 1,
      "original_exif_orientation_present": properties[kCGImagePropertyOrientation] != nil,
      "original_encoded_type": CGImageSourceGetType(source) as String? ?? "unknown",
      "original_profile_name": properties[kCGImagePropertyProfileName] as? String ?? "unknown",
      "profile_policy": "ImageIO decode to explicit sRGB; absent source profile remains unknown",
      "native_os": ProcessInfo.processInfo.operatingSystemVersionString,
      "native_build_identifier": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      "source_width": originalWidth, "source_height": originalHeight,
      "oriented_width": image.width, "oriented_height": image.height,
      "target_width": 1024, "target_height": 1024, "uniform_scale": scale,
      "pad_x": x, "pad_y": y, "alpha_background": "white"
    ], options: [.sortedKeys])
    return .init(source: sourceAsset, squarePNG: square, preparationJSON: metadata)
  }
}
