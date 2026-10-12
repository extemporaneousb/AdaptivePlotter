import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PortraitCore
import Testing
@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PlotterApp

private func reviewFixturePair(_ store: PortraitCandidateStore) async throws -> (SavedDrawing, SavedDrawing) {
  let capture = UUID(), library = UUID()
  let first = try transferTestPackage(captureID: capture, libraryID: library)
  let second = try transferTestPackage(captureID: capture, libraryID: library, resultBytes: Data("{\"frozenResult\":2}".utf8))
  let a = try await store.importDrawingPackage(DrawingPackageCodec.encode(first))
  let b = try await store.importDrawingPackage(DrawingPackageCodec.encode(second))
  return (a, b)
}

private func reviewRequest(package: DrawingPackage, id: UUID = UUID(), pilotID: UUID? = nil,
  groups: PortraitReviewGroups = .init(), split: PortraitReviewDatasetSplit = .unassigned) throws -> PortraitReviewGenerationRequest {
  try .init(id: id, captureID: package.origin.captureID, acquisitionID: nil,
    source: package.source, inputs: [.init(role: "artist-input", asset: package.artistInput)], groups: groups,
    artist: package.artist, environmentJSON: Data("{\"planned\":true}".utf8), conversionJSON: Data("{}".utf8), seed: 23,
    material: .init(widthMM: package.program.fieldExtent.width, heightMM: package.program.fieldExtent.height,
      nominalLineWidthMM: package.program.strokes[0].style.nominalLineWidth), pilotID: pilotID, split: split)
}

