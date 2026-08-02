import Foundation

public struct PenLiftRequest: Hashable, Codable, Sendable, CanonicalEncodable {
  public let penProfileID: PenProfileID
  public let settleNanoseconds: UInt64

  public init(penProfileID: PenProfileID, settleNanoseconds: UInt64) {
    self.penProfileID = penProfileID
    self.settleNanoseconds = settleNanoseconds
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try penProfileID.encodeCanonical(to: &encoder)
    encoder.appendUInt64(settleNanoseconds)
  }
}

public struct MotionPath: Hashable, Codable, Sendable, CanonicalEncodable {
  public let path: Polyline<MachineSpace>
  public let maximumFeed: Double

  public init(path: Polyline<MachineSpace>, maximumFeed: Double) throws {
    guard maximumFeed.isFinite, maximumFeed > 0 else {
      throw PlotterModelError.invalidValue("motion feed must be positive and finite")
    }
    self.path = path
    self.maximumFeed = maximumFeed
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try path.encodeCanonical(to: &encoder)
    try encoder.appendDouble(maximumFeed)
  }

  private enum CodingKeys: String, CodingKey { case path, maximumFeed }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      path: container.decode(Polyline<MachineSpace>.self, forKey: .path),
      maximumFeed: container.decode(Double.self, forKey: .maximumFeed)
    )
  }
}

public struct DrawPath: Hashable, Codable, Sendable, CanonicalEncodable {
  public let strokeID: StrokeID
  public let sliceID: StrokeSliceID
  public let path: Polyline<MachineSpace>
  public let modelID: ModelID
  public let maximumFeed: Double

  public init(
    strokeID: StrokeID,
    sliceID: StrokeSliceID,
    path: Polyline<MachineSpace>,
    modelID: ModelID,
    maximumFeed: Double
  ) throws {
    guard maximumFeed.isFinite, maximumFeed > 0 else {
      throw PlotterModelError.invalidValue("draw feed must be positive and finite")
    }
    self.strokeID = strokeID
    self.sliceID = sliceID
    self.path = path
    self.modelID = modelID
    self.maximumFeed = maximumFeed
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try strokeID.encodeCanonical(to: &encoder)
    try sliceID.encodeCanonical(to: &encoder)
    try path.encodeCanonical(to: &encoder)
    try modelID.encodeCanonical(to: &encoder)
    try encoder.appendDouble(maximumFeed)
  }

  private enum CodingKeys: String, CodingKey {
    case strokeID, sliceID, path, modelID, maximumFeed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      strokeID: container.decode(StrokeID.self, forKey: .strokeID),
      sliceID: container.decode(StrokeSliceID.self, forKey: .sliceID),
      path: container.decode(Polyline<MachineSpace>.self, forKey: .path),
      modelID: container.decode(ModelID.self, forKey: .modelID),
      maximumFeed: container.decode(Double.self, forKey: .maximumFeed)
    )
  }
}

public struct Deadline: Hashable, Codable, Sendable, CanonicalEncodable {
  public let durationNanoseconds: UInt64

  public init(durationNanoseconds: UInt64) throws {
    guard durationNanoseconds > 0 else {
      throw PlotterModelError.invalidValue("deadline must be nonzero")
    }
    self.durationNanoseconds = durationNanoseconds
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt64(durationNanoseconds)
  }

  private enum CodingKeys: String, CodingKey { case durationNanoseconds }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(durationNanoseconds: container.decode(UInt64.self, forKey: .durationNanoseconds))
  }
}

public struct StableFrameRequirement: Hashable, Codable, Sendable, CanonicalEncodable {
  public let minimumFrameCount: UInt16
  public let newerThanMonotonicNanoseconds: UInt64
  public let maximumSpanNanoseconds: UInt64

  public init(
    minimumFrameCount: UInt16,
    newerThanMonotonicNanoseconds: UInt64,
    maximumSpanNanoseconds: UInt64
  ) throws {
    guard minimumFrameCount >= 2, maximumSpanNanoseconds > 0 else {
      throw PlotterModelError.invalidValue("stable frame requirement is not bounded")
    }
    self.minimumFrameCount = minimumFrameCount
    self.newerThanMonotonicNanoseconds = newerThanMonotonicNanoseconds
    self.maximumSpanNanoseconds = maximumSpanNanoseconds
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt16(minimumFrameCount)
    encoder.appendUInt64(newerThanMonotonicNanoseconds)
    encoder.appendUInt64(maximumSpanNanoseconds)
  }

  private enum CodingKeys: String, CodingKey {
    case minimumFrameCount, newerThanMonotonicNanoseconds, maximumSpanNanoseconds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      minimumFrameCount: container.decode(UInt16.self, forKey: .minimumFrameCount),
      newerThanMonotonicNanoseconds: container.decode(
        UInt64.self,
        forKey: .newerThanMonotonicNanoseconds
      ),
      maximumSpanNanoseconds: container.decode(UInt64.self, forKey: .maximumSpanNanoseconds)
    )
  }
}

