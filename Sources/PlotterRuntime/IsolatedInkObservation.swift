import Foundation
import PlotterModel

public struct ExactFrameProvenance: Codable, Hashable, Sendable {
  public let frameID: FrameID
  public let frameSHA256: String
  public let captureNanoseconds: UInt64
  public let cameraConfigurationID: CameraConfigurationID
  public let width: Int
  public let height: Int
  public let rowBytes: Int
  public let pixelFormat: FramePixelFormat

  public init(frame: StampedFrame) {
    frameID = frame.id
    frameSHA256 = frame.contentSHA256
    captureNanoseconds = frame.captureNanoseconds
    cameraConfigurationID = frame.cameraConfigurationID
    width = frame.width
    height = frame.height
    rowBytes = frame.rowBytes
    pixelFormat = frame.pixelFormat
  }
}
public struct IsolatedInkObservationRequest: Hashable, Sendable {
  public let localPreLineBaseline: SamePoseFrameSample
  public let postLine: SamePoseFrameSample
  public let region: PixelRect
  public let thresholds: InkPixelThresholds
  public let lineStartPoint: Point2<CameraPixelSpace>
  public let tipRegistrationRevisionID: LearningArtifactRevisionID
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let toolPaperRevision: UUID
  public let controllerPositionToleranceMM: Double
  public let alignmentSearchRadiusPixels: Int
  public let maximumAlignmentShiftPixels: Int
  public let maximumBackgroundMeanAbsoluteDifference: Double
  public let projectedActualStrokeDelta: Vector2<CameraPixelSpace>?
  public let algorithmRevision: String
  public let minimumLinePixels: Int
  public let maximumLineMinorToMajorVarianceRatio: Double

  public init(
    localPreLineBaseline: SamePoseFrameSample,
    postLine: SamePoseFrameSample,
    region: PixelRect,
    thresholds: InkPixelThresholds,
    lineStartPoint: Point2<CameraPixelSpace>,
    tipRegistrationRevisionID: LearningArtifactRevisionID,
    controllerSessionID: UUID,
    coordinateRevision: UInt64,
    toolPaperRevision: UUID,
    controllerPositionToleranceMM: Double,
    alignmentSearchRadiusPixels: Int,
    maximumAlignmentShiftPixels: Int,
    maximumBackgroundMeanAbsoluteDifference: Double,
    projectedActualStrokeDelta: Vector2<CameraPixelSpace>?,
    algorithmRevision: String,
    minimumLinePixels: Int = 5,
    maximumLineMinorToMajorVarianceRatio: Double = 0.25
  ) {
    self.localPreLineBaseline = localPreLineBaseline
    self.postLine = postLine
    self.region = region
    self.thresholds = thresholds
    self.lineStartPoint = lineStartPoint
    self.tipRegistrationRevisionID = tipRegistrationRevisionID
    self.controllerSessionID = controllerSessionID
    self.coordinateRevision = coordinateRevision
    self.toolPaperRevision = toolPaperRevision
    self.controllerPositionToleranceMM = controllerPositionToleranceMM
    self.alignmentSearchRadiusPixels = alignmentSearchRadiusPixels
    self.maximumAlignmentShiftPixels = maximumAlignmentShiftPixels
    self.maximumBackgroundMeanAbsoluteDifference = maximumBackgroundMeanAbsoluteDifference
    self.projectedActualStrokeDelta = projectedActualStrokeDelta
    self.algorithmRevision = algorithmRevision
    self.minimumLinePixels = minimumLinePixels
    self.maximumLineMinorToMajorVarianceRatio = maximumLineMinorToMajorVarianceRatio
  }
}

public enum IsolatedInkRejectionReason: Codable, Hashable, Sendable {
  case invalidPolicy
  case invalidRegion
  case framesNotStrictlyIncreasing
  case cameraConfigurationMismatch
  case sourceMismatch
  case observationPoseMismatch(distanceMM: Double, toleranceMM: Double)
  case excessiveAlignment(shiftX: Int, shiftY: Int, maximumPixels: Int)
  case excessiveBackgroundResidual(actual: Double, maximum: Double)
  case dimensionMismatch
  case pixelFormatMismatch
  case lineMissing
  case lineTooSmall(actualPixels: Int, minimumPixels: Int)
  case lineAmbiguous(candidateCount: Int)
  case lineNotLineLike(minorToMajorVarianceRatio: Double)
}

