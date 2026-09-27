import CoreGraphics
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import PlotterUI
import Observation
import SwiftUI

enum ActionSurfaceScalePolicy: String, Sendable {
  case aspectFit
}

/// The high-rate, presentation-only frame owner. The application retains this
/// reference outside its semantic observation graph so camera preview changes
/// invalidate only views that explicitly observe this model.
@MainActor
@Observable
final class ActionSurfacePreviewModel {
  private(set) var displayedFrame: DisplayedFrame?
  /// Semantic admission inspects identity without subscribing the control root
  /// to every preview publication. The video leaf observes displayedFrame.
  @ObservationIgnored private(set) var latestFrameSnapshot: DisplayedFrame?
  private(set) var publicationCount: UInt64 = 0
  private(set) var presentationRevision: UInt64 = 0
  @ObservationIgnored private(set) var overlayCanvasDrawCount = 0
  @ObservationIgnored private(set) var overlayCanvasBuildCount = 0

  func recordOverlayCanvasBuild() {
    overlayCanvasBuildCount += 1
  }

  func recordOverlayCanvasDraw() {
    overlayCanvasDrawCount += 1
  }

  /// Refreshes video-local overlay and diagnostic consumers. The application
  /// remains the authority for the presentation and its exact-frame evidence.
  func invalidatePresentation() {
    presentationRevision &+= 1
  }

  @discardableResult
  func publish(_ frame: DisplayedFrame?) -> Bool {
    if framesHaveSameIdentity(displayedFrame, frame) { return false }
    if let displayedFrame, let frame,
      displayedFrame.source == frame.source,
      displayedFrame.frame.cameraConfigurationID == frame.frame.cameraConfigurationID,
      frame.frame.captureNanoseconds < displayedFrame.frame.captureNanoseconds
    {
      return false
    }
    latestFrameSnapshot = frame
    displayedFrame = frame
    if frame != nil { publicationCount &+= 1 }
    return true
  }

  func resetPublicationCount() {
    publicationCount = 0
    overlayCanvasDrawCount = 0
    overlayCanvasBuildCount = 0
  }

  private func framesHaveSameIdentity(
    _ lhs: DisplayedFrame?,
    _ rhs: DisplayedFrame?
  ) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil):
      true
    case (.some(let lhs), .some(let rhs)):
      lhs.source == rhs.source
        && lhs.frame.id == rhs.frame.id
        && lhs.frame.sequence == rhs.frame.sequence
        && lhs.frame.captureNanoseconds == rhs.frame.captureNanoseconds
        && lhs.frame.cameraConfigurationID == rhs.frame.cameraConfigurationID
    case (.none, .some), (.some, .none):
      false
    }
  }
}

/// Presentation-only projection from top-left-origin camera pixels into the
/// aspect-fitted image rectangle. Camera +Y remains view +Y.
struct CameraPixelToViewTransform: Equatable, Sendable {
  let frameWidth: Double
  let frameHeight: Double
  let viewWidth: Double
  let viewHeight: Double
  let scale: Double
  let originX: Double
  let originY: Double
  let visibleCameraRect: CGRect

  init?(
    frameWidth: Int,
    frameHeight: Int,
    viewWidth: Double,
    viewHeight: Double,
    focusRegion: PixelRect? = nil,
    policy: ActionSurfaceScalePolicy = .aspectFit
  ) {
    guard frameWidth > 0, frameHeight > 0, viewWidth > 0, viewHeight > 0 else { return nil }
    let requestedRect =
      focusRegion.map {
        CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
      } ?? CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let frameRect = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let clippedRect = requestedRect.intersection(frameRect)
    guard !clippedRect.isNull, clippedRect.width > 0, clippedRect.height > 0 else { return nil }
    visibleCameraRect = clippedRect
    let horizontalScale = viewWidth / clippedRect.width
    let verticalScale = viewHeight / clippedRect.height
    switch policy {
    case .aspectFit:
      scale = min(horizontalScale, verticalScale)
    }
    self.frameWidth = Double(frameWidth)
    self.frameHeight = Double(frameHeight)
    self.viewWidth = viewWidth
    self.viewHeight = viewHeight
    originX = (viewWidth - clippedRect.width * scale) / 2 - clippedRect.minX * scale
    originY = (viewHeight - clippedRect.height * scale) / 2 - clippedRect.minY * scale
  }

  var imageRect: CGRect {
    CGRect(
      x: originX,
      y: originY,
      width: frameWidth * scale,
      height: frameHeight * scale
    )
  }

  func point(_ cameraPoint: Point2<CameraPixelSpace>) -> CGPoint {
    CGPoint(
      x: originX + cameraPoint.x * scale,
      y: originY + cameraPoint.y * scale
    )
  }

  func cameraPoint(_ viewPoint: CGPoint) -> Point2<CameraPixelSpace>? {
    let x = (viewPoint.x - originX) / scale
    let y = (viewPoint.y - originY) / scale
    guard visibleCameraRect.contains(CGPoint(x: x, y: y)),
      x >= 0, x < frameWidth, y >= 0, y < frameHeight
    else { return nil }
    return try? Point2(x: x, y: y)
  }
}

enum ActionSurfaceTipPresentation: Hashable, Sendable {
  case notCalibrated
  case awaitingClick(String)
  case collectingClicks(
    prompt: String,
    clicks: [Point2<CameraPixelSpace>]
  )
  case selected(
    click: Point2<CameraPixelSpace>,
    pointingUncertaintyPixels: Vector2<CameraPixelSpace>,
    prediction: Point2<CameraPixelSpace>?,
    residualPixels: Double?
  )
  case calibrated(prediction: Point2<CameraPixelSpace>?)

  var statusText: String {
    switch self {
    case .notCalibrated: "Tip not calibrated"
    case .awaitingClick(let prompt): prompt
    case .collectingClicks(let prompt, let clicks):
      "\(clicks.count)/\(ToolContactCalibrationPosition.sparseTipCornerPositions.count) centers selected · \(prompt)"
    case .selected(_, _, _, let residual):
      residual.map { String(format: "Selection residual %.3f px", $0) }
        ?? "Mark center selected"
    case .calibrated: "Tip calibration accepted"
    }
  }

  var interactionPrompt: String? {
    switch self {
    case .awaitingClick, .collectingClicks, .selected: statusText
    case .notCalibrated, .calibrated: nil
    }
  }

  var reviewGeometry: ActionSurfaceTipReviewGeometry? {
    guard case .selected(let click, let uncertainty, let prediction, _) = self else {
      return nil
    }
    return ActionSurfaceTipReviewGeometry(
      click: click,
      pointingUncertaintyPixels: uncertainty,
      prediction: prediction,
      residual: prediction.flatMap { try? Polyline(points: [$0, click]) }
    )
  }

  var clickMarkers: [Point2<CameraPixelSpace>] {
    guard case .collectingClicks(_, let clicks) = self else { return [] }
    return clicks
  }
}

struct ActionSurfaceTipReviewGeometry: Hashable, Sendable {
  let click: Point2<CameraPixelSpace>
  let pointingUncertaintyPixels: Vector2<CameraPixelSpace>
  let prediction: Point2<CameraPixelSpace>?
  let residual: Polyline<CameraPixelSpace>?
}

