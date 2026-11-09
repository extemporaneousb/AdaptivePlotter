import AppKit
import Foundation
import ImageIO
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing

@Suite("Derived Drawing presentation bounds and lifetime", .serialized)
@MainActor
struct DrawingPresentationCacheTests {
  @Test("Concurrent exact requests share one materialization; render size remains part of identity")
  func deduplicationAndProfile() async throws {
    let gate = PresentationReadGate(FlowDojoFixture.image(1))
    defer { gate.release() }
    let cache = FlowPresentationImageCache()
    let first = Task { await cache.load(identity: "exact-source", read: { await gate.read() }) }
    try await gate.waitForStarts(1)
    let second = Task { await cache.load(identity: "exact-source", read: { await gate.read() }) }
    await Task.yield(); gate.release()
    let a = try #require(await first.value), b = try #require(await second.value)
    #expect(a === b && cache.decodeCount == 1)
    #expect(gate.starts == 1)
    let smaller = try #require(await cache.load(data: FlowDojoFixture.image(1), identity: "exact-source", maximumDimension: 20))
    var rect = NSRect(origin: .zero, size: smaller.size)
    #expect(try #require(smaller.cgImage(forProposedRect: &rect, context: nil, hints: nil)).width == 20)
    #expect(cache.decodeCount == 2 && cache.statistics["entries"] == 2)
  }

