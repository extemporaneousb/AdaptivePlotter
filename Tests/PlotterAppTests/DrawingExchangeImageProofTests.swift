import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import PortraitCore

@Suite("DX03 image proof", .serialized)
struct DrawingExchangeImageProofTests {
  func png() throws -> Data {
    let pixels = Data([255, 0, 0, 255, 0, 255, 0, 255])
    let provider = try #require(CGDataProvider(data: pixels as CFData))
    let image = try #require(CGImage(width: 2, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination)); return output as Data
  }
  @Test func headerIsNotDecodeAndDecodeIsExplicit() throws {
    let image = try png(), asset = try ExchangeAsset(bytes: image, mediaType: "image/png", encoding: "png")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8), "data/objects/sha256/" + asset.object.description: image]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let descriptor = ExchangeAssetDescriptor(asset: asset, dimensions: .init(width: 2, height: 1))
    #expect(try staged.files.validateAsset(descriptor) == .unsupported(reason: "Encoded header verified; pixels require explicit bounded decode"))
    #expect(staged.statistics.imageDecodeCount == 0)
    #expect(try ExchangeEncodedImageProof.decode(descriptor, files: staged.files).pixels.count == 8)
    #expect(staged.statistics.imageDecodeCount == 1)
    #expect(throws: (any Error).self) { try staged.files.validateAsset(.init(asset: asset, dimensions: .init(width: 1, height: 2))) }
  }
  @Test func expectedDimensionsWithoutInlineDimensions() throws {
    let image = try png(), asset = try ExchangeAsset(bytes: image, mediaType: "image/png", encoding: "png")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8), "data/objects/sha256/" + asset.object.description: image]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(asset))
    #expect(throws: (any Error).self) { try DrawingImageAdmission.validateImageAsset(raw, objects: .files(staged.files), descriptors: [:], dimensions: (1, 2)) }
    #expect(staged.statistics.imageDecodeCount == 0)
  }
  @Test func contradictoryRawLayoutAndZeroMediaRead() throws {
    let raw = Data([0, 1, 2, 3]), asset = try ExchangeAsset(bytes: raw, mediaType: "application/octet-stream", encoding: "raw-rgba8")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8), "data/objects/sha256/" + asset.object.description: raw]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let before = staged.statistics.materializedBytesRead
    let bad = try ExchangeRasterLayout(width: 1, height: 1, pixelFormat: "rgba", componentType: "uint8", bitDepth: 8,
      channelOrder: ["blue", "green", "red", "alpha"], rowStride: 4, byteOrder: "not-applicable", orientation: "up", colorInterpretation: "sRGB")
    #expect(throws: (any Error).self) { try staged.files.validateAsset(.init(asset: asset, pixelLayout: bad)) }
    let good = try ExchangeRasterLayout(width: 1, height: 1, bytesPerPixel: 4, rowStride: 4)
    #expect(try staged.files.validateAsset(.init(asset: asset, pixelLayout: good)) == .supported)
    #expect(staged.statistics.materializedBytesRead == before)
  }
  @Test func encodedBoundsAndCorruption() throws {
    let corrupt = Data([137,80,78,71,13,10,26,10,0]), asset = try ExchangeAsset(bytes: corrupt, mediaType: "image/png", encoding: "png")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8), "data/objects/sha256/" + asset.object.description: corrupt]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    #expect(throws: (any Error).self) { try ExchangeEncodedImageProof.decode(.init(asset: asset), files: staged.files) }
    #expect(staged.statistics.imageDecodeCount == 0)
  }
  @Test func coherentlyHashedPNGWithBadCriticalCRCIsRefused() throws {
    var image = try png(), offset = 8, changed = false
    while offset + 12 <= image.count {
      let length = image[offset..<offset + 4].reduce(0) { ($0 << 8) | Int($1) }
      let kind = String(decoding: image[offset + 4..<offset + 8], as: UTF8.self)
      if kind == "IDAT" { image[offset + length + 8] ^= 1; changed = true; break }
      offset += length + 12
    }
    #expect(changed)
    let native = CGImageSourceCreateWithData(image as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
    let headerReadable = native.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) } != nil
    print("DX03 bad-IDAT-CRC ImageIO header readable: \(headerReadable); container CRC proof is separate")
    let asset = try ExchangeAsset(bytes: image, mediaType: "image/png", encoding: "png")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8), "data/objects/sha256/" + asset.object.description: image]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    #expect(throws: (any Error).self) { try staged.files.validateAsset(.init(asset: asset, dimensions: .init(width: 2, height: 1))) }
    #expect(staged.statistics.imageDecodeCount == 0)
  }

  @Test func JPEGHeaderDecodeArtifactAndTruncatedClosure() throws {
    let prepared = try png()
    let source = try #require(CGImageSourceCreateWithData(prepared as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let output = NSMutableData()
    let writer = try #require(CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    #expect(CGImageDestinationFinalize(writer))
    let jpeg = output as Data, truncated = Data(jpeg.dropLast(2))
    let original = try ExchangeAsset(bytes: jpeg, mediaType: "image/jpeg", encoding: "jpeg")
    let broken = try ExchangeAsset(bytes: truncated, mediaType: "image/jpeg", encoding: "jpeg")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8),
      "data/objects/sha256/" + original.object.description: jpeg, "data/objects/sha256/" + broken.object.description: truncated]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    #expect(!(try staged.files.validateAsset(.init(asset: original, dimensions: .init(width: 2, height: 1)))).isSupported)
    #expect(staged.statistics.imageDecodeCount == 0)
    let decoded = try ExchangeEncodedImageProof.decode(.init(asset: original), files: staged.files)
    #expect(decoded.width == 2 && decoded.height == 1 && decoded.rowStride == 8)
    #expect(decoded.channelOrder == ["red", "green", "blue", "alpha"] && decoded.byteOrder == "big" && decoded.alpha == "premultiplied")
    #expect(decoded.pixels.count == 8)
    #expect(throws: (any Error).self) { try staged.files.validateAsset(.init(asset: original, dimensions: .init(width: 1, height: 2))) }
    #expect(throws: (any Error).self) { try staged.files.validateAsset(.init(asset: broken)) }
    #expect(staged.statistics.imageDecodeCount == 1)
  }
  @Test func rawMaskLayoutRetainsPaddingWithoutMaterializingPixels() throws {
    let mask = Data([0, 255, 0, 19, 255, 0, 255, 23]), asset = try ExchangeAsset(bytes: mask, mediaType: "application/octet-stream", encoding: "raw-gray8")
    let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json": Data("{}".utf8), "data/objects/sha256/" + asset.object.description: mask]); defer { bag.dispose() }
    let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
    let layout = try ExchangeRasterLayout(width: 3, height: 2, bytesPerPixel: 1, rowStride: 4)
    let descriptor = ExchangeAssetDescriptor(asset: asset, dimensions: .init(width: 3, height: 2), pixelLayout: layout)
    let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(descriptor))
    let before = staged.statistics.materializedBytesRead
    #expect(try DrawingImageAdmission.validateImageAsset(raw, objects: .files(staged.files), descriptors: [:], dimensions: (3, 2)).1)
    #expect(staged.statistics.materializedBytesRead == before && staged.statistics.imageDecodeCount == 0)
    let invalid = try ExchangeRasterLayout(width: 3, height: 2, bytesPerPixel: 1, rowStride: 5)
    #expect(throws: (any Error).self) { try staged.files.validateAsset(.init(asset: asset, pixelLayout: invalid)) }
    #expect(try staged.files.record(asset.object, maximumBytes: 8) == mask)
  }

  @Test func opaquePhotoCannotHideKnownInputClaims() throws {
    let issuer = "550e8400-e29b-41d4-a716-446655440000", photoID = "550e8400-e29b-41d4-a716-446655440001", inputID = "550e8400-e29b-41d4-a716-446655440002"
    let photo = try JSONSerialization.data(withJSONObject: ["profile":"adaptiveplotter.photo/9", "ref":["issuer":issuer,"revision":photoID], "vendor":"opaque"])
    let pixels = Data([10, 20]), parameters = Data("{}".utf8)
    let raster = try ExchangeAsset(bytes: pixels, mediaType: "application/octet-stream", encoding: "raw-gray8")
    let parameter = try ExchangeAsset(bytes: parameters, mediaType: "application/json", encoding: "example.parameters/1")
    let layout = try ExchangeRasterLayout(width: 2, height: 1, bytesPerPixel: 1, rowStride: 2)
    let descriptor = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ExchangeAssetDescriptor(asset: raster, pixelLayout: layout)))
    let parameterObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(parameter))
    let missing: [String: Any] = ["object":String(repeating:"0",count:64),"byteLength":2,"mediaType":"application/octet-stream","encoding":"raw-gray8"]
    for changed in ["none", "raster", "mask", "preparation", "parameters"] {
      var input: [String: Any] = ["profile":"adaptiveplotter.image-input/1", "requiredFeatures":[], "ref":["issuer":issuer,"revision":inputID],
        "photo":["issuer":issuer,"revision":photoID,"digest":ExchangeDigest.hash(photo).description],
        "pixelBasis":["dimensions":["width":2,"height":1],"orientation":"up","origin":"top-left","xAxis":"right","yAxis":"down","pixelEdges":"integer","pixelCenters":"half-integer"],
        "sourceToInput":[1,0,0,0,1,0,0,0,1],"inputToField":[1,0,0,0,1,0,0,0,1],"raster":descriptor,"mask":["state":"none"],
        "operations":[["kind":"identity","parameters":parameterObject]],"preparation":["id":"example.preparation","version":"1","record":parameter.object.description]]
      switch changed {
      case "raster": input["raster"] = missing
      case "mask": input["mask"] = ["state":"present","asset":missing]
      case "preparation": input["preparation"] = ["id":"example.preparation","version":"1","record":String(repeating:"0",count:64)]
      case "parameters": input["operations"] = [["kind":"identity","parameters":missing]]
      default: break
      }
      let record = try JSONSerialization.data(withJSONObject: input)
      let reference = ImageInputRef(issuer: UUID(uuidString: issuer)!, revision: UUID(uuidString: inputID)!, digest: .hash(record))
      let bag = try DrawingExchangeCarrierTestBag(files: ["data/exchange.json":Data("{}".utf8),
        "data/photos/"+issuer+"/"+photoID+"/photo.json":photo,"data/inputs/"+issuer+"/"+inputID+"/input.json":record,
        "data/objects/sha256/"+raster.object.description:pixels,"data/objects/sha256/"+parameter.object.description:parameters])
      defer { bag.dispose() }
      let staged = try DrawingExchangeCarrier.stageDirectory(bag.source, stagingParent: bag.root)
      if changed == "none" {
        let admitted = try DrawingImageAdmission.input(reference, files: staged.files)
        #expect(!admitted.supportedSemantics && admitted.originalJSON == record)
      } else {
        #expect(throws: (any Error).self) { try DrawingImageAdmission.input(reference, files: staged.files) }
      }
    }
  }

}
