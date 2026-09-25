import Foundation

/// Exact top-left-origin crop in the bounded decoded image's pixel coordinates.
struct PortraitAnalysisCrop: Codable, Hashable, Sendable {
  let x: Double
  let y: Double
  let width: Double
  let height: Double
}

enum PortraitRasterSampling: String, Codable, Hashable, Sendable {
  case pixelCentersV1 = "pixel-centers-v1"
}

/// Retained numerical inputs for the crop, resampling and contrast stages.
/// Source extents are oriented original-image pixels, not controller units.
struct PortraitAnalysisGeometry: Codable, Hashable, Sendable {
  var schemaVersion = 1
  let sourcePixelExtent: PortraitSourceCropExtent
  let decodedWidth: Int
  let decodedHeight: Int
  let crop: PortraitAnalysisCrop
  let rasterWidth: Int
  let rasterHeight: Int
  var sampling: PortraitRasterSampling = .pixelCentersV1
  var preprocessingRevision = "portrait-analysis-v1"
  let contrastLow: Double
  let contrastHigh: Double
  let contrastApplied: Bool

  func validate(width: Int, height: Int) throws {
    guard schemaVersion == 1, ["portrait-analysis-v1", "portrait-analysis-v2"].contains(preprocessingRevision),
      decodedWidth > 0, decodedHeight > 0, rasterWidth == width, rasterHeight == height,
      [crop.x, crop.y, crop.width, crop.height, contrastLow, contrastHigh].allSatisfy(\.isFinite),
      crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
      crop.x + crop.width <= Double(decodedWidth), crop.y + crop.height <= Double(decodedHeight),
      crop.x.rounded() == crop.x, crop.y.rounded() == crop.y,
      crop.width.rounded() == crop.width, crop.height.rounded() == crop.height,
      contrastLow >= 0, contrastHigh <= 1, contrastHigh >= contrastLow,
      contrastApplied == (contrastHigh - contrastLow > 0.05)
    else { throw PortraitDrawingError.unreadableImage }
  }
}

enum PortraitPersonMaskStatus: String, Codable, Hashable, Sendable {
  case notRequested, applied, noPerson, cropUnavailable, unavailable
}

/// The exact raster-resolution alpha used by background whitening. Raw Vision
/// results are never recreated by assuming the same request revision is repeatable.
struct PortraitPersonMask: Codable, Hashable, Sendable {
  var schemaVersion = 1
  let status: PortraitPersonMaskStatus
  let requestRevision: Int?
  let platformVersion: String
  var quality = "accurate"
  let width: Int
  let height: Int
  var sourceMaskWidth: Int? = nil
  var sourceMaskHeight: Int? = nil
  var sourceMaskCrop: PortraitAnalysisCrop? = nil
  var alpha: [Double]? = nil
  var unavailableReason: String? = nil

  func validate(width: Int, height: Int) throws {
    guard schemaVersion == 1, quality == "accurate", self.width == width, self.height == height,
      requestRevision.map({ $0 > 0 }) ?? (status == .notRequested), !platformVersion.isEmpty
    else { throw PortraitDrawingError.unreadableImage }
    if let alpha {
      guard alpha.count == width * height, alpha.allSatisfy({ $0.isFinite && (0...1).contains($0) })
      else { throw PortraitDrawingError.unreadableImage }
    }
    if sourceMaskWidth != nil || sourceMaskHeight != nil {
      guard let sourceMaskWidth, let sourceMaskHeight, sourceMaskWidth > 0, sourceMaskHeight > 0
      else { throw PortraitDrawingError.unreadableImage }
    }
    if alpha != nil, sourceMaskCrop == nil { throw PortraitDrawingError.unreadableImage }
    if let crop = sourceMaskCrop {
      guard let maskWidth = sourceMaskWidth, let maskHeight = sourceMaskHeight,
        maskWidth > 0, maskHeight > 0,
        [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite),
        crop.x >= 0, crop.y >= 0, crop.width > 0, crop.height > 0,
        crop.x + crop.width <= Double(maskWidth), crop.y + crop.height <= Double(maskHeight)
      else { throw PortraitDrawingError.unreadableImage }
    }
    if status == .applied {
      guard let alpha, alpha.contains(where: { $0 > 0.5 }), sourceMaskCrop != nil,
        unavailableReason == nil else { throw PortraitDrawingError.unreadableImage }
    }
    if status == .noPerson, alpha?.contains(where: { $0 > 0.5 }) == true {
      throw PortraitDrawingError.unreadableImage
    }
    if [.noPerson, .cropUnavailable, .unavailable].contains(status) {
      guard let unavailableReason, !unavailableReason.isEmpty else { throw PortraitDrawingError.unreadableImage }
    }
    if status == .notRequested {
      guard requestRevision == nil, alpha == nil, sourceMaskCrop == nil
      else { throw PortraitDrawingError.unreadableImage }
    }
  }
}