struct SparseTipKnownMachinePosition: Hashable, Sendable {
  let calibrationPosition: ToolContactCalibrationPosition
  let machinePosition: MachinePosition
}

struct SparseTipClickAssociation: Hashable, Sendable {
  let calibrationPosition: ToolContactCalibrationPosition
  let machinePosition: MachinePosition
  let projectedCameraPoint: Point2<CameraPixelSpace>
  let clickedCameraPoint: Point2<CameraPixelSpace>
}

/// Associates the four corner clicks without treating click order as evidence. Both point
/// sets are centered before evaluating every assignment so the unknown common
/// cap-to-tip translation has no effect on the selected correspondence.
func associateSparseTipClicks(
  using registrationFit: MachineCameraRegistrationFit,
  knownMachinePositions: [SparseTipKnownMachinePosition],
  clicks: [Point2<CameraPixelSpace>]
) throws -> [SparseTipClickAssociation] {
  let canonicalPositions = ToolContactCalibrationPosition.sparseTipCornerPositions
  precondition(
    knownMachinePositions.count == canonicalPositions.count
      && clicks.count == canonicalPositions.count
      && Set(knownMachinePositions.map(\.calibrationPosition)) == Set(canonicalPositions)
  )

  let knownByPosition = Dictionary(
    uniqueKeysWithValues: knownMachinePositions.map { ($0.calibrationPosition, $0.machinePosition) }
  )
  let projected = try canonicalPositions.map { position in
    let machinePosition = knownByPosition[position]!
    return (
      position,
      machinePosition,
      try registrationFit.cameraPoint(from: machinePosition.point)
    )
  }
  let projectedCenter = try Point2<CameraPixelSpace>(
    x: projected.map { $0.2.x }.reduce(0, +) / Double(projected.count),
    y: projected.map { $0.2.y }.reduce(0, +) / Double(projected.count)
  )
  let clickedCenter = try Point2<CameraPixelSpace>(
    x: clicks.map(\.x).reduce(0, +) / Double(clicks.count),
    y: clicks.map(\.y).reduce(0, +) / Double(clicks.count)
  )
  let centeredProjected = projected.map {
    (x: $0.2.x - projectedCenter.x, y: $0.2.y - projectedCenter.y)
  }
  // Coordinate ordering makes exact-score ties independent of operator click order.
  // Permutation slots remain the canonical calibration-position order above.
  let canonicalClicks = clicks.sorted {
    $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x
  }
  let centeredClicks = canonicalClicks.map {
    (x: $0.x - clickedCenter.x, y: $0.y - clickedCenter.y)
  }

  var bestIndices: [Int] = []
  var bestScore = Double.infinity
  for indices in permutations(of: Array(canonicalClicks.indices)) {
    let score = canonicalPositions.indices.reduce(0.0) { result, positionIndex in
      let click = centeredClicks[indices[positionIndex]]
      let projection = centeredProjected[positionIndex]
      let dx = projection.x - click.x
      let dy = projection.y - click.y
      return result + dx * dx + dy * dy
    }
    // Enumeration is lexicographic in canonical calibration-position order;
    // retaining the first equal score is the deterministic exact-tie rule.
    if score < bestScore {
      bestScore = score
      bestIndices = indices
    }
  }

  return canonicalPositions.indices.map { index in
    SparseTipClickAssociation(
      calibrationPosition: projected[index].0,
      machinePosition: projected[index].1,
      projectedCameraPoint: projected[index].2,
      clickedCameraPoint: canonicalClicks[bestIndices[index]]
    )
  }
}

private func permutations(of values: [Int]) -> [[Int]] {
  guard !values.isEmpty else { return [[]] }
  return values.indices.flatMap { index in
    var remaining = values
    let next = remaining.remove(at: index)
    return permutations(of: remaining).map { [next] + $0 }
  }
}

/// Stable presentation identity for optional fitted plotter bounds. Exact
/// frame identity deliberately does not participate: zoom is presentation only.
struct ActionSurfaceViewportContext: Hashable, Sendable {
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let frameWidth: Int
  let frameHeight: Int
  let fittedRegion: PixelRect?
  let preferredInitialZoom: Double
  let presentationRevisionToken: String
}

/// The effective camera-pixel bounds used by viewport projection and clipping.
/// Empty or wholly out-of-frame fitted bounds have no drawable intersection.
func cameraFrameIntersection(
  _ region: PixelRect,
  frameWidth: Int,
  frameHeight: Int
) -> PixelRect? {
  guard frameWidth > 0, frameHeight > 0, region.width > 0, region.height > 0 else {
    return nil
  }
  let minimumX = max(0, region.x)
  let minimumY = max(0, region.y)
  let maximumX = min(frameWidth, region.x + region.width)
  let maximumY = min(frameHeight, region.y + region.height)
  guard maximumX > minimumX, maximumY > minimumY else { return nil }
  return PixelRect(
    x: minimumX,
    y: minimumY,
    width: maximumX - minimumX,
    height: maximumY - minimumY
  )
}

/// Window-local, presentation-only viewport state. `zoom == 0` is the complete
/// camera frame and `zoom == 1` is the fitted learned plotter region.
/// Intermediate values never mutate camera-pixel evidence.
struct ActionSurfaceViewportState: Equatable, Sendable {
  private(set) var context: ActionSurfaceViewportContext?
  private(set) var presentationTransformRevision = PresentationTransformRevision()
  private(set) var panOffsetX: Int = 0
  private(set) var panOffsetY: Int = 0
  /// Camera-pixel displacement not yet represented by the integer viewport.
  private var fractionalPanX: Double = 0
  private var fractionalPanY: Double = 0
  /// Exact operator-owned focus retained when a compatible context replaces
  /// the fitted target underneath the current numeric zoom and pan values.
  private var retainedCompatibleVisibleRegion: PixelRect?
  var zoom: Double = 0 {
    didSet {
      if zoom != oldValue {
        clearFractionalPan()
        if retainedCompatibleVisibleRegion != nil {
          panOffsetX = 0
          panOffsetY = 0
        }
        retainedCompatibleVisibleRegion = nil
        presentationTransformRevision = PresentationTransformRevision()
      }
    }
  }

  mutating func synchronize(with context: ActionSurfaceViewportContext?) {
    guard self.context != context else { return }
    clearFractionalPan()
    let previousContext = self.context
    let alreadyRetainingExactRegion = retainedCompatibleVisibleRegion != nil
    let preservesOperatorView =
      previousContext.map { previous in
        guard let context else { return false }
        return previous.source == context.source
          && previous.cameraConfigurationID == context.cameraConfigurationID
          && context.preferredInitialZoom == 0
      } ?? false
    let presentationTargetChanged = previousContext.map { previous in
      guard let context else { return false }
      return previous.frameWidth != context.frameWidth
        || previous.frameHeight != context.frameHeight
        || previous.fittedRegion != context.fittedRegion
    } ?? false
    let operatorVisibleRegion = preservesOperatorView
      ? previousContext.flatMap {
        visibleRegion(frameWidth: $0.frameWidth, frameHeight: $0.frameHeight)
      } : nil
    self.context = context
    if preservesOperatorView,
      (alreadyRetainingExactRegion || presentationTargetChanged),
      let context
    {
      retainedCompatibleVisibleRegion = operatorVisibleRegion.flatMap {
        cameraFrameIntersection(
          $0,
          frameWidth: context.frameWidth,
          frameHeight: context.frameHeight
        )
      }
    } else if preservesOperatorView {
      retainedCompatibleVisibleRegion = nil
    } else {
      retainedCompatibleVisibleRegion = nil
      zoom = min(1, max(0, context?.preferredInitialZoom ?? 0))
      panOffsetX = 0
      panOffsetY = 0
    }
    presentationTransformRevision = PresentationTransformRevision()
  }

