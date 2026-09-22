import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PlotterRuntime
import Testing
import UniformTypeIdentifiers

@testable import PlotterApp

@Suite("Portrait still-photo selection")
struct PortraitBurstSelectorTests {
  @Test("sharp exposed source wins over softened, black and clipped white frames")
  func qualitySelectionPreservesOriginalSource() throws {
    let extent = try PortraitSourceCropExtent(widthPixels: 1200, heightPixels: 900)
    let sharp = PortraitBurstSample(data: try png { x, _ in x < 32 ? 64 : 192 },
      frameID: FrameID(), captureNanoseconds: 101, label: "Sharp source", sourcePixelExtent: extent)
    let soft = PortraitBurstSample(data: try png { x, _ in
      UInt8(64 + min(32, max(0, x - 16)) * 4)
    }, frameID: FrameID(), captureNanoseconds: 102, label: "Soft source")
    let dark = PortraitBurstSample(data: try png { _, _ in 0 },
      frameID: FrameID(), captureNanoseconds: 103, label: "Dark source")
    let white = PortraitBurstSample(data: try png { _, _ in 255 },
      frameID: FrameID(), captureNanoseconds: 104, label: "White source")

    let selected = try #require(try PortraitBurstSelector.select(from: [sharp, soft, dark, white]))
    #expect(selected.data == sharp.data)
    #expect(selected.frameID == sharp.frameID)
    #expect(selected.captureNanoseconds == sharp.captureNanoseconds)
    #expect(selected.sourcePixelExtent == extent)
    #expect(selected.label == sharp.label)
    let provenance = try #require(selected.selectionProvenance)
    #expect(provenance.method == .sharpnessAndExposure)
    #expect(provenance.capturedFrameCount == 4)
    #expect(provenance.evaluatedFrameCount == 4)
    #expect(try #require(provenance.selectedSharpness) > 0)
    #expect(provenance.selectedClippedFraction == 0)
  }

  @Test("bounded evaluation and equal scores consistently prefer the latest source")
  func boundedDeterministicSelection() throws {
    let data = try png { x, _ in x < 32 ? 64 : 192 }
    let samples = (1...20).map { index in
      PortraitBurstSample(data: data, frameID: FrameID(),
        captureNanoseconds: UInt64(index), label: "Source \(index)")
    }
    let first = try #require(try PortraitBurstSelector.select(from: samples))
    let second = try #require(try PortraitBurstSelector.select(from: samples))
    #expect(first.frameID == samples.last?.frameID)
    #expect(first.frameID == second.frameID)
    #expect(first.selectionProvenance == second.selectionProvenance)
    #expect(first.selectionProvenance?.capturedFrameCount == 20)
    #expect(first.selectionProvenance?.evaluatedFrameCount == PortraitBurstSelector.maximumEvaluatedFrames)
  }

  @Test("unreadable or oversized inputs fall back without claiming quality measurement")
  func boundedFallback() throws {
    let invalid = PortraitBurstSample(data: Data([1, 2, 3]), frameID: FrameID(),
      captureNanoseconds: 1, label: "Unreadable")
    let oversized = PortraitBurstSample(
      data: Data(repeating: 0, count: PortraitBurstSelector.maximumEncodedFrameBytes + 1),
      frameID: FrameID(), captureNanoseconds: 2, label: "Oversized")
    let selected = try #require(try PortraitBurstSelector.select(from: [invalid, oversized]))
    #expect(selected.frameID == oversized.frameID)
    #expect(selected.selectionProvenance?.method == .latestAvailable)
    #expect(selected.selectionProvenance?.evaluatedFrameCount == 0)
    #expect(selected.selectionProvenance?.selectedSharpness == nil)
    #expect(selected.selectionProvenance?.selectedMeanLuminance == nil)
    #expect(try PortraitBurstSelector.select(from: []) == nil)
  }

  @Test("a later corrupt frame does not displace an evaluated source")
  func validBeforeCorrupt() throws {
    let valid = PortraitBurstSample(data: try png { x, _ in x < 32 ? 64 : 192 },
      frameID: FrameID(), captureNanoseconds: 1, label: "Valid")
    let invalid = PortraitBurstSample(data: Data([1]), frameID: FrameID(),
      captureNanoseconds: 2, label: "Invalid")
    let selected = try #require(try PortraitBurstSelector.select(from: [valid, invalid]))
    #expect(selected.frameID == valid.frameID)
    #expect(selected.selectionProvenance?.evaluatedFrameCount == 1)
  }

  @Test("cancelled selection never publishes a fallback")
  func cancellation() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try PortraitBurstSelector.select(from: [
        PortraitBurstSample(data: Data([1]), frameID: nil, captureNanoseconds: nil, label: "Held"),
      ])
    }
    do {
      _ = try await task.value
      Issue.record("Cancelled selection returned a sample")
    } catch is CancellationError {
      // Cancellation takes precedence even when all source bytes are invalid.
    }
  }

  private func png(_ value: (Int, Int) -> UInt8) throws -> Data {
    let width = 64, height = 64
    let pixels = Data((0..<height).flatMap { y in (0..<width).map { x in value(x, y) } })
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
      bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data,
      UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }
}
