import Foundation
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Material persistence integration", .serialized)
@MainActor
struct DrawingMaterialPersistenceIntegrationTests {
  @Test("measurement archive digest survives multiple capture sessions and fresh processes")
  func multiSessionArchive() async throws {
    let retainedPath = ProcessInfo.processInfo.environment["ADAPTIVEPLOTTER_MATERIAL_PROCESS_FIXTURE"]
    let directory = retainedPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
      ?? FileManager.default.temporaryDirectory.appendingPathComponent("material-process-\(UUID())")
    defer { if retainedPath == nil { try? FileManager.default.removeItem(at: directory) } }
    let store = DrawingMaterialStore(directoryURL: directory)
    if !FileManager.default.fileExists(atPath: directory.appendingPathComponent("index-v1.json").path) {
      let fixture = try await CompleteAcceptedLearningFixture.make()
      var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.registration)) as? [String: Any])
      let sessions = fixture.registration.captureSessionIDs.union([CameraCaptureSessionID(), CameraCaptureSessionID(), CameraCaptureSessionID()])
      object["captureSessionIDs"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sessions))
      let registration = try JSONDecoder().decode(TipCameraRegistration.self, from: JSONSerialization.data(withJSONObject: object))
      let domain = registration.applicabilityRectangle
      let geometry = try Polyline<MachineSpace>(points: [Point2(x: domain.minX, y: domain.minY), Point2(x: domain.maxX, y: domain.minY)])
      let measurement = DrawingMaterialMeasurement(algorithmRevision: "archive-fixture-no-width-claim",
        registration: registration, geometry: [geometry], qualification: .unavailable,
        distribution: nil, samples: [], limitations: ["Unresolved synthetic fixture; no measured width asserted"],
        source: fixture.frame.source, singleFrame: ExactFrameProvenance(frame: fixture.frame.frame),
        observationMode: .existingInkLocalContrast)
      let profile = try DrawingMaterialProfileRevision(name: "Multiple capture sessions", nominalWidthMM: 1,
        qualification: .unavailable, measurementEvidenceID: measurement.id)
      let record = try DrawingMaterialRecord(profile: profile,
        applicability: DrawingMaterialApplicability(registration: registration, paperStock: "Synthetic paper",
          drawingFeedMMPerMinute: 500, penActuationProfile: .initialDefaults), measurement: measurement)
      try await store.save(.init(records: [record], activeKey: profile.key,
        revisionDigests: [profile.key: DrawingMaterialSnapshot.digest(record)]))
    }
    let snapshot = try await store.load()
    let record = try #require(snapshot.records.first)
    #expect(try #require(record.measurement).registration.captureSessionIDs.count >= 3)
    let expected = try #require(snapshot.revisionDigests[record.profile.key])
    for _ in 0..<12 {
      let decoded = try JSONDecoder().decode(DrawingMaterialRecord.self, from: JSONEncoder().encode(record))
      #expect(try DrawingMaterialSnapshot.digest(decoded) == expected)
    }
    try await DrawingMaterialStore(directoryURL: directory).save(snapshot)
    #expect(try await store.load().records == snapshot.records)
    print("Material archive verified in process \(ProcessInfo.processInfo.processIdentifier): \(expected)")
  }

  @Test("production observation composition joins a held material write before shutdown completes")
  func shutdownJoinsMaterialWrite() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("material-shutdown-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = HeldMaterialWrite()
    defer { gate.release.signal() }
    let library = DrawingMaterialLibrary(store: .init(directoryURL: directory, write: { bytes, url in
      gate.entered.signal()
      guard gate.release.wait(timeout: .now() + 10) == .success else { throw CocoaError(.fileWriteUnknown) }
      try bytes.write(to: url, options: .atomic)
    }))
    let fixture = makeCausalSimulatorAppFixture(
      observationSession: CameraComposition.makeIsolatedObservationSessionForTesting(), drawingMaterials: library)
    #expect(library.createNominal(name: "Held save", widthMM: 0.8) == nil)
    let entered: Bool = await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: gate.entered.wait(timeout: .now() + 5) == .success)
      }
    }
    #expect(entered)
    var finished = false
    let shutdown = Task { await fixture.workspace.shutdown(); finished = true }
    try await Task.sleep(for: .milliseconds(200))
    #expect(!finished)
    #expect(library.isSaving)
    gate.release.signal()
    await shutdown.value
    #expect(finished)
    #expect(library.persistenceError == nil)
    #expect(library.pendingMutationCount == 0)
    let restored = try await DrawingMaterialStore(directoryURL: directory).load()
    #expect(restored.records.first?.profile.name == "Held save")
    #expect(restored.activeKey == library.activeKey)
  }

  @Test("revision allocation preserves deleted identities before and after reload")
  func deletedRevisionAllocation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("material-revisions-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    #expect(library.createNominal(name: "Revisioned", widthMM: 0.8) == nil)
    let prior = try #require(library.activeRecord)
    let later = try DrawingMaterialRecord(profile: .init(id: prior.profile.id, revision: 2,
      name: prior.profile.name, nominalWidthMM: 1))
    #expect(library.add(later) == nil)
    #expect(library.delete(key: later.profile.key) == nil)
    #expect(library.nextRevision(for: prior.profile.id) == 3)
    await library.flush()
    let restored = DrawingMaterialLibrary(store: .init(directoryURL: directory))
    await restored.load()
    #expect(restored.nextRevision(for: prior.profile.id) == 3)
  }
}

private final class HeldMaterialWrite: @unchecked Sendable {
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
}
