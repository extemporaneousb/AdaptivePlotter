import AppKit
import QuartzCore
import SwiftUI
import Testing
import PlotterModel
@testable import PlotterApp

@Suite("Portrait preview reuse", .serialized)
@MainActor
struct PortraitPlanePreviewCacheTests {
  @Test("unchanged geometry reuses paths while viewport, source, placement, progress and width invalidate")
  func invalidation() throws {
    let fixture = try PreviewCacheFixture()
    let cache = PortraitPlanePreviewCache()
    let size = CGSize(width: 600, height: 500)
    let reference = PortraitPlanePreviewSource().resolve(program: fixture.program, nominalWidth: 0.4)
    let first = try #require(cache.resolve(reference, size: size))
    for index in 0..<10 {
      let metadataOnly = PortraitPlanePreviewSource(materialUnavailableReason: "Status \(index)")
        .resolve(program: fixture.program, nominalWidth: 0.4)
      let reused = try #require(cache.resolve(metadataOnly, size: size))
      #expect(reused.paths == first.paths)
    }
    #expect(cache.buildCount == 1)
    #expect(cache.hitCount == 10)

    let differentProgram = try previewCacheProgram(strokes: 3, points: 6)
    let material = try DrawingMaterialProfileRevision(name: "Wide pen", nominalWidthMM: 1.2)
    let camera = try DrawingCameraGeometry(cameraFromMachine: .init(
      m11: -1.7, m12: 0.2, m21: 0.04, m22: -1.34, tx: 1600, ty: 280))
    let rotated = try PreviewCacheFixture(program: fixture.program, rotation: 37)
    let cameraFixture = try PreviewCacheFixture(program: fixture.program, camera: camera)
    let cases: [(PortraitPlanePreview, CGSize)] = [
      (reference, CGSize(width: 800, height: 500)),
      (PortraitPlanePreviewSource().resolve(program: differentProgram, nominalWidth: 0.4), size),
      (PortraitPlanePreviewSource(material: material).resolve(program: fixture.program, nominalWidth: 0.4), size),
      (.planned(fixture.plan), size),
      (.planned(fixture.plan, completedStrokeCount: 1), size),
      (.planned(fixture.plan, completedStrokeCount: 2), size),
      (.planned(rotated.plan), size),
      (.planned(cameraFixture.plan), size),
      (.historical(program: fixture.program, presentation: try #require(
        cameraFixture.source.resolve(program: fixture.program, nominalWidth: 0.4).presentationContext)), size),
      (PortraitPlanePreviewSource(region: fixture.region).resolve(program: fixture.program, nominalWidth: 0.4), size)
    ]
    for (preview, viewport) in cases {
      let before = cache.buildCount
      let cached = try #require(cache.resolve(preview, size: viewport))
      let exact = try #require(PortraitPlaneDrawing(preview: preview, size: viewport))
      #expect(cache.buildCount == before + 1)
      #expect(cached.paths == exact.paths)
      #expect(cached.outline == exact.outline)
      #expect(cached.lineWidth == exact.lineWidth)
      _ = cache.resolve(preview, size: viewport)
      #expect(cache.buildCount == before + 1)
    }
    #expect(cache.resolve(reference, size: .zero) == nil)
    #expect(cache.retainedPointCount == 0)
    #expect(cache.resolve(PortraitPlanePreviewSource().resolve(program: nil, nominalWidth: 0.4), size: size) == nil)
  }

  @Test("oversized previews paint every point without retaining their paths")
  func retentionBound() throws {
    for (strokes, points) in [(2, PortraitPlanePreviewCache.maximumPoints / 2 + 1),
      (PortraitPlanePreviewCache.maximumStrokes + 1, 2)] {
      let program = try previewCacheProgram(strokes: strokes, points: points)
      let preview = PortraitPlanePreviewSource().resolve(program: program, nominalWidth: 0.4)
      let cache = PortraitPlanePreviewCache()
      let size = CGSize(width: 600, height: 500)
      let drawing = try #require(cache.resolve(preview, size: size))
      #expect(drawing.pointCount == strokes * points)
      #expect(drawing.paths.count == strokes)
      #expect(cache.retainedPointCount == 0)
      _ = cache.resolve(preview, size: size)
      #expect(cache.buildCount == 2)
    }
  }

  @Test("native hosted repaint preserves pixels and measures warm reuse",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_PREVIEW_BENCHMARK"] == "1"))
  func nativeRepaint() async throws {
    _ = NSApplication.shared
    let program = try previewCacheProgram(strokes: 800, points: 80)
    let size = CGSize(width: 800, height: 650)
    let cache = PortraitPlanePreviewCache()
    let baseline = PreviewBaselineCounter()
    func makeHost() -> (NSWindow, NSHostingView<AnyView>) {
      let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10000, y: -10000), size: size),
        styleMask: [.borderless], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let host = NSHostingView(rootView: AnyView(Color.white))
      host.frame = CGRect(origin: .zero, size: size)
      window.contentView = host
      window.orderFront(nil)
      return (window, host)
    }
    // Keep both view identities mounted: replacing one view type with the other
    // would measure remounting rather than unchanged-preview repaint work.
    let cachedHost = makeHost(), uncachedHost = makeHost()
    defer { cachedHost.0.close(); uncachedHost.0.close() }
    var samples: [String: [Double]] = ["uncached": [], "cached": []]
    var updateSamples: [String: [Double]] = ["uncached": [], "cached": []]
    var synchronousBaselineBuilds = 0
    var pixels: [String: Data] = [:]
    // Alternate paths so background load and window warmup do not favor one.
    for index in 0..<26 {
      for cached in index.isMultiple(of: 2) ? [false, true] : [true, false] {
        let (window, host) = cached ? cachedHost : uncachedHost
        let preview = PortraitPlanePreviewSource(materialUnavailableReason: "Paint \(index)")
          .resolve(program: program, nominalWidth: 0.4)
        let started = ContinuousClock.now
        let baselineBuildsBefore = baseline.buildCount
        host.rootView = cached
          ? AnyView(PortraitPlaneProgramPreview(preview: preview, cache: cache))
          : AnyView(UncachedPreview(preview: preview, counter: baseline))
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        let updateElapsed = started.duration(to: .now)
        let updateMS = Double(updateElapsed.components.seconds) * 1000
          + Double(updateElapsed.components.attoseconds) / 1e15
        if !cached { synchronousBaselineBuilds += baseline.buildCount - baselineBuildsBefore }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        CATransaction.flush()
        let elapsed = started.duration(to: .now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        let name = cached ? "cached" : "uncached"
        if index >= 2 {
          samples[name, default: []].append(ms)
          updateSamples[name, default: []].append(updateMS)
        }
        if index == 25 {
          let data = try #require(bitmap.bitmapData)
          pixels[name] = Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
          let center = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2,
            y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
          let corner = try #require(bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB))
          #expect(center.redComponent < 0.5 && center.alphaComponent > 0.9)
          #expect(corner.redComponent > 0.9 && corner.alphaComponent > 0.9)
        }
        await Task.yield()
      }
    }
    #expect(!cachedHost.0.isKeyWindow && !uncachedHost.0.isKeyWindow)
    #expect(pixels["cached"] == pixels["uncached"])
    #expect(baseline.buildCount >= 24)
    #expect(synchronousBaselineBuilds >= 24)
    #expect(cache.buildCount == 1)
    func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    #if DEBUG
    let configuration = "debug"
    #else
    let configuration = "release"
    #endif
    let report: [String: Any] = [
      "workload": "800 strokes, 64000 points, 800x650 native NSHostingView repaint",
      "uncachedMedianMS": median(samples["uncached"]!),
      "cachedMedianMS": median(samples["cached"]!),
      "samplesMS": samples,
      "uncachedUpdateMedianMS": median(updateSamples["uncached"]!),
      "cachedUpdateMedianMS": median(updateSamples["cached"]!),
      "updateSamplesMS": updateSamples,
      "synchronousBaselineBuilds": synchronousBaselineBuilds,
      "updateTimingScope": "root update, layout, displayIfNeeded and transaction flush; bitmap capture and GPU completion excluded",
      "baselineBuilds": baseline.buildCount, "cachedBuilds": cache.buildCount,
      "cacheHits": cache.hitCount, "pixelsEqual": pixels["cached"] == pixels["uncached"],
      "buildConfiguration": configuration,
      "liveUserSession": false, "physicalEvidence": false
    ]
    let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    print("PORTRAIT_NATIVE_PREVIEW " + String(decoding: bytes, as: UTF8.self))
    // Equality must not suppress layout-driven invalidation inside the child.
    let buildsBeforeResize = cache.buildCount
    var resizedPixels: [Data] = []
    for (window, host) in [cachedHost, uncachedHost] {
      window.setContentSize(CGSize(width: 640, height: 480))
      host.layoutSubtreeIfNeeded()
      window.displayIfNeeded()
      let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
      host.cacheDisplay(in: host.bounds, to: bitmap)
      let data = try #require(bitmap.bitmapData)
      resizedPixels.append(Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh))
    }
    #expect(cache.buildCount > buildsBeforeResize)
    #expect(resizedPixels[0] == resizedPixels[1])
    if let path = ProcessInfo.processInfo.environment["PORTRAIT_PREVIEW_BENCHMARK_OUTPUT"] {
      try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
  }
}

