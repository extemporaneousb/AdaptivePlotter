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
  public let cleanReference: StampedFrame
  public let anchoredBaseline: StampedFrame
  public let postLine: StampedFrame
  public let region: PixelRect
  public let thresholds: GreenPixelThresholds
  public let projectedActualStrokeDelta: Vector2<CameraPixelSpace>?
  public let algorithmRevision: String
  public let minimumAnchorPixels: Int
  public let minimumLinePixels: Int
  public let maximumLineMinorToMajorVarianceRatio: Double

  public init(
    cleanReference: StampedFrame,
    anchoredBaseline: StampedFrame,
    postLine: StampedFrame,
    region: PixelRect,
    thresholds: GreenPixelThresholds,
    projectedActualStrokeDelta: Vector2<CameraPixelSpace>?,
    algorithmRevision: String,
    minimumAnchorPixels: Int = 3,
    minimumLinePixels: Int = 5,
    maximumLineMinorToMajorVarianceRatio: Double = 0.25
  ) {
    self.cleanReference = cleanReference
    self.anchoredBaseline = anchoredBaseline
    self.postLine = postLine
    self.region = region
    self.thresholds = thresholds
    self.projectedActualStrokeDelta = projectedActualStrokeDelta
    self.algorithmRevision = algorithmRevision
    self.minimumAnchorPixels = minimumAnchorPixels
    self.minimumLinePixels = minimumLinePixels
    self.maximumLineMinorToMajorVarianceRatio = maximumLineMinorToMajorVarianceRatio
  }
}

public struct AnchorDotObservationRequest: Hashable, Sendable {
  public let cleanReference: StampedFrame
  public let anchoredBaseline: StampedFrame
  public let region: PixelRect
  public let thresholds: GreenPixelThresholds
  public let algorithmRevision: String
  public let minimumAnchorPixels: Int

  public init(
    cleanReference: StampedFrame,
    anchoredBaseline: StampedFrame,
    region: PixelRect,
    thresholds: GreenPixelThresholds,
    algorithmRevision: String,
    minimumAnchorPixels: Int = 3
  ) {
    self.cleanReference = cleanReference
    self.anchoredBaseline = anchoredBaseline
    self.region = region
    self.thresholds = thresholds
    self.algorithmRevision = algorithmRevision
    self.minimumAnchorPixels = minimumAnchorPixels
  }
}

public enum AnchorDotRejectionReason: Codable, Hashable, Sendable {
  case invalidPolicy
  case invalidRegion
  case framesNotStrictlyIncreasing
  case cameraConfigurationMismatch
  case dimensionMismatch
  case pixelFormatMismatch
  case missing
  case tooSmall(actualPixels: Int, minimumPixels: Int)
  case ambiguous(candidateCount: Int)
}

public struct AnchorDotObservation: Codable, Hashable, Sendable {
  public let cleanReference: ExactFrameProvenance
  public let anchoredBaseline: ExactFrameProvenance
  public let region: PixelRect
  public let centroid: Point2<CameraPixelSpace>
  public let pixelCount: Int
  public let overlay: CameraOverlayMeasurement
  public let algorithmRevision: String
}

public struct AnchorDotRejection: Codable, Hashable, Sendable {
  public let reason: AnchorDotRejectionReason
  public let cleanReference: ExactFrameProvenance
  public let anchoredBaseline: ExactFrameProvenance
}

public enum AnchorDotObservationOutcome: Codable, Hashable, Sendable {
  case observed(AnchorDotObservation)
  case rejected(AnchorDotRejection)
}

public enum IsolatedInkRejectionReason: Codable, Hashable, Sendable {
  case invalidPolicy
  case invalidRegion
  case framesNotStrictlyIncreasing
  case cameraConfigurationMismatch
  case dimensionMismatch
  case pixelFormatMismatch
  case anchorMissing
  case anchorTooSmall(actualPixels: Int, minimumPixels: Int)
  case anchorAmbiguous(candidateCount: Int)
  case lineMissing
  case lineTooSmall(actualPixels: Int, minimumPixels: Int)
  case lineAmbiguous(candidateCount: Int)
  case lineNotLineLike(minorToMajorVarianceRatio: Double)
}

public struct IsolatedInkRejection: Codable, Hashable, Sendable {
  public let reason: IsolatedInkRejectionReason
  public let cleanReference: ExactFrameProvenance
  public let anchoredBaseline: ExactFrameProvenance
  public let postLine: ExactFrameProvenance
}

public struct IsolatedInkResidual: Codable, Hashable, Sendable {
  public let rootMeanSquareEndpointPixels: Double
  public let maximumEndpointPixels: Double
  public let rootMeanSquareCrossTrackPixels: Double
}

