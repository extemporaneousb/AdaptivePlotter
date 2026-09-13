import Foundation
import PlotterModel

public enum DrawingMaterialMeasurementError: Error, Equatable, Sendable {
  case invalidPolicy, frameMismatch, poseMismatch, applicabilityMismatch, unsupportedGeometry
}

extension VisionWorker {
  /// Measures deposited ink in controller-coordinate millimetres. The camera
  /// registration is not an independent physical length standard.
  public func measureDepositedWidth(
    _ request: DrawingMaterialMeasurementRequest
  ) async throws -> DrawingMaterialMeasurement {
    guard request.baseline.source == request.result.source,
      request.baseline.frame.id != request.result.frame.id,
      request.baseline.frame.captureNanoseconds < request.result.frame.captureNanoseconds,
      request.baseline.frame.cameraConfigurationID == request.result.frame.cameraConfigurationID,
      request.baseline.frame.width == request.result.frame.width,
      request.baseline.frame.height == request.result.frame.height,
      request.baseline.frame.rowBytes == request.result.frame.rowBytes,
      request.baseline.frame.pixelFormat == request.result.frame.pixelFormat
    else { throw DrawingMaterialMeasurementError.frameMismatch }
    guard request.baseline.controllerPosition.point.distance(to: request.result.controllerPosition.point) <= 0.02
    else { throw DrawingMaterialMeasurementError.poseMismatch }
    return try await measureMaterial(MaterialInput(baseline: request.baseline, result: request.result,
      registration: request.registration, intendedPaths: request.intendedPaths, occlusionMask: request.occlusionMask,
      maximumWidthMM: request.maximumWidthMM, thresholds: request.thresholds,
      maximumSamples: request.maximumSamples, currentApplicability: request.currentApplicability,
      visibilityEvidence: request.visibilityEvidence))
  }

  /// Existing marks are measured against observed local paper contrast. This
  /// mode does not assert when, or by which attempt, their ink was deposited.
  public func measureDepositedWidth(
    _ request: DrawingMaterialExistingInkMeasurementRequest
  ) async throws -> DrawingMaterialMeasurement {
    try await measureMaterial(MaterialInput(baseline: nil, result: request.result,
      registration: request.registration, intendedPaths: request.intendedPaths, occlusionMask: request.occlusionMask,
      maximumWidthMM: request.maximumWidthMM, thresholds: request.thresholds,
      maximumSamples: request.maximumSamples, currentApplicability: request.currentApplicability,
      visibilityEvidence: request.visibilityEvidence))
  }

  private struct MaterialInput {
    let baseline: SamePoseFrameSample?
    let result: SamePoseFrameSample
    let registration: TipCameraRegistration
    let intendedPaths: [Polyline<MachineSpace>]
    let occlusionMask: [Bool]?
    let maximumWidthMM: Double
    let thresholds: InkPixelThresholds
    let maximumSamples: Int
    let currentApplicability: TipCalibrationApplicabilityContext?
    let visibilityEvidence: DrawingMaterialVisibilityEvidence?
  }