public enum InspectionKind: UInt8, Codable, Sendable, CanonicalEncodable {
  case cleanBaseline = 0
  case isolatedInk = 1

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public struct InspectionRequest: Hashable, Codable, Sendable, CanonicalEncodable {
  public let kind: InspectionKind
  public let observationRegionID: ObservationRegionID
  public let baselineEvidenceID: EvidenceID?

  public init(
    kind: InspectionKind,
    observationRegionID: ObservationRegionID,
    baselineEvidenceID: EvidenceID? = nil
  ) throws {
    if kind == .isolatedInk, baselineEvidenceID == nil {
      throw PlotterModelError.invalidValue("ink inspection requires baseline evidence")
    }
    self.kind = kind
    self.observationRegionID = observationRegionID
    self.baselineEvidenceID = baselineEvidenceID
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try kind.encodeCanonical(to: &encoder)
    try observationRegionID.encodeCanonical(to: &encoder)
    encoder.appendBool(baselineEvidenceID != nil)
    if let baselineEvidenceID { try baselineEvidenceID.encodeCanonical(to: &encoder) }
  }

  private enum CodingKeys: String, CodingKey {
    case kind, observationRegionID, baselineEvidenceID
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      kind: container.decode(InspectionKind.self, forKey: .kind),
      observationRegionID: container.decode(
        ObservationRegionID.self,
        forKey: .observationRegionID
      ),
      baselineEvidenceID: container.decodeIfPresent(EvidenceID.self, forKey: .baselineEvidenceID)
    )
  }
}

public enum ExecutionInstruction: Hashable, Codable, Sendable, CanonicalEncodable {
  case liftPen(PenLiftRequest)
  case travel(MotionPath)
  case draw(DrawPath)
  case clearObservationRegion(ClearancePath, ObservationRegion)
  case awaitControllerIdle(Deadline)
  case acquireStableFrame(StableFrameRequirement)
  case inspect(InspectionRequest)
  case checkpoint(CheckpointID)

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case let .liftPen(request):
      encoder.appendUInt8(0)
      try request.encodeCanonical(to: &encoder)
    case let .travel(path):
      encoder.appendUInt8(1)
      try path.encodeCanonical(to: &encoder)
    case let .draw(path):
      encoder.appendUInt8(2)
      try path.encodeCanonical(to: &encoder)
    case let .clearObservationRegion(path, region):
      encoder.appendUInt8(3)
      try path.encodeCanonical(to: &encoder)
      try region.encodeCanonical(to: &encoder)
    case let .awaitControllerIdle(deadline):
      encoder.appendUInt8(4)
      try deadline.encodeCanonical(to: &encoder)
    case let .acquireStableFrame(requirement):
      encoder.appendUInt8(5)
      try requirement.encodeCanonical(to: &encoder)
    case let .inspect(request):
      encoder.appendUInt8(6)
      try request.encodeCanonical(to: &encoder)
    case let .checkpoint(id):
      encoder.appendUInt8(7)
      try id.encodeCanonical(to: &encoder)
    }
  }
}

public enum ExecutionPlanError: Error, Equatable, Sendable {
  case empty
  case checkpointMustBeUniqueAndLast
  case drawModelMismatch
  case motionRequiresPenUp
  case baselineRequiredBeforeDraw
  case drawMustBeFollowedByLiftClearFrameAndInspection
  case inspectionRequiresFreshFrame
  case multipleDrawsNotSupportedInInitialKernel
}

public struct ExecutionPlan: Hashable, Sendable, Codable, CanonicalEncodable {
  public static let schemaVersion: UInt16 = 1

  public let id: PlanID
  public let revision: UInt32
  public let parent: PlanID?
  public let programID: ProgramID
  public let programHash: Digest
  public let modelID: ModelID
  public let stateEstimateID: StateEstimateID
  public let fieldRegistrationID: FieldRegistrationID
  public let safetyPolicyID: SafetyPolicyID
  public let machineConfigurationID: MachineConfigurationID
  public let compilerVersion: UInt32
  public let instructions: [ExecutionInstruction]
  public let contentHash: Digest

  public init(
    id: PlanID,
    revision: UInt32,
    parent: PlanID?,
    programID: ProgramID,
    programHash: Digest,
    modelID: ModelID,
    stateEstimateID: StateEstimateID,
    fieldRegistrationID: FieldRegistrationID,
    safetyPolicyID: SafetyPolicyID,
    machineConfigurationID: MachineConfigurationID,
    compilerVersion: UInt32,
    instructions: [ExecutionInstruction]
  ) throws {
    try Self.validate(instructions: instructions, modelID: modelID)
    self.id = id
    self.revision = revision
    self.parent = parent
    self.programID = programID
    self.programHash = programHash
    self.modelID = modelID
    self.stateEstimateID = stateEstimateID
    self.fieldRegistrationID = fieldRegistrationID
    self.safetyPolicyID = safetyPolicyID
    self.machineConfigurationID = machineConfigurationID
    self.compilerVersion = compilerVersion
    self.instructions = instructions
    contentHash = try canonicalDigest(
      of: ExecutionPlanHashBasis(
        id: id,
        revision: revision,
        parent: parent,
        programID: programID,
        programHash: programHash,
        modelID: modelID,
        stateEstimateID: stateEstimateID,
        fieldRegistrationID: fieldRegistrationID,
        safetyPolicyID: safetyPolicyID,
        machineConfigurationID: machineConfigurationID,
        compilerVersion: compilerVersion,
        instructions: instructions
      ))
  }

