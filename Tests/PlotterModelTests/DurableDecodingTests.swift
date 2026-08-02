import Foundation
import Testing

@testable import PlotterModel

private func mutatedJSON<T: Encodable>(
  _ value: T,
  mutate: (inout [String: Any]) throws -> Void
) throws -> Data {
  let encoded = try JSONEncoder().encode(value)
  guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
    throw PlotterModelError.invalidValue("test fixture is not a JSON object")
  }
  try mutate(&object)
  return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

private func decodeFails<T: Decodable>(_ type: T.Type, from data: Data) -> Bool {
  do {
    _ = try JSONDecoder().decode(type, from: data)
    return false
  } catch {
    return true
  }
}

@Suite("Fail-closed durable decoding")
struct DurableDecodingTests {
  @Test("Digest rejects a non-SHA-256 byte count")
  func digestLength() {
    let malicious = Data(#"{"bytes":[1,2,3]}"#.utf8)
    #expect(decodeFails(Digest.self, from: malicious))
  }

  @Test("AuthorityLimits rejects negative machine bounds")
  func authorityLimits() throws {
    let valid = try AuthorityLimits(
      maximumFeed: 1,
      maximumDistance: 1,
      maximumCommandHorizonNanoseconds: 1
    )
    let malicious = try mutatedJSON(valid) { $0["maximumFeed"] = -1 }
    #expect(decodeFails(AuthorityLimits.self, from: malicious))
  }

  @Test("RunBlocker rejects whitespace-only durable text")
  func blockerText() throws {
    let valid = try RunBlocker(code: "camera_stale", summary: "No fresh frame")
    let malicious = try mutatedJSON(valid) { $0["code"] = "  \n" }
    #expect(decodeFails(RunBlocker.self, from: malicious))
  }

  @Test("ModelValidationReport rejects negative metrics")
  func modelValidationMetrics() throws {
    let valid = try ModelValidationReport(
      independentTrialCount: 1,
      holdoutRootMeanSquareError: 0.1,
      holdoutMaximumError: 0.2,
      accepted: true
    )
    let malicious = try mutatedJSON(valid) { $0["holdoutMaximumError"] = -1 }
    #expect(decodeFails(ModelValidationReport.self, from: malicious))
  }

  @Test("AdaptiveDrawingModel rejects a decoded unaccepted validation")
  func activeModelRequiresAcceptance() throws {
    let model = try affineModel()
    let malicious = try mutatedJSON(model) { object in
      var validation = try #require(object["validation"] as? [String: Any])
      validation["accepted"] = false
      object["validation"] = validation
    }
    #expect(decodeFails(AdaptiveDrawingModel.self, from: malicious))
  }

  @Test("MotionPath rejects a decoded negative feed")
  func motionFeed() throws {
    let motion = try MotionPath(
      path: Polyline(points: [try machinePoint(0, 0), try machinePoint(1, 1)]),
      maximumFeed: 1
    )
    let malicious = try mutatedJSON(motion) { $0["maximumFeed"] = -1 }
    #expect(decodeFails(MotionPath.self, from: malicious))
  }

  @Test("ToolOcclusionEnvelope rejects a decoded negative margin")
  func clearanceMargin() throws {
    let pose = try clearancePose(polygon: [
      try cameraPoint(20, 20), try cameraPoint(25, 20),
      try cameraPoint(25, 25), try cameraPoint(20, 25),
    ])
    let malicious = try mutatedJSON(pose.envelope) { $0["fixedMarginPixels"] = -1 }
    #expect(decodeFails(ToolOcclusionEnvelope.self, from: malicious))
  }

  @Test("ClearancePath rejects a decoded path that misses its destination")
  func clearanceDestination() throws {
    let pose = try clearancePose(polygon: [
      try cameraPoint(20, 20), try cameraPoint(25, 20),
      try cameraPoint(25, 25), try cameraPoint(20, 25),
    ])
    let path = try clearancePath(to: pose)
    let malicious = try mutatedJSON(path) { object in
      object["destinationMachinePosition"] = ["x": 99, "y": 99]
    }
    #expect(decodeFails(ClearancePath.self, from: malicious))
  }

  @Test("ExecutionFrontiers rejects decoded controller progress beyond commands")
  func frontierOrder() throws {
    let cursor = PlanCursor(planID: IDs.plan, instructionIndex: 4)
    let frontiers = try ExecutionFrontiers(
      planID: IDs.plan,
      commandedThrough: cursor,
      controllerCompletedThrough: cursor,
      inkBySlice: [:]
    )
    let malicious = try mutatedJSON(frontiers) { object in
      var completed = try #require(object["controllerCompletedThrough"] as? [String: Any])
      completed["instructionIndex"] = 5
      object["controllerCompletedThrough"] = completed
    }
    #expect(decodeFails(ExecutionFrontiers.self, from: malicious))
  }

  @Test("ExecutionAuthority rejects decoded drawing authority without evidence")
  func authorityEvidence() throws {
    let valid = try authority(operation: .generalDrawing)
    let malicious = try mutatedJSON(valid) { $0["evidence"] = [] }
    #expect(decodeFails(ExecutionAuthority.self, from: malicious))
  }

  @Test("ExecutionAuthority rejects decoded drawing authority without a model")
  func authorityModel() throws {
    let valid = try authority(operation: .generalDrawing)
    let malicious = try mutatedJSON(valid) { $0["modelID"] = NSNull() }
    #expect(decodeFails(ExecutionAuthority.self, from: malicious))
  }

  @Test("ExecutionAuthority rejects decoded machine authority with zero limits")
  func authorityPositiveLimits() throws {
    let valid = try authority(operation: .boundedPenUpTrial)
    let malicious = try mutatedJSON(valid) { object in
      var limits = try #require(object["limits"] as? [String: Any])
      limits["maximumDistance"] = 0
      object["limits"] = limits
    }
    #expect(decodeFails(ExecutionAuthority.self, from: malicious))
  }

  @Test("Passive interrogation round-trips with nil identities and zero limits")
  func passiveAuthorityRoundTrip() throws {
    let passive = try ExecutionAuthority(
      allowed: true,
      operation: .passiveInterrogation,
      planID: nil,
      modelID: nil,
      stateEstimateID: nil,
      fixedSafetyPolicyID: IDs.safety,
      evidence: [],
      limits: AuthorityLimits(
        maximumFeed: 0,
        maximumDistance: 0,
        maximumCommandHorizonNanoseconds: 0
      ),
      blockers: []
    )
    let decoded = try JSONDecoder().decode(
      ExecutionAuthority.self,
      from: JSONEncoder().encode(passive)
    )
    #expect(decoded == passive)
  }

  @Test("PlanningBasis rejects decoded duplicate unresolved slices")
  func planningBasisDuplicates() throws {
    let basis = try PlanningBasis(
      programID: IDs.program,
      currentPlanID: IDs.plan,
      modelID: IDs.model,
      stateEstimateID: IDs.state,
      safetyPolicyID: IDs.safety,
      unresolvedSlices: [IDs.slice]
    )
    let malicious = try mutatedJSON(basis) { object in
      let slices = try #require(object["unresolvedSlices"] as? [Any])
      object["unresolvedSlices"] = slices + slices
    }
    #expect(decodeFails(PlanningBasis.self, from: malicious))
  }

  @Test("SuccessorPlanActivation rejects decoded authority identity drift")
  func successorActivationIdentity() throws {
    let valid = try successorActivation()
    let malicious = try mutatedJSON(valid) { object in
      var authority = try #require(object["authority"] as? [String: Any])
      authority["modelID"] = object["planID"]
      object["authority"] = authority
    }
    #expect(decodeFails(SuccessorPlanActivation.self, from: malicious))
  }

  @Test("SuccessorPlanActivation rejects decoded pre-advanced frontiers")
  func successorActivationFreshFrontiers() throws {
    let valid = try successorActivation()
    let cursor = PlanCursor(planID: IDs.successorPlan, instructionIndex: 0)
    let progressed = try ExecutionFrontiers(
      planID: IDs.successorPlan,
      commandedThrough: cursor,
      controllerCompletedThrough: cursor,
      inkBySlice: [:]
    )
    let progressedObject = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(progressed)) as? [String: Any]
    )
    let malicious = try mutatedJSON(valid) { object in
      object["frontiers"] = progressedObject
    }
    #expect(decodeFails(SuccessorPlanActivation.self, from: malicious))
  }
}
