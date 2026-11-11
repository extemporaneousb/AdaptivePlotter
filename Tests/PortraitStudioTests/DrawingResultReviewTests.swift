import AppKit
import Foundation
@testable import DrawingLibrary
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import SwiftUI
import Testing

@Suite("Drawing returned-result cold review", .serialized)
@MainActor struct DrawingResultReviewTests {
  private func refusedResult() async throws -> (DestinationFixture, URL) {
    let fixture = try await DestinationFixture(parent: true)
    let service = fixture.service()
    let ticket = try await fixture.ticket(service)
    guard case .decision(let decision) = try await service.handle(.submit(.init(namespace: UUID()), ticket)),
      case .result(let url) = try await service.handle(.exportResult(decision.job.handle)) else {
      throw DrawingDestinationRefusal.preparationUnavailable
    }
    await service.close()
    return (fixture, url)
  }

  @Test("Shared native import mounts a real refused result on an empty Library and reveals its exact Drawing")
  func coldRefusedResultRoute() async throws {
    let (fixture, carrier) = try await refusedResult()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let library = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("cold-result"),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let sketches = PortraitSketchCollection(library: library)
    let browser = DrawingLibraryBrowserModel(sketches: sketches)
    var route = DrawingLibraryRoute(); route.workspace = .drawingStudio
    let binding = Binding(get: { route }, set: { route = $0 })
    await browser.importResult(from: carrier, route: binding)
    #expect(browser.error == nil && route.drawing == fixture.reference && route.workspace == .library)
    #expect(sketches.selected?.reference == fixture.reference)
    let original = try await fixture.library.drawing(fixture.reference)
    #expect(sketches.selected?.parent == original.parent && sketches.selected?.program == original.program)
    let model = DrawingResultReviewModel(library: library, drawing: fixture.reference)
    let before = DrawingLibraryDiagnostics.shared.snapshot()
    await model.load()
    let after = DrawingLibraryDiagnostics.shared.snapshot()
    #expect(after["storageObjectReads", default: 0] == before["storageObjectReads", default: 0])
    #expect(model.entries.count == 1 && model.inspection == nil && model.image == nil)
    let result = try #require(model.entries.first?.reference)
    await model.inspect(result)
    let inspection = try #require(model.inspection)
    #expect(inspection.result == result && inspection.drawing == fixture.reference)
    #expect(inspection.jobs.count == 1 && inspection.jobs.first?.disposition == "refused")
    #expect(inspection.snapshots.isEmpty && inspection.media.isEmpty)
    let copied = fixture.root.appendingPathComponent("returned-result-copy.zip")
    await browser.exportResult(result, to: copied)
    #expect(browser.error == nil)
    let secondLibrary = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("second-cold-result"),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    #expect(try await secondLibrary.mountResult(from: copied).reference == result)
    await secondLibrary.closeLibrary()
    // Re-import is idempotent and cannot manufacture another job or attempt.
    await browser.importResult(from: carrier, route: binding)
    #expect(try await library.results(for: fixture.reference).entries.count == 1)
    #expect(try await library.attempts(for: fixture.reference).entries.isEmpty)
    #expect(try await library.records(kind: "adaptiveplotter.destination.job").isEmpty)
    model.close(); browser.close(); await sketches.shutdown(); await library.closeLibrary(); await fixture.library.closeLibrary()
  }

  @Test("Closing the inspector during the actual cold Library read prevents late result and image adoption")
  func closedInspectionCannotAdopt() async throws {
    let (fixture, carrier) = try await refusedResult()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let library = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("closed-result"),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let mounted = try await library.mountResult(from: carrier)
    let gate = ResultInspectionGate()
    let model = DrawingResultReviewModel(library: library, drawing: fixture.reference, readResult: { reference in
      let value = try await library.result(reference)
      await gate.wait()
      return value
    })
    await model.load()
    let reading = Task { await model.inspect(mounted.reference) }
    try await gate.waitUntilEntered()
    model.close(); gate.release(); await reading.value
    #expect(model.isClosed && !model.isBusy && model.inspection == nil && model.image == nil && model.error == nil)
    #expect(try await library.results(for: fixture.reference).entries.count == 1)
    await library.closeLibrary(); await fixture.library.closeLibrary()
  }

