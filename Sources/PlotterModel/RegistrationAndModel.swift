import Foundation

public enum RegistrationError: Error, Equatable, Sendable {
  case insufficientTrainingPoints
  case insufficientHoldoutPoints
  case degenerateTrainingGeometry
  case holdoutIsNotIndependent
  case holdoutValidationFailed(maxError: Double, limit: Double)
}

public struct RegistrationCorrespondence: Hashable, Codable, Sendable, CanonicalEncodable {
  public let camera: Point2<CameraPixelSpace>
  public let field: Point2<FieldSpace>

  public init(camera: Point2<CameraPixelSpace>, field: Point2<FieldSpace>) {
    self.camera = camera
    self.field = field
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try camera.encodeCanonical(to: &encoder)
    try field.encodeCanonical(to: &encoder)
  }
}

public struct RegistrationValidation: Hashable, Codable, Sendable, CanonicalEncodable {
  public let holdoutCount: UInt32
  public let rootMeanSquareError: Double
  public let maximumError: Double
  public let acceptanceLimit: Double

  public init(
    holdoutCount: UInt32,
    rootMeanSquareError: Double,
    maximumError: Double,
    acceptanceLimit: Double
  ) throws {
    guard rootMeanSquareError.isFinite, rootMeanSquareError >= 0,
      maximumError.isFinite, maximumError >= 0,
      acceptanceLimit.isFinite, acceptanceLimit > 0
    else { throw GeometryError.nonFiniteCoordinate }
    self.holdoutCount = holdoutCount
    self.rootMeanSquareError = rootMeanSquareError
    self.maximumError = maximumError
    self.acceptanceLimit = acceptanceLimit
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt32(holdoutCount)
    try encoder.appendDouble(rootMeanSquareError)
    try encoder.appendDouble(maximumError)
    try encoder.appendDouble(acceptanceLimit)
  }

  private enum CodingKeys: String, CodingKey {
    case holdoutCount, rootMeanSquareError, maximumError, acceptanceLimit
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      holdoutCount: container.decode(UInt32.self, forKey: .holdoutCount),
      rootMeanSquareError: container.decode(Double.self, forKey: .rootMeanSquareError),
      maximumError: container.decode(Double.self, forKey: .maximumError),
      acceptanceLimit: container.decode(Double.self, forKey: .acceptanceLimit)
    )
  }
}

