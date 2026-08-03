import Foundation

public enum RegistrationError: Error, Equatable, Sendable {
  case insufficientPoints
  case degenerateGeometry
}

public struct RegistrationCorrespondence: Hashable, Codable, Sendable {
  public let camera: Point2<CameraPixelSpace>
  public let field: Point2<FieldSpace>

  public init(camera: Point2<CameraPixelSpace>, field: Point2<FieldSpace>) {
    self.camera = camera
    self.field = field
  }
}

/// One affine camera-to-field fit for the current local setup.
///
/// All supplied correspondences participate in the fit. The reported residual
/// is diagnostic; it does not create a promotion workflow or development gate.
public struct FieldRegistration: Hashable, Codable, Sendable {
  public let id: FieldRegistrationID
  public let fieldFromCamera: AffineTransform2<CameraPixelSpace, FieldSpace>
  public let correspondences: [RegistrationCorrespondence]
  public let rootMeanSquareError: Double
  public let maximumError: Double

  public static func fit(
    id: FieldRegistrationID,
    correspondences: [RegistrationCorrespondence]
  ) throws -> Self {
    guard correspondences.count >= 3 else { throw RegistrationError.insufficientPoints }
    let transform = try fitAffine(correspondences)
    let errors = try correspondences.map {
      try transform.applying(to: $0.camera).distance(to: $0.field)
    }
    let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count))
    return Self(
      id: id,
      fieldFromCamera: transform,
      correspondences: correspondences,
      rootMeanSquareError: rms,
      maximumError: errors.max() ?? 0
    )
  }

  public func fieldPoint(from cameraPoint: Point2<CameraPixelSpace>) throws -> Point2<FieldSpace> {
    try fieldFromCamera.applying(to: cameraPoint)
  }

  public func cameraPoint(from fieldPoint: Point2<FieldSpace>) throws -> Point2<CameraPixelSpace> {
    try fieldFromCamera.inverted().applying(to: fieldPoint)
  }
}

private func fitAffine(
  _ samples: [RegistrationCorrespondence]
) throws -> AffineTransform2<CameraPixelSpace, FieldSpace> {
  let count = Double(samples.count)
  let centerX = samples.reduce(0) { $0 + $1.camera.x } / count
  let centerY = samples.reduce(0) { $0 + $1.camera.y } / count
  let averageSquaredRadius = samples.reduce(0) { partial, sample in
    let x = sample.camera.x - centerX
    let y = sample.camera.y - centerY
    return partial + x * x + y * y
  } / count
  let scale = sqrt(averageSquaredRadius)
  guard scale.isFinite, scale > 1e-12 else { throw RegistrationError.degenerateGeometry }

  let normalized = samples.map { sample in
    ((sample.camera.x - centerX) / scale, (sample.camera.y - centerY) / scale, sample.field)
  }
  let sxx = normalized.reduce(0) { $0 + $1.0 * $1.0 } / count
  let syy = normalized.reduce(0) { $0 + $1.1 * $1.1 } / count
  let sxy = normalized.reduce(0) { $0 + $1.0 * $1.1 } / count
  guard sxx * syy - sxy * sxy > 1e-10 else {
    throw RegistrationError.degenerateGeometry
  }

  var normal = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
  var targetX = Array(repeating: 0.0, count: 3)
  var targetY = Array(repeating: 0.0, count: 3)
  for sample in normalized {
    let row = [sample.0, sample.1, 1.0]
    for i in 0..<3 {
      targetX[i] += row[i] * sample.2.x
      targetY[i] += row[i] * sample.2.y
      for j in 0..<3 { normal[i][j] += row[i] * row[j] }
    }
  }
  let betaX = try solve3x3(normal, targetX)
  let betaY = try solve3x3(normal, targetY)
  let m11 = betaX[0] / scale
  let m12 = betaX[1] / scale
  let m21 = betaY[0] / scale
  let m22 = betaY[1] / scale
  return try AffineTransform2(
    m11: m11,
    m12: m12,
    m21: m21,
    m22: m22,
    tx: betaX[2] - m11 * centerX - m12 * centerY,
    ty: betaY[2] - m21 * centerX - m22 * centerY
  )
}

