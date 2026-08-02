import Testing

@testable import PlotterModel

@Suite("Registration and drawing model")
struct RegistrationAndModelTests {
  @Test("affine registration fits training geometry and validates independent holdouts")
  func fitRegistration() throws {
    func mapped(_ x: Double, _ y: Double) throws -> RegistrationCorrespondence {
      RegistrationCorrespondence(
        camera: try cameraPoint(x, y),
        field: try fieldPoint(2 * x + 0.5 * y + 3, -0.25 * x + 1.5 * y - 4)
      )
    }
    let registration = try FieldRegistration.fit(
      id: IDs.registration,
      training: [
        mapped(0, 0), mapped(10, 0), mapped(0, 10), mapped(12, 7), mapped(-2, 6),
      ],
      independentHoldouts: [mapped(3, 4), mapped(8, 2)],
      maximumHoldoutError: 1e-8
    )
    let result = try registration.fieldPoint(from: cameraPoint(6, 5))
    let expected = try fieldPoint(17.5, 2)
    #expect(result.distance(to: expected) < 1e-9)
    #expect(registration.validation.holdoutCount == 2)
    #expect(registration.validation.maximumError < 1e-9)
  }

  @Test("collinear registration evidence is rejected")
  func rejectsDegenerateRegistration() throws {
    let training = try [0.0, 1, 2, 3].map { value in
      RegistrationCorrespondence(
        camera: try cameraPoint(value, value),
        field: try fieldPoint(value, value)
      )
    }
    let holdouts = [
      RegistrationCorrespondence(camera: try cameraPoint(4, 4), field: try fieldPoint(4, 4)),
      RegistrationCorrespondence(camera: try cameraPoint(5, 5), field: try fieldPoint(5, 5)),
    ]
    #expect(throws: RegistrationError.degenerateTrainingGeometry) {
      _ = try FieldRegistration.fit(
        id: IDs.registration,
        training: training,
        independentHoldouts: holdouts,
        maximumHoldoutError: 0.1
      )
    }
  }

  @Test("self-fit points cannot be reused as holdout validation")
  func rejectsReusedHoldout() throws {
    let samples = [
      RegistrationCorrespondence(camera: try cameraPoint(0, 0), field: try fieldPoint(0, 0)),
      RegistrationCorrespondence(camera: try cameraPoint(10, 0), field: try fieldPoint(10, 0)),
      RegistrationCorrespondence(camera: try cameraPoint(0, 10), field: try fieldPoint(0, 10)),
    ]
    #expect(throws: RegistrationError.holdoutIsNotIndependent) {
      _ = try FieldRegistration.fit(
        id: IDs.registration,
        training: samples,
        independentHoldouts: [samples[0], samples[1]],
        maximumHoldoutError: 0.1
      )
    }
  }

  @Test("held-out error gate rejects a plausible but wrong map")
  func holdoutGate() throws {
    let training = [
      RegistrationCorrespondence(camera: try cameraPoint(0, 0), field: try fieldPoint(0, 0)),
      RegistrationCorrespondence(camera: try cameraPoint(10, 0), field: try fieldPoint(10, 0)),
      RegistrationCorrespondence(camera: try cameraPoint(0, 10), field: try fieldPoint(0, 10)),
    ]
    let holdouts = [
      RegistrationCorrespondence(camera: try cameraPoint(2, 2), field: try fieldPoint(3, 2)),
      RegistrationCorrespondence(camera: try cameraPoint(8, 8), field: try fieldPoint(9, 8)),
    ]
    #expect {
      _ = try FieldRegistration.fit(
        id: IDs.registration,
        training: training,
        independentHoldouts: holdouts,
        maximumHoldoutError: 0.1
      )
    } throws: { error in
      guard case RegistrationError.holdoutValidationFailed = error else { return false }
      return true
    }
  }

  @Test("inverse is numerical inversion of the accepted forward model with a forward check")
  func inverseForwardCheck() throws {
    let model = try affineModel()
    let commanded = try machinePoint(12, 8)
    let desired = try model.predictedFieldPoint(for: commanded)
    let recovered = try CommandInverter.machinePoint(
      for: desired,
      using: model,
      maximumForwardError: 1e-9
    )
    #expect(recovered.distance(to: commanded) < 1e-10)
  }

  @Test("inverse refuses commands outside the fixed machine domain")
  func inverseRefusesExtrapolation() throws {
    let model = try affineModel()
    #expect(throws: GeometryError.outsideDomain) {
      _ = try CommandInverter.machinePoint(
        for: fieldPoint(10_000, 10_000),
        using: model,
        maximumForwardError: 0.01
      )
    }
  }

  @Test("candidate remains a distinct non-authoritative value")
  func candidateDistinct() throws {
    let model = try affineModel()
    let candidate = ModelCandidate(
      id: IDs.candidate,
      parentModelID: model.id,
      proposedMachineToField: model.machineToField,
      machineDomain: model.machineDomain,
      validation: try ModelValidationReport(
        independentTrialCount: 1,
        holdoutRootMeanSquareError: 1,
        holdoutMaximumError: 2,
        accepted: false
      )
    )
    #expect(candidate.parentModelID == model.id)
    #expect(!candidate.validation.accepted)
  }
}

@Suite("Armature clearance")
struct ClearanceTests {
  @Test("camera-space envelope disjoint from projected ROI is clear")
  func clear() throws {
    let pose = try clearancePose(polygon: [
      cameraPoint(20, 20), cameraPoint(25, 20),
      cameraPoint(25, 25), cameraPoint(20, 25),
    ])
    let assessment = try ClearanceValidator.assess(
      observationRegion: observationRegion(),
      registration: identityRegistration(),
      clearancePose: pose
    )
    #expect(assessment.isClear)
  }

  @Test("overlap blocks clearance")
  func overlapBlocks() throws {
    let pose = try clearancePose(polygon: [
      cameraPoint(8, 8), cameraPoint(12, 8),
      cameraPoint(12, 12), cameraPoint(8, 12),
    ])
    #expect(
      try ClearanceValidator.assess(
        observationRegion: observationRegion(),
        registration: identityRegistration(),
        clearancePose: pose
      ) == .blocked)
  }

  @Test("uncertainty plus margin is conservatively inflated")
  func inflatedOverlapBlocks() throws {
    let pose = try clearancePose(
      polygon: [
        cameraPoint(12, 0), cameraPoint(14, 0),
        cameraPoint(14, 2), cameraPoint(12, 2),
      ],
      uncertainty: 1,
      margin: 1
    )
    #expect(
      try ClearanceValidator.assess(
        observationRegion: observationRegion(),
        registration: identityRegistration(),
        clearancePose: pose
      ) == .blocked)
  }

  @Test("clearance path is bounded and terminates at its measured pose")
  func pathBounded() throws {
    let pose = try clearancePose(polygon: [
      cameraPoint(20, 20), cameraPoint(25, 20),
      cameraPoint(25, 25), cameraPoint(20, 25),
    ])
    let path = try clearancePath(to: pose)
    #expect(path.path.length <= path.maximumDistance)
    #expect(path.path.end == pose.machinePosition)
  }
}
