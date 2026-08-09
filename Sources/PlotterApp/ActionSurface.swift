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
    let requestedRect = focusRegion.map {
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
}

struct ActionSurfaceFocus: Hashable, Sendable {
  let frameID: FrameID
  let cameraConfigurationID: CameraConfigurationID
  let region: PixelRect
  let label: String

  func matches(_ displayedFrame: DisplayedFrame) -> Bool {
    frameID == displayedFrame.frame.id
      && cameraConfigurationID == displayedFrame.frame.cameraConfigurationID
  }
}

struct ActionSurfacePresentation: Sendable {
  static let rendererIdentity = "canonical-stamped-frame"

  let displayedFrame: DisplayedFrame?
  let overlays: [CameraOverlayMeasurement]
  let simulatedAnnotations: [SimulatedLearningAnnotation]
  let simulatedViewportID: SimulatedCameraViewportID?
  let simulatedAnnotationsAreVisible: Bool
  let focus: ActionSurfaceFocus?

  var rendererIdentity: String { Self.rendererIdentity }

  init(
    displayedFrame: DisplayedFrame?,
    overlays: [CameraOverlayMeasurement],
    simulatedAnnotations: [SimulatedLearningAnnotation] = [],
    simulatedViewportID: SimulatedCameraViewportID? = nil,
    simulatedAnnotationsAreVisible: Bool = true,
    focus: ActionSurfaceFocus? = nil
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
      self.focus = focus.flatMap { $0.matches(displayedFrame) ? $0 : nil }
    } else {
      self.overlays = []
      self.simulatedAnnotations = []
      self.focus = nil
    }
  }

  var sourceBadgeLabel: String? {
    guard case .simulated = displayedFrame?.source else { return nil }
    return "SIMULATED"
  }
}

struct ActionSurface: View {
  let presentation: ActionSurfacePresentation
  @StateObject private var imageCache = FramePresentationImageCache()
  @State private var simulatedAnnotationsAreVisible = true
  @State private var showsFullFrame = false

  var body: some View {
    let frameImage = presentation.displayedFrame.flatMap {
      imageCache.image(from: $0.frame)
    }
    GeometryReader { proxy in
      Canvas { context, size in
        guard
          let displayedFrame = presentation.displayedFrame,
          let transform = CameraPixelToViewTransform(
            frameWidth: displayedFrame.frame.width,
            frameHeight: displayedFrame.frame.height,
            viewWidth: size.width,
            viewHeight: size.height,
            focusRegion: showsFullFrame ? nil : presentation.focus?.region
          )
        else { return }

        if let frameImage {
          context.draw(
            Image(decorative: frameImage, scale: 1),
            in: transform.imageRect
          )
        }

        for overlay in presentation.overlays {
          draw(overlay, in: &context, transform: transform)
        }
        if simulatedAnnotationsAreVisible {
          for annotation in presentation.simulatedAnnotations {
            draw(annotation, in: &context, transform: transform)
          }
        }
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
          if !presentation.simulatedAnnotations.isEmpty {
            Button(
              simulatedAnnotationsAreVisible
                ? "Hide Simulator Annotations" : "Show Simulator Annotations"
            ) {
              simulatedAnnotationsAreVisible.toggle()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityValue(
              simulatedAnnotationsAreVisible ? "Visible" : "Hidden"
            )
          }
          if let focus = presentation.focus {
            Button(showsFullFrame ? "Show Target ROI" : "Show Full Frame") {
              showsFullFrame.toggle()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .help(
              showsFullFrame
                ? "Magnify the exact target ROI for this frame"
                : "Show the complete exact camera frame without changing Vision's ROI"
            )
            Text(
              showsFullFrame
                ? "FULL FRAME · \(focus.label) available"
                : "TARGET ROI \(focus.region.width)x\(focus.region.height) · \(focus.label)"
            )
            .font(.caption2.monospaced().bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.black.opacity(0.7))
          }
        }
        .padding(8)
      }
      .overlay(alignment: .topTrailing) {
        if let frame = presentation.displayedFrame?.frame {
          Text("FRAME \(frame.sequence) · \(frame.width)×\(frame.height)")
            .font(.caption2.monospaced())
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.65))
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
      .onChange(of: presentation.focus) { _, _ in
        showsFullFrame = false
      }
      .accessibilityValue(
        simulatedAnnotationsAreVisible
          ? presentation.simulatedAnnotations.map(\.accessibleValue).joined(separator: ", ")
          : "Simulator annotations hidden"
      )
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
        Path(ellipseIn: CGRect(
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
        Path(CGRect(
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
    case .currentContact:
      return (.green, 2.5, [])
    case .recentMotionTrail:
      return (.white.opacity(0.75), 1.5, [3, 3])
    case .currentOperation:
      return (.red, 3, [])
    case .targetROI:
      return (.yellow, 2.5, [6, 3])
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
    case .modelPrediction:
      return (.purple, 2, [8, 5])
    case .observedInk:
      return (.white, 3, [])
    case .residual:
      return (.orange, 1.5, [])
    case .measuredFrameSide:
      return (.blue, 2.5, [])
    case .drawingFrameEstimate:
      return (.cyan, 2, [10, 5])
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
