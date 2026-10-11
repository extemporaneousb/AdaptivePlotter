import Foundation

/// Coordinates are top-left-origin pixels of the exact decoded image, before crop.
package struct PortraitLandmarkPoint: Codable, Hashable, Sendable {
  package let x: Double
  package let y: Double

  package init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

package enum PortraitFaceRegion: String, Codable, Hashable, Sendable {
  case faceContour, leftEye, rightEye, leftEyebrow, rightEyebrow
  case nose, noseCrest, medianLine, outerLips, innerLips, leftPupil, rightPupil
}

package struct PortraitLandmarkRegion: Codable, Hashable, Sendable {
  package let kind: PortraitFaceRegion
  package let points: [PortraitLandmarkPoint]
  /// Vision's raw precision estimates, not confidence values or physical units.
  package let precisionEstimates: [Double]?
  package let pointsClassification: Int

  package init(
    kind: PortraitFaceRegion,
    points: [PortraitLandmarkPoint],
    precisionEstimates: [Double]? = nil,
    pointsClassification: Int
  ) {
    self.kind = kind
    self.points = points
    self.precisionEstimates = precisionEstimates
    self.pointsClassification = pointsClassification
  }
}

package enum PortraitFaceAnalysisStatus: String, Codable, Hashable, Sendable {
  case detected, noFace, unavailable
}

package struct PortraitFaceAnalysis: Codable, Hashable, Sendable {
  package var schemaVersion = 1
  package var algorithmRevision = "portrait-face-landmarks-v1"
  package let requestRevision: Int
  package let constellation: Int
  package let platformVersion: String
  package let status: PortraitFaceAnalysisStatus
  package let unavailableReason: String?
  package let decodedWidth: Int
  package let decodedHeight: Int
  package let boundingBox: PortraitAnalysisCrop?
  package let observationConfidence: Double?
  package let landmarksConfidence: Double?
  /// Vision orientation in radians. Missing values remain unknown.
  package let roll: Double?
  package let yaw: Double?
  package let pitch: Double?
  package let regions: [PortraitLandmarkRegion]

  package func region(_ kind: PortraitFaceRegion) -> [PortraitLandmarkPoint] {
    regions.first { $0.kind == kind }?.points ?? []
  }

  package func validate() throws {
    guard schemaVersion == 1, algorithmRevision == "portrait-face-landmarks-v1",
      requestRevision > 0, decodedWidth > 0, decodedHeight > 0, !platformVersion.isEmpty,
      Set(regions.map(\.kind)).count == regions.count,
      [observationConfidence, landmarksConfidence].compactMap({ $0 }).allSatisfy({ (0...1).contains($0) }),
      [observationConfidence, landmarksConfidence, roll, yaw, pitch].compactMap({ $0 }).allSatisfy(\.isFinite),
      regions.allSatisfy({ region in
        region.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.x >= 0 && $0.y >= 0
          && $0.x <= Double(decodedWidth) && $0.y <= Double(decodedHeight) }
          && (region.precisionEstimates?.allSatisfy { $0.isFinite && $0 >= 0 } ?? true)
          && (region.precisionEstimates.map { $0.count == region.points.count } ?? true)
      }) else { throw PortraitDrawingError.unreadableImage }
    if let boundingBox {
      guard [boundingBox.x, boundingBox.y, boundingBox.width, boundingBox.height].allSatisfy(\.isFinite),
        boundingBox.width > 0, boundingBox.height > 0 else { throw PortraitDrawingError.unreadableImage }
    }
  }

  package init(
    schemaVersion: Int = 1,
    algorithmRevision: String = "portrait-face-landmarks-v1",
    requestRevision: Int,
    constellation: Int,
    platformVersion: String,
    status: PortraitFaceAnalysisStatus,
    unavailableReason: String? = nil,
    decodedWidth: Int,
    decodedHeight: Int,
    boundingBox: PortraitAnalysisCrop? = nil,
    observationConfidence: Double? = nil,
    landmarksConfidence: Double? = nil,
    roll: Double? = nil,
    yaw: Double? = nil,
    pitch: Double? = nil,
    regions: [PortraitLandmarkRegion]
  ) {
    self.schemaVersion = schemaVersion
    self.algorithmRevision = algorithmRevision
    self.requestRevision = requestRevision
    self.constellation = constellation
    self.platformVersion = platformVersion
    self.status = status
    self.unavailableReason = unavailableReason
    self.decodedWidth = decodedWidth
    self.decodedHeight = decodedHeight
    self.boundingBox = boundingBox
    self.observationConfidence = observationConfidence
    self.landmarksConfidence = landmarksConfidence
    self.roll = roll
    self.yaw = yaw
    self.pitch = pitch
    self.regions = regions
  }
}

/// Relative semantic amplitudes; zero is identity. Nil on an older recipe keeps
/// that recipe's encoding and archived identity unchanged. New Big Head uses v1.
package struct PortraitSemanticHeadParameters: Codable, Hashable, Sendable {
  package var revision = "semantic-head-v1"
  package var foreheadWidth = 0.24
  package var foreheadHeight = 0.28
  package var eyeScale = 0.12
  package var lateralScale = 0.12

  package var bounded: Self {
    var result = self
    result.foreheadWidth = Self.limit(foreheadWidth)
    result.foreheadHeight = Self.limit(foreheadHeight)
    result.eyeScale = Self.limit(eyeScale)
    result.lateralScale = Self.limit(lateralScale)
    return result
  }
  private static func limit(_ value: Double) -> Double { value.isFinite ? min(0.6, max(0, value)) : 0 }

  package init(
    revision: String = "semantic-head-v1",
    foreheadWidth: Double = 0.24,
    foreheadHeight: Double = 0.28,
    eyeScale: Double = 0.12,
    lateralScale: Double = 0.12
  ) {
    self.revision = revision
    self.foreheadWidth = foreheadWidth
    self.foreheadHeight = foreheadHeight
    self.eyeScale = eyeScale
    self.lateralScale = lateralScale
  }
}
