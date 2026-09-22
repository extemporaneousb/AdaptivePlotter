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
  var sourcePixelExtent: PortraitSourceCropExtent? = nil
  /// Ephemeral worker preparation; never part of a saved photo or candidate.
  var flowWorkspace: PortraitFlowRenderer.Workspace? = nil
}

struct PortraitRenderResult: Sendable {
  let raster: PortraitRaster
  let program: PlotterModel.DrawingProgram
  var transformationSummary: String? = nil
  var warpManifest: PortraitHeadWarpManifest? = nil
  var flowWorkspace: PortraitFlowRenderer.Workspace? = nil
}

protocol PortraitRendering: Sendable {
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult
}

enum PortraitPhotoInput: Sendable {
  case frame(StampedFrame)
  case file(URL)
}

struct PortraitAcquiredPhoto: Sendable {
  let data: Data
  var sourcePixelExtent: PortraitSourceCropExtent? = nil
}

protocol PortraitPhotoAcquiring: Sendable {
  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto
}

struct PortraitImageAnalyzer: PortraitRendering, PortraitPhotoAcquiring {
  static func analysisMaximumDimension(for style: PortraitStyle) -> Int {
    style == .flowEdges ? 320 : 160
  }

  static func cachedRasterIsCompatible(_ raster: PortraitRaster, with style: PortraitStyle) -> Bool {
    // Unknown legacy/synthetic geometry may intentionally use another lattice.
    // A Flow edit must still acquire its higher-resolution image evidence.
    if style != .flowEdges { return raster.analysisGeometry == nil || max(raster.width, raster.height) <= 160 }
    return max(raster.width, raster.height) == analysisMaximumDimension(for: style)
  }

