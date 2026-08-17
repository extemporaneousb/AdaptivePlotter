import Foundation
import PlotterModel

/// A bounded request to compare planned camera-space paths with new ink in one
/// exact same-pose frame pair. The pinned frame pair is evidence identity, not
/// permission to move the machine, redraw a path, or promote a model.
public struct PlannedDrawingObservationRequest: Hashable, Sendable {
  public let frames: DrawingObservationFramePair
  public let localPreDrawingBaseline: SamePoseFrameSample
  public let postDrawing: SamePoseFrameSample
  public let region: PixelRect
  public let intendedCameraPolylines: [Polyline<CameraPixelSpace>]
  public let thresholds: InkPixelThresholds
  public let controllerPositionToleranceMM: Double
  public let alignmentSearchRadiusPixels: Int
  public let maximumAlignmentShiftPixels: Int
  public let maximumBackgroundMeanAbsoluteDifference: Double
  public let minimumInkPixelsPerPolyline: Int
  public let maximumInkPixels: Int
  public let maximumRegionPixelCount: Int
  public let maximumIntendedPointCount: Int
  public let maximumAssociationEvaluationCount: Int
  public let maximumAssociationDistancePixels: Double
  public let associationAmbiguityTolerancePixels: Double
  public let centrelineSampleSpacingPixels: Double
  public let maximumCentrelineSampleCountPerPolyline: Int
  public let observerRevision: AlgorithmRevisionEvidence
  public let additionalAlgorithmRevisions: Set<AlgorithmRevisionEvidence>

  public init(
    frames: DrawingObservationFramePair,
    localPreDrawingBaseline: SamePoseFrameSample,
    postDrawing: SamePoseFrameSample,
    region: PixelRect,
    intendedCameraPolylines: [Polyline<CameraPixelSpace>],
    thresholds: InkPixelThresholds,
    controllerPositionToleranceMM: Double,
    alignmentSearchRadiusPixels: Int,
    maximumAlignmentShiftPixels: Int,
    maximumBackgroundMeanAbsoluteDifference: Double,
    minimumInkPixelsPerPolyline: Int = 3,
    maximumInkPixels: Int = 250_000,
    maximumRegionPixelCount: Int = 1_000_000,
    maximumIntendedPointCount: Int = 25_000,
    maximumAssociationEvaluationCount: Int = 5_000_000,
    maximumAssociationDistancePixels: Double = 4,
    associationAmbiguityTolerancePixels: Double = 0.01,
    centrelineSampleSpacingPixels: Double = 4,
    maximumCentrelineSampleCountPerPolyline: Int = 4_096,
    observerRevision: AlgorithmRevisionEvidence,
    additionalAlgorithmRevisions: Set<AlgorithmRevisionEvidence> = []
  ) {
    self.frames = frames
    self.localPreDrawingBaseline = localPreDrawingBaseline
    self.postDrawing = postDrawing
    self.region = region
    self.intendedCameraPolylines = intendedCameraPolylines
    self.thresholds = thresholds
    self.controllerPositionToleranceMM = controllerPositionToleranceMM
    self.alignmentSearchRadiusPixels = alignmentSearchRadiusPixels
    self.maximumAlignmentShiftPixels = maximumAlignmentShiftPixels
    self.maximumBackgroundMeanAbsoluteDifference = maximumBackgroundMeanAbsoluteDifference
    self.minimumInkPixelsPerPolyline = minimumInkPixelsPerPolyline
    self.maximumInkPixels = maximumInkPixels
    self.maximumRegionPixelCount = maximumRegionPixelCount
    self.maximumIntendedPointCount = maximumIntendedPointCount
    self.maximumAssociationEvaluationCount = maximumAssociationEvaluationCount
    self.maximumAssociationDistancePixels = maximumAssociationDistancePixels
    self.associationAmbiguityTolerancePixels = associationAmbiguityTolerancePixels
    self.centrelineSampleSpacingPixels = centrelineSampleSpacingPixels
    self.maximumCentrelineSampleCountPerPolyline = maximumCentrelineSampleCountPerPolyline
    self.observerRevision = observerRevision
    self.additionalAlgorithmRevisions = additionalAlgorithmRevisions
  }
}

public struct PlannedDrawingObservation: Codable, Hashable, Sendable {
  public let evidence: DrawingObservedInkEvidence
  public let alignment: IntegerFrameAlignment
  public let overlays: [CameraOverlayMeasurement]
  public let observedPixelCount: Int

