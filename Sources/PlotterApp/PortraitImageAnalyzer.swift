import CoreGraphics
import CoreVideo
import CryptoKit
import Foundation
import ImageIO
import PlotterModel
import PlotterRuntime
import UniformTypeIdentifiers
import Vision

struct PortraitAnalysisOptions: Codable, Hashable, Sendable {
  var cropToFace = true
  var removeBackground = true
  /// Padding around the detected face, as a fraction of its width. Smaller
  /// margins allocate more of the portrait to the head; no facial warp occurs.
  var faceCropMargin = 0.35

  var boundedFaceCropMargin: Double {
    faceCropMargin.isFinite ? min(0.8, max(0.05, faceCropMargin)) : 0.35
  }
}

/// Invoked on a worker task only after capture/import or an analysis option
/// changes. No continuous Vision requests run on either camera's preview path.
struct PortraitRenderRequest: Sendable {
  let data: Data
  let pose: PortraitPose
  let style: PortraitStyle
  let options: PortraitAnalysisOptions
  let cachedRaster: PortraitRaster?
  let strokeStyle: PlotterModel.StrokeStyle
  var vectorOptions = PortraitVectorOptions()
}

struct PortraitRenderResult: Sendable {
  let raster: PortraitRaster
  let program: PlotterModel.DrawingProgram
  var transformationSummary: String? = nil
}

protocol PortraitRendering: Sendable {
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult
}

enum PortraitPhotoInput: Sendable {
  case frame(StampedFrame)
  case file(URL)
}

protocol PortraitPhotoAcquiring: Sendable {
  func acquire(_ input: PortraitPhotoInput) async throws -> Data
}

