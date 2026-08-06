import Foundation
import PlotterModel

public enum OnlineJogResponseError: Error, Hashable, Sendable {
  case invalidAlgorithmRevision
  case duplicateEpisodeID(String)
  case cameraConfigurationMismatch(
    expected: CameraConfigurationID,
    actual: CameraConfigurationID
  )
  case algorithmRevisionMismatch(expected: String, actual: String)
  case episodeAlgorithmRevisionChanged(before: String, after: String)
  case invalidCameraProvenance(String)
  case invalidActualControllerDelta(String)
  case invalidCameraDelta(String)
  case insufficientTrainingEpisodes(required: Int, actual: Int)
  case rankDeficientTrainingGeometry
  case nonFiniteCandidate
}

public struct OnlineJogResponseDatasetSummary: Hashable, Sendable {
  public let episodeCount: Int
  public let trainingCount: Int
  public let holdoutCount: Int
  public let episodeIDs: [String]
  public let trainingEpisodeIDs: [String]
  public let holdoutEpisodeIDs: [String]

  public init(
    episodeCount: Int,
    trainingCount: Int,
    holdoutCount: Int,
    episodeIDs: [String],
    trainingEpisodeIDs: [String],
    holdoutEpisodeIDs: [String]
  ) {
    self.episodeCount = episodeCount
    self.trainingCount = trainingCount
    self.holdoutCount = holdoutCount
    self.episodeIDs = episodeIDs
    self.trainingEpisodeIDs = trainingEpisodeIDs
    self.holdoutEpisodeIDs = holdoutEpisodeIDs
  }
}

/// A through-origin local response map:
///
///     cameraDelta = matrix * actualMachineDelta
///
/// Coefficients are diagnostic pixel response per millimeter. This value has
/// no inverse, command, acceptance, or promotion API.
public struct JogResponseMatrix: Hashable, Sendable {
  public let cameraXPerMachineX: Double
  public let cameraXPerMachineY: Double
  public let cameraYPerMachineX: Double
  public let cameraYPerMachineY: Double

  public init(
    cameraXPerMachineX: Double,
    cameraXPerMachineY: Double,
    cameraYPerMachineX: Double,
    cameraYPerMachineY: Double
  ) throws {
    guard cameraXPerMachineX.isFinite, cameraXPerMachineY.isFinite,
      cameraYPerMachineX.isFinite, cameraYPerMachineY.isFinite
    else {
      throw OnlineJogResponseError.nonFiniteCandidate
    }
    self.cameraXPerMachineX = cameraXPerMachineX
    self.cameraXPerMachineY = cameraXPerMachineY
    self.cameraYPerMachineX = cameraYPerMachineX
    self.cameraYPerMachineY = cameraYPerMachineY
  }

  public func cameraDelta(
    for actualMachineDelta: Vector2<MachineSpace>
  ) throws -> Vector2<CameraPixelSpace> {
    try Vector2(
      dx: cameraXPerMachineX * actualMachineDelta.dx
        + cameraXPerMachineY * actualMachineDelta.dy,
      dy: cameraYPerMachineX * actualMachineDelta.dx
        + cameraYPerMachineY * actualMachineDelta.dy
    )
  }
}

public struct JogResponseResidualMetrics: Hashable, Sendable {
  public let episodeCount: Int
  public let rootMeanSquarePixels: Double
  public let maximumPixels: Double

  public init(
    episodeCount: Int,
    rootMeanSquarePixels: Double,
    maximumPixels: Double
  ) {
    self.episodeCount = episodeCount
    self.rootMeanSquarePixels = rootMeanSquarePixels
    self.maximumPixels = maximumPixels
  }
}

/// A diagnostic proposal derived from the current in-memory episode set.
/// It cannot be accepted as motion or drawing authority.
public struct JogResponseCandidate: Hashable, Sendable {
  public let matrix: JogResponseMatrix
  public let trainingMetrics: JogResponseResidualMetrics
  public let holdoutMetrics: JogResponseResidualMetrics?

