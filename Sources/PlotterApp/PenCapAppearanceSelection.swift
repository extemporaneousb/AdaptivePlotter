import Foundation
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime

struct PenCapAppearanceSelection: Codable, Hashable, Sendable {
  let color: PenCapColor
  let frameID: FrameID
  let frameSHA256: String
  let source: FrameSourceIdentity
  let cameraConfigurationID: CameraConfigurationID
  let width: Int
  let height: Int
  let pixelFormat: FramePixelFormat
  let clickPoint: Point2<CameraPixelSpace>
  let usableSampleCount: Int
  let totalSampleCount: Int
  let algorithmRevision: String

  func matches(_ frame: DisplayedFrame) -> Bool {
    guard let displayedSHA256 = frame.frame.materializedContentSHA256 else {
      return false
    }
    return frameID == frame.frame.id
      && frameSHA256 == displayedSHA256
      && source == frame.source
      && cameraConfigurationID == frame.frame.cameraConfigurationID
      && width == frame.frame.width
      && height == frame.frame.height
      && pixelFormat == frame.frame.pixelFormat
  }

  var persistedLiveRejectionReason: String? {
    guard case .live = source else {
      return
        "Persisted pen-cap appearance was ignored because its source is SIMULATED. Use Identify Pen Cap on a LIVE camera frame."
    }
    guard !frameID.rawValue.isEmpty,
      frameSHA256.count == 64,
      frameSHA256.allSatisfy({ $0.isHexDigit }),
      width > 0,
      height > 0,
      pixelFormat == .rgba8 || pixelFormat == .bgra8,
      clickPoint.x >= 0,
      clickPoint.x < Double(width),
      clickPoint.y >= 0,
      clickPoint.y < Double(height),
      usableSampleCount >= PlotterPenCapPointSampler.minimumUsablePixels,
      totalSampleCount >= usableSampleCount,
      algorithmRevision == PlotterPenCapPointSampler.algorithmRevision,
      PlotterPenCapPointSampler.isUsable(
        red: color.red,
        green: color.green,
        blue: color.blue
      )
    else {
      return
        "Persisted LIVE pen-cap appearance was ignored because its exact-frame sample provenance is invalid. Use Identify Pen Cap again."
    }
    return nil
  }
}

extension PenCapAppearanceSelection {
  init(sample: PlotterAcceptedPenCapSample, frame: DisplayedFrame) {
    self.init(
      color: PenCapColor(red: sample.red, green: sample.green, blue: sample.blue),
      frameID: frame.frame.id,
      frameSHA256: frame.frame.contentSHA256,
      source: frame.source,
      cameraConfigurationID: frame.frame.cameraConfigurationID,
      width: frame.frame.width,
      height: frame.frame.height,
      pixelFormat: frame.frame.pixelFormat,
      clickPoint: sample.clickPoint,
      usableSampleCount: sample.usableSampleCount,
      totalSampleCount: sample.totalSampleCount,
      algorithmRevision: sample.algorithmRevision
    )
  }

  init(checkpoint: AcceptedPenCapAppearance) {
    self.init(
      color: checkpoint.color,
      frameID: checkpoint.frameID,
      frameSHA256: checkpoint.frameSHA256,
      source: checkpoint.source,
      cameraConfigurationID: checkpoint.cameraConfigurationID,
      width: checkpoint.width,
      height: checkpoint.height,
      pixelFormat: checkpoint.pixelFormat,
      clickPoint: checkpoint.clickPoint,
      usableSampleCount: checkpoint.usableSampleCount,
      totalSampleCount: checkpoint.totalSampleCount,
      algorithmRevision: checkpoint.algorithmRevision
    )
  }

  func acceptedCheckpoint() throws -> AcceptedPenCapAppearance {
    try AcceptedPenCapAppearance(
      color: color,
      frameID: frameID,
      frameSHA256: frameSHA256,
      source: source,
      cameraConfigurationID: cameraConfigurationID,
      width: width,
      height: height,
      pixelFormat: pixelFormat,
      clickPoint: clickPoint,
      usableSampleCount: usableSampleCount,
      totalSampleCount: totalSampleCount,
      algorithmRevision: algorithmRevision
    )
  }
}

enum PersistedPenCapAppearanceLoadState: Hashable, Sendable {
  case absent
  case accepted
  case refused(String)

  var unavailableMessage: String {
    switch self {
    case .absent, .accepted:
      "Not learned — use Identify Pen Cap before LIVE pen-cap or armature analysis."
    case .refused(let reason):
      reason
    }
  }
}
