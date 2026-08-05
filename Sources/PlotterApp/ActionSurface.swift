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

  init?(
    frameWidth: Int,
    frameHeight: Int,
    viewWidth: Double,
    viewHeight: Double,
    policy: ActionSurfaceScalePolicy = .aspectFit
  ) {
    guard frameWidth > 0, frameHeight > 0, viewWidth > 0, viewHeight > 0 else { return nil }
    let horizontalScale = viewWidth / Double(frameWidth)
    let verticalScale = viewHeight / Double(frameHeight)
    switch policy {
    case .aspectFit:
      scale = min(horizontalScale, verticalScale)
    }
    self.frameWidth = Double(frameWidth)
    self.frameHeight = Double(frameHeight)
    self.viewWidth = viewWidth
    self.viewHeight = viewHeight
    originX = (viewWidth - Double(frameWidth) * scale) / 2
    originY = (viewHeight - Double(frameHeight) * scale) / 2
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

struct ActionSurfacePresentation: Sendable {
  static let rendererIdentity = "canonical-stamped-frame"

  let displayedFrame: DisplayedFrame?
  let overlays: [CameraOverlayMeasurement]

  var rendererIdentity: String { Self.rendererIdentity }

  init(
    displayedFrame: DisplayedFrame?,
    overlays: [CameraOverlayMeasurement]
  ) {
    self.displayedFrame = displayedFrame
    if let displayedFrame {
      self.overlays = overlays.filter { $0.matches(displayedFrame) }
    } else {
      self.overlays = []
    }
  }

  var sourceLabel: String {
    guard let source = displayedFrame?.source else { return "NO SOURCE" }
    switch source {
    case .live:
      return "LIVE"
    case .simulated:
      return "SIMULATED"
    }
  }
}

struct CameraConfiguredFieldRegistration: Hashable, Sendable {
  let registration: FieldRegistration
  let cameraConfigurationID: CameraConfigurationID

  init(
    registration: FieldRegistration,
    cameraConfigurationID: CameraConfigurationID
  ) {
    self.registration = registration
    self.cameraConfigurationID = cameraConfigurationID
  }
}

enum FieldOverlayProjectionError: Error, Equatable, Sendable {
  case cameraConfigurationMismatch(
    registration: CameraConfigurationID,
    displayedFrame: CameraConfigurationID
  )
}

enum FieldOverlayProjection {
  static func overlay(
    _ fieldGeometry: Polyline<FieldSpace>,
    on displayedFrame: DisplayedFrame,
    using configuredRegistration: CameraConfiguredFieldRegistration,
    operation: String,
    algorithmRevision: String
  ) throws -> CameraOverlayMeasurement {
    guard
      configuredRegistration.cameraConfigurationID
        == displayedFrame.frame.cameraConfigurationID
    else {
      throw FieldOverlayProjectionError.cameraConfigurationMismatch(
        registration: configuredRegistration.cameraConfigurationID,
        displayedFrame: displayedFrame.frame.cameraConfigurationID
      )
    }
    let cameraGeometry = try Polyline<CameraPixelSpace>(
      points: fieldGeometry.points.map {
        try configuredRegistration.registration.cameraPoint(from: $0)
      }
    )
    return CameraOverlayMeasurement(
      frameID: displayedFrame.frame.id,
      cameraConfigurationID: displayedFrame.frame.cameraConfigurationID,
      geometry: .polyline(cameraGeometry),
      provenance: CameraMeasurementProvenance(
        operation: operation,
        algorithmRevision: algorithmRevision
      )
    )
  }
}

struct ActionSurface: View {
  let presentation: ActionSurfacePresentation
  @StateObject private var imageCache = FramePresentationImageCache()

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
            viewHeight: size.height
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
      }
      .background(Color.black)
      .overlay(alignment: .topLeading) {
        Text(presentation.sourceLabel)
          .font(.caption.monospaced().bold())
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .padding(.vertical, 6)
          .background(sourceColor.opacity(0.88))
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
    }
  }

  private var sourceColor: Color {
    guard let source = presentation.displayedFrame?.source else { return .gray }
    switch source {
    case .live: return Color.red
    case .simulated: return Color.blue
    }
  }

  private func draw(
    _ overlay: CameraOverlayMeasurement,
    in context: inout GraphicsContext,
    transform: CameraPixelToViewTransform
  ) {
    switch overlay.geometry {
    case let .point(point):
      let center = transform.point(point)
      let radius = max(3, transform.scale * 2)
      let rect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.stroke(Path(ellipseIn: rect), with: .color(.orange), lineWidth: 2)
    case let .bounds(bounds):
      guard
        let minimumCamera = try? Point2<CameraPixelSpace>(x: bounds.minX, y: bounds.minY),
        let maximumCamera = try? Point2<CameraPixelSpace>(x: bounds.maxX, y: bounds.maxY)
      else { return }
      let minimum = transform.point(minimumCamera)
      let maximum = transform.point(maximumCamera)
      context.stroke(
        Path(
          CGRect(
            x: minimum.x,
            y: minimum.y,
            width: maximum.x - minimum.x,
            height: maximum.y - minimum.y
          )
        ),
        with: .color(.yellow),
        lineWidth: 2
      )
    case let .polyline(polyline):
      var path = Path()
      path.move(to: transform.point(polyline.start))
      for point in polyline.points.dropFirst() {
        path.addLine(to: transform.point(point))
      }
      let style = lineStyle(for: overlay.provenance.operation)
      context.stroke(
        path,
        with: .color(style.color),
        style: SwiftUI.StrokeStyle(lineWidth: style.width, dash: style.dash)
      )
    }
  }

  private func lineStyle(for operation: String) -> (color: Color, width: CGFloat, dash: [CGFloat]) {
    switch operation {
    case CanvasLayer.logical.operationName:
      return (.cyan, 2, [])
    case CanvasLayer.predicted.operationName:
      return (.purple, 2, [8, 5])
    case CanvasLayer.observed.operationName:
      return (.white, 3, [])
    case CanvasLayer.residuals.operationName:
      return (.orange, 1.5, [])
    case CanvasLayer.frameSides.operationName:
      return (.blue, 2.5, [])
    default:
      return (.green, 2, [])
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
