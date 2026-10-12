import Foundation
import Observation
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI

@Observable @MainActor
final class PortraitStudioArtistModel {
  private(set) var availability = SwiftSketchAvailability(available: false,
    reason: "Configure a pinned local SwiftSketch runtime and successful inference receipt.")
  private(set) var isProcessing = false
  private(set) var drawing: SavedDrawing?
  private(set) var jobs: [PortraitReviewGenerationSummary] = []
  private(set) var status = "Select a retained source photo in Studio."
  var error: String?
  var widthMM = 100.0
  var heightMM = 100.0
  var nominalPenWidthMM = 0.4
  var preprocessing: SwiftSketchPreprocessing = .unchanged
  var subjectID = ""
  var photoSessionID = ""
  var groupProvenance = ""
  @ObservationIgnored private let studio: PortraitStudioModel
  @ObservationIgnored private let store: PortraitCandidateStore
  @ObservationIgnored private let client: SwiftSketchClient?
  @ObservationIgnored private let configuration: SwiftSketchWorkerConfiguration?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var snapshot: PortraitExperimentalSourceSnapshot?
  private var isClosing = false

  init(studio: PortraitStudioModel, store: PortraitCandidateStore,
    configuration: SwiftSketchWorkerConfiguration? = PortraitStudioArtistModel.localConfiguration()) {
    self.studio = studio; self.store = store; self.configuration = configuration
    client = configuration.map(SwiftSketchClient.init(configuration:))
  }

