import CoreGraphics
import Observation
import PlotterModel
import PlotterRuntime

struct VideoViewportIdentity: Hashable, Sendable {
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID

  init(source: FrameSourceIdentity, cameraConfigurationID: CameraConfigurationID) {
    self.source = source
    self.cameraConfigurationID = cameraConfigurationID
  }

  init(_ context: ActionSurfaceViewportContext) {
    self.init(
      source: context.source,
      cameraConfigurationID: context.cameraConfigurationID
    )
  }

  init(_ frame: DisplayedFrame) {
    self.init(
      source: frame.source,
      cameraConfigurationID: frame.frame.cameraConfigurationID
    )
  }

  func matches(_ frame: DisplayedFrame) -> Bool {
    source == frame.source
      && cameraConfigurationID == frame.frame.cameraConfigurationID
  }
}

struct VideoViewportBasis: Hashable, Sendable {
  let identity: VideoViewportIdentity
  let fittedRegion: PixelRect?
}

/// The single operator-owned video preference object shared by the window,
/// Action Surface, and inspectors. Workflow projections may update the fit
/// suggestion, but only an explicit operator action can make that suggestion
/// the viewport basis.
@MainActor
@Observable
final class VideoPresentationPreferences {
  private(set) var viewportBasis: VideoViewportBasis?
  private(set) var fitSuggestion: PixelRect?
  private(set) var zoom: Double = 0
  private(set) var panOffsetX = 0
  private(set) var panOffsetY = 0
  private(set) var presentationTransformRevision = PresentationTransformRevision()
  private(set) var lockedAnalysisRegion: VideoAnalysisRegionLock?
  private(set) var cadence: VisionAnalysisCadence
  private(set) var overlayPreferenceState: OverlayPreferenceState

  var enabledOverlays: Set<UserSceneOverlay> { overlayPreferenceState.enabled }

  init(
    cadence: VisionAnalysisCadence = .twoFPS,
    enabledOverlays: Set<UserSceneOverlay> = Set(UserSceneOverlay.allCases)
  ) {
    self.cadence = cadence
    overlayPreferenceState = .loaded(enabledOverlays)
  }

  var analysisROI: PixelRect? { lockedAnalysisRegion?.region }
  var analysisIsLocked: Bool { lockedAnalysisRegion != nil }

  /// Source/configuration identity is the only automatic geometry reset. A
  /// changed Learning step or fitted region merely refreshes the suggestion.
  func synchronize(with context: ActionSurfaceViewportContext?) {
    guard let context else { return }
    let identity = VideoViewportIdentity(context)
    fitSuggestion = context.fittedRegion
    guard viewportBasis?.identity != identity else { return }

    viewportBasis = VideoViewportBasis(identity: identity, fittedRegion: nil)
    zoom = 0
    panOffsetX = 0
    panOffsetY = 0
    lockedAnalysisRegion = nil
    presentationTransformRevision = PresentationTransformRevision()
  }

  func setZoom(_ requestedZoom: Double) {
    guard !analysisIsLocked else { return }
    let next = min(1, max(0, requestedZoom.isFinite ? requestedZoom : 0))
    guard next != zoom else { return }
    zoom = next
    presentationTransformRevision = PresentationTransformRevision()
  }

  func showFullFrame() {
    guard !analysisIsLocked else { return }
    guard zoom != 0 || panOffsetX != 0 || panOffsetY != 0 else { return }
    zoom = 0
    panOffsetX = 0
    panOffsetY = 0
    presentationTransformRevision = PresentationTransformRevision()
  }

  /// Applies the latest workflow-derived bounds only because the operator
  /// explicitly requested Fit. Later workflow changes cannot move this basis.
  func fitCurrentSuggestion() {
    guard !analysisIsLocked, let identity = viewportBasis?.identity else { return }
    viewportBasis = VideoViewportBasis(identity: identity, fittedRegion: fitSuggestion)
    zoom = 1
    panOffsetX = 0
    panOffsetY = 0
    presentationTransformRevision = PresentationTransformRevision()
  }

  func visibleRect(frameWidth: Int, frameHeight: Int) -> PixelRect? {
    guard frameWidth > 0, frameHeight > 0 else { return nil }
    let fullFrame = PixelRect(x: 0, y: 0, width: frameWidth, height: frameHeight)
    if let locked = lockedAnalysisRegion?.region {
      return cameraFrameIntersection(locked, frameWidth: frameWidth, frameHeight: frameHeight)
    }

    let t = min(1, max(0, zoom))
    guard t > 0 else { return fullFrame }
    let requested =
      viewportBasis?.fittedRegion
      ?? PixelRect(
        x: frameWidth / 4,
        y: frameHeight / 4,
        width: max(1, frameWidth / 2),
        height: max(1, frameHeight / 2)
      )
    guard
      let fitted = cameraFrameIntersection(
        requested,
        frameWidth: frameWidth,
        frameHeight: frameHeight
      )
    else { return fullFrame }

    let x = Int((Double(fitted.x) * t).rounded())
    let y = Int((Double(fitted.y) * t).rounded())
    let width = max(1, Int((Double(frameWidth) + Double(fitted.width - frameWidth) * t).rounded()))
    let height = max(
      1,
      Int((Double(frameHeight) + Double(fitted.height - frameHeight) * t).rounded())
    )
    let clampedWidth = min(width, frameWidth)
    let clampedHeight = min(height, frameHeight)
    let clampedX = min(max(0, x + panOffsetX), frameWidth - clampedWidth)
    let clampedY = min(max(0, y + panOffsetY), frameHeight - clampedHeight)
    return PixelRect(
      x: clampedX,
      y: clampedY,
      width: clampedWidth,
      height: clampedHeight
    )
  }

  func pan(
    by translation: CGSize,
    viewSize: CGSize,
    frameWidth: Int,
    frameHeight: Int
  ) {
    guard !analysisIsLocked, zoom > 0,
      let region = visibleRect(frameWidth: frameWidth, frameHeight: frameHeight),
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

  /// Captures the current cropped viewport as the analysis ROI. Merely zooming
  /// never produces a backend ROI, and full-frame cannot be represented as a
  /// misleading lock.
  @discardableResult
  func lockVisibleRect(for frame: DisplayedFrame) -> PixelRect? {
    guard viewportBasis?.identity.matches(frame) == true,
      let visible = visibleRect(
        frameWidth: frame.frame.width,
        frameHeight: frame.frame.height
      )
    else { return nil }
    let fullFrame = PixelRect(
      x: 0,
      y: 0,
      width: frame.frame.width,
      height: frame.frame.height
    )
    guard visible != fullFrame else { return nil }
    lockedAnalysisRegion = VideoAnalysisRegionLock(
      source: frame.source,
      cameraConfigurationID: frame.frame.cameraConfigurationID,
      region: visible
    )
    return visible
  }

  /// Clears analysis admission without changing the operator's visible view.
  func unlockAnalysisROI() {
    lockedAnalysisRegion = nil
  }

  func isAnalysisLocked(to frame: DisplayedFrame) -> Bool {
    lockedAnalysisRegion?.matches(frame) == true
  }

  func selectCadence(_ cadence: VisionAnalysisCadence) {
    self.cadence = cadence
  }

  func setOverlay(_ overlay: UserSceneOverlay, enabled: Bool) {
    overlayPreferenceState.applyOperatorSelection(overlay, enabled: enabled)
  }
}
