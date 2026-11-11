import Foundation
import CryptoKit
import Darwin
import DrawingLibrary
import PortraitCore
import PlotterModel

/// Package-only observation of the real artifact worker. Tests may hold it;
/// there is no replacement work path or application configuration.
package enum DrawingDestinationArtifactBoundary: Sendable { case assemblyStarted, beforePublication, copyingOriginal, beforeResultLink }
package final class DrawingDestinationArtifactObservation: @unchecked Sendable {
  package static let shared = DrawingDestinationArtifactObservation()
  private let lock = NSLock()
  private var observer: (@Sendable (JobRef, DrawingDestinationArtifactBoundary) -> Void)?
  package func install(_ observer: (@Sendable (JobRef, DrawingDestinationArtifactBoundary) -> Void)?) {
    lock.lock(); self.observer = observer; lock.unlock()
  }
  func notify(_ job: JobRef, _ boundary: DrawingDestinationArtifactBoundary) {
    lock.lock(); let observer = observer; lock.unlock()
    observer?(job, boundary)
  }
}

public enum DrawingDestinationResult {
  /// Local owner codecs recognize only the concrete plan and options types.
  public static var payloadValidators: ExchangePayloadValidators {
    var validators = DrawingNativeResultCodec.validators
    validators[.init(encoding: "adaptiveplotter.local-prepared-plan/1", version: "1")] = { context in
        let bytes = try context.resolver.record(context.descriptor.asset.object, maximumBytes: DrawingExchangeLimits.maximumProgramBytes)
        let plan = try JSONDecoder().decode(ExecutionPlanRevision.self, from: bytes)
        guard !plan.strokes.isEmpty else { throw DrawingExchangeError.malformed("Empty prepared plan") }
        return .verified(.init(plan: context.descriptor.asset.object))
      }
    validators[.init(encoding: "adaptiveplotter.local-medium-options/1", version: "1")] = { context in
        let bytes = try context.resolver.record(context.descriptor.asset.object, maximumBytes: 65_536)
        let options = try JSONDecoder().decode(DrawingDestinationOptions.self, from: bytes)
        guard !options.readiness.isEmpty, options.readiness.utf8.count <= 4096 else { throw DrawingExchangeError.malformed("Invalid readiness") }
        return .verified(.init())
      }
    return .init(validators)
  }
  static func export(_ decision: DrawingJobDecision, library: DrawingLibrary, to destination: URL) async throws {
    DrawingDestinationArtifactObservation.shared.notify(decision.job.handle, .assemblyStarted)
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-destination-result-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    var complete = false
    defer { if complete { try? FileManager.default.removeItem(at: temporary) } }
    if FileManager.default.fileExists(atPath: destination.path) {
      try verifyExisting(decision, at: destination, stagingParent: temporary)
      complete = true
      return
    }
    let bag = temporary.appendingPathComponent("bag")
    try await library.exportDrawing(decision.ticket.facts.drawing, to: bag)
    var index = try ExchangeJSON.validate(Data(contentsOf: bag.appendingPathComponent("data/exchange.json")))
    let encoder = DrawingArtifactCoding.encoder()
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value)) }
    let receipt = try ExchangeJobReceipt(originalJSON: decision.receipt)
    guard receipt.disposition == "refused", receipt.handle == decision.job.handle,
      ExchangeDigest.hash(decision.receipt) == decision.job.receiptDigest else { throw DrawingExchangeError.malformed("Refusal receipt") }
    let assets = [decision.ticket.facts.plan, decision.ticket.facts.options]
    var descriptors = try JSONDecoder().decode([ExchangeAssetDescriptor].self,
      from: JSONSerialization.data(withJSONObject: index["assets"] ?? []))
    for asset in assets {
      // Export uses engine CAS bytes, never client paths or regenerated plan bytes.
      let bytes = try await library.asset(asset.object)
      try asset.validate(bytes, maximumBytes: DrawingExchangeLimits.maximumProgramBytes)
      let path = bag.appendingPathComponent("data/objects/sha256/" + asset.object.description)
      try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: path, options: .atomic)
      if !descriptors.contains(.init(asset: asset)) { descriptors.append(.init(asset: asset)) }
    }
    let receiptPath = bag.appendingPathComponent("data/jobs/" + receipt.handle.engine.uuidString.lowercased() + "/" + receipt.handle.job.uuidString.lowercased() + "/receipt.json")
    try FileManager.default.createDirectory(at: receiptPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try decision.receipt.write(to: receiptPath, options: .atomic)
    guard let includedAsOf = receipt.issuedAt.wallTime else { throw DrawingExchangeError.malformed("Local refusal receipt wall time") }
    index["includedAsOf"] = includedAsOf
    index["kind"] = "result"; index["jobs"] = try object([decision.job]); index["attempts"] = [String]()
    index["assets"] = try object(descriptors)
    try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys, .withoutEscapingSlashes])
      .write(to: bag.appendingPathComponent("data/exchange.json"), options: .atomic)
    try seal(bag)
    let staged = try DrawingExchangeCarrier.stageDirectory(bag, stagingParent: temporary)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: payloadValidators)
    let publication = destination.deletingLastPathComponent().appendingPathComponent(".result-publication-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: publication, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let output = publication.appendingPathComponent("result.zip")
    try DrawingExchangeCarrier.preserveZIP(admitted.files, to: output)
    let descriptor = Darwin.open(output.path, O_RDONLY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw DrawingExchangeError.malformed("Result synchronization open") }
    let synchronized = Darwin.fsync(descriptor)
    Darwin.close(descriptor)
    guard synchronized == 0 else { throw DrawingExchangeError.malformed("Result synchronization") }
    DrawingDestinationArtifactObservation.shared.notify(decision.job.handle, .beforePublication)
    // Same-volume, exclusive atomic rename: a divergent existing target is never overwritten.
    if Darwin.renamex_np(output.path, destination.path, UInt32(RENAME_EXCL)) != 0 {
      if errno == EEXIST { try verifyExisting(decision, at: destination, stagingParent: temporary) }
      else { throw DrawingExchangeError.malformed("Result publication: " + String(errno)) }
    }
    let parent = Darwin.open(destination.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY)
    guard parent >= 0 else { throw DrawingExchangeError.malformed("Result directory synchronization open") }
    let directorySynchronized = Darwin.fsync(parent)
    Darwin.close(parent)
    guard directorySynchronized == 0 else { throw DrawingExchangeError.malformed("Result directory synchronization") }
    try FileManager.default.removeItem(at: publication)
    complete = true
  }
  private static func verifyExisting(_ decision: DrawingJobDecision, at destination: URL, stagingParent: URL) throws {
    let staged = try DrawingExchangeCarrier.stageZIP(destination, stagingParent: stagingParent)
    let admitted = try ExchangeAdmission.validate(staged, payloadValidators: payloadValidators)
    guard let index = admitted.index.known, index.kind == "result", index.roots == [decision.ticket.facts.drawing],
      index.jobs == [decision.job], index.attempts.isEmpty,
      admitted.receipts[decision.job]?.originalJSON == decision.receipt else {
      throw DrawingExchangeError.malformed("Divergent existing result publication")
    }
  }
  static func seal(_ bag: URL) throws {
    let files = FileManager.default.enumerator(at: bag, includingPropertiesForKeys: [.isRegularFileKey])!
    let root = bag.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    var payload: [String] = [], tags: [String] = []
    for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
      let components = file.standardizedFileURL.resolvingSymlinksInPath().pathComponents
      guard components.count > root.count, components.starts(with: root) else { throw DrawingExchangeError.malformed("Result manifest path") }
      let path = components.dropFirst(root.count).joined(separator: "/")
      if path == "manifest-sha256.txt" || path == "tagmanifest-sha256.txt" { continue }
      let stream = try FileHandle(forReadingFrom: file)
      defer { try? stream.close() }
      var hash = SHA256()
      while let bytes = try stream.read(upToCount: 256 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
      let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
      let line = digest + "  " + path + "\n"
      if path.hasPrefix("data/") { payload.append(line) } else { tags.append(line) }
    }
    let manifest = Data(payload.sorted().joined().utf8)
    try manifest.write(to: bag.appendingPathComponent("manifest-sha256.txt"), options: .atomic)
    tags.append(ExchangeDigest.hash(manifest).description + "  manifest-sha256.txt\n")
    try Data(tags.sorted().joined().utf8).write(to: bag.appendingPathComponent("tagmanifest-sha256.txt"), options: .atomic)
  }
}
