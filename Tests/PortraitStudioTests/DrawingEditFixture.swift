import Foundation
@testable import DrawingLibrary
import PlotterModel
import PortraitCore
import Testing

/// Test-local gate for the existing synchronous catalog boundary. It suspends
/// only the Library actor's publication thread; the MainActor remains runnable.
final class DrawingEditCommitGate: @unchecked Sendable {
  private let lock = NSLock()
  private let releaseSignal = DispatchSemaphore(value: 0)
  private var reached = false
  private var waiter: CheckedContinuation<Bool, Never>?
  private var armed = true
  enum Failure: Error { case timeout }
  func hold() throws {
    lock.lock()
    guard armed else { lock.unlock(); return }
    armed = false; reached = true
    let waiting = waiter; waiter = nil
    lock.unlock()
    waiting?.resume(returning: true)
    guard releaseSignal.wait(timeout: .now() + 15) == .success else { throw Failure.timeout }
  }
  func waitUntilHeld() async -> Bool {
    await withCheckedContinuation { continuation in
      lock.lock()
      if reached { lock.unlock(); continuation.resume(returning: true); return }
      waiter = continuation
      lock.unlock()
      Task.detached { [weak self] in
        try? await Task.sleep(for: .seconds(10))
        self?.finishWaiting()
      }
    }
  }
  private func finishWaiting() {
    lock.lock(); let waiting = waiter; waiter = nil; lock.unlock()
    waiting?.resume(returning: false)
  }
  func release() { releaseSignal.signal() }
}

enum DrawingEditInjectedFailure: Error { case boundary }
extension DrawingLibrary {
  func pendingEditResources() -> (count: Int, roots: [URL]) {
    (pendingRetentions.count, pendingRetentions.values.compactMap(\.temporaryRoot))
  }
  func editFault(_ boundary: LibraryExchangeCatalogBoundary?) throws {
    guard let boundary else { cachedExchangeCatalog?.injectFault = nil; return }
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == boundary { throw DrawingEditInjectedFailure.boundary } }
  }
  func editGate(_ gate: DrawingEditCommitGate) throws {
    let catalog = try commonCatalog()
    catalog.injectFault = { if $0 == .beforeSQLCommit { try gate.hold() } }
  }
}

