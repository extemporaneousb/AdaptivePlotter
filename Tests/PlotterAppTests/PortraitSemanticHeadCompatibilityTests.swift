import Foundation
import Testing

@testable import PlotterApp

@Suite("Semantic head archive compatibility")
struct PortraitSemanticHeadCompatibilityTests {
  @Test("DS02 and DS03 goldens preserve every hashed legacy byte and exact vector program")
  func legacyEncodingGoldens() throws {
    for (json, identity) in [(Self.ds02JSON, Self.ds02ID), (Self.ds03JSON, Self.ds03ID)] {
      let bytes = Data(json.utf8)
      let candidate = try JSONDecoder().decode(PortraitCandidate.self, from: bytes)
      try candidate.validateIntegrity()
      let encoder = PortraitCandidateCoding.encoder()
      #expect(candidate.id == identity)
      #expect(candidate.producerRevision == "portrait-v3")
      #expect(candidate.warpManifest == nil)
      #expect(candidate.recipe.vectorOptions.semanticHead == nil)
      #expect(candidate.rasterSHA256 == Self.rasterSHA256)
      #expect(candidate.recipeSHA256 == Self.recipeSHA256)
      #expect(candidate.program.contentHash.description == Self.programSHA256)
      #expect(String(decoding: try encoder.encode(candidate.raster), as: UTF8.self) == Self.rasterJSON)
      #expect(String(decoding: try encoder.encode(candidate.recipe), as: UTF8.self) == Self.recipeJSON)
      #expect(try encoder.encode(candidate) == bytes)
      #expect(candidate.program.strokes[0].path.points.map(\.x) == [20, 180])
      #expect(candidate.program.strokes[0].path.points.map(\.y) == [30, 60])
      #expect(candidate.renderPose == .front)
    }
  }

