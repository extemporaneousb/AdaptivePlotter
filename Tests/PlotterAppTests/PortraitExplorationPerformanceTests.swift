import CoreGraphics
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait exploration workload", .serialized)
@MainActor
struct PortraitExplorationPerformanceTests {
  @Test("three-option exploration reuses analysis and bounds vector work", arguments: PortraitStyle.authoringCases)
  func cachedRoundWorkload(style: PortraitStyle) async throws {
    let environment = ProcessInfo.processInfo.environment
    if let selectedStyle = environment["PORTRAIT_EXPLORATION_STYLE"], selectedStyle != style.rawValue {
      return
    }
    let referencePath = environment["PORTRAIT_EXPLORATION_REFERENCE_PHOTO"]
    let image = try referencePath.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
      ?? explorationPerformanceImage()
    let fixtureLabel = referencePath == nil ? "analytic-portrait-480x640-v1" : "local-photo"
    let renderer = ExplorationMeasuredRenderer()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-browser-performance-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PortraitCandidateStore(directoryURL: directory)
    let model = PortraitStudioModel(renderer: renderer, candidateStore: store, explorationSeed: 0x50302026)
    await model.loadArchive()
    let pen = try portraitTestStyle()
    model.style = style
    if referencePath == nil {
      model.options.cropToFace = false
      model.options.removeBackground = false
    }
    model.vectorOptions = style == .flowEdges ? .flowDefaults : PortraitVectorPreset.balanced.options
    let clock = ContinuousClock()
    let coldStart = clock.now
    model.setPhoto(image, for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let coldMS = elapsedMS(coldStart.duration(to: clock.now))
    let center = try #require(model.selectedCandidate)
    // Populate with representative complete geometry, not tiny archive mocks.
    // These synthetic provenance aliases are setup load, not diversity evidence.
    for seed in 1...24 {
      let recipe = PortraitStyleRecipe(id: "benchmark-alias-\(seed)", title: "History setup \(seed)",
        seed: UInt64(seed), style: center.recipe.style, vectorOptions: center.recipe.vectorOptions,
        analysisOptions: center.recipe.analysisOptions)
      let candidate = try PortraitCandidate(sourceData: center.sourceData, sourcePixelExtent: center.sourcePixelExtent,
        raster: center.raster, recipe: recipe, program: center.program, photoID: center.photoID,
        captureSessionID: center.captureSessionID, lineage: center.lineage, pose: center.pose,
        warpManifest: center.warpManifest)
      model.sketches.recordAttempt(candidate, record: try .prepare(candidate: candidate, pen: pen))
    }
    await model.sketches.awaitPersistence()
    #expect(max(center.raster.width, center.raster.height) == PortraitImageAnalyzer.analysisMaximumDimension(for: style))
    #expect(await renderer.coldCalls == 1)
    var roundMS: [Double] = []
    var firstReadyMS: [Double] = []
    var pairReadyMS: [Double] = []
    var roundCalls: [Int] = []
    var availableNeighbors: [Int] = []
    var previousOptionCounts: [Int] = []
    var geometryOracleMS: [Double] = []
    var maximumMainActorGapMS = 0.0
    let heartbeat = Task { @MainActor in
      var previous = clock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(2))
        let now = clock.now
        maximumMainActorGapMS = max(maximumMainActorGapMS, elapsedMS(previous.duration(to: now)))
        previous = now
      }
    }
    for index in 0..<4 {
      let beforeCalls = await renderer.calls
      let start = clock.now
      if let previous = model.explorationRound {
        if index % 2 == 1,
          let slot = previous.slots.first(where: { $0.index != 1 && $0.candidate != nil }) {
          model.chooseExplorationSlot(slot.index, roundID: previous.id, strokeStyle: pen)
        } else {
          model.resampleExploration(roundID: previous.id, strokeStyle: pen)
        }
      } else { model.setExplorationEnabled(true, strokeStyle: pen) }
      await model.awaitRendering()
      roundMS.append(elapsedMS(start.duration(to: clock.now)))
      if let value = model.firstAlternativeSeconds { firstReadyMS.append(value * 1000) }
      if let value = model.alternativePairSeconds { pairReadyMS.append(value * 1000) }
      roundCalls.append(await renderer.calls - beforeCalls)
      let round = try #require(model.explorationRound)
      #expect(round.slots.count == 3)
      let alternatives = round.slots.filter { $0.index != 1 }.compactMap(\.candidate)
      availableNeighbors.append(alternatives.count)
      previousOptionCounts.append(round.slots.filter(\.isPrevious).count)
      let programs = ([round.center] + alternatives).map(\.program)
      // The independent oracle is deliberately off MainActor. Reconstructing
      // occupancy here otherwise contaminates the product heartbeat measurement.
      let oracle = await Task.detached {
        let oracleClock = ContinuousClock()
        let oracleStart = oracleClock.now
        let geometries = programs.map(PortraitExplorationPolicy.VisibleGeometry.init)
        var distinct = true
        for left in geometries.indices {
          for right in geometries.indices where right > left {
            distinct = distinct && geometries[left].isMeaningfullyDifferent(from: geometries[right])
          }
        }
        return (distinct, elapsedMS(oracleStart.duration(to: oracleClock.now)))
      }.value
      #expect(oracle.0)
      geometryOracleMS.append(oracle.1)
      #expect(round.slots.compactMap(\.candidate).allSatisfy {
        $0.rasterSHA256 == center.rasterSHA256 && $0.recipe.analysisOptions == center.recipe.analysisOptions
      })
    }
    #expect(await renderer.coldCalls == 1)
    #expect(roundCalls.allSatisfy { (0...4).contains($0) })
    #expect(availableNeighbors.contains { $0 > 0 })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    let backCalls = await renderer.calls
    let backStart = clock.now
    model.goBackExploration()
    let backMS = elapsedMS(backStart.duration(to: clock.now))
    #expect(await renderer.calls == backCalls)
    let historyCalls = await renderer.calls
    var historyInstallMS: [Double] = []
    var feedbackMS: [Double] = []
    for entry in model.sketches.attempts.prefix(24) {
      let begin = clock.now
      model.inspectAttempt(entry.id, strokeStyle: pen)
      historyInstallMS.append(elapsedMS(begin.duration(to: clock.now)))
      let feedbackStart = clock.now
      model.toggleFeedback(.promising, candidate: entry.candidate)
      model.toggleFeedback(.promising, candidate: entry.candidate)
      feedbackMS.append(elapsedMS(feedbackStart.duration(to: clock.now)))
    }
    #expect(await renderer.calls == historyCalls)
    await model.sketches.awaitPersistence()
    heartbeat.cancel()
    await heartbeat.value
    #expect(model.sketches.persistenceState == .saved)
    let stats: [String: Any] = [
      "persistentHistoryCount": model.sketches.attempts.count,
      "preloadPayload": "24 provenance aliases of the full representative source/raster/program",
      "preloadProgramStrokes": center.program.strokes.count,
      "preloadProgramPoints": center.program.strokes.reduce(0) { $0 + $1.path.points.count },
      "preloadSourceBytes": center.sourceData.count,
      "historyModelInstallMS": historyInstallMS, "feedbackModelMutationMS": feedbackMS,
      "nativeClickToPaintMeasured": false,
      "firstAlternativeReadyMS": firstReadyMS, "pairReadyMS": pairReadyMS,
      "fixture": fixtureLabel, "encodedSHA256": PortraitCandidateCoding.digest(image),
      "style": style.rawValue, "policy": PortraitExplorationPolicy.revision,
      "analyzedWidth": center.raster.width, "analyzedHeight": center.raster.height,
      "coldAnalysisAndCenterMS": coldMS, "cachedRoundMS": roundMS,
      "cachedRoundRenderCalls": roundCalls, "availableNeighborCounts": availableNeighbors,
      "previousOptionCounts": previousOptionCounts,
      "proposedOptionCounts": zip(availableNeighbors, previousOptionCounts).map { $0 - $1 },
      "rejections": model.explorationRejections,
      "coldAnalysisCalls": await renderer.coldCalls, "backMS": backMS,
      "maximumMainActorHeartbeatGapMS": maximumMainActorGapMS,
      "geometryOracleMS": geometryOracleMS, "geometryOracleExecutionContext": "detached off MainActor",
      "maximumConcurrentWorkers": model.workDiagnostics.maximumConcurrentWorkerCount,
      "buildConfiguration": explorationBuildConfiguration, "physicalOrHumanQualityEvidence": false
    ]
    let bytes = try JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys])
    print("PORTRAIT_EXPLORATION_WORKLOAD " + String(decoding: bytes, as: UTF8.self))
    if let path = ProcessInfo.processInfo.environment["PORTRAIT_EXPLORATION_PERFORMANCE_OUTPUT"] {
      let suffix = style.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
      try bytes.write(to: URL(fileURLWithPath: path + "." + suffix + ".json"), options: .atomic)
    }
    await model.shutdown()
  }

  @Test("long Flow preference walk keeps Current usable and distinguishes new proposals from history fallback")
  func repeatedPreferenceWalk() async throws {
    let environment = ProcessInfo.processInfo.environment
    let referencePath = environment["PORTRAIT_EXPLORATION_REFERENCE_PHOTO"]
    let image = try referencePath.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
      ?? explorationPerformanceImage()
    let count = min(48, max(32, Int(environment["PORTRAIT_EXPLORATION_WALK_ROUNDS"] ?? "") ?? 32))
    let renderer = ExplorationMeasuredRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 0x50302026)
    let pen = try portraitTestStyle()
    model.style = .flowEdges
    model.vectorOptions = .flowDefaults
    if referencePath == nil {
      model.options.cropToFace = false
      model.options.removeBackground = false
    }
    model.setPhoto(image, for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let initial = try #require(model.selectedCandidate)
    let clock = ContinuousClock()
    var durations: [Double] = [], calls: [Int] = [], available: [Int] = []
    var proposed: [Int] = [], previous: [Int] = [], firstSeen: [Int] = []
    var selectedOptions: [PortraitVectorOptions] = []
    var seenPrograms = Set([initial.program.contentHash.description])
    var maxHeartbeatMS = 0.0
    let heartbeat = Task { @MainActor in
      var last = clock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(2))
        let now = clock.now
        maxHeartbeatMS = max(maxHeartbeatMS, elapsedMS(last.duration(to: now)))
        last = now
      }
    }
    for index in 0..<count {
      let before = await renderer.calls
      let started = clock.now
      var expected = model.selectedCandidate
      if let round = model.explorationRound {
        if index < 7 || index % 8 == 3 {
          model.chooseExplorationSlot(1, roundID: round.id, strokeStyle: pen)
        } else if index % 8 == 5, model.canGoBackExploration {
          model.goBackExploration()
          expected = model.selectedCandidate
          #expect(await renderer.calls == before)
        } else if index % 8 == 0 || index % 8 == 7 {
          model.resampleExploration(roundID: round.id, strokeStyle: pen)
        } else {
          let desired = index % 2 == 0 ? 2 : 0
          if let slot = round.slots.first(where: { $0.index == desired && $0.candidate != nil })
            ?? round.slots.first(where: { $0.index != 1 && $0.candidate != nil }) {
            expected = slot.candidate
            model.chooseExplorationSlot(slot.index, roundID: round.id, strokeStyle: pen)
          } else { model.resampleExploration(roundID: round.id, strokeStyle: pen) }
        }
      } else { model.setExplorationEnabled(true, strokeStyle: pen) }
      // A rapid click during pending work keeps the same offer alive.
      if model.isExploring, let pendingID = model.explorationDisplayID {
        let search = model.explorationSearch
        for _ in 0..<3 { model.chooseExplorationSlot(1, roundID: pendingID, strokeStyle: pen) }
        #expect(model.isExploring)
        #expect(model.explorationSearch == search)
      }
      #expect(model.selectedCandidate?.id == expected?.id)
      await model.awaitRendering()
      durations.append(elapsedMS(started.duration(to: clock.now)))
      calls.append(await renderer.calls - before)
      let round = try #require(model.explorationRound)
      #expect(round.center.id == expected?.id)
      #expect(round.slots.count == 3)
      #expect(round.slots[1].candidate?.id == round.center.id)
      let alternatives = round.slots.filter { $0.index != 1 && $0.candidate != nil }
      available.append(alternatives.count)
      previous.append(alternatives.filter(\.isPrevious).count)
      proposed.append(alternatives.filter { !$0.isPrevious }.count)
      firstSeen.append(alternatives.compactMap(\.candidate).filter {
        seenPrograms.insert($0.program.contentHash.description).inserted
      }.count)
      selectedOptions.append(round.center.recipe.vectorOptions)
      #expect(round.slots.compactMap(\.candidate).allSatisfy {
        $0.sourceSHA256 == initial.sourceSHA256 && $0.rasterSHA256 == initial.rasterSHA256
          && $0.recipe.analysisOptions == initial.recipe.analysisOptions
          && $0.recipe.vectorOptions.materialContext == initial.recipe.vectorOptions.materialContext
      })
      #expect(round.slots.allSatisfy { $0.candidate != nil || $0.failureKind != nil })
      #expect(model.currentProgram != nil)
    }
    heartbeat.cancel()
    await heartbeat.value
    #expect(calls.allSatisfy { (0...4).contains($0) })
    #expect(await renderer.coldCalls == 1)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    // This controlled fixture must never strand a walk with no usable alternative.
    // External photos retain the same safety assertions; coverage is evidence,
    // not a claim that every possible image has two distinct useful drawings.
    if referencePath == nil { #expect(available.allSatisfy { $0 > 0 }) }
    let encodedOptions = try PortraitCandidateCoding.encoder().encode(selectedOptions)
    let stats: [String: Any] = [
      "fixture": referencePath == nil ? "analytic-portrait-480x640-v1" : "local-photo",
      "encodedSHA256": PortraitCandidateCoding.digest(image),
      "policy": PortraitExplorationPolicy.revision, "roundCount": count,
      "roundMS": durations, "renderCalls": calls, "availableOptionCounts": available,
      "proposedOptionCounts": proposed, "previousOptionCounts": previous,
      "firstSeenProgramCounts": firstSeen,
      "selectedVectorOptions": try JSONSerialization.jsonObject(with: encodedOptions),
      "rejections": model.explorationRejections,
      "maximumMainActorHeartbeatGapMS": maxHeartbeatMS,
      "maximumConcurrentWorkers": model.workDiagnostics.maximumConcurrentWorkerCount,
      "coldAnalysisCalls": await renderer.coldCalls,
      "buildConfiguration": explorationBuildConfiguration, "physicalOrHumanQualityEvidence": false
    ]
    let bytes = try JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys])
    print("PORTRAIT_EXPLORATION_WALK " + String(decoding: bytes, as: UTF8.self))
    if let path = environment["PORTRAIT_EXPLORATION_PERFORMANCE_OUTPUT"] {
      try bytes.write(to: URL(fileURLWithPath: path + ".walk.json"), options: .atomic)
    }
    await model.shutdown()
  }

}