enum DrawingEditFixture {
  static func root() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("dx08-edit-" + UUID().uuidString)
  }
  static func value() throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    let paths: [[(Double, Double)]] = [[(10,20),(30,40)],[(20,70),(40,50),(60,70)],[(70,20),(90,30)]]
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 100),
      strokes: paths.enumerated().map { index, coordinates in
        LogicalStroke(id: StrokeID(), path: try Polyline(points: coordinates.map { try Point2(x: $0.0, y: $0.1) }),
          style: style, ordering: UInt32(index))
      }, source: .init(kind: "example.dx08", sourceIdentifier: "explicit synthetic source-free membership fixture"))
    return try Drawing(program: program, input: .none, parent: .none,
      producer: DrawingProducerReceipt(id: "example.dx08", version: "1", recordJSON: Data("{}".utf8)))
  }
  static func sourceFree() async throws -> Drawing {
    let style = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID())
    return try await CatalogDrawingProducer().produce(input: .metricSquare40, settings: .init(style: style)).drawing
  }
  static func json(_ object: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
  }
  static func wire<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: DrawingArtifactCoding.encoder().encode(value))
  }
  struct Imported {
    let drawing: Drawing
    let original: FrozenDrawingRecord
    let sourceFiles: [String: Data]
    let photo: PhotoRef?
    let input: ImageInputRef?
  }
  static func imported(in library: DrawingLibrary, directory: URL, unsupportedOwn: Bool = false,
                       uncertainSource: Bool = false) async throws -> Imported {
    let base = try value()
    var assets: [ExchangeDigest: (ExchangeAssetDescriptor, Data)] = [:]
    var files: [String: Data] = [:]
    var source: SourceLink<ImageInputRef> = .none
    var photoRef: PhotoRef?
    var inputRef: ImageInputRef?
    if uncertainSource {
      let pixels = try DrawingImageAsset.gray8(Data([0,64,128,255]), width: 2, height: 2)
      let photo = try DrawingImageRecords.photo(identity: .init(issuer: UUID()), original: pixels, width: 2, height: 2,
        acquired: .unknown(provenance: "Synthetic acquisition"), imported: .unknown(provenance: "Synthetic import"))
      let mask = try DrawingImageAsset.gray8(Data([255,0,255,0]), width: 2, height: 2)
      let input = try DrawingImageRecords.input(identity: .init(issuer: UUID()), photo: photo, raster: pixels,
        width: 2, height: 2, orientation: "up", sourceToInput: ExchangeTransform([1,0,0,0,1,0,0,0,1]),
        inputToField: ExchangeTransform([0.5,0,0,0,-0.5,1,0,0,1]), mask: .present(mask),
        operations: [DrawingImageOperation(kind: "identity", parametersJSON: Data("{}".utf8))],
        preparation: DrawingProducerReceipt(id: "example.dx08-input", version: "1", recordJSON: Data("{}".utf8)))
      var inputJSON = try #require(JSONSerialization.jsonObject(with: input.record.originalJSON) as? [String: Any])
      inputJSON["requiredFeatures"] = ["example.unknown-source/1"]
      let inputBytes = try json(inputJSON)
      let exact = ImageInputRef(issuer: input.reference.issuer, revision: input.reference.revision, digest: .hash(inputBytes))
      files["data/photos/\(photo.reference.issuer.uuidString.lowercased())/\(photo.reference.revision.uuidString.lowercased())/photo.json"] = photo.record.originalJSON
      files["data/inputs/\(exact.issuer.uuidString.lowercased())/\(exact.revision.uuidString.lowercased())/input.json"] = inputBytes
      for asset in input.assets { assets[asset.descriptor.asset.object] = (asset.descriptor, asset.bytes) }
      source = .present(exact); photoRef = photo.reference; inputRef = exact
    }
    let value = try Drawing(program: base.program, input: source, parent: .none, producer: base.producer)
    let frozen = try DrawingExchangeCodec.freeze(value, identity: .init(issuer: UUID()), createdAt: Date(timeIntervalSince1970: 1_800_000_000))
    var drawingJSON = try #require(JSONSerialization.jsonObject(with: frozen.originalJSON) as? [String: Any])
    if unsupportedOwn { drawingJSON["requiredFeatures"] = ["example.unknown-drawing/1"] }
    let drawingBytes = try json(drawingJSON)
    let ref = DrawingRef(issuer: frozen.reference.issuer, revision: frozen.reference.revision, digest: .hash(drawingBytes))
    files["data/drawings/\(ref.issuer.uuidString.lowercased())/\(ref.revision.uuidString.lowercased())/drawing.json"] = drawingBytes
    for (bytes, encoding) in [(frozen.originalProgramJSON, DrawingExchangeCodec.strokeProfile), (value.producer.originalJSON, "utf8-json")] {
      let asset = try ExchangeAsset(bytes: bytes, mediaType: "application/json", encoding: encoding)
      assets[asset.object] = (.init(asset: asset), bytes)
    }
    for (digest, value) in assets { files["data/objects/sha256/" + digest.description] = value.1 }
    let index: [String: Any] = ["profile":"adaptiveplotter.exchange/1", "requiredFeatures":[String](), "kind":"drawing",
      "roots":try wire([ref]), "includedAsOf":"2027-01-15T08:00:00Z", "attempts":[String](), "assessments":[String](),
      "assets":try wire(assets.values.map(\.0).sorted { $0.asset.object.description < $1.asset.object.description })]
    files["data/exchange.json"] = try json(index)
    let bag = directory.appendingPathComponent(UUID().uuidString)
    try write(files, to: bag)
    #expect(try await library.importDrawings(from: bag) == [ref])
    return .init(drawing: try await library.drawing(ref), original: frozen, sourceFiles: files, photo: photoRef, input: inputRef)
  }
  static func write(_ payload: [String: Data], to directory: URL) throws {
    var files = payload
    files["bagit.txt"] = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    files["manifest-sha256.txt"] = Data(files.keys.filter { $0.hasPrefix("data/") }.sorted().map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    files["tagmanifest-sha256.txt"] = Data(["bagit.txt","manifest-sha256.txt"].map {
      ExchangeDigest.hash(files[$0]!).description + "  " + $0 + "\n"
    }.joined().utf8)
    for (path, bytes) in files {
      let url = directory.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try bytes.write(to: url)
    }
  }
}
