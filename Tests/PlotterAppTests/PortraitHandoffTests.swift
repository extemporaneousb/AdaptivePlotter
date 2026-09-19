import Foundation
import PlotterModel
import PlotterUI
import Testing
@testable import PlotterApp

@Suite("Portrait immutable drawing handoff", .serialized)
@MainActor
struct PortraitHandoffTests {
  @Test("Re-showing the same artwork retains placement with and without a border", arguments: [false, true])
  func repeatedHandoffPreservesPlacement(drawBorder: Bool) async throws {
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let app = fixture.application
    do {
      let candidate = try portraitPersistenceCandidate(seed: 410)
      #expect(await app.projectPortrait(candidate) == nil)
      if drawBorder { try await fixture.submit(.setDrawBorder(true)) }
      let fittedScale = app.drawingDraftSnapshot.uniformScale
      try await fixture.submit(.setUniformScale(floor(fittedScale * 70) / 100))
      try await fixture.submit(.setRotationDegrees(19))
      let placement = try #require(app.drawingDraftSnapshot.artworkPlan?.placement)
      let plan = try #require(app.drawingDraftSnapshot.artworkPlan?.contentHash)
      let executionPlan = app.drawingDraftSnapshot.plan?.contentHash
      try await fixture.submit(.hideTarget)
      #expect(await app.projectPortrait(candidate) == nil)
      #expect(app.drawingTargetIsVisible)
      #expect(app.drawingDraftSnapshot.artworkPlan?.placement == placement)
      #expect(app.drawingDraftSnapshot.artworkPlan?.contentHash == plan)
      #expect(app.drawingDraftSnapshot.plan?.contentHash == executionPlan)
      #expect(app.drawingDraftSnapshot.drawBorder == drawBorder)
      #expect(app.portraitStudio.projectedReference(for: candidate.program)?.candidateID == candidate.id)
      await app.shutdown()
    } catch { await app.shutdown(); throw error }
  }
}
