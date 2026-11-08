import Foundation
import ImageIO
import PortraitCore
import PlotterModel

/// Header facts and preparation facts supplied by the actual image producer.
package enum PortraitDrawingImages {
  package struct Encoded: Sendable { package let asset: DrawingImageAsset; package let width: Int; package let height: Int; package let orientation: Int; package var mediaType: String { asset.descriptor.asset.mediaType } }
  package static func sourceAsset(_ data: Data) throws -> Encoded {
    guard !data.isEmpty, data.count <= DrawingArtifactLimits.sourceBytes,
      let image = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      CGImageSourceGetCount(image) == 1,
      let type = CGImageSourceGetType(image) as String?, ["public.png", "public.jpeg"].contains(type),
      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= DrawingArtifactLimits.maximumImageDimension,
      height <= DrawingArtifactLimits.maximumImageDimension, width <= DrawingArtifactLimits.maximumImagePixels / height else {
      throw DrawingExchangeError.malformed("Choose a bounded PNG or JPEG photograph.")
    }
    let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
    guard (1...8).contains(orientation) else { throw DrawingExchangeError.malformed("Image orientation") }
    let names = ["up", "up-mirrored", "down", "down-mirrored", "left-mirrored", "right", "right-mirrored", "left"]
    let asset = try ExchangeAsset(bytes: data, mediaType: type == "public.png" ? "image/png" : "image/jpeg", encoding: type == "public.png" ? "png" : "jpeg")
    return Encoded(asset: try .init(descriptor: .init(asset: asset, dimensions: .init(width: width, height: height), orientation: names[orientation - 1], containerType: type), bytes: data), width: width, height: height, orientation: orientation)
  }
  package static func photo(data: Data, issuer: UUID, captureID: UUID, capturedAt: Date?, importedAt: Date,
    facts: Data? = nil) throws -> FrozenPhotoRecord {
    let image = try sourceAsset(data)
    let acquired: DrawingImageDatedFact = try capturedAt.map { .known(try ExchangeTimestamp(wallTime: ISO8601DateFormatter().string(from: $0)), provenance: "owning-camera-capture") } ?? .unknown(provenance: "import-has-no-acquisition-time")
    return try DrawingImageRecords.photo(identity: .init(issuer: issuer, revision: captureID), original: image.asset,
      width: image.width, height: image.height, acquired: acquired,
      imported: .known(ExchangeTimestamp(wallTime: ISO8601DateFormatter().string(from: importedAt)), provenance: "Flow-source-import"), captureFactsJSON: facts)
  }
  package static func input(result: PortraitRenderResult, data: Data, photo: FrozenPhotoRecord, identity: ExchangeIdentity) throws -> FrozenImageInputRecord? {
    let raster = result.raster
    let source = try sourceAsset(data)
    guard source.asset.descriptor.asset.object == photo.record.original.object,
      source.asset.descriptor.asset.byteLength == photo.record.original.byteLength,
      source.width == photo.record.width, source.height == photo.record.height else {
      throw DrawingExchangeError.digestMismatch("Prepared source does not match exact Photo")
    }
    guard let geometry = raster.analysisGeometry else { return nil }
    try geometry.validate(width: raster.width, height: raster.height)
    let w = Double(source.width), h = Double(source.height)
    let orientation: [Double]
    switch source.orientation {
    case 1: orientation = [1,0,0,0,1,0,0,0,1]
    case 2: orientation = [-1,0,w,0,1,0,0,0,1]
    case 3: orientation = [-1,0,w,0,-1,h,0,0,1]
    case 4: orientation = [1,0,0,0,-1,h,0,0,1]
    case 5: orientation = [0,1,0,1,0,0,0,0,1]
    case 6: orientation = [0,-1,h,1,0,0,0,0,1]
    case 7: orientation = [0,-1,h,-1,0,w,0,0,1]
    default: orientation = [0,1,0,-1,0,w,0,0,1]
    }
    let orientedWidth = source.orientation >= 5 ? h : w, orientedHeight = source.orientation >= 5 ? w : h
    let sx = Double(geometry.decodedWidth) / orientedWidth * Double(raster.width) / geometry.crop.width
    let sy = Double(geometry.decodedHeight) / orientedHeight * Double(raster.height) / geometry.crop.height
    let tx = -geometry.crop.x * Double(raster.width) / geometry.crop.width
    let ty = -geometry.crop.y * Double(raster.height) / geometry.crop.height
    let sourceToInput = try ExchangeTransform([sx*orientation[0],sx*orientation[1],sx*orientation[2]+tx,sy*orientation[3],sy*orientation[4],sy*orientation[5]+ty,0,0,1])
    let inputToField = try ExchangeTransform([result.program.fieldExtent.width / Double(raster.width),0,0,0,-result.program.fieldExtent.height / Double(raster.height),result.program.fieldExtent.height,0,0,1])
    func array(_ values: [Double], units: String) throws -> DrawingImageAsset {
      var bytes = Data(); bytes.reserveCapacity(values.count * 8)
      for value in values { var bits = value.bitPattern.littleEndian; withUnsafeBytes(of: &bits) { bytes.append(contentsOf: $0) } }
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/octet-stream", encoding: "array-float64")
      let layout = try ExchangeArrayLayout(shape: [raster.height, raster.width], dtype: "float64", layout: "row-major", byteOrder: "little", units: units)
      return try .init(descriptor: .init(asset: asset, dimensions: .init(width: raster.width, height: raster.height), arrayLayout: layout), bytes: bytes)
    }
    let pixels = try array(raster.luminance, units: "normalized-luminance")
    let mask: DrawingInputMask
    if let alpha = raster.personMask?.alpha { mask = .present(try array(alpha, units: "normalized-alpha")) }
    else { mask = .none }
    let evidence = try DrawingArtifactCoding.encoder().encode(raster)
    let preparation = try DrawingProducerReceipt(id: "adaptiveplotter.portrait-preparation", version: geometry.preprocessingRevision, recordJSON: evidence)
    var operations = [try DrawingImageOperation(kind: "crop", parametersJSON: DrawingArtifactCoding.encoder().encode(geometry)),
      try DrawingImageOperation(kind: "scale", parametersJSON: DrawingArtifactCoding.encoder().encode(geometry))]
    if source.orientation != 1 {
      operations.append(try DrawingImageOperation(kind: "rotate", parametersJSON: JSONSerialization.data(withJSONObject: ["exifOrientation": source.orientation], options: [.sortedKeys])))
    }
    if geometry.contrastApplied { operations.append(try DrawingImageOperation(kind: "contrast", parametersJSON: DrawingArtifactCoding.encoder().encode(geometry))) }
    if case .present = mask { operations.append(try DrawingImageOperation(kind: "mask", parametersJSON: DrawingArtifactCoding.encoder().encode(raster.personMask))) }
    return try DrawingImageRecords.input(identity: identity, photo: photo, raster: pixels, width: raster.width, height: raster.height,
      orientation: "up", sourceToInput: sourceToInput, inputToField: inputToField, mask: mask, operations: operations, preparation: preparation)
  }
}
