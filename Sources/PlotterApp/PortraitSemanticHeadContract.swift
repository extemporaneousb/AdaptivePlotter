import Foundation

/// Coordinates are top-left-origin pixels of the exact decoded image, before crop.
struct PortraitLandmarkPoint: Codable, Hashable, Sendable {
  let x: Double
  let y: Double
}

enum PortraitFaceRegion: String, Codable, Hashable, Sendable {
  case faceContour, leftEye, rightEye, leftEyebrow, rightEyebrow
  case nose, noseCrest, medianLine, outerLips, innerLips, leftPupil, rightPupil
}

struct PortraitLandmarkRegion: Codable, Hashable, Sendable {
  let kind: PortraitFaceRegion
  let points: [PortraitLandmarkPoint]
  /// Vision's raw precision estimates, not confidence values or physical units.
  let precisionEstimates: [Double]?
  let pointsClassification: Int
}

enum PortraitFaceAnalysisStatus: String, Codable, Hashable, Sendable {
  case detected, noFace, unavailable
}

struct PortraitFaceAnalysis: Codable, Hashable, Sendable {
  var schemaVersion = 1
  var algorithmRevision = "portrait-face-landmarks-v1"
  let requestRevision: Int
  let constellation: Int
  let platformVersion: String
  let status: PortraitFaceAnalysisStatus
  let unavailableReason: String?
  let decodedWidth: Int
  let decodedHeight: Int
  let boundingBox: PortraitAnalysisCrop?
  let observationConfidence: Double?
  let landmarksConfidence: Double?
  /// Vision orientation in radians. Missing values remain unknown.
  let roll: Double?
  let yaw: Double?
  let pitch: Double?
  let regions: [PortraitLandmarkRegion]

  func region(_ kind: PortraitFaceRegion) -> [PortraitLandmarkPoint] {
    regions.first { $0.kind == kind }?.points ?? []
  }

  func validate() throws {
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
}

/// Relative semantic amplitudes; zero is identity. Nil on an older recipe keeps
/// that recipe's encoding and archived identity unchanged. New Big Head uses v1.
struct PortraitSemanticHeadParameters: Codable, Hashable, Sendable {
  var revision = "semantic-head-v1"
  var foreheadWidth = 0.24
  var foreheadHeight = 0.28
  var eyeScale = 0.12
  var lateralScale = 0.12

  var bounded: Self {
    var result = self
    result.foreheadWidth = Self.limit(foreheadWidth)
    result.foreheadHeight = Self.limit(foreheadHeight)
    result.eyeScale = Self.limit(eyeScale)
    result.lateralScale = Self.limit(lateralScale)
    return result
  }
  private static func limit(_ value: Double) -> Double { value.isFinite ? min(0.6, max(0, value)) : 0 }
}
