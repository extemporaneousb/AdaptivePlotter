import Foundation
import PlotterModel
import Testing
@testable import PlotterApp

/// Uses real producer output and immutable candidate/label constructors.
func portraitTrainingFixture(sourceCount: Int = 5, samplesPerSource: Int = 8) throws -> (PortraitTrainingScopeDefinition, PortraitCandidateArchive) {
  let recipe = PortraitStyleRecipe(id: "training-reference", title: "Training hatch", seed: 7, style: .hatch,
    vectorOptions: .init(hatchSpacing: 8), analysisOptions: .init())
  let scope = PortraitStyleScope(id: UUID(uuidString: "874E3277-EDC7-4F6E-9C4E-5109EFC76458")!, name: "Spacing preference",
    revision: 1, objective: .screenAesthetic, allowedFamilies: [.hatch], activeParameters: [.hatchSpacing], frozenParameters: [.init(parameter: .headScale, value: 1)])
  let definition = PortraitTrainingScopeDefinition(scope: scope, mode: .drawingStyle, referenceRecipe: recipe,
    schemaRevision: PortraitTrainingScopeDefinition.currentRevision)
  var archive = PortraitCandidateArchive()
  for source in 0..<sourceCount {
    for sample in 0..<samplesPerSource {
      let candidate = try portraitTrainingCandidate(definition: definition, source: source, sample: sample)
      let rating = 1 + min(4, sample * 5 / max(1, samplesPerSource))
      let label = try PortraitLabelRevision(candidate: candidate, rating: rating, scope: scope, presentation: .init(),
        id: PortraitVectorizer.stableID("training-label-\(source)-\(sample)"), createdAt: Date(timeIntervalSince1970: 100))
      archive.entries.append(.init(candidate: candidate, reasons: [.init(reason: .rated(labelRevisionID: label.id))]))
      archive.labels.append(label)
    }
  }
  return (definition, archive)
}