  private static func validate(instructions: [ExecutionInstruction], modelID: ModelID) throws {
    guard !instructions.isEmpty else { throw ExecutionPlanError.empty }
    let checkpoints = instructions.enumerated().compactMap { index, instruction -> Int? in
      if case .checkpoint = instruction { return index }
      return nil
    }
    guard checkpoints == [instructions.count - 1] else {
      throw ExecutionPlanError.checkpointMustBeUniqueAndLast
    }

    var penIsUp = false
    var baselineInspected = false
    var frameAcquired = false
    var drawCount = 0
    var drew = false
    var liftedAfterDraw = false
    var clearedAfterDraw = false
    var inspectedAfterDraw = false

    for instruction in instructions {
      switch instruction {
      case .liftPen:
        penIsUp = true
        if drew { liftedAfterDraw = true }
      case .travel:
        guard penIsUp else { throw ExecutionPlanError.motionRequiresPenUp }
        frameAcquired = false
      case let .draw(path):
        guard path.modelID == modelID else { throw ExecutionPlanError.drawModelMismatch }
        guard penIsUp else { throw ExecutionPlanError.motionRequiresPenUp }
        guard baselineInspected else { throw ExecutionPlanError.baselineRequiredBeforeDraw }
        drawCount += 1
        guard drawCount == 1 else {
          throw ExecutionPlanError.multipleDrawsNotSupportedInInitialKernel
        }
        drew = true
        penIsUp = false
        frameAcquired = false
      case .clearObservationRegion:
        guard penIsUp else { throw ExecutionPlanError.motionRequiresPenUp }
        if drew { clearedAfterDraw = true }
        frameAcquired = false
      case .awaitControllerIdle:
        break
      case .acquireStableFrame:
        frameAcquired = true
      case let .inspect(request):
        guard frameAcquired else { throw ExecutionPlanError.inspectionRequiresFreshFrame }
        if request.kind == .cleanBaseline { baselineInspected = true }
        if request.kind == .isolatedInk {
          guard drew, liftedAfterDraw, clearedAfterDraw else {
            throw ExecutionPlanError.drawMustBeFollowedByLiftClearFrameAndInspection
          }
          inspectedAfterDraw = true
        }
        frameAcquired = false
      case .checkpoint:
        break
      }
    }
    if drew, !(liftedAfterDraw && clearedAfterDraw && inspectedAfterDraw) {
      throw ExecutionPlanError.drawMustBeFollowedByLiftClearFrameAndInspection
    }
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try ExecutionPlanHashBasis(
      id: id,
      revision: revision,
      parent: parent,
      programID: programID,
      programHash: programHash,
      modelID: modelID,
      stateEstimateID: stateEstimateID,
      fieldRegistrationID: fieldRegistrationID,
      safetyPolicyID: safetyPolicyID,
      machineConfigurationID: machineConfigurationID,
      compilerVersion: compilerVersion,
      instructions: instructions
    ).encodeCanonical(to: &encoder)
    encoder.appendDigest(contentHash)
  }

  private enum CodingKeys: String, CodingKey {
    case id, revision, parent, programID, programHash, modelID, stateEstimateID
    case fieldRegistrationID, safetyPolicyID, machineConfigurationID
    case compilerVersion, instructions, contentHash
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let encodedHash = try container.decode(Digest.self, forKey: .contentHash)
    let decoded = try Self(
      id: container.decode(PlanID.self, forKey: .id),
      revision: container.decode(UInt32.self, forKey: .revision),
      parent: container.decodeIfPresent(PlanID.self, forKey: .parent),
      programID: container.decode(ProgramID.self, forKey: .programID),
      programHash: container.decode(Digest.self, forKey: .programHash),
      modelID: container.decode(ModelID.self, forKey: .modelID),
      stateEstimateID: container.decode(StateEstimateID.self, forKey: .stateEstimateID),
      fieldRegistrationID: container.decode(
        FieldRegistrationID.self,
        forKey: .fieldRegistrationID
      ),
      safetyPolicyID: container.decode(SafetyPolicyID.self, forKey: .safetyPolicyID),
      machineConfigurationID: container.decode(
        MachineConfigurationID.self,
        forKey: .machineConfigurationID
      ),
      compilerVersion: container.decode(UInt32.self, forKey: .compilerVersion),
      instructions: container.decode([ExecutionInstruction].self, forKey: .instructions)
    )
    guard decoded.contentHash == encodedHash else { throw PlotterModelError.contentHashMismatch }
    self = decoded
  }
}

