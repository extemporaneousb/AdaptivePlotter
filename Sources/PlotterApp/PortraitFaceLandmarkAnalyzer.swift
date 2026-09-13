import CoreGraphics
import Foundation
import Vision

/// The only Vision adapter for retained semantic face analysis. Vision points are
/// normalized within its lower-left-origin face box; archived points use the
/// exact decoded image's top-left-origin pixels, before any face crop or sampling.
enum PortraitFaceLandmarkAnalyzer {
  static let requestRevision = VNDetectFaceLandmarksRequestRevision3
  static let constellation = VNRequestFaceLandmarksConstellation.constellation76Points

  static func analyze(_ image: CGImage) throws -> PortraitFaceAnalysis {
    try Task.checkCancellation()
    let request = VNDetectFaceLandmarksRequest()
    request.revision = requestRevision
    request.constellation = constellation
    do {
      try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
      try Task.checkCancellation()
      let result = retain(observations: request.results ?? [], width: image.width, height: image.height)
      try result.validate()
      return result
    } catch is CancellationError { throw CancellationError() }
    catch {
      return unavailable(width: image.width, height: image.height, reason: error.localizedDescription)
    }
  }

  static func retain(observations: [VNFaceObservation], width: Int, height: Int) -> PortraitFaceAnalysis {
    guard let face = observations.max(by: {
      $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
    }) else {
      return record(status: .noFace, width: width, height: height)
    }
    let landmarks = face.landmarks
    let regions: [(PortraitFaceRegion, VNFaceLandmarkRegion2D?)] = [
      (.faceContour, landmarks?.faceContour), (.leftEye, landmarks?.leftEye),
      (.rightEye, landmarks?.rightEye), (.leftEyebrow, landmarks?.leftEyebrow),
      (.rightEyebrow, landmarks?.rightEyebrow), (.nose, landmarks?.nose),
      (.noseCrest, landmarks?.noseCrest), (.medianLine, landmarks?.medianLine),
      (.outerLips, landmarks?.outerLips), (.innerLips, landmarks?.innerLips),
      (.leftPupil, landmarks?.leftPupil), (.rightPupil, landmarks?.rightPupil),
    ]
    return record(status: .detected, width: width, height: height,
      reason: landmarks == nil ? "Vision located a face but returned no facial landmarks" : nil,
      boundingBox: decodedBox(face.boundingBox, width: width, height: height),
      observationConfidence: Double(face.confidence), landmarksConfidence: landmarks.map { Double($0.confidence) },
      roll: face.roll?.doubleValue, yaw: face.yaw?.doubleValue, pitch: face.pitch?.doubleValue,
      regions: regions.compactMap { kind, region -> PortraitLandmarkRegion? in
        guard let region else { return nil }
        return retainRegion(kind: kind, normalizedPoints: region.normalizedPoints,
          precisionEstimates: region.precisionEstimatesPerPoint?.map { Double($0) },
          pointsClassification: Int(region.pointsClassification.rawValue),
          boundingBox: face.boundingBox, width: width, height: height)
      })
  }

  static func retainRegion(kind: PortraitFaceRegion, normalizedPoints: [CGPoint],
    precisionEstimates: [Double]?, pointsClassification: Int,
    boundingBox: CGRect, width: Int, height: Int) -> PortraitLandmarkRegion {
    PortraitLandmarkRegion(kind: kind,
      points: normalizedPoints.map { point in
        PortraitLandmarkPoint(x: (boundingBox.minX + point.x * boundingBox.width) * Double(width),
          y: (1 - boundingBox.minY - point.y * boundingBox.height) * Double(height))
      }, precisionEstimates: precisionEstimates, pointsClassification: pointsClassification)
  }

  static func decodedBox(_ box: CGRect, width: Int, height: Int) -> PortraitAnalysisCrop {
    PortraitAnalysisCrop(x: box.minX * Double(width), y: (1 - box.maxY) * Double(height),
      width: box.width * Double(width), height: box.height * Double(height))
  }

  static func unavailable(width: Int, height: Int, reason: String) -> PortraitFaceAnalysis {
    record(status: .unavailable, width: width, height: height, reason: reason)
  }

  private static func record(status: PortraitFaceAnalysisStatus, width: Int, height: Int,
    reason: String? = nil, boundingBox: PortraitAnalysisCrop? = nil,
    observationConfidence: Double? = nil, landmarksConfidence: Double? = nil,
    roll: Double? = nil, yaw: Double? = nil, pitch: Double? = nil,
    regions: [PortraitLandmarkRegion] = []) -> PortraitFaceAnalysis {
    PortraitFaceAnalysis(requestRevision: requestRevision, constellation: Int(constellation.rawValue),
      platformVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      status: status, unavailableReason: reason, decodedWidth: width, decodedHeight: height,
      boundingBox: boundingBox, observationConfidence: observationConfidence,
      landmarksConfidence: landmarksConfidence, roll: roll, yaw: yaw, pitch: pitch, regions: regions)
  }
}
