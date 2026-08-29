import PlotterModel
import Testing

@testable import PlotterRuntime

@Suite("Simulated Learning Runtime")
struct SimulatedLearningRuntimeTests {
  @Test("connect and Enable Motion are separate simulator admissions")
  func connectAndEnableMotion() async throws {
    let runtime = SimulatedLearningRuntime()

    var snapshot = await runtime.snapshot()
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
    #expect(snapshot.penPose == .up)
    #expect(snapshot.mpos == .zero)
    #expect(snapshot.evidenceNotice.label == "SIMULATED — NOT PHYSICAL EVIDENCE")

    let refusedEnable = await runtime.enableMotion()
    #expect(refusal(refusedEnable) == .sessionDisconnected)
    #expect(refusedEnable.evidenceNotice == .notPhysicalEvidence)
    snapshot = try accepted(await runtime.connect())
    #expect(snapshot.session == .connected)
    #expect(snapshot.motionAuthorization == .disabled)

    snapshot = try accepted(await runtime.enableMotion())
    #expect(snapshot.motionAuthorization == .enabled)
    #expect(snapshot.evidenceNotice == .notPhysicalEvidence)

    snapshot = try accepted(await runtime.disableMotion())
    #expect(snapshot.motionAuthorization == .disabled)
    snapshot = try accepted(await runtime.disconnect())
    #expect(snapshot.session == .disconnected)
    #expect(snapshot.motionAuthorization == .disabled)
  }

  @Test("world auto-fit is uniform centered invertible and stable for arbitrary truth")
  func worldAutoFitGeometry() throws {
    let truths = [
      SimulatedLearningBoundaryTruth(
        negativeXMM: -200, positiveXMM: 200,
        negativeYMM: -20, positiveYMM: 20
      ),
      SimulatedLearningBoundaryTruth(
        negativeXMM: 20, positiveXMM: 60,
        negativeYMM: -180, positiveYMM: 180
      ),
      SimulatedLearningBoundaryTruth(
        negativeXMM: 120, positiveXMM: 260,
        negativeYMM: 80, positiveYMM: 150
      ),
      SimulatedLearningBoundaryTruth(
        negativeXMM: -351.473, positiveXMM: -164.923,
        negativeYMM: -76.534, positiveYMM: 82.633
      ),
    ]

    for truth in truths {
      let transform = try SimulatedWorldToCameraTransform(
        truth: truth,
        frameWidth: 640,
        frameHeight: 480
      )
      let repeated = try SimulatedWorldToCameraTransform(
        truth: truth,
        frameWidth: 640,
        frameHeight: 480
      )
      #expect(transform == repeated)
      #expect(transform.viewportID == repeated.viewportID)

      let center = try SimulatedLearningMPos(
        xMM: (truth.negativeXMM + truth.positiveXMM) / 2,
        yMM: (truth.negativeYMM + truth.positiveYMM) / 2
      )
      let cameraCenter = transform.cameraPoint(for: center)
      #expect(abs(cameraCenter.x - 320) < 1e-10)
      #expect(abs(cameraCenter.y - 240) < 1e-10)

      let probe = try SimulatedLearningMPos(
        xMM: truth.negativeXMM + 0.37 * (truth.positiveXMM - truth.negativeXMM),
        yMM: truth.negativeYMM + 0.61 * (truth.positiveYMM - truth.negativeYMM)
      )
      let roundTrip = transform.worldPosition(for: transform.cameraPoint(for: probe))
      #expect(abs(roundTrip.xMM - probe.xMM) < 1e-10)
      #expect(abs(roundTrip.yMM - probe.yMM) < 1e-10)

      let xStep = transform.cameraPoint(
        for: try SimulatedLearningMPos(xMM: probe.xMM + 1, yMM: probe.yMM)
      )
      let yStep = transform.cameraPoint(
        for: try SimulatedLearningMPos(xMM: probe.xMM, yMM: probe.yMM + 1)
      )
      let base = transform.cameraPoint(for: probe)
      #expect(abs((xStep.x - base.x) - transform.scalePixelsPerMillimeter) < 1e-10)
      #expect(abs((yStep.y - base.y) - transform.scalePixelsPerMillimeter) < 1e-10)
      #expect(xStep.x > base.x)
      #expect(yStep.y > base.y)

      let fitted = transform.fittedWorldBounds
      let minimum = transform.cameraPoint(
        for: try SimulatedLearningMPos(
          xMM: fitted.negativeXMM,
          yMM: fitted.negativeYMM
        )
      )
      let maximum = transform.cameraPoint(
        for: try SimulatedLearningMPos(
          xMM: fitted.positiveXMM,
          yMM: fitted.positiveYMM
        )
      )
      #expect(minimum.x >= transform.paddingPixels - 1e-10)
      #expect(minimum.y >= transform.paddingPixels - 1e-10)
      #expect(maximum.x <= Double(transform.frameWidth) - transform.paddingPixels + 1e-10)
      #expect(maximum.y <= Double(transform.frameHeight) - transform.paddingPixels + 1e-10)
    }
  }

