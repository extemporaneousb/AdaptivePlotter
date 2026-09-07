import Foundation
import PlotterModel

public enum PlotterDrawingDraftIntent: Hashable, Sendable {
  case open
  case close
  case selectCatalogItem(DrawingCatalogEntryID)
  case selectProgram(DrawingProgram)
  case setEvidenceRole(BorderValidationEvidenceRole)
  case placeAtCameraPoint(PlotterDrawingDraftCameraPlacement)
  case setUniformScale(Double)
  case setRotationDegrees(Double)
  case centerInDrawableRegion
  case beginNewPlan
  case assertPaperCoverage
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
