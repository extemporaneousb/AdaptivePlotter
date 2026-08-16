import CoreGraphics
import Foundation
import PlotterModel
import PlotterRuntime
import SwiftUI

enum ActionSurfaceScalePolicy: String, Sendable {
  case aspectFit
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

enum ActionSurfacePointSelectionPurpose: Hashable, Sendable {
  case penCapAppearance
  case toolContact
}

struct ActionSurfacePointSelectionRequest: Hashable, Sendable {
  let frame: ExactTipCalibrationFrame
  let presentationTransformRevision: PresentationTransformRevision
  let prompt: String
  let purpose: ActionSurfacePointSelectionPurpose

  init(
    frame: ExactTipCalibrationFrame,
    presentationTransformRevision: PresentationTransformRevision,
    prompt: String,
    purpose: ActionSurfacePointSelectionPurpose = .toolContact
  ) {
    self.frame = frame
    self.presentationTransformRevision = presentationTransformRevision
    self.prompt = prompt
    self.purpose = purpose
  }

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    frame.frameID == displayedFrame.frame.id
      && frame.frameSHA256 == displayedFrame.frame.contentSHA256
      && frame.source == displayedFrame.source
      && frame.cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
      && frame.width == displayedFrame.frame.width
      && frame.height == displayedFrame.frame.height
      && frame.pixelFormat == displayedFrame.frame.pixelFormat
  }
}

struct ActionSurfacePointSelection: Hashable, Sendable {
  let frame: ExactTipCalibrationFrame
  let point: Point2<CameraPixelSpace>
  let presentationTransformRevision: PresentationTransformRevision
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
      "\(clicks.count)/5 centers selected · \(prompt)"
    case .selected(_, _, _, let residual):
      residual.map { String(format: "Selection residual %.3f px", $0) }
        ?? "Mark center selected"
    case .calibrated: "Tip calibration accepted"
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

/// Associates the five clicks without treating click order as evidence. Both point
/// sets are centered before evaluating every assignment so the unknown common
/// cap-to-tip translation has no effect on the selected correspondence.
func associateSparseTipClicks(
  using registrationFit: MachineCameraRegistrationFit,
  knownMachinePositions: [SparseTipKnownMachinePosition],
  clicks: [Point2<CameraPixelSpace>]
) throws -> [SparseTipClickAssociation] {
  let canonicalPositions: [ToolContactCalibrationPosition] = [
    .center, .negativeX, .positiveY, .positiveX, .negativeY,
  ]
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
  var zoom: Double = 0 {
    didSet {
      if zoom != oldValue { presentationTransformRevision = PresentationTransformRevision() }
    }
  }

  mutating func synchronize(with context: ActionSurfaceViewportContext?) {
    guard self.context != context else { return }
    let preservesOperatorView =
      self.context.map { previous in
        guard let context else { return false }
        return previous.source == context.source
          && previous.cameraConfigurationID == context.cameraConfigurationID
          && context.preferredInitialZoom == 0
      } ?? false
    self.context = context
    if !preservesOperatorView {
      zoom = min(1, max(0, context?.preferredInitialZoom ?? 0))
      panOffsetX = 0
      panOffsetY = 0
    }
    presentationTransformRevision = PresentationTransformRevision()
  }

  mutating func showFullFrame() {
    zoom = 0
    panOffsetX = 0
    panOffsetY = 0
  }

  mutating func showFittedBounds() { zoom = 1 }

  func visibleRegion(frameWidth: Int, frameHeight: Int) -> PixelRect? {
    guard let context, frameWidth > 0, frameHeight > 0 else { return nil }
    let t = min(1, max(0, zoom))
    if t == 0 { return nil }
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
    guard scale.isFinite, scale > 0 else { return }
    let translatedX = region.x - Int((Double(translation.width) / scale).rounded())
    let translatedY = region.y - Int((Double(translation.height) / scale).rounded())
    let clampedX = min(max(0, translatedX), frameWidth - region.width)
    let clampedY = min(max(0, translatedY), frameHeight - region.height)
    let nextX = panOffsetX + clampedX - region.x
    let nextY = panOffsetY + clampedY - region.y
    guard nextX != panOffsetX || nextY != panOffsetY else { return }
    panOffsetX = nextX
    panOffsetY = nextY
    presentationTransformRevision = PresentationTransformRevision()
  }
}

struct ActionSurfacePresentation: Sendable {
  static let rendererIdentity = "canonical-stamped-frame"