  public init(
    evidence: DrawingObservedInkEvidence,
    alignment: IntegerFrameAlignment,
    overlays: [CameraOverlayMeasurement],
    observedPixelCount: Int
  ) {
    self.evidence = evidence
    self.alignment = alignment
    self.overlays = overlays
    self.observedPixelCount = observedPixelCount
  }
}

public enum PlannedDrawingObservationOutcome: Codable, Hashable, Sendable {
  case observed(PlannedDrawingObservation)
  case rejected(DrawingObservationRejection)
}

extension VisionWorker {
  public func observePlannedDrawingInk(
    _ request: PlannedDrawingObservationRequest
  ) -> PlannedDrawingObservationOutcome {
    let requestedAlgorithms = request.additionalAlgorithmRevisions.union([request.observerRevision])
    func reject(
      _ reason: DrawingObservationRejectionReason,
      algorithms: Set<AlgorithmRevisionEvidence> = []
    ) -> PlannedDrawingObservationOutcome {
      let revisions = algorithms.isEmpty ? requestedAlgorithms : algorithms
      guard
        let rejection = try? DrawingObservationRejection(
          frames: request.frames,
          reason: reason,
          algorithmRevisions: revisions
        )
      else {
        // The request always carries a valid frame pair and observer revision.
        // Retain a typed failure if a future evidence contract becomes stricter.
        let fallback = try! DrawingObservationRejection(
          frames: request.frames,
          reason: .algorithmFailure(code: "rejection-construction-failed"),
          algorithmRevisions: [request.observerRevision]
        )
        return .rejected(fallback)
      }
      return .rejected(rejection)
    }

    guard Self.validPolicy(request) else {
      return reject(.algorithmFailure(code: "invalid-policy"))
    }
    guard Self.contains(request.region, in: request.localPreDrawingBaseline.frame),
      Self.contains(request.region, in: request.postDrawing.frame),
      request.region.height > 0,
      request.region.width <= request.maximumRegionPixelCount / request.region.height
    else { return reject(.algorithmFailure(code: "invalid-region")) }
    guard !request.intendedCameraPolylines.isEmpty,
      request.intendedCameraPolylines.reduce(0, { $0 + $1.points.count })
        <= request.maximumIntendedPointCount,
      request.intendedCameraPolylines.allSatisfy({
        $0.points.allSatisfy { Self.contains($0, in: request.region) }
      })
    else { return reject(.unsupportedDrawing) }
    guard Self.matchesPinnedFrames(request) else {
      return reject(.invalidFrameIdentity)
    }
    let poseDistance = request.localPreDrawingBaseline.controllerPosition.point.distance(
      to: request.postDrawing.controllerPosition.point
    )
    guard poseDistance <= request.controllerPositionToleranceMM else {
      return reject(.observationPoseMismatch)
    }

    let alignment = Self.bestIntegerAlignment(
      request.localPreDrawingBaseline.frame,
      request.postDrawing.frame,
      excluding: request.region,
      searchRadius: request.alignmentSearchRadiusPixels
    )
    let alignmentRevision = try! AlgorithmRevisionEvidence(
      component: "integer-frame-alignment",
      revision: alignment.estimatorRevision
    )
    let algorithms = requestedAlgorithms.union([alignmentRevision])
    guard
      max(abs(alignment.shiftX), abs(alignment.shiftY))
        <= request.maximumAlignmentShiftPixels
    else { return reject(.excessiveAlignment, algorithms: algorithms) }
    guard
      alignment.backgroundMeanAbsoluteDifference
        <= request.maximumBackgroundMeanAbsoluteDifference
    else { return reject(.excessiveBackgroundResidual, algorithms: algorithms) }

    let newInk = Self.newInkPixels(
      from: request.localPreDrawingBaseline.frame,
      to: request.postDrawing.frame,
      region: request.region,
      thresholds: request.thresholds,
      observationShiftX: alignment.shiftX,
      observationShiftY: alignment.shiftY
    )
    guard !newInk.isEmpty else { return reject(.inkMissing, algorithms: algorithms) }
    guard newInk.count <= request.maximumInkPixels else {
      return reject(.algorithmFailure(code: "ink-pixel-budget-exceeded"), algorithms: algorithms)
    }
    let intendedSegmentCount = request.intendedCameraPolylines.reduce(0) {
      $0 + $1.points.count - 1
    }
    guard intendedSegmentCount > 0,
      newInk.count <= request.maximumAssociationEvaluationCount / intendedSegmentCount
    else {
      return reject(
        .algorithmFailure(code: "association-budget-exceeded"),
        algorithms: algorithms
      )
    }

    let association = Self.associate(
      newInk,
      with: request.intendedCameraPolylines,
      observationShiftX: alignment.shiftX,
      observationShiftY: alignment.shiftY,
      maximumDistance: request.maximumAssociationDistancePixels,
      ambiguityTolerance: request.associationAmbiguityTolerancePixels
    )
    if association.ambiguousPixelCount > 0 {
      return reject(
        .inkAmbiguous(candidateCount: association.ambiguousPixelCount),
        algorithms: algorithms
      )
    }
    guard association.unassociatedPixelCount == 0 else {
      return reject(.correspondenceUnavailable, algorithms: algorithms)
    }
    guard
      association.byPolyline.allSatisfy({
        $0.count >= request.minimumInkPixelsPerPolyline
      })
    else { return reject(.inkMissing, algorithms: algorithms) }

    guard
      let sampled = Self.sampleObservedCentrelines(
        association.byPolyline,
        intended: request.intendedCameraPolylines,
        spacing: request.centrelineSampleSpacingPixels,
        maximumSamplesPerPolyline: request.maximumCentrelineSampleCountPerPolyline
      )
    else { return reject(.correspondenceUnavailable, algorithms: algorithms) }
    guard let residual = Self.residualEvidence(sampled.correspondences) else {
      return reject(.algorithmFailure(code: "residual-construction-failed"), algorithms: algorithms)
    }
    guard
      let evidence = try? DrawingObservedInkEvidence(
        frames: request.frames,
        intendedInk: request.intendedCameraPolylines,
        observedInk: sampled.polylines,
        residual: residual,
        algorithmRevisions: algorithms
      )
    else {
      return reject(.algorithmFailure(code: "evidence-construction-failed"), algorithms: algorithms)
    }
    let overlayRevision = Self.overlayRevision(algorithms)
    let overlays = Self.plannedDrawingOverlays(
      frame: request.postDrawing.frame,
      intended: request.intendedCameraPolylines,
      observed: sampled.polylines,
      correspondences: sampled.correspondences,
      algorithmRevision: overlayRevision
    )
    return .observed(
      PlannedDrawingObservation(
        evidence: evidence,
        alignment: alignment,
        overlays: overlays,
        observedPixelCount: newInk.count
      ))
  }
}