public struct IsolatedInkRejection: Codable, Hashable, Sendable {
  public let reason: IsolatedInkRejectionReason
  public let localPreLineBaseline: ExactFrameProvenance
  public let postLine: ExactFrameProvenance
}

public struct IsolatedInkResidual: Codable, Hashable, Sendable {
  public let rootMeanSquareEndpointPixels: Double
  public let maximumEndpointPixels: Double
  public let rootMeanSquareCrossTrackPixels: Double
}

public struct IsolatedInkObservation: Codable, Hashable, Sendable {
  public let localPreLineBaseline: ExactFrameProvenance
  public let postLine: ExactFrameProvenance
  public let region: PixelRect
  public let lineStartPoint: Point2<CameraPixelSpace>
  public let tipRegistrationRevisionID: LearningArtifactRevisionID
  public let source: FrameSourceIdentity
  public let controllerSessionID: UUID
  public let coordinateRevision: UInt64
  public let toolPaperRevision: UUID
  public let alignment: IntegerFrameAlignment
  public let observedEndpoints: [Point2<CameraPixelSpace>]
  public let observedCentreline: Polyline<CameraPixelSpace>
  public let observedPixelCount: Int
  public let displacementPixels: Vector2<CameraPixelSpace>
  public let orientationRadians: Double
  public let intendedLine: Polyline<CameraPixelSpace>?
  public let residual: IsolatedInkResidual?
  public let overlays: [CameraOverlayMeasurement]
  public let algorithmRevision: String
}

public enum IsolatedInkObservationOutcome: Codable, Hashable, Sendable {
  case observed(IsolatedInkObservation)
  case rejected(IsolatedInkRejection)
}

public struct SamePoseFrameSample: Hashable, Sendable {
  public let source: FrameSourceIdentity
  public let frame: StampedFrame
  public let controllerPosition: MachinePosition

  public init(displayedFrame: DisplayedFrame, controllerPosition: MachinePosition) {
    source = displayedFrame.source
    frame = displayedFrame.frame
    self.controllerPosition = controllerPosition
  }

  public init(
    source: FrameSourceIdentity,
    frame: StampedFrame,
    controllerPosition: MachinePosition
  ) {
    self.source = source
    self.frame = frame
    self.controllerPosition = controllerPosition
  }
}

public struct IntegerFrameAlignment: Codable, Hashable, Sendable {
  public let shiftX: Int
  public let shiftY: Int
  public let backgroundMeanAbsoluteDifference: Double
  public let estimatorRevision: String
  public let supportRegion: PixelRect
  public let exclusionRegion: PixelRect
  public let evaluatedPixelCount: Int
}