public struct FieldRegistration: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: FieldRegistrationID
  public let fieldFromCamera: AffineTransform2<CameraPixelSpace, FieldSpace>
  public let trainingEvidence: [RegistrationCorrespondence]
  public let holdoutEvidence: [RegistrationCorrespondence]
  public let validation: RegistrationValidation

  public static func fit(
    id: FieldRegistrationID,
    training: [RegistrationCorrespondence],
    independentHoldouts: [RegistrationCorrespondence],
    maximumHoldoutError: Double
  ) throws -> Self {
    guard training.count >= 3 else { throw RegistrationError.insufficientTrainingPoints }
    guard independentHoldouts.count >= 2 else { throw RegistrationError.insufficientHoldoutPoints }
    guard maximumHoldoutError.isFinite, maximumHoldoutError > 0 else {
      throw PlotterModelError.invalidValue("maximum holdout error must be positive and finite")
    }

    let independent = independentHoldouts.allSatisfy { holdout in
      !training.contains { sample in
        sample.camera.distance(to: holdout.camera) <= 1e-9
          || sample.field.distance(to: holdout.field) <= 1e-9
      }
    }
    guard independent else { throw RegistrationError.holdoutIsNotIndependent }

    let transform = try fitAffine(training)
    let errors = try independentHoldouts.map {
      try transform.applying(to: $0.camera).distance(to: $0.field)
    }
    guard let maximumError = errors.max() else {
      throw RegistrationError.insufficientHoldoutPoints
    }
    let rms = sqrt(errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count))
    guard maximumError <= maximumHoldoutError else {
      throw RegistrationError.holdoutValidationFailed(
        maxError: maximumError,
        limit: maximumHoldoutError
      )
    }
    return try Self(
      id: id,
      fieldFromCamera: transform,
      trainingEvidence: training,
      holdoutEvidence: independentHoldouts,
      validation: RegistrationValidation(
        holdoutCount: UInt32(independentHoldouts.count),
        rootMeanSquareError: rms,
        maximumError: maximumError,
        acceptanceLimit: maximumHoldoutError
      )
    )
  }

  private init(
    id: FieldRegistrationID,
    fieldFromCamera: AffineTransform2<CameraPixelSpace, FieldSpace>,
    trainingEvidence: [RegistrationCorrespondence],
    holdoutEvidence: [RegistrationCorrespondence],
    validation: RegistrationValidation
  ) throws {
    guard trainingEvidence.count >= 3 else { throw RegistrationError.insufficientTrainingPoints }
    guard holdoutEvidence.count >= 2 else { throw RegistrationError.insufficientHoldoutPoints }
    self.id = id
    self.fieldFromCamera = fieldFromCamera
    self.trainingEvidence = trainingEvidence
    self.holdoutEvidence = holdoutEvidence
    self.validation = validation
  }

  private enum CodingKeys: String, CodingKey {
    case id, fieldFromCamera, trainingEvidence, holdoutEvidence, validation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let encodedTransform = try container.decode(
      AffineTransform2<CameraPixelSpace, FieldSpace>.self,
      forKey: .fieldFromCamera
    )
    let encodedValidation = try container.decode(RegistrationValidation.self, forKey: .validation)
    let fitted = try Self.fit(
      id: container.decode(FieldRegistrationID.self, forKey: .id),
      training: container.decode([RegistrationCorrespondence].self, forKey: .trainingEvidence),
      independentHoldouts: container.decode(
        [RegistrationCorrespondence].self,
        forKey: .holdoutEvidence
      ),
      maximumHoldoutError: encodedValidation.acceptanceLimit
    )
    guard fitted.fieldFromCamera == encodedTransform,
      fitted.validation == encodedValidation
    else { throw PlotterModelError.contentHashMismatch }
    self = fitted
  }

  public func fieldPoint(from cameraPoint: Point2<CameraPixelSpace>) throws -> Point2<FieldSpace> {
    try fieldFromCamera.applying(to: cameraPoint)
  }

  public func cameraPoint(from fieldPoint: Point2<FieldSpace>) throws -> Point2<CameraPixelSpace> {
    try fieldFromCamera.inverted().applying(to: fieldPoint)
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("FieldRegistration")
    try id.encodeCanonical(to: &encoder)
    try fieldFromCamera.encodeCanonical(to: &encoder)
    try encoder.appendCount(trainingEvidence.count)
    for sample in trainingEvidence { try sample.encodeCanonical(to: &encoder) }
    try encoder.appendCount(holdoutEvidence.count)
    for sample in holdoutEvidence { try sample.encodeCanonical(to: &encoder) }
    try validation.encodeCanonical(to: &encoder)
  }
}

