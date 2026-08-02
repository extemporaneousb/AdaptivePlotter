import Foundation

@testable import PlotterModel

func uuid(_ value: String) -> UUID { UUID(uuidString: value)! }

enum IDs {
  static let program = ProgramID(uuid("00000000-0000-0000-0000-000000000001"))
  static let stroke = StrokeID(uuid("00000000-0000-0000-0000-000000000002"))
  static let slice = StrokeSliceID(uuid("00000000-0000-0000-0000-000000000003"))
  static let otherSlice = StrokeSliceID(uuid("00000000-0000-0000-0000-000000000004"))
  static let plan = PlanID(uuid("00000000-0000-0000-0000-000000000005"))
  static let run = RunID(uuid("00000000-0000-0000-0000-000000000006"))
  static let model = ModelID(uuid("00000000-0000-0000-0000-000000000007"))
  static let candidate = ModelCandidateID(uuid("00000000-0000-0000-0000-000000000008"))
  static let state = StateEstimateID(uuid("00000000-0000-0000-0000-000000000009"))
  static let registration = FieldRegistrationID(uuid("00000000-0000-0000-0000-00000000000a"))
  static let safety = SafetyPolicyID(uuid("00000000-0000-0000-0000-00000000000b"))
  static let machine = MachineConfigurationID(uuid("00000000-0000-0000-0000-00000000000c"))
  static let camera = CameraConfigurationID(uuid("00000000-0000-0000-0000-00000000000d"))
  static let tool = ToolConfigurationID(uuid("00000000-0000-0000-0000-00000000000e"))
  static let pen = PenProfileID(uuid("00000000-0000-0000-0000-00000000000f"))
  static let evidence = EvidenceID(uuid("00000000-0000-0000-0000-000000000010"))
  static let observation = ObservationID(uuid("00000000-0000-0000-0000-000000000011"))
  static let region = ObservationRegionID(uuid("00000000-0000-0000-0000-000000000012"))
  static let checkpoint = CheckpointID(uuid("00000000-0000-0000-0000-000000000013"))
  static let resolution = CheckpointResolutionID(uuid("00000000-0000-0000-0000-000000000014"))
  static let envelope = ClearanceEnvelopeID(uuid("00000000-0000-0000-0000-000000000015"))
  static let pose = ClearancePoseID(uuid("00000000-0000-0000-0000-000000000016"))
  static let clearancePath = ClearancePathID(uuid("00000000-0000-0000-0000-000000000017"))
  static let successorPlan = PlanID(uuid("00000000-0000-0000-0000-000000000018"))
  static let successorModel = ModelID(uuid("00000000-0000-0000-0000-000000000019"))
  static let successorState = StateEstimateID(uuid("00000000-0000-0000-0000-00000000001a"))
  static let otherProgram = ProgramID(uuid("00000000-0000-0000-0000-00000000001b"))
  static let otherSafety = SafetyPolicyID(uuid("00000000-0000-0000-0000-00000000001c"))
}

func fieldPoint(_ x: Double, _ y: Double) throws -> Point2<FieldSpace> {
  try Point2(x: x, y: y)
}

func machinePoint(_ x: Double, _ y: Double) throws -> Point2<MachineSpace> {
  try Point2(x: x, y: y)
}

func cameraPoint(_ x: Double, _ y: Double) throws -> Point2<CameraPixelSpace> {
  try Point2(x: x, y: y)
}

func identityRegistration() throws -> FieldRegistration {
  let training = [
    RegistrationCorrespondence(camera: try cameraPoint(0, 0), field: try fieldPoint(0, 0)),
    RegistrationCorrespondence(camera: try cameraPoint(10, 0), field: try fieldPoint(10, 0)),
    RegistrationCorrespondence(camera: try cameraPoint(0, 10), field: try fieldPoint(0, 10)),
  ]
  let holdouts = [
    RegistrationCorrespondence(camera: try cameraPoint(2, 3), field: try fieldPoint(2, 3)),
    RegistrationCorrespondence(camera: try cameraPoint(8, 7), field: try fieldPoint(8, 7)),
  ]
  return try FieldRegistration.fit(
    id: IDs.registration,
    training: training,
    independentHoldouts: holdouts,
    maximumHoldoutError: 0.1
  )
}