  nonisolated static var installedRuntimeURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/PortraitStudio/SwiftSketchRuntime", isDirectory: true)
  }

  nonisolated static func localConfiguration(environment: [String: String] = ProcessInfo.processInfo.environment,
    installedRuntime: URL? = PortraitStudioArtistModel.installedRuntimeURL) -> SwiftSketchWorkerConfiguration? {
    let keys = ["PORTRAIT_SWIFTSKETCH_PYTHON", "PORTRAIT_SWIFTSKETCH_WORKER",
      "PORTRAIT_SWIFTSKETCH_MANIFEST", "PORTRAIT_SWIFTSKETCH_PROOF"]
    let paths = keys.compactMap { environment[$0] }
    if paths.isEmpty, let installedRuntime {
      return .init(pythonExecutable: installedRuntime.appendingPathComponent("venv/bin/python"),
        workerScript: installedRuntime.appendingPathComponent("adapter/worker.py"),
        modelManifest: installedRuntime.appendingPathComponent("manifest.json"),
        proofReceipt: installedRuntime.appendingPathComponent("proof.json"),
        attemptRoot: installedRuntime.appendingPathComponent("attempts", isDirectory: true))
    }
    guard paths.count == keys.count, paths.allSatisfy({ $0.hasPrefix("/") }) else { return nil }
    let attempts = environment["PORTRAIT_SWIFTSKETCH_ATTEMPTS"]
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/PortraitStudio/SwiftSketchAttempts").path
    guard attempts.hasPrefix("/") else { return nil }
    return .init(pythonExecutable: URL(fileURLWithPath: paths[0]), workerScript: URL(fileURLWithPath: paths[1]),
      modelManifest: URL(fileURLWithPath: paths[2]), proofReceipt: URL(fileURLWithPath: paths[3]),
      attemptRoot: URL(fileURLWithPath: attempts, isDirectory: true))
  }

  func refresh() async {
    guard !isClosing else { return }
    if let client { availability = await client.availability() }
    do { jobs = try await store.reviewGenerationPage(limit: 32) }
    catch { self.error = error.localizedDescription }
  }

  func generate() async {
    guard !isClosing, !isProcessing, let client, let configuration, availability.available else { return }
    isProcessing = true; error = nil
    let width = widthMM, height = heightMM, pen = nominalPenWidthMM, arm = preprocessing
    let groups = PortraitReviewGroups(subjectID: Self.known(subjectID), photoSessionID: Self.known(photoSessionID),
      declaration: Self.known(groupProvenance))
    let task = Task {
      defer { self.isProcessing = false; self.snapshot = nil }
      var request: PortraitReviewGenerationRequest?
      var outputs: [PortraitReviewAsset] = []
      var response: SwiftSketchWorkerResult?
      do {
        try groups.validate()
        let frozen = try await self.studio.experimentalSourceSnapshot()
        self.snapshot = frozen
        let prepare = Task.detached { try PortraitStudioArtistInput.prepare(frozen.photo.data) }
        let input = try await withTaskCancellationHandler { try await prepare.value } onCancel: { prepare.cancel() }
        try Task.checkCancellation()
        guard self.studio.admitsExperimentalSource(frozen) else { throw CancellationError() }
        let conversion = try SwiftSketchConverter.settingsJSON(fieldWidthMM: width, fieldHeightMM: height, nominalPenWidthMM: pen)
        let settings = try JSONSerialization.data(withJSONObject: [
          "seed": 42, "preprocessing": arm.rawValue,
          "preparation": JSONSerialization.jsonObject(with: input.preparationJSON),
          "conversion": JSONSerialization.jsonObject(with: conversion)
        ], options: [.sortedKeys])
        let environment = try Self.configuredEnvironment(configuration)
        let artist = DrawingPackageArtist(identifier: "swiftsketch.cpu", revision: "pinned-worker-v1", settingsJSON: settings)
        let scheduled = try PortraitReviewGenerationRequest(captureID: frozen.photo.id,
          acquisitionID: frozen.photo.captureSessionID, source: input.source,
          inputs: [.init(role: "prepared-source", asset: input.squarePNG)], groups: groups, artist: artist,
          environmentJSON: environment, conversionJSON: conversion, seed: 42,
          material: .init(widthMM: width, heightMM: height, nominalLineWidthMM: pen,
            provenance: "operator-declared nominal authoring dimensions; physical pen unmeasured"))
        try await self.store.beginReviewGeneration(scheduled)
        request = scheduled
        self.status = "SwiftSketch is generating one retained-source result."
        let result = try await client.generate(request: .init(requestID: scheduled.id,
          inputPNG: input.squarePNG.bytes, preprocessing: arm))
        response = result
        outputs = PortraitStudioArtistPackageFactory.assets(result)
        guard result.status == .succeeded else {
          let disposition: PortraitReviewGenerationStatus = result.status == .cancelled ? .cancelled
            : (result.status == .unavailable ? .unsupported : .failed)
          _ = try await self.store.finishReviewGeneration(id: scheduled.id, status: disposition,
            reason: result.reason ?? result.status.rawValue, outputs: outputs,
            runtimeEnvironmentJSON: result.provenanceJSON, runtimeMetricsJSON: result.responseJSON)
          self.status = result.reason ?? result.status.rawValue
          await self.refresh(); return
        }
        try Task.checkCancellation()
        guard self.studio.admitsExperimentalSource(frozen) else { throw CancellationError() }
        let producer = try await self.store.reviewLibraryIdentity()
        let conversionTask = Task.detached {
          try PortraitStudioArtistPackageFactory.package(request: scheduled, producerLibraryID: producer, result: result)
        }
        let package = try await withTaskCancellationHandler { try await conversionTask.value } onCancel: { conversionTask.cancel() }
        await self.studio.sketches.awaitPersistence()
        try Task.checkCancellation()
        guard self.studio.admitsExperimentalSource(frozen) else { throw CancellationError() }
        let committed = try await self.store.commitExperimentalReviewResult(requestID: scheduled.id,
          package: package, sourceAdmission: frozen.admission, outputs: outputs,
          runtimeEnvironmentJSON: result.provenanceJSON, runtimeMetricsJSON: result.responseJSON)
        if let evidenceError = committed.evidenceError {
          self.error = "Drawing saved; job evidence needs attention: \(evidenceError)"
        }
        self.status = "Exact SwiftSketch result retained in Library."
        // A cancellation after durable commit changes presentation admission,
        // never the committed drawing's successful outcome.
        guard !Task.isCancelled, self.studio.admitsExperimentalSource(frozen) else {
          await self.refresh(); return
        }
        self.drawing = committed.drawing
        self.status = "Exact SwiftSketch result retained in Library."
        await self.refresh()
      } catch {
        if let request {
          let cancelled = error is CancellationError || Task.isCancelled
          let unsupported: Bool
          if let failure = error as? SwiftSketchError, case .unavailable = failure {
            unsupported = true
          } else { unsupported = false }
          do {
            _ = try await self.store.finishReviewGeneration(id: request.id,
              status: cancelled ? .cancelled : (unsupported ? .unsupported : .failed),
              reason: cancelled ? "Cancelled or source selection changed; no result published." : error.localizedDescription,
              outputs: outputs, runtimeEnvironmentJSON: response?.provenanceJSON, runtimeMetricsJSON: response?.responseJSON)
          } catch { self.error = "Job evidence could not be retained: \(error.localizedDescription)" }
        }
        if !(error is CancellationError) { self.error = self.error ?? error.localizedDescription }
        self.status = error is CancellationError
          ? (request == nil ? "Cancelled before a job was scheduled." : "Cancelled; retained job evidence remains in Library.")
          : "Generation failed."
        await self.refresh()
      }
    }
    operation = task
    await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    operation = nil
  }

  func cancel() async { snapshot?.admission.cancel(); operation?.cancel(); await operation?.value }
  func cancelIfSourceChanged() async {
    if let snapshot, !studio.admitsExperimentalSource(snapshot) { await cancel() }
  }
  func shutdown() async { isClosing = true; await cancel() }

  private static func known(_ text: String) -> String? {
    let value = text.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value
  }
  private static func configuredEnvironment(_ configuration: SwiftSketchWorkerConfiguration) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["runtime": "configured-local-cpu", "threads": 2,
      "timeout_seconds": configuration.timeoutSeconds, "maximum_rss_bytes": configuration.maximumRSSBytes,
      "worker_path": configuration.workerScript.path, "model_manifest_path": configuration.modelManifest.path,
      "proof_path": configuration.proofReceipt.path,
      "attempt_root": configuration.attemptRoot.path,
      "native_os": ProcessInfo.processInfo.operatingSystemVersionString,
      "native_bundle_identifier": Bundle.main.bundleIdentifier ?? "unknown",
      "native_build_identifier": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
      "native_toolchain": "unknown"], options: [.sortedKeys])
  }
}
