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