func affineModel(id: ModelID = IDs.model) throws -> AdaptiveDrawingModel {
  try AdaptiveDrawingModel(
    id: id,
    parentID: nil,
    machineToField: AffineTransform2(
      m11: 2, m12: 0.25, m21: -0.5, m22: 1.5, tx: 10, ty: 20
    ),
    machineDomain: AxisAlignedBounds(minX: 0, minY: 0, maxX: 100, maxY: 100),
    fieldRegistrationID: IDs.registration,
    validation: ModelValidationReport(
      independentTrialCount: 5,
      holdoutRootMeanSquareError: 0.1,
      holdoutMaximumError: 0.2,
      accepted: true
    )
  )
}

func observationRegion() throws -> ObservationRegion {
  ObservationRegion(
    id: IDs.region,
    fieldBounds: try AxisAlignedBounds(minX: 0, minY: 0, maxX: 10, maxY: 10)
  )
}

func clearancePose(
  polygon: [Point2<CameraPixelSpace>],
  uncertainty: Double = 0,
  margin: Double = 0
) throws -> ClearancePose {
  let envelope = try ToolOcclusionEnvelope(
    id: IDs.envelope,
    cameraConfigurationID: IDs.camera,
    toolConfigurationID: IDs.tool,
    penServoState: .operatorObservedUp,
    polygon: Polygon2(vertices: polygon),
    poseUncertaintyPixels: uncertainty,
    fixedMarginPixels: margin
  )
  return ClearancePose(
    id: IDs.pose,
    machinePosition: try machinePoint(20, 20),
    envelope: envelope
  )
}

func clearancePath(to pose: ClearancePose) throws -> ClearancePath {
  try ClearancePath(
    id: IDs.clearancePath,
    path: Polyline(points: [try machinePoint(10, 10), pose.machinePosition]),
    destination: pose,
    maximumFeed: 100,
    maximumDistance: 20
  )
}

func drawingProgram() throws -> DrawingProgram {
  let stroke = LogicalStroke(
    id: IDs.stroke,
    path: try Polyline(points: [try fieldPoint(1, 1), try fieldPoint(4, 4)]),
    style: try StrokeStyle(nominalLineWidth: 0.5, penProfileID: IDs.pen),
    semanticRole: .trainingProbe,
    ordering: 0
  )
  return try DrawingProgram(
    id: IDs.program,
    fieldExtent: Size2(width: 100, height: 100),
    strokes: [stroke],
    source: DrawingSourceProvenance(kind: "café", sourceIdentifier: "probe-1")
  )
}

func validInstructions(modelID: ModelID = IDs.model) throws -> [ExecutionInstruction] {
  let pose = try clearancePose(polygon: [
    try cameraPoint(20, 20), try cameraPoint(25, 20),
    try cameraPoint(25, 25), try cameraPoint(20, 25),
  ])
  return [
    .liftPen(PenLiftRequest(penProfileID: IDs.pen, settleNanoseconds: 300_000_000)),
    .acquireStableFrame(
      try StableFrameRequirement(
        minimumFrameCount: 3,
        newerThanMonotonicNanoseconds: 0,
        maximumSpanNanoseconds: 1_000_000_000
      )),
    .inspect(try InspectionRequest(kind: .cleanBaseline, observationRegionID: IDs.region)),
    .travel(
      try MotionPath(
        path: Polyline(points: [try machinePoint(0, 0), try machinePoint(1, 1)]),
        maximumFeed: 100
      )),
    .draw(
      try DrawPath(
        strokeID: IDs.stroke,
        sliceID: IDs.slice,
        path: Polyline(points: [try machinePoint(1, 1), try machinePoint(4, 4)]),
        modelID: modelID,
        maximumFeed: 50
      )),
    .awaitControllerIdle(try Deadline(durationNanoseconds: 2_000_000_000)),
    .liftPen(PenLiftRequest(penProfileID: IDs.pen, settleNanoseconds: 300_000_000)),
    .clearObservationRegion(try clearancePath(to: pose), try observationRegion()),
    .acquireStableFrame(
      try StableFrameRequirement(
        minimumFrameCount: 3,
        newerThanMonotonicNanoseconds: 1,
        maximumSpanNanoseconds: 1_000_000_000
      )),
    .inspect(
      try InspectionRequest(
        kind: .isolatedInk,
        observationRegionID: IDs.region,
        baselineEvidenceID: IDs.evidence
      )),
    .checkpoint(IDs.checkpoint),
  ]
}