public struct IsolatedInkObservation: Codable, Hashable, Sendable {
  public let cleanReference: ExactFrameProvenance
  public let anchoredBaseline: ExactFrameProvenance
  public let postLine: ExactFrameProvenance
  public let region: PixelRect
  public let anchorCentroid: Point2<CameraPixelSpace>
  public let anchorPixelCount: Int
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

extension VisionWorker {
  public func observeAnchorDot(
    _ request: AnchorDotObservationRequest
  ) -> AnchorDotObservationOutcome {
    let clean = ExactFrameProvenance(frame: request.cleanReference)
    let anchored = ExactFrameProvenance(frame: request.anchoredBaseline)
    func reject(_ reason: AnchorDotRejectionReason) -> AnchorDotObservationOutcome {
      .rejected(AnchorDotRejection(
        reason: reason,
        cleanReference: clean,
        anchoredBaseline: anchored
      ))
    }
    guard request.minimumAnchorPixels > 0, !request.algorithmRevision.isEmpty else {
      return reject(.invalidPolicy)
    }
    guard request.cleanReference.cameraConfigurationID
      == request.anchoredBaseline.cameraConfigurationID
    else { return reject(.cameraConfigurationMismatch) }
    guard request.cleanReference.width == request.anchoredBaseline.width,
      request.cleanReference.height == request.anchoredBaseline.height
    else { return reject(.dimensionMismatch) }
    guard request.cleanReference.pixelFormat == request.anchoredBaseline.pixelFormat else {
      return reject(.pixelFormatMismatch)
    }
    guard request.cleanReference.captureNanoseconds
      < request.anchoredBaseline.captureNanoseconds,
      request.cleanReference.id != request.anchoredBaseline.id
    else { return reject(.framesNotStrictlyIncreasing) }
    guard Self.contains(request.region, in: request.cleanReference) else {
      return reject(.invalidRegion)
    }
    let pixels = Self.newGreenPixels(
      from: request.cleanReference,
      to: request.anchoredBaseline,
      region: request.region,
      thresholds: request.thresholds
    )
    guard !pixels.isEmpty else { return reject(.missing) }
    let components = Self.components(pixels)
    let eligible = components.filter { $0.count >= request.minimumAnchorPixels }
    guard !eligible.isEmpty else {
      return reject(.tooSmall(
        actualPixels: components.map(\.count).max() ?? 0,
        minimumPixels: request.minimumAnchorPixels
      ))
    }
    guard eligible.count == 1 else {
      return reject(.ambiguous(candidateCount: eligible.count))
    }
    let component = eligible[0]
    let centroid = Self.centroid(component)
    return .observed(AnchorDotObservation(
      cleanReference: clean,
      anchoredBaseline: anchored,
      region: request.region,
      centroid: centroid,
      pixelCount: component.count,
      overlay: CameraOverlayMeasurement(
        frameID: request.anchoredBaseline.id,
        cameraConfigurationID: request.anchoredBaseline.cameraConfigurationID,
        geometry: .point(centroid),
        provenance: CameraMeasurementProvenance(
          kind: .observedInk,
          source: .measured,
          algorithmRevision: request.algorithmRevision
        )
      ),
      algorithmRevision: request.algorithmRevision
    ))
  }