  @Test("Resident pixels and entries are independently bounded; oversized results are presented without retention")
  func byteAndEntryBounds() async throws {
    let data = FlowDojoFixture.image(2)
    let probe = FlowPresentationImageCache()
    _ = try #require(await probe.load(data: data, identity: "probe"))
    let pixels = try #require(probe.statistics["decodedBytes"])
    let cost = try #require(probe.statistics["residentByteCost"])
    let bytes = FlowPresentationImageCache(maximumEntries: 80, maximumBytes: cost * 2)
    for index in 0..<4 { _ = try #require(await bytes.load(data: data, identity: "immutable-\(index)")) }
    #expect(bytes.statistics["entries"] == 2 && bytes.statistics["decodedBytes"] == pixels * 2 && bytes.statistics["residentByteCost"] == cost * 2)
    let entries = FlowPresentationImageCache(maximumEntries: 1)
    for index in 0..<3 { _ = try #require(await entries.load(data: data, identity: "entry-\(index)")) }
    #expect(entries.statistics["entries"] == 1)
    let oversized = FlowPresentationImageCache(maximumBytes: cost - 1)
    _ = try #require(await oversized.load(data: data, identity: "too-large-to-retain"))
    #expect(oversized.statistics["entries"] == 0 && oversized.statistics["decodedBytes"] == 0)
  }

  @Test("Worker admission is bounded, cancellation withholds pixels, and invalidated work cannot republish")
  func cancellationAndInflightBounds() async throws {
    let gate = PresentationReadGate(FlowDojoFixture.image(3))
    defer { gate.release() }
    let cache = FlowPresentationImageCache(maximumInflight: 2)
    let requests = (0..<6).map { index in Task { await cache.load(identity: "request-\(index)", read: { await gate.read() }) } }
    try await gate.waitForStarts(2)
    #expect(cache.statistics["inflight"] == 2)
    requests[0].cancel()
    gate.release()
    for request in requests { _ = await request.value }
    #expect(await requests[0].value == nil)
    #expect(cache.statistics["peakInflight"] == 2 && cache.statistics["inflight"] == 0)

    let oldGate = PresentationReadGate(FlowDojoFixture.image(4))
    defer { oldGate.release() }
    let old = (0..<2).map { index in Task {
      await cache.load(identity: "superseded-\(index)", read: { await oldGate.read() })
    } }
    try await oldGate.waitForStarts(2)
    // A canceled read deliberately ignores cancellation until explicitly released.
    // Repeated invalidation must not free admission slots while it remains alive.
    for _ in 0..<4 { cache.invalidate() }
    #expect(cache.statistics["inflight"] == 2)
    let currentGate = PresentationReadGate(FlowDojoFixture.image(5))
    defer { currentGate.release() }
    let current = Task { await cache.load(identity: "superseded-0", read: { await currentGate.read() }) }
    await Task.yield()
    #expect(currentGate.starts == 0)
    #expect(cache.statistics["inflight"] == 2)
    oldGate.release()
    try await currentGate.waitForStarts(1)
    #expect(cache.statistics["peakInflight"] == 2)
    currentGate.release()
    _ = try #require(await current.value)
    for request in old { #expect(await request.value == nil) }
    #expect(cache.statistics["entries"] == 1 && cache.statistics["inflight"] == 0)
  }

  @Test("A valid encoded image above the authoring import limit still gets an uncached bounded preview")
  func largeEncodedImage() async throws {
    let png = FlowDojoFixture.image(1)
    let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let encoded = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    let jpeg = encoded as Data
    try #require(jpeg.starts(with: [0xff, 0xd8]))
    // Legal JPEG APP15 segments add encoded bytes without a huge decoded raster
    // or a costly incompressible multi-megapixel fixture. Each length includes
    // its two length bytes; unknown application segments are intentionally opaque.
    var segment = Data([0xff, 0xef, 0xff, 0xff])
    segment.append(Data(repeating: 0x5a, count: 65_533))
    var padded = Data(jpeg.prefix(2)); padded.reserveCapacity(34 * 1024 * 1024)
    for _ in 0..<513 { padded.append(segment) }
    padded.append(jpeg.dropFirst(2))
    try #require(padded.count > DrawingArtifactLimits.sourceBytes)
    try #require(UInt64(padded.count) <= ExchangeCarrierLimits().maximumEncodedImageBytes)
    let admitted = try #require(CGImageSourceCreateWithData(padded as CFData, nil))
    #expect(CGImageSourceGetCount(admitted) == 1)
    let cache = FlowPresentationImageCache(maximumBytes: 1024 * 1024)
    let preview = try #require(await cache.load(data: padded, identity: "large-encoded-image", maximumDimension: 20))
    var rect = NSRect(origin: .zero, size: preview.size)
    #expect(try #require(preview.cgImage(forProposedRect: &rect, context: nil, hints: nil)).width == 20)
    #expect(cache.statistics["entries"] == 0 && cache.statistics["residentByteCost"] == 0)
    let thumbnails = FlowDojoThumbnailCache(maximumBytes: 1)
    let original = padded
    let encodedThumbnail = try await thumbnails.load(key: "large-encoded-image") { original }
    #expect(!encodedThumbnail.isEmpty && encodedThumbnail.count < padded.count)
    #expect(await thumbnails.statistics["entries"] == 0)
  }

  @Test("Encoded thumbnail requests coalesce and their bytes remain bounded independently of decoded pixels")
  func encodedThumbnails() async throws {
    let gate = PresentationReadGate(FlowDojoFixture.image(1))
    defer { gate.release() }
    let cache = FlowDojoThumbnailCache(maximumEntries: 1, maximumBytes: 1024 * 1024, maximumInflight: 1)
    let first = Task { try await cache.load(key: "source") { await gate.read() } }
    try await gate.waitForStarts(1)
    let second = Task { try await cache.load(key: "source") { await gate.read() } }
    await Task.yield(); gate.release()
    #expect(try await first.value == second.value)
    #expect(gate.starts == 1)
    _ = try await cache.load(key: "other") { FlowDojoFixture.image(2) }
    let stats = await cache.statistics
    #expect(stats["entries"] == 1 && stats["encodedBytes", default: 0] <= 1024 * 1024 && stats["inflight"] == 0)
    let tooSmall = FlowDojoThumbnailCache(maximumBytes: 1)
    let presented = try await tooSmall.load(key: "uncached") { FlowDojoFixture.image(1) }
    #expect(!presented.isEmpty)
    #expect(await tooSmall.statistics["entries"] == 0)
  }
}

@MainActor
private final class PresentationReadGate {
  let data: Data
  private(set) var starts = 0
  private var released = false
  private var readers: [CheckedContinuation<Void, Never>] = []
  init(_ data: Data) { self.data = data }
  func read() async -> Data {
    starts += 1
    if !released { await withCheckedContinuation { readers.append($0) } }
    return data
  }
  func waitForStarts(_ count: Int) async throws {
    let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while starts < count, clock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    try #require(starts >= count,
      "Presentation cache reader admission timed out after 5 seconds: expected \(count), observed \(starts).")
  }
  func release() { released = true; let pending = readers; readers = []; for reader in pending { reader.resume() } }
}