  let displayedFrame: DisplayedFrame?
  let overlays: [CameraOverlayMeasurement]
  let simulatedAnnotations: [SimulatedLearningAnnotation]
  let simulatedViewportID: SimulatedCameraViewportID?
  let simulatedAnnotationsAreVisible: Bool
  let viewportContext: ActionSurfaceViewportContext?
  let analysisRegionIsLocked: Bool
  let analyzedOverlayFrame: ExactFrameOverlayProvenance?
  let pointSelectionRequest: ActionSurfacePointSelectionRequest?
  let tipPresentation: ActionSurfaceTipPresentation

  var rendererIdentity: String { Self.rendererIdentity }

  init(
    displayedFrame: DisplayedFrame?,
    overlays: [CameraOverlayMeasurement],
    simulatedAnnotations: [SimulatedLearningAnnotation] = [],
    simulatedViewportID: SimulatedCameraViewportID? = nil,
    simulatedAnnotationsAreVisible: Bool = true,
    viewportContext: ActionSurfaceViewportContext? = nil,
    analysisRegionIsLocked: Bool = false,
    analyzedOverlayFrame: ExactFrameOverlayProvenance? = nil,
    pointSelectionRequest: ActionSurfacePointSelectionRequest? = nil,
    tipPresentation: ActionSurfaceTipPresentation = .notCalibrated
  ) {
    self.displayedFrame = displayedFrame
    self.simulatedViewportID = simulatedViewportID
    self.simulatedAnnotationsAreVisible = simulatedAnnotationsAreVisible
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
        $0.matches(displayedFrame) ? $0 : nil
      }
      self.analyzedOverlayFrame = analyzedOverlayFrame.flatMap {
        $0.matches(displayedFrame) ? $0 : nil
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
  }

  var sourceBadgeLabel: String? {
    guard case .simulated = displayedFrame?.source else { return nil }
    return "SIMULATED"
  }
}

struct ActionSurface: View {
  let presentation: ActionSurfacePresentation
  @Binding private var viewport: ActionSurfaceViewportState
  @StateObject private var imageCache = FramePresentationImageCache()
  @State private var priorDragTranslation: CGSize = .zero
  private let selectPoint: (ActionSurfacePointSelection) -> Void

  init(
    presentation: ActionSurfacePresentation,
    viewport: Binding<ActionSurfaceViewportState> = .constant(ActionSurfaceViewportState()),
    selectPoint: @escaping (ActionSurfacePointSelection) -> Void = { _ in }
  ) {
    self.presentation = presentation
    _viewport = viewport
    self.selectPoint = selectPoint
  }

  var body: some View {
    let frameImage = presentation.displayedFrame.flatMap {
      imageCache.image(from: $0.frame)
    }
    GeometryReader { proxy in
      Canvas { context, size in
        guard let displayedFrame = presentation.displayedFrame,
          let visibleRegion = viewport.visibleRegion(
            frameWidth: displayedFrame.frame.width,
            frameHeight: displayedFrame.frame.height
          ),
          let transform = CameraPixelToViewTransform(
            frameWidth: displayedFrame.frame.width,
            frameHeight: displayedFrame.frame.height,
            viewWidth: size.width,
            viewHeight: size.height,
            focusRegion: visibleRegion
          )
        else {
          guard let displayedFrame = presentation.displayedFrame,
            let transform = CameraPixelToViewTransform(
              frameWidth: displayedFrame.frame.width,
              frameHeight: displayedFrame.frame.height,
              viewWidth: size.width,
              viewHeight: size.height
            )
          else { return }
          drawFrameAndOverlays(
            frameImage: frameImage,
            context: &context,
            transform: transform
          )
          return
        }

        drawFrameAndOverlays(frameImage: frameImage, context: &context, transform: transform)
      }
      .background(Color.black)
      .overlay(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 6) {
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
      .overlay(alignment: .topTrailing) {
        if let frame = presentation.displayedFrame?.frame {
          VStack(alignment: .trailing, spacing: 3) {
            Text("DISPLAYED FRAME \(frame.sequence) · \(frame.width)×\(frame.height)")
            if let analyzed = presentation.analyzedOverlayFrame {
              Text("OVERLAYS ANALYZED FROM THIS EXACT FRAME \(analyzed.frameSequence)")
            }
          }
          .font(.caption2.monospaced())
          .foregroundStyle(.white)
          .multilineTextAlignment(.trailing)
          .padding(6)
          .background(.black.opacity(0.65))
          .padding(8)
        }
      }
      .overlay(alignment: .bottomLeading) {
        Text(presentation.tipPresentation.statusText)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.white)
          .padding(7)
          .background(.black.opacity(0.72))
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
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
      .gesture(
        SpatialTapGesture(coordinateSpace: .local)
          .onEnded { value in
            submitPointSelection(at: value.location, viewSize: proxy.size)
          }
      )
      .simultaneousGesture(
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
          .onChanged { value in
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
              viewSize: proxy.size,
              frameWidth: frame.width,
              frameHeight: frame.height
            )
          }
          .onEnded { _ in priorDragTranslation = .zero }
      )
      .onChange(of: presentation.viewportContext, initial: true) { _, context in
        viewport.synchronize(with: context)
      }
      .accessibilityValue(
        [
          presentation.analyzedOverlayFrame.map {
            "Overlays analyzed from displayed exact frame \($0.frameSequence)"
          },
          presentation.simulatedAnnotationsAreVisible
            ? presentation.simulatedAnnotations.map(\.accessibleValue).joined(separator: ", ")
            : "Simulator annotations hidden",
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". ")
      )
    }
  }