  @Test("durable storage reloads legacy candidates without migration, reanalysis, or vector replacement")
  func legacyDurableReload() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-ds04-goldens-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let candidates = try [Self.ds02JSON, Self.ds03JSON].map {
      try JSONDecoder().decode(PortraitCandidate.self, from: Data($0.utf8))
    }
    let writer = PortraitCandidateStore(directoryURL: directory)
    try await writer.save(snapshot: .init(entries: candidates.map {
      .init(candidate: $0, reasons: [.init(reason: .shortlisted)])
    }))
    let loaded = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(loaded.canWrite)
    #expect(loaded.archive.entries.count == 2)
    for expected in candidates {
      let actual = try #require(loaded.archive.entries.first { $0.id == expected.id }?.candidate)
      try actual.validateIntegrity()
      #expect(actual.program == expected.program)
      #expect(try PortraitCandidateCoding.encoder().encode(actual)
        == PortraitCandidateCoding.encoder().encode(expected))
    }
  }

  @Test("legacy head candidates remain exact and local exploration requires an explicit new semantic render")
  @MainActor
  func legacyHeadLocalRefusal() async throws {
    let candidate = try JSONDecoder().decode(PortraitCandidate.self, from: Data(Self.ds03JSON.utf8))
    let renderer = SemanticCompatibilityUnexpectedRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    _ = model.sketches.retain(candidate: candidate, reason: .shortlisted)
    #expect(model.selectedCandidate?.id == Self.ds03ID)
    model.moreLikeThis(seed: 93)
    await model.awaitRendering()
    #expect(await renderer.callCount == 0)
    #expect(model.selectedCandidate?.id == Self.ds03ID)
    #expect(model.selectedCandidate?.program == candidate.program)
    #expect(model.history.candidates.isEmpty)
    #expect(model.explorationStatus?.contains("previous head transform") == true)
    #expect(model.sketches.entries.map(\.id) == [Self.ds03ID])
    await model.shutdown()
  }

  @Test("More Like This freezes all semantic head parameters and exact analysis options")
  func localHeadParametersAreFrozen() throws {
    var parameters = PortraitSemanticHeadParameters()
    parameters.foreheadWidth = 0.31
    parameters.foreheadHeight = 0.29
    parameters.eyeScale = 0.13
    parameters.lateralScale = 0.19
    let parent = try semanticCandidate(parameters: parameters)
    let before = try PortraitCandidateCoding.encoder().encode(parent)
    for seed in UInt64(0)..<64 {
      let proposal = PortraitProposalPolicy.local(parent: parent, seed: seed)
      #expect(proposal.recipe.vectorOptions.semanticHead == parameters)
      #expect(proposal.recipe.vectorOptions.headScale == parent.recipe.vectorOptions.headScale)
      #expect(proposal.recipe.analysisOptions == parent.recipe.analysisOptions)
      #expect(proposal.metadata.kind == .local)
    }
    #expect(try PortraitCandidateCoding.encoder().encode(parent) == before)
  }

  @Test("new semantic parameters and manifest create distinct retained identities without changing legacy payloads")
  func semanticIdentityAndDurability() async throws {
    let legacyBytes = Data(Self.ds03JSON.utf8)
    let legacy = try JSONDecoder().decode(PortraitCandidate.self, from: legacyBytes)
    let first = try semanticCandidate(parameters: .init())
    var changed = PortraitSemanticHeadParameters()
    changed.foreheadWidth = 0.37
    let second = try semanticCandidate(parameters: changed)
    #expect(first.id != second.id)
    #expect(first.recipeSHA256 != second.recipeSHA256)
    #expect(first.warpManifest != second.warpManifest)
    #expect(first.program.contentHash != second.program.contentHash)
    #expect(first.producerRevision == "portrait-v4")
    #expect(first.id != legacy.id)
    #expect(try PortraitCandidateCoding.encoder().encode(legacy) == legacyBytes)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("portrait-ds04-semantic-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    try await PortraitCandidateStore(directoryURL: directory).save(snapshot: .init(entries:
      [legacy, first, second].map { .init(candidate: $0, reasons: [.init(reason: .shortlisted)]) }))
    let result = await PortraitCandidateStore(directoryURL: directory).load()
    #expect(result.canWrite)
    #expect(Set(result.archive.entries.map(\.id)) == Set([legacy.id, first.id, second.id]))
    let restored = try #require(result.archive.entries.first { $0.id == first.id }?.candidate)
    try restored.validateIntegrity()
    #expect(restored.warpManifest == first.warpManifest)
    #expect(restored.program == first.program)
    #expect(restored.recipe.vectorOptions.semanticHead == first.recipe.vectorOptions.semanticHead)
  }

  @Test("semantic candidates reject missing or mismatched warp evidence")
  func manifestIntegrity() throws {
    let first = try semanticCandidate(parameters: .init())
    var changed = PortraitSemanticHeadParameters()
    changed.eyeScale = 0.27
    let second = try semanticCandidate(parameters: changed)
    #expect(throws: (any Error).self) {
      _ = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program,
        photoID: first.photoID, captureSessionID: first.captureSessionID, pose: first.pose)
    }
    #expect(throws: (any Error).self) {
      _ = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program,
        photoID: first.photoID, captureSessionID: first.captureSessionID, pose: first.pose,
        warpManifest: second.warpManifest)
    }
  }

  private func semanticCandidate(parameters: PortraitSemanticHeadParameters) throws -> PortraitCandidate {
    let source = try portraitPersistenceCandidate()
    var options = source.recipe.vectorOptions
    options.headScale = 1.4
    options.semanticHead = parameters
    let recipe = PortraitStyleRecipe(id: "semantic-compatibility", title: "Semantic archive fixture", seed: 73,
      style: source.recipe.style, vectorOptions: options, analysisOptions: source.recipe.analysisOptions)
    let program = try PortraitVectorizer.program(from: source.raster, pose: .front, style: recipe.style,
      strokeStyle: source.program.strokes[0].style, vectorOptions: options)
    // Deliberately absent landmark evidence produces an explicit unavailable
    // manifest. These are archive/identity tests, not semantic-warp quality proof.
    let manifest = PortraitHeadTransform(raster: source.raster, parameters: parameters).manifest
    return try PortraitCandidate(sourceData: source.sourceData, sourcePixelExtent: source.sourcePixelExtent,
      raster: source.raster, recipe: recipe, program: program, photoID: source.photoID,
      captureSessionID: source.captureSessionID, pose: .front, warpManifest: manifest)
  }

  // Frozen with the actual DS03 encoders from main b868effb, copied read-only
  // into an isolated /tmp Swift script before DS04 production integration.
  // No current encoder is used to generate or normalize these expected bytes.
  // A minimal, valid exact program makes accidental rerendering detectable.
  private static let ds02ID = "e73dfa6da5079d444afbf0618319438df02d37cad17ff2600912cb10ac4271f8"
  private static let ds03ID = "a089a054701f6dbb36a9ac52e4f8e0cd0a43b4f47e9b8102c2fa7e7c16d77215"
  private static let rasterSHA256 = "11f11e8169e0d381b7aeaae1ef9b797253b682a9515797f520bbaa164400c84b"
  private static let recipeSHA256 = "68a276eb896cf55942d8f6b736ad9ab0c715c337f173887090893c67431b3d1d"
  private static let programSHA256 = "975260444595e25d0568f01ef3f6e823c1bc2058c6c2dd2ebf0caff53f22ebfa"
  private static let rasterJSON = #"""
{"analysisSummary":"Exact legacy fixture","height":2,"luminance":[0,0.25,0.5,1],"provenance":"ds03-golden-analysis","schemaVersion":2,"sourceCropExtent":{"heightPixels":40,"widthPixels":80},"width":2}
"""#
  private static let recipeJSON = #"""
{"analysisOptions":{"cropToFace":true,"faceCropMargin":0.35,"removeBackground":true},"id":"ds03-golden-recipe","seed":73,"style":"Hatch","title":"Legacy Big Head","vectorOptions":{"contourLevels":6,"hatchAngleDegrees":0,"hatchSpacing":4,"headScale":1.4,"minimumContourLength":3,"simplificationTolerance":0.35,"sketchThreshold":0.012,"smoothing":0,"tonalStrength":1}}
"""#
  private static let ds02JSON = #"""
{"captureSessionID":"00000000-0000-0000-0000-000000000004","createdAt":1,"id":"e73dfa6da5079d444afbf0618319438df02d37cad17ff2600912cb10ac4271f8","lineage":{"ancestryGroupID":"00000000-0000-0000-0000-000000000004"},"photoID":"00000000-0000-0000-0000-000000000005","producerRevision":"portrait-v3","program":{"contentHash":{"bytes":[151,82,96,68,69,149,226,93,5,104,240,30,243,246,232,35,193,188,32,88,198,194,221,46,191,12,175,245,63,34,235,250]},"fieldExtent":{"height":100,"width":200},"id":{"rawValue":"00000000-0000-0000-0000-000000000002"},"schemaVersion":1,"source":{"kind":"portrait","sourceIdentifier":"portrait-v3|pose=Front|ds03-golden"},"strokes":[{"id":{"rawValue":"00000000-0000-0000-0000-000000000003"},"ordering":0,"path":{"points":[{"x":20,"y":30},{"x":180,"y":60}]},"semanticRole":0,"style":{"nominalLineWidth":0.8,"penProfileID":{"rawValue":"00000000-0000-0000-0000-000000000001"}}}]},"raster":{"analysisSummary":"Exact legacy fixture","height":2,"luminance":[0,0.25,0.5,1],"provenance":"ds03-golden-analysis","schemaVersion":2,"sourceCropExtent":{"heightPixels":40,"widthPixels":80},"width":2},"rasterSHA256":"11f11e8169e0d381b7aeaae1ef9b797253b682a9515797f520bbaa164400c84b","recipe":{"analysisOptions":{"cropToFace":true,"faceCropMargin":0.35,"removeBackground":true},"id":"ds03-golden-recipe","seed":73,"style":"Hatch","title":"Legacy Big Head","vectorOptions":{"contourLevels":6,"hatchAngleDegrees":0,"hatchSpacing":4,"headScale":1.4,"minimumContourLength":3,"simplificationTolerance":0.35,"sketchThreshold":0.012,"smoothing":0,"tonalStrength":1}},"recipeSHA256":"68a276eb896cf55942d8f6b736ad9ab0c715c337f173887090893c67431b3d1d","sourceData":"AQIDBA==","sourcePixelExtent":{"heightPixels":40,"widthPixels":80},"sourceSHA256":"9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a"}
"""#
  private static let ds03JSON = #"""
{"captureSessionID":"00000000-0000-0000-0000-000000000004","createdAt":1,"id":"a089a054701f6dbb36a9ac52e4f8e0cd0a43b4f47e9b8102c2fa7e7c16d77215","lineage":{"ancestryGroupID":"00000000-0000-0000-0000-000000000004"},"photoID":"00000000-0000-0000-0000-000000000005","pose":"Front","producerRevision":"portrait-v3","program":{"contentHash":{"bytes":[151,82,96,68,69,149,226,93,5,104,240,30,243,246,232,35,193,188,32,88,198,194,221,46,191,12,175,245,63,34,235,250]},"fieldExtent":{"height":100,"width":200},"id":{"rawValue":"00000000-0000-0000-0000-000000000002"},"schemaVersion":1,"source":{"kind":"portrait","sourceIdentifier":"portrait-v3|pose=Front|ds03-golden"},"strokes":[{"id":{"rawValue":"00000000-0000-0000-0000-000000000003"},"ordering":0,"path":{"points":[{"x":20,"y":30},{"x":180,"y":60}]},"semanticRole":0,"style":{"nominalLineWidth":0.8,"penProfileID":{"rawValue":"00000000-0000-0000-0000-000000000001"}}}]},"proposal":{"family":"hatch","kind":"broad","policyRevision":"portrait-proposal-v1","seed":73},"raster":{"analysisSummary":"Exact legacy fixture","height":2,"luminance":[0,0.25,0.5,1],"provenance":"ds03-golden-analysis","schemaVersion":2,"sourceCropExtent":{"heightPixels":40,"widthPixels":80},"width":2},"rasterSHA256":"11f11e8169e0d381b7aeaae1ef9b797253b682a9515797f520bbaa164400c84b","recipe":{"analysisOptions":{"cropToFace":true,"faceCropMargin":0.35,"removeBackground":true},"id":"ds03-golden-recipe","seed":73,"style":"Hatch","title":"Legacy Big Head","vectorOptions":{"contourLevels":6,"hatchAngleDegrees":0,"hatchSpacing":4,"headScale":1.4,"minimumContourLength":3,"simplificationTolerance":0.35,"sketchThreshold":0.012,"smoothing":0,"tonalStrength":1}},"recipeSHA256":"68a276eb896cf55942d8f6b736ad9ab0c715c337f173887090893c67431b3d1d","sourceData":"AQIDBA==","sourcePixelExtent":{"heightPixels":40,"widthPixels":80},"sourceSHA256":"9f64a747e1b97f131fabb6b447296c9b6f0201e79fb3c5356e6c77e89b6a806a"}
"""#
}

private actor SemanticCompatibilityUnexpectedRenderer: PortraitRendering {
  private(set) var callCount = 0
  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    callCount += 1
    throw PortraitDrawingError.noLines
  }
}