extension VisionWorker {
  public func observeIsolatedInk(
    _ request: IsolatedInkObservationRequest
  ) -> IsolatedInkObservationOutcome {
    let provenance = (
      baseline: ExactFrameProvenance(frame: request.localPreLineBaseline.frame),
      post: ExactFrameProvenance(frame: request.postLine.frame)
    )
    func reject(_ reason: IsolatedInkRejectionReason) -> IsolatedInkObservationOutcome {
      .rejected(IsolatedInkRejection(
        reason: reason,
        localPreLineBaseline: provenance.baseline,
        postLine: provenance.post
      ))
    }

    guard request.minimumLinePixels >= 2,
      request.maximumLineMinorToMajorVarianceRatio.isFinite,
      request.maximumLineMinorToMajorVarianceRatio >= 0,
      request.maximumLineMinorToMajorVarianceRatio < 1,
      request.controllerPositionToleranceMM.isFinite,
      request.controllerPositionToleranceMM >= 0,
      request.alignmentSearchRadiusPixels >= 0,
      request.maximumAlignmentShiftPixels >= 0,
      request.maximumAlignmentShiftPixels <= request.alignmentSearchRadiusPixels,
      request.maximumBackgroundMeanAbsoluteDifference.isFinite,
      request.maximumBackgroundMeanAbsoluteDifference >= 0,
      !request.algorithmRevision.isEmpty
    else { return reject(.invalidPolicy) }
    guard request.localPreLineBaseline.source == request.postLine.source else {
      return reject(.sourceMismatch)
    }
    let frames = [request.localPreLineBaseline.frame, request.postLine.frame]
    guard Set(frames.map(\.cameraConfigurationID)).count == 1 else {
      return reject(.cameraConfigurationMismatch)
    }
    guard Set(frames.map { "\($0.width)x\($0.height)" }).count == 1 else {
      return reject(.dimensionMismatch)
    }
    guard Set(frames.map(\.pixelFormat)).count == 1 else {
      return reject(.pixelFormatMismatch)
    }
    guard request.localPreLineBaseline.frame.captureNanoseconds
      < request.postLine.frame.captureNanoseconds,
      Set(frames.map(\.id)).count == 2
    else { return reject(.framesNotStrictlyIncreasing) }
    guard Self.contains(request.region, in: request.localPreLineBaseline.frame) else {
      return reject(.invalidRegion)
    }
    let poseDistance = request.localPreLineBaseline.controllerPosition.point.distance(
      to: request.postLine.controllerPosition.point
    )
    guard poseDistance <= request.controllerPositionToleranceMM else {
      return reject(.observationPoseMismatch(
        distanceMM: poseDistance,
        toleranceMM: request.controllerPositionToleranceMM
      ))
    }
    let alignment = Self.bestIntegerAlignment(
      request.localPreLineBaseline.frame,
      request.postLine.frame,
      excluding: request.region,
      searchRadius: request.alignmentSearchRadiusPixels
    )
    guard max(abs(alignment.shiftX), abs(alignment.shiftY))
      <= request.maximumAlignmentShiftPixels
    else {
      return reject(.excessiveAlignment(
        shiftX: alignment.shiftX,
        shiftY: alignment.shiftY,
        maximumPixels: request.maximumAlignmentShiftPixels
      ))
    }
    guard alignment.backgroundMeanAbsoluteDifference
      <= request.maximumBackgroundMeanAbsoluteDifference
    else {
      return reject(.excessiveBackgroundResidual(
        actual: alignment.backgroundMeanAbsoluteDifference,
        maximum: request.maximumBackgroundMeanAbsoluteDifference
      ))
    }

    let linePixels = Self.newInkPixels(
      from: request.localPreLineBaseline.frame,
      to: request.postLine.frame,
      region: request.region,
      thresholds: request.thresholds,
      observationShiftX: alignment.shiftX,
      observationShiftY: alignment.shiftY
    )
    guard !linePixels.isEmpty else { return reject(.lineMissing) }
    let lineComponents = Self.components(linePixels)
    let eligibleLines = lineComponents.filter { $0.count >= request.minimumLinePixels }
    guard !eligibleLines.isEmpty else {
      return reject(.lineTooSmall(
        actualPixels: lineComponents.map(\.count).max() ?? 0,
        minimumPixels: request.minimumLinePixels
      ))
    }
    guard eligibleLines.count == 1 else {
      return reject(.lineAmbiguous(candidateCount: eligibleLines.count))
    }
    let line = eligibleLines[0]
    guard let fit = Self.fitLine(line),
      fit.minorToMajorVarianceRatio <= request.maximumLineMinorToMajorVarianceRatio
    else {
      let ratio = Self.fitLine(line)?.minorToMajorVarianceRatio ?? .infinity
      return reject(.lineNotLineLike(minorToMajorVarianceRatio: ratio))
    }

    var observedEndpoints = [fit.start, fit.end]
    var intended: Polyline<CameraPixelSpace>?
    var residual: IsolatedInkResidual?
    if let delta = request.projectedActualStrokeDelta,
      delta.dx.isFinite, delta.dy.isFinite, delta.magnitude > 0,
      let intendedEnd = try? request.lineStartPoint.translated(by: delta),
      let intendedLine = try? Polyline(points: [request.lineStartPoint, intendedEnd])
    {
      intended = intendedLine
      let direct = fit.start.distance(to: request.lineStartPoint) + fit.end.distance(to: intendedEnd)
      let reversed = fit.end.distance(to: request.lineStartPoint) + fit.start.distance(to: intendedEnd)
      if reversed < direct { observedEndpoints.reverse() }
      let endpointErrors = [
        observedEndpoints[0].distance(to: request.lineStartPoint),
        observedEndpoints[1].distance(to: intendedEnd),
      ]
      let crossTrackSquared = line.map {
        let point = try! Point2<CameraPixelSpace>(x: Double($0.x), y: Double($0.y))
        let distance = Self.infiniteLineDistance(
          point,
          start: request.lineStartPoint,
          end: intendedEnd
        )
        return distance * distance
      }
      residual = IsolatedInkResidual(
        rootMeanSquareEndpointPixels: sqrt(endpointErrors.reduce(0) { $0 + $1 * $1 } / 2),
        maximumEndpointPixels: endpointErrors.max() ?? 0,
        rootMeanSquareCrossTrackPixels: sqrt(
          crossTrackSquared.reduce(0, +) / Double(crossTrackSquared.count)
        )
      )
    } else if Self.pointOrder(observedEndpoints[1], before: observedEndpoints[0]) {
      observedEndpoints.reverse()
    }

    guard let centreline = try? Polyline(points: observedEndpoints),
      let displacement = try? observedEndpoints[0].vector(to: observedEndpoints[1])
    else { return reject(.lineNotLineLike(minorToMajorVarianceRatio: .infinity)) }
    var overlays: [CameraOverlayMeasurement] = [
      CameraOverlayMeasurement(
        frameID: request.postLine.frame.id,
        cameraConfigurationID: request.postLine.frame.cameraConfigurationID,
        geometry: .polyline(centreline),
        provenance: CameraMeasurementProvenance(
          kind: .observedInk,
          source: .measured,
          algorithmRevision: request.algorithmRevision
        )
      )
    ]
    if let intended {
      overlays.append(CameraOverlayMeasurement(
        frameID: request.postLine.frame.id,
        cameraConfigurationID: request.postLine.frame.cameraConfigurationID,
        geometry: .polyline(intended),
        provenance: CameraMeasurementProvenance(
          kind: .intendedPath,
          source: .planned,
          algorithmRevision: request.algorithmRevision
        )
      ))
      for pair in zip(intended.points, observedEndpoints) {
        if pair.0 != pair.1, let geometry = try? Polyline(points: [pair.0, pair.1]) {
          overlays.append(CameraOverlayMeasurement(
            frameID: request.postLine.frame.id,
            cameraConfigurationID: request.postLine.frame.cameraConfigurationID,
            geometry: .polyline(geometry),
            provenance: CameraMeasurementProvenance(
              kind: .residual,
              source: .diagnostic,
              algorithmRevision: request.algorithmRevision
            )
          ))
        }
      }
    }
    return .observed(IsolatedInkObservation(
      localPreLineBaseline: provenance.baseline,
      postLine: provenance.post,
      region: request.region,
      lineStartPoint: request.lineStartPoint,
      tipRegistrationRevisionID: request.tipRegistrationRevisionID,
      source: request.localPreLineBaseline.source,
      controllerSessionID: request.controllerSessionID,
      coordinateRevision: request.coordinateRevision,
      toolPaperRevision: request.toolPaperRevision,
      alignment: alignment,
      observedEndpoints: observedEndpoints,
      observedCentreline: centreline,
      observedPixelCount: line.count,
      displacementPixels: displacement,
      orientationRadians: atan2(displacement.dy, displacement.dx),
      intendedLine: intended,
      residual: residual,
      overlays: overlays,
      algorithmRevision: request.algorithmRevision
    ))
  }
}