private struct ExecutionPlanHashBasis: CanonicalEncodable {
  let id: PlanID
  let revision: UInt32
  let parent: PlanID?
  let programID: ProgramID
  let programHash: Digest
  let modelID: ModelID
  let stateEstimateID: StateEstimateID
  let fieldRegistrationID: FieldRegistrationID
  let safetyPolicyID: SafetyPolicyID
  let machineConfigurationID: MachineConfigurationID
  let compilerVersion: UInt32
  let instructions: [ExecutionInstruction]

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("ExecutionPlan")
    try id.encodeCanonical(to: &encoder)
    encoder.appendUInt32(revision)
    encoder.appendBool(parent != nil)
    if let parent { try parent.encodeCanonical(to: &encoder) }
    try programID.encodeCanonical(to: &encoder)
    encoder.appendDigest(programHash)
    try modelID.encodeCanonical(to: &encoder)
    try stateEstimateID.encodeCanonical(to: &encoder)
    try fieldRegistrationID.encodeCanonical(to: &encoder)
    try safetyPolicyID.encodeCanonical(to: &encoder)
    try machineConfigurationID.encodeCanonical(to: &encoder)
    encoder.appendUInt32(compilerVersion)
    try encoder.appendCount(instructions.count)
    for instruction in instructions { try instruction.encodeCanonical(to: &encoder) }
  }
}

public struct PlanCursor: Hashable, Codable, Sendable, CanonicalEncodable {
  public let planID: PlanID
  public let instructionIndex: UInt32
  public let commandIndex: UInt32

  public init(planID: PlanID, instructionIndex: UInt32, commandIndex: UInt32 = 0) {
    self.planID = planID
    self.instructionIndex = instructionIndex
    self.commandIndex = commandIndex
  }

  public func compare(to other: Self) throws -> ComparisonResult {
    guard planID == other.planID else {
      throw PlotterModelError.invalidValue("cannot compare cursors from different plans")
    }
    if instructionIndex != other.instructionIndex {
      return instructionIndex < other.instructionIndex ? .orderedAscending : .orderedDescending
    }
    if commandIndex != other.commandIndex {
      return commandIndex < other.commandIndex ? .orderedAscending : .orderedDescending
    }
    return .orderedSame
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try planID.encodeCanonical(to: &encoder)
    encoder.appendUInt32(instructionIndex)
    encoder.appendUInt32(commandIndex)
  }
}

public enum InkDisposition: Hashable, Codable, Sendable, CanonicalEncodable {
  case awaitingInspection
  case verified(ObservationID)
  case failed(EvidenceID, reasons: [String])
  case ambiguous(reasons: [String])
  case operatorSkipped(reason: String)

  public var prohibitsAutomaticRedraw: Bool { true }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case .awaitingInspection:
      encoder.appendUInt8(0)
    case let .verified(id):
      encoder.appendUInt8(1)
      try id.encodeCanonical(to: &encoder)
    case let .failed(id, reasons):
      encoder.appendUInt8(2)
      try id.encodeCanonical(to: &encoder)
      try encodeStrings(reasons, to: &encoder)
    case let .ambiguous(reasons):
      encoder.appendUInt8(3)
      try encodeStrings(reasons, to: &encoder)
    case let .operatorSkipped(reason):
      encoder.appendUInt8(4)
      try encoder.appendString(reason)
    }
  }
}

private func encodeStrings(_ values: [String], to encoder: inout CanonicalEncoder) throws {
  try encoder.appendCount(values.count)
  for value in values { try encoder.appendString(value) }
}

public struct SliceExecutionFact: Hashable, Codable, Sendable, CanonicalEncodable {
  public let drawCursor: PlanCursor
  public let disposition: InkDisposition

  public init(drawCursor: PlanCursor, disposition: InkDisposition) {
    self.drawCursor = drawCursor
    self.disposition = disposition
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try drawCursor.encodeCanonical(to: &encoder)
    try disposition.encodeCanonical(to: &encoder)
  }
}

public struct ExecutionFrontiers: Hashable, Codable, Sendable, CanonicalEncodable {
  public let planID: PlanID
  public let commandedThrough: PlanCursor?
  public let controllerCompletedThrough: PlanCursor?
  public let inkBySlice: [StrokeSliceID: SliceExecutionFact]

  public init(
    planID: PlanID,
    commandedThrough: PlanCursor?,
    controllerCompletedThrough: PlanCursor?,
    inkBySlice: [StrokeSliceID: SliceExecutionFact]
  ) throws {
    guard commandedThrough?.planID == planID || commandedThrough == nil,
      controllerCompletedThrough?.planID == planID || controllerCompletedThrough == nil,
      inkBySlice.values.allSatisfy({ $0.drawCursor.planID == planID })
    else { throw PlotterModelError.invalidValue("frontiers must reference one plan") }
    if let completed = controllerCompletedThrough {
      guard let commanded = commandedThrough,
        try completed.compare(to: commanded) != .orderedDescending
      else {
        throw PlotterModelError.invalidValue("controller completion exceeds commanded frontier")
      }
    }
    for fact in inkBySlice.values {
      switch fact.disposition {
      case .operatorSkipped:
        break
      case .ambiguous:
        guard let commandedThrough,
          try fact.drawCursor.compare(to: commandedThrough) != .orderedDescending
        else {
          throw PlotterModelError.invalidValue("ambiguous slice exceeds commanded frontier")
        }
      case .awaitingInspection, .verified, .failed:
        guard let controllerCompletedThrough,
          try fact.drawCursor.compare(to: controllerCompletedThrough) != .orderedDescending
        else {
          throw PlotterModelError.invalidValue("ink fact exceeds controller-completed frontier")
        }
      }
    }
    self.planID = planID
    self.commandedThrough = commandedThrough
    self.controllerCompletedThrough = controllerCompletedThrough
    self.inkBySlice = inkBySlice
  }