private actor ExplorationMeasuredRenderer: PortraitRendering {
  private(set) var calls = 0
  private(set) var coldCalls = 0
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    calls += 1
    if request.cachedRaster == nil { coldCalls += 1 }
    return try await PortraitImageAnalyzer().render(request)
  }
}

private func elapsedMS(_ duration: Duration) -> Double {
  let value = duration.components
  return Double(value.seconds) * 1000 + Double(value.attoseconds) / 1e15
}

/// No external image, face identity or camera dependency. The nested luminance
/// regions exercise broad tone, eyes, nose, mouth, hair and background contours.
private func explorationPerformanceImage() throws -> Data {
  let width = 480, height = 640
  var pixels = [UInt8](repeating: 255, count: width * height)
  func gaussian(_ x: Double, _ y: Double, _ cx: Double, _ cy: Double,
    _ sx: Double, _ sy: Double) -> Double {
    exp(-pow((x - cx) / sx, 2) - pow((y - cy) / sy, 2))
  }
  for y in 0..<height {
    for x in 0..<width {
      let u = Double(x) / Double(width), v = Double(y) / Double(height)
      let radius = pow((u - 0.5) / 0.31, 2) + pow((v - 0.45) / 0.36, 2)
      var luminance = 0.96 - 0.05 * u
      if radius < 1 {
        luminance = 0.46 + 0.28 * radius + 0.12 * u
        luminance -= 0.34 * gaussian(u, v, 0.38, 0.39, 0.052, 0.024)
        luminance -= 0.34 * gaussian(u, v, 0.62, 0.39, 0.052, 0.024)
        luminance -= 0.2 * gaussian(u, v, 0.52, 0.51, 0.035, 0.105)
        luminance -= 0.28 * gaussian(u, v, 0.5, 0.62, 0.10, 0.020)
        if v < 0.23 + 0.055 * sin(u * 22) { luminance *= 0.28 }
      }
      if v > 0.78 && abs(u - 0.5) < (v - 0.70) * 1.8 {
        luminance = 0.18 + 0.16 * u + 0.04 * sin(u * 70)
      }
      pixels[y * width + x] = UInt8((min(1, max(0, luminance)) * 255).rounded())
    }
  }
  let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
  let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
    bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
    bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
    shouldInterpolate: false, intent: .defaultIntent))
  return try PortraitImageAnalyzer.encodedImage(image)
}

private var explorationBuildConfiguration: String {
  #if DEBUG
  return "debug"
  #else
  return "release"
  #endif
}
