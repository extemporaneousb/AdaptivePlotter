import Foundation
import CoreGraphics
import ImageIO
import DrawingLibrary
import PlotterModel
import PortraitCore
import PortraitArtists
import PortraitStudioUI
import Testing

@Suite("Prepared image variant thumbnails")
struct DrawingLibraryThumbnailTests {
  @Test("Actual prepared float64 luminance input renders distinct dark and light pixels without modifying its asset")
  func preparedLuminancePixels() throws {
    let sourceBytes = FlowAuthoringFixture.image(1)
    let source = try PortraitDrawingImages.sourceAsset(sourceBytes)
    let extent = try PortraitSourceCropExtent(widthPixels: Double(source.width), heightPixels: Double(source.height))
    let geometry = PortraitAnalysisGeometry(sourcePixelExtent: extent, decodedWidth: source.width, decodedHeight: source.height,
      crop: .init(x: 0, y: 0, width: Double(source.width), height: Double(source.height)), rasterWidth: 2, rasterHeight: 2,
      contrastLow: 0, contrastHigh: 1, contrastApplied: true)
    let raster = PortraitRaster(width: 2, height: 2, luminance: [0, 0.25, 0.75, 1], provenance: "synthetic-thumbnail-fixture",
      analysisSummary: "Explicit numerical fixture", sourceCropExtent: extent, analysisGeometry: geometry)
    let photo = try PortraitDrawingImages.photo(data: sourceBytes, issuer: UUID(), captureID: UUID(), capturedAt: nil, importedAt: Date())
    let program = try FlowPortfolioTests.program()
    let prepared = try PortraitDrawingImages.input(result: .init(raster: raster, program: program),
      data: sourceBytes, photo: photo, identity: .init(issuer: photo.reference.issuer, revision: UUID()))
    let input = try #require(prepared)
    let asset = try #require(input.assets.first { $0.descriptor.asset == input.record.raster })
    let original = asset.bytes
    #expect(asset.descriptor.asset.encoding == "array-float64")
    let png = try DrawingLibraryThumbnail.displayPixels(asset)
    let encoded = try #require(CGImageSourceCreateWithData(png as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(encoded, 0, nil))
    #expect(image.width == 2 && image.height == 2)
    var pixels = [UInt8](repeating: 0, count: 4)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try #require(CGContext(data: buffer.baseAddress, width: 2, height: 2, bitsPerComponent: 8,
        bytesPerRow: 2, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
      context.interpolationQuality = .none; context.draw(image, in: CGRect(x: 0, y: 0, width: 2, height: 2))
    }
    #expect(pixels.min() == 0 && pixels.max() == 255)
    #expect(Set(pixels).count == 4)
    #expect(asset.bytes == original && asset.descriptor.asset.object == .hash(original))
  }

  @Test("Unsupported array semantics and invalid normalized samples never become a misleading raster", arguments: ["nonfinite", "range", "shape", "units", "byteOrder", "layout"])
  func rejectInvalidLuminance(kind: String) throws {
    var values = [0.0, 0.25, 0.75, 1.0]
    if kind == "nonfinite" { values[1] = .nan }
    if kind == "range" { values[1] = 1.25 }
    var bytes = Data()
    for value in values { var bits = value.bitPattern.littleEndian; withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) } }
    let layout = try ExchangeArrayLayout(shape: kind == "shape" ? [1, 4] : [2, 2], dtype: "float64",
      layout: kind == "layout" ? "column-major" : "row-major", byteOrder: kind == "byteOrder" ? "big" : "little",
      units: kind == "units" ? "unqualified" : "normalized-luminance")
    let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/octet-stream", encoding: "array-float64")
    let image = try DrawingImageAsset(descriptor: .init(asset: asset, dimensions: .init(width: 2, height: 2), arrayLayout: layout), bytes: bytes)
    #expect(throws: (any Error).self) { try DrawingLibraryThumbnail.displayPixels(image) }
  }
}
