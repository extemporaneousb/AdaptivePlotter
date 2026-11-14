import Foundation

/// Syntax proofs for one admission with a fixed verified resolver. Callers must
/// still read and verify the exact digest before every use, retaining their byte
/// budgets and mutable-file checks. Keep only successful digests, not raster JSON.
final class ExchangeJSONProofCache {
  private var validated = Set<ExchangeDigest>()

  func validate(digest: ExchangeDigest, bytes: Data) throws {
    guard !validated.contains(digest) else { return }
    _ = try ExchangeJSON.validate(bytes)
    validated.insert(digest)
  }
}

public struct ExchangePhotoRecord: Sendable {
  public let originalJSON: Data
  public let reference: PhotoRef
  public let original: ExchangeAsset
  public let width: Int
  public let height: Int
  public let supportedSemantics: Bool
}
public struct ExchangeImageInputRecord: Sendable {
  public let originalJSON: Data
  public let reference: ImageInputRef
  public let photo: PhotoRef
  public let raster: ExchangeAsset
  public let mask: ExchangeAsset?
  public let sourceToInput: ExchangeTransform
  public let inputToField: ExchangeTransform
  public let supportedSemantics: Bool
}
public enum DrawingImageAdmission {
  public static func photo(_ expected: PhotoRef, objects: [ExchangeDigest: Data], supportedFeatures: Set<String> = [], assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]) throws -> ExchangePhotoRecord {
    try photo(expected, objects: .dictionary(objects), supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors)
  }
  public static func photo(_ expected: PhotoRef, files: VerifiedExchangeFiles, supportedFeatures: Set<String> = [], assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]) throws -> ExchangePhotoRecord {
    try photo(expected, objects: .files(files, budget: .init(maximum: files.limits.maximumMaterializedBytes)), supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors)
  }
  public static func input(_ expected: ImageInputRef, objects: [ExchangeDigest: Data], supportedFeatures: Set<String> = [], assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]) throws -> ExchangeImageInputRecord {
    try input(expected, objects: .dictionary(objects), supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors)
  }
  public static func input(_ expected: ImageInputRef, files: VerifiedExchangeFiles, supportedFeatures: Set<String> = [], assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]) throws -> ExchangeImageInputRecord {
    try input(expected, objects: .files(files, budget: .init(maximum: files.limits.maximumMaterializedBytes)), supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors)
  }
  static func bytes(_ digest: ExchangeDigest, in objects: ExchangeObjectResolver) throws -> Data { try objects.bytes(digest) }
  static func decode<T: Decodable>(_ value: Any?, as type: T.Type) throws -> T {
    guard let value else { throw DrawingExchangeError.malformed("Missing field") }
    return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed))
  }
  static func dimensions(_ value: Any?) throws -> (Int, Int) {
    struct Dimensions: Decodable { let width: Int; let height: Int }
    let d = try decode(value, as: Dimensions.self)
    let width = d.width, height = d.height
    guard width > 0, height > 0, width <= DrawingArtifactLimits.maximumImageDimension,
      height <= DrawingArtifactLimits.maximumImageDimension, width <= DrawingArtifactLimits.maximumImagePixels / height else { throw DrawingExchangeError.limit("Image dimensions") }
    return (width, height)
  }
  /// Unknown encodings remain preservable. Recognized raw encodings require complete checked layout.
  static func validateImageAsset(_ raw: Any?, objects: ExchangeObjectResolver, descriptors: [ExchangeDigest: ExchangeAssetDescriptor], dimensions expected: (Int, Int)? = nil) throws -> (ExchangeAsset, Bool) {
    let descriptor = try decode(raw, as: ExchangeAsset.self)
    try objects.validate(descriptor)
    if let object = raw as? [String: Any] {
      for key in ["dimensions", "orientation", "colorSpace", "containerType", "pixelLayout", "arrayLayout", "decodedDigest"] where object[key] is NSNull { throw DrawingExchangeError.malformed("Null descriptor field") }
    }
    let inline = try decode(raw, as: ExchangeAssetDescriptor.self)
    let indexed = descriptors[descriptor.object]
    if let indexed, indexed.asset != descriptor { throw DrawingExchangeError.digestMismatch("Index/reference asset descriptor") }
    if let left = inline.pixelLayout, let right = indexed?.pixelLayout, left != right { throw DrawingExchangeError.malformed("Conflicting pixel layouts") }
    if let left = inline.arrayLayout, let right = indexed?.arrayLayout, left != right { throw DrawingExchangeError.malformed("Conflicting array layouts") }
    if let left = inline.dimensions, let right = indexed?.dimensions, left != right { throw DrawingExchangeError.malformed("Conflicting asset dimensions") }
    if let dimensions = inline.dimensions ?? indexed?.dimensions {
      guard dimensions.width > 0, dimensions.height > 0,
        dimensions.width <= DrawingArtifactLimits.maximumImageDimension, dimensions.height <= DrawingArtifactLimits.maximumImageDimension,
        dimensions.width <= DrawingArtifactLimits.maximumImagePixels / dimensions.height else { throw DrawingExchangeError.limit("Descriptor dimensions") }
      if let expected, dimensions.width != expected.0 || dimensions.height != expected.1 { throw DrawingExchangeError.malformed("Descriptor dimensions disagree") }
    }
    if let left = inline.orientation, let right = indexed?.orientation, left != right { throw DrawingExchangeError.malformed("Conflicting orientation") }
    if let left = inline.colorSpace, let right = indexed?.colorSpace, left != right { throw DrawingExchangeError.malformed("Conflicting color space") }
    if let left = inline.containerType, let right = indexed?.containerType, left != right { throw DrawingExchangeError.malformed("Conflicting container type") }
    if let left = inline.decodedDigest, let right = indexed?.decodedDigest, left != right { throw DrawingExchangeError.malformed("Conflicting decoded digest") }
    let pixelLayout = inline.pixelLayout ?? indexed?.pixelLayout
    let arrayLayout = inline.arrayLayout ?? indexed?.arrayLayout
    if let pixelLayout { _ = try pixelLayout.requiredBytes() }
    if let arrayLayout { _ = try arrayLayout.elementCount() }
    if case .files(let files, _) = objects {
      let merged = ExchangeAssetDescriptor(asset: descriptor, dimensions: inline.dimensions ?? indexed?.dimensions ?? expected.map { ExchangeDimensions(width: $0.0, height: $0.1) },
        pixelLayout: pixelLayout, arrayLayout: arrayLayout,
        orientation: inline.orientation ?? indexed?.orientation, colorSpace: inline.colorSpace ?? indexed?.colorSpace,
        containerType: inline.containerType ?? indexed?.containerType, decodedDigest: inline.decodedDigest ?? indexed?.decodedDigest)
      if let expected {
        if let d = merged.dimensions, d.width != expected.0 || d.height != expected.1 { throw DrawingExchangeError.malformed("Image dimensions") }
        if let l = pixelLayout, l.width != expected.0 || l.height != expected.1 { throw DrawingExchangeError.malformed("Raw dimensions") }
      }
      return (descriptor, try files.validateAsset(merged).isSupported)
    }
    let data = try objects.bytes(descriptor.object, maximum: DrawingArtifactLimits.sourceBytes)
    // Recognized aliases specify interleaved unsigned 8-bit components in this exact order.
    let knownRaw: [String: (format: String, channels: [String])] = [
      "raw-gray8": ("gray", ["gray"]), "raw-rgb8": ("rgb", ["red", "green", "blue"]),
      "raw-rgba8": ("rgba", ["red", "green", "blue", "alpha"]),
      "raw-bgra8": ("bgra", ["blue", "green", "red", "alpha"]),
    ]
    if descriptor.encoding.hasPrefix("raw-") {
      guard let layout = pixelLayout else { throw DrawingExchangeError.malformed("Raw asset lacks pixelLayout") }
      try layout.validate(data)
      if let expected, (layout.width != expected.0 || layout.height != expected.1) { throw DrawingExchangeError.malformed("Raw dimensions disagree with declared image") }
      if let known = knownRaw[descriptor.encoding] {
        guard layout.pixelFormat == known.format, layout.channelOrder == known.channels,
          layout.componentType == "uint8", layout.bitDepth == 8 else { throw DrawingExchangeError.malformed("Raw encoding/layout disagreement") }
      }
      return (descriptor, knownRaw[descriptor.encoding] != nil && layout.supportedSemantics)
    }
    if descriptor.encoding.hasPrefix("array-") {
      guard let arrayLayout else { throw DrawingExchangeError.malformed("Array asset lacks arrayLayout") }
      return (descriptor, try arrayLayout.validate(data))
    }
    // Encoded image header/decode/expansion proof belongs to the carrier/import owner (DX-03).
    return (descriptor, false)
  }
  static func features(_ object: [String: Any]) throws -> [String] {
    guard let features = object["requiredFeatures"] as? [String], Set(features).count == features.count,
      features.allSatisfy(exchangeNamespacedID) else { throw DrawingExchangeError.malformed("Required features") }
    return features
  }
  static func photo(_ expected: PhotoRef, objects: ExchangeObjectResolver, supportedFeatures: Set<String>, assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor]) throws -> ExchangePhotoRecord {
    let data = try bytes(expected.digest, in: objects), json = try ExchangeJSON.validate(data)
    guard let profile = json["profile"] as? String, exchangeNamespacedID(profile) else { throw DrawingExchangeError.malformed("Photo profile") }
    guard profile == "adaptiveplotter.photo/1" else { throw DrawingExchangeError.unsupportedProfile(profile) }
    let identity = try decode(json["ref"], as: ExchangeIdentity.self)
    guard identity == expected.identity else { throw DrawingExchangeError.digestMismatch("Photo identity") }
    let declaredFeatures = try features(json)
    let (width, height) = try dimensions(json["dimensions"])
    let (asset, encodingSupported) = try validateImageAsset(json["original"], objects: objects, descriptors: assetDescriptors, dimensions: (width, height))
    for key in ["acquired", "imported"] {
      guard let date = json[key] as? [String: Any], let state = date["state"] as? String,
        let provenance = date["provenance"] as? String, !provenance.isEmpty else { throw DrawingExchangeError.malformed("Dated fact") }
      switch state {
      case "known":
        _ = try decode(date["time"], as: ExchangeTimestamp.self)
      case "unknown": guard date["time"] == nil else { throw DrawingExchangeError.malformed("Unknown date has time") }
      default: throw DrawingExchangeError.malformed("Dated fact state")
      }
    }
    if let capture = json["captureFacts"] {
      let descriptor = try decode(capture, as: ExchangeAsset.self); try objects.validate(descriptor)
    }
    return .init(originalJSON: data, reference: expected, original: asset, width: width, height: height,
      supportedSemantics: declaredFeatures.allSatisfy(supportedFeatures.subtracting(ExchangeRankingCapsule.localFeatures).contains) && encodingSupported)
  }
  static func input(_ expected: ImageInputRef, objects: ExchangeObjectResolver, supportedFeatures: Set<String>, assetDescriptors: [ExchangeDigest: ExchangeAssetDescriptor], proofCache: ExchangeJSONProofCache? = nil) throws -> ExchangeImageInputRecord {
    let data = try bytes(expected.digest, in: objects), json = try ExchangeJSON.validate(data)
    guard let profile = json["profile"] as? String, exchangeNamespacedID(profile) else { throw DrawingExchangeError.malformed("Input profile") }
    guard profile == "adaptiveplotter.image-input/1" else { throw DrawingExchangeError.unsupportedProfile(profile) }
    let identity = try decode(json["ref"], as: ExchangeIdentity.self)
    guard identity == expected.identity else { throw DrawingExchangeError.digestMismatch("Input identity") }
    var supported = try features(json).allSatisfy(supportedFeatures.subtracting(ExchangeRankingCapsule.localFeatures).contains)
    let photoRef = try decode(json["photo"], as: PhotoRef.self)
    do {
      let source = try photo(photoRef, objects: objects, supportedFeatures: supportedFeatures, assetDescriptors: assetDescriptors)
      supported = supported && source.supportedSemantics
    } catch DrawingExchangeError.unsupportedProfile {
      // The Photo is opaque, but every known claim in this ImageInput must still close.
      supported = false
    }
    guard let basis = json["pixelBasis"] as? [String: Any], let orientation = basis["orientation"] as? String,
      !orientation.isEmpty, basis["origin"] as? String == "top-left", basis["xAxis"] as? String == "right",
      basis["yAxis"] as? String == "down", basis["pixelEdges"] as? String == "integer",
      basis["pixelCenters"] as? String == "half-integer" else { throw DrawingExchangeError.malformed("Pixel basis") }
    let basisDimensions = try dimensions(basis["dimensions"])
    if !["up", "up-mirrored", "down", "down-mirrored", "left", "left-mirrored", "right", "right-mirrored"].contains(orientation) { supported = false }
    let sourceToInput = try decode(json["sourceToInput"], as: ExchangeTransform.self)
    let inputToField = try decode(json["inputToField"], as: ExchangeTransform.self)
    let (raster, rasterSupported) = try validateImageAsset(json["raster"], objects: objects, descriptors: assetDescriptors, dimensions: basisDimensions)
    supported = supported && rasterSupported
    guard let declaration = json["mask"] as? [String: Any], let state = declaration["state"] as? String else { throw DrawingExchangeError.malformed("Mask declaration") }
    let mask: ExchangeAsset?
    switch state {
    case "none": guard Set(declaration.keys) == ["state"] else { throw DrawingExchangeError.malformed("Mask none declaration") }; mask = nil
    case "present":
      guard Set(declaration.keys) == ["state", "asset"] else { throw DrawingExchangeError.malformed("Mask present declaration") }
      let (descriptor, maskSupported) = try validateImageAsset(declaration["asset"], objects: objects, descriptors: assetDescriptors, dimensions: basisDimensions)
      mask = descriptor; supported = supported && maskSupported
    default: throw DrawingExchangeError.malformed("Mask state")
    }
    guard let operations = json["operations"] as? [[String: Any]], !operations.isEmpty, operations.count <= 1024 else { throw DrawingExchangeError.limit("Preparation operations") }
    var needsMask = false
    for operation in operations {
      guard let kind = operation["kind"] as? String else { throw DrawingExchangeError.malformed("Operation kind") }
      if !["identity", "crop", "rotate", "scale", "mask"].contains(kind) { supported = false }
      if kind == "mask" { needsMask = true }
      let parameters = try decode(operation["parameters"], as: ExchangeAsset.self)
      try objects.validate(parameters)
    }
    guard !needsMask || mask != nil else { throw DrawingExchangeError.missingAsset("Declared mask operation has no mask") }
    guard let preparation = json["preparation"] as? [String: Any],
      let producerID = preparation["id"] as? String, exchangeNamespacedID(producerID),
      let version = preparation["version"] as? String, !version.isEmpty else { throw DrawingExchangeError.malformed("Preparation producer") }
    let receipt = try decode(preparation["record"], as: ExchangeDigest.self)
    let receiptBytes = try bytes(receipt, in: objects)
    if let proofCache { try proofCache.validate(digest: receipt, bytes: receiptBytes) }
    else { _ = try ExchangeJSON.validate(receiptBytes) }
    return .init(originalJSON: data, reference: expected, photo: photoRef, raster: raster, mask: mask,
      sourceToInput: sourceToInput, inputToField: inputToField, supportedSemantics: supported)
  }
}
