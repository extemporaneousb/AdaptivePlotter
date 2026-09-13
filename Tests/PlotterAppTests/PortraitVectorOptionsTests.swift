import CoreGraphics
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Portrait density and structural sketch")
struct PortraitVectorOptionsTests {
  @Test("coarse hatch spacing reduces actual pen paths and crossed passes")
  func hatchCoarsening() throws {
    let raster = raster(width: 100, height: 100) { _, _ in 0.1 }
    let fine = try draw(raster, .crosshatch, PortraitVectorOptions(hatchSpacing: 2))
    let coarse = try draw(raster, .crosshatch, PortraitVectorOptions(hatchSpacing: 8))
    #expect(fine.strokes.count == 98)
    #expect(coarse.strokes.count == 26)
    #expect(coarse.strokes.allSatisfy { abs($0.path.length - 100) < 0.001 })
    #expect(fine.id != coarse.id)
    #expect(coarse.source.sourceIdentifier.contains("hatchSpacing=8"))
  }

  @Test("minimum contour length removes small marks while retaining the large outline")
  func minimumLength() throws {
    let raster = raster(width: 100, height: 100) { x, y in
      hypot(Double(x - 20), Double(y - 20)) < 2
        || hypot(Double(x - 60), Double(y - 60)) < 15 ? 0 : 1
    }
    let fine = try draw(raster, .contours,
      PortraitVectorOptions(contourLevels: 1, minimumContourLength: 0))
    let coarse = try draw(raster, .contours,
      PortraitVectorOptions(contourLevels: 1, minimumContourLength: 30))
    #expect(fine.strokes.count == 2)
    #expect(coarse.strokes.count == 1)
    #expect(coarse.strokes[0].path.length > 80)
  }

  @Test("sketch traces a structural transition as a centerline")
  func structuralSketch() throws {
    let raster = raster(width: 80, height: 100) { x, _ in x < 40 ? 0 : 1 }
    let program = try draw(raster, .sketch, PortraitVectorOptions())
    #expect(!program.strokes.isEmpty)
    #expect(program.strokes.count <= 4)
    #expect(program.strokes.contains { $0.path.length > 80 })
    #expect(program.strokes.flatMap(\.path.points).allSatisfy { $0.x > 35 && $0.x < 43 })
    #expect(program.source.sourceIdentifier.contains("style=Sketch"))
  }

  @Test("smoothing suppresses small texture without adding image analysis")
  func smoothing() throws {
    let raster = raster(width: 100, height: 100) { x, y in
      if x > 35 && x < 65 && y > 35 && y < 65 { return 0.1 }
      return (x / 2 + y / 2).isMultiple(of: 2) ? 0.45 : 0.9
    }
    let raw = try draw(raster, .contours,
      PortraitVectorOptions(contourLevels: 1, minimumContourLength: 0, smoothing: 0))
    let smooth = try draw(raster, .contours,
      PortraitVectorOptions(contourLevels: 1, minimumContourLength: 0, smoothing: 2))
    #expect(smooth.strokes.count < raw.strokes.count)
    #expect(!smooth.strokes.isEmpty)
  }

  @Test("tone adjustment changes the generated hatch, including its source identity")
  func tonalStrength() throws {
    let raster = raster(width: 80, height: 100) { _, _ in 0.6 }
    let light = try draw(raster, .hatch, PortraitVectorOptions(tonalStrength: 1))
    let dark = try draw(raster, .hatch, PortraitVectorOptions(tonalStrength: 2))
    #expect(dark.strokes.count > light.strokes.count)
    #expect(dark.contentHash != light.contentHash)
  }

  @Test("nonfinite and out-of-range options produce the same safe effective recipe")
  func boundedOptions() throws {
    let unsafe = PortraitVectorOptions(contourLevels: Int.max, minimumContourLength: .nan,
      simplificationTolerance: -.infinity, hatchSpacing: 0, tonalStrength: .infinity,
      smoothing: -10, sketchThreshold: .nan)
    let effective = PortraitVectorOptions(contourLevels: 12, minimumContourLength: 3,
      simplificationTolerance: 0.35, hatchSpacing: 1, tonalStrength: 1, smoothing: 0,
      sketchThreshold: 0.012)
    #expect(unsafe.bounded == effective)
    #expect(try draw(portraitTestRaster(), .contours, unsafe)
      == draw(portraitTestRaster(), .contours, effective))
  }

  @Test("invalid rasters fail without indexing their storage")
  func invalidRaster() throws {
    let invalid = PortraitRaster(width: 100, height: 100, luminance: [],
      provenance: "invalid", analysisSummary: "fixture")
    #expect(throws: PortraitDrawingError.self) { try draw(invalid, .contours, PortraitVectorOptions()) }
    let nonfinite = raster(width: 3, height: 3) { _, _ in .nan }
    #expect(throws: PortraitDrawingError.self) { try draw(nonfinite, .sketch, PortraitVectorOptions()) }
  }

  @Test("already-cancelled authoring does not produce a drawing")
  func cancellation() async throws {
    let task = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      return try draw(portraitTestRaster(), .sketchHatch, PortraitVectorPreset.broadMarker.options)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test("head framing increases face occupancy and preserves image bounds")
  func headFraming() {
    let face = CGRect(x: 0.25, y: 0.3, width: 0.3, height: 0.4)
    let close = PortraitImageAnalyzer.faceCrop(bounds: face, imageWidth: 1000, imageHeight: 1000, margin: 0.05)
    let wide = PortraitImageAnalyzer.faceCrop(bounds: face, imageWidth: 1000, imageHeight: 1000, margin: 0.8)
    #expect(close.width < wide.width && close.height < wide.height)
    #expect(wide.minX >= 0 && wide.minY >= 0 && wide.maxX <= 1000 && wide.maxY <= 1000)
    #expect(PortraitImageAnalyzer.faceCrop(bounds: face, imageWidth: 1000, imageHeight: 1000, margin: .nan)
      == PortraitImageAnalyzer.faceCrop(bounds: face, imageWidth: 1000, imageHeight: 1000, margin: 0.35))
  }

  @Test("camera image normalization bounds retained dimensions")
  func capturedImageSize() throws {
    let width = 1600, height = 2400
    let bytes = Data(repeating: 128, count: width * height)
    let provider = try #require(CGDataProvider(data: bytes as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let normalized = try PortraitImageAnalyzer.scaledImage(image, maximumDimension: 1200)
    #expect(normalized.width == 800 && normalized.height == 1200)
  }

  private func draw(_ raster: PortraitRaster, _ style: PortraitStyle, _ options: PortraitVectorOptions) throws -> DrawingProgram {
    try PortraitVectorizer.program(from: raster, pose: .front, style: style,
      strokeStyle: portraitTestStyle(), vectorOptions: options)
  }

  private func raster(width: Int, height: Int, _ sample: (Int, Int) -> Double) -> PortraitRaster {
    PortraitRaster(width: width, height: height,
      luminance: (0..<(width * height)).map { sample($0 % width, $0 / width) },
      provenance: "density-fixture", analysisSummary: "synthetic fixture")
  }
}