private extension VisionWorker {
  struct InkPixel: Hashable {
    let x: Int
    let y: Int
  }

  struct InkLineFit {
    let start: Point2<CameraPixelSpace>
    let end: Point2<CameraPixelSpace>
    let minorToMajorVarianceRatio: Double
  }

  struct BackgroundResidual {
    let meanAbsoluteDifference: Double
    let pixelCount: Int
  }

  static func contains(_ region: PixelRect, in frame: StampedFrame) -> Bool {
    region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
      && region.x + region.width <= frame.width
      && region.y + region.height <= frame.height
  }

  static func newInkPixels(
    from reference: StampedFrame,
    to observation: StampedFrame,
    region: PixelRect,
    thresholds: InkPixelThresholds,
    observationShiftX: Int = 0,
    observationShiftY: Int = 0
  ) -> Set<InkPixel> {
    var result: Set<InkPixel> = []
    for y in region.y..<(region.y + region.height) {
      for x in region.x..<(region.x + region.width) {
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        if isNewInk(
          reference: reference,
          referenceX: x,
          referenceY: y,
          observation: observation,
          observationX: observedX,
          observationY: observedY,
          thresholds: thresholds
        ) {
          result.insert(InkPixel(x: x, y: y))
        }
      }
    }
    return result
  }