private func fitAffine(
  _ samples: [RegistrationCorrespondence]
) throws -> AffineTransform2<CameraPixelSpace, FieldSpace> {
  let count = Double(samples.count)
  let centerX = samples.reduce(0) { $0 + $1.camera.x } / count
  let centerY = samples.reduce(0) { $0 + $1.camera.y } / count
  let averageSquaredRadius =
    samples.reduce(0) { partial, sample in
      let x = sample.camera.x - centerX
      let y = sample.camera.y - centerY
      return partial + x * x + y * y
    } / count
  let scale = sqrt(averageSquaredRadius)
  guard scale.isFinite, scale > 1e-12 else { throw RegistrationError.degenerateTrainingGeometry }

  let normalized = samples.map { sample in
    ((sample.camera.x - centerX) / scale, (sample.camera.y - centerY) / scale, sample.field)
  }
  let sxx = normalized.reduce(0) { $0 + $1.0 * $1.0 } / count
  let syy = normalized.reduce(0) { $0 + $1.1 * $1.1 } / count
  let sxy = normalized.reduce(0) { $0 + $1.0 * $1.1 } / count
  guard sxx * syy - sxy * sxy > 1e-10 else {
    throw RegistrationError.degenerateTrainingGeometry
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
      throw RegistrationError.degenerateTrainingGeometry
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

public struct ModelValidationReport: Hashable, Codable, Sendable, CanonicalEncodable {
  public let independentTrialCount: UInt32
  public let holdoutRootMeanSquareError: Double
  public let holdoutMaximumError: Double
  public let accepted: Bool

  public init(
    independentTrialCount: UInt32,
    holdoutRootMeanSquareError: Double,
    holdoutMaximumError: Double,
    accepted: Bool
  ) throws {
    guard holdoutRootMeanSquareError.isFinite, holdoutRootMeanSquareError >= 0,
      holdoutMaximumError.isFinite, holdoutMaximumError >= 0
    else { throw GeometryError.nonFiniteCoordinate }
    self.independentTrialCount = independentTrialCount
    self.holdoutRootMeanSquareError = holdoutRootMeanSquareError
    self.holdoutMaximumError = holdoutMaximumError
    self.accepted = accepted
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt32(independentTrialCount)
    try encoder.appendDouble(holdoutRootMeanSquareError)
    try encoder.appendDouble(holdoutMaximumError)
    encoder.appendBool(accepted)
  }

  private enum CodingKeys: String, CodingKey {
    case independentTrialCount, holdoutRootMeanSquareError, holdoutMaximumError, accepted
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      independentTrialCount: container.decode(UInt32.self, forKey: .independentTrialCount),
      holdoutRootMeanSquareError: container.decode(
        Double.self,
        forKey: .holdoutRootMeanSquareError
      ),
      holdoutMaximumError: container.decode(Double.self, forKey: .holdoutMaximumError),
      accepted: container.decode(Bool.self, forKey: .accepted)
    )
  }
}

public struct AdaptiveDrawingModel: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: ModelID
  public let parentID: ModelID?
  public let machineToField: AffineTransform2<MachineSpace, FieldSpace>
  public let machineDomain: AxisAlignedBounds<MachineSpace>
  public let fieldRegistrationID: FieldRegistrationID
  public let validation: ModelValidationReport

  public init(
    id: ModelID,
    parentID: ModelID?,
    machineToField: AffineTransform2<MachineSpace, FieldSpace>,
    machineDomain: AxisAlignedBounds<MachineSpace>,
    fieldRegistrationID: FieldRegistrationID,
    validation: ModelValidationReport
  ) throws {
    guard validation.accepted else {
      throw PlotterModelError.invalidValue("active drawing model requires accepted validation")
    }
    self.id = id
    self.parentID = parentID
    self.machineToField = machineToField
    self.machineDomain = machineDomain
    self.fieldRegistrationID = fieldRegistrationID
    self.validation = validation
  }

  public func predictedFieldPoint(for machinePoint: Point2<MachineSpace>) throws -> Point2<
    FieldSpace
  > {
    guard machineDomain.contains(machinePoint) else { throw GeometryError.outsideDomain }
    return try machineToField.applying(to: machinePoint)
  }

  public func predictedFieldPath(for machinePath: Polyline<MachineSpace>) throws -> Polyline<
    FieldSpace
  > {
    guard machinePath.points.allSatisfy({ machineDomain.contains($0) }) else {
      throw GeometryError.outsideDomain
    }
    return try machineToField.applying(to: machinePath)
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("AdaptiveDrawingModel")
    try id.encodeCanonical(to: &encoder)
    encoder.appendBool(parentID != nil)
    if let parentID { try parentID.encodeCanonical(to: &encoder) }
    try machineToField.encodeCanonical(to: &encoder)
    try machineDomain.encodeCanonical(to: &encoder)
    try fieldRegistrationID.encodeCanonical(to: &encoder)
    try validation.encodeCanonical(to: &encoder)
  }

  private enum CodingKeys: String, CodingKey {
    case id, parentID, machineToField, machineDomain, fieldRegistrationID, validation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: container.decode(ModelID.self, forKey: .id),
      parentID: container.decodeIfPresent(ModelID.self, forKey: .parentID),
      machineToField: container.decode(
        AffineTransform2<MachineSpace, FieldSpace>.self,
        forKey: .machineToField
      ),
      machineDomain: container.decode(
        AxisAlignedBounds<MachineSpace>.self,
        forKey: .machineDomain
      ),
      fieldRegistrationID: container.decode(
        FieldRegistrationID.self,
        forKey: .fieldRegistrationID
      ),
      validation: container.decode(ModelValidationReport.self, forKey: .validation)
    )
  }
}

