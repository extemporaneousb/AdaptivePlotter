import DrawingLibrary
import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore

/// Private writer for Scripts/convert_historical_drawings.py. Only the script
/// knows the retired catalog/portfolio layouts. Both apps stay current-only.
private struct Blob: Decodable {
  let path: String
  let sha256: ExchangeDigest
  func read() throws -> Data {
    let bytes = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    guard ExchangeDigest.hash(bytes) == sha256 else { throw DrawingExchangeError.digestMismatch(path) }
    return bytes
  }
}

private struct Source: Decodable {
  let issuer: UUID
  let id: UUID
  let image: Blob
  let acquired: Date?
  let title: String
  let session: String?
  let facts: Data
}

private struct Artwork: Decodable {
  let issuer: UUID
  let id: UUID
  let inputID: UUID
  let photo: String
  let program: Data
  let programHash: ExchangeDigest
  let raster: Blob?
  let created: Date
  let title: String
  let receipt: Data
}

private struct Entry: Decodable {
  let key: String
  let source: Source?
  let artwork: Artwork?
}

private struct References: Encodable {
  var photos: [String: PhotoRef] = [:]
  var drawings: [String: DrawingRef] = [:]
}

@main
private enum HistoricalDrawingImport {
  static func main() async {
    do {
      if CommandLine.arguments.dropFirst().first == "--flow-prune" {
        try materializeFlowRevision()
        return
      }
      guard CommandLine.arguments.count == 4 else {
        throw DrawingExchangeError.malformed("Use Scripts/convert_historical_drawings.py")
      }
      let args = CommandLine.arguments
      let library = DrawingLibrary(directoryURL: URL(fileURLWithPath: args[1]))
      var refs = References()
      do {
        for try await line in URL(fileURLWithPath: args[2]).lines {
          let entry = try JSONDecoder().decode(Entry.self, from: Data(line.utf8))
          do {
            if let source = entry.source {
              refs.photos[entry.key] = try await importPhoto(source, library)
            } else if let art = entry.artwork, let ref = refs.photos[art.photo] {
              refs.drawings[entry.key] = try await importDrawing(art, photo: ref, library: library)
            } else { throw DrawingExchangeError.malformed("Missing source") }
          } catch { throw DrawingExchangeError.malformed("\(entry.key): \(error)") }
        }
      } catch {
        await library.closeLibrary()
        throw error
      }
      await library.closeLibrary()
      try DrawingArtifactCoding.encoder().encode(refs).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    } catch {
      FileHandle.standardError.write(Data("Historical import: \(error)\n".utf8))
      exit(1)
    }
  }

  /// Historical portfolios stored an ordered mask. Recreate the original export
  /// program with the same identity and source string as FlowPortfolioStore v2.
  private static func materializeFlowRevision() throws {
    struct Mask: Decodable {
      let base: Blob
      let expected: ExchangeDigest
      let revision: UUID
      let source: String
      let removed: [Int]
    }
    let mask = try JSONDecoder().decode(Mask.self, from: FileHandle.standardInput.readDataToEndOfFile())
    let base = try JSONDecoder().decode(DrawingProgram.self, from: mask.base.read())
    let removed = Set(mask.removed)
    guard ExchangeDigest(base.contentHash) == mask.expected, removed.count == mask.removed.count,
      removed.allSatisfy(base.strokes.indices.contains) else { throw DrawingExchangeError.malformed("Invalid archived stroke mask") }
    let strokes = base.strokes.enumerated().compactMap { removed.contains($0.offset) ? nil : $0.element }
    guard !strokes.isEmpty else { return }
    let result = try DrawingProgram(id: ProgramID(mask.revision), fieldExtent: base.fieldExtent, strokes: strokes,
      source: DrawingSourceProvenance(kind: "portrait", sourceIdentifier: mask.source))
    FileHandle.standardOutput.write(try DrawingArtifactCoding.encoder().encode(result))
  }

  static private func importPhoto(_ source: Source, _ library: DrawingLibrary) async throws -> PhotoRef {
    let image = try PortraitDrawingImages.sourceAsset(source.image.read())
    let date: DrawingImageDatedFact = try source.acquired.map {
      .known(try ExchangeTimestamp(wallTime: ISO8601DateFormatter().string(from: $0)), provenance: "historical-capture")
    } ?? .unknown(provenance: "capture-time-unavailable")
    let photo = try DrawingImageRecords.photo(identity: .init(issuer: source.issuer, revision: source.id),
      original: image.asset, width: image.width, height: image.height, acquired: date,
      imported: .unknown(provenance: "original-import-time-unavailable"), captureFactsJSON: source.facts)
    let metadata = DrawingLibraryPhotoMetadataPatch(title: .set(source.title), sessionID: .set(source.session))
    try await library.commitRecords([], closure: .init(photo: photo),
      photoMetadata: [.init(reference: photo.reference, patch: metadata)])
    return photo.reference
  }

  static private func importDrawing(_ item: Artwork, photo ref: PhotoRef,
    library: DrawingLibrary) async throws -> DrawingRef {
    let photo = try await library.photo(ref)
    let program = try JSONDecoder().decode(DrawingProgram.self, from: item.program)
    guard ExchangeDigest(program.contentHash) == item.programHash else { throw DrawingExchangeError.digestMismatch("source program") }
    var input: FrozenImageInputRecord?
    if let raster = item.raster {
      let prepared = try JSONDecoder().decode(PortraitRaster.self, from: raster.read())
      guard let source = photo.assets.first(where: { $0.descriptor.asset.object == photo.record.original.object }) else {
        throw DrawingExchangeError.missingAsset("source photo")
      }
      input = try PortraitDrawingImages.input(result: .init(raster: prepared, program: program), data: source.bytes,
        photo: photo, identity: .init(issuer: item.issuer, revision: item.inputID))
    }
    let drawing = try Drawing(program: program, input: input.map { .present($0.reference) }
      ?? .unavailable(reason: "No archived preparation geometry", knownRef: nil),
      parent: .unavailable(reason: "Historical ancestry not converted", knownRef: nil),
      producer: .init(id: "adaptiveplotter.historical-import", version: "1", recordJSON: item.receipt))
    let frozen = try DrawingExchangeCodec.freeze(drawing, identity: .init(issuer: item.issuer, revision: item.id),
      createdAt: item.created, originalProgramJSON: item.program)
    let publication = try await library.preparePublication(frozen, closure: input.map(DrawingLibraryRetainedClosure.init(input:)) ?? .empty, database: nil)
    defer { try? FileManager.default.removeItem(at: publication.temporaryRoot) }
    let pending = try await library.prepareRetention(frozen.drawing, title: item.title, reason: "Historical import",
      closure: .init(publication: publication.package))
    return try await library.commitRetention(pending).reference
  }
}
