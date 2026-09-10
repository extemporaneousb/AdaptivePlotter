import AppKit
import Foundation
import PlotterEpisodeModel
import PlotterUI
import SwiftUI

/// An on-demand copy of existing records and projections. It records no new
/// events and does not claim to be a complete replay archive or ink evidence.
struct WorkbenchDebugSnapshot: Codable, Identifiable {
  struct Transition: Codable {
    let sequence: UInt64
    let source: String
    let request: String
    let result: String
    let before: UInt64
    let after: UInt64
    let currentItem: String
  }
  struct Action: Codable {
    let id: String
    let title: String
    let intent: String
    let unavailableReason: String?
  }
  let id: UUID
  let format: String
  let capturedAt: Date
  let source: String
  let semanticRevision: UInt64
  let uiRevision: UInt64
  let runtimeRevisions: [PlotterUIRuntimeRevision]
  let learningEpisodeID: UUID
  let transitions: [Transition]
  let actions: [Action]
  let diagnostics: [String]
  let limitations: [String]

  @MainActor
  init(application: PlotterApplicationRuntime, projection: PlotterUIProjection) {
    id = UUID()
    format = "adaptiveplotter.debug-snapshot.v1"
    capturedAt = Date()
    source = application.frameMode == .live ? "LIVE" : "SIMULATED"
    semanticRevision = application.semanticPresentationRevision
    uiRevision = projection.revision.rawValue
    runtimeRevisions = projection.runtimeRevisions
    let record = application.learningEpisodeRecord
    learningEpisodeID = record.episodeID.rawValue
    transitions = record.entries.map {
      Transition(
        sequence: $0.sequence, source: $0.environment.rawValue,
        request: String(describing: $0.request), result: String(describing: $0.result),
        before: $0.preStateRevision.rawValue, after: $0.postStateRevision.rawValue,
        currentItem: $0.postTransitionProjection.currentItem.rawValue
      )
    }
    actions = projection.actions.map {
      Action(id: $0.id.rawValue, title: $0.title, intent: String(describing: $0.intent),
             unavailableReason: $0.unavailableReason)
    }
    var details = projection.diagnostics.map(\.summary)
    details += [application.cameraError, application.visionError, application.explorationError,
      application.drawingEvidenceError].compactMap { $0 }
    let border = application.borderValidationSnapshot
    details += border.terminalHistory.map(\.detail)
    details += ["Drawing Border phase: \(border.phase)",
      "Drawing Border step: \(border.step.title)",
      "Drawing outcome: \(String(describing: border.drawingOutcome))", border.inkStatus]
    let drawing = application.drawingStudioPresentation.runState
    details.append("Drawing run: \(drawing.title). \(drawing.detail)")
    for refusal in [application.drawingDraftSnapshot.planningRefusal,
                    application.drawingDraftSnapshot.lastSubmissionRefusal] {
      if let refusal { details.append("Drawing Draft: \(refusal.reason). \(refusal.remedy)") }
    }
    diagnostics = details
    limitations = [
      "Snapshot of current owners and the existing bounded Learning record (up to 128 retained transitions).",
      "Feature journals retain their own identities; no unrelated journals are merged.",
      "Raw controller traffic, camera pixels, audio, and older or in-flight Learning transitions are not included.",
      "This diagnostic snapshot is not a replay archive or a claim of attended physical evidence."
    ]
  }

  func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(self)
  }
}

struct WorkbenchDiagnosticsView: View {
  let snapshot: WorkbenchDebugSnapshot
  @Environment(\.dismiss) private var dismiss
  @State private var exportStatus: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("Diagnostics").font(.title2.bold())
        Spacer()
        Text(snapshot.source).font(.caption.monospaced().bold())
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Text("Runtime \(snapshot.semanticRevision) · UI \(snapshot.uiRevision) · \(snapshot.transitions.count) Learning transitions")
        .font(.callout.monospaced())
      Text("Learning is retained automatically. These details describe the current workflow and its recorded outcomes.")
        .foregroundStyle(.secondary)
      if !snapshot.diagnostics.isEmpty {
        Text(snapshot.diagnostics.joined(separator: "\n"))
          .font(.callout).textSelection(.enabled)
      }
      ScrollView {
        Text((try? snapshot.encoded()).flatMap { String(data: $0, encoding: .utf8) } ?? "Snapshot encoding failed")
          .font(.system(.caption, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(12)
      }
      .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
      HStack {
        Button("Copy Diagnostics", systemImage: "doc.on.doc") { copySnapshot() }
        if let exportStatus { Text(exportStatus).font(.caption).foregroundStyle(.secondary) }
      }
    }
    .padding(20)
    .frame(minWidth: 680, idealWidth: 840, minHeight: 460, idealHeight: 640)
  }

  private func copySnapshot() {
    do {
      let data = try snapshot.encoded()
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(String(decoding: data, as: UTF8.self), forType: .string)
      exportStatus = "Copied"
    } catch { exportStatus = error.localizedDescription }
  }

}