  public func mayPlanAutomatically(sliceID: StrokeSliceID, at cursor: PlanCursor) -> Bool {
    guard cursor.planID == planID, inkBySlice[sliceID] == nil else { return false }
    guard let commandedThrough else { return true }
    return (try? cursor.compare(to: commandedThrough)) == .orderedDescending
  }

  public func isNonRegressing(from prior: Self) throws -> Bool {
    guard planID == prior.planID,
      try Self.cursor(commandedThrough, isNotBefore: prior.commandedThrough),
      try Self.cursor(controllerCompletedThrough, isNotBefore: prior.controllerCompletedThrough)
    else { return false }

    for (sliceID, priorFact) in prior.inkBySlice {
      guard let resultingFact = inkBySlice[sliceID],
        resultingFact.drawCursor == priorFact.drawCursor,
        Self.disposition(resultingFact.disposition, doesNotRegress: priorFact.disposition)
      else { return false }
    }
    return true
  }

  private static func cursor(_ resulting: PlanCursor?, isNotBefore prior: PlanCursor?) throws
    -> Bool
  {
    guard let prior else { return true }
    guard let resulting else { return false }
    return try resulting.compare(to: prior) != .orderedAscending
  }

  private static func disposition(
    _ resulting: InkDisposition,
    doesNotRegress prior: InkDisposition
  ) -> Bool {
    switch prior {
    case .awaitingInspection:
      return true
    case .ambiguous:
      if case .awaitingInspection = resulting { return false }
      return true
    case .verified, .failed, .operatorSkipped:
      return resulting == prior
    }
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try planID.encodeCanonical(to: &encoder)
    encoder.appendBool(commandedThrough != nil)
    if let commandedThrough { try commandedThrough.encodeCanonical(to: &encoder) }
    encoder.appendBool(controllerCompletedThrough != nil)
    if let controllerCompletedThrough {
      try controllerCompletedThrough.encodeCanonical(to: &encoder)
    }
    let entries = inkBySlice.sorted { $0.key < $1.key }
    try encoder.appendCount(entries.count)
    for (sliceID, fact) in entries {
      try sliceID.encodeCanonical(to: &encoder)
      try fact.encodeCanonical(to: &encoder)
    }
  }

  private enum CodingKeys: String, CodingKey {
    case planID, commandedThrough, controllerCompletedThrough, inkBySlice
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      planID: container.decode(PlanID.self, forKey: .planID),
      commandedThrough: container.decodeIfPresent(
        PlanCursor.self,
        forKey: .commandedThrough
      ),
      controllerCompletedThrough: container.decodeIfPresent(
        PlanCursor.self,
        forKey: .controllerCompletedThrough
      ),
      inkBySlice: container.decode(
        [StrokeSliceID: SliceExecutionFact].self,
        forKey: .inkBySlice
      )
    )
  }
}

public enum AuthorizedOperation: UInt8, Codable, Sendable, CanonicalEncodable {
  case passiveInterrogation = 0
  case boundedPenUpTrial = 1
  case isolatedTrainingProbe = 2
  case generalDrawing = 3

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendUInt8(rawValue)
  }
}

public struct AuthorityLimits: Hashable, Codable, Sendable, CanonicalEncodable {
  public let maximumFeed: Double
  public let maximumDistance: Double
  public let maximumCommandHorizonNanoseconds: UInt64

  public init(
    maximumFeed: Double,
    maximumDistance: Double,
    maximumCommandHorizonNanoseconds: UInt64
  ) throws {
    guard maximumFeed.isFinite, maximumFeed >= 0,
      maximumDistance.isFinite, maximumDistance >= 0
    else { throw PlotterModelError.invalidValue("authority limits must be finite and nonnegative") }
    self.maximumFeed = maximumFeed
    self.maximumDistance = maximumDistance
    self.maximumCommandHorizonNanoseconds = maximumCommandHorizonNanoseconds
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendDouble(maximumFeed)
    try encoder.appendDouble(maximumDistance)
    encoder.appendUInt64(maximumCommandHorizonNanoseconds)
  }

  public var permitsMachineEffects: Bool {
    maximumFeed > 0 && maximumDistance > 0 && maximumCommandHorizonNanoseconds > 0
  }

