import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

struct DrawingMaterialMeasurementTests {
  @Test("Both edges recover synthetic width across anisotropy, shear and directions")
  func twoEdgesUsePerpendicularMachineDistance() async throws {
    let transforms: [AffineTransform2<MachineSpace, CameraPixelSpace>] = [
      try .init(m11: 10, m12: 0, m21: 0, m22: 10, tx: 100, ty: 100),
      try .init(m11: 12, m12: 5, m21: 1, m22: 7, tx: 60, ty: 60)
    ]
    for transform in transforms {
      for vertical in [false, true] {
        let path = try line(vertical ? [(16, 6), (16, 30)] : [(6, 16), (30, 16)])
        let request = try fixture(paths: [path], transform: transform, width: 0.8)
        let measured = try await VisionWorker().measureDepositedWidth(request)
        let distribution = try #require(measured.distribution)
        #expect(measured.samples.count >= 3)
        #expect(abs(try #require(distribution.medianMM) - 0.8) < 0.2)
        #expect(measured.qualification != .independentlyMeasured)
        #expect(measured.samples.allSatisfy { $0.firstEdge != $0.secondEdge && $0.uncertaintyMM > 0 })
        #expect(measured.alignment?.shiftX == 0)
        #expect(measured.geometry == [path])
        let decoded = try JSONDecoder().decode(DrawingMaterialMeasurement.self,
          from: JSONEncoder().encode(measured))
        #expect(decoded == measured)
      }
    }
  }

