import Foundation
import PlotterModel
@testable import PlotterApp

func cameraArtworkControllerHeight(sourceDelta: Vector2<FieldSpace>, machineDelta: Vector2<MachineSpace>,
  fieldHeight: Double, camera: DrawingCameraGeometry) throws -> Double {
  let inverse = try camera.commandCorrection.inverted()
  let x = inverse.m11 * machineDelta.dx + inverse.m12 * machineDelta.dy
  let y = inverse.m21 * machineDelta.dx + inverse.m22 * machineDelta.dy
  let squaredLength = sourceDelta.dx * sourceDelta.dx + sourceDelta.dy * sourceDelta.dy
  guard squaredLength > 0 else { throw PortraitCandidateError.invalidPresentation }
  let p = (x * sourceDelta.dx + y * sourceDelta.dy) / squaredLength
  let q = (y * sourceDelta.dx - x * sourceDelta.dy) / squaredLength
  let k = camera.commandCorrection
  let height = fieldHeight * hypot(-k.m11 * q + k.m12 * p, -k.m21 * q + k.m22 * p)
  guard height.isFinite, height > 0 else { throw PortraitCandidateError.invalidPresentation }
  return height
}
