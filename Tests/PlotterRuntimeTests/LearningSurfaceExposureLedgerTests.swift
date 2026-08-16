import Foundation
import PlotterModel
@testable import PlotterRuntime
import Testing

@Suite("Learning surface exposure ledger")
struct LearningSurfaceExposureLedgerTests {
  @Test("one owner may reserve one geometry on a paper and finalize Pen Up once")
  func ownerAndFinalizerUniqueness() throws {
    let paper = PaperContactPlaneRevision()
    let first = try sparseExposure(position: .center, paper: paper)
    var ledger = LearningSurfaceExposureLedger()
    try ledger.reserve(first)

    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try ledger.reserve(try sparseExposure(position: .center, paper: paper))
    }

    let finalization = LearningSurfacePenUpFinalization(
      reason: .circleCompleted,
      outcome: .commandedAndSettled(command: .raise, commandedState: .up),
      attemptedNanoseconds: 20
    )
    try ledger.recordPenUpFinalization(for: first.id, finalization: finalization)
    #expect(ledger.entries.first?.penUpFinalization == finalization)
    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try ledger.recordPenUpFinalization(for: first.id, finalization: finalization)
    }
  }

  @Test("geometry kind must match its owner and remain nondegenerate")
  func geometryValidation() throws {
    let paper = PaperContactPlaneRevision()
    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try LearningSurfaceExposure(
        provenance: .simulatedNonphysical,
        paperContactPlane: paper,
        owner: .sparseTipMark(.center),
        geometry: .isolatedLine(
          startPosition: try MachinePosition(x: 0, y: 0),
          endPosition: try MachinePosition(x: 1, y: 0)
        ),
        reservedNanoseconds: 1
      )
    }
    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try LearningSurfaceExposure(
        provenance: .simulatedNonphysical,
        paperContactPlane: paper,
        owner: .drawingTrial(AttemptGroupIdentity(rawValue: "trial")),
        geometry: .isolatedLine(
          startPosition: try MachinePosition(x: 0, y: 0),
          endPosition: try MachinePosition(x: 0, y: 0)
        ),
        reservedNanoseconds: 1
      )
    }
  }

  @Test("LIVE store round-trips checksum-protected exposure and finalization")
  func liveStoreRoundTrip() throws {
    let fixture = storeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let paper = PaperContactPlaneRevision()
    let exposure = try sparseExposure(position: .center, paper: paper)
    var ledger = LearningSurfaceExposureLedger()
    try ledger.reserve(exposure)
    try ledger.recordPenUpFinalization(
      for: exposure.id,
      finalization: LearningSurfacePenUpFinalization(
        reason: .circleCompleted,
        outcome: .commandedAndSettled(command: .raise, commandedState: .up),
        attemptedNanoseconds: 20
      )
    )

    let saved = try fixture.store.save(
      expectedRevision: .absent,
      ledger,
      currentPaperContactPlane: paper
    )
    guard case .loaded(let loaded) = fixture.store.load() else {
      Issue.record("Expected the saved ledger to load.")
      return
    }
    #expect(loaded == saved)
    #expect(loaded.checkpoint.ledger == ledger)
  }

  @Test("LIVE store rejects simulated exposure")
  func liveStoreRejectsSimulation() throws {
    let fixture = storeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let paper = PaperContactPlaneRevision()
    var ledger = LearningSurfaceExposureLedger()
    try ledger.reserve(
      LearningSurfaceExposure(
        provenance: .simulatedNonphysical,
        paperContactPlane: paper,
        owner: .drawingTrial(AttemptGroupIdentity(rawValue: "simulated")),
        geometry: .isolatedLine(
          startPosition: try MachinePosition(x: 0, y: 0),
          endPosition: try MachinePosition(x: 5, y: 0)
        ),
        reservedNanoseconds: 1
      )
    )

    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try fixture.store.save(
        expectedRevision: .absent,
        ledger,
        currentPaperContactPlane: paper
      )
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.store.fileURL.path))
  }

  @Test("two store instances reread under one path lock and reject stale save")
  func twoInstanceCAS() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("surface.json")
    let first = LiveLearningSurfaceExposureStore(fileURL: url)
    let second = LiveLearningSurfaceExposureStore(fileURL: url)
    let paper = PaperContactPlaneRevision()
    var firstLedger = LearningSurfaceExposureLedger()
    try firstLedger.reserve(try sparseExposure(position: .center, paper: paper))
    var staleLedger = LearningSurfaceExposureLedger()
    try staleLedger.reserve(try sparseExposure(position: .negativeX, paper: paper))

    let committed = try first.save(
      expectedRevision: .absent,
      firstLedger,
      currentPaperContactPlane: paper
    )
    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try second.save(
        expectedRevision: .absent,
        staleLedger,
        currentPaperContactPlane: paper
      )
    }
    guard case .loaded(let final) = second.load() else {
      Issue.record("The first saved ledger should remain readable.")
      return
    }
    #expect(final.revision == committed.revision)
    #expect(final.checkpoint.ledger == firstLedger)
  }

  @Test("corrupt bytes require Paper Replacement and remain archived")
  func corruptRecovery() throws {
    let fixture = storeFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    let oldPaper = PaperContactPlaneRevision()
    var ledger = LearningSurfaceExposureLedger()
    try ledger.reserve(try sparseExposure(position: .center, paper: oldPaper))
    _ = try fixture.store.save(
      expectedRevision: .absent,
      ledger,
      currentPaperContactPlane: oldPaper
    )
    var bytes = try Data(contentsOf: fixture.store.fileURL)
    bytes[bytes.count / 2] ^= 0x01
    try bytes.write(to: fixture.store.fileURL)

    guard case .rejected(_, let rejectedRevision) = fixture.store.load() else {
      Issue.record("Tampered safety history must be rejected.")
      return
    }
    #expect(throws: LearningSurfaceExposureLedgerError.self) {
      try fixture.store.save(
        expectedRevision: rejectedRevision,
        LearningSurfaceExposureLedger(),
        currentPaperContactPlane: oldPaper
      )
    }

    let newPaper = PaperContactPlaneRevision()
    let recovered = try fixture.store.recoverForPaperReplacement(
      expectedRevision: rejectedRevision,
      newPaper
    )
    #expect(recovered.checkpoint.currentPaperContactPlane == newPaper)
    #expect(recovered.checkpoint.ledger.entries.isEmpty)
    let archives = try FileManager.default.contentsOfDirectory(
      at: fixture.store.corruptArchiveDirectoryURL,
      includingPropertiesForKeys: nil
    )
    #expect(archives.count == 1)
    #expect(try Data(contentsOf: archives[0]) == bytes)
    guard case .loaded(let loaded) = fixture.store.load() else {
      Issue.record("Recovered new-paper safety history should load.")
      return
    }
    #expect(loaded == recovered)
  }
}

private func sparseExposure(
  position: ToolContactCalibrationPosition,
  paper: PaperContactPlaneRevision
) throws -> LearningSurfaceExposure {
  try LearningSurfaceExposure(
    provenance: .livePossiblePhysicalInk,
    paperContactPlane: paper,
    owner: .sparseTipMark(position),
    geometry: .sparseCalibrationCircle(
      center: MachinePosition(x: Double(position.rawValue.count), y: 0),
      radiusMM: 2
    ),
    reservedNanoseconds: 10
  )
}

private func storeFixture() -> (
  directory: URL,
  store: LiveLearningSurfaceExposureStore
) {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  return (
    directory,
    LiveLearningSurfaceExposureStore(
      fileURL: directory.appendingPathComponent("surface.json"),
      corruptArchiveDirectoryURL: directory.appendingPathComponent(
        "CorruptArchive",
        isDirectory: true
      )
    )
  )
}
