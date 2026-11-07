import Foundation
import PlotterModel
import PlotterRuntime
import PortraitCore
import Testing
@testable import PlotterApp
@testable import PortraitLibrary

func transferTestPackage(captureID: UUID = UUID(), libraryID: UUID = UUID(),
  resultBytes: Data = Data("{\"frozenResult\":1}".utf8),
  programOverride: DrawingProgram? = nil) throws -> DrawingPackage {
  let base = try DrawingProgramCatalog.program(for: .square, style: portraitTestStyle())
  let program = try programOverride ?? DrawingProgram(id: base.id, fieldExtent: base.fieldExtent,
    strokes: base.strokes, source: .init(kind: "portrait", sourceIdentifier: "external-fixture-v1"))
  let source = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aY9sAAAAASUVORK5CYII=")!
  let image = DrawingPackageAsset(mediaType: "image/png", bytes: source, pixelWidth: 1, pixelHeight: 1)
  return try DrawingPackage(origin: .init(libraryID: libraryID, captureID: captureID, resultID: "result-1",
    resultRecordSHA256: DrawingPackageCodec.sha256(resultBytes), programHash: program.contentHash),
    program: program, createdAt: Date(timeIntervalSinceReferenceDate: 123), title: "Transfer fixture",
    resultRecordJSON: resultBytes, source: image,
    artistInput: .init(mediaType: "application/json", bytes: Data("{\"input\":1}".utf8)),
    artist: .init(identifier: "fixture", revision: "1", settingsJSON: Data("{}".utf8)), preview: image)
}

@Suite("Immutable drawing transfer format")
struct DrawingPackageTests {
  @Test("Exact package round trip preserves authored identities and all embedded bytes")
  func roundTrip() throws {
    let package = try transferTestPackage()
    let bytes = try DrawingPackageCodec.encode(package)
    let decoded = try DrawingPackageCodec.decode(bytes)
    #expect(decoded == package)
    #expect(try DrawingPackageCodec.encode(decoded) == bytes)
    #expect(decoded.program.id == package.program.id)
    #expect(decoded.program.contentHash == package.origin.programHash)
    #expect(decoded.legacyCandidateJSON == nil)
  }

  @Test("Capture, library and frozen record bytes distinguish equal result identities")
  func occurrenceIdentity() throws {
    let capture = UUID(), library = UUID()
    let a = try transferTestPackage(captureID: capture, libraryID: library)
    let same = try transferTestPackage(captureID: capture, libraryID: library)
    let otherCapture = try transferTestPackage(libraryID: library)
    let otherLibrary = try transferTestPackage(captureID: capture)
    let replaced = try transferTestPackage(captureID: capture, libraryID: library,
      resultBytes: Data("{\"frozenResult\":2}".utf8))
    #expect(a.origin.drawingID == same.origin.drawingID)
    #expect(Set([a, otherCapture, otherLibrary, replaced].map { $0.origin.drawingID }).count == 4)
  }

  @Test("Tampered result, source and input bytes fail their declared hashes")
  func tamper() throws {
    let data = try DrawingPackageCodec.encode(transferTestPackage())
    for key in ["source", "artistInput"] {
      var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
      var asset = try #require(json[key] as? [String: Any])
      asset["bytes"] = Data("changed".utf8).base64EncodedString()
      json[key] = asset
      let changed = try JSONSerialization.data(withJSONObject: json)
      #expect(throws: (any Error).self) { try DrawingPackageCodec.decode(changed) }
    }
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json["resultRecordJSON"] = Data("{}".utf8).base64EncodedString()
    #expect(throws: (any Error).self) {
      try DrawingPackageCodec.decode(JSONSerialization.data(withJSONObject: json))
    }
  }

  @Test("Declared dimensions and unsupported package versions are refused")
  func limits() throws {
    let data = try DrawingPackageCodec.encode(transferTestPackage())
    var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var source = try #require(json["source"] as? [String: Any])
    source["pixelWidth"] = DrawingTransferLimits.maximumImageDimension + 1
    json["source"] = source
    #expect(throws: (any Error).self) {
      try DrawingPackageCodec.decode(JSONSerialization.data(withJSONObject: json))
    }
    json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    json["schemaVersion"] = 2
    #expect(throws: (any Error).self) {
      try DrawingPackageCodec.decode(JSONSerialization.data(withJSONObject: json))
    }
  }

  @Test("Version one refuses source-free programs rather than bypassing portrait provenance")
  func portraitSourceGate() throws {
    let program = try DrawingProgramCatalog.program(for: .square, style: portraitTestStyle())
    #expect(throws: (any Error).self) { try transferTestPackage(programOverride: program) }
    let package = try transferTestPackage(), drawing = try SavedDrawing(package: package)
    #expect(SavedDrawing.authored(program: package.program, projectedDrawing: nil, executionProgram: package.program) == nil)
    #expect(SavedDrawing.authored(program: package.program, projectedDrawing: drawing, executionProgram: package.program) == drawing)
  }

  @Test("Nil-origin runtime encoding is unchanged and transferred origin is exact")
  func referenceEncoding() throws {
    let package = try transferTestPackage(), program = package.program
    struct LegacyReference: Encodable {
      let candidateID: String
      let contentHash: PlotterModel.Digest
      let programContentHash: PlotterModel.Digest
      let sourceProgram: DrawingProgram
    }
    let legacy = DrawingRunCandidateReference(candidateID: "drawing-" + program.contentHash.description,
      contentHash: program.contentHash, sourceProgram: program)
    let prior = LegacyReference(candidateID: legacy.candidateID, contentHash: legacy.contentHash,
      programContentHash: legacy.programContentHash, sourceProgram: program)
    #expect(try DrawingPackageCodec.encoder().encode(legacy) == DrawingPackageCodec.encoder().encode(prior))
    let transferred = DrawingRunCandidateReference(candidateID: package.origin.drawingID,
      contentHash: package.origin.identityHash, sourceProgram: program, origin: package.origin)
    #expect(transferred.matches(program))
    let substituted = DrawingRunCandidateReference(candidateID: legacy.candidateID,
      contentHash: legacy.contentHash, sourceProgram: program, origin: package.origin)
    #expect(!substituted.matches(program))
  }
}