  private func measureMaterial(_ request: MaterialInput) async throws -> DrawingMaterialMeasurement {
    try Task.checkCancellation()
    // This alias provides common raster dimensions only. Existing-ink mode
    // never constructs a baseline frame, frame pair, or alignment observation.
    let baseline = request.baseline?.frame ?? request.result.frame
    let result = request.result.frame
    guard request.maximumWidthMM.isFinite, request.maximumWidthMM > 0,
      request.maximumWidthMM <= 100, request.maximumSamples > 0, request.maximumSamples <= 8192,
      request.thresholds.minimumLuminanceDecrease > 0,
      baseline.width <= 8192, baseline.height <= 8192,
      baseline.width * baseline.height <= 16_777_216,
      request.occlusionMask.map({ $0.count == result.width * result.height }) ?? true
    else { throw DrawingMaterialMeasurementError.invalidPolicy }
    let optical = request.registration.applicability.opticalConfiguration
    guard request.currentApplicability == request.registration.applicability,
      optical.source == request.result.source, optical.width == baseline.width,
      optical.height == baseline.height, optical.pixelFormat == baseline.pixelFormat
    else { throw DrawingMaterialMeasurementError.applicabilityMismatch }
    guard !request.intendedPaths.isEmpty,
      request.intendedPaths.reduce(0, { $0 + $1.points.count }) <= 4096
    else { throw DrawingMaterialMeasurementError.unsupportedGeometry }
    let frames = try request.baseline.map { sample in
      try DrawingObservationFramePair(source: sample.source,
        baseline: ExactFrameProvenance(frame: sample.frame), post: ExactFrameProvenance(frame: result))
    }
    if let visibility = request.visibilityEvidence {
      let expectedFrames = (frames.map { [$0.baseline, $0.post] }) ?? [ExactFrameProvenance(frame: result)]
      guard visibility.source == request.result.source, visibility.inspectedFrames == expectedFrames,
        visibility.method == "operator-confirmed-unobstructed-v1", visibility.confirmedAt.timeIntervalSince1970.isFinite
      else { throw DrawingMaterialMeasurementError.frameMismatch }
    }
    let policy = DrawingMaterialMeasurementPolicy(maximumWidthMM: request.maximumWidthMM,
      maximumSamples: request.maximumSamples, minimumLuminanceDecrease: request.thresholds.minimumLuminanceDecrease)
    var limitations = [
      "Controller-coordinate estimate; independent physical millimetre accuracy is unverified.",
      "Raw frame hashes identify these inputs; raw image durability is not established by this measurement."
    ]
    if request.baseline == nil {
      limitations.append("Existing ink is compared with observed local paper on both sides; deposition time and attempt attribution are unknown.")
    }
    var exclusions: [String: Int] = [:]
    var alignment: IntegerFrameAlignment?
    func report(_ samples: [DepositedWidthSample], reason: String? = nil) throws -> DrawingMaterialMeasurement {
      var notes = limitations
      if let reason { notes.append(reason) }
      let distribution: DepositedWidthDistribution?
      let qualification: MaterialWidthQualification
      if samples.isEmpty {
        distribution = nil
        qualification = .unavailable
        notes.append("Exclusions: " + exclusions.keys.sorted().map { "\($0)=\(exclusions[$0]!)" }.joined(separator: ", "))
      } else {
        let widths = samples.map(\.widthMM).sorted()
        let median = Self.materialMedian(widths)
        let uncertainty = samples.map(\.uncertaintyMM).max() ?? 0
        let groups = Dictionary(grouping: samples) { Int(($0.directionRadians / .pi * 8).rounded()) % 8 }
        let directional = try groups.keys.sorted().map { key in
          let values = groups[key]!
          return try DirectionalWidthEstimate(directionRadians: Double(key) * .pi / 8,
            medianMM: Self.materialMedian(values.map(\.widthMM).sorted()),
            uncertaintyMM: values.map(\.uncertaintyMM).max() ?? 0, sampleCount: values.count)
        }
        distribution = try DepositedWidthDistribution(medianMM: median,
          lowerBoundMM: widths.first!, upperBoundMM: widths.last!, uncertaintyMM: uncertainty,
          sampleCount: widths.count, directional: directional, exclusions: exclusions)
        let extrapolation = samples.map(\.edgeExtrapolationMM).max() ?? 0
        if extrapolation > 1e-9 {
          notes.append("Conditional affine edge extrapolation up to \(extrapolation) mm beyond the calibration centre hull. Covariance is evaluated at those edges; out-of-domain model error is unquantified. This is not an unconditional physical width bound.")
        }
        qualification = extrapolation <= 1e-9 && samples.count >= 3 && uncertainty < median * 0.5
          ? .controllerCoordinateEstimate : .bounded
        if qualification == .bounded { notes.append("Sample count or uncertainty supports only a bounded width estimate.") }
      }
      return DrawingMaterialMeasurement(algorithmRevision: "two-edge-material-v1", frames: frames,
        registration: request.registration, geometry: request.intendedPaths,
        qualification: qualification, distribution: distribution, samples: samples,
        limitations: notes, alignment: alignment, source: request.result.source,
        singleFrame: request.baseline == nil ? ExactFrameProvenance(frame: result) : nil,
        observationMode: request.baseline == nil ? .existingInkLocalContrast : .pairedNewInk,
        visibilityEvidence: request.visibilityEvidence, policy: policy)
    }
    guard let occlusion = request.occlusionMask else {
      exclusions["occlusion-unclassified"] = 1
      return try report([], reason: "Visible unoccluded support has not been classified.")
    }
    let transform = request.registration.cameraFromMachine
    let inverse = try transform.inverted()
    let segments = try Self.materialSegments(request.intendedPaths, transform: transform)
    guard !segments.isEmpty else { throw DrawingMaterialMeasurementError.unsupportedGeometry }
    let cameraPoints = segments.flatMap { [$0.cameraA, $0.cameraB] }
    let maxScale = sqrt(transform.m11 * transform.m11 + transform.m12 * transform.m12
      + transform.m21 * transform.m21 + transform.m22 * transform.m22)
    guard maxScale.isFinite, maxScale > 0, maxScale <= 100_000,
      cameraPoints.allSatisfy({ abs($0.x) < 1_000_000_000 && abs($0.y) < 1_000_000_000 })
    else { throw DrawingMaterialMeasurementError.unsupportedGeometry }
    let padding = request.maximumWidthMM * maxScale + 4
    let minX = max(0, Int(floor(cameraPoints.map(\.x).min()! - padding)))
    let minY = max(0, Int(floor(cameraPoints.map(\.y).min()! - padding)))
    let maxX = min(baseline.width, Int(ceil(cameraPoints.map(\.x).max()! + padding)))
    let maxY = min(baseline.height, Int(ceil(cameraPoints.map(\.y).max()! + padding)))
    guard maxX > minX, maxY > minY else { return try report([], reason: "Intended ink is outside the captured image.") }
    let region = PixelRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    if request.baseline != nil {
      do {
        alignment = try await Self.boundedSubsampledIntegerAlignment(baseline, result,
          excluding: region, searchRadius: 2, baseComputation: .zero, checkpointHandler: nil).alignment
      } catch is CancellationError { throw CancellationError() }
      catch { return try report([], reason: "Background alignment support is unavailable.") }
      guard let aligned = alignment,
        abs(aligned.shiftX) <= 1, abs(aligned.shiftY) <= 1,
        aligned.backgroundMeanAbsoluteDifference <= 4
      else { return try report([], reason: "Background shift or residual exceeds the bounded alignment policy.") }
      limitations.append("Integer alignment permits at most one pixel translation; subpixel alignment uncertainty is included.")
    }
    let shiftX = alignment?.shiftX ?? 0, shiftY = alignment?.shiftY ?? 0
    var samples: [DepositedWidthSample] = []
    var inspected = 0
    segmentLoop: for segment in segments {
      let cameraLength = segment.cameraA.distance(to: segment.cameraB)
      guard cameraLength >= 4 else { exclusions["short-segment", default: 0] += 1; continue }
      let cameraNX = -(segment.cameraB.y - segment.cameraA.y) / cameraLength
      let cameraNY = (segment.cameraB.x - segment.cameraA.x) / cameraLength
      // n_machine^T B^-1 converts camera-normal separation into true
      // perpendicular separation. Its absolute value is not |B^-1 n_camera|.
      let qx = segment.nx * inverse.m11 + segment.ny * inverse.m21
      let qy = segment.nx * inverse.m12 + segment.ny * inverse.m22
      let perpendicularPerPixel = abs(qx * cameraNX + qy * cameraNY)
      guard perpendicularPerPixel.isFinite, perpendicularPerPixel > 1e-10 else { continue }
      let scanRadius = min(512, Int(ceil(request.maximumWidthMM / perpendicularPerPixel)))
      guard scanRadius >= 3, scanRadius < 512 else { exclusions["resolution-or-scan-budget", default: 0] += 1; continue }
      let count = max(1, min(64, Int(cameraLength / 3)))
      for index in 0..<count {
        try Task.checkCancellation()
        inspected += 1
        if inspected > request.maximumSamples {
          exclusions["sample-budget", default: 0] += 1
          limitations.append("Sampling stopped at the declared finite sample budget; uninspected geometry is unknown.")
          break segmentLoop
        }
        let fraction = Double(index + 1) / Double(count + 1)
        let mx = segment.a.x + (segment.b.x - segment.a.x) * fraction
        let my = segment.a.y + (segment.b.y - segment.a.y) * fraction
        guard DrawingRegionContainmentPolicy.contains(try Point2<MachineSpace>(x: mx, y: my),
          in: request.registration.applicabilityRectangle) else {
          exclusions["outside-calibrated-domain", default: 0] += 1; continue
        }
        let cx = segment.cameraA.x + (segment.cameraB.x - segment.cameraA.x) * fraction
        let cy = segment.cameraA.y + (segment.cameraB.y - segment.cameraA.y) * fraction
        var values: [Double] = []
        var blocked = false
        for offset in -scanRadius...scanRadius {
          let x = Int((cx + cameraNX * Double(offset)).rounded())
          let y = Int((cy + cameraNY * Double(offset)).rounded())
          let rx = x + shiftX, ry = y + shiftY
          guard x >= 0, y >= 0, x < baseline.width, y < baseline.height,
            rx >= 0, ry >= 0, rx < result.width, ry < result.height else {
            exclusions["image-edge", default: 0] += 1; blocked = true; break
          }
          if occlusion[ry * result.width + rx] {
            exclusions["occluded", default: 0] += 1; blocked = true; break
          }
          if request.baseline != nil {
            values.append(Double(Self.luminance(baseline, x: x, y: y)
              - Self.luminance(result, x: rx, y: ry)))
          } else {
            values.append(Double(Self.luminance(result, x: rx, y: ry)))
          }
        }
        if blocked { continue }
        if request.baseline == nil {
          // Both tails must support comparable bright paper. Use a linear
          // background between their medians; uneven/dark support is unknown.
          let tailCount = max(3, min(7, values.count / 5))
          let leftTail = Array(values.prefix(tailCount)).sorted()
          let rightTail = Array(values.suffix(tailCount)).sorted()
          let leftPaper = Self.materialMedian(leftTail), rightPaper = Self.materialMedian(rightTail)
          guard min(leftPaper, rightPaper) >= 100, abs(leftPaper - rightPaper) <= 20,
            leftTail.last! - leftTail.first! <= 35, rightTail.last! - rightTail.first! <= 35 else {
            exclusions["local-paper-support-unavailable", default: 0] += 1; continue
          }
          values = values.enumerated().map { index, luminance in
            leftPaper + (rightPaper - leftPaper) * Double(index) / Double(values.count - 1) - luminance
          }
        }
        let threshold = Double(request.thresholds.minimumLuminanceDecrease)
        let bands = Self.materialBands(values, threshold: threshold)
        guard bands.count == 1, let band = bands.first else {
          exclusions[bands.isEmpty ? "no-ink" : "multiple-bands-or-overlap", default: 0] += 1; continue
        }
        guard band.lowerBound > 0, band.upperBound < values.count - 1 else {
          exclusions["unresolved-outer-edge", default: 0] += 1; continue
        }
        let peak = values[band].max() ?? 0
        guard peak >= threshold * 2 else { exclusions["low-contrast", default: 0] += 1; continue }
        let highBand = Self.materialBands(values, threshold: peak * 0.8)
        let lowBand = Self.materialBands(values, threshold: max(threshold * 0.5, peak * 0.2))
        guard highBand.count == 1, lowBand.count == 1 else {
          exclusions["blur-or-multiple-bands", default: 0] += 1; continue
        }
        let blur = Double(lowBand[0].count - highBand[0].count)
        guard blur <= 4 else { exclusions["blur", default: 0] += 1; continue }
        let left = Double(band.lowerBound - scanRadius) - 0.5
        let right = Double(band.upperBound - scanRadius) + 0.5
        guard right - left >= 3 else { exclusions["insufficient-resolution", default: 0] += 1; continue }
        // Edges are in the result-frame coordinates. Undo the retained alignment
        // before applying the registration, which belongs to the baseline frame.
        let first = try Point2<CameraPixelSpace>(x: cx + cameraNX * left + Double(shiftX),
          y: cy + cameraNY * left + Double(shiftY))
        let second = try Point2<CameraPixelSpace>(x: cx + cameraNX * right + Double(shiftX),
          y: cy + cameraNY * right + Double(shiftY))
        let firstMachine = try inverse.applying(to: Point2<CameraPixelSpace>(
          x: first.x - Double(shiftX), y: first.y - Double(shiftY)))
        let secondMachine = try inverse.applying(to: Point2<CameraPixelSpace>(
          x: second.x - Double(shiftX), y: second.y - Double(shiftY)))
        let extrapolation = max(DrawingMaterialMeasurement.edgeExtrapolation(firstMachine, domain: request.registration.applicabilityRectangle),
          DrawingMaterialMeasurement.edgeExtrapolation(secondMachine, domain: request.registration.applicabilityRectangle))
        guard extrapolation <= policy.maximumEdgeExtrapolationMM else {
          exclusions["edge-extrapolation-limit", default: 0] += 1; continue
        }
        let width = abs((secondMachine.x - firstMachine.x) * segment.nx
          + (secondMachine.y - firstMachine.y) * segment.ny)
        guard width > 0, width <= request.maximumWidthMM else {
          exclusions["width-bound-exceeded", default: 0] += 1; continue
        }
        let midpointCrossTrack = abs(((firstMachine.x + secondMachine.x) * 0.5 - mx) * segment.nx
          + ((firstMachine.y + secondMachine.y) * 0.5 - my) * segment.ny)
        guard midpointCrossTrack <= width * 0.5 + perpendicularPerPixel else {
          exclusions["off-path-band", default: 0] += 1; continue
        }
        let endpointMargin = max(width * 1.5, perpendicularPerPixel * 2)
        guard min(fraction, 1 - fraction) * segment.length > endpointMargin else {
          exclusions["endpoint-or-vertex-pooling", default: 0] += 1; continue
        }
        let crossing = segments.contains { other in
          guard other.pathIndex != segment.pathIndex || other.segmentIndex != segment.segmentIndex else { return false }
          return Self.materialDistance(x: mx, y: my, to: other) < width + perpendicularPerPixel * 2
        }
        guard !crossing else { exclusions["crossing-or-overlap", default: 0] += 1; continue }
        let uncertainty = (3 + blur) * hypot(qx, qy)
          + Self.materialRegistrationUncertainty(at: firstMachine, qx: qx, qy: qy, registration: request.registration)
          + Self.materialRegistrationUncertainty(at: secondMachine, qx: qx, qy: qy, registration: request.registration)
        var direction = atan2(segment.b.y - segment.a.y, segment.b.x - segment.a.x)
        if direction < 0 { direction += .pi }
        if direction >= .pi { direction -= .pi }
        samples.append(DepositedWidthSample(pathIndex: segment.pathIndex, segmentIndex: segment.segmentIndex,
          pathFraction: fraction, directionRadians: direction, firstEdge: first, secondEdge: second,
          widthMM: width, uncertaintyMM: uncertainty, edgeExtrapolationMM: extrapolation))
      }
    }
    return try report(samples)
  }

