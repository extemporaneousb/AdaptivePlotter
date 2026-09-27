import Foundation
import PlotterModel

/// Physical geometry for newly planned four-circle calibration. Historical
/// registration decoders retain their recorded geometry independently.
public enum TipCalibrationWorkingRegionPolicy {
  public static let centerInsetMM = 10.0
  public static let circleRadiusMM = 2.0
  public static let minimumCircleGapMM = 1.0
  public static let minimumSpanMM = 2 * centerInsetMM + 2 * circleRadiusMM + minimumCircleGapMM

  public static func permitsSpan(_ span: Double) -> Bool {
    span.isFinite && span >= minimumSpanMM - DrawingRegionContainmentPolicy.numericalEpsilonMM
  }

  public static func contains(_ bounds: AxisAlignedBounds<MachineSpace>, in boundary: AxisAlignedBounds<MachineSpace>) -> Bool {
    let epsilon = DrawingRegionContainmentPolicy.numericalEpsilonMM
    return bounds.minX >= boundary.minX - epsilon && bounds.minY >= boundary.minY - epsilon
      && bounds.maxX <= boundary.maxX + epsilon && bounds.maxY <= boundary.maxY + epsilon
  }
}