  func acquire(_ input: PortraitPhotoInput) async throws -> PortraitAcquiredPhoto {
    try Task.checkCancellation()
    let image: CGImage
    let sourcePixelExtent: PortraitSourceCropExtent
    switch input {
    case .frame(let frame):
      guard let captured = FrameImageFactory.image(from: frame) else {
        throw PortraitDrawingError.unreadableImage
      }
      sourcePixelExtent = try PortraitSourceCropExtent(
        widthPixels: Double(captured.width), heightPixels: Double(captured.height))
      image = try Self.scaledImage(captured, maximumDimension: 1200)
    case .file(let url):
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      let data = try Data(contentsOf: url)
      try Task.checkCancellation()
      let decoded = try Self.decodedImage(from: data)
      image = decoded.image
      sourcePixelExtent = decoded.sourcePixelExtent
    }
    try Task.checkCancellation()
    let data = try Self.encodedImage(image)
    try Task.checkCancellation()
    return PortraitAcquiredPhoto(data: data, sourcePixelExtent: sourcePixelExtent)
  }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    try Task.checkCancellation()
    let cached = request.cachedRaster.flatMap {
      Self.cachedRasterIsCompatible($0, with: request.style) ? $0 : nil
    }
    let raster = try cached ?? Self.analyze(data: request.data, options: request.options,
      sourcePixelExtent: request.sourcePixelExtent,
      maximumDimension: Self.analysisMaximumDimension(for: request.style))
    try Task.checkCancellation()
    var workspace: PortraitFlowRenderer.Workspace?
    var flowLayers: PortraitFlowRenderer.Layers?
    if request.style == .flowEdges {
      var prepared = request.flowWorkspace ?? .init()
      var effective = request.vectorOptions.bounded
      if let material = effective.materialContext { effective = try material.adapting(effective, raster: raster) }
      flowLayers = try PortraitFlowRenderer.layers(from: raster, options: effective, workspace: &prepared)
      workspace = prepared
    }
    let program = try PortraitVectorizer.program(
      from: raster, pose: request.pose, style: request.style, strokeStyle: request.strokeStyle,
      vectorOptions: request.vectorOptions, flowLayers: flowLayers)
    try Task.checkCancellation()
    let transformSummary: String?
    let warpManifest = request.vectorOptions.bounded.semanticHead.map {
      PortraitHeadTransform(raster: raster, parameters: $0).manifest
    }
    if let warpManifest {
      transformSummary = warpManifest.summary
    } else if request.vectorOptions.bounded.headScale > 1 {
      transformSummary = PortraitHeadTransform.validFaceBounds(raster.faceBounds) == nil
        ? "No face located; head enlargement skipped"
        : String(format: "Head emphasis %.2f×", request.vectorOptions.bounded.headScale)
    } else { transformSummary = nil }
    return PortraitRenderResult(raster: raster, program: program, transformationSummary: transformSummary,
      warpManifest: warpManifest, flowWorkspace: workspace)
  }

  static func image(from data: Data) throws -> CGImage {
    try decodedImage(from: data).image
  }

  /// Read the full source metric before the thumbnail rounds either axis.
  /// ImageIO applies EXIF orientation to the thumbnail, so its source metric
  /// must use the same oriented axes. Decoding work remains bounded at 1200 px.
  static func decodedImage(from data: Data) throws
    -> (image: CGImage, sourcePixelExtent: PortraitSourceCropExtent) {
    try Task.checkCancellation()
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 1200,
      ] as CFDictionary)
    else { throw PortraitDrawingError.unreadableImage }
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let swapsAxes = (5...8).contains(orientation)
    let sourcePixelExtent = try PortraitSourceCropExtent(
      widthPixels: swapsAxes ? height : width, heightPixels: swapsAxes ? width : height)
    return (image, sourcePixelExtent)
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

  static func analyze(data: Data, options: PortraitAnalysisOptions,
    sourcePixelExtent: PortraitSourceCropExtent? = nil,
    maximumDimension: Int = 160) throws -> PortraitRaster {
    try Task.checkCancellation()
    let decoded = try decodedImage(from: data)
    let image = decoded.image
    let originalExtent = sourcePixelExtent ?? decoded.sourcePixelExtent
    var crop = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    var detectedFace: CGRect?
    var notes: [String] = []
    // Face geometry is cached for framing and optional caricature even when
    // the operator retains the full photograph. This runs only on analysis.
    let faceAnalysis = try PortraitFaceLandmarkAnalyzer.analyze(image)
    if let face = faceAnalysis.boundingBox {
      detectedFace = CGRect(x: face.x, y: face.y, width: face.width, height: face.height)
      if options.cropToFace {
        // The retained observation is top-left pixels; faceCrop accepts Vision's
        // normalized lower-left box. This conversion does not round landmarks.
        let bounds = CGRect(x: face.x / Double(image.width),
          y: 1 - (face.y + face.height) / Double(image.height),
          width: face.width / Double(image.width), height: face.height / Double(image.height))
        crop = faceCrop(bounds: bounds, imageWidth: image.width, imageHeight: image.height,
          margin: options.boundedFaceCropMargin)
        notes.append("Face crop")
      } else { notes.append("Full photo") }
      if let reason = faceAnalysis.unavailableReason { notes.append(reason) }
    } else if faceAnalysis.status == .noFace {
      notes.append("No face located; full photo")
    } else {
      notes.append("Face analysis unavailable (\(faceAnalysis.unavailableReason ?? "unknown reason")); full photo")
    }
    try Task.checkCancellation()
    guard let cropped = image.cropping(to: crop) else { throw PortraitDrawingError.unreadableImage }
    let sourceCropExtent = try cropMetric(sourcePixelExtent: originalExtent,
      decodedWidth: image.width, decodedHeight: image.height,
      cropWidth: cropped.width, cropHeight: cropped.height)
    let ratio = sourceCropExtent.aspectRatio
    let dimension = Double(min(512, max(8, maximumDimension)))
    let width = Int(min(dimension, max(8, dimension * ratio)))
    let height = Int(min(dimension, max(8, dimension / ratio)))
    var luminance = try grayscale(cropped, width: width, height: height)
    // Normalize illumination before whitening the background; the matte must
    // not bias the contrast percentiles toward white.
    let sorted = luminance.sorted()
    let low = sorted[sorted.count / 50], high = sorted[sorted.count * 49 / 50]
    if high - low > 0.05 {
      luminance = luminance.map { min(1, max(0, ($0-low)/(high-low))) }
    }
    var maskStatus: PortraitPersonMaskStatus = .notRequested
    var maskRevision: Int?
    var maskWidth: Int?
    var maskHeight: Int?
    var retainedMaskCrop: PortraitAnalysisCrop?
    var retainedAlpha: [Double]?
    var maskUnavailableReason: String?
    if options.removeBackground {
      try Task.checkCancellation()
      do {
        let request = VNGeneratePersonSegmentationRequest()
        maskRevision = request.revision
        maskStatus = .unavailable
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        try Task.checkCancellation()
        if let buffer = request.results?.first?.pixelBuffer {
          let mask = try maskImage(buffer)
          maskWidth = mask.width
          maskHeight = mask.height
          let maskCrop = CGRect(
            x: crop.minX / Double(image.width) * Double(mask.width),
            y: crop.minY / Double(image.height) * Double(mask.height),
            width: crop.width / Double(image.width) * Double(mask.width),
            height: crop.height / Double(image.height) * Double(mask.height))
            .integral.intersection(CGRect(x: 0, y: 0, width: mask.width, height: mask.height))
          if let croppedMask = mask.cropping(to: maskCrop) {
            retainedMaskCrop = PortraitAnalysisCrop(x: maskCrop.minX, y: maskCrop.minY,
              width: Double(croppedMask.width), height: Double(croppedMask.height))
            let alpha = try grayscale(croppedMask, width: width, height: height)
            retainedAlpha = alpha
            if alpha.contains(where: { $0 > 0.5 }) {
              luminance = zip(luminance, alpha).map { value, mask in 1 - mask*(1-value) }
              maskStatus = .applied
              notes.append("Person background removed")
            } else {
              maskStatus = .noPerson
              maskUnavailableReason = "No foreground alpha above 0.5"
              notes.append("No person mask; background retained")
            }
          } else {
            maskStatus = .cropUnavailable
            maskUnavailableReason = "The Vision mask could not be cropped to the analyzed image"
            notes.append("Mask crop unavailable; background retained")
          }
        } else {
          maskStatus = .noPerson
          maskUnavailableReason = "Vision returned no person mask"
          notes.append("No person mask; background retained")
        }
      } catch is CancellationError { throw CancellationError() }
      catch {
        maskStatus = .unavailable
        maskUnavailableReason = error.localizedDescription
        notes.append("Person masking unavailable (\(error.localizedDescription)); background retained")
      }
    }
    try Task.checkCancellation()
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let rasterDigest = SHA256.hash(data: Data(luminance.map { UInt8(($0*255).rounded()) }))
      .map { String(format: "%02x", $0) }.joined()
    let geometry = PortraitAnalysisGeometry(sourcePixelExtent: originalExtent,
      decodedWidth: image.width, decodedHeight: image.height,
      crop: PortraitAnalysisCrop(x: crop.minX, y: crop.minY,
        width: Double(cropped.width), height: Double(cropped.height)),
      rasterWidth: width, rasterHeight: height,
      contrastLow: low, contrastHigh: high, contrastApplied: high - low > 0.05)
    let personMask = PortraitPersonMask(status: maskStatus, requestRevision: maskRevision,
      platformVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      width: width, height: height, sourceMaskWidth: maskWidth, sourceMaskHeight: maskHeight,
      sourceMaskCrop: retainedMaskCrop, alpha: retainedAlpha, unavailableReason: maskUnavailableReason)
    let result = PortraitRaster(
      width: width, height: height, luminance: luminance,
      provenance: "image=\(digest)|raster=\(rasterDigest)|sourcePixels=\(originalExtent.widthPixels)x\(originalExtent.heightPixels)|decodedPixels=\(image.width)x\(image.height)|crop=\(crop)|size=\(width)x\(height)|face=\(options.cropToFace)|faceMargin=\(options.boundedFaceCropMargin)|mask=\(options.removeBackground)|analysisSchema=3|faceAnalysisRevision=\(faceAnalysis.algorithmRevision)|faceRequestRevision=\(faceAnalysis.requestRevision)|faceConstellation=\(faceAnalysis.constellation)|faceAnalysisStatus=\(faceAnalysis.status.rawValue)|maskStatus=\(maskStatus.rawValue)|maskRevision=\(maskRevision.map(String.init) ?? "none")",
      analysisSummary: notes.joined(separator: " · "),
      faceBounds: detectedFace.map { face in
        CGRect(x: (face.minX-crop.minX)/crop.width, y: (face.minY-crop.minY)/crop.height,
          width: face.width/crop.width, height: face.height/crop.height)
      }, sourceCropExtent: sourceCropExtent, analysisGeometry: geometry, personMask: personMask,
      faceAnalysis: faceAnalysis)
    try result.validateAnalysisEvidence()
    return result
  }

  /// An integer crop of a rounded thumbnail occupies fractional original pixels.
  static func cropMetric(sourcePixelExtent: PortraitSourceCropExtent,
    decodedWidth: Int, decodedHeight: Int, cropWidth: Int, cropHeight: Int) throws -> PortraitSourceCropExtent {
    guard decodedWidth > 0, decodedHeight > 0, cropWidth > 0, cropHeight > 0,
      cropWidth <= decodedWidth, cropHeight <= decodedHeight else { throw PortraitDrawingError.unreadableImage }
    return try PortraitSourceCropExtent(
      widthPixels: sourcePixelExtent.widthPixels * (Double(cropWidth) / Double(decodedWidth)),
      heightPixels: sourcePixelExtent.heightPixels * (Double(cropHeight) / Double(decodedHeight)))
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
