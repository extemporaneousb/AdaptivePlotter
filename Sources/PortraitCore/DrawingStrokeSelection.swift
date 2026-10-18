import Foundation
import PlotterModel

/// An exact supervised selection target, not an aesthetic or pass/fail label.
/// The root package is embedded once; reopening an edit never nests edit packages.
public struct DrawingStrokeSelection: Codable, Equatable, Sendable {
  public static let artistIdentifier = "adaptiveplotter.flow-edge-selection"
  public static let revision = "whole-polyline-removal-v1"
  public let schemaVersion: Int
  public let editID: UUID
  public let createdAt: Date
  public let originalPackageJSON: Data
  public let baseOrigin: DrawingOriginReference
  public let baseProgram: DrawingProgram
  public let initialRemovedStrokeIDs: [StrokeID]
  /// Applied removal groups only. Undone groups are excluded from the target.
  public let deletionBatches: [[StrokeID]]
  public let removedStrokeIDs: [StrokeID]
  public let judgment: String

  public init(editID: UUID, createdAt: Date, originalPackageJSON: Data,
    baseOrigin: DrawingOriginReference, baseProgram: DrawingProgram, initialRemovedStrokeIDs: [StrokeID],
    deletionBatches: [[StrokeID]]) throws {
    schemaVersion = 1; self.editID = editID; self.createdAt = createdAt
    self.originalPackageJSON = originalPackageJSON; self.baseOrigin = baseOrigin
    self.baseProgram = baseProgram
    self.initialRemovedStrokeIDs = initialRemovedStrokeIDs; self.deletionBatches = deletionBatches
    removedStrokeIDs = initialRemovedStrokeIDs + deletionBatches.flatMap { $0 }
    judgment = "unrated-selection-target"
    _ = try original()
  }

  public func original() throws -> DrawingPackage {
    guard schemaVersion == 1, judgment == "unrated-selection-target",
      createdAt.timeIntervalSinceReferenceDate.isFinite,
      originalPackageJSON.count <= DrawingTransferLimits.drawingJSONBytes,
      deletionBatches.count <= DrawingTransferLimits.maximumStrokes else {
      throw DrawingTransferError.invalid("Unsupported or oversized stroke-selection record.")
    }
    // Inspect before validating to disallow recursive/nested selection packages.
    let original = try JSONDecoder().decode(DrawingPackage.self, from: originalPackageJSON)
    guard original.artist.identifier == "adaptiveplotter.Flow Edge", original.legacyCandidateJSON != nil else {
      throw DrawingTransferError.invalid("Line editing requires a frozen native Flow Edge original.")
    }
    try original.validate(); try baseOrigin.validate()
    let all = Set(original.program.strokes.map(\.id)), removed = Set(removedStrokeIDs)
    let initial = Set(initialRemovedStrokeIDs)
    guard baseOrigin.captureID == original.origin.captureID,
      baseProgram.contentHash == baseOrigin.programHash,
      baseProgram.fieldExtent == original.program.fieldExtent,
      baseProgram.strokes == original.program.strokes.filter({ !initial.contains($0.id) }),
      removedStrokeIDs == initialRemovedStrokeIDs + deletionBatches.flatMap({ $0 }),
      removed.count == removedStrokeIDs.count, removed.isSubset(of: all), removed.count < all.count,
      deletionBatches.allSatisfy({ !$0.isEmpty }) else {
      throw DrawingTransferError.invalid("Removal groups must name distinct original lines and leave at least one line.")
    }
    return original
  }

  public func program() throws -> DrawingProgram {
    let root = try original(), removed = Set(removedStrokeIDs)
    return try DrawingProgram(id: ProgramID(editID), fieldExtent: root.program.fieldExtent,
      strokes: root.program.strokes.filter { !removed.contains($0.id) },
      source: DrawingSourceProvenance(kind: "portrait", sourceIdentifier:
        Self.revision + "|original=" + root.origin.identityHash.description + "|edit=" + editID.uuidString.lowercased()))
  }

  public static func record(in package: DrawingPackage) throws -> Self? {
    guard package.artist.identifier == artistIdentifier else { return nil }
    let record = try JSONDecoder().decode(Self.self, from: package.resultRecordJSON)
    let root = try record.original()
    guard package.artist.revision == revision, package.program == (try record.program()),
      package.source == root.source, package.artistInput == root.artistInput,
      package.createdAt == record.createdAt, package.origin.captureID == root.origin.captureID,
      package.origin.resultID == record.editID.uuidString.lowercased(), package.legacyCandidateJSON == nil,
      package.artist.settingsJSON == settingsJSON else {
      throw DrawingTransferError.invalid("The edited package differs from its exact stroke-selection target.")
    }
    return record
  }

  public static var settingsJSON: Data {
    Data("{\"operation\":\"whole-polyline-removal\",\"retained_strokes\":\"target-membership-not-independent-approval\",\"quality_judgment\":\"unrated\"}".utf8)
  }
}