@Suite("Durable explicit portrait reviews", .serialized)
struct PortraitReviewStoreTests {
  @Test("Distinct native source hashes with retained common ancestry cannot cross declared splits")
  func nativeAncestrySplitGuards() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library")), family = UUID()
    func candidate(_ seed: UInt64, gray: Double) throws -> PortraitCandidate {
      let base = try portraitPersistenceCandidate(seed: seed)
      return try .init(sourceData: validReviewSourcePNG(gray: gray), sourcePixelExtent: base.sourcePixelExtent,
        raster: base.raster, recipe: base.recipe, program: base.program, photoID: UUID(), captureSessionID: UUID(),
        lineage: .init(parentID: nil, parentProgramHash: nil, parentRecipe: nil, ancestryGroupID: family))
    }
    let a = try candidate(801, gray: 0.2), b = try candidate(802, gray: 0.7)
    #expect(a.sourceSHA256 != b.sourceSHA256)
    try await store.save(snapshot: .init(entries: [.init(candidate: a, reasons: []), .init(candidate: b, reasons: [])]))
    let p = try await store.prepareReviewDrawing(.init(candidate: a))
    let q = try await store.prepareReviewDrawing(.init(candidate: b))
    let ga = PortraitReviewGroups(subjectID: "person-a", photoSessionID: "session-a", declaration: "fixture declaration")
    let gb = PortraitReviewGroups(subjectID: "person-b", photoSessionID: "session-b", declaration: "fixture declaration")
    _ = try await store.declareReviewGroups(origin: p.origin, groups: ga, split: .train)
    await #expect(throws: (any Error).self) { try await store.declareReviewGroups(origin: q.origin, groups: gb, split: .test) }
    _ = try await store.declareReviewGroups(origin: q.origin, groups: gb, split: .train)
    let manifest = try await store.exportReviewDataset(to: root.appendingPathComponent("export"))
    #expect(manifest.artifactDependencies.count == 2)
    #expect(manifest.groups.allSatisfy { $0.groups.ancestryIDs.isEmpty })
    #expect(manifest.results.allSatisfy { $0.split == .train })
  }

  @Test("Successful generation preserves actual runtime, raw curves, exact input and program bytes")
  func successfulGeneration() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let prototype = try transferTestPackage(libraryID: await store.reviewLibraryIdentity())
    let request = try reviewRequest(package: prototype)
    try await store.beginReviewGeneration(request)
    let package = try DrawingPackage(origin: prototype.origin, program: prototype.program,
      createdAt: request.createdAt.addingTimeInterval(1), title: prototype.title, resultRecordJSON: prototype.resultRecordJSON,
      source: prototype.source, artistInput: prototype.artistInput, artist: prototype.artist, preview: prototype.preview)
    let drawing = try await store.importDrawingPackage(DrawingPackageCodec.encode(package))
    let raw = PortraitReviewAsset(role: "raw-curves", asset: .init(mediaType: "application/json", bytes: Data("{\"fixtureCurves\":[1]}".utf8)))
    let observed = Data("{\"observedDevice\":\"fixture-only\"}".utf8)
    let metrics = Data("{\"durationSeconds\":0.25}".utf8)
    let outcome = try await store.finishReviewGeneration(id: request.id, status: .succeeded, drawing: drawing,
      outputs: [raw], now: request.createdAt.addingTimeInterval(2), runtimeEnvironmentJSON: observed, runtimeMetricsJSON: metrics)
    #expect(outcome.origin == package.origin)
    #expect(outcome.runtimeEnvironmentJSON == observed && outcome.runtimeMetricsJSON == metrics)
    let manifest = try await store.exportReviewDataset(to: root.appendingPathComponent("export"))
    #expect(manifest.counts.succeeded == 1 && manifest.counts.pending == 0 && manifest.results.count == 1)
    #expect(manifest.files.contains { $0.sha256 == raw.asset.sha256 })
    let result = try #require(manifest.results.first)
    #expect(result.requestID == request.id && result.sourceSHA256 == package.source.sha256)
    #expect(try Data(contentsOf: root.appendingPathComponent("export/assets/" + result.packageSHA256)) == DrawingPackageCodec.encode(package))
    #expect(try JSONDecoder().decode(DrawingProgram.self,
      from: Data(contentsOf: root.appendingPathComponent("export/assets/" + result.programSHA256))) == package.program)
  }

  @Test("Metadata paging does not decode source/input/package payloads; selected integrity still fails")
  func boundedMetadataPage() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root)
    let pair = try await reviewFixturePair(store)
    let comparison = try await store.createReviewComparison(first: pair.0, second: pair.1, presentationSeed: 14, rubricVersion: "1")
    let package = try await store.loadReviewPackage(origin: comparison.a.origin)
    let request = try reviewRequest(package: package)
    try await store.beginReviewGeneration(request)
    let packageFile = root.appendingPathComponent("review-v1/assets/" + comparison.a.packageSHA256)
    try Data("damaged".utf8).write(to: packageFile)
    let db = try PortraitLibraryDatabase(url: root.appendingPathComponent("library-v1.sqlite"), readOnly: true)
    let requestHash = try #require(try db.scalar("SELECT value FROM state WHERE key=?", ["review.request." + request.id.uuidString.lowercased()]))
    try Data("damaged".utf8).write(to: root.appendingPathComponent("review-v1/assets/" + requestHash))
    #expect(try await store.reviewComparisonPage().map(\.id) == [comparison.id])
    #expect(try await store.reviewGenerationPage().map(\.id) == [request.id])
    await #expect(throws: (any Error).self) { try await store.loadReviewComparison(id: comparison.id) }
    await #expect(throws: (any Error).self) { try await store.finishReviewGeneration(id: request.id, status: .failed, reason: "failure") }
  }

  @Test("Randomized presentation, exact retained bytes and sparse explicit revisions survive restart")
  func roundTripAndRevisions() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let pair = try await reviewFixturePair(store)
    let comparison = try await store.createReviewComparison(first: pair.0, second: pair.1, presentationSeed: 83, rubricVersion: "rubric-1")
    let swapped = try await store.createReviewComparison(first: pair.1, second: pair.0, presentationSeed: 83, rubricVersion: "rubric-1")
    #expect(comparison.a == swapped.a && comparison.b == swapped.b)
    #expect(comparison.originalVisible)
    #expect(comparison.a.material.penIdentifier == nil)
    #expect(comparison.a.material.provenance == nil)
    let display = try await store.loadReviewDisplayPreview(comparisonID: comparison.id, side: .a)
    #expect(display.sha256 == comparison.a.displayPreviewSHA256)
    #expect(display.pixelWidth == comparison.displayPixelWidth)
    #expect(display.pixelHeight == comparison.displayPixelHeight)
    #expect(display.sha256 != comparison.a.previewSHA256)
    let first = try await store.appendReviewLabel(comparisonID: comparison.id,
      choices: [.overall: .a, .likeness: .tie], reviewerID: nil, expectedRevisionID: nil)
    #expect(first.choices[.expression] == nil && first.reviewerID == nil)
    await #expect(throws: (any Error).self) {
      try await store.appendReviewLabel(comparisonID: comparison.id, choices: [.overall: .b], reviewerID: nil, expectedRevisionID: nil)
    }
    let skipped = try await store.appendReviewLabel(comparisonID: comparison.id,
      choices: [.overall: .skip], reviewerID: "fixture-reviewer", expectedRevisionID: first.id)
    let reopened = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    #expect(try await reopened.loadReviewComparison(id: comparison.id) == comparison)
    #expect(try await reopened.reviewLabelHead(comparisonID: comparison.id) == skipped)
    #expect(try await reopened.loadReviewPackage(origin: comparison.a.origin).source.sha256 == comparison.originalSourceSHA256)
    let manifest = try await reopened.exportReviewDataset(to: root.appendingPathComponent("export"))
    #expect(manifest.counts.labelRevisions == 2)
    #expect(manifest.counts.skippedComparisonHeads == 1 && manifest.counts.ratedComparisonHeads == 0)
    #expect(manifest.counts.unlabeledComparisons == 1)
    #expect(manifest.results.allSatisfy { $0.split == .unassigned })
    try PortraitCandidateStore.verifyReviewDataset(at: root.appendingPathComponent("export"))
    let original = try #require(manifest.files.first { $0.sha256 == comparison.originalSourceSHA256 })
    try Data("tamper".utf8).write(to: root.appendingPathComponent("export").appendingPathComponent(original.path))
    #expect(throws: (any Error).self) { try PortraitCandidateStore.verifyReviewDataset(at: root.appendingPathComponent("export")) }
  }

  @Test("Failure before conversion is durable without inventing a DrawingPackage; every terminal category exports")
  func terminalFailureRecords() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let package = try transferTestPackage()
    let pending = try reviewRequest(package: package)
    try await store.beginReviewGeneration(pending)
    for status in [PortraitReviewGenerationStatus.failed, .cancelled, .skipped, .unsupported] {
      let request = try reviewRequest(package: package)
      try await store.beginReviewGeneration(request)
      let output = PortraitReviewAsset(role: "raw-curves", asset: .init(mediaType: "application/json", bytes: Data("{\"invalidCurves\":[]}".utf8)))
      let outcome = try await store.finishReviewGeneration(id: request.id, status: status,
        reason: status.rawValue, outputs: [output], runtimeEnvironmentJSON: Data("{\"observed\":true}".utf8))
      #expect(outcome.origin == nil && outcome.packageSHA256 == nil)
      #expect(outcome.runtimeEnvironmentJSON != request.environmentJSON)
    }
    let reopened = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let page = try await reopened.reviewGenerationPage(limit: 8)
    #expect(page.count == 5 && page.filter { $0.status == nil }.count == 1)
    #expect(try await reopened.reviewGenerationPage(offset: 3, limit: 2).count == 2)
    let manifest = try await reopened.exportReviewDataset(to: root.appendingPathComponent("export"))
    #expect(manifest.results.isEmpty)
    #expect(manifest.counts.pending == 1 && manifest.counts.failed == 1 && manifest.counts.cancelled == 1)
    #expect(manifest.counts.skipped == 1 && manifest.counts.unsupported == 1 && manifest.counts.succeeded == 0)
    let requestBytes = try #require(manifest.records.first { $0.id == pending.id && $0.kind == "request" })
    let decoded = try JSONDecoder().decode(PortraitReviewGenerationRequest.self,
      from: Data(contentsOf: root.appendingPathComponent("export/assets/" + requestBytes.fileSHA256)))
    #expect(decoded == pending)
    #expect(decoded.acquisitionID == nil && decoded.groups.photoSessionID == nil)
  }

  @Test("Deleting canonical artwork blocks new labels while exact audit snapshots remain readable")
  func deletedResultRefusesLabel() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root)
    let pair = try await reviewFixturePair(store)
    let comparison = try await store.createReviewComparison(first: pair.0, second: pair.1, presentationSeed: 3, rubricVersion: "1")
    var archive = await store.load().archive
    archive.savedDrawings?.removeAll { $0.id == pair.0.id }
    archive.tombstones.append(.init(id: UUID(), kind: .candidate, identity: pair.0.id,
      affectedCandidateIDs: [], assetSHA256s: [], createdAt: Date()))
    try await store.save(snapshot: archive)
    await #expect(throws: (any Error).self) {
      try await store.appendReviewLabel(comparisonID: comparison.id, choices: [.overall: .a], reviewerID: nil, expectedRevisionID: nil)
    }
    #expect(try await store.loadReviewPackage(origin: comparison.a.origin).origin == comparison.a.origin)
    await #expect(throws: (any Error).self) { try await store.validateDurableDrawing(pair.0) }
  }

  @Test("Unrelated producer capture UUID collisions and different nominal pens are refused")
  func captureAndMaterialGuards() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root), capture = UUID()
    let a = try transferTestPackage(captureID: capture)
    let b = try transferTestPackage(captureID: capture, resultBytes: Data("{\"frozenResult\":2}".utf8))
    let x = try await store.importDrawingPackage(DrawingPackageCodec.encode(a))
    let y = try await store.importDrawingPackage(DrawingPackageCodec.encode(b))
    await #expect(throws: (any Error).self) {
      try await store.createReviewComparison(first: x, second: y, presentationSeed: 2, rubricVersion: "1")
    }
    let changedStyle = try StrokeStyle(nominalLineWidth: a.program.strokes[0].style.nominalLineWidth * 2,
      penProfileID: a.program.strokes[0].style.penProfileID)
    let changed = try DrawingProgram(id: a.program.id, fieldExtent: a.program.fieldExtent,
      strokes: a.program.strokes.map { .init(id: $0.id, path: $0.path, style: changedStyle, ordering: $0.ordering) }, source: a.program.source)
    let otherPen = try transferTestPackage(captureID: capture, libraryID: a.origin.libraryID,
      resultBytes: Data("{\"frozenResult\":3}".utf8), programOverride: changed)
    let z = try await store.importDrawingPackage(DrawingPackageCodec.encode(otherPen))
    await #expect(throws: (any Error).self) {
      try await store.createReviewComparison(first: x, second: z, presentationSeed: 2, rubricVersion: "1")
    }
  }

  @Test("Human declarations are explicit immutable metadata and frozen splits cannot be changed at export")
  func declarationsAndFrozenSplits() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root.appendingPathComponent("library"))
    let pair = try await reviewFixturePair(store)
    let package = try await store.prepareReviewDrawing(pair.0)
    let groups = PortraitReviewGroups(subjectID: "person-one", photoSessionID: "session-one", declaration: "operator-declared fixture")
    let declared = try await store.declareReviewGroups(origin: package.origin, groups: groups, split: .train)
    #expect(declared.acquisitionID == nil)
    #expect(try await store.declareReviewGroups(origin: package.origin, groups: groups, split: .train) == declared)
    await #expect(throws: (any Error).self) {
      try await store.declareReviewGroups(origin: package.origin, groups: groups, split: .test)
    }
    await #expect(throws: (any Error).self) {
      try await store.exportReviewDataset(to: root.appendingPathComponent("bad"), splitAssignments: [declared.id: .test])
    }
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("bad").path))
    let manifest = try await store.exportReviewDataset(to: root.appendingPathComponent("good"), splitAssignments: [declared.id: .train])
    #expect(manifest.counts.requests == 0 && manifest.groups.count == 1)
    #expect(manifest.results.first?.split == .train)
  }

  @Test("Review writes preserve same-actor native saves and an external selector change remains a blocker")
  func nativeSaveOwnership() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PortraitCandidateStore(directoryURL: root)
    let source = try validReviewSourcePNG(), capture = UUID(), acquisition = UUID()
    func candidate(_ seed: UInt64) throws -> PortraitCandidate {
      let base = try portraitPersistenceCandidate(seed: seed)
      return try .init(sourceData: source, sourcePixelExtent: base.sourcePixelExtent, raster: base.raster,
        recipe: base.recipe, program: base.program, photoID: capture, captureSessionID: acquisition)
    }
    let first = try candidate(501), second = try candidate(502), third = try candidate(503)
    var archive = PortraitCandidateArchive(entries: [.init(candidate: first, reasons: []), .init(candidate: second, reasons: [])])
    try await store.save(snapshot: archive)
    let comparison = try await store.createReviewComparison(first: .init(candidate: first), second: .init(candidate: second),
      presentationSeed: 2, rubricVersion: "native-1")
    _ = try await store.appendReviewLabel(comparisonID: comparison.id, choices: [.overall: .tie], reviewerID: nil, expectedRevisionID: nil)
    _ = try await store.declareReviewGroups(origin: comparison.a.origin,
      groups: .init(subjectID: "native-person", photoSessionID: "native-session", declaration: "fixture operator"))
    archive.entries.append(.init(candidate: third, reasons: []))
    try await store.save(snapshot: archive)
    let reopened = PortraitCandidateStore(directoryURL: root)
    #expect(await reopened.load().canWrite)
    #expect(try await reopened.reviewComparisonPage().contains(where: { $0.id == comparison.id }))
    let external = try PortraitLibraryDatabase(url: root.appendingPathComponent("library-v1.sqlite"))
    try external.transaction { try external.setState("external-test-change", "1"); try external.bumpRevision() }
    await #expect(throws: (any Error).self) {
      try await store.appendReviewLabel(comparisonID: comparison.id, choices: [.overall: .b], reviewerID: nil,
        expectedRevisionID: try await store.reviewLabelHead(comparisonID: comparison.id)?.id)
    }
    await #expect(throws: (any Error).self) { try await store.save(snapshot: archive) }
  }
}

private func validReviewSourcePNG(gray: Double = 0.8) throws -> Data {
  let context = try #require(CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160,
    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(gray: gray, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
  let bytes = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
  CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
  #expect(CGImageDestinationFinalize(destination))
  return bytes as Data
}