  public init(
    matrix: JogResponseMatrix,
    trainingMetrics: JogResponseResidualMetrics,
    holdoutMetrics: JogResponseResidualMetrics?
  ) {
    self.matrix = matrix
    self.trainingMetrics = trainingMetrics
    self.holdoutMetrics = holdoutMetrics
  }
}

/// Current-session, diagnostic-only physical jog response episodes. The
/// dataset is pinned to one physical camera configuration and one deterministic
/// vision revision, and deliberately has no encoding or persistence surface.
public struct OnlineJogResponseDataset: Sendable {
  public let cameraConfigurationID: CameraConfigurationID
  public let algorithmRevision: String
  public private(set) var episodes: [PhysicalJogObservation]

  private var episodeIDs: Set<String>

  public init(
    cameraConfigurationID: CameraConfigurationID,
    algorithmRevision: String
  ) throws {
    let revision = algorithmRevision.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !revision.isEmpty else {
      throw OnlineJogResponseError.invalidAlgorithmRevision
    }
    self.cameraConfigurationID = cameraConfigurationID
    self.algorithmRevision = algorithmRevision
    episodes = []
    episodeIDs = []
  }

  public var summary: OnlineJogResponseDatasetSummary {
    let training = episodes.filter { $0.request.split == .training }
    let holdout = episodes.filter { $0.request.split == .holdout }
    return OnlineJogResponseDatasetSummary(
      episodeCount: episodes.count,
      trainingCount: training.count,
      holdoutCount: holdout.count,
      episodeIDs: episodes.map(\.observationID),
      trainingEpisodeIDs: training.map(\.observationID),
      holdoutEpisodeIDs: holdout.map(\.observationID)
    )
  }

  public mutating func record(_ episode: PhysicalJogObservation) throws {
    guard !episodeIDs.contains(episode.observationID) else {
      throw OnlineJogResponseError.duplicateEpisodeID(episode.observationID)
    }
    guard episode.before.cameraConfigurationID == cameraConfigurationID else {
      throw OnlineJogResponseError.cameraConfigurationMismatch(
        expected: cameraConfigurationID,
        actual: episode.before.cameraConfigurationID
      )
    }
    guard episode.after.cameraConfigurationID == cameraConfigurationID else {
      throw OnlineJogResponseError.cameraConfigurationMismatch(
        expected: cameraConfigurationID,
        actual: episode.after.cameraConfigurationID
      )
    }
    guard episode.before.algorithmRevision == episode.after.algorithmRevision else {
      throw OnlineJogResponseError.episodeAlgorithmRevisionChanged(
        before: episode.before.algorithmRevision,
        after: episode.after.algorithmRevision
      )
    }
    guard episode.before.algorithmRevision == algorithmRevision else {
      throw OnlineJogResponseError.algorithmRevisionMismatch(
        expected: algorithmRevision,
        actual: episode.before.algorithmRevision
      )
    }
    guard Self.hasValidCameraProvenance(episode) else {
      throw OnlineJogResponseError.invalidCameraProvenance(episode.observationID)
    }
    _ = try Self.actualMachineDelta(for: episode)
    _ = try Self.measuredCameraDelta(for: episode)

    episodes.append(episode)
    episodeIDs.insert(episode.observationID)
  }

  public func proposeCandidate() throws -> JogResponseCandidate {
    let training = episodes.filter { $0.request.split == .training }
    guard training.count >= 2 else {
      throw OnlineJogResponseError.insufficientTrainingEpisodes(
        required: 2,
        actual: training.count
      )
    }

    let samples = try training.map(Self.sample)
    let xx = samples.reduce(0) { $0 + $1.machine.dx * $1.machine.dx }
    let xy = samples.reduce(0) { $0 + $1.machine.dx * $1.machine.dy }
    let yy = samples.reduce(0) { $0 + $1.machine.dy * $1.machine.dy }
    let determinant = xx * yy - xy * xy
    let scale = max(max(xx, yy), 1)
    guard determinant.isFinite, determinant > scale * scale * 1e-12 else {
      throw OnlineJogResponseError.rankDeficientTrainingGeometry
    }

    let cameraXX = samples.reduce(0) { $0 + $1.camera.dx * $1.machine.dx }
    let cameraXY = samples.reduce(0) { $0 + $1.camera.dx * $1.machine.dy }
    let cameraYX = samples.reduce(0) { $0 + $1.camera.dy * $1.machine.dx }
    let cameraYY = samples.reduce(0) { $0 + $1.camera.dy * $1.machine.dy }
    let matrix = try JogResponseMatrix(
      cameraXPerMachineX: (cameraXX * yy - cameraXY * xy) / determinant,
      cameraXPerMachineY: (cameraXY * xx - cameraXX * xy) / determinant,
      cameraYPerMachineX: (cameraYX * yy - cameraYY * xy) / determinant,
      cameraYPerMachineY: (cameraYY * xx - cameraYX * xy) / determinant
    )
    let holdout = episodes.filter { $0.request.split == .holdout }
    return JogResponseCandidate(
      matrix: matrix,
      trainingMetrics: try Self.metrics(for: training, matrix: matrix),
      holdoutMetrics: holdout.isEmpty ? nil : try Self.metrics(for: holdout, matrix: matrix)
    )
  }