  private enum CodingKeys: String, CodingKey {
    case maximumFeed, maximumDistance, maximumCommandHorizonNanoseconds
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      maximumFeed: container.decode(Double.self, forKey: .maximumFeed),
      maximumDistance: container.decode(Double.self, forKey: .maximumDistance),
      maximumCommandHorizonNanoseconds: container.decode(
        UInt64.self,
        forKey: .maximumCommandHorizonNanoseconds
      )
    )
  }
}

public struct RunBlocker: Hashable, Codable, Sendable, CanonicalEncodable {
  public let code: String
  public let summary: String

  public init(code: String, summary: String) throws {
    let code = code.precomposedStringWithCanonicalMapping
    let summary = summary.precomposedStringWithCanonicalMapping
    guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw PlotterModelError.invalidValue("blocker code and summary cannot be empty")
    }
    self.code = code
    self.summary = summary
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString(code)
    try encoder.appendString(summary)
  }

  private enum CodingKeys: String, CodingKey { case code, summary }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      code: container.decode(String.self, forKey: .code),
      summary: container.decode(String.self, forKey: .summary)
    )
  }
}

public struct ExecutionAuthority: Hashable, Codable, Sendable, CanonicalEncodable {
  public let allowed: Bool
  public let operation: AuthorizedOperation?
  public let planID: PlanID?
  public let modelID: ModelID?
  public let stateEstimateID: StateEstimateID?
  public let fixedSafetyPolicyID: SafetyPolicyID
  public let evidence: [EvidenceID]
  public let limits: AuthorityLimits
  public let blockers: [RunBlocker]

  public init(
    allowed: Bool,
    operation: AuthorizedOperation?,
    planID: PlanID?,
    modelID: ModelID?,
    stateEstimateID: StateEstimateID?,
    fixedSafetyPolicyID: SafetyPolicyID,
    evidence: [EvidenceID],
    limits: AuthorityLimits,
    blockers: [RunBlocker]
  ) throws {
    guard Set(evidence).count == evidence.count else {
      throw PlotterModelError.invalidValue("authority evidence IDs must be unique")
    }
    if allowed {
      guard let operation, blockers.isEmpty else {
        throw PlotterModelError.invalidValue(
          "authority allowed state conflicts with blockers/operation")
      }
      switch operation {
      case .passiveInterrogation:
        break
      case .boundedPenUpTrial, .isolatedTrainingProbe, .generalDrawing:
        guard planID != nil, modelID != nil, stateEstimateID != nil,
          !evidence.isEmpty, limits.permitsMachineEffects
        else {
          throw PlotterModelError.invalidValue(
            "machine authority requires plan/model/state evidence and positive limits"
          )
        }
      }
    } else {
      guard operation == nil, !blockers.isEmpty else {
        throw PlotterModelError.invalidValue(
          "blocked authority requires exact blockers and no allowed operation"
        )
      }
    }
    self.allowed = allowed
    self.operation = operation
    self.planID = planID
    self.modelID = modelID
    self.stateEstimateID = stateEstimateID
    self.fixedSafetyPolicyID = fixedSafetyPolicyID
    self.evidence = evidence.sorted()
    self.limits = limits
    self.blockers = blockers.sorted { $0.code < $1.code }
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    encoder.appendBool(allowed)
    encoder.appendBool(operation != nil)
    if let operation { try operation.encodeCanonical(to: &encoder) }
    for optionalID in [
      planID.map(AnyStrongID.plan), modelID.map(AnyStrongID.model),
      stateEstimateID.map(AnyStrongID.state),
    ] {
      encoder.appendBool(optionalID != nil)
      if let optionalID { try optionalID.encodeCanonical(to: &encoder) }
    }
    try fixedSafetyPolicyID.encodeCanonical(to: &encoder)
    try encoder.appendCount(evidence.count)
    for id in evidence { try id.encodeCanonical(to: &encoder) }
    try limits.encodeCanonical(to: &encoder)
    try encoder.appendCount(blockers.count)
    for blocker in blockers { try blocker.encodeCanonical(to: &encoder) }
  }

  private enum CodingKeys: String, CodingKey {
    case allowed, operation, planID, modelID, stateEstimateID, fixedSafetyPolicyID
    case evidence, limits, blockers
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      allowed: container.decode(Bool.self, forKey: .allowed),
      operation: container.decodeIfPresent(AuthorizedOperation.self, forKey: .operation),
      planID: container.decodeIfPresent(PlanID.self, forKey: .planID),
      modelID: container.decodeIfPresent(ModelID.self, forKey: .modelID),
      stateEstimateID: container.decodeIfPresent(
        StateEstimateID.self,
        forKey: .stateEstimateID
      ),
      fixedSafetyPolicyID: container.decode(
        SafetyPolicyID.self,
        forKey: .fixedSafetyPolicyID
      ),
      evidence: container.decode([EvidenceID].self, forKey: .evidence),
      limits: container.decode(AuthorityLimits.self, forKey: .limits),
      blockers: container.decode([RunBlocker].self, forKey: .blockers)
    )
  }
}

private enum AnyStrongID: CanonicalEncodable {
  case plan(PlanID)
  case model(ModelID)
  case state(StateEstimateID)

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case let .plan(id): try id.encodeCanonical(to: &encoder)
    case let .model(id): try id.encodeCanonical(to: &encoder)
    case let .state(id): try id.encodeCanonical(to: &encoder)
    }
  }
}