  public func observeIsolatedInk(
    _ request: IsolatedInkObservationRequest
  ) -> IsolatedInkObservationOutcome {
    let provenance = (
      clean: ExactFrameProvenance(frame: request.cleanReference),
      anchored: ExactFrameProvenance(frame: request.anchoredBaseline),
      post: ExactFrameProvenance(frame: request.postLine)
    )
    func reject(_ reason: IsolatedInkRejectionReason) -> IsolatedInkObservationOutcome {
      .rejected(IsolatedInkRejection(
        reason: reason,
        cleanReference: provenance.clean,
        anchoredBaseline: provenance.anchored,
        postLine: provenance.post
      ))
    }

    guard request.minimumAnchorPixels > 0, request.minimumLinePixels >= 2,
      request.maximumLineMinorToMajorVarianceRatio.isFinite,
      request.maximumLineMinorToMajorVarianceRatio >= 0,
      request.maximumLineMinorToMajorVarianceRatio < 1,
      !request.algorithmRevision.isEmpty
    else { return reject(.invalidPolicy) }
    let frames = [request.cleanReference, request.anchoredBaseline, request.postLine]
    guard Set(frames.map(\.cameraConfigurationID)).count == 1 else {
      return reject(.cameraConfigurationMismatch)
    }
    guard Set(frames.map { "\($0.width)x\($0.height)" }).count == 1 else {
      return reject(.dimensionMismatch)
    }
    guard Set(frames.map(\.pixelFormat)).count == 1 else {
      return reject(.pixelFormatMismatch)
    }
    guard request.cleanReference.captureNanoseconds < request.anchoredBaseline.captureNanoseconds,
      request.anchoredBaseline.captureNanoseconds < request.postLine.captureNanoseconds,
      Set(frames.map(\.id)).count == 3
    else { return reject(.framesNotStrictlyIncreasing) }
    guard Self.contains(request.region, in: request.cleanReference) else {
      return reject(.invalidRegion)
    }

    let anchorOutcome = observeAnchorDot(AnchorDotObservationRequest(
      cleanReference: request.cleanReference,
      anchoredBaseline: request.anchoredBaseline,
      region: request.region,
      thresholds: request.thresholds,
      algorithmRevision: request.algorithmRevision,
      minimumAnchorPixels: request.minimumAnchorPixels
    ))
    let anchorObservation: AnchorDotObservation
    switch anchorOutcome {
    case .observed(let observation):
      anchorObservation = observation
    case .rejected(let rejection):
      return reject(Self.isolatedReason(for: rejection.reason))
    }
    let anchorCentroid = anchorObservation.centroid

    let linePixels = Self.newGreenPixels(
      from: request.anchoredBaseline,
      to: request.postLine,
      region: request.region,
      thresholds: request.thresholds
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
      let intendedEnd = try? anchorCentroid.translated(by: delta),
      let intendedLine = try? Polyline(points: [anchorCentroid, intendedEnd])
    {
      intended = intendedLine
      let direct = fit.start.distance(to: anchorCentroid) + fit.end.distance(to: intendedEnd)
      let reversed = fit.end.distance(to: anchorCentroid) + fit.start.distance(to: intendedEnd)
      if reversed < direct { observedEndpoints.reverse() }
      let endpointErrors = [
        observedEndpoints[0].distance(to: anchorCentroid),
        observedEndpoints[1].distance(to: intendedEnd),
      ]
      let crossTrackSquared = line.map {
        let point = try! Point2<CameraPixelSpace>(x: Double($0.x), y: Double($0.y))
        let distance = Self.infiniteLineDistance(point, start: anchorCentroid, end: intendedEnd)
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
        frameID: request.postLine.id,
        cameraConfigurationID: request.postLine.cameraConfigurationID,
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
        frameID: request.postLine.id,
        cameraConfigurationID: request.postLine.cameraConfigurationID,
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
            frameID: request.postLine.id,
            cameraConfigurationID: request.postLine.cameraConfigurationID,
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
      cleanReference: provenance.clean,
      anchoredBaseline: provenance.anchored,
      postLine: provenance.post,
      region: request.region,
      anchorCentroid: anchorCentroid,
      anchorPixelCount: anchorObservation.pixelCount,
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

  static func isolatedReason(
    for reason: AnchorDotRejectionReason
  ) -> IsolatedInkRejectionReason {
    switch reason {
    case .invalidPolicy: .invalidPolicy
    case .invalidRegion: .invalidRegion
    case .framesNotStrictlyIncreasing: .framesNotStrictlyIncreasing
    case .cameraConfigurationMismatch: .cameraConfigurationMismatch
    case .dimensionMismatch: .dimensionMismatch
    case .pixelFormatMismatch: .pixelFormatMismatch
    case .missing: .anchorMissing
    case .tooSmall(let actual, let minimum):
      .anchorTooSmall(actualPixels: actual, minimumPixels: minimum)
    case .ambiguous(let count): .anchorAmbiguous(candidateCount: count)
    }
  }

  static func contains(_ region: PixelRect, in frame: StampedFrame) -> Bool {
    region.x >= 0 && region.y >= 0 && region.width > 0 && region.height > 0
      && region.x + region.width <= frame.width
      && region.y + region.height <= frame.height
  }

  static func newGreenPixels(
    from reference: StampedFrame,
    to observation: StampedFrame,
    region: PixelRect,
    thresholds: GreenPixelThresholds
  ) -> Set<InkPixel> {
    var result: Set<InkPixel> = []
    for y in region.y..<(region.y + region.height) {
      for x in region.x..<(region.x + region.width) {
        if isGreen(observation, x: x, y: y, thresholds: thresholds)
          && !isGreen(reference, x: x, y: y, thresholds: thresholds)
        {
          result.insert(InkPixel(x: x, y: y))
        }
      }
    }
    return result
  }

  static func isGreen(
    _ frame: StampedFrame,
    x: Int,
    y: Int,
    thresholds: GreenPixelThresholds
  ) -> Bool {
    let offset = y * frame.rowBytes + x * frame.pixelFormat.bytesPerPixel
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    switch frame.pixelFormat {
    case .gray8:
      red = frame.bytes[offset]
      green = frame.bytes[offset]
      blue = frame.bytes[offset]
    case .rgba8:
      red = frame.bytes[offset]
      green = frame.bytes[offset + 1]
      blue = frame.bytes[offset + 2]
    case .bgra8:
      blue = frame.bytes[offset]
      green = frame.bytes[offset + 1]
      red = frame.bytes[offset + 2]
    }
    return green >= thresholds.minimumGreen
      && Int(green) - Int(max(red, blue)) >= Int(thresholds.minimumGreenExcess)
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
