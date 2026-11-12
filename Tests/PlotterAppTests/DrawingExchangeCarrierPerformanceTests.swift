import Darwin
import Foundation
import CryptoKit
import MachO
import Testing
@testable import Drawing
@testable import PortraitCore

@Suite("DX03 carrier measurements", .serialized)
struct DrawingExchangeCarrierPerformanceTests {
  private func sha256(_ path: String) throws -> String {
    let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path)); defer { try? handle.close() }
    var hash = SHA256()
    while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
  }
  private func imageUUID(_ header: UnsafePointer<mach_header>) -> String? {
    let head = header.pointee
    guard head.magic == MH_MAGIC_64, head.ncmds < 65_536 else { return nil }
    var pointer = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size), remaining = Int(head.sizeofcmds)
    for _ in 0..<head.ncmds {
      guard remaining >= MemoryLayout<load_command>.size else { return nil }
      let command = pointer.load(as: load_command.self), length = Int(command.cmdsize)
      guard length >= MemoryLayout<load_command>.size, length <= remaining else { return nil }
      if command.cmd == LC_UUID, length >= MemoryLayout<uuid_command>.size { return UUID(uuid: pointer.load(as: uuid_command.self).uuid).uuidString.lowercased() }
      pointer = pointer.advanced(by: length); remaining -= length
    }
    return nil
  }
  private func identity(token: String, expectedImage: String) throws -> [String: Any] {
    var images: [[String: Any]] = []
    for index in 0..<_dyld_image_count() {
      guard let name = _dyld_get_image_name(index), let header = _dyld_get_image_header(index) else { continue }
      let path = String(cString: name)
      if URL(fileURLWithPath: path).lastPathComponent == "AdaptivePlotterPackageTests" {
        images.append(["path": path, "sha256": try sha256(path), "loadedMachOUUID": imageUUID(header) as Any? ?? NSNull()])
      }
    }
    let image = try #require(images.first)
    #expect(images.count == 1)
    guard let path = image["path"] as? String,
      URL(fileURLWithPath: path).resolvingSymlinksInPath() == URL(fileURLWithPath: expectedImage).resolvingSymlinksInPath() else { throw DrawingExchangeError.malformed("Loaded test image differs from requested artifact") }
    return ["pid": ProcessInfo.processInfo.processIdentifier, "argv": CommandLine.arguments, "token": token,
      "mainBundlePath": Bundle.main.bundleURL.path, "mainExecutablePath": Bundle.main.executableURL?.path as Any? ?? NSNull(), "testImages": images]
  }
  @Test("opt-in inert streaming admission", .enabled(if: ProcessInfo.processInfo.environment["DX03_PERF_ROOT"] != nil))
  func streaming() throws {
    let env = ProcessInfo.processInfo.environment
    let source = URL(fileURLWithPath: try #require(env["DX03_PERF_ROOT"]))
    let output = URL(fileURLWithPath: try #require(env["DX03_PERF_OUTPUT"]))
    let staging = URL(fileURLWithPath: try #require(env["DX03_PERF_STAGE"]))
    let ack = URL(fileURLWithPath: try #require(env["DX03_PERF_ACK"]))
    let token = try #require(env["DX03_PERF_TOKEN"]), expectedImage = try #require(env["DX03_PERF_EXPECTED_IMAGE"])
    let trials = Int(env["DX03_PERF_TRIALS"] ?? "1") ?? 0, warmups = Int(env["DX03_PERF_WARMUPS"] ?? "0") ?? -1
    guard trials > 0, trials <= 100, warmups >= 0, warmups <= 1, !FileManager.default.fileExists(atPath: output.path) else { throw DrawingExchangeError.malformed("Measurement arguments/output") }
    let helper = try identity(token: token, expectedImage: expectedImage)
    let imageHash = try #require((helper["testImages"] as? [[String: Any]])?.first?["sha256"] as? String)
    let imageAttributes = try FileManager.default.attributesOfItem(atPath: expectedImage)
    var measurements: [[String: Any]] = [], warmupRows: [[String: Any]] = []
    func report(_ status: String, failure: [String: Any]? = nil) throws {
      var value: [String: Any] = ["schemaVersion": 2, "status": status, "identity": helper,
        "operation": "separately timed full directory import and preserveDirectory; output SHA proof outside both intervals", "trials": measurements, "warmups": warmupRows,
        "RSSScope": "Actual helper process lifetime peak, including setup/warmup, import, export and untimed output verification; cumulative across same-helper warm trials, not independent phase/trial allocation samples",
        "counterScope": "Successful carrier file copy/SHA pass bytes, bounded record/receipt SHA bytes, successful per-path materializations, program JSON decode call entries and producer-validator entries; not every internal APCB/catalog UUID hash primitive", "evidenceClass": "inert software only"]
      if let failure { value["failure"] = failure }
      try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }
    try report("awaiting-host-attestation")
    // Untimed startup handshake lets the driver observe the actual live helper and its ancestry.
    let deadline = ContinuousClock.now.advanced(by: .seconds(20))
    while !FileManager.default.fileExists(atPath: ack.path), ContinuousClock.now < deadline { Thread.sleep(forTimeInterval: 0.01) }
    let attestation = try JSONSerialization.jsonObject(with: Data(contentsOf: ack)) as? [String: Any]
    guard attestation?["token"] as? String == token, (attestation?["pid"] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier,
      attestation?["testImageSHA256"] as? String == imageHash else { throw DrawingExchangeError.malformed("Host helper attestation") }
    for index in 0..<(warmups + trials) {
      var failedStage: URL?
      var failedExport: URL?
      do {
        let row: [String: Any] = try autoreleasepool {
          let start = ContinuousClock.now
          let package = try DrawingExchangeCarrier.stageDirectory(source, stagingParent: staging)
          failedStage = package.stagingURL.deletingLastPathComponent()
          let admitted = try ExchangeAdmission.validate(package)
          let end = ContinuousClock.now
          let known = try #require(admitted.index.known)
          let raw = known.assets.filter { $0.asset.encoding.hasPrefix("raw-") }
          if env["DX03_PERF_CONTROL"] == "raw-read", let first = raw.first { _ = try package.files.record(first.asset.object, maximumBytes: 16 * 1024 * 1024) }
          let statistics = package.statistics
          let fileBytes = package.files.entries.values.reduce(UInt64(0)) { $0 + $1.byteLength }
          let rawPaths = Set(raw.map { "data/objects/sha256/" + $0.asset.object.description })
          let rawReadBytes = statistics.materializedBytesByPath.filter { rawPaths.contains($0.key) }.values.reduce(UInt64(0), +)
          let rawReadPasses = statistics.materializationReadPassesByPath.filter { rawPaths.contains($0.key) }.values.reduce(UInt64(0), +)
          let rawSupported = raw.allSatisfy { admitted.assetSupport[$0.asset.object]?.isSupported == true }
          guard statistics.sourceBytesRead == fileBytes, statistics.stagedBytesWritten == fileBytes,
            statistics.verificationBytesRead == fileBytes, statistics.hashedBytes == fileBytes,
            statistics.imageHeaderReads == 0, statistics.imageDecodeCount == 0, statistics.programJSONDecodeCalls == 1, statistics.producerValidatorEntries == 1,
            rawReadBytes == 0, rawReadPasses == 0, rawSupported else {
            let diagnostic: [String: Any] = ["reason": "Structural measurement contract rejected", "stagingPath": failedStage!.path,
              "rawMaterializedBytes": rawReadBytes, "rawMaterializationPasses": rawReadPasses,
              "statistics": try JSONSerialization.jsonObject(with: JSONEncoder().encode(statistics))]
            try report("rejected", failure: diagnostic)
            throw DrawingExchangeError.malformed("Structural measurement contract rejected")
          }
          let export = staging.appendingPathComponent("preserved-" + UUID().uuidString.lowercased())
          failedExport = export
          let exportStart = ContinuousClock.now
          try DrawingExchangeCarrier.preserveDirectory(package.files, to: export)
          let exportEnd = ContinuousClock.now
          let afterExport = package.statistics
          guard afterExport.reexportBytesRead == fileBytes, afterExport.reexportBytesWritten == fileBytes,
            afterExport.programJSONDecodeCalls == statistics.programJSONDecodeCalls,
            afterExport.producerValidatorEntries == statistics.producerValidatorEntries,
            afterExport.imageHeaderReads == statistics.imageHeaderReads, afterExport.imageDecodeCount == statistics.imageDecodeCount,
            afterExport.materializedBytesRead == statistics.materializedBytesRead,
            afterExport.materializationReadPassesByPath == statistics.materializationReadPassesByPath,
            afterExport.materializedBytesByPath == statistics.materializedBytesByPath,
            afterExport.semanticBytesHashed == statistics.semanticBytesHashed,
            afterExport.hashedBytes == statistics.hashedBytes else { throw DrawingExchangeError.malformed("Export pass counters") }
          // Untimed independent verifier counters: no extra payload copy or semantic decode.
          let outputCounters = ExchangeCarrierCounters()
          let outputEntries = try DrawingExchangeCarrier.verify(export, limits: package.files.limits, counters: outputCounters, cancelled: { false })
          let outputStatistics = outputCounters.snapshot
          guard Set(outputEntries.keys) == Set(package.files.entries.keys), package.files.entries.allSatisfy({ path, entry in
            outputEntries[path]?.digest == entry.digest && outputEntries[path]?.byteLength == entry.byteLength
          }), outputStatistics.verificationBytesRead == fileBytes, outputStatistics.hashedBytes == fileBytes,
            outputStatistics.programJSONDecodeCalls == 0, outputStatistics.producerValidatorEntries == 0,
            outputStatistics.imageHeaderReads == 0, outputStatistics.imageDecodeCount == 0 else { throw DrawingExchangeError.digestMismatch("Preserved directory output") }
          let elapsed = start.duration(to: end), exportElapsed = exportStart.duration(to: exportEnd)
          var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
          let row: [String: Any] = ["importMilliseconds": Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15,
            "exportMilliseconds": Double(exportElapsed.components.seconds) * 1000 + Double(exportElapsed.components.attoseconds) / 1e15,
            "importStatistics": try JSONSerialization.jsonObject(with: JSONEncoder().encode(statistics)),
            "exportCounters": ["fileBytesRead": afterExport.reexportBytesRead, "fileBytesWritten": afterExport.reexportBytesWritten,
              "programJSONDecodeCalls": afterExport.programJSONDecodeCalls - statistics.programJSONDecodeCalls,
              "producerValidatorEntries": afterExport.producerValidatorEntries - statistics.producerValidatorEntries,
              "imageDecodeCount": afterExport.imageDecodeCount - statistics.imageDecodeCount,
              "materializedBytesRead": afterExport.materializedBytesRead - statistics.materializedBytesRead,
              "materializationPasses": afterExport.materializationReadPassesByPath.values.reduce(UInt64(0), +) - statistics.materializationReadPassesByPath.values.reduce(UInt64(0), +)],
            "exportVerificationStatistics": try JSONSerialization.jsonObject(with: JSONEncoder().encode(outputStatistics)),
            "outputByteIntegrityVerified": true, "outputFileCount": outputEntries.count, "fileCount": package.files.entries.count,
            "fileBytes": fileBytes, "rawAssetCount": raw.count, "rawMaterializedBytes": rawReadBytes, "rawMaterializationPasses": rawReadPasses,
            "programCount": admitted.drawings.count, "processPeakRSSBytes": usage.ru_maxrss]
          // Outside interval. Failed operations never arrive here and keep their inspection bytes.
          try FileManager.default.removeItem(at: export)
          failedExport = nil
          try FileManager.default.removeItem(at: package.stagingURL.deletingLastPathComponent())
          failedStage = nil
          return row
        }
        if index < warmups { warmupRows.append(row) } else { measurements.append(row) }
        try report("running")
      } catch {
        if (try? Data(contentsOf: output)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["status"] as? String != "rejected" {
          try report("failed", failure: ["reason": String(describing: error), "stagingPath": failedStage?.path as Any? ?? NSNull(), "exportPath": failedExport?.path as Any? ?? NSNull(), "counterCoverage": "Unavailable if stage did not return; no invented zero counters"])
        }
        throw error
      }
    }
    let after = try FileManager.default.attributesOfItem(atPath: expectedImage)
    guard after[.systemFileNumber] as? NSNumber == imageAttributes[.systemFileNumber] as? NSNumber,
      after[.size] as? NSNumber == imageAttributes[.size] as? NSNumber,
      after[.modificationDate] as? Date == imageAttributes[.modificationDate] as? Date else { throw DrawingExchangeError.malformed("Test image changed during helper") }
    try report("complete")
  }
}
