import CryptoKit
import Foundation
import Observation
import PlotterModel

/// An immutable preference label attached to one exact authoring candidate.
/// The caller supplies the completed render's source and recipe, not whatever
/// happens to be selected while another render is still running.
struct PortraitPreferenceExample: Identifiable, Codable, Hashable, Sendable {
  let id: UUID
  let photoID: UUID
  let photoData: Data
  let photoSHA256: String
  let recipe: PortraitStyleRecipe
  let recipeSHA256: String
  let program: DrawingProgram
  let rating: Int
  let createdAt: Date
  let ratedAt: Date

  var programContentHash: String { program.contentHash.description }
}

struct PortraitPreferenceExport: Codable, Sendable {
  let schemaVersion: Int
  let kind: String
  let ratingMinimum: Int
  let ratingMaximum: Int
  let intendedUsage: String
  let sourceImageEncoding: String
  let examples: [PortraitPreferenceExample]

  init(examples: [PortraitPreferenceExample]) {
    schemaVersion = 1
    kind = "portrait-preference-examples"
    ratingMinimum = 1
    ratingMaximum = 5
    intendedUsage = "Operator ratings of generated candidates for preference analysis or ranker training. "
      + "The vectors are generated candidates, not corrected target artwork. "
      + "These examples contain no evidence of physical plotting and do not represent a trained generator."
    sourceImageEncoding = "base64-original-retained-image-bytes"
    self.examples = examples
  }
}

enum PortraitPreferenceError: LocalizedError {
  case emptyCollection
  case collectionTooLarge

  var errorDescription: String? {
    switch self {
    case .emptyCollection: "Rate a completed portrait before exporting examples."
    case .collectionTooLarge: "The rated examples exceed the export size limit."
    }
  }
}

/// Session-only storage. The byte budget measures the complete export payload,
/// including base64 photos, full vector programs, recipes and metadata. No
/// files are written and no network request is made by this collection.
@Observable @MainActor
final class PortraitPreferenceCollection {
  nonisolated static let maximumCount = 32
  nonisolated static let maximumRetainedBytes = 48 * 1024 * 1024

  private(set) var examples: [PortraitPreferenceExample] = []
  private(set) var retainedBytes = 0
  @ObservationIgnored private let countLimit: Int
  @ObservationIgnored private let byteLimit: Int
  @ObservationIgnored private var exampleByteCounts: [UUID: Int] = [:]
  @ObservationIgnored private var envelopeByteCount: Int?

  init(maximumCount: Int = 32, maximumRetainedBytes: Int = 48 * 1024 * 1024) {
    countLimit = min(Self.maximumCount, max(1, maximumCount))
    byteLimit = min(Self.maximumRetainedBytes, max(0, maximumRetainedBytes))
  }

  @discardableResult
  func record(
    photoData: Data, photoID: UUID, recipe: PortraitStyleRecipe,
    program: DrawingProgram, rating: Int
  ) -> String? {
    guard !photoData.isEmpty else { return "The portrait source is unavailable; the rating was not saved." }
    guard (1...5).contains(rating) else { return "Choose a rating from 1 to 5." }
    guard photoData.count <= byteLimit else {
      return "This portrait is too large to retain as a rated example."
    }
    do {
      let photoHash = Self.digest(photoData)
      let recipeHash = Self.digest(try Self.encoder().encode(recipe))
      let existing = examples.first {
        $0.photoSHA256 == photoHash && $0.recipeSHA256 == recipeHash
          && $0.program.contentHash == program.contentHash
      }
      let now = Date()
      let example = PortraitPreferenceExample(
        id: existing?.id ?? UUID(), photoID: photoID, photoData: photoData,
        photoSHA256: photoHash, recipe: recipe, recipeSHA256: recipeHash,
        program: program, rating: rating, createdAt: existing?.createdAt ?? now, ratedAt: now)
      let encodedByteCount = try Self.encoder().encode(example).count
      let envelopeBytes: Int
      if let cached = envelopeByteCount { envelopeBytes = cached }
      else { envelopeBytes = try Self.encoder().encode(PortraitPreferenceExport(examples: [])).count }
      guard envelopeBytes + encodedByteCount <= byteLimit else {
        return "This candidate's photo and vectors are too large to retain as a rated example."
      }

      // Prepare the full mutation before publishing it. An encoding failure or
      // oversized record leaves every existing example and rating intact.
      var updated = examples.filter { $0.id != example.id }
      var byteCounts = exampleByteCounts
      byteCounts[example.id] = encodedByteCount
      updated.append(example)
      func payloadBytes(_ entries: [PortraitPreferenceExample]) -> Int {
        envelopeBytes + entries.reduce(0) { $0 + (byteCounts[$1.id] ?? 0) } + max(0, entries.count - 1)
      }
      while updated.count > countLimit || payloadBytes(updated) > byteLimit {
        let removed = updated.removeFirst()
        byteCounts.removeValue(forKey: removed.id)
      }
      envelopeByteCount = envelopeBytes
      exampleByteCounts = byteCounts
      retainedBytes = payloadBytes(updated)
      examples = updated
      return nil
    } catch {
      return "The rating could not be saved: \(error.localizedDescription)"
    }
  }

  func remove(_ id: UUID) {
    examples.removeAll { $0.id == id }
    exampleByteCounts.removeValue(forKey: id)
    retainedBytes = examples.isEmpty ? 0 : (envelopeByteCount ?? 0)
      + examples.reduce(0) { $0 + (exampleByteCounts[$1.id] ?? 0) } + max(0, examples.count - 1)
  }

  func exportData() throws -> Data {
    try Self.exportData(examples: examples)
  }

  /// The UI can freeze examples on MainActor, then encode that immutable
  /// snapshot in a detached task before presenting its file exporter.
  nonisolated static func exportData(examples: [PortraitPreferenceExample]) throws -> Data {
    guard !examples.isEmpty else { throw PortraitPreferenceError.emptyCollection }
    guard examples.count <= maximumCount else { throw PortraitPreferenceError.collectionTooLarge }
    let data = try encoder().encode(PortraitPreferenceExport(examples: examples))
    guard data.count <= maximumRetainedBytes else { throw PortraitPreferenceError.collectionTooLarge }
    return data
  }

  private nonisolated static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.dataEncodingStrategy = .base64
    return encoder
  }

  private nonisolated static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
