import Foundation
import PlotterEpisodeModel
import PlotterUI
import Testing
@testable import PlotterApp

@Suite("Workbench diagnostic snapshots", .serialized)
@MainActor
struct WorkbenchDiagnosticsTests {
  @Test("snapshot exports the existing record and exact refusal without creating events")
  func snapshotUsesExistingOwners() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: .humanGuidedDiscovery(.penInteraction), includesLearningPath: true
    ).semantic
    let stale = PlotterUIRequest(
      id: .init(rawValue: UUID()), uiRevision: .init(rawValue: projection.revision.rawValue &+ 1),
      runtimeRevisions: projection.runtimeRevisions,
      actionID: .init(rawValue: "obsolete-voice-choice"),
      intent: .learningAction(.init(item: .init(rawValue: "pen"), action: .choice(.yes)))
    )
    guard case .refused = await workspace.submitPlotterUIRequest(stale) else {
      Issue.record("Stale request unexpectedly accepted")
      await workspace.shutdown()
      return
    }
    let record = workspace.learningEpisodeRecord
    let beforeRevision = workspace.semanticPresentationRevision
    let snapshot = WorkbenchDebugSnapshot(application: workspace, projection: projection)
    let encoded = try snapshot.encoded()
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: encoded)
    #expect(decoded["format"] == .string("adaptiveplotter.debug-snapshot.v1"))
    #expect(snapshot.learningEpisodeID == record.episodeID.rawValue)
    #expect(snapshot.transitions.map(\.sequence) == record.entries.map(\.sequence))
    #expect(snapshot.transitions.last?.result.contains("staleUIRevision") == true)
    #expect(snapshot.runtimeRevisions == projection.runtimeRevisions)
    #expect(snapshot.actions.count == projection.actions.count)
    #expect(snapshot.limitations.contains { $0.contains("not a replay archive") })
    #expect(workspace.learningEpisodeRecord.entries == record.entries)
    #expect(workspace.semanticPresentationRevision == beforeRevision)
    await workspace.shutdown()
  }

  @Test("empty session diagnostics remain exportable and declare omitted evidence")
  func emptySessionCanBeDebugged() async throws {
    let workspace = makeCausalSimulatorAppFixture().workspace
    let projection = workspace.testPlotterUIProjection(
      selectedItemID: .humanGuidedDiscovery(.penInteraction), includesLearningPath: true
    ).semantic
    let snapshot = WorkbenchDebugSnapshot(application: workspace, projection: projection)
    #expect(snapshot.transitions.isEmpty)
    #expect(try !snapshot.encoded().isEmpty)
    #expect(snapshot.actions.contains { $0.unavailableReason != nil })
    #expect(snapshot.limitations.contains { $0.contains("camera pixels") })
    await workspace.shutdown()
  }
}

private enum JSONValue: Decodable, Equatable {
  case string(String), other
  init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer()
    if let text = try? value.decode(String.self) { self = .string(text) }
    else { self = .other }
  }
}