  mutating func showFullFrame() {
    clearFractionalPan()
    retainedCompatibleVisibleRegion = nil
    zoom = 0
    panOffsetX = 0
    panOffsetY = 0
  }

  mutating func showFittedBounds() {
    clearFractionalPan()
    retainedCompatibleVisibleRegion = nil
    zoom = 1
    panOffsetX = 0
    panOffsetY = 0
    presentationTransformRevision = PresentationTransformRevision()
  }

  func visibleRegion(frameWidth: Int, frameHeight: Int) -> PixelRect? {
    guard let context, frameWidth > 0, frameHeight > 0 else { return nil }
    let t = min(1, max(0, zoom))
    if t == 0 { return nil }
    if let retainedCompatibleVisibleRegion {
      return cameraFrameIntersection(
        retainedCompatibleVisibleRegion,
        frameWidth: frameWidth,
        frameHeight: frameHeight
      )
    }
    let frame = PixelRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    let requested =
      context.fittedRegion
      ?? PixelRect(
        x: frameWidth / 4,
        y: frameHeight / 4,
        width: max(1, frameWidth / 2),
        height: max(1, frameHeight / 2)
      )
    guard
      let roi = cameraFrameIntersection(
        requested,
        frameWidth: frameWidth,
        frameHeight: frameHeight
      )
    else { return nil }
    let x = Int((Double(frame.x) + Double(roi.x - frame.x) * t).rounded())
    let y = Int((Double(frame.y) + Double(roi.y - frame.y) * t).rounded())
    let width = max(1, Int((Double(frame.width) + Double(roi.width - frame.width) * t).rounded()))
    let height = max(
      1, Int((Double(frame.height) + Double(roi.height - frame.height) * t).rounded()))
    let clampedWidth = min(width, frameWidth)
    let clampedHeight = min(height, frameHeight)
    let clampedX = min(max(0, x + panOffsetX), frameWidth - clampedWidth)
    let clampedY = min(max(0, y + panOffsetY), frameHeight - clampedHeight)
    return PixelRect(x: clampedX, y: clampedY, width: clampedWidth, height: clampedHeight)
  }

  func selectedRegion(frameWidth: Int, frameHeight: Int) -> PixelRect? {
    guard frameWidth > 0, frameHeight > 0 else { return nil }
    return visibleRegion(frameWidth: frameWidth, frameHeight: frameHeight)
      ?? PixelRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
  }

  mutating func pan(
    by translation: CGSize,
    viewSize: CGSize,
    frameWidth: Int,
    frameHeight: Int
  ) {
    guard zoom > 0,
      let region = visibleRegion(frameWidth: frameWidth, frameHeight: frameHeight),
      viewSize.width > 0, viewSize.height > 0
    else { return }
    let scale = min(
      Double(viewSize.width) / Double(region.width),
      Double(viewSize.height) / Double(region.height)
    )
    guard scale.isFinite, scale > 0,
      translation.width.isFinite, translation.height.isFinite else { return }
    // Clamp the continuous position before rounding so outward motion cannot
    // accumulate at an edge and delay the next drag in the opposite direction.
    let continuousX = min(max(0,
      Double(region.x) + fractionalPanX - Double(translation.width) / scale),
      Double(frameWidth - region.width))
    let continuousY = min(max(0,
      Double(region.y) + fractionalPanY - Double(translation.height) / scale),
      Double(frameHeight - region.height))
    let clampedX = Int(continuousX.rounded())
    let clampedY = Int(continuousY.rounded())
    fractionalPanX = continuousX - Double(clampedX)
    fractionalPanY = continuousY - Double(clampedY)
    if retainedCompatibleVisibleRegion != nil {
      let next = PixelRect(
        x: clampedX,
        y: clampedY,
        width: region.width,
        height: region.height
      )
      guard next != region else { return }
      retainedCompatibleVisibleRegion = next
      presentationTransformRevision = PresentationTransformRevision()
      return
    }
    let nextX = panOffsetX + clampedX - region.x
    let nextY = panOffsetY + clampedY - region.y
    guard nextX != panOffsetX || nextY != panOffsetY else { return }
    panOffsetX = nextX
    panOffsetY = nextY
    presentationTransformRevision = PresentationTransformRevision()
  }

  private mutating func clearFractionalPan() {
    fractionalPanX = 0
    fractionalPanY = 0
  }
}

struct ActionSurfacePresentation: Sendable {
  static let rendererIdentity = "canonical-stamped-frame"

  let displayedFrame: DisplayedFrame?
  let usesAmbientPreviewFrame: Bool
  let overlays: [CameraOverlayMeasurement]
  /// Last measured geometry on the moving preview. Original frame identities
  /// stay intact; exact-frame selection and evidence still use `overlays`.
  let ambientOverlays: [CameraOverlayMeasurement]
  let ambientOverlayFrame: DisplayedFrame?
  var renderedOverlays: [CameraOverlayMeasurement] { overlays + ambientOverlays }
  let simulatedAnnotations: [SimulatedLearningAnnotation]
  let simulatedViewportID: SimulatedCameraViewportID?
  let simulatedAnnotationsAreVisible: Bool
  let viewportContext: ActionSurfaceViewportContext?
  let analysisRegionIsLocked: Bool
  let analyzedOverlayFrame: ExactFrameOverlayProvenance?
  let pointSelectionRequest: PlotterPointSelectionRequest?
  let pointSelectionFailure: String?
  let tipPresentation: ActionSurfaceTipPresentation
  let completedComparisonReview: CompletedComparisonReviewPresentation
  let drawingStudioCanvas: DrawingStudioCanvasPresentation?
  let showsMachineBoundary: Bool
  let showsDrawingRegion: Bool
  let drawingPositioningUnavailableReason: String?

  var rendererIdentity: String { Self.rendererIdentity }