func executionPlan(instructions: [ExecutionInstruction]? = nil) throws -> ExecutionPlan {
  let program = try drawingProgram()
  return try ExecutionPlan(
    id: IDs.plan,
    revision: 0,
    parent: nil,
    programID: program.id,
    programHash: program.contentHash,
    modelID: IDs.model,
    stateEstimateID: IDs.state,
    fieldRegistrationID: IDs.registration,
    safetyPolicyID: IDs.safety,
    machineConfigurationID: IDs.machine,
    compilerVersion: 1,
    instructions: instructions ?? validInstructions()
  )
}

func authority(
  allowed: Bool = true,
  operation: AuthorizedOperation = .isolatedTrainingProbe,
  planID: PlanID = IDs.plan,
  modelID: ModelID = IDs.model,
  stateEstimateID: StateEstimateID = IDs.state,
  safetyPolicyID: SafetyPolicyID = IDs.safety,
  blockers: [RunBlocker] = []
) throws -> ExecutionAuthority {
  try ExecutionAuthority(
    allowed: allowed,
    operation: allowed ? operation : nil,
    planID: planID,
    modelID: modelID,
    stateEstimateID: stateEstimateID,
    fixedSafetyPolicyID: safetyPolicyID,
    evidence: [IDs.evidence],
    limits: AuthorityLimits(
      maximumFeed: 100,
      maximumDistance: 20,
      maximumCommandHorizonNanoseconds: 2_000_000_000
    ),
    blockers: blockers
  )
}

func emptyFrontiers() throws -> ExecutionFrontiers {
  try ExecutionFrontiers(
    planID: IDs.plan,
    commandedThrough: nil,
    controllerCompletedThrough: nil,
    inkBySlice: [:]
  )
}

func successorResolution(
  priorFrontiers: ExecutionFrontiers,
  programID: ProgramID = IDs.program,
  safetyPolicyID: SafetyPolicyID = IDs.safety
) throws -> CheckpointResolution {
  try CheckpointResolution(
    id: IDs.resolution,
    checkpointID: IDs.checkpoint,
    decision: CheckpointDecision(
      evidenceDisposition: .accepted(IDs.evidence),
      stateSelection: .accept(IDs.evidence, IDs.successorState),
      modelSelection: .accept(IDs.evidence, IDs.candidate, IDs.successorModel),
      nextAction: .planSuccessor
    ),
    priorFrontiers: priorFrontiers,
    resultingFrontiers: priorFrontiers,
    nextPlanningBasis: PlanningBasis(
      programID: programID,
      currentPlanID: priorFrontiers.planID,
      modelID: IDs.successorModel,
      stateEstimateID: IDs.successorState,
      safetyPolicyID: safetyPolicyID,
      unresolvedSlices: [IDs.otherSlice]
    )
  )
}

func successorActivation(
  programID: ProgramID = IDs.program,
  planID: PlanID = IDs.successorPlan,
  modelID: ModelID = IDs.successorModel,
  stateEstimateID: StateEstimateID = IDs.successorState,
  safetyPolicyID: SafetyPolicyID = IDs.safety,
  frontiers: ExecutionFrontiers? = nil,
  activationAuthority: ExecutionAuthority? = nil
) throws -> SuccessorPlanActivation {
  let resolvedFrontiers =
    try frontiers
    ?? ExecutionFrontiers(
      planID: planID,
      commandedThrough: nil,
      controllerCompletedThrough: nil,
      inkBySlice: [:]
    )
  let resolvedAuthority =
    try activationAuthority
    ?? authority(
      planID: planID,
      modelID: modelID,
      stateEstimateID: stateEstimateID,
      safetyPolicyID: safetyPolicyID
    )
  return try SuccessorPlanActivation(
    programID: programID,
    planID: planID,
    modelID: modelID,
    stateEstimateID: stateEstimateID,
    safetyPolicyID: safetyPolicyID,
    frontiers: resolvedFrontiers,
    authority: resolvedAuthority
  )
}