  private struct MaterialSegment {
    let pathIndex: Int, segmentIndex: Int
    let a: Point2<MachineSpace>, b: Point2<MachineSpace>
    let cameraA: Point2<CameraPixelSpace>, cameraB: Point2<CameraPixelSpace>
    let length: Double, nx: Double, ny: Double
  }

  private static func materialSegments(_ paths: [Polyline<MachineSpace>],
    transform: AffineTransform2<MachineSpace, CameraPixelSpace>) throws -> [MaterialSegment] {
    var segments: [MaterialSegment] = []
    for (pathIndex, path) in paths.enumerated() {
      for index in 0..<(path.points.count - 1) {
        let a = path.points[index], b = path.points[index + 1]
        let length = a.distance(to: b)
        if length <= 1e-10 { continue }
        segments.append(try MaterialSegment(pathIndex: pathIndex, segmentIndex: index, a: a, b: b,
          cameraA: transform.applying(to: a), cameraB: transform.applying(to: b), length: length,
          nx: -(b.y - a.y) / length, ny: (b.x - a.x) / length))
      }
    }
    return segments
  }

  private static func materialDistance(x: Double, y: Double, to segment: MaterialSegment) -> Double {
    let dx = segment.b.x - segment.a.x, dy = segment.b.y - segment.a.y
    let fraction = min(1, max(0, ((x - segment.a.x) * dx + (y - segment.a.y) * dy)
      / (segment.length * segment.length)))
    return hypot(x - segment.a.x - fraction * dx, y - segment.a.y - fraction * dy)
  }