  @Test("A real sixteen-chord geometry can measure resolved isolated interiors; filled centre cannot")
  func polygonRingUsesActualChords() async throws {
    let points: [(Double, Double)] = (0...16).map { index in
      let angle = Double(index) * Double.pi / 8.0
      return (10.0 + 2.0*cos(angle), 10.0 + 2.0*sin(angle))
    }
    let ring = try line(points)
    let transform = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: 25, m12: 0, m21: 0, m22: 25, tx: 70, ty: 0)
    let narrow = try fixture(paths: [ring], transform: transform, width: 0.12, maximumWidth: 0.8)
    let good = try await VisionWorker().measureDepositedWidth(narrow)
    #expect(!good.samples.isEmpty)
    #expect(good.samples.allSatisfy { $0.segmentIndex >= 0 && $0.segmentIndex < 16 })
    let filled = try fixture(paths: [ring], transform: transform, width: 0.12,
      maximumWidth: 0.8, filledDisk: (10, 10, 2))
    let bad = try await VisionWorker().measureDepositedWidth(filled)
    #expect(bad.samples.isEmpty)
    #expect(bad.qualification == .unavailable)
  }

  @Test("Calibration rings crossing the centre hull retain only supported interior edge samples")
  func calibrationDomainClipsSamples() async throws {
    let points: [(Double, Double)] = (0...16).map { index in
      let angle = Double(index) * Double.pi / 8.0
      return (2.0*cos(angle), 10.0 + 2.0*sin(angle))
    }
    let ring = try line(points)
    let transform = try AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: 25, m12: 0, m21: 0, m22: 25, tx: 150, ty: 0)
    let request = try fixture(paths: [ring], transform: transform, width: 0.12, maximumWidth: 0.8)
    let report = try await VisionWorker().measureDepositedWidth(request)
    #expect(report.geometry == [ring])
    #expect(!report.samples.isEmpty)
    #expect((report.distribution?.exclusions["outside-calibrated-domain"] ?? 0) > 0)
    let inverse = try transform.inverted()
    for sample in report.samples {
      let distance = max(DrawingMaterialMeasurement.edgeExtrapolation(try inverse.applying(to: sample.firstEdge), domain: request.registration.applicabilityRectangle),
        DrawingMaterialMeasurement.edgeExtrapolation(try inverse.applying(to: sample.secondEdge), domain: request.registration.applicabilityRectangle))
      #expect(abs(distance-sample.edgeExtrapolationMM) < 1e-9)
      #expect(distance <= report.policy.maximumEdgeExtrapolationMM)
    }
  }

  @Test("Border on centre hull retains conditional edge extrapolation and exact policy")
  func borderAtCalibrationHull() async throws {
    let request = try fixture(paths: [line([(6, 0), (30, 0)])], width: 0.8, maximumWidth: 2)
    let report = try await VisionWorker().measureDepositedWidth(request)
    #expect(!report.samples.isEmpty)
    #expect(report.qualification == .bounded)
    #expect(report.samples.allSatisfy { $0.edgeExtrapolationMM > 0 && $0.edgeExtrapolationMM < 0.6 })
    #expect(report.limitations.contains { $0.contains("model error is unquantified") })
    #expect(report.policy.maximumWidthMM == 2)
    #expect(report.policy.maximumSamples == request.maximumSamples)
    #expect(report.policy.minimumLuminanceDecrease == request.thresholds.minimumLuminanceDecrease)
    #expect(try JSONDecoder().decode(DrawingMaterialMeasurement.self, from: JSONEncoder().encode(report)) == report)
  }

  @Test("Existing-ink mode retains one real frame and no invented pair or deposition attribution")
  func existingInkLocalPaper() async throws {
    let paired = try fixture(paths: [line([(6, 16), (30, 16)])], width: 0.8)
    let request = DrawingMaterialExistingInkMeasurementRequest(result: paired.result,
      registration: paired.registration, intendedPaths: paired.intendedPaths, occlusionMask: paired.occlusionMask,
      maximumWidthMM: 2, currentApplicability: paired.currentApplicability)
    let report = try await VisionWorker().measureDepositedWidth(request)
    #expect(!report.samples.isEmpty)
    #expect(report.frames == nil)
    #expect(report.singleFrame?.frameID == paired.result.frame.id)
    #expect(report.alignment == nil)
    #expect(report.observationMode == .existingInkLocalContrast)
    #expect(report.limitations.contains { $0.contains("attribution are unknown") })
    #expect(abs(try #require(report.distribution?.medianMM) - 0.8) < 0.2)
  }

  @Test("A bounded one-pixel shift is retained and removed before inverse geometry")
  func boundedAlignment() async throws {
    let request = try fixture(paths: [line([(6, 16), (30, 16)])], width: 0.8, shiftX: 1)
    let result = try await VisionWorker().measureDepositedWidth(request)
    #expect(result.alignment?.shiftX == 1)
    #expect(abs(try #require(result.distribution?.medianMM) - 0.8) < 0.2)
  }

  @Test("Crossings and short pooled segments are excluded instead of averaged into width")
  func crossingAndPooling() async throws {
    let horizontal = try line([(6, 16), (30, 16)])
    let vertical = try line([(18, 5), (18, 28)])
    let request = try fixture(paths: [horizontal, vertical], width: 0.8)
    let result = try await VisionWorker().measureDepositedWidth(request)
    #expect((result.distribution?.exclusions["crossing-or-overlap"] ?? 0) > 0)
    #expect(!result.samples.isEmpty)
    let pooled = try fixture(paths: [line([(15, 16), (16, 16)])], width: 1.6)
    let excluded = try await VisionWorker().measureDepositedWidth(pooled)
    #expect(excluded.samples.isEmpty)
    #expect(excluded.qualification == .unavailable)
  }

  @Test("Blur, occlusion, unknown visibility and unresolved pixel widths do not claim precision")
  func insufficientEvidence() async throws {
    let path = try line([(6, 16), (30, 16)])
    let worker = VisionWorker()
    let blurred = try await worker.measureDepositedWidth(fixture(paths: [path], width: 0.8, blurMM: 1.2))
    #expect(blurred.samples.isEmpty)
    let thin = try await worker.measureDepositedWidth(fixture(paths: [path], width: 0.05))
    #expect(thin.samples.isEmpty)
    let occluded = try await worker.measureDepositedWidth(fixture(paths: [path], width: 0.8, occluded: true))
    #expect(occluded.samples.isEmpty)
    let unknown = try fixture(paths: [path], width: 0.8)
    let unclassified = DrawingMaterialMeasurementRequest(baseline: unknown.baseline, result: unknown.result,
      registration: unknown.registration, intendedPaths: unknown.intendedPaths,
      currentApplicability: unknown.currentApplicability)
    let report = try await worker.measureDepositedWidth(unclassified)
    #expect(report.qualification == .unavailable)
    #expect(report.limitations.contains { $0.contains("not been classified") })
  }

  @Test("Matched frame identity, pose and full current applicability are mandatory")
  func mismatchesRefuse() async throws {
    let request = try fixture(paths: [line([(6, 16), (30, 16)])], width: 0.8)
    let worker = VisionWorker()
    let noContext = DrawingMaterialMeasurementRequest(baseline: request.baseline, result: request.result,
      registration: request.registration, intendedPaths: request.intendedPaths, occlusionMask: request.occlusionMask)
    await #expect(throws: DrawingMaterialMeasurementError.applicabilityMismatch) {
      try await worker.measureDepositedWidth(noContext)
    }
    let otherSource = SamePoseFrameSample(source: .simulated, frame: request.result.frame,
      controllerPosition: request.result.controllerPosition)
    let wrongSource = DrawingMaterialMeasurementRequest(baseline: request.baseline, result: otherSource,
      registration: request.registration, intendedPaths: request.intendedPaths,
      currentApplicability: request.currentApplicability)
    await #expect(throws: DrawingMaterialMeasurementError.frameMismatch) {
      try await worker.measureDepositedWidth(wrongSource)
    }
    let moved = SamePoseFrameSample(source: request.result.source, frame: request.result.frame,
      controllerPosition: try MachinePosition(x: 2, y: 2))
    let wrongPose = DrawingMaterialMeasurementRequest(baseline: request.baseline, result: moved,
      registration: request.registration, intendedPaths: request.intendedPaths,
      currentApplicability: request.currentApplicability)
    await #expect(throws: DrawingMaterialMeasurementError.poseMismatch) {
      try await worker.measureDepositedWidth(wrongPose)
    }
    let changedPaper = TipCalibrationApplicabilityContext(
      opticalConfiguration: request.registration.applicability.opticalConfiguration,
      machineGeometry: request.registration.applicability.machineGeometry,
      machineCoordinateFrame: request.registration.applicability.machineCoordinateFrame,
      toolAssembly: request.registration.applicability.toolAssembly,
      penContactProfile: request.registration.applicability.penContactProfile,
      paperContactPlane: PaperContactPlaneRevision())
    let wrongApplicability = DrawingMaterialMeasurementRequest(baseline: request.baseline, result: request.result,
      registration: request.registration, intendedPaths: request.intendedPaths, currentApplicability: changedPaper)
    await #expect(throws: DrawingMaterialMeasurementError.applicabilityMismatch) {
      try await worker.measureDepositedWidth(wrongApplicability)
    }
  }

  @Test("Full affine covariance and residual increase conservative uncertainty")
  func uncertaintyPropagation() async throws {
    let paths = try [line([(6, 16), (30, 16)])]
    let worker = VisionWorker()
    let clean = try await worker.measureDepositedWidth(fixture(paths: paths, width: 0.8))
    let uncertain = try await worker.measureDepositedWidth(fixture(paths: paths, width: 0.8, covariance: true))
    #expect(try #require(uncertain.distribution?.uncertaintyMM) > #require(clean.distribution?.uncertaintyMM))
    #expect(uncertain.qualification == .bounded)
  }

  @Test("Finite samples and cooperative cancellation bound the work")
  func boundedAndCancelled() async throws {
    let request = try fixture(paths: [line([(6, 16), (30, 16)])], width: 0.8)
    let bounded = DrawingMaterialMeasurementRequest(baseline: request.baseline, result: request.result,
      registration: request.registration, intendedPaths: request.intendedPaths, occlusionMask: request.occlusionMask,
      maximumWidthMM: 2, maximumSamples: 2, currentApplicability: request.currentApplicability)
    let report = try await VisionWorker().measureDepositedWidth(bounded)
    #expect(report.samples.count <= 2)
    #expect(report.limitations.contains { $0.contains("sample budget") })
    let task = Task {
      while !Task.isCancelled { await Task.yield() }
      return try await VisionWorker().measureDepositedWidth(request)
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  private func line(_ pairs: [(Double, Double)]) throws -> Polyline<MachineSpace> {
    try Polyline(points: pairs.map { try Point2(x: $0.0, y: $0.1) })
  }

  /// Fixture camera mappings and pixel values are synthetic; they do not
  /// validate a physical tool or the independently unproved controller metric.
  private func fixture(paths: [Polyline<MachineSpace>],
    transform supplied: AffineTransform2<MachineSpace, CameraPixelSpace>? = nil,
    width: Double, maximumWidth: Double = 2, blurMM: Double = 0,
    occluded: Bool = false, covariance: Bool = false,
    filledDisk: (Double, Double, Double)? = nil, shiftX: Int = 0
  ) throws -> DrawingMaterialMeasurementRequest {
    let authority = try TipAuthorityFixture()
    let transform = try supplied ?? AffineTransform2<MachineSpace, CameraPixelSpace>(
      m11: 10, m12: 0, m21: 0, m22: 10, tx: 100, ty: 100)
    var encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(authority.registration())) as? [String: Any])
    encoded["cameraFromMachine"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(transform))
    var cov = Array(repeating: 0.0, count: 36)
    if covariance {
      // Correlated m11/m21/m12/m22 perturbation plus uncertain translation.
      let direction = [0.01, 0.02, 0.02, 0.01, 0.15, 0.2]
      for row in 0..<6 { for column in 0..<6 { cov[row * 6 + column] = direction[row] * direction[column] } }
    }
    encoded["uncertainty"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
      TipCalibrationUncertainty(affineParameterCovariance: cov,
        rootMeanSquareResidualPixels: covariance ? 1 : 0, maximumResidualPixels: covariance ? 2 : 0)))
    let registration = try JSONDecoder().decode(TipCameraRegistration.self,
      from: JSONSerialization.data(withJSONObject: encoded))
    let inverse = try transform.inverted()
    let w = 640, h = 480
    var before = [UInt8](repeating: 240, count: w * h)
    var after = before
    let segments = paths.flatMap { path in zip(path.points, path.points.dropFirst()).map { ($0.0, $0.1) } }
    for y in 0..<h { for x in 0..<w {
      let pixel = y * w + x
      let background = UInt8(225 + (x * 13 + y * 17) % 25)
      before[pixel] = background
      let point = try inverse.applying(to: Point2<CameraPixelSpace>(x: Double(x), y: Double(y)))
      let distance = segments.map { a, b in
        let dx = b.x - a.x, dy = b.y - a.y
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / (dx * dx + dy * dy)))
        return hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
      }.min() ?? .infinity
      let disk = filledDisk.map { hypot(point.x - $0.0, point.y - $0.1) <= $0.2 } ?? false
      let opacity: Double
      if disk || distance <= width * 0.5 { opacity = 1 }
      else if blurMM > 0 { opacity = max(0, 1 - (distance - width * 0.5) / blurMM) }
      else { opacity = 0 }
      after[pixel] = UInt8(max(0, Double(background) - 190 * opacity))
    } }
    if shiftX != 0 {
      let unshifted = after
      for y in 0..<h { for x in 0..<w {
        after[y * w + x] = unshifted[y * w + max(0, min(w - 1, x - shiftX))]
      } }
    }
    let baseline = try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: authority.cameraConfigurationID, width: w, height: h,
      rowBytes: w, pixelFormat: .gray8, bytes: OwnedFrameBytes(before))
    let result = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: authority.cameraConfigurationID, width: w, height: h,
      rowBytes: w, pixelFormat: .gray8, bytes: OwnedFrameBytes(after))
    return DrawingMaterialMeasurementRequest(
      baseline: SamePoseFrameSample(source: authority.source, frame: baseline, controllerPosition: try MachinePosition(x: 0, y: 0)),
      result: SamePoseFrameSample(source: authority.source, frame: result, controllerPosition: try MachinePosition(x: 0, y: 0)),
      registration: registration, intendedPaths: paths, occlusionMask: Array(repeating: occluded, count: w * h),
      maximumWidthMM: maximumWidth, currentApplicability: registration.applicability)
  }
}
