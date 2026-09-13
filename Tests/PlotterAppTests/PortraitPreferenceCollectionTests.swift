import CryptoKit
import Foundation
import PlotterModel
import Testing

@testable import PlotterApp

@Suite("Exact portrait preference examples")
@MainActor
struct PortraitPreferenceCollectionTests {
  @Test("export preserves immutable source bytes, complete vectors, recipe, and rating")
  func exactSnapshot() throws {
    let collection = PortraitPreferenceCollection()
    var photo = Data([1, 2, 3, 4])
    let originalPhoto = photo, photoID = UUID(), recipe = self.recipe()
    let program = try self.program(photo: photo, recipe: recipe)
    #expect(collection.record(photoData: photo, photoID: photoID, recipe: recipe,
      program: program, rating: 4) == nil)
    photo[0] = 9
    let exported = try collection.exportData()
    let document = try decode(exported)
    #expect(document.schemaVersion == 1)
    #expect(document.intendedUsage.contains("not corrected target artwork"))
    #expect(document.intendedUsage.contains("do not represent a trained generator"))
    let example = try #require(document.examples.first)
    #expect(example.photoData == originalPhoto)
    #expect(example.photoID == photoID)
    #expect(example.photoSHA256 == digest(originalPhoto))
    #expect(example.recipe == recipe)
    #expect(example.program == program)
    #expect(example.rating == 4)
    #expect(example.programContentHash == program.contentHash.description)
    #expect(collection.retainedBytes == exported.count)
    let json = try #require(JSONSerialization.jsonObject(with: exported) as? [String: Any])
    let records = try #require(json["examples"] as? [[String: Any]])
    #expect(records[0]["photoData"] as? String == originalPhoto.base64EncodedString())
  }

  @Test("re-rating identical source, recipe, and vectors replaces the existing label")
  func rerating() throws {
    let collection = PortraitPreferenceCollection(), photo = Data([7]), recipe = self.recipe()
    let program = try self.program(photo: photo, recipe: recipe)
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: program, rating: 2) == nil)
    let initial = try #require(collection.examples.first)
    let latestPhotoID = UUID()
    #expect(collection.record(photoData: photo, photoID: latestPhotoID, recipe: recipe,
      program: program, rating: 5) == nil)
    #expect(collection.examples.count == 1)
    let updated = try #require(collection.examples.first)
    #expect(updated.id == initial.id)
    #expect(updated.createdAt == initial.createdAt)
    #expect(updated.ratedAt >= initial.ratedAt)
    #expect(updated.photoID == latestPhotoID)
    #expect(updated.rating == 5)
    #expect(collection.retainedBytes == (try collection.exportData()).count)
  }

  @Test("recipe and pen-program changes produce distinct preference candidates")
  func candidateIdentity() throws {
    let collection = PortraitPreferenceCollection(), photo = Data([8]), firstRecipe = self.recipe()
    let firstProgram = try self.program(photo: photo, recipe: firstRecipe)
    let secondRecipe = self.recipe(seed: 99)
    let widerProgram = try self.program(photo: photo, recipe: firstRecipe, penWidth: 1.2)
    for (recipe, program) in [(firstRecipe, firstProgram), (secondRecipe, firstProgram), (firstRecipe, widerProgram)] {
      #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
        program: program, rating: 3) == nil)
    }
    #expect(collection.examples.count == 3)
    #expect(Set(collection.examples.map(\.id)).count == 3)
    #expect(collection.examples[0].recipeSHA256 != collection.examples[1].recipeSHA256)
    #expect(collection.examples[0].programContentHash != collection.examples[2].programContentHash)
  }

  @Test("count retention evicts oldest examples and protects a newly revised rating")
  func countRetention() throws {
    let collection = PortraitPreferenceCollection(maximumCount: 2), recipe = self.recipe()
    let photos = [Data([1]), Data([2]), Data([3])]
    let programs = try photos.map { try self.program(photo: $0, recipe: recipe) }
    for index in 0...1 {
      #expect(collection.record(photoData: photos[index], photoID: UUID(), recipe: recipe,
        program: programs[index], rating: 2) == nil)
    }
    #expect(collection.record(photoData: photos[0], photoID: UUID(), recipe: recipe,
      program: programs[0], rating: 5) == nil)
    #expect(collection.record(photoData: photos[2], photoID: UUID(), recipe: recipe,
      program: programs[2], rating: 4) == nil)
    #expect(collection.examples.map(\.photoData) == [photos[0], photos[2]])
    #expect(collection.examples.map(\.rating) == [5, 4])
  }

  @Test("byte retention counts base64 source data and complete vector payload")
  func byteRetention() throws {
    let recipe = self.recipe(), photo = Data(repeating: 1, count: 4096)
    let firstProgram = try self.program(photo: photo, recipe: recipe)
    let probe = PortraitPreferenceCollection()
    #expect(probe.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: firstProgram, rating: 3) == nil)
    let oneSize = probe.retainedBytes
    #expect(oneSize > photo.count)
    let limit = oneSize + oneSize / 2
    let collection = PortraitPreferenceCollection(maximumRetainedBytes: limit)
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: firstProgram, rating: 3) == nil)
    let newestPhoto = Data(repeating: 2, count: 4096)
    #expect(collection.record(photoData: newestPhoto, photoID: UUID(), recipe: recipe,
      program: try self.program(photo: newestPhoto, recipe: recipe), rating: 4) == nil)
    #expect(collection.examples.count == 1)
    #expect(collection.examples.first?.photoData == newestPhoto)
    #expect(collection.retainedBytes <= limit)
    #expect(collection.retainedBytes == (try collection.exportData()).count)
  }

  @Test("oversized, empty, invalid-rating and unencodable records preserve existing examples")
  func failedRecordIsAtomic() throws {
    let collection = PortraitPreferenceCollection(maximumRetainedBytes: 40_000)
    let photo = Data([1]), recipe = self.recipe(), program = try self.program(photo: Data([1]), recipe: self.recipe())
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: program, rating: 3) == nil)
    let before = collection.examples, beforeBytes = collection.retainedBytes
    #expect(collection.record(photoData: Data(repeating: 9, count: 40_000), photoID: UUID(),
      recipe: recipe, program: program, rating: 4) != nil)
    #expect(collection.record(photoData: Data(), photoID: UUID(), recipe: recipe,
      program: program, rating: 4) != nil)
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: program, rating: 0) != nil)
    let nonfinite = PortraitStyleRecipe(id: "invalid", title: "Invalid", seed: 0, style: .hatch,
      vectorOptions: PortraitVectorOptions(tonalStrength: .nan), analysisOptions: PortraitAnalysisOptions())
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: nonfinite,
      program: program, rating: 4) != nil)
    #expect(collection.examples == before)
    #expect(collection.retainedBytes == beforeBytes)
  }

  @Test("closing an example removes its export payload immediately")
  func removeExample() throws {
    let collection = PortraitPreferenceCollection(), recipe = self.recipe(), photo = Data([1])
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: try self.program(photo: photo, recipe: recipe), rating: 3) == nil)
    collection.remove(try #require(collection.examples.first?.id))
    #expect(collection.examples.isEmpty)
    #expect(collection.retainedBytes == 0)
    #expect(throws: PortraitPreferenceError.self) { try collection.exportData() }
  }

  @Test("export snapshot is Sendable and independent of subsequent session edits")
  func backgroundExport() async throws {
    let collection = PortraitPreferenceCollection(), recipe = self.recipe(), photo = Data([1])
    #expect(collection.record(photoData: photo, photoID: UUID(), recipe: recipe,
      program: try self.program(photo: photo, recipe: recipe), rating: 3) == nil)
    let snapshot = collection.examples
    collection.remove(try #require(snapshot.first?.id))
    let exported = try await Task.detached {
      try PortraitPreferenceCollection.exportData(examples: snapshot)
    }.value
    #expect(try decode(exported).examples.count == 1)
    #expect(collection.examples.isEmpty)
  }

  private func recipe(seed: UInt64 = 42) -> PortraitStyleRecipe {
    PortraitStyleRecipe(id: "test-hatch", title: "Hatch", seed: seed, style: .hatch,
      vectorOptions: PortraitVectorOptions(hatchSpacing: 8), analysisOptions: PortraitAnalysisOptions())
  }

  private func program(photo: Data, recipe: PortraitStyleRecipe, penWidth: Double = 0.8) throws -> DrawingProgram {
    let raster = PortraitRaster(width: 40, height: 40, luminance: Array(repeating: 0.1, count: 1600),
      provenance: "image=\(digest(photo))", analysisSummary: "preference serialization fixture")
    let style = try StrokeStyle(nominalLineWidth: penWidth,
      penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
    return try PortraitVectorizer.program(from: raster, pose: .front, style: recipe.style,
      strokeStyle: style, vectorOptions: recipe.vectorOptions)
  }

  private func decode(_ data: Data) throws -> PortraitPreferenceExport {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return try decoder.decode(PortraitPreferenceExport.self, from: data)
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
