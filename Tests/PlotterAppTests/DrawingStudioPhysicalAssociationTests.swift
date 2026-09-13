import Foundation
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

@Suite("Studio physical attempt association")
@MainActor
struct DrawingStudioPhysicalAssociationTests {
  @Test("successful projection pins exact candidate despite gallery selection with identical vectors")
  func exactProjection() async throws {
    let model = PortraitStudioModel()
    let first = try portraitPersistenceCandidate()
    let sibling = try portraitPersistenceCandidate(lineage: .init(parentID: first.id,
      parentProgramHash: first.program.contentHash.description, parentRecipe: first.recipe,
      ancestryGroupID: UUID()))
    #expect(first.program == sibling.program)
    #expect(first.id != sibling.id)
    #expect(await model.acceptProjection(first, perform: { nil }) == nil)
    #expect(model.sketches.retain(candidate: sibling, reason: .shortlisted) == nil)
    #expect(model.selectedCandidate?.id == sibling.id)
    #expect(model.projectedReference(for: first.program)?.candidateID == first.id)
    #expect(await model.acceptProjection(sibling, perform: { "projection failed" }) == "projection failed")
    #expect(model.projectedReference(for: first.program)?.candidateID == first.id)
    #expect(await model.acceptProjection(sibling, perform: { nil }) == nil)
    #expect(model.projectedReference(for: first.program)?.candidateID == sibling.id)
    await model.shutdown()
  }

  @Test("physical rating requires a result identity and round trips without changing screen context")
  func physicalLabels() throws {
    let screen = try PortraitPresentationContext()
    let bytes = try PortraitCandidateCoding.encoder().encode(screen)
    #expect(!String(decoding: bytes, as: UTF8.self).contains("physical"))
    #expect(throws: PortraitCandidateError.invalidPresentation) {
      try PortraitPresentationContext(objective: .physicalRealization)
    }
    let attempt = UUID(), record = UUID()
    let context = try PortraitPresentationContext(objective: .physicalRealization,
      physicalAttemptID: attempt, physicalRecordID: record,
      physicalMediaSHA256s: [String(repeating: "a", count: 64)])
    let decoded = try JSONDecoder().decode(PortraitPresentationContext.self,
      from: PortraitCandidateCoding.encoder().encode(context))
    #expect(decoded == context)
    #expect(decoded.physicalAttemptID == attempt)
    #expect(decoded.objective != screen.objective)
  }

  @Test("material context extends plan provenance while absent metadata preserves old encoding")
  func materialIdentity() throws {
    let digest = try Digest(bytes: Array(repeating: 1, count: 32))
    let material = try Digest(bytes: Array(repeating: 2, count: 32))
    let base = DrawingPlanningProvenance(modelRevisionID: .init(), modelContentHash: digest,
      registrationRevisionID: .init(), registrationContentHash: digest)
    let changed = DrawingPlanningProvenance(modelRevisionID: base.modelRevisionID, modelContentHash: digest,
      registrationRevisionID: base.registrationRevisionID, registrationContentHash: digest,
      materialContextHash: material)
    #expect(try canonicalDigest(of: base) != canonicalDigest(of: changed))
    let encoder = PortraitCandidateCoding.encoder()
    let encoded = try encoder.encode(base)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("materialContextHash"))
    #expect(try JSONDecoder().decode(DrawingPlanningProvenance.self, from: encoded) == base)
  }
}
