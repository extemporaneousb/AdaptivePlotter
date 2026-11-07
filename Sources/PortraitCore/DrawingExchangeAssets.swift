import Foundation

public struct ExchangeAsset: Hashable, Codable, Sendable {
  public let object: ExchangeDigest
  public let byteLength: UInt64
  public let mediaType: String
  public let encoding: String
  public init(bytes: Data, mediaType: String, encoding: String) throws {
    guard exchangeMIMEType(mediaType), !encoding.isEmpty else { throw DrawingExchangeError.malformed("Asset type") }
    object = .hash(bytes); byteLength = UInt64(bytes.count); self.mediaType = mediaType; self.encoding = encoding
  }
  enum CodingKeys: String, CodingKey { case object, byteLength, mediaType, encoding }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    object = try c.decode(ExchangeDigest.self, forKey: .object)
    byteLength = try c.decode(UInt64.self, forKey: .byteLength)
    mediaType = try c.decode(String.self, forKey: .mediaType)
    encoding = try c.decode(String.self, forKey: .encoding)
    guard byteLength <= 9_007_199_254_740_991, exchangeMIMEType(mediaType), !encoding.isEmpty else {
      throw DrawingExchangeError.malformed("Asset reference structure")
    }
  }
  public func validate(_ bytes: Data, maximumBytes: Int = DrawingTransferLimits.sourceBytes) throws {
    guard byteLength <= UInt64(maximumBytes), bytes.count == byteLength else { throw DrawingExchangeError.limit("Asset length") }
    guard object == .hash(bytes) else { throw DrawingExchangeError.digestMismatch("Asset") }
    guard exchangeMIMEType(mediaType), !encoding.isEmpty else { throw DrawingExchangeError.malformed("Asset type") }
  }
}
/// Normative RawPixelLayout. Row stride includes padding; no allocation occurs here.
public struct ExchangeRasterLayout: Hashable, Codable, Sendable {
  public let width: Int
  public let height: Int
  public let pixelFormat: String
  public let componentType: String
  public let bitDepth: Int
  public let channelOrder: [String]
  public let rowStride: Int
  public let byteOrder: String
  public let orientation: String
  public let colorInterpretation: String
  public init(width: Int, height: Int, pixelFormat: String, componentType: String, bitDepth: Int,
    channelOrder: [String], rowStride: Int, byteOrder: String, orientation: String, colorInterpretation: String) throws {
    self.width = width; self.height = height; self.pixelFormat = pixelFormat; self.componentType = componentType
    self.bitDepth = bitDepth; self.channelOrder = channelOrder; self.rowStride = rowStride; self.byteOrder = byteOrder
    self.orientation = orientation; self.colorInterpretation = colorInterpretation
    _ = try requiredBytes()
  }
  /// Convenience for known interleaved 8-bit layouts; wire fields remain the normative profile.
  public init(width: Int, height: Int, bytesPerPixel: Int, rowStride: Int) throws {
    let channels = [1: ["gray"], 3: ["red", "green", "blue"], 4: ["red", "green", "blue", "alpha"]]
    guard let order = channels[bytesPerPixel] else { throw DrawingExchangeError.malformed("Unknown pixel format") }
    try self.init(width: width, height: height, pixelFormat: bytesPerPixel == 1 ? "gray" : bytesPerPixel == 3 ? "rgb" : "rgba",
      componentType: "uint8", bitDepth: 8, channelOrder: order, rowStride: rowStride, byteOrder: "not-applicable", orientation: "up", colorInterpretation: bytesPerPixel == 1 ? "linear-gray" : "sRGB")
  }
  enum CodingKeys: String, CodingKey {
    case width, height, pixelFormat, componentType, bitDepth, channelOrder, rowStride, byteOrder, orientation, colorInterpretation
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(width: c.decode(Int.self, forKey: .width), height: c.decode(Int.self, forKey: .height),
      pixelFormat: c.decode(String.self, forKey: .pixelFormat), componentType: c.decode(String.self, forKey: .componentType),
      bitDepth: c.decode(Int.self, forKey: .bitDepth), channelOrder: c.decode([String].self, forKey: .channelOrder),
      rowStride: c.decode(Int.self, forKey: .rowStride), byteOrder: c.decode(String.self, forKey: .byteOrder),
      orientation: c.decode(String.self, forKey: .orientation), colorInterpretation: c.decode(String.self, forKey: .colorInterpretation))
  }
  public func requiredBytes() throws -> Int {
    guard width > 0, height > 0, width <= DrawingTransferLimits.maximumImageDimension,
      height <= DrawingTransferLimits.maximumImageDimension, width <= DrawingTransferLimits.maximumImagePixels / height,
      !pixelFormat.isEmpty, !componentType.isEmpty, !colorInterpretation.isEmpty, !orientation.isEmpty,
      !channelOrder.isEmpty, channelOrder.count <= 16, channelOrder.allSatisfy({ !$0.isEmpty }),
      bitDepth > 0, bitDepth <= 64, bitDepth <= Int.max / channelOrder.count,
      ["little", "big", "not-applicable"].contains(byteOrder) else { throw DrawingExchangeError.limit("Raw pixel layout") }
    let bitsPerPixel = bitDepth * channelOrder.count
    guard width <= (Int.max - 7) / bitsPerPixel else { throw DrawingExchangeError.limit("Raw row overflow") }
    let minimumRowBytes = (width * bitsPerPixel + 7) / 8
    guard rowStride >= minimumRowBytes, rowStride <= 9_007_199_254_740_991, rowStride <= Int.max / height else { throw DrawingExchangeError.limit("Raw stride overflow") }
    return rowStride * height
  }
  public var bytesPerPixel: Int { (bitDepth * channelOrder.count + 7) / 8 }
  public var supportedSemantics: Bool {
    componentType == "uint8" && bitDepth == 8
      && ["gray": ["gray"], "rgb": ["red", "green", "blue"], "rgba": ["red", "green", "blue", "alpha"], "bgra": ["blue", "green", "red", "alpha"]][pixelFormat] == channelOrder
      && ["up", "down", "left", "right", "up-mirrored", "down-mirrored", "left-mirrored", "right-mirrored"].contains(orientation)
      && ["linear-gray", "sRGB"].contains(colorInterpretation)
  }
  public func validate(_ bytes: Data) throws {
    guard bytes.count == (try requiredBytes()) else { throw DrawingExchangeError.malformed("Raw raster byte count") }
  }
}
public typealias ExchangePixelLayout = ExchangeRasterLayout
public struct ExchangeArrayLayout: Hashable, Codable, Sendable {
  public let shape: [Int]
  public let dtype: String
  public let layout: String
  public let byteOrder: String
  public let units: String
  public init(shape: [Int], dtype: String, layout: String, byteOrder: String, units: String) throws {
    self.shape = shape; self.dtype = dtype; self.layout = layout; self.byteOrder = byteOrder; self.units = units
    _ = try elementCount()
  }
  enum CodingKeys: String, CodingKey { case shape, dtype, layout, byteOrder, units }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(shape: c.decode([Int].self, forKey: .shape), dtype: c.decode(String.self, forKey: .dtype),
      layout: c.decode(String.self, forKey: .layout), byteOrder: c.decode(String.self, forKey: .byteOrder), units: c.decode(String.self, forKey: .units))
  }
  public func elementCount() throws -> Int {
    guard !shape.isEmpty, shape.count <= 16, !dtype.isEmpty, !units.isEmpty,
      ["row-major", "column-major"].contains(layout), ["little", "big", "not-applicable"].contains(byteOrder) else { throw DrawingExchangeError.malformed("Array layout") }
    var count = 1
    for size in shape {
      guard size > 0, size <= 9_007_199_254_740_991, count <= Int.max / size else { throw DrawingExchangeError.limit("Array shape overflow") }
      count *= size
    }
    return count
  }
  public func requiredBytes() throws -> Int? {
    let count = try elementCount()
    let sizes = ["uint8":1, "int8":1, "uint16":2, "int16":2, "float16":2, "uint32":4, "int32":4, "float32":4, "uint64":8, "int64":8, "float64":8]
    guard let stride = sizes[dtype] else { return nil }
    guard count <= Int.max / stride else { throw DrawingExchangeError.limit("Array byte overflow") }
    return count * stride
  }
  public func validate(_ bytes: Data) throws -> Bool {
    guard let length = try requiredBytes() else { return false }
    guard length == bytes.count else { throw DrawingExchangeError.malformed("Array byte count") }
    return true
  }
}
public struct ExchangeDimensions: Hashable, Codable, Sendable {
  public let width: Int
  public let height: Int
  public init(width: Int, height: Int) { self.width = width; self.height = height }
}
/// Flattened AssetDescriptor, usable directly from ExchangeIndex.assets.
public struct ExchangeAssetDescriptor: Codable, Hashable, Sendable {
  public let asset: ExchangeAsset
  public let dimensions: ExchangeDimensions?
  public let pixelLayout: ExchangePixelLayout?
  public let arrayLayout: ExchangeArrayLayout?
  public init(asset: ExchangeAsset, dimensions: ExchangeDimensions? = nil,
    pixelLayout: ExchangePixelLayout? = nil, arrayLayout: ExchangeArrayLayout? = nil) {
    self.asset = asset; self.dimensions = dimensions; self.pixelLayout = pixelLayout; self.arrayLayout = arrayLayout
  }
  enum CodingKeys: String, CodingKey { case dimensions, pixelLayout, arrayLayout }
  public init(from decoder: Decoder) throws {
    asset = try ExchangeAsset(from: decoder)
    let c = try decoder.container(keyedBy: CodingKeys.self)
    dimensions = c.contains(.dimensions) ? try c.decode(ExchangeDimensions.self, forKey: .dimensions) : nil
    pixelLayout = c.contains(.pixelLayout) ? try c.decode(ExchangePixelLayout.self, forKey: .pixelLayout) : nil
    arrayLayout = c.contains(.arrayLayout) ? try c.decode(ExchangeArrayLayout.self, forKey: .arrayLayout) : nil
  }
  public func encode(to encoder: Encoder) throws {
    try asset.encode(to: encoder)
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(dimensions, forKey: .dimensions); try c.encodeIfPresent(pixelLayout, forKey: .pixelLayout)
    try c.encodeIfPresent(arrayLayout, forKey: .arrayLayout)
  }
}
public struct ExchangeTransform: Hashable, Codable, Sendable {
  public let values: [Double]
  public init(_ values: [Double]) throws {
    guard values.count == 9, values.allSatisfy(\.isFinite) else { throw DrawingExchangeError.malformed("Transform requires nine finite values") }
    self.values = values
  }
  public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode([Double].self)) }
  public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(values) }
}