  init(
    displayedFrame: DisplayedFrame?,
    usesAmbientPreviewFrame: Bool = true,
    overlays: [CameraOverlayMeasurement],
    ambientOverlays: [CameraOverlayMeasurement] = [],
    ambientOverlayFrame: DisplayedFrame? = nil,
    simulatedAnnotations: [SimulatedLearningAnnotation] = [],
    simulatedViewportID: SimulatedCameraViewportID? = nil,
    simulatedAnnotationsAreVisible: Bool = true,
    viewportContext: ActionSurfaceViewportContext? = nil,
    analysisRegionIsLocked: Bool = false,
    analyzedOverlayFrame: ExactFrameOverlayProvenance? = nil,
    pointSelectionRequest: PlotterPointSelectionRequest? = nil,
    pointSelectionFailure: String? = nil,
    tipPresentation: ActionSurfaceTipPresentation = .notCalibrated,
    completedComparisonReview: CompletedComparisonReviewPresentation = .unavailable,
    drawingStudioCanvas: DrawingStudioCanvasPresentation? = nil,
    showsMachineBoundary: Bool = true,
    showsDrawingRegion: Bool = true,
    drawingPositioningUnavailableReason: String? = nil
  ) {
    self.displayedFrame = displayedFrame
    self.usesAmbientPreviewFrame = usesAmbientPreviewFrame
    self.pointSelectionFailure = pointSelectionFailure
    self.simulatedViewportID = simulatedViewportID
    self.simulatedAnnotationsAreVisible = simulatedAnnotationsAreVisible
    let compatibleAmbientFrame = ambientOverlayFrame.flatMap { measured -> DisplayedFrame? in
      guard usesAmbientPreviewFrame, let displayedFrame,
        measured.source == displayedFrame.source,
        measured.frame.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID,
        measured.frame.width == displayedFrame.frame.width,
        measured.frame.height == displayedFrame.frame.height,
        measured.frame.sequence <= displayedFrame.frame.sequence
      else { return nil }
      return measured
    }
    self.ambientOverlayFrame = compatibleAmbientFrame
    self.ambientOverlays = compatibleAmbientFrame.map { measured in
      ambientOverlays.filter { $0.matches(measured) && displayedFrame.map($0.matches) != true }
    } ?? []
    if let displayedFrame {
      self.overlays = overlays.filter { $0.matches(displayedFrame) }
      if simulatedAnnotationsAreVisible, let simulatedViewportID {
        self.simulatedAnnotations = simulatedAnnotations.filter {
          $0.matches(displayedFrame, viewportID: simulatedViewportID)
        }
      } else {
        self.simulatedAnnotations = []
      }
      self.viewportContext = viewportContext.flatMap {
        $0.source == displayedFrame.source
          && $0.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID ? $0 : nil
      }
      self.pointSelectionRequest = pointSelectionRequest.flatMap {
        $0.matchesExactDisplayedFrame(displayedFrame) ? $0 : nil
      }
      self.analyzedOverlayFrame = analyzedOverlayFrame.flatMap {
        $0.matches(displayedFrame) || compatibleAmbientFrame.map($0.matches) == true ? $0 : nil
      }
    } else {
      self.overlays = []
      self.simulatedAnnotations = []
      self.viewportContext = nil
      self.pointSelectionRequest = nil
      self.analyzedOverlayFrame = nil
    }
    self.analysisRegionIsLocked = analysisRegionIsLocked
    self.tipPresentation = tipPresentation
    self.completedComparisonReview = completedComparisonReview
    self.drawingStudioCanvas = drawingStudioCanvas
    self.showsMachineBoundary = showsMachineBoundary
    self.showsDrawingRegion = showsDrawingRegion
    self.drawingPositioningUnavailableReason = drawingPositioningUnavailableReason
  }

  func resolvingAmbientPreviewFrame(_ frame: DisplayedFrame?, forceRetainedFrame: Bool = false) -> Self {
    guard usesAmbientPreviewFrame || forceRetainedFrame else { return self }
    let matchingViewportContext: ActionSurfaceViewportContext? = viewportContext.flatMap {
      context in
      guard let frame,
        context.source == frame.source,
        context.cameraConfigurationID == frame.frame.cameraConfigurationID
      else { return nil }
      return context
    }
    return Self(
      displayedFrame: frame,
      usesAmbientPreviewFrame: usesAmbientPreviewFrame && !forceRetainedFrame,
      overlays: overlays,
      ambientOverlays: forceRetainedFrame ? [] : renderedOverlays,
      ambientOverlayFrame: forceRetainedFrame ? nil : ambientOverlayFrame ?? displayedFrame,
      simulatedAnnotations: simulatedAnnotations,
      simulatedViewportID: simulatedViewportID,
      simulatedAnnotationsAreVisible: simulatedAnnotationsAreVisible,
      viewportContext: matchingViewportContext,
      analysisRegionIsLocked: matchingViewportContext == nil ? false : analysisRegionIsLocked,
      analyzedOverlayFrame: analyzedOverlayFrame,
      pointSelectionRequest: pointSelectionRequest,
      pointSelectionFailure: pointSelectionFailure,
      tipPresentation: tipPresentation,
      completedComparisonReview: completedComparisonReview,
      drawingStudioCanvas: drawingStudioCanvas,
      showsMachineBoundary: showsMachineBoundary,
      showsDrawingRegion: showsDrawingRegion,
      drawingPositioningUnavailableReason: drawingPositioningUnavailableReason
    )
  }

  var sourceBadgeLabel: String? {
    guard case .simulated = displayedFrame?.source else { return nil }
    return "SIMULATED"
  }

  func acceptsPendingPointSelection(_ submission: PlotterPointSelectionSubmission) -> Bool {
    guard let request = pointSelectionRequest else { return false }
    return submission.selectionID == request.id
      && submission.frame == request.frame
      && submission.presentationTransformRevision == request.presentationTransformRevision
  }
}

/// The only Action Surface view that observes high-rate preview publication.
/// It reads overlays locally; semantic control requests remain supplied by
/// the root application projection.
struct PreviewingActionSurface: View {
  let application: PlotterApplicationRuntime
  let preview: ActionSurfacePreviewModel
  @Binding var viewport: ActionSurfaceViewportState
  let plotterUIProjection: PlotterUIProjection
  let plotterUIIntentSink: any PlotterUIIntentSink
  @Binding var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @Binding var pendingPointSelection: PlotterPointSelectionSubmission?

  var body: some View {
    let _ = preview.presentationRevision
    ActionSurface(
      presentation: application.actionSurfacePresentation.resolvingAmbientPreviewFrame(application.calibrationWorkingRegionFrame ?? application.drawingFrameEditSession?.frame ?? preview.displayedFrame, forceRetainedFrame: application.calibrationWorkingRegionFrame != nil || application.drawingFrameEditSession != nil),
      renderDiagnostics: preview,
      viewport: $viewport,
      plotterUIProjection: plotterUIProjection,
      plotterUIIntentSink: plotterUIIntentSink,
      pendingDrawingPlacement: $pendingDrawingPlacement,
      pendingPointSelection: $pendingPointSelection,
      beginFrameEdit: { await application.beginDrawingFrameEdit(id: $0, on: $1) },
      endFrameEdit: { application.endDrawingFrameEdit(id: $0) },
      workingRegion: application.calibrationWorkingRegionPresentation,
      beginWorkingRegionEdit: { application.beginCalibrationWorkingRegionEdit(id: $0, on: $1) },
      applyWorkingRegion: { application.applyCalibrationWorkingRegion($0, bounds: $1) },
      cancelWorkingRegionEdit: { application.cancelCalibrationWorkingRegionEdit(id: $0) }
    )
  }
}

struct ActionSurfacePointSelectionPendingIdentity: Hashable, Sendable {
  let request: PlotterPointSelectionRequest?
  let viewportRevision: PresentationTransformRevision
}

enum ActionSurfacePointSubmissionPolicy {
  static func automaticSubmission(
    pending: PlotterPointSelectionSubmission?,
    presentation: ActionSurfacePresentation,
    projection: PlotterUIProjection
  ) -> PlotterPointSelectionSubmission? {
    guard let pending,
      presentation.acceptsPendingPointSelection(pending),
      projection.request(matching: .pointSelection(pending)) != nil
    else { return nil }
    return pending
  }
}