func portraitTrainingCandidate(definition: PortraitTrainingScopeDefinition, source: Int, sample: Int,
  captureSessionID: UUID? = nil, ancestryGroupID: UUID? = nil) throws -> PortraitCandidate {
  let extent = try PortraitSourceCropExtent(widthPixels: 32, heightPixels: 32)
  let raster = PortraitRaster(width: 32, height: 32, luminance: Array(repeating: 0.1, count: 1024),
    provenance: "training-source-\(source)", analysisSummary: "synthetic known preference", sourceCropExtent: extent)
  var options = definition.referenceRecipe.vectorOptions
  options.hatchSpacing = 1 + min(15, sample * 2)
  let recipe = PortraitStyleRecipe(id: "training-\(source)-\(sample)", title: "Spacing \(sample)", seed: UInt64(sample),
    style: .hatch, vectorOptions: options, analysisOptions: definition.referenceRecipe.analysisOptions)
  let stroke = try StrokeStyle(nominalLineWidth: 0.4, penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
  let program = try PortraitVectorizer.program(from: raster, pose: .front, style: recipe.style, strokeStyle: stroke, vectorOptions: options)
  let session = captureSessionID ?? PortraitVectorizer.stableID("training-session-\(source)")
  return try PortraitCandidate(sourceData: Data("training-source-\(source)".utf8), sourcePixelExtent: extent, raster: raster,
    recipe: recipe, program: program, photoID: PortraitVectorizer.stableID("training-photo-\(source)"), captureSessionID: session,
    createdAt: Date(timeIntervalSince1970: 100), lineage: .init(parentID: nil, parentProgramHash: nil, parentRecipe: nil,
      ancestryGroupID: ancestryGroupID ?? session), pose: .front)
}

@Suite("Frozen preference datasets")
struct PortraitPreferenceDatasetTests {
  @Test("grouped deterministic split never separates shared sources or unlabeled bridges")
  func grouping() throws {
    let fixture = try portraitTrainingFixture()
    let scope = fixture.0
    var archive = fixture.1
    let a = archive.entries[0].candidate, b = archive.entries[8].candidate
    let bridge = try portraitTrainingCandidate(definition: scope, source: 99, sample: 1,
      captureSessionID: a.captureSessionID, ancestryGroupID: b.lineage.ancestryGroupID)
    archive.entries.append(.init(candidate: bridge, reasons: [.init(reason: .shortlisted)]))
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 4)
    #expect(dataset.payload.groups.first { $0.candidateIDs.contains(a.id) }?.id == dataset.payload.groups.first { $0.candidateIDs.contains(b.id) }?.id)
    #expect(dataset.payload.exclusions.contains { $0.candidateID == bridge.id && $0.reason.contains("without a label") })
    archive.entries.reverse(); archive.labels.reverse()
    #expect(try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 4).id == dataset.id)
    #expect(dataset.payload.rows.contains { $0.split == .holdout })
    for rows in Dictionary(grouping: dataset.payload.rows, by: \.sourceSHA256).values { #expect(Set(rows.map(\.split)).count == 1) }
  }

  @Test("withdrawn current leaf never resurrects an older rating")
  func withdrawal() throws {
    let fixture = try portraitTrainingFixture(sourceCount: 1)
    let scope = fixture.0
    var archive = fixture.1
    let old = archive.labels[0], candidate = archive.entries[0].candidate
    let revised = try PortraitLabelRevision(candidate: candidate, rating: 5, scope: scope.scope, presentation: .init(), previousRevisionID: old.id)
    archive.labels.append(revised)
    archive.tombstones.append(.init(id: UUID(), kind: .label, identity: revised.id.uuidString, affectedCandidateIDs: [], assetSHA256s: [], createdAt: Date()))
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 4)
    #expect(!dataset.payload.rows.contains { $0.candidateID == candidate.id })
    #expect(dataset.payload.exclusions.contains { $0.labelRevisionID == old.id && $0.reason.contains("Superseded") })
    #expect(dataset.payload.exclusions.contains { $0.labelRevisionID == revised.id && $0.reason.contains("withdrawn") })
  }

  @Test("revision forks and cycles are refused before withdrawal filtering")
  func invalidRevisions() throws {
    let fixture = try portraitTrainingFixture(sourceCount: 1)
    let scope = fixture.0
    var archive = fixture.1
    let candidate = archive.entries[0].candidate, old = archive.labels[0]
    for rating in [2,3] { archive.labels.append(try .init(candidate: candidate, rating: rating, scope: scope.scope,
      presentation: .init(), previousRevisionID: old.id)) }
    #expect(throws: PortraitTrainingError.self) { try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 1) }
    archive.labels.removeLast(2)
    let firstID = UUID(), secondID = UUID()
    archive.labels = [try .init(candidate: candidate, rating: 1, scope: scope.scope, presentation: .init(), previousRevisionID: secondID, id: firstID),
      try .init(candidate: candidate, rating: 2, scope: scope.scope, presentation: .init(), previousRevisionID: firstID, id: secondID)]
    #expect(throws: PortraitTrainingError.self) { try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 1) }
  }

  @Test("scope mismatch and frozen parameter changes remain explicit exclusions")
  func exclusions() throws {
    let fixture = try portraitTrainingFixture(sourceCount: 1)
    let scope = fixture.0
    var archive = fixture.1
    let wrong = try portraitPersistenceCandidate()
    archive.entries.append(.init(candidate: wrong, reasons: [.init(reason: .shortlisted)]))
    archive.labels.append(try .init(candidate: wrong, rating: 1, scope: .screenSketch, presentation: .init()))
    let dataset = try PortraitPreferenceDatasetBuilder.freeze(archive: archive, scope: scope, seed: 1)
    #expect(dataset.payload.exclusions.contains { $0.candidateID == wrong.id && $0.reason.contains("Different named scope") })
    let forged = try portraitTrainingReplacingJSON(dataset, key: "id", value: String(repeating: "0", count: 64))
    #expect(throws: PortraitTrainingError.self) { try PortraitTrainingValidation.dataset(forged) }
  }
}

func portraitTrainingReplacingJSON<T: Codable>(_ value: T, key: String, value replacement: Any) throws -> T {
  var object = try #require(JSONSerialization.jsonObject(with: PortraitCandidateCoding.encoder().encode(value)) as? [String: Any])
  object[key] = replacement
  return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: object, options: .sortedKeys))
}
