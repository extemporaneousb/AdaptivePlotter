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
    let referencePath = ProcessInfo.processInfo.environment["PORTRAIT_EXPLORATION_REFERENCE_PHOTO"]
    let image = try referencePath.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
      ?? explorationPerformanceImage()
    let fixtureLabel = referencePath == nil ? "analytic-portrait-480x640-v1" : "local-photo"
    let renderer = ExplorationMeasuredRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 0x50302026)
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
    #expect(max(center.raster.width, center.raster.height) == PortraitImageAnalyzer.analysisMaximumDimension(for: style))
    #expect(await renderer.coldCalls == 1)
    var roundMS: [Double] = []
    var roundCalls: [Int] = []
    var availableNeighbors: [Int] = []
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
      roundCalls.append(await renderer.calls - beforeCalls)
      let round = try #require(model.explorationRound)
      #expect(round.slots.count == 3)
      let alternatives = round.slots.filter { $0.index != 1 }.compactMap(\.candidate)
      availableNeighbors.append(alternatives.count)
      let geometries = [round.center] + alternatives
      for left in geometries.indices {
        for right in geometries.indices where right > left {
          #expect(PortraitExplorationPolicy.VisibleGeometry(geometries[left].program)
            .isMeaningfullyDifferent(from: .init(geometries[right].program)))
        }
      }
      #expect(round.slots.compactMap(\.candidate).allSatisfy {
        $0.rasterSHA256 == center.rasterSHA256 && $0.recipe.analysisOptions == center.recipe.analysisOptions
      })
    }
    heartbeat.cancel()
    await heartbeat.value
    #expect(await renderer.coldCalls == 1)
    #expect(roundCalls.allSatisfy { (0...4).contains($0) })
    #expect(availableNeighbors.contains { $0 > 0 })
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    let backCalls = await renderer.calls
    let backStart = clock.now
    model.goBackExploration()
    let backMS = elapsedMS(backStart.duration(to: clock.now))
    #expect(await renderer.calls == backCalls)
    let stats: [String: Any] = [
      "fixture": fixtureLabel, "encodedSHA256": PortraitCandidateCoding.digest(image),
      "style": style.rawValue, "policy": PortraitExplorationPolicy.revision,
      "analyzedWidth": center.raster.width, "analyzedHeight": center.raster.height,
      "coldAnalysisAndCenterMS": coldMS, "cachedRoundMS": roundMS,
      "cachedRoundRenderCalls": roundCalls, "availableNeighborCounts": availableNeighbors,
      "coldAnalysisCalls": await renderer.coldCalls, "backMS": backMS,
      "maximumMainActorHeartbeatGapMS": maximumMainActorGapMS,
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