  private static func sample(
    _ episode: PhysicalJogObservation
  ) throws -> (machine: Vector2<MachineSpace>, camera: Vector2<CameraPixelSpace>) {
    (
      machine: try actualMachineDelta(for: episode),
      camera: try measuredCameraDelta(for: episode)
    )
  }

  private static func actualMachineDelta(
    for episode: PhysicalJogObservation
  ) throws -> Vector2<MachineSpace> {
    let dx = episode.finalPosition.point.x - episode.startPosition.point.x
    let dy = episode.finalPosition.point.y - episode.startPosition.point.y
    guard dx.isFinite, dy.isFinite, dx != 0 || dy != 0 else {
      throw OnlineJogResponseError.invalidActualControllerDelta(episode.observationID)
    }
    do {
      return try Vector2(dx: dx, dy: dy)
    } catch {
      throw OnlineJogResponseError.invalidActualControllerDelta(episode.observationID)
    }
  }

  private static func measuredCameraDelta(
    for episode: PhysicalJogObservation
  ) throws -> Vector2<CameraPixelSpace> {
    do {
      return try episode.before.capCentroid.vector(to: episode.after.capCentroid)
    } catch {
      throw OnlineJogResponseError.invalidCameraDelta(episode.observationID)
    }
  }

  private static func metrics(
    for episodes: [PhysicalJogObservation],
    matrix: JogResponseMatrix
  ) throws -> JogResponseResidualMetrics {
    let residuals = try episodes.map { episode in
      let sample = try sample(episode)
      let predicted: Vector2<CameraPixelSpace>
      do {
        predicted = try matrix.cameraDelta(for: sample.machine)
      } catch {
        throw OnlineJogResponseError.nonFiniteCandidate
      }
      return hypot(
        predicted.dx - sample.camera.dx,
        predicted.dy - sample.camera.dy
      )
    }
    guard residuals.allSatisfy(\.isFinite) else {
      throw OnlineJogResponseError.nonFiniteCandidate
    }
    let squaredSum = residuals.reduce(0) { $0 + $1 * $1 }
    guard squaredSum.isFinite else {
      throw OnlineJogResponseError.nonFiniteCandidate
    }
    return JogResponseResidualMetrics(
      episodeCount: residuals.count,
      rootMeanSquarePixels: sqrt(squaredSum / Double(residuals.count)),
      maximumPixels: residuals.max() ?? 0
    )
  }

  private static func hasValidCameraProvenance(
    _ episode: PhysicalJogObservation
  ) -> Bool {
    let observations = [episode.before, episode.after]
    return episode.before.frameID != episode.after.frameID
      && episode.after.captureNanoseconds > episode.before.captureNanoseconds
      && observations.allSatisfy { observation in
        !observation.frameID.rawValue.isEmpty
          && observation.captureNanoseconds > 0
          && isSHA256(observation.frameSHA256)
          && observation.capConfidence.isFinite
          && (0...1).contains(observation.capConfidence)
          && !observation.algorithmRevision.isEmpty
      }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.utf8.count == 64
      && value.utf8.allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 97 && $0 <= 102)
      }
  }
}
