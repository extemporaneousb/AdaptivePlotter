import Foundation
import PlotterModel

public enum PlotterDrawingDraftIntent: Hashable, Sendable {
  case showTarget
  case hideTarget
  case selectCatalogItem(DrawingCatalogEntryID)
  case selectProgram(DrawingProgram)
  case placeAtCameraPoint(PlotterDrawingDraftCameraPlacement)
  case setUniformScale(Double)
  case setRotationDegrees(Double)
  case centerInDrawableRegion
  case fitInDrawableRegion
  case beginNewPlan
  case assertPaperCoverage
  case prepareCoverageExperiment
  case nextCoverageTrial
  case leaveCoverageExperiment
  case selectResidualRecord(DrawingEvidenceRecordID, selected: Bool)
  case analyzeSelectedResiduals
}

public struct PlotterDrawingDraftCameraPlacement: Hashable, Sendable {
  public let frame: PlotterExactFrameReference
  public let point: Point2<CameraPixelSpace>

  public init(frame: PlotterExactFrameReference, point: Point2<CameraPixelSpace>) {
    self.frame = frame
    self.point = point
  }
}

public struct PlotterDrawingDraftRevision:
  RawRepresentable, Hashable, Comparable, Sendable
{
  public let rawValue: UInt64

  public init(rawValue: UInt64) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

public struct PlotterDrawingDraftRequestID: RawRepresentable, Hashable, Sendable {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }
}