public struct ModelCandidate: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: ModelCandidateID
  public let parentModelID: ModelID
  public let proposedMachineToField: AffineTransform2<MachineSpace, FieldSpace>
  public let machineDomain: AxisAlignedBounds<MachineSpace>
  public let validation: ModelValidationReport

  public init(
    id: ModelCandidateID,
    parentModelID: ModelID,
    proposedMachineToField: AffineTransform2<MachineSpace, FieldSpace>,
    machineDomain: AxisAlignedBounds<MachineSpace>,
    validation: ModelValidationReport
  ) {
    self.id = id
    self.parentModelID = parentModelID
    self.proposedMachineToField = proposedMachineToField
    self.machineDomain = machineDomain
    self.validation = validation
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("ModelCandidate")
    try id.encodeCanonical(to: &encoder)
    try parentModelID.encodeCanonical(to: &encoder)
    try proposedMachineToField.encodeCanonical(to: &encoder)
    try machineDomain.encodeCanonical(to: &encoder)
    try validation.encodeCanonical(to: &encoder)
  }

  private enum CodingKeys: String, CodingKey {
    case id, parentModelID, proposedMachineToField, machineDomain, validation
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try container.decode(ModelCandidateID.self, forKey: .id),
      parentModelID: try container.decode(ModelID.self, forKey: .parentModelID),
      proposedMachineToField: try container.decode(
        AffineTransform2<MachineSpace, FieldSpace>.self,
        forKey: .proposedMachineToField
      ),
      machineDomain: try container.decode(
        AxisAlignedBounds<MachineSpace>.self,
        forKey: .machineDomain
      ),
      validation: try container.decode(ModelValidationReport.self, forKey: .validation)
    )
  }
}

public enum CommandInverter {
  public static func machinePoint(
    for desiredFieldPoint: Point2<FieldSpace>,
    using model: AdaptiveDrawingModel,
    maximumForwardError: Double
  ) throws -> Point2<MachineSpace> {
    guard maximumForwardError.isFinite, maximumForwardError > 0 else {
      throw PlotterModelError.invalidValue("forward error limit must be positive and finite")
    }
    let candidate = try model.machineToField.inverted().applying(to: desiredFieldPoint)
    guard model.machineDomain.contains(candidate) else { throw GeometryError.outsideDomain }
    let projected = try model.predictedFieldPoint(for: candidate)
    let error = projected.distance(to: desiredFieldPoint)
    guard error <= maximumForwardError else {
      throw GeometryError.forwardCheckFailed(error: error, limit: maximumForwardError)
    }
    return candidate
  }

  public static func machinePath(
    for desiredFieldPath: Polyline<FieldSpace>,
    using model: AdaptiveDrawingModel,
    maximumForwardError: Double
  ) throws -> Polyline<MachineSpace> {
    try Polyline(
      points: desiredFieldPath.points.map {
        try machinePoint(for: $0, using: model, maximumForwardError: maximumForwardError)
      })
  }
}