@Suite("Drawing Exchange common authored contract")
struct DrawingExchangeValueTests {
  private var fixtureRoot: URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .appendingPathComponent("Fixtures/DrawingExchange/dx02")
  }
  struct VectorIndex: Decodable {
    struct Vector: Decodable { let name: String; let ref: DrawingRef; let programHash: String; let points: [[Double]] }
    let vectors: [Vector]
    let photos: [PhotoRef]
  }
  private func fixtures() throws -> (VectorIndex, [ExchangeDigest: Data]) {
    let index = try JSONDecoder().decode(VectorIndex.self, from: Data(contentsOf: fixtureRoot.appendingPathComponent("vectors.json")))
    var objects: [ExchangeDigest: Data] = [:]
    for url in try FileManager.default.contentsOfDirectory(at: fixtureRoot.appendingPathComponent("objects"), includingPropertiesForKeys: nil) {
      objects[try ExchangeDigest(url.lastPathComponent)] = try Data(contentsOf: url)
    }
    return (index, objects)
  }
  @Test("Frozen cross-language vectors retain bytes geometry and canonical program hashes")
  func vectors() throws {
    let (index, objects) = try fixtures()
    for vector in index.vectors {
      let bytes = try #require(objects[vector.ref.digest])
      guard case .materialized(let record) = try DrawingExchangeCodec.decode(bytes, objects: objects, expected: vector.ref) else { Issue.record("Unexpected opaque vector"); continue }
      #expect(record.drawing.programDigest.description == vector.programHash)
      #expect(record.drawing.program.strokes.flatMap { $0.path.points }.map { [$0.x, $0.y] } == vector.points)
      #expect(DrawingExchangeCodec.encode(record) == bytes)
      #expect(record.drawing.summary().pointCount == vector.points.count)
      #expect(record.drawing.reference == vector.ref)
      if vector.name == "unknown-producer" { #expect(!record.drawing.capabilities.producerVerified); try record.drawing.capabilities.require(.plot) }
      if vector.name == "unknown-required-feature" { #expect(throws: (any Error).self) { try record.drawing.capabilities.require(.plot) } }
      if vector.name == "historical-unknown-units" { #expect(record.drawing.units.nominalPenWidthMM == nil) }
    }
    let a = try DrawingImageAdmission.photo(index.photos[0], objects: objects)
    let b = try DrawingImageAdmission.photo(index.photos[1], objects: objects)
    #expect(a.original == b.original); #expect(a.reference != b.reference)
  }
  @Test("Known producer claims, object bytes, exact refs and missing mask closure fail admission")
  func negatives() throws {
    let (index, objects) = try fixtures()
    let vector = try #require(index.vectors.first { $0.name == "source-free" })
    let bytes = try #require(objects[vector.ref.digest])
    var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var producer = try #require(json["producer"] as? [String: Any])
    let badClaim = Data("{\"entry\":\"square\",\"sourceIdentifier\":\"adaptiveplotter.builtin.line.v1\"}".utf8)
    var altered = objects; altered[.hash(badClaim)] = badClaim; producer["record"] = ExchangeDigest.hash(badClaim).description; json["producer"] = producer
    #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(JSONSerialization.data(withJSONObject: json), objects: altered) }
    altered = objects; let representation = try #require(json["representation"] as? [String: Any]); let digest = try ExchangeDigest(#require(representation["object"] as? String)); altered[digest] = Data("{}".utf8)
    #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(bytes, objects: altered) }
    #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(bytes + Data(" ".utf8), objects: objects, expected: vector.ref) }
    let masked = try #require(index.vectors.first { $0.name == "masked-rotated" })
    let drawingJSON = try #require(objects[masked.ref.digest]); let drawing = try #require(JSONSerialization.jsonObject(with: drawingJSON) as? [String: Any])
    let link = try #require(drawing["input"] as? [String: Any]); let inputRef = try JSONDecoder().decode(ImageInputRef.self, from: JSONSerialization.data(withJSONObject: #require(link["ref"])))
    let input = try DrawingImageAdmission.input(inputRef, objects: objects)
    altered = objects; altered.removeValue(forKey: try #require(input.mask).object)
    #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(drawingJSON, objects: altered) }
  }
  @Test("Strict JSON, source declarations, layout overflow and opaque majors preserve boundaries")
  func strictAdmission() throws {
    for string in ["{\"a\":1,\"a\":2}", "{\"a\":1e999}", "{\"a\":NaN}", "{\"a\":{\"x\":1,\"x\":2}}"] {
      #expect(throws: (any Error).self) { try ExchangeJSON.validate(Data(string.utf8)) }
    }
    let opaque = Data(" {\"profile\":\"adaptiveplotter.drawing/9\", \"future\":true} \n".utf8)
    guard case .opaque(let original, _) = try DrawingExchangeCodec.decode(opaque, objects: [:]) else { Issue.record("Opaque major materialized"); return }
    #expect(original == opaque)
    for string in ["{\"state\":\"none\",\"ref\":null}", "{\"state\":\"unavailable\",\"reason\":\"missing\",\"knownRef\":null}"] {
      #expect(throws: (any Error).self) { try JSONDecoder().decode(SourceLink<DrawingRef>.self, from: Data(string.utf8)) }
    }
    #expect(throws: (any Error).self) { try ExchangeRasterLayout(width: 2, height: 2, bytesPerPixel: 4, rowStride: Int.max) }
    #expect(throws: (any Error).self) { try ExchangeTransform([Double.infinity] + Array(repeating: 0, count: 8)) }
  }
  @Test("Stable-ID edits preserve exact geometry and reject fake edits and parent links")
  func pureEdits() throws {
    let (index, objects) = try fixtures()
    let vector = try #require(index.vectors.first { $0.name == "parent" })
    guard case .materialized(let frozen) = try DrawingExchangeCodec.decode(#require(objects[vector.ref.digest]), objects: objects) else { Issue.record("Missing parent"); return }
    let drawing = frozen.drawing, ids = drawing.program.strokes.map(\.id)
    let child = try drawing.applying(.remove([ids[1]]), to: vector.ref, programID: ProgramID(UUID(uuidString: "00000000-0000-4000-8000-000000000099")!))
    #expect(child.program.strokes == Array(drawing.program.strokes.prefix(1)))
    #expect(child.parent == .present(vector.ref)); #expect(child.reference == nil)
    let frozenChild = try DrawingExchangeCodec.freeze(child, identity: .init(issuer: vector.ref.issuer), createdAt: Date(timeIntervalSince1970: 1))
    var closure = objects
    closure[child.producer.record] = child.producer.originalJSON
    closure[.hash(frozenChild.originalProgramJSON)] = frozenChild.originalProgramJSON
    closure[frozenChild.reference.digest] = frozenChild.originalJSON
    guard case .materialized(let readChild) = try DrawingExchangeCodec.decode(frozenChild.originalJSON, objects: closure) else { Issue.record("Edited child was opaque"); return }
    #expect(readChild.drawing.capabilities.producerVerified)
    let restoreChild = try readChild.drawing.applying(.restore([ids[1]]), to: frozenChild.reference,
      universe: drawing, programID: ProgramID(UUID(uuidString: "00000000-0000-4000-8000-000000000098")!))
    #expect(restoreChild.program.strokes == drawing.program.strokes)
    let badUniverse = try Drawing(program: drawing.program, input: drawing.input, parent: drawing.parent,
      producer: drawing.producer, units: drawing.units)
    #expect(throws: (any Error).self) { try readChild.drawing.applying(.membership(ids), to: frozenChild.reference,
      universe: badUniverse, programID: ProgramID()) }

    let restored = try DrawingStrokeMembership.apply(.restore([ids[1]]), to: child.program, universe: drawing.program)
    #expect(restored == drawing.program.strokes)
    for edit in [DrawingStrokeEdit.remove([]), .remove([ids[0],ids[0]]), .remove(ids), .membership(ids), .remove([StrokeID()])] {
      #expect(throws: (any Error).self) { try DrawingStrokeMembership.apply(edit, to: drawing.program, universe: drawing.program) }
    }
    let wrong = DrawingRef(issuer: vector.ref.issuer, revision: UUID(), digest: vector.ref.digest)
    #expect(throws: (any Error).self) { try drawing.applying(.remove([ids[1]]), to: wrong, programID: ProgramID()) }
    #expect(throws: (any Error).self) { try child.applying(.restore([ids[1]]), to: vector.ref, universe: drawing, programID: ProgramID()) }
  }
  @Test("Concrete source-free producer enters common contract and new exports declare millimeters")
  func catalogProducer() async throws {
    let output = try await CatalogDrawingProducer().produce(input: .line,
      settings: .init(style: portraitTestStyle(), nominalPenWidthMM: 0.5))
    #expect(output.drawing.input == .none); #expect(output.drawing.capabilities.producerVerified)
    #expect(output.drawing.summary().bounds.minY == 50)
    #expect(output.drawing.summary().bounds.maxY == 50)
    let frozen = try DrawingExchangeCodec.freeze(output.drawing, identity: .init(issuer: UUID()), createdAt: Date())
    let objects = [ExchangeDigest.hash(frozen.originalProgramJSON): frozen.originalProgramJSON,
      output.drawing.producer.record: output.artifacts]
    guard case .materialized(let reloaded) = try DrawingExchangeCodec.decode(frozen.originalJSON, objects: objects) else { Issue.record("Unexpected opaque catalog"); return }
    #expect(reloaded.drawing.program == output.drawing.program)
    #expect(reloaded.drawing.units.nominalPenWidthMM == 0.5)
  }
  @Test("New-profile limits admit 20,000 source-free strokes independently of legacy limits")
  func commonLargeProgram() throws {
    let base = try DrawingProgramCatalog.program(for: .line, style: portraitTestStyle())
    let strokes = (0..<20_000).map { index in
      LogicalStroke(id: StrokeID(UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!),
        path: base.strokes[0].path, style: base.strokes[0].style, ordering: UInt32(index))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: base.fieldExtent, strokes: strokes,
      source: .init(kind: "authored", sourceIdentifier: "dx02-large-20000"))
    let receipt = try DrawingProducerReceipt(id: "example.large", version: "1", recordJSON: Data("{}".utf8))
    let drawing = try Drawing(program: program, input: .none, parent: .none, producer: receipt)
    #expect(drawing.summary().strokeCount == 20_000)
    for _ in 0..<30 { #expect(drawing.summary().pointCount == 40_000); #expect(drawing.programDigest == program.contentHash) }
    #expect(DrawingTransferLimits.maximumStrokes == 10_000)
  }

  @Test("Program JSON has an explicit bound independent of the small record bound")
  func largeProgramBytes() throws {
    let base = try DrawingProgramCatalog.program(for: .line, style: portraitTestStyle())
    let program = try DrawingProgram(id: base.id, fieldExtent: base.fieldExtent, strokes: base.strokes,
      source: .init(kind: "authored", sourceIdentifier: String(repeating: "x", count: ExchangeJSON.maximumRecordBytes + 1)))
    let programBytes = try DrawingPackageCodec.encoder().encode(program)
    #expect(programBytes.count > ExchangeJSON.maximumRecordBytes)
    let receipt = try DrawingProducerReceipt(id: "example.large-record", version: "1", recordJSON: Data("{}".utf8))
    let drawing = try Drawing(program: program, input: .none, parent: .none, producer: receipt,
      units: .init(nominalPenWidthMM: 0.5))
    let record = try DrawingExchangeCodec.freeze(drawing, identity: .init(issuer: UUID()), createdAt: Date(), originalProgramJSON: programBytes)
    let objects = [ExchangeDigest.hash(programBytes): programBytes, receipt.record: receipt.originalJSON]
    guard case .materialized(let loaded) = try DrawingExchangeCodec.decode(record.originalJSON, objects: objects) else { Issue.record("Large program opaque"); return }
    #expect(loaded.originalProgramJSON == programBytes)
    #expect(loaded.drawing.programDigest == program.contentHash)
  }
  @Test("Expected digest is checked for opaque majors and unknown producer versions remain unverified")
  func unknownVersion() throws {
    let opaque = Data("{\"profile\":\"adaptiveplotter.drawing/9\"}".utf8)
    let wrong = DrawingRef(issuer: UUID(), revision: UUID(), digest: .hash(Data()))
    #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(opaque, objects: [:], expected: wrong) }
    let (index, objects) = try fixtures()
    let vector = try #require(index.vectors.first { $0.name == "source-free" })
    let bytes = try #require(objects[vector.ref.digest])
    var json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    var producer = try #require(json["producer"] as? [String: Any]); producer["version"] = "999"; json["producer"] = producer
    guard case .materialized(let record) = try DrawingExchangeCodec.decode(JSONSerialization.data(withJSONObject: json), objects: objects) else { Issue.record("Future producer opaque"); return }
    #expect(!record.drawing.capabilities.producerVerified)
    try record.drawing.capabilities.require(.plot)
  }

  private func mutateImage(_ mutation: (inout [String: Any], inout [String: Any]) throws -> Void) throws -> (Data, [ExchangeDigest: Data]) {
    let (index, originals) = try fixtures()
    let vector = try #require(index.vectors.first { $0.name == "masked-rotated" })
    let drawingBytes = try #require(originals[vector.ref.digest])
    var drawing = try #require(JSONSerialization.jsonObject(with: drawingBytes) as? [String: Any])
    let link = try #require(drawing["input"] as? [String: Any])
    var inputRef = try #require(link["ref"] as? [String: Any])
    let inputDigest = try ExchangeDigest(#require(inputRef["digest"] as? String))
    let inputBytes = try #require(originals[inputDigest])
    var input = try #require(JSONSerialization.jsonObject(with: inputBytes) as? [String: Any])
    var photoRef = try #require(input["photo"] as? [String: Any])
    let photoDigest = try ExchangeDigest(#require(photoRef["digest"] as? String))
    let photoBytes = try #require(originals[photoDigest])
    var photo = try #require(JSONSerialization.jsonObject(with: photoBytes) as? [String: Any])
    try mutation(&input, &photo)
    photoRef = try #require(input["photo"] as? [String: Any])
    var objects = originals
    let newPhoto = try JSONSerialization.data(withJSONObject: photo, options: .sortedKeys)
    let newPhotoDigest = ExchangeDigest.hash(newPhoto); objects[newPhotoDigest] = newPhoto
    photoRef["digest"] = newPhotoDigest.description; input["photo"] = photoRef
    let newInput = try JSONSerialization.data(withJSONObject: input, options: .sortedKeys)
    let newInputDigest = ExchangeDigest.hash(newInput); objects[newInputDigest] = newInput
    inputRef["digest"] = newInputDigest.description; drawing["input"] = ["state":"present", "ref":inputRef]
    return (try JSONSerialization.data(withJSONObject: drawing, options: .sortedKeys), objects)
  }
  @Test("Coherent-digest unknown image semantics preserve bytes and gate capabilities")
  func unknownImageSemantics() throws {
    for mutation in 0..<5 {
      let (bytes, objects) = try mutateImage { input, photo in
        if mutation == 0 { photo["requiredFeatures"] = ["example.future-photo/1"] }
        if mutation == 1 { var basis = input["pixelBasis"] as! [String: Any]; basis["orientation"] = "future-orientation"; input["pixelBasis"] = basis }
        if mutation == 3 { input["profile"] = "adaptiveplotter.image-input/9" }
        if mutation == 4 { photo["profile"] = "adaptiveplotter.photo/9" }
        if mutation == 2 { var raster = input["raster"] as! [String: Any]; raster["encoding"] = "example.future-raster/1"; input["raster"] = raster }
      }
      guard case .materialized(let record) = try DrawingExchangeCodec.decode(bytes, objects: objects) else { Issue.record("Unknown input lost geometry"); return }
      #expect(DrawingExchangeCodec.encode(record) == bytes)
      #expect(!record.drawing.capabilities.sourceSemanticsSupported)
      try record.drawing.capabilities.require(.preview)
      try record.drawing.capabilities.require(.plot)
      try record.drawing.capabilities.require(.edit)
      #expect(throws: (any Error).self) { try record.drawing.capabilities.require(.regenerate) }
      #expect(throws: (any Error).self) { try record.drawing.capabilities.require(.train) }
      if mutation == 0 {
        guard case .materialized(let supported) = try DrawingExchangeCodec.decode(bytes, objects: objects, supportedFeatures: ["example.future-photo/1"]) else { return }
        try supported.drawing.capabilities.require(.plot)
        #expect(supported.drawing.capabilities.sourceSemanticsSupported)
      }
    }
  }
  @Test("Coherent-digest raw dimensions mask overflow and malformed known clocks fail")
  func malformedImageClosure() throws {
    for mutation in 0..<7 {
      let (bytes, objects) = try mutateImage { input, photo in
        if mutation == 0 { var original = photo["original"] as! [String: Any]; original.removeValue(forKey: "pixelLayout"); photo["original"] = original }
        if mutation == 1 { var basis = input["pixelBasis"] as! [String: Any]; basis["dimensions"] = ["width":3,"height":2]; input["pixelBasis"] = basis }
        if mutation == 2 || mutation == 3 {
          var mask = input["mask"] as! [String: Any], asset = mask["asset"] as! [String: Any]
          if mutation == 2 { asset.removeValue(forKey: "pixelLayout") }
          else { var layout = asset["pixelLayout"] as! [String: Any]; layout["rowStride"] = Int.max; asset["pixelLayout"] = layout }
          mask["asset"] = asset; input["mask"] = mask
        }
        if mutation == 4 { photo["dimensions"] = ["width":true,"height":2] }
        if mutation == 5 { photo["acquired"] = ["state":"known", "provenance":"bad clock", "time":["wallTime":"2026-11-06T00:00:00Z", "event":["clockID":"camera", "bootSession":"550e8400-e29b-41d4-a716-446655440000", "ticks":"01", "ticksPerSecond":1]]] }
        if mutation == 6 { var asset = input["raster"] as! [String: Any]; var layout = asset["pixelLayout"] as! [String: Any]; layout["rowStride"] = 3; asset["pixelLayout"] = layout; input["raster"] = asset }
      }
      #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(bytes, objects: objects) }
    }
  }
  @Test("Normative index-only descriptors and event-only timestamps are admitted")
  func descriptorContext() throws {
    let (bytes, objects) = try mutateImage { input, photo in
      var original = photo["original"] as! [String: Any]; original.removeValue(forKey: "pixelLayout"); photo["original"] = original
      var raster = input["raster"] as! [String: Any]; raster.removeValue(forKey: "pixelLayout"); input["raster"] = raster
      var mask = input["mask"] as! [String: Any], asset = mask["asset"] as! [String: Any]; asset.removeValue(forKey: "pixelLayout"); mask["asset"] = asset; input["mask"] = mask
      photo["acquired"] = ["state":"known", "provenance":"event-only", "time":["event":["clockID":"camera", "bootSession":"550e8400-e29b-41d4-a716-446655440000", "ticks":"184467440737095516160000", "ticksPerSecond":1]]]
    }
    let (_, originalObjects) = try fixtures()
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    for original in originalObjects.values {
      guard let json = try? JSONSerialization.jsonObject(with: original) as? [String: Any] else { continue }
      for key in ["original", "raster"] {
        if let asset = json[key] as? [String: Any] {
          let d = try JSONDecoder().decode(ExchangeAssetDescriptor.self, from: JSONSerialization.data(withJSONObject: asset)); descriptors[d.asset.object] = d
        }
      }
      if let mask = json["mask"] as? [String: Any], let asset = mask["asset"] as? [String: Any] {
        let d = try JSONDecoder().decode(ExchangeAssetDescriptor.self, from: JSONSerialization.data(withJSONObject: asset)); descriptors[d.asset.object] = d
      }
    }
    guard case .materialized(let record) = try DrawingExchangeCodec.decode(bytes, objects: objects, assetDescriptors: descriptors) else { Issue.record("Index descriptors not resolved"); return }
    try record.drawing.capabilities.require(.plot)
    let layout = try ExchangeArrayLayout(shape: [2,2], dtype: "float32", layout: "row-major", byteOrder: "little", units: "field")
    #expect(try layout.validate(Data(repeating: 0, count: 16)))
    #expect(throws: (any Error).self) { try ExchangeArrayLayout(shape: [9_007_199_254_740_991, 9_007_199_254_740_991], dtype: "float64", layout: "row-major", byteOrder: "little", units: "field") }
  }
  @Test("Freeze preflight rejects ambiguous original program bytes and legacy v1 stays exact")
  func frozenLegacyAndAmbiguousProgram() throws {
    let baseline = fixtureRoot.deletingLastPathComponent().appendingPathComponent("baseline/legacy-v1.json")
    let bytes = try Data(contentsOf: baseline)
    #expect(DrawingPackageCodec.sha256(bytes) == "def00a78893810aa2d520ed0eab0b4c84cbb1a2e30ac195d05b2cd7845d78d4f")
    #expect(try DrawingPackageCodec.encode(DrawingPackageCodec.decode(bytes)) == bytes)
    let base = try DrawingProgramCatalog.program(for: .line, style: portraitTestStyle())
    let receipt = try DrawingProducerReceipt(id: "example.ambiguous", version: "1", recordJSON: Data("{}".utf8))
    let drawing = try Drawing(program: base, input: .none, parent: .none, producer: receipt, units: .init(nominalPenWidthMM: 0.5))
    let program = try DrawingPackageCodec.encoder().encode(base)
    let duplicate = Data("{\"schemaVersion\":1,".utf8) + program.dropFirst()
    #expect(throws: (any Error).self) { try DrawingExchangeCodec.freeze(drawing, identity: .init(issuer: UUID()), createdAt: Date(), originalProgramJSON: duplicate) }
  }

  @Test("Known RGBA and BGRA raw aliases reject coherent channel-order contradictions")
  func rawChannelOrderBindings() throws {
    let pixel = Data([10,20,30,255])
    for encoding in ["raw-rgba8", "raw-bgra8"] {
      let source = try ExchangeAsset(bytes: pixel, mediaType: "application/octet-stream", encoding: encoding)
      let expected = encoding == "raw-rgba8" ? ["red","green","blue","alpha"] : ["blue","green","red","alpha"]
      let format = encoding == "raw-rgba8" ? "rgba" : "bgra"
      let layout = try ExchangePixelLayout(width: 1, height: 1, pixelFormat: format, componentType: "uint8", bitDepth: 8,
        channelOrder: expected, rowStride: 4, byteOrder: "not-applicable", orientation: "up", colorInterpretation: "sRGB")
      let photo: [String: Any] = ["profile":"adaptiveplotter.photo/1", "requiredFeatures":[],
        "ref":["issuer":"550e8400-e29b-41d4-a716-446655440000","revision":"00000000-0000-4000-8000-000000000081"],
        "original":try JSONSerialization.jsonObject(with: DrawingPackageCodec.encoder().encode(ExchangeAssetDescriptor(asset: source, pixelLayout: layout))),
        "dimensions":["width":1,"height":1], "acquired":["state":"unknown","provenance":"fixture"], "imported":["state":"unknown","provenance":"fixture"]]
      let validBytes = try JSONSerialization.data(withJSONObject: photo, options: .sortedKeys)
      let issuer = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!, revision = UUID(uuidString: "00000000-0000-4000-8000-000000000081")!
      var objects = [source.object: pixel, ExchangeDigest.hash(validBytes): validBytes]
      let valid = PhotoRef(issuer: issuer, revision: revision, digest: .hash(validBytes))
      #expect(try DrawingImageAdmission.photo(valid, objects: objects).supportedSemantics)
      var corrupt = photo, asset = photo["original"] as! [String: Any], fields = asset["pixelLayout"] as! [String: Any]
      fields["pixelFormat"] = format == "rgba" ? "bgra" : "rgba"
      fields["channelOrder"] = encoding == "raw-rgba8" ? ["blue","green","red","alpha"] : ["red","green","blue","alpha"]
      asset["pixelLayout"] = fields; corrupt["original"] = asset
      let badBytes = try JSONSerialization.data(withJSONObject: corrupt, options: .sortedKeys)
      objects[.hash(badBytes)] = badBytes
      let bad = PhotoRef(issuer: issuer, revision: revision, digest: .hash(badBytes))
      #expect(throws: (any Error).self) { try DrawingImageAdmission.photo(bad, objects: objects) }
    }
  }

  @Test("Known catalog unit claims reject Boolean widths and unproven physical fields")
  func catalogUnitClaimBindings() throws {
    let (index, originals) = try fixtures()
    let vector = try #require(index.vectors.first { $0.name == "source-free" })
    let bytes = try #require(originals[vector.ref.digest])
    let original = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    for mutation in 0..<2 {
      var record = original, representation = original["representation"] as! [String: Any], objects = originals
      if mutation == 0 {
        var producer = original["producer"] as! [String: Any]
        let claimDigest = try ExchangeDigest(#require(producer["record"] as? String))
        let claimBytes = try #require(objects[claimDigest])
        var claim = try #require(JSONSerialization.jsonObject(with: claimBytes) as? [String: Any])
        claim["nominalPenWidthMillimeters"] = true
        let altered = try JSONSerialization.data(withJSONObject: claim, options: .sortedKeys)
        objects[.hash(altered)] = altered; producer["record"] = ExchangeDigest.hash(altered).description
        record["producer"] = producer; representation["nominalPenWidthMillimeters"] = 1
      } else { representation["intendedPhysicalFieldMillimeters"] = ["width":100,"height":100] }
      record["representation"] = representation
      let altered = try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
      #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(altered, objects: objects) }
    }
  }
  @Test("Closed image identities and references reject coherently rehashed extra keys")
  func closedImageReferences() throws {
    for mutation in 0..<3 {
      let (bytes, objects) = try mutateImage { input, photo in
        if mutation == 0 { var ref = photo["ref"] as! [String: Any]; ref["unexpected"] = 1; photo["ref"] = ref }
        if mutation == 1 { var ref = input["ref"] as! [String: Any]; ref["unexpected"] = 1; input["ref"] = ref }
        if mutation == 2 { var ref = input["photo"] as! [String: Any]; ref["unexpected"] = 1; input["photo"] = ref }
      }
      #expect(throws: (any Error).self) { try DrawingExchangeCodec.decode(bytes, objects: objects) }
    }
    let bad = Data("{\"object\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"byteLength\":9007199254740992,\"mediaType\":\"image/png\",\"encoding\":\"png\"}".utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(ExchangeAsset.self, from: bad) }
  }

  @Test("Freeze and pure edits preserve requirements independently of the receiver's capabilities")
  func requiredFeaturesCannotBeLaundered() throws {
    let (index, originals) = try fixtures()
    let feature = "example.new-meaning/1"
    let unknown = try #require(index.vectors.first { $0.name == "unknown-required-feature" })
    let unknownBytes = try #require(originals[unknown.ref.digest])
    guard case .materialized(let blocked) = try DrawingExchangeCodec.decode(unknownBytes, objects: originals) else { Issue.record("Missing feature vector"); return }
    let frozenBlocked = try DrawingExchangeCodec.freeze(blocked.drawing, identity: .init(issuer: unknown.ref.issuer), createdAt: Date())
    var copiedObjects = originals
    copiedObjects[.hash(frozenBlocked.originalProgramJSON)] = frozenBlocked.originalProgramJSON
    guard case .materialized(let stillBlocked) = try DrawingExchangeCodec.decode(frozenBlocked.originalJSON, objects: copiedObjects) else { Issue.record("Opaque copied drawing"); return }
    #expect(stillBlocked.drawing.requiredFeatures == [feature])
    #expect(throws: (any Error).self) { try stillBlocked.drawing.capabilities.require(.plot) }
    #expect(DrawingExchangeCodec.encode(blocked) == unknownBytes)
    guard case .materialized(let originSupports) = try DrawingExchangeCodec.decode(unknownBytes, objects: originals, supportedFeatures: [feature]) else { return }
    try originSupports.drawing.capabilities.require(.plot)
    let frozenSupported = try DrawingExchangeCodec.freeze(originSupports.drawing, identity: .init(issuer: unknown.ref.issuer), createdAt: Date())
    copiedObjects[.hash(frozenSupported.originalProgramJSON)] = frozenSupported.originalProgramJSON
    guard case .materialized(let receiverDoesNot) = try DrawingExchangeCodec.decode(frozenSupported.originalJSON, objects: copiedObjects) else { return }
    #expect(throws: (any Error).self) { try receiverDoesNot.drawing.capabilities.require(.plot) }
    let parentVector = try #require(index.vectors.first { $0.name == "parent" })
    let parentBytes = try #require(originals[parentVector.ref.digest])
    var parentJSON = try #require(JSONSerialization.jsonObject(with: parentBytes) as? [String: Any])
    parentJSON["requiredFeatures"] = [feature]
    let changedParent = try JSONSerialization.data(withJSONObject: parentJSON, options: .sortedKeys)
    guard case .materialized(let parent) = try DrawingExchangeCodec.decode(changedParent, objects: originals, supportedFeatures: [feature]) else { return }
    let child = try parent.drawing.applying(.remove([parent.drawing.program.strokes[1].id]), to: parent.reference, programID: ProgramID())
    #expect(child.requiredFeatures == [feature])
    let frozenChild = try DrawingExchangeCodec.freeze(child, identity: .init(issuer: parent.reference.issuer), createdAt: Date())
    var closure = originals; closure[parent.reference.digest] = changedParent
    closure[child.producer.record] = child.producer.originalJSON
    closure[.hash(frozenChild.originalProgramJSON)] = frozenChild.originalProgramJSON
    guard case .materialized(let receivedChild) = try DrawingExchangeCodec.decode(frozenChild.originalJSON, objects: closure) else { return }
    #expect(receivedChild.drawing.requiredFeatures == [feature])
    #expect(throws: (any Error).self) { try receivedChild.drawing.capabilities.require(.edit) }
    var forgedChild = try #require(JSONSerialization.jsonObject(with: frozenChild.originalJSON) as? [String: Any])
    forgedChild["requiredFeatures"] = []
    let forgedBytes = try JSONSerialization.data(withJSONObject: forgedChild, options: .sortedKeys)
    let forgedRef = DrawingRef(issuer: frozenChild.reference.issuer, revision: frozenChild.reference.revision, digest: .hash(forgedBytes))
    #expect(throws: DrawingExchangeError.invalidProducer("Membership child drops parent requirements")) {
      try DrawingExchangeCodec.decode(forgedBytes, objects: closure, expected: forgedRef)
    }
    forgedChild["requiredFeatures"] = [feature, "example.additional/1"]
    let extendedBytes = try JSONSerialization.data(withJSONObject: forgedChild, options: .sortedKeys)
    guard case .materialized(let extended) = try DrawingExchangeCodec.decode(extendedBytes, objects: closure) else { Issue.record("Additional requirements became opaque"); return }
    #expect(Set(extended.drawing.requiredFeatures) == [feature, "example.additional/1"])

  }

  @Test("Known historical units stay anchored through exact membership parents")
  func historicalUnitsSurviveMembershipEdits() async throws {
    let output = try await CatalogDrawingProducer().produce(input: .metricSquare40,
      settings: .init(style: portraitTestStyle(), nominalPenWidthMM: 0.5))
    var claim = try #require(JSONSerialization.jsonObject(with: output.drawing.producer.originalJSON) as? [String: Any])
    claim["historicalUnits"] = "millimeters"
    let claimBytes = try JSONSerialization.data(withJSONObject: claim, options: .sortedKeys)
    let receipt = try DrawingProducerReceipt(id: "adaptiveplotter.catalog", version: "1", recordJSON: claimBytes)
    let units = try DrawingUnits(nominalPenWidthMM: 0.5, historical: "millimeters", historicalReceipt: receipt.record)
    let authored = try Drawing(program: output.drawing.program, input: .none, parent: .none, producer: receipt, units: units)
    let root = try DrawingExchangeCodec.freeze(authored, identity: .init(issuer: UUID()), createdAt: Date(timeIntervalSince1970: 1))
    var objects = [ExchangeDigest.hash(root.originalProgramJSON): root.originalProgramJSON,
      receipt.record: receipt.originalJSON, root.reference.digest: root.originalJSON]
    guard case .materialized(let parent) = try DrawingExchangeCodec.decode(root.originalJSON, objects: objects) else { Issue.record("Known historical parent was opaque"); return }
    let first = try parent.drawing.applying(.remove([parent.drawing.program.strokes[0].id]),
      to: parent.reference, programID: ProgramID())
    let firstFrozen = try DrawingExchangeCodec.freeze(first, identity: .init(issuer: parent.reference.issuer), createdAt: Date(timeIntervalSince1970: 2))
    objects[.hash(firstFrozen.originalProgramJSON)] = firstFrozen.originalProgramJSON
    objects[first.producer.record] = first.producer.originalJSON; objects[firstFrozen.reference.digest] = firstFrozen.originalJSON
    guard case .materialized(let firstRead) = try DrawingExchangeCodec.decode(firstFrozen.originalJSON, objects: objects) else { Issue.record("Historical child was opaque"); return }
    #expect(firstRead.drawing.units == units)
    let second = try firstRead.drawing.applying(.remove([firstRead.drawing.program.strokes[0].id]),
      to: firstRead.reference, programID: ProgramID())
    let secondFrozen = try DrawingExchangeCodec.freeze(second, identity: .init(issuer: parent.reference.issuer), createdAt: Date(timeIntervalSince1970: 3))
    objects[.hash(secondFrozen.originalProgramJSON)] = secondFrozen.originalProgramJSON
    objects[second.producer.record] = second.producer.originalJSON
    guard case .materialized(let secondRead) = try DrawingExchangeCodec.decode(secondFrozen.originalJSON, objects: objects) else { Issue.record("Historical descendant was opaque"); return }
    #expect(secondRead.drawing.units == units)
    #expect(secondRead.drawing.program.strokes.count == 1)
    let forgedProof = ExchangeDigest.hash(Data("forged historical proof".utf8)).description
    for (record, expectedError) in [(firstFrozen, DrawingExchangeError.invalidProducer("Membership receipt bindings")),
      (root, DrawingExchangeError.invalidProducer("Unit receipt is not the admitted producer"))] {
      var json = try #require(JSONSerialization.jsonObject(with: record.originalJSON) as? [String: Any])
      var representation = json["representation"] as! [String: Any]
      var historical = representation["historicalUnits"] as! [String: Any]
      historical["producerReceipt"] = forgedProof; representation["historicalUnits"] = historical; json["representation"] = representation
      let bytes = try JSONSerialization.data(withJSONObject: json, options: .sortedKeys)
      let ref = DrawingRef(issuer: record.reference.issuer, revision: record.reference.revision, digest: .hash(bytes))
      #expect(throws: expectedError) { try DrawingExchangeCodec.decode(bytes, objects: objects, expected: ref) }
    }
  }

}
