import AppKit
import Foundation
import ImageIO
import PortraitCore

/// Derived presentation only. Immutable asset/revision identity and the decode
/// profile form the key; callers keep originals and guard visible publication.
@MainActor
package final class FlowPresentationImageCache {
  package static let shared = FlowPresentationImageCache()
  private struct Key: Hashable, Sendable { let identity: String; let dimension: Int }
  private struct Raster: @unchecked Sendable { let image: CGImage; let encodedBytes: Int }
  private struct Entry { let image: NSImage; let decodedBytes: Int; let cost: Int }
  private struct Flight { let id: UUID; let key: Key; let generation: UInt64; let task: Task<Raster?, Never> }
  private let maximumEntries: Int
  private let maximumBytes: Int
  private let maximumInflight: Int
  private var values: [Key: Entry] = [:]
  private var order: [Key] = []
  private var flights: [UUID: Flight] = [:]
  private var currentFlights: [Key: UUID] = [:]
  private var retainedBytes = 0
  private var decodedBytes = 0
  private var generation: UInt64 = 0
  package private(set) var decodeCount = 0
  private var peakInflight = 0

  package init(maximumEntries: Int = 80, maximumBytes: Int = 64 * 1024 * 1024, maximumInflight: Int = 2) {
    self.maximumEntries = max(1, maximumEntries)
    self.maximumBytes = max(1, maximumBytes)
    self.maximumInflight = max(1, maximumInflight)
  }
  package var statistics: [String: Int] {
    ["entries": values.count, "decodedBytes": decodedBytes, "residentByteCost": retainedBytes,
      "inflight": flights.count, "peakInflight": peakInflight, "maximumEntries": maximumEntries,
      "maximumResidentByteCost": maximumBytes, "maximumInflight": maximumInflight]
  }
  package func load(data: Data, identity: String, maximumDimension: Int = 2048) async -> NSImage? {
    await load(identity: identity, maximumDimension: maximumDimension, read: { data })
  }
  package func load(identity: String, maximumDimension: Int = 2048,
    read: @escaping @Sendable () async -> Data?) async -> NSImage? {
    let key = Key(identity: identity, dimension: max(1, min(2048, maximumDimension)))
    let requestGeneration = generation
    while !Task.isCancelled, requestGeneration == generation {
      if let entry = values[key] { touch(key); return entry.image }
      if let id = currentFlights[key], let flight = flights[id] {
        let raster = await flight.task.value
        let image = finish(flight, raster: raster)
        return Task.isCancelled ? nil : image
      }
      // Wait on bounded existing work instead of retaining an unbounded queue of
      // source buffers/workers. Any waiter may settle a completed shared flight.
      if flights.count >= maximumInflight, let pending = flights.values.first {
        let raster = await pending.task.value
        _ = finish(pending, raster: raster)
        continue
      }
      decodeCount += 1
      let task = Task.detached(priority: .userInitiated) { () -> Raster? in
        guard !Task.isCancelled, let data = await read(), UInt64(data.count) <= ExchangeCarrierLimits().maximumEncodedImageBytes,
          !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? Int.max
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? Int.max
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let image: CGImage?
        if width <= key.dimension, height <= key.dimension, orientation == 1 {
          // Preserve the exact decoded pixels when no resize/orientation work
          // is needed, rather than resampling an already viewport-sized preview.
          image = CGImageSourceCreateImageAtIndex(source, 0,
            [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        } else {
          image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: key.dimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
          ] as CFDictionary)
        }
        guard let image, !Task.isCancelled else { return nil }
        return Raster(image: image, encodedBytes: data.count)
      }
      let flight = Flight(id: UUID(), key: key, generation: generation, task: task)
      flights[flight.id] = flight; currentFlights[key] = flight.id; peakInflight = max(peakInflight, flights.count)
      let raster = await task.value
      let image = finish(flight, raster: raster)
      return Task.isCancelled ? nil : image
    }
    return nil
  }
  /// Canceled work remains admitted until it actually settles: ImageIO and a
  /// suspended reader need not stop immediately. Repeated invalidation therefore
  /// cannot open additional worker slots or let old completion remove new work.
  package func invalidate() {
    generation &+= 1
    for flight in flights.values { flight.task.cancel() }
    currentFlights.removeAll(); values.removeAll(); order.removeAll()
    retainedBytes = 0; decodedBytes = 0
  }
  private func touch(_ key: Key) { order.removeAll { $0 == key }; order.append(key) }
  private func finish(_ flight: Flight, raster: Raster?) -> NSImage? {
    let pending = flights.removeValue(forKey: flight.id) != nil
    if currentFlights[flight.key] == flight.id { currentFlights.removeValue(forKey: flight.key) }
    guard flight.generation == generation else { return nil }
    if !pending {
      return values[flight.key]?.image ?? raster.map { NSImage(cgImage: $0.image, size: .zero) }
    }
    guard let raster else { return nil }
    let image = NSImage(cgImage: raster.image, size: .zero)
    let pixels = raster.image.bytesPerRow * raster.image.height
    // ImageIO may retain the encoded provider after eager decoding. Charge its
    // full source size conservatively as well; report pixel bytes separately.
    let cost = pixels + raster.encodedBytes
    if cost <= maximumBytes {
      values[flight.key] = Entry(image: image, decodedBytes: pixels, cost: cost)
      retainedBytes += cost; decodedBytes += pixels; touch(flight.key)
      while order.count > maximumEntries || retainedBytes > maximumBytes {
        if let removed = values.removeValue(forKey: order.removeFirst()) {
          retainedBytes -= removed.cost; decodedBytes -= removed.decodedBytes
        }
      }
    }
    return image
  }
}