struct PortraitImageAnalyzer: PortraitRendering, PortraitPhotoAcquiring {
  func acquire(_ input: PortraitPhotoInput) async throws -> Data {
    try Task.checkCancellation()
    let image: CGImage
    switch input {
    case .frame(let frame):
      guard let captured = FrameImageFactory.image(from: frame) else {
        throw PortraitDrawingError.unreadableImage
      }
      image = try Self.scaledImage(captured, maximumDimension: 1200)
    case .file(let url):
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      try Task.checkCancellation()
      image = try Self.image(from: data)
    }
    try Task.checkCancellation()
    let data = try Self.encodedImage(image)
    try Task.checkCancellation()
    return data
  }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    try Task.checkCancellation()
    let raster = try request.cachedRaster ?? Self.analyze(data: request.data, options: request.options)
    try Task.checkCancellation()
    let program = try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions)
    try Task.checkCancellation()
    let transformSummary: String?
    if request.vectorOptions.bounded.headScale > 1 {
      transformSummary = PortraitHeadTransform.validFaceBounds(raster.faceBounds) == nil
        ? "No face located; head enlargement skipped"
        : String(format: "Head emphasis %.2f×", request.vectorOptions.bounded.headScale)
    } else { transformSummary = nil }
    return PortraitRenderResult(raster: raster, program: program, transformationSummary: transformSummary)
  }

  static func image(from data: Data) throws -> CGImage {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1200,
      ] as CFDictionary)
    else { throw PortraitDrawingError.unreadableImage }
    return image
  }

  static func encodedImage(_ image: CGImage) throws -> Data {
    try Task.checkCancellation()
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
    else { throw PortraitDrawingError.unreadableImage }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw PortraitDrawingError.unreadableImage }
    return data as Data
  }

  /// Store camera frames at the same bounded resolution as imported photos.
  /// The gallery also imposes a total byte bound; this avoids retaining a full
  /// camera-resolution PNG for every candidate in a portrait burst.
  static func scaledImage(_ image: CGImage, maximumDimension: Int) throws -> CGImage {
    try Task.checkCancellation()
    guard maximumDimension > 0 else { throw PortraitDrawingError.unreadableImage }
    guard max(image.width, image.height) > maximumDimension else { return image }
    let scale = Double(maximumDimension) / Double(max(image.width, image.height))
    let width = max(1, Int((Double(image.width) * scale).rounded()))
    let height = max(1, Int((Double(image.height) * scale).rounded()))
    guard let context = CGContext(data: nil, width: width, height: height,
      bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw PortraitDrawingError.unreadableImage }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    try Task.checkCancellation()
    guard let result = context.makeImage() else { throw PortraitDrawingError.unreadableImage }
    return result
  }

  static func faceCrop(bounds: CGRect, imageWidth: Int, imageHeight: Int, margin: Double) -> CGRect {
    let padding = margin.isFinite ? min(0.8, max(0.05, margin)) : 0.35
    let padded = bounds.insetBy(dx: -bounds.width * padding, dy: -bounds.height * padding * 9 / 7)
    let full = CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight)
    return CGRect(x: padded.minX * Double(imageWidth), y: (1 - padded.maxY) * Double(imageHeight),
      width: padded.width * Double(imageWidth), height: padded.height * Double(imageHeight))
      .intersection(full).integral.intersection(full)
  }

  static func analyze(data: Data, options: PortraitAnalysisOptions) throws -> PortraitRaster {
    try Task.checkCancellation()
    let image = try image(from: data)
    var crop = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    var detectedFace: CGRect?
    var notes: [String] = []
    // Face geometry is cached for framing and optional caricature even when
    // the operator retains the full photograph. This runs only on analysis.
    let faces = VNDetectFaceRectanglesRequest()
    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([faces])
      try Task.checkCancellation()
      if let face = faces.results?.max(by: { $0.boundingBox.width*$0.boundingBox.height < $1.boundingBox.width*$1.boundingBox.height }) {
        detectedFace = CGRect(x: face.boundingBox.minX * Double(image.width),
          y: (1-face.boundingBox.maxY) * Double(image.height),
          width: face.boundingBox.width * Double(image.width), height: face.boundingBox.height * Double(image.height))
        if options.cropToFace {
          crop = faceCrop(bounds: face.boundingBox, imageWidth: image.width, imageHeight: image.height,
                          margin: options.boundedFaceCropMargin)
          notes.append("Face crop")
        } else { notes.append("Full photo") }
      } else { notes.append("No face located; full photo") }
    } catch is CancellationError { throw CancellationError() }
    catch { notes.append("Face detection unavailable (\(error.localizedDescription)); full photo") }
    try Task.checkCancellation()
    guard let cropped = image.cropping(to: crop) else { throw PortraitDrawingError.unreadableImage }
    let ratio = Double(cropped.width) / Double(cropped.height)
    let width = max(8, min(160, Int(160 * ratio)))
    let height = max(8, min(160, Int(160 / ratio)))
    var luminance = try grayscale(cropped, width: width, height: height)
    // Normalize illumination before whitening the background; the matte must
    // not bias the contrast percentiles toward white.
    let sorted = luminance.sorted()
    let low = sorted[sorted.count / 50], high = sorted[sorted.count * 49 / 50]
    if high - low > 0.05 {
      luminance = luminance.map { min(1, max(0, ($0-low)/(high-low))) }
    }
    if options.removeBackground {
      try Task.checkCancellation()
      do {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        try Task.checkCancellation()
        if let buffer = request.results?.first?.pixelBuffer {
          let mask = try maskImage(buffer)
          let maskCrop = CGRect(
            x: crop.minX / Double(image.width) * Double(mask.width),
            y: crop.minY / Double(image.height) * Double(mask.height),
            width: crop.width / Double(image.width) * Double(mask.width),
            height: crop.height / Double(image.height) * Double(mask.height))
          if let croppedMask = mask.cropping(to: maskCrop) {
            let alpha = try grayscale(croppedMask, width: width, height: height)
            if alpha.contains(where: { $0 > 0.5 }) {
              luminance = zip(luminance, alpha).map { value, mask in 1 - mask*(1-value) }
              notes.append("Person background removed")
            } else { notes.append("No person mask; background retained") }
          } else { notes.append("Mask crop unavailable; background retained") }
        } else { notes.append("No person mask; background retained") }
      } catch is CancellationError { throw CancellationError() }
      catch { notes.append("Person masking unavailable (\(error.localizedDescription)); background retained") }
    }
    try Task.checkCancellation()
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let rasterDigest = SHA256.hash(data: Data(luminance.map { UInt8(($0*255).rounded()) }))
      .map { String(format: "%02x", $0) }.joined()
    return PortraitRaster(
      width: width, height: height, luminance: luminance,
      provenance: "image=\(digest)|raster=\(rasterDigest)|crop=\(crop)|size=\(width)x\(height)|face=\(options.cropToFace)|faceMargin=\(options.boundedFaceCropMargin)|mask=\(options.removeBackground)",
      analysisSummary: notes.joined(separator: " · "),
      faceBounds: detectedFace.map { face in
        CGRect(x: (face.minX-crop.minX)/crop.width, y: (face.minY-crop.minY)/crop.height,
          width: face.width/crop.width, height: face.height/crop.height)
      })
  }

  static func grayscale(_ image: CGImage, width: Int, height: Int) throws -> [Double] {
    try Task.checkCancellation()
    var bytes = [UInt8](repeating: 255, count: width*height)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .high
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { throw PortraitDrawingError.unreadableImage }
    return bytes.map { Double($0) / 255 }
  }

  private static func maskImage(_ buffer: CVPixelBuffer) throws -> CGImage {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let address = CVPixelBufferGetBaseAddress(buffer) else { throw PortraitDrawingError.unreadableImage }
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer), height = CVPixelBufferGetHeight(buffer)
    let data = Data(bytes: address, count: rowBytes*height)
    guard let provider = CGDataProvider(data: data as CFData),
      let image = CGImage(width: CVPixelBufferGetWidth(buffer), height: height,
                          bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: rowBytes,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                          provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { throw PortraitDrawingError.unreadableImage }
    return image
  }
}
