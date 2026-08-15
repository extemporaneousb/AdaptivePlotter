import Foundation

public enum RegistrationError: Error, Equatable, Sendable {
  case insufficientPoints
  case degenerateGeometry
}

public struct MachineCameraRegistrationCorrespondence: Hashable, Codable, Sendable {
  public let machine: Point2<MachineSpace>
  public let camera: Point2<CameraPixelSpace>

  public init(machine: Point2<MachineSpace>, camera: Point2<CameraPixelSpace>) {
    self.machine = machine
    self.camera = camera
  }
}

/// A current-session affine fit from controller coordinates to exact camera
/// pixels. Context and evidence identities deliberately live in the runtime's
/// provenance wrapper; this value contains only the fitted geometry and errors.
public struct MachineCameraRegistrationFit: Hashable, Codable, Sendable {
  public let cameraFromMachine: AffineTransform2<MachineSpace, CameraPixelSpace>
  public let correspondences: [MachineCameraRegistrationCorrespondence]
  public let rootMeanSquareErrorPixels: Double
  public let maximumErrorPixels: Double

  public static func fit(
    correspondences: [MachineCameraRegistrationCorrespondence]
  ) throws -> Self {
    try fit(
      correspondences: correspondences,
      weights: Array(repeating: 1, count: correspondences.count)
    )
  }

  /// Weighted least squares. Weights are evidence precision, not presentation
  /// confidence; every value must be finite and strictly positive.
  public static func fit(
    correspondences: [MachineCameraRegistrationCorrespondence],
    weights: [Double]
  ) throws -> Self {
    guard correspondences.count >= 3 else { throw RegistrationError.insufficientPoints }
    guard weights.count == correspondences.count,
      weights.allSatisfy({ $0.isFinite && $0 > 0 })
    else { throw RegistrationError.degenerateGeometry }
    let transform = try fitMachineCameraAffine(correspondences, weights: weights)
    let errors = try correspondences.map {
      try transform.applying(to: $0.machine).distance(to: $0.camera)
    }
    let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count))
    return Self(
      cameraFromMachine: transform,
      correspondences: correspondences,
      rootMeanSquareErrorPixels: rms,
      maximumErrorPixels: errors.max() ?? 0
    )
  }

  public func cameraPoint(
    from machinePoint: Point2<MachineSpace>
  ) throws -> Point2<CameraPixelSpace> {
    try cameraFromMachine.applying(to: machinePoint)
  }

  public func machinePoint(
    from cameraPoint: Point2<CameraPixelSpace>
  ) throws -> Point2<MachineSpace> {
    try cameraFromMachine.inverted().applying(to: cameraPoint)
  }
}

private func fitMachineCameraAffine(
  _ samples: [MachineCameraRegistrationCorrespondence],
  weights: [Double]
) throws -> AffineTransform2<MachineSpace, CameraPixelSpace> {
  let totalWeight = weights.reduce(0, +)
  let centerX = zip(samples, weights).reduce(0) { $0 + $1.0.machine.x * $1.1 } / totalWeight
  let centerY = zip(samples, weights).reduce(0) { $0 + $1.0.machine.y * $1.1 } / totalWeight
  let averageSquaredRadius = zip(samples, weights).reduce(0) { partial, item in
    let sample = item.0
    let x = sample.machine.x - centerX
    let y = sample.machine.y - centerY
    return partial + item.1 * (x * x + y * y)
  } / totalWeight
  let scale = sqrt(averageSquaredRadius)
  guard scale.isFinite, scale > 1e-12 else { throw RegistrationError.degenerateGeometry }

  let normalized = zip(samples, weights).map { sample, weight in
    (
      (sample.machine.x - centerX) / scale,
      (sample.machine.y - centerY) / scale,
      sample.camera,
      weight
    )
  }
  let sxx = normalized.reduce(0) { $0 + $1.3 * $1.0 * $1.0 } / totalWeight
  let syy = normalized.reduce(0) { $0 + $1.3 * $1.1 * $1.1 } / totalWeight
  let sxy = normalized.reduce(0) { $0 + $1.3 * $1.0 * $1.1 } / totalWeight
  guard sxx * syy - sxy * sxy > 1e-10 else {
    throw RegistrationError.degenerateGeometry
  }

  var normal = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
  var targetX = Array(repeating: 0.0, count: 3)
  var targetY = Array(repeating: 0.0, count: 3)
  for sample in normalized {
    let row = [sample.0, sample.1, 1.0]
    for i in 0..<3 {
      targetX[i] += sample.3 * row[i] * sample.2.x
      targetY[i] += sample.3 * row[i] * sample.2.y
      for j in 0..<3 { normal[i][j] += sample.3 * row[i] * row[j] }
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