enum ExactFramePointSubmissionBuilder {
  static func submission(
    presentation: ActionSurfacePresentation,
    viewport: ActionSurfaceViewportState,
    at location: CGPoint,
    viewSize: CGSize,
    referenceRegion: AxisAlignedBounds<CameraPixelSpace>? = nil
  ) -> PlotterPointSelectionSubmission? {
    guard let displayedFrame = presentation.displayedFrame,
      let request = presentation.pointSelectionRequest,
      let transform = CameraPixelToViewTransform(
        frameWidth: displayedFrame.frame.width,
        frameHeight: displayedFrame.frame.height,
        viewWidth: viewSize.width,
        viewHeight: viewSize.height,
        focusRegion: viewport.visibleRegion(
          frameWidth: displayedFrame.frame.width,
          frameHeight: displayedFrame.frame.height
        )
      ),
      let point = transform.cameraPoint(location),
      let exactFrame = displayedFrame.pointSelectionSubmissionReferenceIfMaterialized(
        archiveBinding: request.frame
      )
    else { return nil }
    return PlotterPointSelectionSubmission(
      selectionID: request.id,
      frame: exactFrame,
      point: point,
      presentationTransformRevision: request.presentationTransformRevision,
      referenceRegion: referenceRegion
    )
  }
}

struct ActionSurface: View {
  let presentation: ActionSurfacePresentation
  private let renderDiagnostics: ActionSurfacePreviewModel?
  @Binding private var viewport: ActionSurfaceViewportState
  @Binding private var pendingDrawingPlacement: PlotterDrawingDraftCameraPlacement?
  @Binding private var pendingPointSelection: PlotterPointSelectionSubmission?
  @StateObject private var imageCache = FramePresentationImageCache()
  @StateObject private var overlayCache = ActionSurfaceOverlayContentCache()
  @State private var capReferenceRegion: AxisAlignedBounds<CameraPixelSpace>?
  @State private var drawsCapReference = true
  @State private var movesDrawing = false
  @State private var frameEditID: UUID?
  @State private var frameEditProjection: PlotterDrawingDraftProjectionReference?
  @State private var drawingDrag: DrawingFrameDrag?
  @State private var stagedFrame: PlotterDrawingDraftFrame?
  private let beginFrameEdit: (@MainActor (UUID, DisplayedFrame) async -> Bool)?
  private let endFrameEdit: (@MainActor (UUID) -> Void)?
  private let workingRegion: CalibrationWorkingRegionPresentation?
  private let beginWorkingRegionEdit: ((UUID, DisplayedFrame) -> Bool)?
  private let applyWorkingRegion: ((PlotterTipWorkingRegionEdit, AxisAlignedBounds<MachineSpace>) -> String?)?
  private let cancelWorkingRegionEdit: ((UUID) -> Void)?
  @State private var workingRegionEditID: UUID?
  @State private var stagedWorkingRegion: AxisAlignedBounds<MachineSpace>?
  @State private var workingRegionDrag: CalibrationWorkingRegionDrag?
  @State private var workingRegionRefusal: String?
  @State private var pointSelectionRefusal: String?
  @State private var priorDragTranslation: CGSize = .zero
  @State private var drawingPlacementRefusal: String?
  private let plotterUIProjection: PlotterUIProjection
  private let plotterUIIntentSink: any PlotterUIIntentSink

  init(
    presentation: ActionSurfacePresentation,
    renderDiagnostics: ActionSurfacePreviewModel? = nil,
    viewport: Binding<ActionSurfaceViewportState> = .constant(ActionSurfaceViewportState()),
    plotterUIProjection: PlotterUIProjection,
    plotterUIIntentSink: any PlotterUIIntentSink,
    pendingDrawingPlacement: Binding<PlotterDrawingDraftCameraPlacement?> = .constant(nil),
    pendingPointSelection: Binding<PlotterPointSelectionSubmission?> = .constant(nil),
    beginFrameEdit: (@MainActor (UUID, DisplayedFrame) async -> Bool)? = nil,
    endFrameEdit: (@MainActor (UUID) -> Void)? = nil,
    workingRegion: CalibrationWorkingRegionPresentation? = nil,
    beginWorkingRegionEdit: ((UUID, DisplayedFrame) -> Bool)? = nil,
    applyWorkingRegion: ((PlotterTipWorkingRegionEdit, AxisAlignedBounds<MachineSpace>) -> String?)? = nil,
    cancelWorkingRegionEdit: ((UUID) -> Void)? = nil
  ) {
    self.presentation = presentation
    self.renderDiagnostics = renderDiagnostics
    _viewport = viewport
    self.plotterUIProjection = plotterUIProjection
    self.plotterUIIntentSink = plotterUIIntentSink
    _pendingDrawingPlacement = pendingDrawingPlacement
    _pendingPointSelection = pendingPointSelection
    self.beginFrameEdit = beginFrameEdit
    self.endFrameEdit = endFrameEdit
    self.workingRegion = workingRegion
    self.beginWorkingRegionEdit = beginWorkingRegionEdit
    self.applyWorkingRegion = applyWorkingRegion
    self.cancelWorkingRegionEdit = cancelWorkingRegionEdit
  }