  private static func materialBands(_ values: [Double], threshold: Double) -> [ClosedRange<Int>] {
    var bands: [ClosedRange<Int>] = []
    var start: Int?
    for index in values.indices {
      if values[index] >= threshold { if start == nil { start = index } }
      else if let lower = start { bands.append(lower...(index - 1)); start = nil }
    }
    if let lower = start { bands.append(lower...(values.count - 1)) }
    return bands
  }

  private static func materialMedian(_ sorted: [Double]) -> Double {
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) * 0.5 : sorted[middle]
  }

  private static func materialRegistrationUncertainty(at point: Point2<MachineSpace>,
    qx: Double, qy: Double, registration: TipCameraRegistration) -> Double {
    // n^T d(B^-1(p-t)) / d[m11,m12,m21,m22,tx,ty].
    // All covariance entries, including cross terms, contribute. Summing the
    // two endpoint uncertainties conservatively avoids claiming cancellation.
    let gradient = [-qx * point.x, -qx * point.y, -qy * point.x, -qy * point.y, -qx, -qy]
    let covariance = registration.uncertainty.affineParameterCovariance
    var variance = 0.0
    for row in 0..<6 { for column in 0..<6 {
      variance += gradient[row] * covariance[row * 6 + column] * gradient[column]
    } }
    return 3 * sqrt(max(0, variance))
      + registration.uncertainty.maximumResidualPixels * hypot(qx, qy)
  }
}
