import CoreGraphics
import Foundation
import PlotterModel
import PlotterRuntime
import SwiftUI

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
    focusRegion: PixelRect? = nil
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
    scale = min(horizontalScale, verticalScale)
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
  case awaitingClick
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
    case .awaitingClick: "Awaiting exact-frame click"
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
}

struct ActionSurfaceTipReviewGeometry: Hashable, Sendable {
  let click: Point2<CameraPixelSpace>
  let pointingUncertaintyPixels: Vector2<CameraPixelSpace>
  let prediction: Point2<CameraPixelSpace>?
  let residual: Polyline<CameraPixelSpace>?
}

/// Stable presentation identity for optional fitted plotter bounds. Exact
/// frame identity deliberately does not participate: zoom is presentation only.
struct ActionSurfaceViewportContext: Hashable, Sendable {
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let fittedRegion: PixelRect?
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

struct ActionSurfacePresentation: Sendable {
  let displayedFrame: DisplayedFrame?
  let overlays: [CameraOverlayMeasurement]
  let simulatedAnnotations: [SimulatedLearningAnnotation]
  let viewportContext: ActionSurfaceViewportContext?
  let pointSelectionRequest: ActionSurfacePointSelectionRequest?
  let tipPresentation: ActionSurfaceTipPresentation

  init(
    displayedFrame: DisplayedFrame?,
    overlays: [CameraOverlayMeasurement],
    simulatedAnnotations: [SimulatedLearningAnnotation] = [],
    simulatedViewportID: SimulatedCameraViewportID? = nil,
    simulatedAnnotationsAreVisible: Bool = true,
    viewportContext: ActionSurfaceViewportContext? = nil,
    pointSelectionRequest: ActionSurfacePointSelectionRequest? = nil,
    tipPresentation: ActionSurfaceTipPresentation = .notCalibrated
  ) {
    self.displayedFrame = displayedFrame
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
    } else {
      self.overlays = []
      self.simulatedAnnotations = []
      self.viewportContext = nil
      self.pointSelectionRequest = nil
    }
    self.tipPresentation = tipPresentation
  }

  var sourceBadgeLabel: String? {
    guard case .simulated = displayedFrame?.source else { return nil }
    return "SIMULATED"
  }

  var simulatedAnnotationAccessibilityValues: [String] {
    var seen = Set<String>()
    return simulatedAnnotations.compactMap { annotation in
      let value = annotation.accessibleValue.trimmingCharacters(
        in: .whitespacesAndNewlines
      )
      guard !value.isEmpty, seen.insert(value).inserted else { return nil }
      return value
    }
  }
}

struct ActionSurface: View {
  let presentation: ActionSurfacePresentation
  let videoPreferences: VideoPresentationPreferences
  @StateObject private var imageCache = FramePresentationImageCache()
  @State private var priorDragTranslation: CGSize = .zero
  private let selectPoint: (ActionSurfacePointSelection) -> Void

  init(
    presentation: ActionSurfacePresentation,
    videoPreferences: VideoPresentationPreferences,
    selectPoint: @escaping (ActionSurfacePointSelection) -> Void = { _ in }
  ) {
    self.presentation = presentation
    self.videoPreferences = videoPreferences
    self.selectPoint = selectPoint
  }

  var body: some View {
    let frameImage = presentation.displayedFrame.flatMap {
      imageCache.image(from: $0.frame)
    }
    GeometryReader { proxy in
      Canvas { context, size in
        guard let displayedFrame = presentation.displayedFrame,
          let visibleRegion = videoPreferences.visibleRect(
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
        if let displayedFrame = presentation.displayedFrame,
          videoPreferences.isAnalysisLocked(to: displayedFrame)
        {
          Label("VIEW LOCKED", systemImage: "lock.fill")
            .font(.caption.monospaced().bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.black.opacity(0.65))
            .padding(8)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if let prompt = presentation.pointSelectionRequest?.prompt {
          Label(prompt, systemImage: "cursorarrow.click.2")
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 6))
            .padding(8)
        }
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
            guard !videoPreferences.analysisIsLocked,
              let frame = presentation.displayedFrame?.frame
            else { return }
            let delta = CGSize(
              width: value.translation.width - priorDragTranslation.width,
              height: value.translation.height - priorDragTranslation.height
            )
            priorDragTranslation = value.translation
            videoPreferences.pan(
              by: delta,
              viewSize: proxy.size,
              frameWidth: frame.width,
              frameHeight: frame.height
            )
          }
          .onEnded { _ in priorDragTranslation = .zero }
      )
      .onChange(of: presentation.viewportContext, initial: true) { _, context in
        videoPreferences.synchronize(with: context)
      }
      .accessibilityValue(
        (
          [
            presentation.sourceBadgeLabel,
            presentation.pointSelectionRequest?.prompt,
            videoPreferences.analysisIsLocked ? "View locked" : nil,
          ].compactMap { $0 }.filter { !$0.isEmpty }
            + presentation.simulatedAnnotationAccessibilityValues
        ).joined(separator: ". ")
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
        focusRegion: videoPreferences.visibleRect(
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
        presentationTransformRevision: videoPreferences.presentationTransformRevision
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
    for annotation in presentation.simulatedAnnotations {
      draw(annotation, in: &context, transform: transform)
    }
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
