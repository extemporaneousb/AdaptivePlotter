import Foundation

/// Exact top-left-origin crop in the bounded decoded image's pixel coordinates.
package struct PortraitAnalysisCrop: Codable, Hashable, Sendable {
  package let x: Double
  package let y: Double
  package let width: Double
  package let height: Double

  package init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

package enum PortraitRasterSampling: String, Codable, Hashable, Sendable {
  case pixelCentersV1 = "pixel-centers-v1"
}

/// Retained numerical inputs for the crop, resampling and contrast stages.
/// Source extents are oriented original-image pixels, not controller units.
package struct PortraitAnalysisGeometry: Codable, Hashable, Sendable {
  package var schemaVersion = 1
  package let sourcePixelExtent: PortraitSourceCropExtent
  package let decodedWidth: Int
  package let decodedHeight: Int
  package let crop: PortraitAnalysisCrop
  package let rasterWidth: Int
  package let rasterHeight: Int
  package var sampling: PortraitRasterSampling = .pixelCentersV1
  package var preprocessingRevision = "portrait-analysis-v1"
  package let contrastLow: Double
  package let contrastHigh: Double
  package let contrastApplied: Bool

  package func validate(width: Int, height: Int) throws {
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

  package init(
    schemaVersion: Int = 1,
    sourcePixelExtent: PortraitSourceCropExtent,
    decodedWidth: Int,
    decodedHeight: Int,
    crop: PortraitAnalysisCrop,
    rasterWidth: Int,
    rasterHeight: Int,
    sampling: PortraitRasterSampling = .pixelCentersV1,
    preprocessingRevision: String = "portrait-analysis-v1",
    contrastLow: Double,
    contrastHigh: Double,
    contrastApplied: Bool
  ) {
    self.schemaVersion = schemaVersion
    self.sourcePixelExtent = sourcePixelExtent
    self.decodedWidth = decodedWidth
    self.decodedHeight = decodedHeight
    self.crop = crop
    self.rasterWidth = rasterWidth
    self.rasterHeight = rasterHeight
    self.sampling = sampling
    self.preprocessingRevision = preprocessingRevision
    self.contrastLow = contrastLow
    self.contrastHigh = contrastHigh
    self.contrastApplied = contrastApplied
  }
}

package enum PortraitPersonMaskStatus: String, Codable, Hashable, Sendable {
  case notRequested, applied, noPerson, cropUnavailable, unavailable
}

/// The exact raster-resolution alpha used by background whitening. Raw Vision
/// results are never recreated by assuming the same request revision is repeatable.
package struct PortraitPersonMask: Codable, Hashable, Sendable {
  package var schemaVersion = 1
  package let status: PortraitPersonMaskStatus
  package let requestRevision: Int?
  package let platformVersion: String
  package var quality = "accurate"
  package let width: Int
  package let height: Int
  package var sourceMaskWidth: Int? = nil
  package var sourceMaskHeight: Int? = nil
  package var sourceMaskCrop: PortraitAnalysisCrop? = nil
  package var alpha: [Double]? = nil
  package var unavailableReason: String? = nil

  package func validate(width: Int, height: Int) throws {
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

  package init(
    schemaVersion: Int = 1,
    status: PortraitPersonMaskStatus,
    requestRevision: Int? = nil,
    platformVersion: String,
    quality: String = "accurate",
    width: Int,
    height: Int,
    sourceMaskWidth: Int? = nil,
    sourceMaskHeight: Int? = nil,
    sourceMaskCrop: PortraitAnalysisCrop? = nil,
    alpha: [Double]? = nil,
    unavailableReason: String? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.status = status
    self.requestRevision = requestRevision
    self.platformVersion = platformVersion
    self.quality = quality
    self.width = width
    self.height = height
    self.sourceMaskWidth = sourceMaskWidth
    self.sourceMaskHeight = sourceMaskHeight
    self.sourceMaskCrop = sourceMaskCrop
    self.alpha = alpha
    self.unavailableReason = unavailableReason
  }
}