@MainActor
private final class PreviewBaselineCounter {
  var buildCount = 0
}

private struct UncachedPreview: View {
  let preview: PortraitPlanePreview
  let counter: PreviewBaselineCounter
  var body: some View {
    Canvas { context, size in
      counter.buildCount += 1
      PortraitPlaneDrawing(preview: preview, size: size)?.draw(in: &context)
    }.background(.white)
  }
}

private struct PreviewCacheFixture {
  let program: DrawingProgram
  let region: DrawableMachineRegion
  let plan: ExecutionPlanRevision
  var source: PortraitPlanePreviewSource { .init(region: region, artworkPlan: plan) }
  init(program: DrawingProgram? = nil, rotation: Double = 0, camera: DrawingCameraGeometry? = nil) throws {
    self.program = try program ?? previewCacheProgram(strokes: 4, points: 8)
    region = try .init(bounds: AxisAlignedBounds(minX: -310, minY: -210, maxX: -90, maxY: -70), edgeClearance: 10)
    let placement = try DrawingPlacement(fieldAnchor: Point2(x: 50, y: 50),
      machineAnchor: Point2(x: -185, y: -135), uniformScale: 0.5,
      rotationRadians: rotation * .pi / 180, cameraGeometry: camera)
    let hash = self.program.contentHash
    plan = try DrawingPlanner.plan(program: self.program, placement: placement, drawableRegion: region,
      provenance: .init(modelRevisionID: DrawingModelRevisionID(), modelContentHash: hash,
        registrationRevisionID: DrawingRegistrationRevisionID(), registrationContentHash: hash))
  }
}

private func previewCacheProgram(strokes: Int, points: Int) throws -> DrawingProgram {
  let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
  let paths = try (0..<strokes).map { index in
    let samples = try (0..<points).map { point in
      try Point2<FieldSpace>(x: 5 + 90 * Double(point) / Double(points - 1),
        y: 5 + 88 * Double(index) / Double(strokes) + sin(Double(point) * 0.3))
    }
    return LogicalStroke(id: StrokeID(), path: try Polyline(points: samples), style: style, ordering: UInt32(index))
  }
  return try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100),
    strokes: paths, source: .init(kind: "test", sourceIdentifier: "preview-cache"))
}