  @Test("A different Drawing occurrence cannot discover or inspect a mounted result with equal geometry")
  func exactOccurrenceOnly() async throws {
    let (fixture, carrier) = try await refusedResult()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let library = DrawingLibrary(directoryURL: fixture.root.appendingPathComponent("exact-result"),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    let mounted = try await library.mountResult(from: carrier)
    let original = try await library.drawing(fixture.reference)
    let other = try Drawing(program: original.program, input: original.input, parent: .none,
      producer: original.producer, units: original.units)
    let otherRef = try await library.retain(other, reason: "distinct equal geometry").reference
    #expect(otherRef != fixture.reference)
    let model = DrawingResultReviewModel(library: library, drawing: otherRef)
    await model.load(); await model.inspect(mounted.reference)
    #expect(model.entries.isEmpty && model.inspection == nil && model.image == nil)
    model.close(); await library.closeLibrary(); await fixture.library.closeLibrary()
  }

  @Test("Real native accepted and interrupted carriers cold-mount and expose exact cumulative facts and original pixels",
    .enabled(if: ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT"] != nil))
  func nativeAcceptedCarriers() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT"])
    let source = URL(fileURLWithPath: path, isDirectory: true)
    let carriers = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension.lowercased() == "zip" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    try #require(!carriers.isEmpty, "The native result suite must export real carriers before this integration gate")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-result-cold-review-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var accepted = false, originalMedia = false, provisional = false, sealed = false
    for (index, carrier) in carriers.enumerated() {
      let library = DrawingLibrary(directoryURL: root.appendingPathComponent(String(index)),
        payloadValidators: DrawingDestinationResult.payloadValidators)
      let mounted = try await library.mountResult(from: carrier)
      let package = try await library.result(mounted.reference)
      let drawing = try #require(package.index.known?.roots.first)
      let model = DrawingResultReviewModel(library: library, drawing: drawing)
      await model.load(); await model.inspect(mounted.reference)
      let inspection = try #require(model.inspection)
      #expect(inspection.drawing == drawing && inspection.result == mounted.reference && model.error == nil)
      #expect(inspection.snapshots.count == package.attempts.values.filter { $0.drawing == drawing }.count)
      #expect(inspection.snapshots.filter(\.isSelectedRoot).map(\.id) == package.index.known?.attempts)
      accepted = accepted || inspection.jobs.contains { $0.disposition == "accepted" }
      provisional = provisional || inspection.snapshots.contains { !$0.sealed }
      sealed = sealed || inspection.snapshots.contains { $0.sealed }
      for snapshot in inspection.snapshots {
        #expect(snapshot.frontiers.count == 4)
        #expect(snapshot.frontiers.contains { $0.hasPrefix("inkVerified:") })
        if snapshot.id.sequence > 1 { #expect(snapshot.previous != nil) }
        let originalSnapshot = try #require(package.attempts[snapshot.id])
        let coverage = try ExchangeJSON.validate(package.files.record(originalSnapshot.coverage))
        let entries = try #require(coverage["entries"] as? [[String: Any]])
        for entry in entries where entry["status"] as? String == "present" {
          let kind = try #require(entry["kind"] as? String)
          if !["adaptiveplotter.raw-baseline", "adaptiveplotter.raw-progress", "adaptiveplotter.raw-terminal"].contains(kind) {
            #expect(snapshot.declared.contains { $0.hasPrefix(kind + ": declared present;") })
            #expect(!snapshot.missing.contains { $0.hasPrefix(kind + ":") })
          }
        }
      }
      if let media = inspection.media.first {
        await model.showMedia(media)
        #expect(model.image != nil && model.imageDetail?.contains("not an ink or motion verification") == true)
        originalMedia = originalMedia || model.image != nil
      }
      model.close(); await library.closeLibrary()
    }
    #expect(accepted && originalMedia && provisional && sealed)
  }

  @Test("An attributed supplement preserves verified sealed coverage and original media without retry authority",
    .enabled(if: ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT"] != nil))
  func attributedSupplementKeepsNativeScope() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_RESULT_FIXTURE_OUTPUT"])
    let source = URL(fileURLWithPath: path).appendingPathComponent("native-source-free-terminal.zip")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("native-supplement-review-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let staged = try DrawingExchangeCarrier.stageZIP(source, stagingParent: root)
    let original = try ExchangeAdmission.validate(staged, payloadValidators: DrawingDestinationResult.payloadValidators)
    let snapshot = try #require(original.index.known?.attempts.first)
    let drawing = try #require(original.attempts[snapshot]?.drawing)
    let fixture = try supplement(staged, snapshot: snapshot, parent: root)
    let library = DrawingLibrary(directoryURL: root.appendingPathComponent("cold"), payloadValidators: DrawingDestinationResult.payloadValidators)
    let baseMount = try await library.mountResult(from: source)
    let mounted = try await library.mountResult(from: fixture)
    let admitted = try await library.result(mounted.reference)
    #expect(baseMount.reference != mounted.reference && admitted.attempts[snapshot]?.originalJSON == original.attempts[snapshot]?.originalJSON)
    #expect(!admitted.capabilities.supported.contains(.interpretResults))
    #expect(admitted.interpretableAttempts.contains(snapshot))
    #expect(!admitted.capabilities.supported.contains(.physicalInterpretation) && !admitted.capabilities.supported.contains(.train))
    let model = DrawingResultReviewModel(library: library, drawing: drawing)
    await model.load(); await model.inspect(mounted.reference)
    let value = try #require(model.inspection)
    #expect(value.snapshots.first?.sealed == true && value.snapshots.first?.frontiers.count == 4)
    #expect(value.annotations.count == 1 && value.annotations.first?.reviewer.contains("native-review-fixture") == true)
    #expect(value.annotations.first?.targets == ["Snapshot \(snapshot.archive)/\(snapshot.run)/\(snapshot.sequence)/\(snapshot.digest)"])
    #expect(value.annotations.first?.declaredAnswer.contains("Attributed fixture note") == true)
    let media = try #require(value.media.first)
    await model.showMedia(media)
    #expect(model.image != nil && model.error == nil)
    #expect(try await library.records(kind: "adaptiveplotter.destination.job").isEmpty)
    // Unknown enclosing requirements still block the selected native scope.
    let blockedSource = try supplement(staged, snapshot: snapshot, parent: root, unknownIndexRequirement: true)
    let blocked = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(blockedSource, stagingParent: root),
      payloadValidators: DrawingDestinationResult.payloadValidators)
    #expect(blocked.interpretableAttempts.isEmpty)
    // This is a coherent alternative initial carrier, not a supplemental
    // revision of the sealed snapshot already mounted above. Keep it cold and
    // independent so the immutability check remains fully exercised.
    let extensionLibrary = DrawingLibrary(directoryURL: root.appendingPathComponent("cold-extension"), payloadValidators: DrawingDestinationResult.payloadValidators)
    let extensionModel = DrawingResultReviewModel(library: extensionLibrary, drawing: drawing)
    let extensionSource = try supplement(staged, snapshot: snapshot, parent: root, vendorImage: true)
    let extensionMount = try await extensionLibrary.mountResult(from: extensionSource)
    await extensionModel.load(); await extensionModel.inspect(extensionMount.reference)
    let extensionReview = try #require(extensionModel.inspection)
    #expect(extensionReview.media.count == value.media.count)
    #expect(extensionReview.media.allSatisfy { !$0.capture.contains("fabricated-extension-frame") && $0.kind != "vendor.synthetic/1" })
    #expect(extensionReview.snapshots.contains { $0.declared.contains { $0.contains("vendor.synthetic/1: declared present;") } })
    #expect(extensionReview.snapshots.allSatisfy { !$0.missing.contains { $0.hasPrefix("vendor.synthetic/1:") } })
    #expect(extensionReview.snapshots.first?.frontiers.count == 4)
    extensionModel.close(); await extensionLibrary.closeLibrary()
    model.close(); await library.closeLibrary()
  }

  private func supplement(_ staged: StagedExchangePackage, snapshot: SnapshotRef, parent: URL,
    unknownIndexRequirement: Bool = false, vendorImage: Bool = false) throws -> URL {
    let destination = parent.appendingPathComponent("supplement-" + UUID().uuidString)
    try DrawingExchangeCarrier.preserveDirectory(staged.files, to: destination)
    func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    var index = try ExchangeJSON.validate(staged.indexJSON)
    var inventory = staged.files.entries.filter { $0.key.hasPrefix("data/") }.mapValues(\.digest)
    var target = snapshot
    if vendorImage {
      let image = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
      image.bitmapData?.update(repeating: 255, count: 4)
      let png = try #require(image.representation(using: .png, properties: [:]))
      let asset = try ExchangeAsset(bytes: png, mediaType: "image/png", encoding: "png")
      let imagePath = "data/objects/sha256/" + asset.object.description
      try png.write(to: destination.appendingPathComponent(imagePath))
      inventory[imagePath] = asset.object
      var descriptors = try #require(index["assets"] as? [[String: Any]])
      descriptors.append(try #require(try object(ExchangeAssetDescriptor(asset: asset)) as? [String: Any]))
      index["assets"] = descriptors
      let attemptPath = "data/attempts/\(snapshot.archive.uuidString.lowercased())/\(snapshot.run.uuidString.lowercased())/\(snapshot.sequence)/attempt.json"
      var attempt = try ExchangeJSON.validate(staged.files.record(at: attemptPath))
      let coverageDigest = try JSONDecoder().decode(ExchangeDigest.self, from: JSONSerialization.data(withJSONObject: attempt["coverage"]!, options: .fragmentsAllowed))
      var coverage = try ExchangeJSON.validate(staged.files.record(coverageDigest))
      var entries = try #require(coverage["entries"] as? [[String: Any]])
      entries.append(["kind": "vendor.synthetic/1", "status": "present", "asset": try object(asset),
        "rawFrameID": "fabricated-extension-frame", "rawCaptureTicks": "123456789", "captureClock": "vendor-clock"])
      coverage["entries"] = entries
      let coverageBytes = try JSONSerialization.data(withJSONObject: coverage, options: .sortedKeys)
      let coverageAsset = try ExchangeAsset(bytes: coverageBytes, mediaType: "application/json", encoding: "adaptiveplotter.native-coverage/1")
      let coveragePath = "data/objects/sha256/" + coverageAsset.object.description
      try coverageBytes.write(to: destination.appendingPathComponent(coveragePath))
      inventory[coveragePath] = coverageAsset.object
      descriptors.append(try #require(try object(ExchangeAssetDescriptor(asset: coverageAsset)) as? [String: Any]))
      index["assets"] = descriptors
      attempt["coverage"] = coverageAsset.object.description
      let attemptBytes = try JSONSerialization.data(withJSONObject: attempt, options: .sortedKeys)
      try attemptBytes.write(to: destination.appendingPathComponent(attemptPath), options: .atomic)
      inventory[attemptPath] = .hash(attemptBytes)
      target = try SnapshotRef(archive: snapshot.archive, run: snapshot.run, sequence: snapshot.sequence, digest: .hash(attemptBytes))
      index["attempts"] = [try object(target)]
    }
    let identity = ExchangeIdentity(issuer: UUID())
    let note: [String: Any] = ["profile": "adaptiveplotter.assessment/1", "requiredFeatures": [],
      "ref": try object(identity), "targets": [["kind": "attempt", "ref": try object(target)]],
      "reviewer": ["kind": "human", "id": "native-review-fixture"],
      "question": ["id": "example.raw-review-note", "version": "1", "text": "Declared review note"],
      "time": ["wallTime": "2026-11-11T12:00:00Z"],
      "answer": ["type": "example.note/1", "value": "Attributed fixture note"], "supportingAssets": []]
    let bytes = try JSONSerialization.data(withJSONObject: note, options: [.sortedKeys])
    let ref = AssessmentRef(issuer: identity.issuer, revision: identity.revision, digest: .hash(bytes))
    let recordPath = "data/assessments/\(identity.issuer.uuidString.lowercased())/\(identity.revision.uuidString.lowercased()).json"
    let recordURL = destination.appendingPathComponent(recordPath)
    try FileManager.default.createDirectory(at: recordURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: recordURL)
    index["assessments"] = [try object(ref)]
    if unknownIndexRequirement { index["requiredFeatures"] = ["example.unknown-native-review/1"] }
    let indexBytes = try JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    try indexBytes.write(to: destination.appendingPathComponent("data/exchange.json"), options: .atomic)
    inventory["data/exchange.json"] = .hash(indexBytes); inventory[recordPath] = .hash(bytes)
    let manifest = Data(inventory.keys.sorted().map { inventory[$0]!.description + "  " + $0 + "\n" }.joined().utf8)
    try manifest.write(to: destination.appendingPathComponent("manifest-sha256.txt"), options: .atomic)
    let tags = ["bagit.txt": try #require(staged.files.entries["bagit.txt"]?.digest), "manifest-sha256.txt": ExchangeDigest.hash(manifest)]
    let tagManifest = Data(tags.keys.sorted().map { tags[$0]!.description + "  " + $0 + "\n" }.joined().utf8)
    try tagManifest.write(to: destination.appendingPathComponent("tagmanifest-sha256.txt"), options: .atomic)
    return destination
  }
}

@MainActor private final class ResultInspectionGate {
  private var waiting: CheckedContinuation<Void, Never>?
  private var entered = false
  func wait() async { entered = true; await withCheckedContinuation { waiting = $0 } }
  func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !entered, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(entered)
  }
  func release() { let continuation = waiting; waiting = nil; continuation?.resume() }
}
