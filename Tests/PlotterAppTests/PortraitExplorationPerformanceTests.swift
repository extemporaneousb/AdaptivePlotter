import CoreGraphics
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait exploration workload", .serialized)
@MainActor
struct PortraitExplorationPerformanceTests {
  @Test("ordinary default tonal options fill low default and high variation neighborhoods")
  func defaultTonalCoverage() async throws {
    let model = PortraitStudioModel(explorationSeed: 0x50302026)
    let pen = try portraitTestStyle()
    model.options.cropToFace = false
    model.options.removeBackground = false
    model.setPhoto(try explorationPerformanceImage(), for: .front, strokeStyle: pen)
    await model.awaitRendering()
    for variation in [0.08, 0.35, 0.9] {
      model.setExplorationVariation(variation, strokeStyle: pen)
      model.setExplorationEnabled(true, strokeStyle: pen)
      await model.awaitRendering()
      let round = try #require(model.explorationRound)
      let neighbors = round.slots.filter { $0.index != 4 }.compactMap(\.candidate)
      #expect(neighbors.count == 8)
      let signatures = neighbors.map { PortraitExplorationPolicy.geometryIdentity($0.program) }
      #expect(Set(signatures).count == 8)
      print("PORTRAIT_DEFAULT_TONAL_COVERAGE variation=\(variation) distinct=\(neighbors.count) distances=\(neighbors.map { tonalRecipeDistance(round.center.recipe.vectorOptions, $0.recipe.vectorOptions) })")
    }
    await model.shutdown()
  }

  @Test("fixed tonal portrait fixture separates cold analysis from cached exploration")
  func cachedRoundWorkload() async throws {
    let image = try explorationPerformanceImage()
    let renderer = ExplorationMeasuredRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 0x50302026)
    let pen = try portraitTestStyle()
    model.options.cropToFace = false
    model.options.removeBackground = false
    model.vectorOptions = PortraitVectorPreset.balanced.options
    let clock = ContinuousClock()
    let coldStart = clock.now
    model.setPhoto(image, for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let coldMS = elapsedMS(coldStart.duration(to: clock.now))
    let center = try #require(model.selectedCandidate)
    #expect(center.raster.width == 120)
    #expect(center.raster.height == 160)
    #expect(await renderer.coldCalls == 1)
    var roundMS: [Double] = []
    var roundCalls: [Int] = []
    var availableNeighbors: [Int] = []
    var variations: [Double] = []
    var distances: [[Double]] = []
    var actions: [String] = []
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
    for (roundIndex, variation) in [0.35, 0.08, 0.9, 0.9, 0.9, 0.9].enumerated() {
      let beforeCalls = await renderer.calls
      let start = clock.now
      if let previous = model.explorationRound {
        if roundIndex >= 3, let slot = previous.slots.first(where: { $0.index != 4 && $0.candidate != nil }) {
          model.chooseExplorationSlot(slot.index, roundID: previous.id, strokeStyle: pen)
          actions.append("choose-\(slot.index)")
        } else if model.explorationVariation != variation {
          model.setExplorationVariation(variation, strokeStyle: pen)
          actions.append("variation")
        } else {
          model.resampleExploration(roundID: previous.id, strokeStyle: pen)
          actions.append("resample")
        }
      } else {
        model.setExplorationEnabled(true, strokeStyle: pen)
        actions.append("initial")
      }
      await model.awaitRendering()
      roundMS.append(elapsedMS(start.duration(to: clock.now)))
      roundCalls.append(await renderer.calls - beforeCalls)
      let round = try #require(model.explorationRound)
      variations.append(round.variation)
      availableNeighbors.append(round.slots.filter { $0.index != 4 && $0.candidate != nil }.count)
      if roundIndex < 3 { #expect(round.center.id == center.id) }
      #expect(round.variation == variation)
      distances.append(round.slots.filter { $0.index != 4 }.compactMap(\.candidate).map {
        tonalRecipeDistance(round.center.recipe.vectorOptions, $0.recipe.vectorOptions)
      })
      #expect(round.slots.compactMap(\.candidate).allSatisfy {
        $0.rasterSHA256 == center.rasterSHA256 && $0.recipe.analysisOptions == center.recipe.analysisOptions
      })
    }
    heartbeat.cancel()
    await heartbeat.value
    #expect(await renderer.coldCalls == 1)
    #expect(roundCalls.allSatisfy { (1...24).contains($0) })
    #expect(availableNeighbors.allSatisfy { $0 == 8 })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    let backCalls = await renderer.calls
    let backStart = clock.now
    model.goBackExploration()
    let backMS = elapsedMS(backStart.duration(to: clock.now))
    #expect(await renderer.calls == backCalls)
    let stats: [String: Any] = [
      "fixture": "analytic-portrait-480x640-v1", "encodedSHA256": PortraitCandidateCoding.digest(image),
      "style": "tonal-contours", "seed": "0x50302026", "variation": model.explorationVariation,
      "analyzedWidth": center.raster.width, "analyzedHeight": center.raster.height,
      "coldAnalysisAndCenterMS": coldMS, "cachedRoundMS": roundMS,
      "coldMeaning": "empty model raster and render caches; process and Vision may be warm",
      "cachedRoundRenderCalls": roundCalls, "availableNeighborCounts": availableNeighbors,
      "roundVariations": variations, "roundActions": actions, "normalizedRecipeDistances": distances,
      "coldAnalysisCalls": await renderer.coldCalls, "backMS": backMS,
      "maximumMainActorHeartbeatGapMS": maximumMainActorGapMS,
      "maximumConcurrentWorkers": model.workDiagnostics.maximumConcurrentWorkerCount,
      "buildConfiguration": explorationBuildConfiguration, "physicalOrHumanQualityEvidence": false
    ]
    let bytes = try JSONSerialization.data(withJSONObject: stats, options: [.prettyPrinted, .sortedKeys])
    print("PORTRAIT_EXPLORATION_WORKLOAD " + String(decoding: bytes, as: UTF8.self))
    if let path = ProcessInfo.processInfo.environment["PORTRAIT_EXPLORATION_PERFORMANCE_OUTPUT"] {
      try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
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

/// Euclidean distance over the five applicable contour controls normalized by
/// each documented bounded range. This measures parameter spread, not aesthetics.
private func tonalRecipeDistance(_ lhs: PortraitVectorOptions, _ rhs: PortraitVectorOptions) -> Double {
  let differences = [Double(lhs.contourLevels - rhs.contourLevels) / 11,
    (lhs.minimumContourLength - rhs.minimumContourLength) / 40,
    (lhs.simplificationTolerance - rhs.simplificationTolerance) / 3,
    (lhs.tonalStrength - rhs.tonalStrength) / 1.6,
    (lhs.smoothing - rhs.smoothing) / 4]
  return sqrt(differences.reduce(0) { $0 + $1 * $1 })
}

private var explorationBuildConfiguration: String {
  #if DEBUG
  return "debug"
  #else
  return "release"
  #endif
}
