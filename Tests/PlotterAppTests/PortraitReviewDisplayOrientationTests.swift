import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PortraitCore
import Testing
@testable import PortraitArtists
@testable import PortraitLibrary

private struct ReviewOrientationPixels {
  let image: CGImage
  let bytes: Data
  let components: Int
  init(_ asset: DrawingPackageAsset) throws {
    let source = try #require(CGImageSourceCreateWithData(asset.bytes as CFData, nil))
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let count = decoded.bitsPerPixel / 8
    #expect(decoded.bitsPerComponent == 8)
    #expect(count >= 3 && count <= 4)
    let data = try #require(decoded.dataProvider?.data) as Data
    image = decoded; components = count; bytes = data
  }
  /// Decoded PNG storage rows are image-pixel y-down, independent of the rendering CGContext.
  func shade(x: Int, y: Int) throws -> Double {
    #expect(x >= 0 && x < image.width && y >= 0 && y < image.height)
    let offset = y * image.bytesPerRow + x * components
    guard offset >= 0, offset + components <= bytes.count else { throw DrawingTransferError.invalid("Pixel sample is out of bounds.") }
    // The fixture is opaque black/white. Including an alpha/skip byte remains well separated:
    // black is <=64, white is >=191 for RGBA, regardless of channel order.
    return bytes[offset..<(offset + components)].reduce(0.0, { $0 + Double($1) }) / Double(components)
  }
}

private func orientationPackage(_ program: DrawingProgram, source: DrawingPackageAsset,
  capture: UUID, library: UUID, result: String) throws -> DrawingPackage {
  let record = try JSONSerialization.data(withJSONObject: ["orientationFixture": result], options: [.sortedKeys])
  return try .init(origin: .init(libraryID: library, captureID: capture, resultID: result,
    resultRecordSHA256: DrawingPackageCodec.sha256(record), programHash: program.contentHash),
    program: program, createdAt: Date(timeIntervalSinceReferenceDate: 100), title: "Asymmetric orientation",
    resultRecordJSON: record, source: source, artistInput: source,
    artist: .init(identifier: "orientation-fixture", revision: "1", settingsJSON: Data("{}".utf8)), preview: source)
}

private func orientationComparison(_ program: DrawingProgram, source: DrawingPackageAsset,
  store: PortraitCandidateStore) async throws -> PortraitReviewComparison {
  let capture = UUID(), library = UUID()
  let p = try orientationPackage(program, source: source, capture: capture, library: library, result: "a")
  let q = try orientationPackage(program, source: source, capture: capture, library: library, result: "b")
  let a = try await store.importDrawingPackage(DrawingPackageCodec.encode(p))
  let b = try await store.importDrawingPackage(DrawingPackageCodec.encode(q))
  return try await store.createReviewComparison(first: a, second: b, presentationSeed: 7, rubricVersion: "orientation-1")
}

private func shadeAtField(_ point: Point2<FieldSpace>, comparison: PortraitReviewComparison,
  pixels: ReviewOrientationPixels) throws -> Double {
  let padding = comparison.displayPaddingMM
  let scale = 1024 / max(comparison.displayMaterial.widthMM + 2 * padding,
    comparison.displayMaterial.heightMM + 2 * padding)
  // This expectation uses PNG's y-down coordinates, whereas the renderer draws into y-up Quartz.
  let x = Int(((point.x + padding) * scale).rounded())
  let y = Int((Double(comparison.displayPixelHeight) - (point.y + padding) * scale).rounded())
  return try pixels.shade(x: x, y: y)
}