  private func submitPointSelection(at location: CGPoint, viewSize: CGSize) {
    guard let displayedFrame = presentation.displayedFrame,
      let request = presentation.pointSelectionRequest,
      request.matches(displayedFrame),
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
      let point = transform.cameraPoint(location)
    else { return }
    selectPoint(
      ActionSurfacePointSelection(
        frame: request.frame,
        point: point,
        presentationTransformRevision: viewport.presentationTransformRevision
      ))
  }

  private func drawFrameAndOverlays(
    frameImage: CGImage?,
    context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    if let frameImage {
      context.draw(Image(decorative: frameImage, scale: 1), in: transform.imageRect)
    }
    for overlay in presentation.overlays {
      draw(overlay, in: &context, transform: transform)
    }
    if let review = presentation.tipPresentation.reviewGeometry {
      draw(review, in: &context, transform: transform)
    }
    for (index, click) in presentation.tipPresentation.clickMarkers.enumerated() {
      drawCollectedClick(click, ordinal: index + 1, in: &context, transform: transform)
    }
    if presentation.simulatedAnnotationsAreVisible {
      for annotation in presentation.simulatedAnnotations {
        draw(annotation, in: &context, transform: transform)
      }
    }
  }

  private func drawCollectedClick(
    _ click: Point2<CameraPixelSpace>,
    ordinal: Int,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let center = transform.point(click)
    let radius: CGFloat = 6
    context.stroke(
      Path(
        ellipseIn: CGRect(
          x: center.x - radius,
          y: center.y - radius,
          width: radius * 2,
          height: radius * 2
        )
      ),
      with: .color(.cyan),
      lineWidth: 2
    )
    context.draw(
      Text("\(ordinal)").font(.caption2.monospaced().bold()).foregroundStyle(.cyan),
      at: CGPoint(x: center.x + 10, y: center.y - 10),
      anchor: .center
    )
  }

  private func draw(
    _ review: ActionSurfaceTipReviewGeometry,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let click = transform.point(review.click)
    let uncertaintyRect = CGRect(
      x: click.x - review.pointingUncertaintyPixels.dx * transform.scale,
      y: click.y - review.pointingUncertaintyPixels.dy * transform.scale,
      width: review.pointingUncertaintyPixels.dx * transform.scale * 2,
      height: review.pointingUncertaintyPixels.dy * transform.scale * 2
    )
    context.stroke(
      Path(ellipseIn: uncertaintyRect),
      with: .color(.cyan),
      style: SwiftUI.StrokeStyle(lineWidth: 1.5, dash: [3, 2])
    )
    let crossRadius: CGFloat = 5
    var cross = Path()
    cross.move(to: CGPoint(x: click.x - crossRadius, y: click.y))
    cross.addLine(to: CGPoint(x: click.x + crossRadius, y: click.y))
    cross.move(to: CGPoint(x: click.x, y: click.y - crossRadius))
    cross.addLine(to: CGPoint(x: click.x, y: click.y + crossRadius))
    context.stroke(cross, with: .color(.cyan), lineWidth: 2)

    if let prediction = review.prediction {
      let predicted = transform.point(prediction)
      let radius: CGFloat = 5
      context.fill(
        Path(
          ellipseIn: CGRect(
            x: predicted.x - radius,
            y: predicted.y - radius,
            width: radius * 2,
            height: radius * 2
          )),
        with: .color(.purple)
      )
    }
    if let residual = review.residual {
      var path = Path()
      path.move(to: transform.point(residual.start))
      for point in residual.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      context.stroke(path, with: .color(.orange), lineWidth: 1.5)
    }
  }