  var body: some View {
    let frameImage = presentation.displayedFrame.flatMap {
      imageCache.image(from: $0.frame)
    }
    let pointSelectionPendingIdentity = ActionSurfacePointSelectionPendingIdentity(
      request: presentation.pointSelectionRequest,
      viewportRevision: viewport.presentationTransformRevision
    )
    let automaticPointSubmission = ActionSurfacePointSubmissionPolicy.automaticSubmission(
      pending: pendingPointSelection,
      presentation: presentation,
      projection: plotterUIProjection
    )
    let drawingPlacementRequest = pendingDrawingPlacement.flatMap { placement in
      plotterUIProjection.request(matching: .drawingDraft(.placeAtCameraPoint(placement)))
    }
    GeometryReader { proxy in
      let transform = presentation.displayedFrame.flatMap { displayed in
        CameraPixelToViewTransform(
          frameWidth: displayed.frame.width,
          frameHeight: displayed.frame.height,
          viewWidth: proxy.size.width,
          viewHeight: proxy.size.height,
          focusRegion: viewport.visibleRegion(
            frameWidth: displayed.frame.width, frameHeight: displayed.frame.height
          )
        )
      }
      let overlayContent = overlayCache.resolve(
        ActionSurfaceOverlayContent(presentation: presentation, stagedFrame: stagedFrame, hidesCalibrationGuides: workingRegion != nil, replacesDrawingRegion: workingRegion != nil || movesDrawing), transform: transform)
      let canvas = ActionSurfaceOverlayCanvas(
        content: overlayContent,
        transform: transform,
        diagnostics: renderDiagnostics
      )
      .equatable()
      .background {
        CameraFrameLayerView(image: frameImage, imageRect: transform?.imageRect ?? .zero)
          .allowsHitTesting(false)
      }
      .clipped()
      .overlay {
        if presentation.pointSelectionRequest?.purpose == .penCapAppearance,
          presentation.pointSelectionRequest?.referenceMode != .sampledColorMarker {
          PenCapReferenceSelectionOverlay(region: capReferenceRegion, transform: transform)
            .allowsHitTesting(false)
        }
      }
      .overlay {
        if movesDrawing, presentation.showsDrawingRegion, workingRegion == nil,
          let frame = stagedFrame ?? presentation.drawingStudioCanvas?.frame,
          presentation.drawingStudioCanvas?.targetPreview(for: presentation.displayedFrame) != nil,
          let transform {
          DrawingFrameOverlay(frame: frame, transform: transform, editing: movesDrawing, staged: stagedFrame != nil)
        }
      }
      .overlay {
        if let workingRegion, let transform {
          CalibrationWorkingRegionOverlay(context: workingRegion.context,
            bounds: stagedWorkingRegion ?? workingRegion.bounds, transform: transform,
            editing: workingRegionEditID != nil, showsRegion: presentation.showsDrawingRegion)
        }
      }
      let content = canvas
      .overlay(alignment: .topLeading) { topControls(hasTargetPreview: overlayContent.targetPreview != nil) }
      .overlay(alignment: .bottomLeading) {
        VStack(alignment: .leading, spacing: 6) {
          if let prompt = presentation.tipPresentation.interactionPrompt {
            Text(presentation.pointSelectionRequest?.referenceMode == .sampledColorMarker
              ? "Click the pen cap. Drag to pan."
              : presentation.pointSelectionRequest?.purpose == .penCapAppearance
              ? (drawsCapReference
                ? "Drag a compact reference region, then click its pen-cap point."
                : (capReferenceRegion == nil
                  ? (presentation.pointSelectionRequest?.referenceGeometry == nil
                    ? "Drag to pan. Choose Draw Reference to select the tracking surface."
                    : "Click the same physical pen-cap point. Drag to pan; Draw Reference changes its appearance region.")
                  : "Click the pen-cap point inside the rectangle. Drag to pan; use Redraw Reference to change it."))
              : prompt)
              .font(.caption.monospaced().bold())
              .foregroundStyle(.white)
              .padding(7)
              .background(.black.opacity(0.72))
          }
          if presentation.pointSelectionRequest != nil,
            let refusal = pointSelectionRefusal ?? presentation.pointSelectionFailure {
            Label(refusal, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .padding(7)
              .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
          }
        }
        .padding(8)
        .allowsHitTesting(false)
      }
      .overlay(alignment: .topTrailing) {
        if overlayContent.targetPreview != nil {
          OperatorRequestButton(
            title: "Hide Drawing",
            request: plotterUIProjection.request(matching: .drawingDraft(.hideTarget)),
            unavailableReason: nil,
            sink: plotterUIIntentSink,
            nativeActionIdentifier: "drawing.hideTarget"
          )
          .help("Clear the drawing preview from the video. Keep its placement for Show Drawing.")
          .accessibilityIdentifier("drawing.hideTarget")
          .padding(8)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if presentation.completedComparisonReview.isPresentedOnCanvas {
          CompletedComparisonReviewControls(
            presentation: presentation.completedComparisonReview,
            displayedFrame: presentation.displayedFrame,
            plotterUIProjection: plotterUIProjection,
            plotterUIIntentSink: plotterUIIntentSink
          )
          .padding(8)
        }
      }
      .overlay(alignment: .bottom) {
        VStack(spacing: 6) {
          if let drawingPlacementRefusal {
            Label(drawingPlacementRefusal, systemImage: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .padding(6)
              .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 6))
          }
          if pendingDrawingPlacement != nil {
            Button("Apply Drawing Placement") {
              submitPendingDrawingPlacement()
            }
            .operatorButton(.affirmative, isEnabled: drawingPlacementRequest != nil)
            .help(
              drawingPlacementRequest == nil
                ? "Refresh the exact Drawing Studio placement before applying it."
                : "Apply the exact staged camera-frame placement."
            )
          }
        }
        .padding(8)
      }
      .overlay {
        if presentation.displayedFrame == nil {
          ContentUnavailableView(
            "No camera frame",
            systemImage: "camera.fill",
            description: Text("Select a live camera or switch to the simulator.")
          )
          .foregroundStyle(.white)
        }
      }
      content
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture(coordinateSpace: .local)
          .onEnded { value in
            stagePointSelection(at: value.location, viewSize: proxy.size)
          }
      )
      .simultaneousGesture(surfaceDragGesture(transform: transform, viewSize: proxy.size))
      .onChange(of: presentation.viewportContext, initial: true) { _, context in
        viewport.synchronize(with: context)
      }
      .onChange(of: presentation.drawingStudioCanvas == nil || overlayContent.targetPreview == nil, initial: true) { _, hidden in
        if hidden { cancelFrameEdit() }
      }
      .onChange(of: presentation.drawingStudioCanvas?.draftProjection) { _, current in
        if let origin = frameEditProjection,
          current.map({ DrawingFrameEditSession.matches(origin, $0) }) != true {
          cancelFrameEdit()
        }
      }
      .onChange(of: viewport.presentationTransformRevision) { _, _ in
        if movesDrawing { cancelFrameEdit() }
        if workingRegionEditID != nil { clearWorkingRegionEdit() }
      }
      .onChange(of: workingRegion?.context) { _, _ in clearWorkingRegionEdit() }
      .onChange(of: workingRegion?.edit?.id) { _, id in
        if let workingRegionEditID, id != workingRegionEditID { clearWorkingRegionEdit() }
      }
      .onChange(of: workingRegion == nil) { _, hidden in if hidden { clearWorkingRegionEdit() } }
      .onDisappear { cancelFrameEdit(); clearWorkingRegionEdit() }
      .onChange(of: pointSelectionPendingIdentity, initial: true) { prior, current in
        if prior.request != current.request {
          capReferenceRegion = nil
          drawsCapReference = presentation.pointSelectionRequest?.purpose == .penCapAppearance
            && presentation.pointSelectionRequest?.referenceMode != .sampledColorMarker
            && presentation.pointSelectionRequest?.referenceGeometry == nil
          cancelFrameEdit()
          pointSelectionRefusal = nil
          pendingDrawingPlacement = nil
          drawingPlacementRefusal = nil
          priorDragTranslation = .zero
        }
        guard let pendingPointSelection else { return }
        if prior.viewportRevision != current.viewportRevision
          || !presentation.acceptsPendingPointSelection(pendingPointSelection)
        {
          self.pendingPointSelection = nil
        }
      }
      .onChange(of: automaticPointSubmission) { _, submission in
        guard let submission else { return }
        // Acceptance removes the selection from the rendered canvas. The
        // application's retained submission, not this view, owns completion.
        Task { @MainActor in await submitPendingPointSelection(submission) }
      }
      .accessibilityValue(
        [
          overlayContent.analyzedOverlayFrame.map {
            "Displayed measurement from frame \($0.frameSequence)"
          },
          presentation.simulatedAnnotationsAreVisible
            ? presentation.simulatedAnnotations.map(\.accessibleValue).joined(separator: ", ")
            : "Simulator annotations hidden",
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
      )
    }
  }

  private func surfaceDragGesture(transform: CameraPixelToViewTransform?, viewSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 3, coordinateSpace: .local)
      .onChanged { value in
        if workingRegionEditID != nil {
          guard let workingRegion, let transform, let point = transform.cameraPoint(value.location) else { return }
          if workingRegionDrag == nil {
            workingRegionDrag = CalibrationWorkingRegionDrag(bounds: stagedWorkingRegion ?? workingRegion.bounds,
              context: workingRegion.context, start: value.startLocation, transform: transform)
          }
          if let bounds = try? workingRegionDrag?.updated(at: point) { stagedWorkingRegion = bounds }
          return
        }
        switch ActionSurfaceDragIntent.resolve(presentation: presentation,
          drawsReference: drawsCapReference, movesDrawing: movesDrawing) {
        case .reference:
          capReferenceRegion = PenCapReferenceSelectionGeometry.region(
            from: value.startLocation, to: value.location, transform: transform)
          pendingPointSelection = nil
          pointSelectionRefusal = nil
          return
        case .drawing:
          priorDragTranslation = .zero
          stageDrawingPlacement(from: value.startLocation, to: value.location, transform: transform)
          return
        case .locked: return
        case .pan: break
        }
        guard !presentation.analysisRegionIsLocked,
          let frame = presentation.displayedFrame?.frame
        else { return }
        let delta = CGSize(
          width: value.translation.width - priorDragTranslation.width,
          height: value.translation.height - priorDragTranslation.height
        )
        priorDragTranslation = value.translation
        viewport.pan(
          by: delta,
          viewSize: viewSize,
          frameWidth: frame.width,
          frameHeight: frame.height
        )
      }
      .onEnded { _ in
        workingRegionDrag = nil
        drawingDrag = nil
        priorDragTranslation = .zero
        if presentation.pointSelectionRequest?.purpose == .penCapAppearance, drawsCapReference {
          if capReferenceRegion != nil {
            drawsCapReference = false
          } else {
            pointSelectionRefusal = "Draw a rectangle entirely inside the camera image."
          }
        }
      }
  }

