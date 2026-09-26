import CoreGraphics
import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

@Suite("Portrait sequential workload", .serialized)
@MainActor
struct PortraitExplorationPerformanceTests {
  @Test("Next reuses analysis with at most two renders; retained navigation does none", arguments: PortraitStyle.authoringCases)
  func cachedWorkload(style: PortraitStyle) async throws {
    let environment = ProcessInfo.processInfo.environment
    if let selected = environment["PORTRAIT_EXPLORATION_STYLE"], selected != style.rawValue { return }
    let reference = environment["PORTRAIT_EXPLORATION_REFERENCE_PHOTO"]
    let image = try reference.map { try Data(contentsOf: URL(fileURLWithPath: $0)) } ?? explorationPerformanceImage()
    let renderer = ExplorationMeasuredRenderer()
    let model = PortraitStudioModel(renderer: renderer, explorationSeed: 0x50302026)
    let pen = try portraitTestStyle()
    model.style = style
    model.options = .init(cropToFace: false, removeBackground: false)
    model.vectorOptions = PortraitVectorPreset.balanced.options(for: style)
    let clock = ContinuousClock()
    let coldStart = clock.now
    model.setPhoto(image, for: .front, strokeStyle: pen)
    await model.awaitRendering()
    let coldMS = elapsedMS(coldStart.duration(to: clock.now))
    let center = try #require(model.selectedCandidate)
    var nextMS: [Double] = [], nextCalls: [Int] = [], accepted = 0, lateAccepted = 0
    for step in 0..<24 {
      let previous = try #require(model.selectedCandidate)
      let calls = await renderer.calls
      let started = clock.now
      model.nextPortrait(strokeStyle: pen)
      await model.awaitRendering()
      nextMS.append(elapsedMS(started.duration(to: clock.now)))
      nextCalls.append(await renderer.calls - calls)
      let candidate = try #require(model.selectedCandidate)
      #expect(candidate.rasterSHA256 == center.rasterSHA256)
      #expect(candidate.recipe.style == style)
      if candidate.id != previous.id {
        accepted += 1
        if step >= 12 { lateAccepted += 1 }
        let different = await Task.detached {
          PortraitExplorationPolicy.VisibleGeometry(candidate.program)
            .isMeaningfullyDifferent(from: PortraitExplorationPolicy.VisibleGeometry(previous.program))
        }.value
        #expect(different)
      }
    }
    #expect(await renderer.coldCalls == 1)
    #expect(nextCalls.allSatisfy { (0...2).contains($0) })
    #expect(accepted > 0)
    if style == .contours || style == .flowEdges {
      #expect(accepted >= 12)
      #expect(lateAccepted >= 5)
    }
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    let calls = await renderer.calls
    let current = try #require(model.selectedCandidate)
    let navigationStart = clock.now
    model.previousPortrait()
    model.nextPortrait(strokeStyle: pen)
    let navigationMS = elapsedMS(navigationStart.duration(to: clock.now))
    #expect(model.selectedCandidate?.program == current.program)
    #expect(await renderer.calls == calls)
    let stats: [String: Any] = ["style": style.rawValue, "coldMS": coldMS, "nextMS": nextMS,
      "nextRenderCalls": nextCalls, "accepted": accepted, "lateAccepted": lateAccepted, "backForwardMS": navigationMS,
      "nativeClickToPaintMeasured": false, "physicalOrHumanQualityEvidence": false]
    let bytes = try JSONSerialization.data(withJSONObject: stats, options: [.sortedKeys])
    print("PORTRAIT_SEQUENTIAL_WORKLOAD " + String(decoding: bytes, as: UTF8.self))
    if let path = environment["PORTRAIT_EXPLORATION_PERFORMANCE_OUTPUT"] {
      try bytes.write(to: URL(fileURLWithPath: path + "." + style.rawValue + ".json"), options: .atomic)
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
