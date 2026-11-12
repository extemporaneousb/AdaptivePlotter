import PlotterModel
import SwiftUI

/// Execution-owned run navigation, independent of artwork authoring identities.
struct DrawingExecutionHistoryView: View {
  let application: PlotterApplicationRuntime
  let close: () -> Void
  @State private var selectedRun: RunID?
  var body: some View {
    VStack {
      HStack { Text("Execution history").font(.title2); Spacer(); Button("Close", action: close) }
      HSplitView {
        List(application.drawingReviewRecords.reversed(), id: \.recordID) { record in
          Button { selectedRun = record.runID } label: {
            VStack(alignment: .leading) {
              Text("Run " + record.runID.rawValue.uuidString.prefix(8))
              Text(String(describing: record.executionDisposition)).font(.caption).foregroundStyle(.secondary)
            }
          }.buttonStyle(.plain)
        }.frame(minWidth: 200, idealWidth: 260)
        ScrollView {
          if let record = application.drawingReviewRecords.first(where: { $0.runID == selectedRun }) {
            DrawingRunHistoryDetail(application: application, record: record).id(record.recordID)
          } else {
            Text("Select a run to inspect its retained evidence and export the result.").foregroundStyle(.secondary).padding()
          }
        }.frame(minWidth: 400)
      }
    }.padding().accessibilityIdentifier("drawing.executionHistory")
  }
}
