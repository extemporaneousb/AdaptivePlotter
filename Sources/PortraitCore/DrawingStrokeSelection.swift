import Foundation
import PlotterModel

/// An exact supervised selection target, not an aesthetic or pass/fail label.
/// The root package is embedded once; reopening an edit never nests edit packages.
public struct DrawingStrokeSelection: Codable, Equatable, Sendable {
  public static let artistIdentifier = "adaptiveplotter.flow-edge-selection"
  public static let revision = "whole-polyline-removal-v1"
  public static let restorationRevision = "whole-polyline-selection-v2"
  public struct Operation: Codable, Equatable, Sendable {
    public enum Action: String, Codable, Sendable { case remove, restore }
    public let action: Action
    public let strokeIDs: [StrokeID]
    public init(action: Action, strokeIDs: [StrokeID]) {
      self.action = action; self.strokeIDs = strokeIDs
    }
  }
  public enum OperationSource: String, Codable, Sendable { case human, exerciseProposal }
  public struct ExerciseContext: Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let policyJSON: Data
    public init(id: UUID, title: String, policyJSON: Data) {
      self.id = id; self.title = title; self.policyJSON = policyJSON
    }
  }
  public let schemaVersion: Int
  public let editID: UUID
  public let createdAt: Date
  public let originalPackageJSON: Data
  public let baseOrigin: DrawingOriginReference
  public let baseProgram: DrawingProgram
  public let initialRemovedStrokeIDs: [StrokeID]
  /// Applied removal groups only. Undone groups are excluded from the target.
  public let deletionBatches: [[StrokeID]]
  /// Version two records applied remove/restore operations in order, with their source.
  /// Undone operations are absent. Starting removals belong to the retained base.
  public let operations: [Operation]?
  public let operationSource: OperationSource?
  /// Carried through human edits to identify the generated exercise, not a label.
  public let exerciseContext: ExerciseContext?
  public let removedStrokeIDs: [StrokeID]
  public let judgment: String

  public init(editID: UUID, createdAt: Date, originalPackageJSON: Data,
    baseOrigin: DrawingOriginReference, baseProgram: DrawingProgram, initialRemovedStrokeIDs: [StrokeID],
    deletionBatches: [[StrokeID]]) throws {
    schemaVersion = 1; self.editID = editID; self.createdAt = createdAt
    self.originalPackageJSON = originalPackageJSON; self.baseOrigin = baseOrigin
    self.baseProgram = baseProgram
    self.initialRemovedStrokeIDs = initialRemovedStrokeIDs; self.deletionBatches = deletionBatches
    operations = nil
    operationSource = nil; exerciseContext = nil
    removedStrokeIDs = initialRemovedStrokeIDs + deletionBatches.flatMap { $0 }
    judgment = "unrated-selection-target"
    _ = try original()
  }

  public init(editID: UUID, createdAt: Date, originalPackageJSON: Data,
    baseOrigin: DrawingOriginReference, baseProgram: DrawingProgram,
    initialRemovedStrokeIDs: [StrokeID], operations: [Operation],
    operationSource: OperationSource = .human, exerciseContext: ExerciseContext? = nil) throws {
    schemaVersion = 2; self.editID = editID; self.createdAt = createdAt
    self.originalPackageJSON = originalPackageJSON; self.baseOrigin = baseOrigin
    self.baseProgram = baseProgram; self.initialRemovedStrokeIDs = initialRemovedStrokeIDs
    self.operations = operations
    self.operationSource = operationSource; self.exerciseContext = exerciseContext
    deletionBatches = operations.filter { $0.action == .remove }.map(\.strokeIDs)
    var removed = Set(initialRemovedStrokeIDs)
    for operation in operations {
      if operation.action == .remove { removed.formUnion(operation.strokeIDs) }
      else { removed.subtract(operation.strokeIDs) }
    }
    let root = try JSONDecoder().decode(DrawingPackage.self, from: originalPackageJSON)
    removedStrokeIDs = root.program.strokes.map(\.id).filter { removed.contains($0) }
    judgment = "unrated-selection-target"
    _ = try original()
  }

  public var artistRevision: String { schemaVersion == 2 ? Self.restorationRevision : Self.revision }
  public var artistSettingsJSON: Data {
    schemaVersion == 2
      ? Data("{\"operation\":\"whole-polyline-remove-and-restore\",\"retained_strokes\":\"target-membership-not-independent-approval\",\"quality_judgment\":\"unrated\"}".utf8)
      : Self.settingsJSON
  }

  public func original() throws -> DrawingPackage {
    guard [1, 2].contains(schemaVersion), judgment == "unrated-selection-target",
      createdAt.timeIntervalSinceReferenceDate.isFinite,
      originalPackageJSON.count <= DrawingTransferLimits.drawingJSONBytes,
      deletionBatches.count <= DrawingTransferLimits.maximumStrokes,
      (operations?.count ?? 0) <= DrawingTransferLimits.maximumStrokes,
      (operations?.reduce(0, { $0 + $1.strokeIDs.count }) ?? 0) <= DrawingTransferLimits.maximumPoints else {
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
      initial.count == initialRemovedStrokeIDs.count, initial.isSubset(of: all),
      removed.count == removedStrokeIDs.count, removed.isSubset(of: all), removed.count < all.count,
      deletionBatches.allSatisfy({ !$0.isEmpty }) else {
      throw DrawingTransferError.invalid("Removal groups must name distinct original lines and leave at least one line.")
    }
    if schemaVersion == 1 {
      guard operations == nil, operationSource == nil, exerciseContext == nil,
        removedStrokeIDs == initialRemovedStrokeIDs + deletionBatches.flatMap({ $0 }) else {
        throw DrawingTransferError.invalid("Legacy removal groups differ from their target.")
      }
    } else {
      guard let operations, let operationSource,
        deletionBatches == operations.filter({ $0.action == .remove }).map(\.strokeIDs) else {
        throw DrawingTransferError.invalid("Selection operations are missing or inconsistent.")
      }
      if let exerciseContext {
        guard !exerciseContext.title.isEmpty, exerciseContext.title.utf8.count <= 256,
          !exerciseContext.policyJSON.isEmpty, exerciseContext.policyJSON.count <= 2 * 1024 * 1024,
          (try? JSONSerialization.jsonObject(with: exerciseContext.policyJSON)) != nil else {
          throw DrawingTransferError.invalid("Exercise context is invalid.")
        }
      } else if operationSource == .exerciseProposal {
        throw DrawingTransferError.invalid("Generated exercise selection requires its policy context.")
      }
      var applied = initial
      for operation in operations {
        let ids = Set(operation.strokeIDs)
        guard !ids.isEmpty, ids.count == operation.strokeIDs.count, ids.isSubset(of: all),
          operation.action == .remove ? ids.isDisjoint(with: applied) : ids.isSubset(of: applied) else {
          throw DrawingTransferError.invalid("Selection operations do not match the available lines.")
        }
        if operation.action == .remove { applied.formUnion(ids) } else { applied.subtract(ids) }
      }
      guard removedStrokeIDs == original.program.strokes.map(\.id).filter({ applied.contains($0) }) else {
        throw DrawingTransferError.invalid("Selection operations differ from the exact final target.")
      }
    }
    return original
  }

  public func program() throws -> DrawingProgram {
    let root = try original(), removed = Set(removedStrokeIDs)
    let strokes = removed.isEmpty ? root.program.strokes
      : try DrawingStrokeMembership.apply(.remove(removedStrokeIDs), to: root.program, universe: root.program)
    return try DrawingProgram(id: ProgramID(editID), fieldExtent: root.program.fieldExtent,
      strokes: strokes,
      source: DrawingSourceProvenance(kind: "portrait", sourceIdentifier:
        artistRevision + "|original=" + root.origin.identityHash.description + "|edit=" + editID.uuidString.lowercased()))
  }

  public static func record(in package: DrawingPackage) throws -> Self? {
    guard package.artist.identifier == artistIdentifier else { return nil }
    let record = try JSONDecoder().decode(Self.self, from: package.resultRecordJSON)
    let root = try record.original()
    guard package.artist.revision == record.artistRevision, package.program == (try record.program()),
      package.source == root.source, package.artistInput == root.artistInput,
      package.createdAt == record.createdAt, package.origin.captureID == root.origin.captureID,
      package.origin.resultID == record.editID.uuidString.lowercased(), package.legacyCandidateJSON == nil,
      package.artist.settingsJSON == record.artistSettingsJSON else {
      throw DrawingTransferError.invalid("The edited package differs from its exact stroke-selection target.")
    }
    return record
  }

  public static var settingsJSON: Data {
    Data("{\"operation\":\"whole-polyline-removal\",\"retained_strokes\":\"target-membership-not-independent-approval\",\"quality_judgment\":\"unrated\"}".utf8)
  }
}