public enum EvidenceDisposition: Hashable, Codable, Sendable, CanonicalEncodable {
  case accepted(EvidenceID)
  case rejected(EvidenceID?, reasons: [String])

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case let .accepted(id):
      encoder.appendUInt8(0)
      try id.encodeCanonical(to: &encoder)
    case let .rejected(id, reasons):
      encoder.appendUInt8(1)
      encoder.appendBool(id != nil)
      if let id { try id.encodeCanonical(to: &encoder) }
      try encodeStrings(reasons, to: &encoder)
    }
  }
}

public enum StateSelection: Hashable, Codable, Sendable, CanonicalEncodable {
  case retain(StateEstimateID)
  case accept(EvidenceID, StateEstimateID)

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case let .retain(id):
      encoder.appendUInt8(0)
      try id.encodeCanonical(to: &encoder)
    case let .accept(evidence, id):
      encoder.appendUInt8(1)
      try evidence.encodeCanonical(to: &encoder)
      try id.encodeCanonical(to: &encoder)
    }
  }

  public var selectedStateEstimateID: StateEstimateID {
    switch self {
    case let .retain(id), let .accept(_, id): id
    }
  }
}

public enum ModelSelection: Hashable, Codable, Sendable, CanonicalEncodable {
  case retain(ModelID, reasons: [String])
  case accept(EvidenceID, ModelCandidateID, ModelID)

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case let .retain(id, reasons):
      encoder.appendUInt8(0)
      try id.encodeCanonical(to: &encoder)
      try encodeStrings(reasons, to: &encoder)
    case let .accept(evidence, candidate, id):
      encoder.appendUInt8(1)
      try evidence.encodeCanonical(to: &encoder)
      try candidate.encodeCanonical(to: &encoder)
      try id.encodeCanonical(to: &encoder)
    }
  }

  public var selectedModelID: ModelID {
    switch self {
    case let .retain(id, _), let .accept(_, _, id): id
    }
  }
}

public enum NextRunAction: Hashable, Codable, Sendable, CanonicalEncodable {
  case planSuccessor
  case reacquire(boundedAttempt: UInt16, reasons: [String])
  case pause(blockers: [RunBlocker])
  case complete

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    switch self {
    case .planSuccessor:
      encoder.appendUInt8(0)
    case let .reacquire(attempt, reasons):
      encoder.appendUInt8(1)
      encoder.appendUInt16(attempt)
      try encodeStrings(reasons, to: &encoder)
    case let .pause(blockers):
      encoder.appendUInt8(2)
      let blockers = blockers.sorted { $0.code < $1.code }
      try encoder.appendCount(blockers.count)
      for blocker in blockers { try blocker.encodeCanonical(to: &encoder) }
    case .complete:
      encoder.appendUInt8(3)
    }
  }
}

public struct CheckpointDecision: Hashable, Codable, Sendable, CanonicalEncodable {
  public let evidenceDisposition: EvidenceDisposition
  public let stateSelection: StateSelection
  public let modelSelection: ModelSelection
  public let nextAction: NextRunAction

  public init(
    evidenceDisposition: EvidenceDisposition,
    stateSelection: StateSelection,
    modelSelection: ModelSelection,
    nextAction: NextRunAction
  ) {
    self.evidenceDisposition = evidenceDisposition
    self.stateSelection = stateSelection
    self.modelSelection = modelSelection
    self.nextAction = nextAction
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try evidenceDisposition.encodeCanonical(to: &encoder)
    try stateSelection.encodeCanonical(to: &encoder)
    try modelSelection.encodeCanonical(to: &encoder)
    try nextAction.encodeCanonical(to: &encoder)
  }
}

public struct PlanningBasis: Hashable, Codable, Sendable, CanonicalEncodable {
  public let programID: ProgramID
  public let currentPlanID: PlanID
  public let modelID: ModelID
  public let stateEstimateID: StateEstimateID
  public let safetyPolicyID: SafetyPolicyID
  public let unresolvedSlices: [StrokeSliceID]

  public init(
    programID: ProgramID,
    currentPlanID: PlanID,
    modelID: ModelID,
    stateEstimateID: StateEstimateID,
    safetyPolicyID: SafetyPolicyID,
    unresolvedSlices: [StrokeSliceID]
  ) throws {
    guard Set(unresolvedSlices).count == unresolvedSlices.count else {
      throw PlotterModelError.invalidValue("planning basis contains duplicate slices")
    }
    self.programID = programID
    self.currentPlanID = currentPlanID
    self.modelID = modelID
    self.stateEstimateID = stateEstimateID
    self.safetyPolicyID = safetyPolicyID
    self.unresolvedSlices = unresolvedSlices.sorted()
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try programID.encodeCanonical(to: &encoder)
    try currentPlanID.encodeCanonical(to: &encoder)
    try modelID.encodeCanonical(to: &encoder)
    try stateEstimateID.encodeCanonical(to: &encoder)
    try safetyPolicyID.encodeCanonical(to: &encoder)
    try encoder.appendCount(unresolvedSlices.count)
    for slice in unresolvedSlices { try slice.encodeCanonical(to: &encoder) }
  }

