import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import PortraitCore
import UniformTypeIdentifiers
import Vision

/// One preparation path for authoring and retained experiments. Coordinates in
/// its metadata are oriented pixels, origin at the top left, before rendering.
struct PortraitStudioArtistInput: Sendable {
  static let preparationRevision = "studio-face-person-mask-srgb-square-v2"
  static let targetDimension = 1024
  static let targetFaceHeightFraction = 0.52
  static let targetFaceCenterXFraction = 0.5
  static let targetFaceCenterYFraction = 0.54

  let source: DrawingPackageAsset
  let squarePNG: DrawingPackageAsset
  let framedSourcePNG: DrawingPackageAsset
  let foregroundMaskPNG: DrawingPackageAsset
  let preparationJSON: Data

  struct FaceOverride: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let declaration: String

    var rectangle: CGRect { CGRect(x: x, y: y, width: width, height: height) }
  }

  struct DetectedFace {
    let rectangle: CGRect
    let confidence: Float
  }

  struct Framing {
    let crop: CGRect
    let scale: Double
    let translateX: Double
    let translateY: Double
    let faceInTarget: CGRect
  }

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

  /// Face height and center are fixed; a single uniform scale preserves the
  /// source proportions. The square may extend outside the source: those pixels
  /// are declared white padding rather than a clamped, differently sized crop.
  static func framing(face: CGRect, orientedWidth: Int, orientedHeight: Int) throws -> Framing {
    let values = [face.minX, face.minY, face.width, face.height]
    guard values.allSatisfy(\.isFinite), face.width > 0, face.height > 0,
      face.minX >= 0, face.minY >= 0,
      face.maxX <= Double(orientedWidth), face.maxY <= Double(orientedHeight),
      orientedWidth > 0, orientedHeight > 0 else {
      throw DrawingTransferError.invalid("The selected face must be a finite, positive rectangle inside the oriented source.")
    }
    let target = Double(targetDimension)
    let scale = target * targetFaceHeightFraction / face.height
    let side = target / scale
    let x = face.midX - targetFaceCenterXFraction * side
    let y = face.midY - targetFaceCenterYFraction * side
    let tx = -x * scale, ty = -y * scale
    let faceInTarget = CGRect(x: face.minX * scale + tx, y: face.minY * scale + ty,
      width: face.width * scale, height: face.height * scale)
    guard faceInTarget.minX >= 0, faceInTarget.maxX <= target,
      faceInTarget.minY >= 0, faceInTarget.maxY <= target else {
      throw DrawingTransferError.invalid("The selected face is too wide for the fixed portrait frame without distortion.")
    }
    return .init(crop: CGRect(x: x, y: y, width: side, height: side), scale: scale,
      translateX: tx, translateY: ty, faceInTarget: faceInTarget)
  }

  static func prepare(_ bytes: Data, faceOverride: FaceOverride? = nil,
    faceDetector: (CGImage) throws -> [DetectedFace] = detectFaces,
    maskGenerator: (CGImage) throws -> CGImage = personMask
  ) throws -> Self {
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
      ] as CFDictionary) else {
      throw DrawingTransferError.invalid("The retained source cannot be decoded within the image bounds.")
    }
    let detections: [DetectedFace]
    let face: CGRect
    let selection: String
    if let faceOverride {
      let declaration = faceOverride.declaration.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !declaration.isEmpty, declaration.utf8.count <= 4096 else {
        throw DrawingTransferError.invalid("An explicit face rectangle requires its selection declaration.")
      }
      detections = []
      face = faceOverride.rectangle
      selection = "explicit-oriented-pixel-rectangle"
    } else {
      detections = try faceDetector(image)
      let accepted = detections.filter { $0.confidence.isFinite && $0.confidence >= 0.5 }
      guard !accepted.isEmpty else {
        throw DrawingTransferError.unavailable("No confident face was detected. Supply an explicit oriented face rectangle.")
      }
      guard accepted.count == 1 else {
        throw DrawingTransferError.unavailable("Multiple faces were detected. Select one with an explicit oriented face rectangle.")
      }
      face = accepted[0].rectangle
      selection = "single-confident-vision-face"
    }
    try Task.checkCancellation()
    let geometry = try framing(face: face, orientedWidth: image.width, orientedHeight: image.height)
    let framed = try framedImage(image, framing: geometry)
    try Task.checkCancellation()
    let rawMask = try maskGenerator(framed)
    try Task.checkCancellation()
    guard rawMask.width > 0, rawMask.height > 0,
      rawMask.width <= DrawingTransferLimits.maximumImageDimension,
      rawMask.height <= DrawingTransferLimits.maximumImageDimension,
      rawMask.width <= DrawingTransferLimits.maximumImagePixels / rawMask.height else {
      throw DrawingTransferError.invalid("The person mask exceeds the image bounds.")
    }
    let mask = try grayscaleBytes(rawMask, width: targetDimension, height: targetDimension)
    let faceMaskMean = meanMask(mask, rectangle: geometry.faceInTarget)
    let foregroundCount = mask.reduce(0) { $0 + ($1 >= 128 ? 1 : 0) }
    guard foregroundCount > 0, foregroundCount < mask.count,
      faceMaskMean >= 0.25 else {
      throw DrawingTransferError.unavailable("Person segmentation did not produce a usable foreground mask covering the selected face.")
    }
    let prepared = try composite(framed, mask: mask)
    let framedAsset = try pngAsset(framed)
    let maskAsset = try pngAsset(rawMask)
    let square = try pngAsset(prepared)
    let type = CGImageSourceGetType(source) as String?
    guard type == UTType.png.identifier || type == UTType.jpeg.identifier else {
      throw DrawingTransferError.invalid("The retained source must be encoded as PNG or JPEG.")
    }
    let sourceAsset = DrawingPackageAsset(mediaType: type == UTType.png.identifier ? "image/png" : "image/jpeg",
      bytes: bytes, pixelWidth: originalWidth, pixelHeight: originalHeight)
    try sourceAsset.validate(maximumBytes: DrawingTransferLimits.sourceBytes, requireImage: true)
    let sourceBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let intersection = geometry.crop.intersection(sourceBounds)
    let observationJSON: [[String: Any]] = detections.map {
      ["rectangle": rectangleJSON($0.rectangle), "confidence": Double($0.confidence)]
    }
    let metadataObject: [String: Any] = [
      "revision": preparationRevision, "color_space": "sRGB",
      "orientation": "EXIF-applied", "coordinate_space": "oriented-source-pixels-top-left-y-down",
      "crop": rectangleJSON(geometry.crop), "crop_source_intersection": rectangleJSON(intersection),
      "crop_policy": "fixed-square-about-selected-face; outside-source-pixels-white",
      "face": rectangleJSON(face), "face_in_target": rectangleJSON(geometry.faceInTarget),
      "face_selection": selection, "face_selection_declaration": faceOverride?.declaration ?? "Vision detected exactly one face with confidence >= 0.5",
      "face_observations": observationJSON,
      "face_request": "VNDetectFaceRectanglesRequest", "face_request_revision": VNDetectFaceRectanglesRequestRevision3,
      "face_request_performed": faceOverride == nil,
      "target_face_height_fraction": targetFaceHeightFraction,
      "target_face_center_x_fraction": targetFaceCenterXFraction,
      "target_face_center_y_fraction": targetFaceCenterYFraction,
      "mask": "native-person-segmentation-accurate-over-fixed-face-frame-v1",
      "mask_request": "VNGeneratePersonSegmentationRequest", "mask_request_revision": VNGeneratePersonSegmentationRequestRevision1,
      "mask_quality": "accurate", "mask_pixel_format": "OneComponent8",
      "mask_compute_policy": "Vision-native-default; no external model or network",
      "mask_coordinate_space": "entire-framed-square-top-left-y-down",
      "mask_resampling": "CoreGraphics-high-quality-to-1024; grayscale luminance alpha over white",
      "mask_width": rawMask.width, "mask_height": rawMask.height,
      "mask_sha256": maskAsset.sha256, "framed_source_sha256": framedAsset.sha256,
      "prepared_source_sha256": square.sha256, "original_sha256": sourceAsset.sha256,
      "face_mask_mean": faceMaskMean,
      "foreground_fraction_at_half_alpha": Double(foregroundCount) / Double(mask.count),
      "original_exif_orientation": properties[kCGImagePropertyOrientation] as? Int ?? 1,
      "original_exif_orientation_present": properties[kCGImagePropertyOrientation] != nil,
      "original_encoded_type": type ?? "unknown",
      "original_profile_name": properties[kCGImagePropertyProfileName] as? String ?? "unknown",
      "profile_policy": "ImageIO decode to explicit sRGB; absent source profile remains unknown",
      "native_os": ProcessInfo.processInfo.operatingSystemVersionString,
      "native_build_identifier": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      "source_width": originalWidth, "source_height": originalHeight,
      "oriented_width": image.width, "oriented_height": image.height,
      "target_width": targetDimension, "target_height": targetDimension,
      "uniform_scale": geometry.scale,
      "affine_top_left": [geometry.scale, 0, 0, geometry.scale, geometry.translateX, geometry.translateY],
      "padding_target_pixels": ["left": max(0, geometry.translateX), "top": max(0, geometry.translateY),
        "right": max(0, Double(targetDimension) - (Double(image.width) * geometry.scale + geometry.translateX)),
        "bottom": max(0, Double(targetDimension) - (Double(image.height) * geometry.scale + geometry.translateY))],
      "alpha_background": "white", "source_proportions": "preserved by one uniform scale; no per-axis stretch"
    ]
    let metadata = try JSONSerialization.data(withJSONObject: metadataObject, options: [.sortedKeys])
    return .init(source: sourceAsset, squarePNG: square, framedSourcePNG: framedAsset,
      foregroundMaskPNG: maskAsset, preparationJSON: metadata)
  }

  private static func detectFaces(_ image: CGImage) throws -> [DetectedFace] {
    let request = VNDetectFaceRectanglesRequest()
    request.revision = VNDetectFaceRectanglesRequestRevision3
    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
    try Task.checkCancellation()
    return (request.results ?? []).map { observation in
      let box = observation.boundingBox
      return .init(rectangle: CGRect(x: box.minX * Double(image.width),
        y: (1 - box.maxY) * Double(image.height), width: box.width * Double(image.width),
        height: box.height * Double(image.height)), confidence: observation.confidence)
    }
  }

  private static func personMask(_ image: CGImage) throws -> CGImage {
    let request = VNGeneratePersonSegmentationRequest()
    request.revision = VNGeneratePersonSegmentationRequestRevision1
    request.qualityLevel = .accurate
    request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
      try Task.checkCancellation()
      guard let buffer = request.results?.first?.pixelBuffer,
        CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else {
        throw DrawingTransferError.unavailable("Vision returned no 8-bit person mask.")
      }
      CVPixelBufferLockBaseAddress(buffer, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
      guard let address = CVPixelBufferGetBaseAddress(buffer) else {
        throw DrawingTransferError.unavailable("Vision person mask could not be read.")
      }
      let rowBytes = CVPixelBufferGetBytesPerRow(buffer), height = CVPixelBufferGetHeight(buffer)
      let data = Data(bytes: address, count: rowBytes * height)
      guard let provider = CGDataProvider(data: data as CFData),
        let mask = CGImage(width: CVPixelBufferGetWidth(buffer), height: height,
          bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: rowBytes,
          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
        throw DrawingTransferError.unavailable("Vision person mask could not be decoded.")
      }
      return mask
    } catch is CancellationError { throw CancellationError() }
    catch {
      throw DrawingTransferError.unavailable("Local person segmentation is unavailable: \(error.localizedDescription)")
    }
  }

  private static func framedImage(_ source: CGImage, framing: Framing) throws -> CGImage {
    let context = try rgbaContext()
    let target = Double(targetDimension)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: target, height: target))
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: framing.translateX,
      y: target - (Double(source.height) * framing.scale + framing.translateY),
      width: Double(source.width) * framing.scale, height: Double(source.height) * framing.scale))
    guard let image = context.makeImage() else { throw DrawingTransferError.invalid("Face framing failed.") }
    return image
  }

  private static func grayscaleBytes(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: width * height)
    let success = pixels.withUnsafeMutableBytes { storage in
      guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
        bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard success else { throw DrawingTransferError.invalid("Person mask resampling failed.") }
    return pixels
  }

  private static func meanMask(_ pixels: [UInt8], rectangle: CGRect) -> Double {
    let x0 = max(0, Int(rectangle.minX.rounded(.down)))
    let y0 = max(0, Int(rectangle.minY.rounded(.down)))
    let x1 = min(targetDimension, Int(rectangle.maxX.rounded(.up)))
    let y1 = min(targetDimension, Int(rectangle.maxY.rounded(.up)))
    var total = 0, count = 0
    for y in y0..<y1 {
      for x in x0..<x1 { total += Int(pixels[y * targetDimension + x]); count += 1 }
    }
    return count > 0 ? Double(total) / Double(count * 255) : 0
  }

  private static func composite(_ source: CGImage, mask: [UInt8]) throws -> CGImage {
    let context = try rgbaContext()
    context.draw(source, in: CGRect(x: 0, y: 0, width: targetDimension, height: targetDimension))
    guard let pointer = context.data?.assumingMemoryBound(to: UInt8.self) else {
      throw DrawingTransferError.invalid("Masked source could not be rasterized.")
    }
    for index in 0..<mask.count {
      if index % (targetDimension * 64) == 0 { try Task.checkCancellation() }
      let alpha = Int(mask[index]), base = index * 4
      for channel in 0..<3 {
        pointer[base + channel] = UInt8((Int(pointer[base + channel]) * alpha + 255 * (255 - alpha) + 127) / 255)
      }
      pointer[base + 3] = 255
    }
    guard let image = context.makeImage() else { throw DrawingTransferError.invalid("Person mask composition failed.") }
    return image
  }

  private static func rgbaContext() throws -> CGContext {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: targetDimension, height: targetDimension,
        bitsPerComponent: 8, bytesPerRow: targetDimension * 4, space: colorSpace,
        bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DrawingTransferError.invalid("The fixed sRGB portrait frame could not be allocated.")
    }
    return context
  }

  private static func pngAsset(_ image: CGImage) throws -> DrawingPackageAsset {
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
      throw DrawingTransferError.invalid("Prepared source could not be encoded.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingTransferError.invalid("Prepared PNG encoding failed.") }
    let asset = DrawingPackageAsset(mediaType: "image/png", bytes: output as Data,
      pixelWidth: image.width, pixelHeight: image.height)
    try asset.validate(maximumBytes: DrawingTransferLimits.inputBytes, requireImage: true)
    return asset
  }

  private static func rectangleJSON(_ rectangle: CGRect) -> [String: Double] {
    ["x": rectangle.minX, "y": rectangle.minY, "width": rectangle.width, "height": rectangle.height]
  }
}
