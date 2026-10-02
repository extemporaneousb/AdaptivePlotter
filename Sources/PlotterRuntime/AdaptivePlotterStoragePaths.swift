import Foundation

/// Canonical locations only. Domain stores retain their own schemas, writers,
/// validation and retention. Resolving a path never redirects a failed write.
public struct AdaptivePlotterStoragePaths: Sendable {
  public let rootDirectory: URL
  public let logsDirectory: URL

  public init(applicationSupportDirectory: URL, logsDirectory: URL? = nil) {
    rootDirectory = applicationSupportDirectory.appendingPathComponent("AdaptivePlotter", isDirectory: true)
    self.logsDirectory = (logsDirectory ?? applicationSupportDirectory.deletingLastPathComponent()
      .appendingPathComponent("Logs", isDirectory: true))
      .appendingPathComponent("AdaptivePlotter", isDirectory: true)
  }

  public static let production = Self(
    applicationSupportDirectory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
  )

  public var acceptedArtifactsDirectory: URL { directory("AcceptedArtifacts") }
  public var acceptedLearningCheckpoint: URL {
    acceptedArtifactsDirectory.appendingPathComponent("accepted-learning-path-v1.json")
  }
  public var acceptedLearningHistoryDirectory: URL {
    acceptedArtifactsDirectory.appendingPathComponent("History", isDirectory: true)
  }
  public var legacyMachineCheckpoint: URL {
    acceptedArtifactsDirectory.appendingPathComponent("accepted-machine-artifacts-v1.json")
  }
  public var legacyTipCheckpoint: URL {
    acceptedArtifactsDirectory.appendingPathComponent("accepted-tip-calibration-v1.json")
  }
  public var portraitCandidatesDirectory: URL { directory("PortraitCandidates") }
  public var drawingMaterialsDirectory: URL { directory("DrawingMaterials") }
  public var drawingEvidenceDirectory: URL { directory("DrawingEvidence") }
  public var drawingEvidenceArchive: URL {
    drawingEvidenceDirectory.appendingPathComponent("drawing-run-evidence-v1.json")
  }
  public var episodeRecordingsDirectory: URL { directory("EpisodeRecordings") }
  public var episodeArtifactsDirectory: URL { directory("EpisodeArtifacts") }
  public var machineSessionsDirectory: URL { directory("MachineSessions") }
  public var diagnosticsDirectory: URL { logsDirectory.appendingPathComponent("Diagnostics", isDirectory: true) }
  public var trackingAcquisitionsDirectory: URL {
    logsDirectory.appendingPathComponent("TrackingAcquisitions", isDirectory: true)
  }

  public func episodeRecordingDirectory(_ id: UUID) -> URL {
    episodeRecordingsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
  }
  public func episodeArtifactDirectory(_ id: UUID) -> URL {
    episodeArtifactsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
  }
  private func directory(_ name: String) -> URL { rootDirectory.appendingPathComponent(name, isDirectory: true) }
}