extension VisionWorker {
  struct PlannedInkAssociation {
    let byPolyline: [[PlannedAssociatedInkPixel]]
    let unassociatedPixelCount: Int
    let ambiguousPixelCount: Int
  }

  struct PlannedAssociatedInkPixel {
    let point: Point2<CameraPixelSpace>
    let alongDistance: Double
  }

  struct PlannedPathProjection {
    let distance: Double
    let alongDistance: Double
  }

  struct PlannedSampledCorrespondence {
    let intended: Point2<CameraPixelSpace>
    let observed: Point2<CameraPixelSpace>
    let crossTrackDistance: Double
  }

  struct PlannedSampledCentrelines {
    let polylines: [Polyline<CameraPixelSpace>]
    let correspondences: [PlannedSampledCorrespondence]
  }

  static func validPolicy(_ request: PlannedDrawingObservationRequest) -> Bool {
    request.controllerPositionToleranceMM.isFinite
      && request.controllerPositionToleranceMM >= 0
      && request.alignmentSearchRadiusPixels >= 0
      && request.maximumAlignmentShiftPixels >= 0
      && request.maximumAlignmentShiftPixels <= request.alignmentSearchRadiusPixels
      && request.maximumBackgroundMeanAbsoluteDifference.isFinite
      && request.maximumBackgroundMeanAbsoluteDifference >= 0
      && request.minimumInkPixelsPerPolyline >= 2
      && request.maximumInkPixels >= request.minimumInkPixelsPerPolyline
      && request.maximumRegionPixelCount > 0
      && request.maximumIntendedPointCount >= 2
      && request.maximumAssociationEvaluationCount > 0
      && request.maximumAssociationDistancePixels.isFinite
      && request.maximumAssociationDistancePixels > 0
      && request.associationAmbiguityTolerancePixels.isFinite
      && request.associationAmbiguityTolerancePixels >= 0
      && request.centrelineSampleSpacingPixels.isFinite
      && request.centrelineSampleSpacingPixels > 0
      && request.maximumCentrelineSampleCountPerPolyline >= 2
  }

  static func contains(
    _ point: Point2<CameraPixelSpace>,
    in region: PixelRect
  ) -> Bool {
    point.x >= Double(region.x) && point.y >= Double(region.y)
      && point.x < Double(region.x + region.width)
      && point.y < Double(region.y + region.height)
  }