  private enum CodingKeys: String, CodingKey {
    case programID, currentPlanID, modelID, stateEstimateID, safetyPolicyID, unresolvedSlices
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      programID: container.decode(ProgramID.self, forKey: .programID),
      currentPlanID: container.decode(PlanID.self, forKey: .currentPlanID),
      modelID: container.decode(ModelID.self, forKey: .modelID),
      stateEstimateID: container.decode(StateEstimateID.self, forKey: .stateEstimateID),
      safetyPolicyID: container.decode(SafetyPolicyID.self, forKey: .safetyPolicyID),
      unresolvedSlices: container.decode([StrokeSliceID].self, forKey: .unresolvedSlices)
    )
  }
}

public struct CheckpointResolution: Hashable, Codable, Sendable, CanonicalEncodable {
  public let id: CheckpointResolutionID
  public let checkpointID: CheckpointID
  public let decision: CheckpointDecision
  public let priorFrontiers: ExecutionFrontiers
  public let resultingFrontiers: ExecutionFrontiers
  public let nextPlanningBasis: PlanningBasis
  public let contentHash: Digest

  public init(
    id: CheckpointResolutionID,
    checkpointID: CheckpointID,
    decision: CheckpointDecision,
    priorFrontiers: ExecutionFrontiers,
    resultingFrontiers: ExecutionFrontiers,
    nextPlanningBasis: PlanningBasis
  ) throws {
    guard priorFrontiers.planID == resultingFrontiers.planID,
      resultingFrontiers.planID == nextPlanningBasis.currentPlanID
    else { throw PlotterModelError.invalidValue("checkpoint resolution plan identity mismatch") }
    guard decision.modelSelection.selectedModelID == nextPlanningBasis.modelID,
      decision.stateSelection.selectedStateEstimateID == nextPlanningBasis.stateEstimateID
    else {
      throw PlotterModelError.invalidValue(
        "checkpoint selections disagree with the next planning basis"
      )
    }
    guard try resultingFrontiers.isNonRegressing(from: priorFrontiers) else {
      throw PlotterModelError.invalidValue("checkpoint frontiers regress")
    }
    self.id = id
    self.checkpointID = checkpointID
    self.decision = decision
    self.priorFrontiers = priorFrontiers
    self.resultingFrontiers = resultingFrontiers
    self.nextPlanningBasis = nextPlanningBasis
    contentHash = try canonicalDigest(
      of: CheckpointResolutionHashBasis(
        id: id,
        checkpointID: checkpointID,
        decision: decision,
        priorFrontiers: priorFrontiers,
        resultingFrontiers: resultingFrontiers,
        nextPlanningBasis: nextPlanningBasis
      ))
  }

  public func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try CheckpointResolutionHashBasis(
      id: id,
      checkpointID: checkpointID,
      decision: decision,
      priorFrontiers: priorFrontiers,
      resultingFrontiers: resultingFrontiers,
      nextPlanningBasis: nextPlanningBasis
    ).encodeCanonical(to: &encoder)
    encoder.appendDigest(contentHash)
  }

  private enum CodingKeys: String, CodingKey {
    case id, checkpointID, decision, priorFrontiers, resultingFrontiers
    case nextPlanningBasis, contentHash
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let encodedHash = try container.decode(Digest.self, forKey: .contentHash)
    let decoded = try Self(
      id: container.decode(CheckpointResolutionID.self, forKey: .id),
      checkpointID: container.decode(CheckpointID.self, forKey: .checkpointID),
      decision: container.decode(CheckpointDecision.self, forKey: .decision),
      priorFrontiers: container.decode(ExecutionFrontiers.self, forKey: .priorFrontiers),
      resultingFrontiers: container.decode(
        ExecutionFrontiers.self,
        forKey: .resultingFrontiers
      ),
      nextPlanningBasis: container.decode(PlanningBasis.self, forKey: .nextPlanningBasis)
    )
    guard decoded.contentHash == encodedHash else { throw PlotterModelError.contentHashMismatch }
    self = decoded
  }
}

private struct CheckpointResolutionHashBasis: CanonicalEncodable {
  let id: CheckpointResolutionID
  let checkpointID: CheckpointID
  let decision: CheckpointDecision
  let priorFrontiers: ExecutionFrontiers
  let resultingFrontiers: ExecutionFrontiers
  let nextPlanningBasis: PlanningBasis

  func encodeCanonical(to encoder: inout CanonicalEncoder) throws {
    try encoder.appendString("CheckpointResolution")
    try id.encodeCanonical(to: &encoder)
    try checkpointID.encodeCanonical(to: &encoder)
    try decision.encodeCanonical(to: &encoder)
    try priorFrontiers.encodeCanonical(to: &encoder)
    try resultingFrontiers.encodeCanonical(to: &encoder)
    try nextPlanningBasis.encodeCanonical(to: &encoder)
  }
}
