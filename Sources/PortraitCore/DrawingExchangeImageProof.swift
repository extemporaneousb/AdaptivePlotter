import Foundation
import ImageIO
import CoreGraphics
import zlib

/// A readable encoded header proves bounds/container agreement, never decoded pixels.
/// Decoding is an explicit bounded operation; no carrier admission eagerly decodes media.
public struct ExchangeDecodedImage: Sendable {
  public let pixels: Data
  public let width: Int
  public let height: Int
  public let rowStride: Int
  public let channelOrder: [String]
  public let componentType: String
  public let byteOrder: String
  public let alpha: String
  public let orientationPolicy: String
  public let encodedOrientation: Int?
  public let limitations: [String]
}
public enum ExchangeEncodedImageProof {
  struct Header {
    let source: CGImageSource
    let width: Int
    let height: Int
    let orientation: Int?
    let maximumNativeRowBytes: Int
  }
  static func header(_ descriptor: ExchangeAssetDescriptor, files: VerifiedExchangeFiles) throws -> Header? {
    let asset = descriptor.asset
    guard ["png", "jpeg", "jpg"].contains(asset.encoding) else { return nil }
    guard asset.mediaType == (asset.encoding == "png" ? "image/png" : "image/jpeg"),
      asset.byteLength <= files.limits.maximumEncodedImageBytes else { throw DrawingExchangeError.limit("Encoded image type/bytes") }
    let bytes = try files.record(asset.object, maximumBytes: Int(files.limits.maximumEncodedImageBytes))
    files.counters.update { $0.imageHeaderReads += 1 }
    if asset.encoding == "png" { try pngContainer(bytes, files: files) }
    else { guard bytes.starts(with: [255, 216]), bytes.suffix(2) == Data([255, 217]) else { throw DrawingExchangeError.malformed("JPEG SOI/EOI closure") } }
    guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      CGImageSourceGetCount(source) == 1, let type = CGImageSourceGetType(source) as String?,
      type == (asset.encoding == "png" ? "public.png" : "public.jpeg"),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let w = properties[kCGImagePropertyPixelWidth] as? NSNumber, let h = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      w.doubleValue.isFinite, h.doubleValue.isFinite, w.doubleValue.rounded() == w.doubleValue, h.doubleValue.rounded() == h.doubleValue,
      w.doubleValue > 0, h.doubleValue > 0, w.doubleValue <= Double(Int.max), h.doubleValue <= Double(Int.max) else { throw DrawingExchangeError.malformed("Encoded image header") }
    let width = w.intValue, height = h.intValue
    if let d = descriptor.dimensions, d.width != width || d.height != height { throw DrawingExchangeError.malformed("Encoded dimensions disagree") }
    guard let depth = properties[kCGImagePropertyDepth] as? NSNumber, [8, 16].contains(depth.intValue),
      let color = properties[kCGImagePropertyColorModel] as? String, ["RGB", "Gray"].contains(color) else { throw DrawingExchangeError.unsupportedFeature("Encoded native pixel depth/color model") }
    // Reserve a conservative native RGBA16 plane plus the explicit RGBA8 conversion.
    // ImageIO internal codec workspace is implementation-owned, measured separately by peak RSS.
    guard UInt64(width) <= files.limits.maximumImagePixels / UInt64(height), width <= (Int.max - 255) / 8 else { throw DrawingExchangeError.limit("Decoded image bounds") }
    let nativeRow = ((width * 8 + 255) / 256) * 256
    guard UInt64(nativeRow) + UInt64(width) * 4 <= files.limits.maximumDecodedImageBytes / UInt64(height) else { throw DrawingExchangeError.limit("Decoded native+conversion bounds") }
    if let container = descriptor.containerType, ![type, asset.mediaType, asset.encoding].contains(container) { throw DrawingExchangeError.unsupportedFeature("Unverified encoded container claim: " + container) }
    if let color = descriptor.colorSpace, !["sRGB", "linear-gray"].contains(color) { throw DrawingExchangeError.unsupportedFeature("Unsupported encoded color-space claim: " + color) }
    if let orientation = descriptor.orientation, !["up", "up-mirrored", "down", "down-mirrored", "left", "left-mirrored", "right", "right-mirrored"].contains(orientation) { throw DrawingExchangeError.unsupportedFeature("Unsupported encoded orientation claim: " + orientation) }
    return .init(source: source, width: width, height: height, orientation: (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, maximumNativeRowBytes: nativeRow)
  }
  /// PNG framing and CRC proof is independent of ImageIO's potentially lenient header reader.
  /// This deliberately does not claim that IDAT inflates to valid pixels.
  static func pngContainer(_ bytes: Data, files: VerifiedExchangeFiles) throws {
    guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw DrawingExchangeError.malformed("PNG signature") }
    func integer(_ i: Int) -> UInt32 { bytes[i..<i + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } }
    var offset = 8, sawHeader = false, sawData = false, ended = false
    while offset < bytes.count {
      guard bytes.count - offset >= 12 else { throw DrawingExchangeError.malformed("PNG chunk framing") }
      let length = Int(integer(offset))
      guard length <= bytes.count - offset - 12 else { throw DrawingExchangeError.malformed("PNG chunk range") }
      let kind = String(decoding: bytes[(offset + 4)..<(offset + 8)], as: UTF8.self)
      guard bytes[(offset + 4)..<(offset + 8)].allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { throw DrawingExchangeError.malformed("PNG chunk type") }
      let crc = bytes.withUnsafeBytes { raw in crc32(0, raw.baseAddress!.advanced(by: offset + 4).assumingMemoryBound(to: Bytef.self), uInt(length + 4)) }
      files.counters.update { $0.crcBytes += UInt64(length + 4) }
      guard UInt32(crc) == integer(offset + length + 8) else { throw DrawingExchangeError.digestMismatch("PNG chunk CRC") }
      if !sawHeader { guard kind == "IHDR", length == 13 else { throw DrawingExchangeError.malformed("PNG first IHDR") }; sawHeader = true }
      else if kind == "IHDR" { throw DrawingExchangeError.malformed("PNG duplicate IHDR") }
      if kind == "IDAT" { sawData = true }
      offset += length + 12
      if kind == "IEND" { guard length == 0, sawData, offset == bytes.count else { throw DrawingExchangeError.malformed("PNG IEND/trailing bytes") }; ended = true; break }
    }
    guard sawHeader, sawData, ended else { throw DrawingExchangeError.malformed("Incomplete PNG container") }
  }
  static func validate(_ descriptor: ExchangeAssetDescriptor, files: VerifiedExchangeFiles) throws -> ExchangeAssetSupport {
    do {
      guard try header(descriptor, files: files) != nil else { return .unsupported(reason: "Unsupported asset encoding: " + descriptor.asset.encoding) }
    } catch DrawingExchangeError.unsupportedFeature(let reason) { return .unsupported(reason: reason) }
    if let digest = descriptor.decodedDigest { return .unsupported(reason: "Decoded digest algorithm is unverified: " + digest.algorithm) }
    return .unsupported(reason: "Encoded header verified; pixels require explicit bounded decode")
  }
  /// Returns pixels only on explicit request. The receipt does not grant physical or source-history authority.
  public static func decode(_ descriptor: ExchangeAssetDescriptor, files: VerifiedExchangeFiles) throws -> ExchangeDecodedImage {
    guard try files.byteLength(descriptor.asset.object) == descriptor.asset.byteLength,
      let header = try header(descriptor, files: files) else { throw DrawingExchangeError.unsupportedProfile(descriptor.asset.encoding) }
    files.counters.update { $0.imageDecodeCount += 1 }
    guard let image = CGImageSourceCreateImageAtIndex(header.source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
      CGImageSourceGetStatusAtIndex(header.source, 0) == .statusComplete,
      image.width == header.width, image.height == header.height, image.bitsPerComponent <= 16, image.bitsPerPixel <= 64,
      image.bytesPerRow <= header.maximumNativeRowBytes else { throw DrawingExchangeError.malformed("Encoded image decode") }
    let row = header.width * 4
    var pixels = Data(count: row * header.height)
    let rendered = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(data: raw.baseAddress, width: header.width, height: header.height, bitsPerComponent: 8,
        bytesPerRow: row, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: header.width, height: header.height)); return true
    }
    guard rendered else { throw DrawingExchangeError.malformed("Image render") }
    return .init(pixels: pixels, width: header.width, height: header.height, rowStride: row,
      channelOrder: ["red", "green", "blue", "alpha"], componentType: "uint8", byteOrder: "big", alpha: "premultiplied",
      orientationPolicy: "Encoded pixel order; orientation metadata retained and not applied", encodedOrientation: header.orientation, limitations:
        ["No source/history/physical proof", "Decoded digest claims are unverified; no canonical decoded-digest algorithm is defined", "Declared color-space/orientation claims do not establish semantic support"])
  }
}