  static func matchesPinnedFrames(_ request: PlannedDrawingObservationRequest) -> Bool {
    let baseline = request.localPreDrawingBaseline
    let post = request.postDrawing
    return baseline.source == request.frames.source
      && post.source == request.frames.source
      && ExactFrameProvenance(frame: baseline.frame) == request.frames.baseline
      && ExactFrameProvenance(frame: post.frame) == request.frames.post
  }

  static func associate(
    _ inkPixels: Set<InkPixel>,
    with intended: [Polyline<CameraPixelSpace>],
    observationShiftX: Int,
    observationShiftY: Int,
    maximumDistance: Double,
    ambiguityTolerance: Double
  ) -> PlannedInkAssociation {
    var grouped = Array(repeating: [PlannedAssociatedInkPixel](), count: intended.count)
    var unassociated = 0
    var ambiguous = 0
    let orderedInk = inkPixels.sorted { lhs, rhs in
      lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
    }
    for pixel in orderedInk {
      let point = try! Point2<CameraPixelSpace>(
        x: Double(pixel.x + observationShiftX),
        y: Double(pixel.y + observationShiftY)
      )
      let ranked = intended.enumerated().map { index, path in
        (index: index, projection: nearestProjection(of: point, onto: path))
      }.sorted { lhs, rhs in
        if lhs.projection.distance != rhs.projection.distance {
          return lhs.projection.distance < rhs.projection.distance
        }
        if lhs.index != rhs.index { return lhs.index < rhs.index }
        return lhs.projection.alongDistance < rhs.projection.alongDistance
      }
      guard let nearest = ranked.first,
        nearest.projection.distance <= maximumDistance
      else {
        unassociated += 1
        continue
      }
      if ranked.count > 1,
        ranked[1].projection.distance - nearest.projection.distance <= ambiguityTolerance
      {
        ambiguous += 1
        continue
      }
      grouped[nearest.index].append(
        PlannedAssociatedInkPixel(
          point: point,
          alongDistance: nearest.projection.alongDistance
        ))
    }
    return PlannedInkAssociation(
      byPolyline: grouped,
      unassociatedPixelCount: unassociated,
      ambiguousPixelCount: ambiguous
    )
  }

  static func nearestProjection(
    of point: Point2<CameraPixelSpace>,
    onto path: Polyline<CameraPixelSpace>
  ) -> PlannedPathProjection {
    var best: PlannedPathProjection?
    var precedingLength = 0.0
    for pair in zip(path.points, path.points.dropFirst()) {
      let dx = pair.1.x - pair.0.x
      let dy = pair.1.y - pair.0.y
      let squaredLength = dx * dx + dy * dy
      guard squaredLength > 0 else { continue }
      let rawT = ((point.x - pair.0.x) * dx + (point.y - pair.0.y) * dy) / squaredLength
      let t = min(1, max(0, rawT))
      let projected = try! Point2<CameraPixelSpace>(
        x: pair.0.x + t * dx,
        y: pair.0.y + t * dy
      )
      let segmentLength = sqrt(squaredLength)
      let candidate = PlannedPathProjection(
        distance: point.distance(to: projected),
        alongDistance: precedingLength + t * segmentLength
      )
      if let current = best {
        if candidate.distance < current.distance
          || (candidate.distance == current.distance
            && candidate.alongDistance < current.alongDistance)
        {
          best = candidate
        }
      } else {
        best = candidate
      }
      precedingLength += segmentLength
    }
    return best ?? PlannedPathProjection(distance: .infinity, alongDistance: 0)
  }

  static func sampleObservedCentrelines(
    _ grouped: [[PlannedAssociatedInkPixel]],
    intended: [Polyline<CameraPixelSpace>],
    spacing: Double,
    maximumSamplesPerPolyline: Int
  ) -> PlannedSampledCentrelines? {
    var polylines: [Polyline<CameraPixelSpace>] = []
    var correspondences: [PlannedSampledCorrespondence] = []
    for (pathIndex, pixels) in grouped.enumerated() {
      let intendedPath = intended[pathIndex]
      let unboundedBinCount = intendedPath.length / spacing
      let binCount =
        unboundedBinCount >= Double(maximumSamplesPerPolyline)
        ? maximumSamplesPerPolyline
        : max(2, Int(ceil(unboundedBinCount)))
      var bins = Array(repeating: [PlannedAssociatedInkPixel](), count: binCount)
      for pixel in pixels {
        let fraction = intendedPath.length == 0 ? 0 : pixel.alongDistance / intendedPath.length
        let index = min(binCount - 1, max(0, Int(floor(fraction * Double(binCount)))))
        bins[index].append(pixel)
      }
      var points: [Point2<CameraPixelSpace>] = []
      for bin in bins where !bin.isEmpty {
        let observed = try! Point2<CameraPixelSpace>(
          x: bin.reduce(0.0) { $0 + $1.point.x } / Double(bin.count),
          y: bin.reduce(0.0) { $0 + $1.point.y } / Double(bin.count)
        )
        let meanAlong = bin.reduce(0.0) { $0 + $1.alongDistance } / Double(bin.count)
        let intendedPoint = point(on: intendedPath, at: meanAlong)
        if points.last != observed { points.append(observed) }
        correspondences.append(
          PlannedSampledCorrespondence(
            intended: intendedPoint,
            observed: observed,
            crossTrackDistance: nearestProjection(of: observed, onto: intendedPath).distance
          ))
      }
      guard let centreline = try? Polyline(points: points) else { return nil }
      polylines.append(centreline)
    }
    return PlannedSampledCentrelines(polylines: polylines, correspondences: correspondences)
  }

