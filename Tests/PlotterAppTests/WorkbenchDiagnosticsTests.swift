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
  @Test("background export writes the captured identity once and reports file failures")
  func backgroundFileExport() async throws {
    let application = makeCausalSimulatorAppFixture().workspace
    let capture = WorkbenchDiagnosticCapture(application: application,
      projection: application.testPlotterUIProjection(includesLearningPath: true).semantic)
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let exporter = WorkbenchDiagnosticExporter(directory: directory)
    exporter.export(capture)
    #expect(exporter.isExporting)
    exporter.export(capture) // Repeated clicks while writing cannot enqueue more work.
    try await awaitExport(exporter)
    let url = try #require(exporter.savedURL)
    #expect(url.deletingLastPathComponent().path == directory.path)
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let snapshot = try decoder.decode(WorkbenchDebugSnapshot.self, from: Data(contentsOf: url))
    #expect(snapshot.id == capture.id)
    #expect(snapshot.uiRevision == capture.projection.revision.rawValue)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).count == 1)
    let failure = WorkbenchDiagnosticExporter(directory: url)
    failure.export(capture) // An existing file cannot be used as a directory.
    try await awaitExport(failure)
    #expect(failure.savedURL == nil)
    #expect(failure.status?.contains("failed") == true)
    await application.shutdown()
  }

  @Test("a held file writer leaves the main actor and pane controls responsive")
  func heldFileWriterDoesNotBlockUI() async throws {
    let application = makeCausalSimulatorAppFixture().workspace
    let capture = WorkbenchDiagnosticCapture(application: application,
      projection: application.testPlotterUIProjection(includesLearningPath: true).semantic)
    let gate = DiagnosticWriteGate()
    let exporter = WorkbenchDiagnosticExporter(write: { _, directory in
      await gate.wait()
      return directory.appendingPathComponent("held.json")
    })
    exporter.export(capture)
    await gate.waitUntilEntered()
    #expect(exporter.isExporting)
    var layout = WorkbenchLayoutState(presented: [])
    for panel in WorkbenchPanel.allCases { layout.setPresented(panel, true) }
    #expect(layout.isPresented(.portraitStudio))
    #expect(application.semanticPresentationRevision == capture.semanticRevision)
    await gate.release()
    try await awaitExport(exporter)
    #expect(exporter.savedURL?.lastPathComponent == "held.json")
    await application.shutdown()
  }

  private func awaitExport(_ exporter: WorkbenchDiagnosticExporter) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while exporter.isExporting {
      guard ContinuousClock.now < deadline else { throw DiagnosticWaitFailure() }
      try await Task.sleep(for: .milliseconds(5))
    }
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

private struct DiagnosticWaitFailure: Error {}
private actor DiagnosticWriteGate {
  var continuation: CheckedContinuation<Void, Never>?
  var entered = false
  func wait() async {
    await withCheckedContinuation { continuation in
      self.continuation = continuation
      entered = true
    }
  }
  func waitUntilEntered() async {
    while !entered { await Task.yield() }
  }
  func release() { continuation?.resume(); continuation = nil }
}