  @Test("negative regression truth keeps initial MPos armature and limits in frame")
  func negativeRegressionViewport() async throws {
    let truth = SimulatedLearningBoundaryTruth(
      negativeXMM: -351.473, positiveXMM: -164.923,
      negativeYMM: -76.534, positiveYMM: 82.633
    )
    let initial = try SimulatedLearningMPos(xMM: -258.198, yMM: 3.0495)
    let runtime = SimulatedLearningRuntime(initialMPos: initial, boundaryTruth: truth)
    let scene = try accepted(await runtime.captureSceneFrame())
    #expect(scene.controllerPosition == initial)
    #expect(scene.armatureBounds.minX >= 0)
    #expect(scene.armatureBounds.minY >= 0)
    #expect(scene.armatureBounds.maxX < 640)
    #expect(scene.armatureBounds.maxY < 480)
    let envelope = try #require(scene.annotations.first { $0.kind == .truthEnvelope })
    guard case .bounds(let bounds) = envelope.geometry else {
      Issue.record("Truth annotation must be bounds")
      return
    }
    #expect(bounds.minX >= scene.worldToCameraTransform.paddingPixels)
    #expect(bounds.minY >= scene.worldToCameraTransform.paddingPixels)
    #expect(bounds.maxX <= 640 - scene.worldToCameraTransform.paddingPixels)
    #expect(bounds.maxY <= 480 - scene.worldToCameraTransform.paddingPixels)
  }

  @Test("scene annotations are exact identity presentation only and learned facts are distinct")
  func annotationsArePresentationOnly() async throws {
    let runtime = SimulatedLearningRuntime()
    let plain = try accepted(await runtime.captureSceneFrame())
    let learnedX = try SimulatedLearningMPos(xMM: -40, yMM: 0)
    let learnedCenter = try SimulatedLearningMPos(xMM: 0.5, yMM: -0.25)
    let annotated = try accepted(
      await runtime.captureSceneFrame(
        annotationContext: .init(
          acceptedBoundaryPositions: [.negativeX: learnedX],
          learnedCenter: learnedCenter
        )
      )
    )

    #expect(
      plain.displayedFrame.frame.contentSHA256 == annotated.displayedFrame.frame.contentSHA256
    )
    #expect(plain.viewportID == annotated.viewportID)
    #expect(annotated.worldToCameraTransform.viewportID == annotated.viewportID)
    #expect(
      annotated.annotations.allSatisfy {
        $0.frameID == annotated.displayedFrame.frame.id
          && $0.cameraConfigurationID == annotated.displayedFrame.frame.cameraConfigurationID
          && $0.viewportID == annotated.viewportID
          && $0.evidenceNotice == .notPhysicalEvidence
      }
    )
    #expect(plain.annotations.allSatisfy { $0.kind != .learnedCenter })
    #expect(annotated.annotations.contains { $0.kind == .learnedCenter })
    #expect(annotated.annotations.contains { $0.kind == .acceptedLearnedSide(.negativeX) })
    #expect(annotated.annotations.contains { $0.kind == .truthEnvelope })
  }

  @Test("true camera refit rotates configuration while identical fit is stable")
  func cameraRefitIdentity() async throws {
    let runtime = SimulatedLearningRuntime()
    let initial = await runtime.snapshot()
    let unchanged = try await runtime.refitCamera(frameWidth: 640, frameHeight: 480)
    #expect(unchanged.cameraConfigurationID == initial.cameraConfigurationID)
    #expect(unchanged.viewportID == initial.viewportID)

    let changed = try await runtime.refitCamera(frameWidth: 800, frameHeight: 600)
    #expect(changed.cameraConfigurationID != initial.cameraConfigurationID)
    #expect(changed.viewportID != initial.viewportID)
  }
}

private func accepted<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) throws -> Value {
  try response.result.get()
}

private func refusal<Value: Sendable>(
  _ response: SimulatedLearningResponse<Value>
) -> SimulatedLearningRefusal? {
  guard case .failure(let refusal) = response.result else { return nil }
  return refusal
}