private func solve3x3(_ matrix: [[Double]], _ rightHandSide: [Double]) throws -> [Double] {
  var augmented = zip(matrix, rightHandSide).map { $0 + [$1] }
  for column in 0..<3 {
    var pivot = column
    for candidate in (column + 1)..<3
    where abs(augmented[candidate][column]) > abs(augmented[pivot][column]) {
      pivot = candidate
    }
    guard abs(augmented[pivot][column]) > 1e-12 else {
      throw RegistrationError.degenerateGeometry
    }
    if pivot != column { augmented.swapAt(pivot, column) }
    let divisor = augmented[column][column]
    for index in column..<4 { augmented[column][index] /= divisor }
    for row in 0..<3 where row != column {
      let factor = augmented[row][column]
      for index in column..<4 {
        augmented[row][index] -= factor * augmented[column][index]
      }
    }
  }
  return augmented.map { $0[3] }
}

/// The complete drawing model for the first working version: one affine map,
/// an optional constant field-space correction, and the known machine bounds.
public struct DrawingTransform: Hashable, Codable, Sendable {
  public let machineToField: AffineTransform2<MachineSpace, FieldSpace>
  public let constantFieldCorrection: Vector2<FieldSpace>
  public let machineDomain: AxisAlignedBounds<MachineSpace>

  public init(
    machineToField: AffineTransform2<MachineSpace, FieldSpace>,
    constantFieldCorrection: Vector2<FieldSpace> = try! Vector2(dx: 0, dy: 0),
    machineDomain: AxisAlignedBounds<MachineSpace>
  ) {
    self.machineToField = machineToField
    self.constantFieldCorrection = constantFieldCorrection
    self.machineDomain = machineDomain
  }

  public func predictedFieldPoint(for machinePoint: Point2<MachineSpace>) throws -> Point2<
    FieldSpace
  > {
    guard machineDomain.contains(machinePoint) else { throw GeometryError.outsideDomain }
    return try machineToField.applying(to: machinePoint).translated(by: constantFieldCorrection)
  }

  public func predictedFieldPath(for machinePath: Polyline<MachineSpace>) throws -> Polyline<
    FieldSpace
  > {
    try Polyline(points: machinePath.points.map(predictedFieldPoint))
  }
}

public enum CommandInverter {
  public static func machinePoint(
    for desiredFieldPoint: Point2<FieldSpace>,
    using transform: DrawingTransform,
    maximumForwardError: Double
  ) throws -> Point2<MachineSpace> {
    guard maximumForwardError.isFinite, maximumForwardError > 0 else {
      throw PlotterModelError.invalidValue("forward error limit must be positive and finite")
    }
    let uncorrected = try desiredFieldPoint.translated(
      by: Vector2(
        dx: -transform.constantFieldCorrection.dx,
        dy: -transform.constantFieldCorrection.dy
      ))
    let candidate = try transform.machineToField.inverted().applying(to: uncorrected)
    guard transform.machineDomain.contains(candidate) else { throw GeometryError.outsideDomain }
    let projected = try transform.predictedFieldPoint(for: candidate)
    let error = projected.distance(to: desiredFieldPoint)
    guard error <= maximumForwardError else {
      throw GeometryError.forwardCheckFailed(error: error, limit: maximumForwardError)
    }
    return candidate
  }

  public static func machinePath(
    for desiredFieldPath: Polyline<FieldSpace>,
    using transform: DrawingTransform,
    maximumForwardError: Double
  ) throws -> Polyline<MachineSpace> {
    try Polyline(
      points: desiredFieldPath.points.map {
        try machinePoint(
          for: $0,
          using: transform,
          maximumForwardError: maximumForwardError
        )
      })
  }
}