  private func topControls(hasTargetPreview: Bool) -> some View {
    let positioningReason = presentation.drawingPositioningUnavailableReason
      ?? (presentation.drawingStudioCanvas?.frame == nil ? "Select a drawing that fits the working area." : nil)
      ?? (!hasTargetPreview ? "Show a compatible drawing preview first." : nil)
    return VStack(alignment: .leading, spacing: 6) {
      workingRegionControls
      if presentation.pointSelectionRequest?.purpose == .penCapAppearance,
      presentation.pointSelectionRequest?.referenceMode != .sampledColorMarker {
        HStack {
          Button(capReferenceRegion == nil ? "Draw Reference" : "Redraw Reference") {
            drawsCapReference = true
            pointSelectionRefusal = nil
            pendingPointSelection = nil
          }
          .disabled(drawsCapReference)
          Button("Pan Video") {
            drawsCapReference = false
            pendingPointSelection = nil
          }
          .disabled(!drawsCapReference || presentation.analysisRegionIsLocked)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      } else if workingRegion == nil {
        Button(frameEditID != nil ? "Cancel Positioning" : "Position Drawing") {
          if frameEditID != nil { cancelFrameEdit() }
          else if let frame = presentation.displayedFrame, let beginFrameEdit {
            let id = UUID()
            frameEditID = id
            frameEditProjection = presentation.drawingStudioCanvas?.draftProjection
            Task { @MainActor in
              guard frameEditID == id else { return }
              let began = await beginFrameEdit(id, frame)
              guard frameEditID == id else { endFrameEdit?(id); return }
              if began {
                movesDrawing = true
                drawingPlacementRefusal = nil
              } else {
                cancelFrameEdit()
                drawingPlacementRefusal = "Show a compatible drawing preview before editing its frame."
              }
            }
          }
        }
        .disabled(frameEditID == nil && (positioningReason != nil))
        .accessibilityIdentifier("drawing.editFrame")
        .help("Drag the frame body to move. Drag a corner to resize about the center. Apply to update the drawing.")
        .buttonStyle(.bordered)
        .controlSize(.small)
        if frameEditID == nil, let reason = positioningReason {
          Text(reason).font(.caption).foregroundStyle(.white)
            .padding(6).background(.black.opacity(0.78))
        }
      }
      if movesDrawing {
        Text("Artwork positioning · frozen video")
          .font(.caption.bold()).foregroundStyle(.yellow)
          .padding(6).background(.black.opacity(0.78))
      }
      if let sourceBadgeLabel = presentation.sourceBadgeLabel {
        Text(sourceBadgeLabel)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .background(Color.blue.opacity(0.88))
      }
    }
    .padding(8)
  }

  private func stagePointSelection(at location: CGPoint, viewSize: CGSize) {
    switch ActionSurfacePointStaging.stage(
      presentation: presentation, viewport: viewport, at: location, viewSize: viewSize,
      referenceRegion: capReferenceRegion) {
    case .ignored: break
    case .refused(let remedy):
      pointSelectionRefusal = remedy
      pendingPointSelection = nil
    case .staged(let submission):
      pointSelectionRefusal = nil
      pendingPointSelection = submission
    }
  }

  private func submitPendingPointSelection(
    _ submission: PlotterPointSelectionSubmission
  ) async {
    guard pendingPointSelection == submission,
      presentation.acceptsPendingPointSelection(submission)
    else {
      if pendingPointSelection == submission {
        pendingPointSelection = nil
      }
      return
    }
    let intent = PlotterUIIntent.pointSelection(submission)
    guard let request = plotterUIProjection.request(matching: intent) else {
      pointSelectionRefusal = "The selection changed before it could be submitted. Click again on the current frozen image."
      pendingPointSelection = nil
      return
    }
    let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
    guard pendingPointSelection == submission else { return }
    if case .refused(let refusal) = disposition {
      pointSelectionRefusal = refusal.remedy
    }
    if pendingPointSelection == submission {
      pendingPointSelection = nil
    }
  }

  @ViewBuilder
  private var workingRegionControls: some View {
    if let workingRegion {
      HStack {
        if workingRegionEditID == nil {
          Button("Edit Drawing Region") {
            guard let frame = presentation.displayedFrame else { return }
            let id = UUID()
            if beginWorkingRegionEdit?(id, frame) == true {
              workingRegionEditID = id
              stagedWorkingRegion = workingRegion.bounds
              workingRegionRefusal = nil
            }
          }
          .disabled(workingRegion.unavailableReason != nil)
          .accessibilityIdentifier("learning.editWorkingRegion")
        } else {
          Button("Default") { stagedWorkingRegion = workingRegion.context.boundary }
          Button("Smaller") {
            stagedWorkingRegion = try? CalibrationWorkingRegionGeometry.smaller(stagedWorkingRegion ?? workingRegion.bounds)
          }
          .accessibilityIdentifier("learning.smallerWorkingRegion")
          .help("Shrink the staged region about its center, including when its corners are outside the video.")
          Button("Apply") {
            guard let edit = workingRegion.edit, edit.id == workingRegionEditID,
              let bounds = stagedWorkingRegion else { return }
            workingRegionRefusal = applyWorkingRegion?(edit, bounds)
            if workingRegionRefusal == nil { clearWorkingRegionEdit() }
          }.accessibilityIdentifier("learning.applyWorkingRegion")
          Button("Cancel") { clearWorkingRegionEdit() }
        }
      }.buttonStyle(.bordered).controlSize(.small)
      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 10) {
          Text("White: Machine Boundary").foregroundStyle(.white)
          Text("Yellow: Drawing Region").foregroundStyle(.yellow)
          Text("Cyan: calibration circles").foregroundStyle(.cyan)
        }
        Text("Approximate cap projection · unknown tip offset")
          .foregroundStyle(.yellow)
        if workingRegionEditID != nil {
          Text("Frozen video · drag body or corners · 10 mm center inset / 8 mm circle clearance")
            .foregroundStyle(.yellow)
        }
      }
      .font(.caption.bold()).padding(6).background(.black.opacity(0.78))
      if workingRegionEditID == nil, let reason = workingRegion.unavailableReason {
        Text(reason).font(.caption).foregroundStyle(.white)
          .padding(6).background(.black.opacity(0.78))
      }
      if workingRegion.isStale {
        Text("Selection context changed. Edit and Apply the working region again before drawing.")
          .font(.caption).foregroundStyle(.orange).padding(6).background(.black.opacity(0.78))
      }
      if let workingRegionRefusal {
        Text(workingRegionRefusal).font(.caption).foregroundStyle(.orange)
          .padding(6).background(.black.opacity(0.78))
      }
    }
  }

  private func clearWorkingRegionEdit() {
    if let id = workingRegionEditID { cancelWorkingRegionEdit?(id) }
    workingRegionEditID = nil
    stagedWorkingRegion = nil
    workingRegionDrag = nil
  }

  private func cancelFrameEdit() {
    if let id = frameEditID { endFrameEdit?(id) }
    frameEditID = nil
    frameEditProjection = nil
    movesDrawing = false
    pendingDrawingPlacement = nil
    stagedFrame = nil
    drawingDrag = nil
    priorDragTranslation = .zero
  }

  private func stageDrawingPlacement(from start: CGPoint, to location: CGPoint,
    transform: CameraPixelToViewTransform?) {
    guard let canvas = presentation.drawingStudioCanvas, canvas.placement.placementIsEnabled,
      let original = stagedFrame ?? canvas.frame, let transform,
      let point = transform.cameraPoint(location),
      let exactFrame = presentation.displayedFrame?.plotterExactFrameReferenceIfMaterialized else { return }
    if drawingDrag == nil { drawingDrag = DrawingFrameDrag(frame: original, start: start, transform: transform) }
    guard let updated = try? drawingDrag?.updated(at: point, minimumScale: canvas.placement.allowedScale.lowerBound),
      let center = try? updated.cameraCenter else { return }
    stagedFrame = updated
    pendingDrawingPlacement = PlotterDrawingDraftCameraPlacement(frame: exactFrame,
      point: center, uniformScale: updated.geometry.placement.uniformScale,
      draftRevision: canvas.draftProjection.draftRevision)
    drawingPlacementRefusal = nil
  }

  private func submitPendingDrawingPlacement() {
    guard let placement = pendingDrawingPlacement else {
      drawingPlacementRefusal = "Stage a Drawing Studio placement before applying it."
      return
    }
    let intent = PlotterDrawingDraftIntent.placeAtCameraPoint(placement)
    guard let request = plotterUIProjection.request(matching: .drawingDraft(intent)) else {
      drawingPlacementRefusal = "Refresh the exact Drawing Studio placement before applying it."
      return
    }
    Task { @MainActor in
      let disposition = await plotterUIIntentSink.submitPlotterUIRequest(request)
      if case .accepted = disposition, pendingDrawingPlacement == placement {
        drawingPlacementRefusal = nil
        cancelFrameEdit()
      } else if case .refused(let refusal) = disposition {
        drawingPlacementRefusal = refusal.remedy
      }
    }
  }


}

