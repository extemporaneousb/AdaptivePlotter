import CoreGraphics
import Foundation
import DrawingLibrary
import ImageIO
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Flow Edge dojo autosaved interaction", .serialized)
@MainActor
struct FlowDojoTests {
  @Test("Failed Rank publication preserves the comparison and durable recovery records one response without geometry", arguments: [LibraryExchangeCatalogBoundary.beforeSQLPublication, .afterSQLCommit])
  func canonicalRankFailure(boundary: LibraryExchangeCatalogBoundary) async throws {
    let directory = DrawingExchangeFeedbackFixture.root()
    defer { try? FileManager.default.removeItem(at: directory) }
    let library = DrawingLibrary(directoryURL: directory)
    let model = FlowDojoModel(directory: directory, library: library, purpose: .validationFixture, render: FlowDojoFixture.render)
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(1), title: "Rank failure")
    model.count = 3; await model.generate(refining: false)
    let round = try #require(model.round)
    await model.presentRanking(scope: .round(round.id), count: 2)
    let presentation = try #require(model.presentation)
    let previousRanks = model.ranks
    try await library.feedbackFault(boundary)
    await model.compare(preferred: presentation.items[0].id)
    #expect(model.needsRecovery && model.error != nil)
    #expect(model.presentation?.id == presentation.id && model.ranks == previousRanks)
    #expect(try await library.drawings().entries.isEmpty)
    try await library.feedbackFault(nil)
    await model.recoverAutosave()
    #expect(!model.needsRecovery && model.error == nil)
    #expect(model.document?.rankings.filter { $0.presentationID == presentation.id }.count == 1)
    let committed = try #require(model.document?.rankings.first { $0.presentationID == presentation.id })
    let store = try #require(model.store)
    let reference = try await store.feedbackReference(for: committed.id)
    #expect(try await library.feedback(reference.publication).rankingCapsules.count == 1)
    await model.recoverAutosave()
    #expect(model.document?.rankings.filter { $0.presentationID == presentation.id }.count == 1)
    #expect(try await library.drawings().entries.isEmpty)
    #expect(await model.shutdown())
    await library.closeLibrary()
    let reopened = DrawingLibrary(directoryURL: directory)
    let cold = FlowPortfolioStore(directory: directory, purpose: .validationFixture, library: reopened)
    try await cold.loadRecords()
    #expect(await cold.snapshot().rankings.filter { $0.presentationID == presentation.id }.count == 1)
    #expect(try await reopened.drawings().entries.isEmpty)
    await reopened.closeLibrary()
  }

  @Test("An invalid source image is refused before mutation and does not block subsequent valid capture")
  func invalidSourceIsAdmissionFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    await model.open()
    let revision = model.document?.revision
    await model.addPhoto(data: Data("not a PNG or JPEG".utf8), title: "Invalid source")
    #expect(model.error != nil && !model.needsRecovery)
    #expect(model.document?.sources.isEmpty == true && model.document?.revision == revision)
    await model.importPhotoCollection(directory.appendingPathComponent("missing-photo-set"))
    #expect(model.error != nil && !model.needsRecovery && model.document?.sources.isEmpty == true)
    await model.addPhoto(data: FlowDojoFixture.image(1), title: "Valid source after refusal")
    #expect(model.error == nil && !model.needsRecovery && model.document?.sources.count == 1)
    #expect(await model.shutdown())
  }

  @Test("Typed admission rejects invalid authoring units for overrides and exact parent reuse")
  func liveAdmission() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, nominalPenWidthMM: -1,
      purpose: .validationFixture, render: FlowDojoFixture.render)
    model.count = 3
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(2), title: "Admission source")
    await model.generate(refining: false)
    #expect(model.roundCandidates.isEmpty)
    #expect(model.round?.failures.count == 3)
    let style = model.strokeStyle
    model.updateStrokeStyle(style, nominalPenWidthMM: 0.6)
    await model.generate(refining: false)
    #expect(model.roundCandidates.count == 3)
    let parent = try #require(model.roundCandidates.first)
    await model.selectCandidate(parent.id)
    let original = try #require(model.program)
    model.updateStrokeStyle(style, nominalPenWidthMM: -1)
    await model.generate(refining: true)
    // Slot zero bypasses rendering, but cannot bypass common Drawing admission.
    #expect(model.roundCandidates.isEmpty)
    #expect(try await model.store?.candidateProgram(parent.id) == original)
    await model.shutdown()
  }

  @Test("Photo, broad round, exact anchor refinement and pruning survive reopening without Save")
  func autosavedJourney() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    model.count = 3
    await model.open(); #expect(model.error == nil)
    await model.addPhoto(data: FlowDojoFixture.image(1), title: "Synthetic source")
    await model.generate(refining: false)
    #expect(model.error == nil); #expect(model.roundCandidates.count == 3)
    let chosen = try #require(model.roundCandidates.first)
    await model.selectCandidate(chosen.id, prune: true)
    let original = try #require(model.program), first = try #require(original.strokes.first)
    await model.edit(.remove, ids: [first.id]); #expect(model.removedIDs == [first.id])
    await model.edit(.undo); #expect(model.removedIDs.isEmpty)
    await model.edit(.redo); #expect(model.removedIDs == [first.id])
    await model.edit(.completeTarget)
    let exactMask = model.removedIndices
    let completed = try #require(model.prune)
    await model.generate(refining: true)
    #expect(model.error == nil)
    let anchor = try #require(model.roundCandidates.first(where: { $0.slot == 0 }))
    #expect(try await model.store?.candidateProgram(anchor.id) == original)
    let inherited = try #require(model.document?.latestPrune(candidateID: anchor.id))
    #expect(Set(inherited.removedIndices) == exactMask)
    #expect(inherited.action == .inheritedSelection)
    #expect(inherited.inheritedFromRevisionID == completed.id)
    await model.presentRanking(scope: .candidate(chosen.id))
    let presentation = try #require(model.presentation)
    for (index, item) in presentation.items.enumerated() { await model.rank(item: item.id, position: index + 1) }
    let ranks = model.ranks
    await model.shutdown()
    let reopened = FlowDojoModel(directory: directory, render: FlowDojoFixture.render)
    await reopened.open()
    #expect(reopened.error == nil)
    #expect(reopened.presentation?.id == presentation.id)
    #expect(reopened.ranks == ranks)
    #expect(reopened.document?.pruneRevisions.count == 5)
    await reopened.shutdown()
  }

  @Test("A failed autosave blocks later edits, retains their intent and retries without duplicate operations")
  func autosaveFailureRecovery() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(3), title: "Failure fixture")
    model.count = 3; await model.generate(refining: false)
    await model.selectCandidate(try #require(model.roundCandidates.first).id)
    let program = try #require(model.program), first = program.strokes[0].id, second = program.strokes[1].id
    let records = directory.appendingPathComponent("objects/sha256"), retained = directory.appendingPathComponent("objects/sha256-paused")
    try FileManager.default.moveItem(at: records, to: retained)
    try Data([0]).write(to: records)
    await model.edit(.remove, ids: [first])
    #expect(model.needsRecovery); #expect(model.removedIDs.isEmpty)
    await model.edit(.remove, ids: [second])
    #expect(model.removedIDs.isEmpty)
    try FileManager.default.removeItem(at: records)
    try FileManager.default.moveItem(at: retained, to: records)
    await model.recoverAutosave()
    #expect(!model.needsRecovery); #expect(model.error == nil)
    #expect(model.removedIDs == [first, second])
    #expect(model.document?.pruneRevisions.count == 2)
    await model.shutdown()
  }



  @Test("Source identity and training exclusion commit atomically; excluded photos can still make art")
  func sourceCurationFailureIsAtomic() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(4), title: "Curation failure fixture")
    let sourceID = try #require(model.selectedSource?.id)
    let records = directory.appendingPathComponent("objects/sha256"), retained = directory.appendingPathComponent("objects/sha256-paused")
    try FileManager.default.moveItem(at: records, to: retained); try Data([0]).write(to: records)
    await model.curateSource(sourceID: sourceID, subject: "Subject A", session: "Sitting 1", excluded: true)
    #expect(model.needsRecovery)
    let before = await model.store?.snapshot().sources.first
    #expect(before?.subjectID == nil); #expect(before?.sessionID == nil); #expect(before?.excluded == false)
    try FileManager.default.removeItem(at: records); try FileManager.default.moveItem(at: retained, to: records)
    await model.recoverAutosave()
    #expect(model.error == nil); #expect(model.selectedSource?.subjectID == "Subject A")
    #expect(model.selectedSource?.sessionID == "Sitting 1"); #expect(model.selectedSource?.excluded == true)
    model.count = 3; await model.generate(refining: false)
    #expect(model.error == nil); #expect(model.roundCandidates.count == 3)
    if let store = model.store {
      let dataset = try await DrawingExchangeFeedbackFixture.freezeInputs(store)
      #expect(dataset.examples.isEmpty)
    }
    #expect(await model.shutdown())
  }

  @Test("A frozen fit whose install fails retries the retained report once without losing the result")
  func fitInstallFailureRetainsReport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FlowDojoFitGate()
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture,
      fit: { _, _ in await gate.run() })
    await model.open()
    let fitting = Task { await model.fit() }
    await gate.waitForStart()
    #expect(await model.store?.snapshot().trainingSnapshots.count == 1)
    let records = directory.appendingPathComponent("objects/sha256"), retained = directory.appendingPathComponent("objects/sha256-paused")
    try FileManager.default.moveItem(at: records, to: retained); try Data([0]).write(to: records)
    await gate.release(); await fitting.value
    #expect(model.needsRecovery); #expect(model.fitReport?.checkpoint == nil)
    #expect(await model.store?.snapshot().fits.isEmpty == true)
    #expect(await model.shutdown() == false)
    try FileManager.default.removeItem(at: records); try FileManager.default.moveItem(at: retained, to: records)
    await model.recoverAutosave()
    #expect(model.error == nil); #expect(!model.needsRecovery)
    #expect(model.document?.trainingSnapshots.count == 1); #expect(model.document?.fits.count == 1)
    #expect(await gate.calls == 1)
    let fitID = try #require(model.document?.fits.first?.id)
    #expect(await model.shutdown())
    let reopened = FlowDojoModel(directory: directory)
    await reopened.open(); await reopened.showReport(fitID)
    #expect(reopened.error == nil)
    #expect(reopened.fitReport?.summary == "TEST FIXTURE unavailable result retained across install failure")
    #expect(reopened.document?.fits.first?.hasCheckpoint == false)
    #expect(await reopened.shutdown())
  }



  @Test("Repeated choices coalesce only when every offered output is identical")
  func choicesRetainChangedAlternatives() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(5), title: "Choice identity fixture")
    model.count = 3; await model.generate(refining: false)
    let a = try #require(model.roundCandidates.first), b = model.roundCandidates[1]
    await model.selectCandidate(a.id); await model.selectCandidate(a.id)
    await model.selectCandidate(b.id)
    let stroke = try #require(model.program?.strokes.first?.id)
    await model.edit(.remove, ids: [stroke])
    await model.selectCandidate(a.id); await model.selectCandidate(a.id)
    if let store = model.store {
      let dataset = try await DrawingExchangeFeedbackFixture.freezeInputs(store)
      let choices = dataset.rankings.filter { $0.provenance == .choice && $0.tiers.first == [a.id.uuidString] }
      try #require(choices.count == 2)
      #expect(choices[0].tiers != choices[1].tiers)
    }
    #expect(await model.shutdown())
  }



  @Test("New material styles affect future rounds while each admitted round keeps one frozen style")
  func materialStyleIsFrozenPerRound() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FlowDojoRenderGate()
    let first = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let second = try StrokeStyle(nominalLineWidth: 0.8, penProfileID: PenProfileID())
    let model = FlowDojoModel(directory: directory, strokeStyle: first, purpose: .validationFixture,
      render: { data, recipe, pen in
        await gate.suspendFirst()
        return try await FlowDojoFixture.render(data, recipe, pen)
      })
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(7), title: "Material context fixture")
    model.count = 3
    let rendering = Task { await model.generate(refining: false) }
    await gate.waitForStart(); model.updateStrokeStyle(second); await gate.release(); await rendering.value
    let originals = model.roundCandidates
    try #require(originals.count == 3)
    for candidate in originals {
      let program = try #require(try await model.store?.candidateProgram(candidate.id))
      #expect(program.strokes.allSatisfy { $0.style == first })
    }
    await model.selectCandidate(originals[0].id)
    await model.generate(refining: false)
    try #require(model.roundCandidates.count == 3)
    for candidate in model.roundCandidates {
      let program = try #require(try await model.store?.candidateProgram(candidate.id))
      #expect(program.strokes.allSatisfy { $0.style == second })
    }
    let retained = try #require(try await model.store?.candidateProgram(originals[0].id))
    #expect(retained.strokes.allSatisfy { $0.style == first })
    #expect(await model.shutdown())
  }

  @Test("Shutdown closes admission before awaiting render and prevents a late lazy owner from opening")
  func shutdownAdmissionIsClosedBeforeAwait() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let gate = FlowDojoRenderGate()
    let model = FlowDojoModel(directory: root.appendingPathComponent("active.flowportfolio"), purpose: .validationFixture,
      render: { data, recipe, pen in
        await gate.suspendFirst()
        return try await FlowDojoFixture.render(data, recipe, pen)
      })
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(1), title: "Before shutdown")
    let rendering = Task { await model.generate(refining: false) }
    await gate.waitForStart()
    let closing = Task { await model.shutdown() }
    while model.acceptsChanges { await Task.yield() }
    await model.addPhoto(data: FlowDojoFixture.image(2), title: "Late unadmitted photo")
    #expect(model.document?.sources.count == 1)
    await gate.release(); await rendering.value
    #expect(await closing.value); #expect(!model.acceptsChanges); #expect(model.store == nil)
    let lateURL = root.appendingPathComponent("late-library")
    let owner = PortraitStudioModel(library: DrawingLibrary(directoryURL: lateURL))
    #expect(await owner.preparePortfolioShutdown())
    let late = owner.portfolioDojo(strokeStyle: model.strokeStyle)
    await late.open()
    #expect(!late.acceptsChanges); #expect(late.store == nil)
    #expect(!FileManager.default.fileExists(atPath: lateURL.path))
    await owner.shutdown()
  }

  @Test("Quit joins the complete recovery drain, including edits admitted behind a paused fit")
  func shutdownJoinsRecoveryDrain() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let gate = FlowDojoFitGate()
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture,
      render: FlowDojoFixture.render, fit: { _, _ in await gate.run() })
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(8), title: "Recovery shutdown fixture")
    model.count = 3; await model.generate(refining: false)
    await model.selectCandidate(try #require(model.roundCandidates.first?.id))
    let program = try #require(model.program), first = program.strokes[0].id, second = program.strokes[1].id
    let records = directory.appendingPathComponent("objects/sha256"), retained = directory.appendingPathComponent("objects/sha256-paused")
    try FileManager.default.moveItem(at: records, to: retained); try Data([0]).write(to: records)
    await model.edit(.remove, ids: [first]); #expect(model.needsRecovery)
    await model.fit(); await model.edit(.remove, ids: [second])
    try FileManager.default.removeItem(at: records); try FileManager.default.moveItem(at: retained, to: records)
    let recovery = Task { await model.recoverAutosave() }
    await gate.waitForStart(); #expect(model.isBusy)
    let closing = Task { await model.shutdown() }
    while model.acceptsChanges { await Task.yield() }
    await gate.release(); await recovery.value
    #expect(await closing.value)
    #expect(model.removedIDs == [first, second]); #expect(model.document?.pruneRevisions.count == 2)
    #expect(model.document?.fits.count == 1); #expect(model.error == nil); #expect(model.store == nil)
    let reopened = FlowDojoModel(directory: directory)
    await reopened.open()
    #expect(reopened.removedIDs == [first, second]); #expect(reopened.document?.fits.count == 1)
    #expect(await reopened.shutdown())
  }

  @Test("Training budgets reject expanded rows before feature allocation")
  func trainingBudgetBeforeAllocation() throws {
    var strokes = FlowDojoTraining.Budget()
    #expect(throws: (any Error).self) { try strokes.admit(strokeCount: 10_001, revisionCount: 0, labelCount: 0) }
    var features = FlowDojoTraining.Budget()
    #expect(throws: (any Error).self) { try features.admit(strokeCount: 10_000, revisionCount: 9, labelCount: 0) }
    var labels = FlowDojoTraining.Budget()
    try labels.admit(strokeCount: 10_000, revisionCount: 0, labelCount: 10_000)
    try labels.admit(strokeCount: 10_000, revisionCount: 0, labelCount: 10_000)
    #expect(throws: (any Error).self) { try labels.admit(strokeCount: 1, revisionCount: 0, labelCount: 1) }
    var examples = FlowDojoTraining.Budget()
    try examples.admit(strokeCount: 1, revisionCount: 4_999, labelCount: 0)
    #expect(throws: (any Error).self) { try examples.admit(strokeCount: 1, revisionCount: 0, labelCount: 0) }
  }

  @Test("Stale completed targets do not override later explicit line corrections")
  func trainingSemantics() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = FlowDojoModel(directory: directory, purpose: .validationFixture, render: FlowDojoFixture.render)
    await model.open(); await model.addPhoto(data: FlowDojoFixture.image(2), title: "Synthetic")
    model.count = 3; await model.generate(refining: false)
    let candidate = try #require(model.roundCandidates.first)
    await model.selectCandidate(candidate.id)
    let program = try #require(model.program), first = program.strokes[0]
    await model.edit(.remove, ids: [first.id]); await model.edit(.completeTarget)
    await model.edit(.restore, ids: [first.id])
    let store = try #require(model.store)
    let data = try await DrawingExchangeFeedbackFixture.freezeInputs(store)
    let example = try #require(data.examples.first { $0.id == candidate.id.uuidString })
    #expect(example.strokeLabels.count == 1)
    #expect(example.strokeLabels[0].provenance == .restore)
    #expect(example.strokeLabels[0].removed == false)
    await model.shutdown()
  }
}