  static func point(
    on path: Polyline<CameraPixelSpace>,
    at requestedDistance: Double
  ) -> Point2<CameraPixelSpace> {
    let distance = min(path.length, max(0, requestedDistance))
    var precedingLength = 0.0
    for pair in zip(path.points, path.points.dropFirst()) {
      let segmentLength = pair.0.distance(to: pair.1)
      guard segmentLength > 0 else { continue }
      if precedingLength + segmentLength >= distance {
        let t = (distance - precedingLength) / segmentLength
        return try! Point2(
          x: pair.0.x + t * (pair.1.x - pair.0.x),
          y: pair.0.y + t * (pair.1.y - pair.0.y)
        )
      }
      precedingLength += segmentLength
    }
    return path.end
  }

  static func residualEvidence(
    _ correspondences: [PlannedSampledCorrespondence]
  ) -> DrawingResidualEvidence? {
    guard !correspondences.isEmpty else { return nil }
    let squared = correspondences.map { pow($0.intended.distance(to: $0.observed), 2) }
    let crossTrackSquared = correspondences.map { pow($0.crossTrackDistance, 2) }
    let rootMeanSquare = sqrt(squared.reduce(0, +) / Double(squared.count))
    let maximum = max(rootMeanSquare, sqrt(squared.max() ?? 0))
    return try? DrawingResidualEvidence(
      correspondenceCount: UInt32(correspondences.count),
      rootMeanSquarePixels: rootMeanSquare,
      maximumPixels: maximum,
      rootMeanSquareCrossTrackPixels: sqrt(
        crossTrackSquared.reduce(0, +) / Double(crossTrackSquared.count)
      )
    )
  }

  static func plannedDrawingOverlays(
    frame: StampedFrame,
    intended: [Polyline<CameraPixelSpace>],
    observed: [Polyline<CameraPixelSpace>],
    correspondences: [PlannedSampledCorrespondence],
    algorithmRevision: String
  ) -> [CameraOverlayMeasurement] {
    let identity = (frameID: frame.id, cameraConfigurationID: frame.cameraConfigurationID)
    var overlays = intended.map {
      CameraOverlayMeasurement(
        frameID: identity.frameID,
        cameraConfigurationID: identity.cameraConfigurationID,
        geometry: .polyline($0),
        provenance: CameraMeasurementProvenance(
          kind: .intendedPath,
          source: .planned,
          algorithmRevision: algorithmRevision
        )
      )
    }
    overlays += observed.map {
      CameraOverlayMeasurement(
        frameID: identity.frameID,
        cameraConfigurationID: identity.cameraConfigurationID,
        geometry: .polyline($0),
        provenance: CameraMeasurementProvenance(
          kind: .observedInk,
          source: .measured,
          algorithmRevision: algorithmRevision
        )
      )
    }
    overlays += correspondences.map {
      let geometry: CameraPixelGeometry
      if $0.intended == $0.observed {
        geometry = .point($0.observed)
      } else {
        geometry = .polyline(try! Polyline(points: [$0.intended, $0.observed]))
      }
      return CameraOverlayMeasurement(
        frameID: identity.frameID,
        cameraConfigurationID: identity.cameraConfigurationID,
        geometry: geometry,
        provenance: CameraMeasurementProvenance(
          kind: .residual,
          source: .diagnostic,
          algorithmRevision: algorithmRevision
        )
      )
    }
    return overlays
  }

  static func overlayRevision(
    _ revisions: Set<AlgorithmRevisionEvidence>
  ) -> String {
    revisions.sorted {
      $0.component == $1.component
        ? $0.revision < $1.revision
        : $0.component < $1.component
    }.map { "\($0.component)=\($0.revision)" }.joined(separator: "|")
  }
}
