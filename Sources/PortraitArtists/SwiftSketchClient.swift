import Darwin
import Foundation
import PortraitCore

/// A single local subprocess request. Blocking I/O runs on a detached executor.
public actor SwiftSketchClient {
  private let configuration: SwiftSketchWorkerConfiguration
  private var activeRequest: UUID?
  public init(configuration: SwiftSketchWorkerConfiguration) { self.configuration = configuration }

  public func availability() async -> SwiftSketchAvailability {
    let configuration = configuration
    return await Task.detached { Self.checkAvailability(configuration) }.value
  }

  public func generate(request: SwiftSketchRequest) async throws -> SwiftSketchWorkerResult {
    guard activeRequest == nil else { throw SwiftSketchError.busy }
    guard request.inputPNG.count > 0, request.inputPNG.count <= 16 * 1024 * 1024,
      request.seed == 42 else { throw SwiftSketchError.invalid("SwiftSketch input or paired seed exceeds its contract.") }
    activeRequest = request.requestID
    defer { activeRequest = nil }
    let availability = await availability()
    guard availability.available else { throw SwiftSketchError.unavailable(availability.reason) }
    let configuration = configuration, cancellation = WorkerCancellation()
    return try await withTaskCancellationHandler {
      try await Task.detached {
        try Self.run(request, configuration: configuration, cancellation: cancellation)
      }.value
    } onCancel: {
      cancellation.cancel()
    }
  }

  private static func checkAvailability(_ config: SwiftSketchWorkerConfiguration) -> SwiftSketchAvailability {
    do {
      guard config.timeoutSeconds.isFinite, config.timeoutSeconds > 0, config.timeoutSeconds <= 600,
        config.maximumRSSBytes > 0, config.maximumRSSBytes <= 6 * 1024 * 1024 * 1024,
        FileManager.default.isExecutableFile(atPath: config.pythonExecutable.path),
        FileManager.default.fileExists(atPath: config.workerScript.path),
        FileManager.default.fileExists(atPath: config.modelManifest.path) else {
        return SwiftSketchAvailability(available: false, reason: "Local pinned CPU runtime or model manifest is missing.")
      }
      let proof = try JSONDecoder().decode(Proof.self, from: boundedRead(config.proofReceipt, limit: 64 * 1024))
      guard proof.schemaVersion == 1, proof.status == "succeeded",
        proof.adapterSHA256 == DrawingPackageCodec.sha256(try boundedRead(config.workerScript, limit: 256 * 1024)),
        proof.manifestSHA256 == DrawingPackageCodec.sha256(try boundedRead(config.modelManifest, limit: 64 * 1024)) else {
        return SwiftSketchAvailability(available: false, reason: "Pinned pretrained inference has no matching successful local receipt.")
      }
      let manifest = try JSONDecoder().decode(Manifest.self, from: boundedRead(config.modelManifest, limit: 64 * 1024))
      guard manifest.schemaVersion == 1,
        manifest.upstreamCommit == "6f9fa8654711b9a5d3022b08a59835f0dda08f40" else {
        return SwiftSketchAvailability(available: false, reason: "Unsupported local model manifest.")
      }
      for name in ["diffusion", "diffusion_args", "refinement", "refinement_args", "clip"] {
        guard let asset = manifest.assets[name], asset.path.hasPrefix("/"),
          regularFilePresent(URL(fileURLWithPath: asset.path), maximumBytes: name.hasSuffix("_args") ? 64 * 1024 : 512 * 1024 * 1024) else {
          return SwiftSketchAvailability(available: false, reason: "Pinned local model asset is missing: \(name).")
        }
      }
      let source = URL(fileURLWithPath: manifest.upstreamRoot, isDirectory: true)
      guard manifest.upstreamRoot.hasPrefix("/") else {
        return SwiftSketchAvailability(available: false, reason: "Pinned local upstream source is missing.")
      }
      for name in ["SwiftSketch/model/SwiftSketch_model.py", "SwiftSketch/utils/model_util.py",
        "SwiftSketch/diffusion/gaussian_diffusion.py", "SwiftSketch/CLIP_/clip/model.py",
        "SwiftSketch/CLIP_/clip/clip.py", "SwiftSketch/CLIP_/clip/bpe_simple_vocab_16e6.txt.gz"] {
        guard regularFilePresent(source.appendingPathComponent(name), maximumBytes: 8 * 1024 * 1024) else {
          return SwiftSketchAvailability(available: false, reason: "Pinned local upstream source is missing: \(name).")
        }
      }
      // Presence is cheap menu availability; every generation revalidates all official hashes.
      return SwiftSketchAvailability(available: true, reason: "Pinned local CPU inference has a successful receipt.")
    } catch {
      return SwiftSketchAvailability(available: false, reason: "SwiftSketch requires a successful local inference receipt: \(error.localizedDescription)")
    }
  }

  private static func regularFilePresent(_ url: URL, maximumBytes: Int) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
      values.isRegularFile == true, values.isSymbolicLink != true,
      let count = values.fileSize, count > 0, count <= maximumBytes else { return false }
    return true
  }

  private static func run(_ request: SwiftSketchRequest, configuration config: SwiftSketchWorkerConfiguration,
    cancellation: WorkerCancellation) throws -> SwiftSketchWorkerResult {
    let directory = config.attemptRoot.appendingPathComponent(request.requestID.uuidString, isDirectory: true)
    guard !FileManager.default.fileExists(atPath: directory.path) else {
      throw SwiftSketchError.invalid("Attempt already exists; retained results cannot be overwritten.")
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let input = directory.appendingPathComponent("input.png"), requestFile = directory.appendingPathComponent("request.json")
    let output = directory.appendingPathComponent("output", isDirectory: true)
    try request.inputPNG.write(to: input, options: .atomic)
    let requestJSON: [String: Any] = ["schema_version": 1, "request_id": request.requestID.uuidString,
      "input_path": input.path, "input_sha256": DrawingPackageCodec.sha256(request.inputPNG),
      "preprocessing": request.preprocessing.rawValue, "seed": request.seed,
      "mask_policy": "fixed-input-no-segmentation-v1"]
    try JSONSerialization.data(withJSONObject: requestJSON, options: [.sortedKeys]).write(to: requestFile)
    let logURL = directory.appendingPathComponent("worker.log")
    FileManager.default.createFile(atPath: logURL.path, contents: nil)
    let log = try FileHandle(forWritingTo: logURL)
    defer { try? log.close() }
    let process = Process()
    process.executableURL = config.pythonExecutable
    process.arguments = [config.workerScript.path, "--request", requestFile.path,
      "--manifest", config.modelManifest.path, "--output", output.path]
    var environment = ProcessInfo.processInfo.environment
    environment["OMP_NUM_THREADS"] = "2"; environment["MKL_NUM_THREADS"] = "2"
    environment["OPENBLAS_NUM_THREADS"] = "2"; environment["PYTHONUNBUFFERED"] = "1"
    environment["WANDB_DISABLED"] = "true"; environment["HF_HUB_OFFLINE"] = "1"
    process.environment = environment; process.standardOutput = log; process.standardError = log
    let clock = ContinuousClock(), started = ContinuousClock.now
    let deadline = started.advanced(by: .milliseconds(Int64(config.timeoutSeconds * 1000)))
    func elapsed() -> Double {
      let duration = started.duration(to: clock.now).components
      return Double(duration.seconds) + Double(duration.attoseconds) / 1e18
    }
    if cancellation.isCancelled {
      return try terminal(request, status: .cancelled, reason: "Cancelled before worker launch.", directory: directory)
    }
    try process.run()
    var terminalStatus: SwiftSketchWorkerStatus?
    var reason: String?
    var peakRSS: UInt64 = 0
    var nextMemoryCheck = clock.now
    while process.isRunning {
      if cancellation.isCancelled { terminalStatus = .cancelled; reason = "Cancelled by operator."; break }
      if clock.now >= deadline { terminalStatus = .timedOut; reason = "SwiftSketch exceeded the request timeout."; break }
      if ((try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 8 * 1024 * 1024 {
        terminalStatus = .failed; reason = "SwiftSketch exceeded the worker log byte budget."; break
      }
      if clock.now >= nextMemoryCheck {
        if let rss = residentBytes(pid: process.processIdentifier) {
          peakRSS = max(peakRSS, rss)
          if rss > config.maximumRSSBytes {
            terminalStatus = .failed; reason = "SwiftSketch exceeded the local memory budget."; break
          }
        }
        nextMemoryCheck = clock.now.advanced(by: .seconds(1))
      }
      Thread.sleep(forTimeInterval: 0.05)
    }
    if terminalStatus != nil {
      process.terminate()
      let reapDeadline = clock.now.advanced(by: .seconds(2))
      while process.isRunning, clock.now < reapDeadline { Thread.sleep(forTimeInterval: 0.05) }
      if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }
    process.waitUntilExit()
    if cancellation.isCancelled { terminalStatus = .cancelled; reason = "Cancelled by operator; late result suppressed." }
    if let terminalStatus {
      return try terminal(request, status: terminalStatus, reason: reason ?? "Worker stopped.",
        directory: directory, peakRSS: peakRSS, elapsed: elapsed())
    }
    let responseURL = output.appendingPathComponent("response.json")
    guard FileManager.default.fileExists(atPath: responseURL.path) else {
      return try terminal(request, status: .failed, reason: "Worker exited \(process.terminationStatus) without a protocol response.",
        directory: directory, peakRSS: peakRSS, elapsed: elapsed())
    }
    do {
    let bytes = try boundedRead(responseURL, limit: 2 * 1024 * 1024)
    let response = try JSONDecoder().decode(Response.self, from: bytes)
    guard response.schemaVersion == 1, response.requestID == request.requestID else {
      throw SwiftSketchError.invalid("Worker returned a stale or mismatched request identity.")
    }
    func asset(_ name: String, limit: Int) throws -> Data? {
      guard let hash = response.files[name] else { return nil }
      let data = try boundedRead(output.appendingPathComponent(name), limit: limit)
      guard DrawingPackageCodec.sha256(data) == hash else { throw SwiftSketchError.invalid("Worker asset hash mismatch: \(name)") }
      return data
    }
    let raw = try asset("raw-curves.json", limit: 2 * 1024 * 1024)
    let inputBytes = try asset("artist-input.png", limit: 16 * 1024 * 1024)
    let preview = try asset("preview.png", limit: 8 * 1024 * 1024)
    let provenance = try asset("provenance.json", limit: 2 * 1024 * 1024)
    if response.status == .succeeded {
      guard process.terminationStatus == 0, raw != nil, inputBytes != nil, preview != nil, provenance != nil else {
        throw SwiftSketchError.invalid("Successful worker response is incomplete.")
      }
    }
    // Cancellation during response decoding must also suppress a completed image.
    if cancellation.isCancelled {
      return try terminal(request, status: .cancelled, reason: "Cancelled; late result suppressed.", directory: directory)
    }
    return SwiftSketchWorkerResult(requestID: request.requestID, status: response.status, reason: response.reason,
      rawOutputJSON: raw, artistInputPNG: inputBytes, previewPNG: preview, provenanceJSON: provenance,
      responseJSON: bytes, attemptDirectory: directory)
    } catch {
      if let refused = try? boundedRead(responseURL, limit: 2 * 1024 * 1024) {
        try? refused.write(to: directory.appendingPathComponent("refused-response.bin"), options: .atomic)
      }
      return try terminal(request, status: cancellation.isCancelled ? .cancelled : .failed,
        reason: "Worker response refused: \(error.localizedDescription)", directory: directory,
        peakRSS: peakRSS, elapsed: elapsed())
    }
  }

  private static func terminal(_ request: SwiftSketchRequest, status: SwiftSketchWorkerStatus,
    reason: String, directory: URL, peakRSS: UInt64 = 0, elapsed: Double = 0) throws -> SwiftSketchWorkerResult {
    let bytes = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
      "request_id": request.requestID.uuidString, "status": status.rawValue, "reason": reason,
      "peak_rss_bytes": peakRSS, "elapsed_seconds": elapsed, "files": [:]], options: [.sortedKeys])
    try bytes.write(to: directory.appendingPathComponent("client-terminal.json"), options: .atomic)
    let output = directory.appendingPathComponent("output", isDirectory: true)
    // Refused partial bytes remain review evidence, never an admitted DrawingProgram.
    return SwiftSketchWorkerResult(requestID: request.requestID, status: status, reason: reason,
      rawOutputJSON: try? boundedRead(output.appendingPathComponent("raw-curves.json"), limit: 2 * 1024 * 1024),
      artistInputPNG: try? boundedRead(output.appendingPathComponent("artist-input.png"), limit: 16 * 1024 * 1024),
      previewPNG: try? boundedRead(output.appendingPathComponent("preview.png"), limit: 8 * 1024 * 1024),
      provenanceJSON: try? boundedRead(output.appendingPathComponent("provenance.json"), limit: 2 * 1024 * 1024),
      responseJSON: bytes, attemptDirectory: directory)
  }
  private static func boundedRead(_ url: URL, limit: Int) throws -> Data {
    let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard size.isRegularFile == true, size.isSymbolicLink != true,
      let count = size.fileSize, count > 0, count <= limit else {
      throw SwiftSketchError.invalid("Worker file exceeds the protocol byte bound.")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var bytes = Data()
    while bytes.count <= limit {
      guard let block = try handle.read(upToCount: min(64 * 1024, limit + 1 - bytes.count)), !block.isEmpty else { break }
      bytes.append(block)
    }
    guard !bytes.isEmpty, bytes.count <= limit else { throw SwiftSketchError.invalid("Worker file changed beyond its bound.") }
    return bytes
  }
  private static func residentBytes(pid: Int32) -> UInt64? {
    // A narrow local process observation, independent of the worker's own report.
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/bin/ps")
    process.arguments = ["-o", "rss=", "-p", String(pid)]
    process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
    do {
      try process.run()
      let output = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard let text = String(data: output, encoding: .utf8), let kb = UInt64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
      return kb * 1024
    } catch { return nil }
  }
  private struct Proof: Decodable {
    let schemaVersion: Int, status: String, adapterSHA256: String, manifestSHA256: String
    enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version", status, adapterSHA256 = "adapter_sha256", manifestSHA256 = "manifest_sha256"
    }
  }
  private struct Manifest: Decodable {
    let schemaVersion: Int, upstreamRoot: String, upstreamCommit: String
    let assets: [String: Asset]
    struct Asset: Decodable { let path: String, sha256: String }
    enum CodingKeys: String, CodingKey {
      case schemaVersion = "schema_version", upstreamRoot = "upstream_root", upstreamCommit = "upstream_commit", assets
    }
  }
  private struct Response: Decodable {
    let schemaVersion: Int, requestID: UUID, status: SwiftSketchWorkerStatus, reason: String?, files: [String: String]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", requestID = "request_id", status, reason, files }
  }
}

private final class WorkerCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
  func cancel() { lock.lock(); defer { lock.unlock() }; value = true }
}