/// Explicit test oracle. It supplies varied vector fixtures for workflow tests;
/// real Flow Edge is covered by the opt-in integration trial.
enum FlowDojoFixture {
  static func image(_ index: Int) -> Data {
    let context = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
    context.setFillColor(CGColor(gray: Double(index % 7) / 10, alpha: 1)); context.fill(CGRect(x: 4, y: 4, width: 15 + index, height: 25))
    let bytes = NSMutableData(), destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil); CGImageDestinationFinalize(destination)
    return bytes as Data
  }
  static let render: @Sendable (Data, FlowArtistRecipe, StrokeStyle) async throws -> PortraitRenderResult = { data, recipe, pen in
    try Task.checkCancellation()
    let shift = recipe.values[3] * 9 + recipe.values[6] * 4
    let strokes = try (0..<16).map { index in
      let short = index < 8, x = short ? 8.0 : 45.0
      let y = 5.0 + Double(index % 8) * 11 + recipe.values[4] * 2
      return LogicalStroke(id: StrokeID(), path: try Polyline(points: [
        Point2(x: x, y: y), Point2(x: x + (short ? 3 + shift * 0.1 : 35 + shift), y: y + recipe.values[11] * 4)]),
        style: pen, ordering: UInt32(index))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100), strokes: strokes,
      source: .init(kind: "portrait", sourceIdentifier: "synthetic-dojo-loop|" + DrawingArtifactCoding.sha256(data)))
    let raster = PortraitRaster(width: 24, height: 24, luminance: (0..<576).map { Double($0 % 24) / 25 },
      provenance: "synthetic-dojo-loop", analysisSummary: "Test-only source evidence")
    return PortraitRenderResult(raster: raster, program: program)
  }
}

private actor FlowDojoFitGate {
  private var started = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var resume: CheckedContinuation<Void, Never>?
  private(set) var calls = 0
  func run() async -> FlowArtistFitReport {
    calls += 1; started = true
    for waiter in startedWaiters { waiter.resume() }; startedWaiters = []
    await withCheckedContinuation { resume = $0 }
    return .unavailable("TEST FIXTURE unavailable result retained across install failure")
  }
  func waitForStart() async {
    if started { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }
  func release() { resume?.resume(); resume = nil }
}

private actor FlowDojoRenderGate {
  private var started = false
  private var startedWaiters: [CheckedContinuation<Void, Never>] = []
  private var resume: CheckedContinuation<Void, Never>?
  func suspendFirst() async {
    guard !started else { return }
    started = true
    for waiter in startedWaiters { waiter.resume() }; startedWaiters = []
    await withCheckedContinuation { resume = $0 }
  }
  func waitForStart() async {
    if started { return }
    await withCheckedContinuation { startedWaiters.append($0) }
  }
  func release() { resume?.resume(); resume = nil }
}