  private func draw(
    _ annotation: SimulatedLearningAnnotation,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    let style = annotationStyle(for: annotation.kind)
    let stroke = SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
    switch annotation.geometry {
    case .point(let point):
      let center = transform.point(point)
      let radius = max(3, transform.scale * 1.5)
      context.stroke(
        Path(
          ellipseIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
          )),
        with: .color(style.color),
        style: stroke
      )
    case .bounds(let bounds):
      guard let min = try? Point2<CameraPixelSpace>(x: bounds.minX, y: bounds.minY),
        let max = try? Point2<CameraPixelSpace>(x: bounds.maxX, y: bounds.maxY)
      else { return }
      let minimum = transform.point(min)
      let maximum = transform.point(max)
      context.stroke(
        Path(
          CGRect(
            x: minimum.x,
            y: minimum.y,
            width: maximum.x - minimum.x,
            height: maximum.y - minimum.y
          )),
        with: .color(style.color),
        style: stroke
      )
    case .polyline(let polyline):
      var path = Path()
      path.move(to: transform.point(polyline.start))
      for point in polyline.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      context.stroke(path, with: .color(style.color), style: stroke)
    }
    context.draw(
      Text(annotation.visibleLabel)
        .font(.caption2.monospaced().bold())
        .foregroundStyle(style.color),
      at: transform.point(annotation.anchor),
      anchor: .bottomLeading
    )
  }

  private func annotationStyle(
    for kind: SimulatedLearningAnnotationKind
  ) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
    switch kind {
    case .truthEnvelope, .directionLabel:
      return (.orange, 2, [8, 5])
    case .acceptedLearnedSide, .learnedCenter:
      return (.cyan, 3, [])
    case .currentCapAnchor:
      return (.green, 2.5, [])
    case .recentMotionTrail:
      return (.white.opacity(0.75), 1.5, [3, 3])
    case .currentOperation:
      return (.red, 3, [])
    case .ink:
      return (.blue, 2, [])
    }
  }

  private func draw(
    _ overlay: CameraOverlayMeasurement,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    switch overlay.geometry {
    case let .point(point):
      let style = lineStyle(for: overlay.provenance.kind)
      let center = transform.point(point)
      let radius = max(3, transform.scale * 2)
      let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.stroke(Path(ellipseIn: rect), with: .color(style.color), lineWidth: style.width)
    case let .bounds(bounds):
      guard
        let minimumCamera = try? Point2<CameraPixelSpace>(x: bounds.minX, y: bounds.minY),
        let maximumCamera = try? Point2<CameraPixelSpace>(x: bounds.maxX, y: bounds.maxY)
      else { return }
      let minimum = transform.point(minimumCamera)
      let maximum = transform.point(maximumCamera)
      let style = lineStyle(for: overlay.provenance.kind)
      context.stroke(
        Path(
          CGRect(
            x: minimum.x,
            y: minimum.y,
            width: maximum.x - minimum.x,
            height: maximum.y - minimum.y
          )
        ),
        with: .color(style.color),
        style: SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
      )
    case let .polyline(polyline):
      var path = Path()
      path.move(to: transform.point(polyline.start))
      for point in polyline.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      let style = lineStyle(for: overlay.provenance.kind)
      context.stroke(
        path,
        with: .color(style.color),
        style: SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
      )
    }
  }

  private func lineStyle(
    for kind: CameraOverlayKind
  ) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
    switch kind {
    case .intendedPath:
      return (.cyan, 2, [])
    case .observedInk:
      return (.white, 3, [])
    case .residual:
      return (.orange, 1.5, [])
    case .penCap:
      return (.yellow, 2, [])
    case .armatureEstimate:
      return (.green, 2.5, [7, 4])
    case .diagnostic:
      return (.gray, 1.5, [3, 3])
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
