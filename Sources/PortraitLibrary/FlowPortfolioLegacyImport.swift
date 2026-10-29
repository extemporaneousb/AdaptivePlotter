import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore

extension FlowPortfolioStore {
  /// An explicit historical import retains the entire original package and its
  /// actual human operations. It never upgrades untouched lines into positives.
  @discardableResult package func importLegacySelection(packageData: Data) throws -> FlowPortfolioLegacyImport {
    let packageHash = DrawingPackageCodec.sha256(packageData)
    if let previous = state.legacyImports.first(where: { $0.package.sha256 == packageHash }) { return previous }
    let package = try DrawingPackageCodec.decode(packageData)
    try DrawingPackageLibraryValidation.validate(package)
    guard let record = try DrawingStrokeSelection.record(in: package),
      record.schemaVersion == 2, record.operationSource == .human, let operations = record.operations else {
      throw FlowPortfolioError.invalid("Historical import requires an exact version-two human line-selection record.")
    }
    let root = try record.original()
    guard let legacyBytes = root.legacyCandidateJSON else { throw FlowPortfolioError.invalid("Historical Flow Edge basis is missing.") }
    let legacy = try JSONDecoder().decode(PortraitCandidate.self, from: legacyBytes)
    let recipe = try Self.importedRecipe(legacy.recipe.vectorOptions)
    let encode = DrawingPackageCodec.encoder()
    let retainedPackage = try storage.retain(packageData, mediaType: "application/json")
    var next = state
    let source: FlowPortfolioSource
    if let existing = next.sources.first(where: { $0.image.sha256 == root.source.sha256 }) { source = existing }
    else {
      source = FlowPortfolioSource(id: UUID(), createdAt: Date(), title: "Imported photo \(next.sources.count + 1) · \(root.source.sha256.prefix(8))",
        image: try storage.retain(root.source.bytes, mediaType: root.source.mediaType), subjectID: nil, sessionID: nil)
      next.sources.append(source)
    }
    let roundID = UUID(), candidateID = UUID(), date = Date()
    let candidate = FlowPortfolioCandidate(id: candidateID, createdAt: date, sourceID: source.id,
      roundID: roundID, slot: 0, parentCandidateID: nil, recipe: recipe, modelID: nil,
      program: try storage.retain(encode.encode(root.program), mediaType: "application/json"),
      raster: try storage.retain(encode.encode(legacy.raster), mediaType: "application/json"),
      preview: try storage.retain(root.preview.bytes, mediaType: root.preview.mediaType),
      programHash: root.program.contentHash.description, strokeCount: root.program.strokes.count)
    next.candidates.append(candidate)
    next.rounds.append(FlowPortfolioRound(id: roundID, createdAt: date, sourceID: source.id,
      parentCandidateID: nil, recipes: [recipe], analysisOptions: legacy.recipe.analysisOptions,
      seed: legacy.recipe.seed, modelID: nil, status: .completed, candidateIDs: [candidateID],
      displayedCandidateIDs: [candidateID], recommendedCandidateID: nil, failures: []))
    let positions = Dictionary(uniqueKeysWithValues: root.program.strokes.enumerated().map { ($0.element.id, $0.offset) })
    var mask = Set(record.initialRemovedStrokeIDs.compactMap { positions[$0] })
    var previous: UUID?, undo: [UUID] = []
    if !mask.isEmpty {
      let revision = FlowPortfolioPruneRevision(id: UUID(), createdAt: date, candidateID: candidateID,
        parentRevisionID: nil, action: .inheritedSelection, affectedIndices: mask.sorted(), removedIndices: mask.sorted(),
        modelID: nil, operationID: nil, inheritedFromRevisionID: nil, historicalRecord: retainedPackage,
        probabilities: nil, threshold: nil, policy: nil, undoOperationIDs: [], redoOperationIDs: [])
      next.pruneRevisions.append(revision); previous = revision.id
    }
    for operation in operations {
      let affected = operation.strokeIDs.compactMap { positions[$0] }.sorted()
      let id = UUID()
      if operation.action == .remove { mask.formUnion(affected) } else { mask.subtract(affected) }
      undo.append(id)
      let revision = FlowPortfolioPruneRevision(id: id, createdAt: date, candidateID: candidateID,
        parentRevisionID: previous, action: operation.action == .remove ? .remove : .restore,
        affectedIndices: affected, removedIndices: mask.sorted(), modelID: nil, operationID: nil,
        inheritedFromRevisionID: nil, historicalRecord: nil, probabilities: nil, threshold: nil, policy: nil,
        undoOperationIDs: undo, redoOperationIDs: [])
      next.pruneRevisions.append(revision); previous = id
    }
    guard mask == Set(record.removedStrokeIDs.compactMap { positions[$0] }) else {
      throw FlowPortfolioError.invalid("Historical human operations do not reproduce their exact saved target.")
    }
    let imported = FlowPortfolioLegacyImport(id: UUID(), createdAt: date, sourceID: source.id,
      candidateID: candidateID, finalRevisionID: previous, package: retainedPackage)
    next.legacyImports.append(imported)
    // Import is provenance, not a ranking, selection, or completed-target label.
    try commit(next, operation: "historicalSelectionImported", subjectID: imported.id)
    return imported
  }

  private static func importedRecipe(_ options: PortraitVectorOptions) throws -> FlowArtistRecipe {
    guard options.drawingParameters == nil, options.semanticHead == nil, options.eyeExaggeration == nil,
      options.headScale == 1, options.materialContext == nil, options.regionalAdjustments?.isEmpty ?? true else {
      throw FlowPortfolioError.invalid("Historical recipe uses controls outside the selected Flow artist model; its original remains untouched.")
    }
    if let regional = options.regionalTreatment {
      guard regional.scope == .face, regional.skinSuppression == 0, regional.featureProtection == 0.7,
        regional.shadowStrength == 0, regional.contourEmphasis == 0 else {
        throw FlowPortfolioError.invalid("Historical regional treatment is outside the Flow artist parameter space.")
      }
    }
    var values: [Double] = []
    values.append(Double(options.hatchSpacing)); values.append(options.minimumContourLength)
    values.append(options.simplificationTolerance); values.append(options.tonalStrength)
    values.append(options.smoothing); values.append(options.sketchThreshold)
    values.append(options.flowRectilinearity ?? 0); values.append(options.flowSupport ?? 0)
    values.append(options.flowStructureSupport ?? 0); values.append(options.flowSupportScale ?? 0)
    values.append(options.flowSeedIrregularity ?? 0); values.append(options.regionalTreatment?.angularity ?? 0)
    guard values.count == FlowArtistRecipe.bounds.count,
      zip(values, FlowArtistRecipe.bounds).allSatisfy({ $0.isFinite && $1.contains($0) }) else {
      throw FlowPortfolioError.invalid("Historical parameters exceed the new model's declared bounds; import refused without clamping.")
    }
    return FlowArtistRecipe(values: zip(values, FlowArtistRecipe.bounds).map { ($0 - $1.lowerBound) / ($1.upperBound - $1.lowerBound) })
  }
}
