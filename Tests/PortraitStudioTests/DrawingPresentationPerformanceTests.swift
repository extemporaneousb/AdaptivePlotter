import AppKit
import Darwin
import DrawingLibrary
import Foundation
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

/// Opt-in affected-path measurements. The driver reuses one immutable, real
/// current-format fixture; every helper edits only its own disposable clone.
@Suite("Current Drawing presentation performance", .serialized)
@MainActor
struct DrawingPresentationPerformanceTests {
  @Test("Active-fit refresh and repeated exact preview presentation",
    .enabled(if: ProcessInfo.processInfo.environment["DRAWING_PRESENTATION_PERF"] == "1"))
  func measure() async throws {
    let env = ProcessInfo.processInfo.environment
    let fixture = URL(fileURLWithPath: try #require(env["DRAWING_PRESENTATION_PERF_FIXTURE"]))
    let output = URL(fileURLWithPath: try #require(env["DRAWING_PRESENTATION_PERF_OUTPUT"]))
    let cold = env["DRAWING_PRESENTATION_PERF_PHASE"] == "cold"
    if env["DRAWING_PRESENTATION_PERF_PHASE"] == "seed" {
      try #require(!FileManager.default.fileExists(atPath: fixture.path))
      try await seed(fixture)
      try Data("{\"fixturePrepared\":true}".utf8).write(to: output)
      return
    }
    try #require(FileManager.default.fileExists(atPath: fixture.path))
    let clone = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-presentation-clone-" + UUID().uuidString)
    try FileManager.default.copyItem(at: fixture, to: clone)
    defer { try? FileManager.default.removeItem(at: clone) }
    let model = FlowAuthoringModel(directory: clone, render: FlowAuthoringFixture.render)
    let decoder = FlowPresentationImageCache.shared
    var samples: [[String: Any]] = []
    var renderedPixelDigest: String?
    func counters() -> [String: UInt64] {
      var value = DrawingLibraryDiagnostics.shared.snapshot()
      value["checkpointReadsDecodesValidations"] = UInt64(model.checkpointDecodeCount)
      value["trainingSummaryBuilds"] = UInt64(model.trainingSummaryBuildCount)
      value["presentationMaterializations"] = UInt64(decoder.decodeCount)
      return value
    }
    func delta(_ before: [String: UInt64]) -> [String: UInt64] {
      counters().mapValues { $0 }.reduce(into: [:]) { result, pair in result[pair.key] = pair.value - (before[pair.key] ?? 0) }
    }
    let openingCounters = counters(), opening = DispatchTime.now().uptimeNanoseconds
    await model.open()
    let openMS = Self.ms(opening)
    try #require(model.error == nil, "\(model.error ?? "")")
    try #require(model.activeCheckpoint != nil)
    if cold { samples.append(["operation": "processColdModelOpen", "milliseconds": openMS, "counters": delta(openingCounters)]) }
    let document = try #require(model.document)
    let source = try #require(model.selectedSource)
    let candidates = model.roundCandidates
    try #require(candidates.count == 3)
    let beforeHashes = try hashes(document)
    let preview = try #require(model.previews[candidates[0].id])
    let previewIdentity = DrawingArtifactCoding.sha256(preview)
    if !cold {
      for trial in 0..<35 {
        var before = counters(), start = DispatchTime.now().uptimeNanoseconds
        await model.renameSource(source.id, title: "Performance title \(trial)")
        let rename: [String: Any] = ["operation": "renamePhoto", "milliseconds": Self.ms(start), "counters": delta(before)]
        before = counters(); start = DispatchTime.now().uptimeNanoseconds
        await model.browseCandidate(candidates[trial % candidates.count].id)
        let navigation: [String: Any] = ["operation": "navigateDrawing", "milliseconds": Self.ms(start), "counters": delta(before)]
        before = counters(); start = DispatchTime.now().uptimeNanoseconds
        let image = try #require(await decoder.load(data: preview, identity: previewIdentity))
        // Force the same image's raster representation, avoiding a lazy NSImage
        // constructor-only baseline that never measures actual presentation.
        var rect = NSRect(origin: .zero, size: image.size)
        let raster = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        let context = try #require(CGContext(data: nil, width: raster.width, height: raster.height,
          bitsPerComponent: 8, bytesPerRow: raster.width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(raster, in: CGRect(x: 0, y: 0, width: raster.width, height: raster.height))
        let pixels = try #require(context.data)
        let pixelDigest = DrawingArtifactCoding.sha256(Data(bytes: pixels, count: context.bytesPerRow * context.height))
        if let renderedPixelDigest { #expect(renderedPixelDigest == pixelDigest) }
        else { renderedPixelDigest = pixelDigest }
        let presentation: [String: Any] = ["operation": "presentExactPreview", "milliseconds": Self.ms(start), "counters": delta(before)]
        if trial >= 5 { samples += [rename, navigation, presentation] }
        try #require(model.error == nil, "\(model.error ?? "")")
      }
    }
    let afterHashes = try hashes(try #require(model.document))
    #expect(beforeHashes == afterHashes)
    let progress = try #require(model.trainingProgress)
    var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
    let report: [String: Any] = ["format": "drawing-presentation-performance/1",
      "phase": cold ? "processColdModelOpen" : "warmInteractive", "samples": samples,
      "fixture": ["photos": document.sources.count, "generatedCandidates": document.candidates.count,
        "retainedCandidates": document.candidates.filter { $0.drawing != nil }.count,
        "strokesPerCandidate": 16, "activeFit": document.activeFitID?.uuidString ?? "missing",
        "checkpointDigest": document.fits.first { $0.id == document.activeFitID }?.checkpoint?.sha256 ?? "missing",
        "previewBytes": preview.count],
      "beforeHashes": beforeHashes, "afterHashes": afterHashes,
      "renderedPreviewPixelDigest": renderedPixelDigest ?? "not-rendered-cold-open-only",
      "training": ["canAttemptFit": progress.canAttemptFit, "readiness": progress.readinessMessage,
        "choiceComparisons": progress.choiceComparisonCount, "rankComparisons": progress.rankingComparisonCount,
        "removedLabels": progress.removeLabelCount, "keptLabels": progress.keepLabelCount,
        "activeHasChanges": progress.activeHasTrainingChanges ?? false],
      "processLifetimePeakRSSBytes": usage.ru_maxrss, "derivedImageCache": decoder.statistics,
      "memoryScope": "Darwin process lifetime high-water bytes, including startup, fixture clone/open and all measured operations; not operation-local or cache residency",
      "coldScope": "Fresh helper process and model; OS filesystem cache unspecified; persisted exact fixture cloned before timing",
      "counterScope": "Actual model checkpoint read/decode/validation and summary builds, presentation image materialization attempts (baseline NSImage constructors; timed endpoint forces CGImage pixels), Library SQL statement and storage stream seams; not universal filesystem counts"]
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    #expect(await model.shutdown())
  }

  private func hashes(_ document: FlowPortfolioSnapshot) throws -> [String: String] {
    let encoder = DrawingArtifactCoding.encoder()
    let feedback = try encoder.encode(document.choices) + encoder.encode(document.pruneRevisions) + encoder.encode(document.rankings)
    return ["feedbackBytes": DrawingArtifactCoding.sha256(feedback),
      "orderedProgramDigests": DrawingArtifactCoding.sha256(try encoder.encode(document.candidates.map(\.programHash)))]
  }

  private func seed(_ directory: URL) async throws {
    let model = FlowAuthoringModel(directory: directory, purpose: .validationFixture, render: FlowAuthoringFixture.render)
    await model.open(); model.count = 3
    for index in 1...4 {
      await model.addPhoto(data: FlowAuthoringFixture.image(index), title: "Frozen synthetic source \(index)")
      await model.generate(refining: false)
      for candidate in model.roundCandidates {
        await model.selectCandidate(candidate.id)
        let strokes = try #require(model.program?.strokes)
        await model.edit(.remove, ids: Set(strokes.prefix(8).map(\.id)))
        await model.edit(.completeTarget)
      }
      await model.presentRanking(scope: .round(try #require(model.round?.id)))
      let candidates = Dictionary(uniqueKeysWithValues: model.roundCandidates.map { ($0.id, $0) })
      let items = try #require(model.presentation).items.sorted {
        candidates[$0.candidateID]!.recipe.values[3] < candidates[$1.candidateID]!.recipe.values[3]
      }
      for (rank, item) in items.enumerated() { await model.rank(item: item.id, position: rank + 1) }
    }
    await model.fit()
    try #require(model.error == nil, "\(model.error ?? "")")
    let fit = try #require(model.document?.fits.last)
    try #require(fit.hasCheckpoint, "\(model.fitReport?.summary ?? "No report")")
    await model.activate(fit.id)
    try #require(model.activeCheckpoint != nil)
    #expect(await model.shutdown())
  }
  private static func ms(_ start: UInt64) -> Double { Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000 }
}