  static func bestIntegerAlignment(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    searchRadius: Int
  ) -> IntegerFrameAlignment {
    var best: (shiftX: Int, shiftY: Int, residual: Double)?
    var evaluatedPixelCount = 0
    for shiftY in (-searchRadius)...searchRadius {
      for shiftX in (-searchRadius)...searchRadius {
        let residual = backgroundMeanAbsoluteDifference(
          baseline,
          observation,
          excluding: region,
          observationShiftX: shiftX,
          observationShiftY: shiftY
        )
        evaluatedPixelCount += residual.pixelCount
        let candidate = (
          shiftX: shiftX,
          shiftY: shiftY,
          residual: residual.meanAbsoluteDifference
        )
        if let current = best {
          let candidateRank = (
            candidate.residual,
            max(abs(candidate.shiftX), abs(candidate.shiftY)),
            abs(candidate.shiftX) + abs(candidate.shiftY),
            candidate.shiftY,
            candidate.shiftX
          )
          let currentRank = (
            current.residual,
            max(abs(current.shiftX), abs(current.shiftY)),
            abs(current.shiftX) + abs(current.shiftY),
            current.shiftY,
            current.shiftX
          )
          if candidateRank < currentRank { best = candidate }
        } else {
          best = candidate
        }
      }
    }
    let selected = best ?? (0, 0, 0)
    return IntegerFrameAlignment(
      shiftX: selected.shiftX,
      shiftY: selected.shiftY,
      backgroundMeanAbsoluteDifference: selected.residual,
      estimatorRevision: "bounded-integer-background-mad-v1",
      supportRegion: PixelRect(x: 0, y: 0, width: baseline.width, height: baseline.height),
      exclusionRegion: region,
      evaluatedPixelCount: evaluatedPixelCount
    )
  }

  static func backgroundMeanAbsoluteDifference(
    _ baseline: StampedFrame,
    _ observation: StampedFrame,
    excluding region: PixelRect,
    observationShiftX: Int,
    observationShiftY: Int
  ) -> BackgroundResidual {
    var absoluteDifference = 0.0
    var pixelCount = 0
    for y in 0..<baseline.height {
      for x in 0..<baseline.width {
        let inRegion = x >= region.x && x < region.x + region.width
          && y >= region.y && y < region.y + region.height
        guard !inRegion else { continue }
        let observedX = x + observationShiftX
        let observedY = y + observationShiftY
        guard observedX >= 0, observedX < observation.width,
          observedY >= 0, observedY < observation.height
        else { continue }
        let baseOffset = y * baseline.rowBytes + x * baseline.pixelFormat.bytesPerPixel
        let observedOffset = observedY * observation.rowBytes
          + observedX * observation.pixelFormat.bytesPerPixel
        for component in 0..<baseline.pixelFormat.bytesPerPixel {
          absoluteDifference += abs(
            Double(baseline.bytes[baseOffset + component])
              - Double(observation.bytes[observedOffset + component])
          )
        }
        pixelCount += 1
      }
    }
    let byteCount = pixelCount * baseline.pixelFormat.bytesPerPixel
    return BackgroundResidual(
      meanAbsoluteDifference: byteCount == 0 ? 0 : absoluteDifference / Double(byteCount),
      pixelCount: pixelCount
    )
  }

  static func isNewInk(
    reference: StampedFrame,
    referenceX: Int,
    referenceY: Int,
    observation: StampedFrame,
    observationX: Int,
    observationY: Int,
    thresholds: InkPixelThresholds
  ) -> Bool {
    let referenceLuminance = luminance(reference, x: referenceX, y: referenceY)
    let observationLuminance = luminance(
      observation,
      x: observationX,
      y: observationY
    )
    return referenceLuminance - observationLuminance
      >= Int(thresholds.minimumLuminanceDecrease)
  }