@Suite("Matched review display orientation", .serialized)
struct PortraitReviewDisplayOrientationTests {
  @Test("An asymmetric y-up FieldSpace program keeps its upper-left and lower-right strokes in PNG")
  func authoredFieldToPNG() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let style = try StrokeStyle(nominalLineWidth: 1, penProfileID: PenProfileID(UUID()))
    let upper = try Polyline<FieldSpace>(points: [Point2(x: 10, y: 80), Point2(x: 30, y: 80)])
    let lower = try Polyline<FieldSpace>(points: [Point2(x: 70, y: 20), Point2(x: 70, y: 35)])
    let program = try DrawingProgram(id: ProgramID(UUID()), fieldExtent: Size2(width: 100, height: 100),
      strokes: [.init(id: StrokeID(UUID()), path: upper, style: style, ordering: 0),
        .init(id: StrokeID(UUID()), path: lower, style: style, ordering: 1)],
      source: .init(kind: "portrait", sourceIdentifier: "asymmetric-y-up-field-fixture"))
    let originalHash = program.contentHash
    let store = PortraitCandidateStore(directoryURL: root)
    let comparison = try await orientationComparison(program, source: transferTestPackage().source, store: store)
    let pixels = try ReviewOrientationPixels(await store.loadReviewDisplayPreview(comparisonID: comparison.id, side: .a))
    #expect(comparison.displayTransformRevision == "portrait-review-common-field-v2-y-up")
    #expect(try shadeAtField(Point2(x: 20, y: 80), comparison: comparison, pixels: pixels) < 128)
    #expect(try shadeAtField(Point2(x: 20, y: 20), comparison: comparison, pixels: pixels) > 160)
    #expect(try shadeAtField(Point2(x: 70, y: 27), comparison: comparison, pixels: pixels) < 128)
    #expect(try shadeAtField(Point2(x: 70, y: 73), comparison: comparison, pixels: pixels) > 160)
    #expect(try await store.loadReviewPackage(origin: comparison.a.origin).program == program)
    #expect(program.contentHash == originalHash)
  }

  @Test("Image-pixel y-down cubics convert once to FieldSpace and agree with original/model-preview orientation")
  func rawImageToFieldToPNG() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let topCurve = [[22.0, 45], [35, 45], [55, 45], [67, 45]]
    let bottomCurve = [[168.0, 157], [168, 164], [168, 173], [168, 179]]
    let curves = Array(repeating: topCurve, count: 16) + Array(repeating: bottomCurve, count: 16)
    let normalized = curves.map { $0.map { $0.map { $0 / 224 * 2 - 1 } } }
    let raw = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
      "canvas_width": 224, "canvas_height": 224, "coordinate_space": "image-pixels-y-down",
      "curve_kind": "ordered-open-cubic", "refined": curves,
      "refined_normalized": normalized, "diffusion_normalized": normalized], options: [.sortedKeys])
    let source = try asymmetricImagePixels()
    let program = try SwiftSketchConverter.program(raw: raw, fieldWidthMM: 100, fieldHeightMM: 100,
      nominalPenWidthMM: 0.4, sourceIdentifier: source.sha256)
    let before = program.contentHash
    let store = PortraitCandidateStore(directoryURL: root)
    let comparison = try await orientationComparison(program, source: source, store: store)
    let display = try ReviewOrientationPixels(await store.loadReviewDisplayPreview(comparisonID: comparison.id, side: .a))
    let original = try ReviewOrientationPixels(source)
    #expect(try original.shade(x: 45, y: 45) < 128)
    #expect(try original.shade(x: 45, y: 179) > 160)
    #expect(try original.shade(x: 168, y: 168) < 128)
    #expect(try original.shade(x: 168, y: 56) > 160)
    let upper = try Point2<FieldSpace>(x: 45.0 / 224 * 100, y: (224.0 - 45) / 224 * 100)
    let lower = try Point2<FieldSpace>(x: 168.0 / 224 * 100, y: (224.0 - 168) / 224 * 100)
    #expect(try shadeAtField(upper, comparison: comparison, pixels: display) < 128)
    #expect(try shadeAtField(Point2(x: upper.x, y: 100 - upper.y), comparison: comparison, pixels: display) > 160)
    #expect(try shadeAtField(lower, comparison: comparison, pixels: display) < 128)
    #expect(try shadeAtField(Point2(x: lower.x, y: 100 - lower.y), comparison: comparison, pixels: display) > 160)
    let retained = try await store.loadReviewPackage(origin: comparison.a.origin)
    #expect(retained.program.contentHash == before && retained.program.id == program.id)
    #expect(retained.preview == source && retained.source == source)
  }
}

private func asymmetricImagePixels() throws -> DrawingPackageAsset {
  let width = 224, height = 224
  var bytes = Data(repeating: 255, count: width * height * 4)
  // Literal image-pixel rows, with no CGContext transform to mirror the implementation.
  for y in 43...47 { for x in 22...67 {
    let offset = (y * width + x) * 4
    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0
  } }
  for y in 157...179 { for x in 166...170 {
    let offset = (y * width + x) * 4
    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0
  } }
  let provider = try #require(CGDataProvider(data: bytes as CFData))
  let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
    bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
    decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  let encoded = NSMutableData()
  let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  return .init(mediaType: "image/png", bytes: encoded as Data, pixelWidth: width, pixelHeight: height)
}
