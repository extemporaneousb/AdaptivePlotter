import PortraitCore
@testable import PortraitArtists
@testable import PortraitLibrary
@testable import PortraitStudioUI
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
    let library = DrawingFirstTestStorage.library()
    let model = PortraitStudioModel(library: library)
    let program = try DrawingProgramCatalog.program(for: .line, style: portraitTestStyle())
    let receipt = try DrawingProducerReceipt(id: "example.physical-association", version: "1", recordJSON: Data("{}".utf8))
    let value = try Drawing(program: program, input: .none, parent: .none, producer: receipt)
    let a = try await library.retain(value, reason: "save"), b = try await library.retain(value, reason: "save")
    let first = try await library.drawing(a.reference), sibling = try await library.drawing(b.reference)
    #expect(first.program == sibling.program && first.reference != sibling.reference)
    #expect(await model.acceptDrawingProjection(first, operation: {}) == nil)
    try await model.sketches.select(b.reference)
    #expect(model.projectedDrawing?.executionReference(for: program)?.candidateID == a.reference.digest.description)
    enum Refused: Error { case projection }
    #expect(await model.acceptDrawingProjection(sibling) { throw Refused.projection } != nil)
    #expect(model.projectedDrawing?.reference == a.reference)
    #expect(await model.acceptDrawingProjection(sibling, operation: {}) == nil)
    #expect(model.projectedDrawing?.executionReference(for: program)?.candidateID == b.reference.digest.description)
    await model.shutdown(); await library.closeLibrary()
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