  static func luminance(_ frame: StampedFrame, x: Int, y: Int) -> Int {
    let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    let red: Int
    let green: Int
    let blue: Int
    switch frame.pixelFormat {
    case .gray8:
      return Int(frame.bytes[offset])
    case .rgba8:
      red = Int(frame.bytes[offset])
      green = Int(frame.bytes[offset + 1])
      blue = Int(frame.bytes[offset + 2])
    case .bgra8:
      blue = Int(frame.bytes[offset])
      green = Int(frame.bytes[offset + 1])
      red = Int(frame.bytes[offset + 2])
    }
    return (54 * red + 183 * green + 19 * blue) / 256
  }

  static func components(_ pixels: Set<InkPixel>) -> [[InkPixel]] {
    var remaining = pixels
    var result: [[InkPixel]] = []
    while let seed = remaining.first {
      remaining.remove(seed)
      var queue = [seed]
      var component: [InkPixel] = []
      while let current = queue.popLast() {
        component.append(current)
        for y in (current.y - 1)...(current.y + 1) {
          for x in (current.x - 1)...(current.x + 1) where x != current.x || y != current.y {
            let neighbor = InkPixel(x: x, y: y)
            if remaining.remove(neighbor) != nil { queue.append(neighbor) }
          }
        }
      }
      result.append(component)
    }
    return result.sorted {
      if $0.count != $1.count { return $0.count > $1.count }
      let l = centroid($0)
      let r = centroid($1)
      return pointOrder(l, before: r)
    }
  }

  static func centroid(_ pixels: [InkPixel]) -> Point2<CameraPixelSpace> {
    let x = pixels.reduce(0.0) { $0 + Double($1.x) } / Double(pixels.count)
    let y = pixels.reduce(0.0) { $0 + Double($1.y) } / Double(pixels.count)
    return try! Point2(x: x, y: y)
  }

  static func fitLine(_ pixels: [InkPixel]) -> InkLineFit? {
    guard pixels.count >= 2 else { return nil }
    let centre = centroid(pixels)
    let xx = pixels.reduce(0.0) { $0 + pow(Double($1.x) - centre.x, 2) } / Double(pixels.count)
    let yy = pixels.reduce(0.0) { $0 + pow(Double($1.y) - centre.y, 2) } / Double(pixels.count)
    let xy = pixels.reduce(0.0) {
      $0 + (Double($1.x) - centre.x) * (Double($1.y) - centre.y)
    } / Double(pixels.count)
    let trace = xx + yy
    let discriminant = sqrt(max(0, (xx - yy) * (xx - yy) + 4 * xy * xy))
    let major = (trace + discriminant) / 2
    let minor = max(0, (trace - discriminant) / 2)
    guard major > 0 else { return nil }
    let angle = 0.5 * atan2(2 * xy, xx - yy)
    let axisX = cos(angle)
    let axisY = sin(angle)
    let projections = pixels.map {
      (Double($0.x) - centre.x) * axisX + (Double($0.y) - centre.y) * axisY
    }
    guard let minimum = projections.min(), let maximum = projections.max(), maximum - minimum >= 1 else {
      return nil
    }
    return InkLineFit(
      start: try! Point2(x: centre.x + minimum * axisX, y: centre.y + minimum * axisY),
      end: try! Point2(x: centre.x + maximum * axisX, y: centre.y + maximum * axisY),
      minorToMajorVarianceRatio: minor / major
    )
  }

  static func infiniteLineDistance(
    _ point: Point2<CameraPixelSpace>,
    start: Point2<CameraPixelSpace>,
    end: Point2<CameraPixelSpace>
  ) -> Double {
    let dx = end.x - start.x
    let dy = end.y - start.y
    return abs(dy * point.x - dx * point.y + end.x * start.y - end.y * start.x)
      / hypot(dx, dy)
  }

  static func pointOrder(
    _ lhs: Point2<CameraPixelSpace>,
    before rhs: Point2<CameraPixelSpace>
  ) -> Bool {
    lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
  }
}