private extension DisplayedFrame {
  func pointSelectionSubmissionReferenceIfMaterialized(
    archiveBinding: PlotterExactFrameReference
  ) -> PlotterExactFrameReference? {
    guard let contentSHA256 = frame.materializedContentSHA256 else { return nil }
    return PlotterExactFrameReference(
      frameID: frame.id.rawValue,
      frameSHA256: contentSHA256,
      source: source.pointSelectionExactSource,
      cameraConfigurationID: frame.cameraConfigurationID,
      captureNanoseconds: frame.captureNanoseconds,
      sequence: frame.sequence,
      width: frame.width,
      height: frame.height,
      rowBytes: frame.rowBytes,
      pixelFormat: PlotterExactFramePixelFormat(rawValue: frame.pixelFormat.rawValue)!,
      archivedBytes: archiveBinding.archivedBytes,
      archivedByteLocator: archiveBinding.archivedByteLocator
    )
  }
}

extension PlotterPointSelectionRequest {
  func matchesExactDisplayedFrame(_ displayedFrame: DisplayedFrame) -> Bool {
    guard
      let displayedReference = displayedFrame.pointSelectionSubmissionReferenceIfMaterialized(
        archiveBinding: frame
      )
    else { return false }
    return frame == displayedReference
  }
}

private extension FrameSourceIdentity {
  var pointSelectionExactSource: PlotterExactFrameSource {
    switch self {
    case .live(let deviceID): .live(deviceID: deviceID.rawValue)
    case .simulated: .simulated
    }
  }
}

struct FramePresentationIdentity: Hashable, Sendable {
  let frameID: FrameID
  let cameraConfigurationID: CameraConfigurationID

  init(_ frame: StampedFrame) {
    frameID = frame.id
    cameraConfigurationID = frame.cameraConfigurationID
  }
}

/// A one-entry presentation cache. Frame identity is the evidence boundary:
/// the same frame/configuration pair denotes the same immutable canonical
/// bytes. Keeping only the current image bounds memory as live frames advance.
@MainActor
final class FramePresentationImageCache: ObservableObject {
  private var cachedIdentity: FramePresentationIdentity?
  private var cachedImage: CGImage?
  private(set) var conversionCount = 0

  var cachedEntryCount: Int { cachedIdentity == nil ? 0 : 1 }

  func image(from frame: StampedFrame) -> CGImage? {
    let identity = FramePresentationIdentity(frame)
    if identity == cachedIdentity {
      return cachedImage
    }

    let image = FrameImageFactory.image(from: frame)
    cachedIdentity = identity
    cachedImage = image
    conversionCount += 1
    return image
  }
}

enum FrameImageFactory {
  static func image(from frame: StampedFrame) -> CGImage? {
    guard let provider = CGDataProvider(data: frame.bytes.data as CFData) else {
      return nil
    }

    let colorSpace: CGColorSpace
    let bitsPerPixel: Int
    let bitmapInfo: CGBitmapInfo
    switch frame.pixelFormat {
    case .gray8:
      colorSpace = CGColorSpaceCreateDeviceGray()
      bitsPerPixel = 8
      bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    case .rgba8:
      colorSpace = CGColorSpaceCreateDeviceRGB()
      bitsPerPixel = 32
      bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        .union(.byteOrder32Big)
    case .bgra8:
      colorSpace = CGColorSpaceCreateDeviceRGB()
      bitsPerPixel = 32
      bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)
        .union(.byteOrder32Little)
    }

    return CGImage(
      width: frame.width,
      height: frame.height,
      bitsPerComponent: 8,
      bitsPerPixel: bitsPerPixel,
      bytesPerRow: frame.rowBytes,
      space: colorSpace,
      bitmapInfo: bitmapInfo,
      provider: provider,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    )
  }
}
