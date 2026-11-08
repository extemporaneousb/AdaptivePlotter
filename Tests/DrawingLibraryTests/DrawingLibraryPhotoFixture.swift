import Foundation
import CoreGraphics
import ImageIO
import DrawingLibrary
import PortraitCore
import PlotterModel

/// Explicit current-format synthetic pixels and acquisition facts. The fixture
/// asserts integrity/source closure, never native rendering or physical evidence.
struct DrawingLibraryPhotoFixture {
  enum Encoding: String, CaseIterable, Sendable { case raw, png, jpeg }
  let photo: FrozenPhotoRecord
  let input: FrozenImageInputRecord

  static func json(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
  }
  static func wire<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value))
  }
  static func encoded(_ encoding: Encoding) throws -> Data {
    let pixels = Data([0, 64, 128, 255])
    if encoding == .raw { return pixels }
    guard let provider = CGDataProvider(data: pixels as CFData),
      let image = CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 2,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
      throw DrawingExchangeError.malformed("Synthetic grayscale image")
    }
    let bytes = NSMutableData()
    let type = encoding == .png ? "public.png" : "public.jpeg"
    guard let destination = CGImageDestinationCreateWithData(bytes, type as CFString, 1, nil) else {
      throw DrawingExchangeError.malformed("Synthetic encoded destination")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingExchangeError.malformed("Synthetic encoded image") }
    return bytes as Data
  }
  init(encoding: Encoding = .raw,
       acquired: DrawingImageDatedFact = .unknown(provenance: "Synthetic acquisition unknown"),
       imported: DrawingImageDatedFact = .unknown(provenance: "Synthetic import unknown"),
       aliases: Bool = false) throws {
    let pixels = try DrawingImageAsset.gray8(Data([0, 64, 128, 255]), width: 2, height: 2)
    let original: DrawingImageAsset
    if encoding == .raw { original = pixels }
    else {
      let bytes = try Self.encoded(encoding)
      let asset = try ExchangeAsset(bytes: bytes, mediaType: encoding == .png ? "image/png" : "image/jpeg", encoding: encoding == .png ? "png" : "jpeg")
      original = try .init(descriptor: .init(asset: asset, dimensions: .init(width: 2, height: 2)), bytes: bytes)
    }
    let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: original, width: 2, height: 2,
      acquired: acquired, imported: imported, captureFactsJSON: Data("{\"source\":\"synthetic test pixels\"}".utf8))
    self.photo = photo
    let receipt = aliases ? photo.record.originalJSON : Data("{\"profile\":\"example.dx07-preparation/1\"}".utf8)
    let preparation = try DrawingProducerReceipt(id: "example.dx07-preparation", version: "1", recordJSON: receipt)
    let mask = try DrawingImageAsset.gray8(Data([255, 0, 255, 0]), width: 2, height: 2)
    input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: photo, raster: pixels,
      width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
      inputToField: ExchangeTransform([0.5,0,0,0,-0.5,1,0,0,1]), mask: .present(mask),
      operations: [DrawingImageOperation(kind: "identity", parametersJSON: aliases ? photo.record.originalJSON : Data("{}".utf8)),
        DrawingImageOperation(kind: "mask", parametersJSON: Data("{\"coverage\":\"alternating synthetic mask\"}".utf8))], preparation: preparation)
  }
  static func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx07-photo-" + UUID().uuidString)
  }
  func drawing(input ref: ImageInputRef? = nil) throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(UUID()))
    let program = try DrawingProgramCatalog.program(for: .line, style: style)
    return try Drawing(program: program, input: .present(ref ?? input.reference), parent: .none,
      producer: DrawingProducerReceipt(id: "example.dx07-drawing", version: "1", recordJSON: Data("{}".utf8)))
  }
  func publish(to library: DrawingLibrary) async throws {
    try await library.commitRecords([], closure: .init(input: input))
  }
  var photoPath: String {
    "data/photos/\(photo.reference.issuer.uuidString.lowercased())/\(photo.reference.revision.uuidString.lowercased())/photo.json"
  }
  var inputPath: String {
    "data/inputs/\(input.reference.issuer.uuidString.lowercased())/\(input.reference.revision.uuidString.lowercased())/input.json"
  }
  /// A source-only current Exchange, useful for opaque-feature and selected
  /// context fixtures without inventing an authored Drawing or retaining geometry.
  func packagePayload() throws -> [String: Data] {
    var files = [photoPath: photo.record.originalJSON, inputPath: input.record.originalJSON]
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    for asset in input.assets {
      let digest = asset.descriptor.asset.object
      if let prior = descriptors[digest], prior != asset.descriptor { throw DrawingExchangeError.malformed("Fixture descriptor alias conflict") }
      descriptors[digest] = asset.descriptor
      files["data/objects/sha256/" + digest.description] = asset.bytes
    }
    let index: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](), "kind": "feedback",
      "roots": [String](), "photos": try Self.wire([photo.reference]), "inputs": try Self.wire([input.reference]),
      "jobs": [String](), "attempts": [String](), "assessments": [String](),
      "assets": try Self.wire(descriptors.values.sorted { $0.asset.object.description < $1.asset.object.description }),
      "includedAsOf": "2027-01-15T08:00:00Z"]
    files["data/exchange.json"] = try Self.json(index)
    return files
  }
  enum RequiredScope: String, CaseIterable, Sendable { case index, photo, input }
  func requiring(_ scope: RequiredScope) throws -> (payload: [String: Data], photo: PhotoRef, input: ImageInputRef) {
    var files = try packagePayload()
    var index = try JSONSerialization.jsonObject(with: files["data/exchange.json"]!) as! [String: Any]
    var photoRef = photo.reference
    var inputRef = input.reference
    if scope == .index {
      index["requiredFeatures"] = ["example.dx07-required/1"]
    } else if scope == .photo {
      var object = try JSONSerialization.jsonObject(with: files[photoPath]!) as! [String: Any]
      object["requiredFeatures"] = ["example.dx07-required/1"]
      let bytes = try Self.json(object)
      files[photoPath] = bytes
      photoRef = .init(issuer: photo.reference.issuer, revision: photo.reference.revision, digest: .hash(bytes))
      var prepared = try JSONSerialization.jsonObject(with: files[inputPath]!) as! [String: Any]
      prepared["photo"] = try Self.wire(photoRef)
      let preparedBytes = try Self.json(prepared)
      files[inputPath] = preparedBytes
      inputRef = .init(issuer: input.reference.issuer, revision: input.reference.revision, digest: .hash(preparedBytes))
    } else {
      var object = try JSONSerialization.jsonObject(with: files[inputPath]!) as! [String: Any]
      object["requiredFeatures"] = ["example.dx07-required/1"]
      let bytes = try Self.json(object)
      files[inputPath] = bytes
      inputRef = .init(issuer: input.reference.issuer, revision: input.reference.revision, digest: .hash(bytes))
    }
    index["photos"] = try Self.wire([photoRef])
    index["inputs"] = try Self.wire([inputRef])
    files["data/exchange.json"] = try Self.json(index)
    return (files, photoRef, inputRef)
  }
  static func write(_ payload: [String: Data], to root: URL) throws {
    var files = payload
    files["bagit.txt"] = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    files["manifest-sha256.txt"] = Data(files.keys.filter { $0.hasPrefix("data/") }.sorted().map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    files["tagmanifest-sha256.txt"] = Data(["bagit.txt", "manifest-sha256.txt"].map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    for (path, bytes) in files {
      let target = root.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: target)
    }
  }
}

// Actual Core admission and catalog publication; source-only fixtures do not
// need an invented Drawing or a production-only import branch.
extension DrawingLibrary {
  func publishPhotoFixture(_ payload: [String: Data]) throws {
    let root = DrawingLibraryPhotoFixture.root()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source")
    try DrawingLibraryPhotoFixture.write(payload, to: source)
    let stage = root.appendingPathComponent("stage")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    let admitted = try ExchangeAdmission.validate(DrawingExchangeCarrier.stageDirectory(source, stagingParent: stage))
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    _ = try catalog.publish(admitted)
  }
}
