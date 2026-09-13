import CoreGraphics
import Foundation
import Testing
import Vision

@testable import PlotterApp

@Suite("Retained semantic face analysis")
struct PortraitFaceLandmarkAnalysisTests {
  @Test("Vision face-local points become exact decoded top-left pixels before crop")
  func coordinateMapping() {
    let region = PortraitFaceLandmarkAnalyzer.retainRegion(kind: .leftEye,
      normalizedPoints: [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0.25, y: 0.75)],
      precisionEstimates: [0.125, 2.75, 0.5], pointsClassification: 2,
      boundingBox: CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.5), width: 1200, height: 800)
    #expect(region.points == [PortraitLandmarkPoint(x: 300, y: 700),
      PortraitLandmarkPoint(x: 900, y: 300), PortraitLandmarkPoint(x: 450, y: 400)])
    #expect(region.precisionEstimates == [0.125, 2.75, 0.5])
    #expect(region.pointsClassification == 2)
    let box = PortraitFaceLandmarkAnalyzer.decodedBox(
      CGRect(x: 0.25, y: 0.125, width: 0.5, height: 0.5), width: 1200, height: 800)
    #expect(box == PortraitAnalysisCrop(x: 300, y: 300, width: 600, height: 400))
    // Non-square decoded dimensions never become normalized-square geometry.
    #expect(region.points[1].x - region.points[0].x == 600)
    #expect(region.points[0].y - region.points[1].y == 400)
  }

  @Test("largest observed face retains supplied pose radians without inferring landmarks")
  func retainedPoseAndLargestFace() throws {
    let smaller = VNFaceObservation(requestRevision: VNRequestRevisionUnspecified,
      boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.1), roll: nil, yaw: nil, pitch: nil)
    let larger = VNFaceObservation(requestRevision: VNRequestRevisionUnspecified,
      boundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.5),
      roll: NSNumber(value: 0.61), yaw: NSNumber(value: -0.73), pitch: NSNumber(value: 0.12))
    let retained = PortraitFaceLandmarkAnalyzer.retain(observations: [larger, smaller], width: 1000, height: 800)
    #expect(retained.status == .detected)
    #expect(retained.roll == 0.61 && retained.yaw == -0.73 && retained.pitch == 0.12)
    #expect(retained.boundingBox?.width == 400 && retained.boundingBox?.height == 400)
    #expect(retained.regions.isEmpty)
    #expect(retained.landmarksConfidence == nil)
    #expect(retained.unavailableReason?.contains("no facial landmarks") == true)
    #expect(retained.requestRevision == 3)
    #expect(retained.constellation == Int(VNRequestFaceLandmarksConstellation.constellation76Points.rawValue))
    try retained.validate()
    let restored = try JSONDecoder().decode(PortraitFaceAnalysis.self, from: JSONEncoder().encode(retained))
    #expect(restored == retained)
  }

  @Test("unknown pose stays unknown and absent regions are not synthesized")
  func unknownPose() {
    let observation = VNFaceObservation(requestRevision: VNRequestRevisionUnspecified,
      boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6), roll: nil, yaw: nil, pitch: nil)
    let retained = PortraitFaceLandmarkAnalyzer.retain(observations: [observation], width: 600, height: 800)
    #expect(retained.roll == nil && retained.yaw == nil && retained.pitch == nil)
    #expect(retained.region(.faceContour).isEmpty)
    #expect(retained.region(.leftEye).isEmpty && retained.region(.rightEye).isEmpty)
  }

  @Test("no face and failed request remain distinct versioned evidence")
  func missingAnalysis() throws {
    let noFace = PortraitFaceLandmarkAnalyzer.retain(observations: [], width: 80, height: 60)
    let unavailable = PortraitFaceLandmarkAnalyzer.unavailable(width: 80, height: 60, reason: "test request failure")
    #expect(noFace.status == .noFace && noFace.unavailableReason == nil)
    #expect(unavailable.status == .unavailable && unavailable.unavailableReason == "test request failure")
    for analysis in [noFace, unavailable] {
      #expect(analysis.requestRevision == 3 && analysis.constellation == 2)
      #expect(!analysis.platformVersion.isEmpty)
      #expect(analysis.boundingBox == nil && analysis.observationConfidence == nil)
      #expect(analysis.regions.isEmpty && analysis.pitch == nil)
      try analysis.validate()
      #expect(try JSONDecoder().decode(PortraitFaceAnalysis.self,
        from: JSONEncoder().encode(analysis)) == analysis)
    }
  }

  @Test("full-photo analysis retains its actual face outcome without claiming a human fixture")
  func fullPhotoEvidence() throws {
    let raster = try PortraitImageAnalyzer.analyze(data: portraitTestImage(),
      options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    let analysis = try #require(raster.faceAnalysis)
    let geometry = try #require(raster.analysisGeometry)
    #expect(analysis.decodedWidth == geometry.decodedWidth)
    #expect(analysis.decodedHeight == geometry.decodedHeight)
    #expect(geometry.crop.x == 0 && geometry.crop.y == 0)
    #expect(analysis.requestRevision == 3 && analysis.constellation == 2)
    #expect(raster.provenance.contains("faceAnalysisStatus=\(analysis.status.rawValue)"))
    #expect(raster.provenance.contains("faceRequestRevision=3"))
    #expect(raster.personMask?.status == .notRequested)
    let restored = try JSONDecoder().decode(PortraitRaster.self, from: JSONEncoder().encode(raster))
    #expect(restored.faceAnalysis == analysis)
    #expect(restored.analysisGeometry == geometry)
    #expect(restored.sourceCropExtent == raster.sourceCropExtent)
    try restored.validateAnalysisEvidence()
  }
}
