import PlotterModel
import PlotterRuntime
import SwiftUI

@main
@MainActor
struct AdaptivePlotterApp: App {
  @State private var workspace = OperatorWorkspace(
    passiveProbeRunner: PassiveProbeComposition.run
  )

  var body: some Scene {
    WindowGroup("AdaptivePlotter") {
      OperatorWorkspaceView(workspace: workspace)
        .frame(minWidth: 1_040, minHeight: 720)
    }
  }
}

struct OperatorWorkspaceView: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    VStack(spacing: 0) {
      productBlockBanner
      AuthorityBar(authority: workspace.authority)

      HStack(alignment: .top, spacing: 10) {
        if workspace.visiblePanes.contains(.devices) {
          DevicePane(workspace: workspace)
            .frame(width: 250)
        }

        VStack(spacing: 10) {
          OfflineModeBanner(state: workspace.simulatorTaskState)
          PrototypeCanvas(
            program: workspace.program,
            correspondence: workspace.correspondence,
            visibleLayers: workspace.visibleLayers
          )
          .frame(minHeight: 330)

          LayerControls(workspace: workspace)
        }
        .frame(maxWidth: .infinity)

        if workspace.visiblePanes.contains(.facts) {
          ExecutionFactsPane(
            authority: workspace.authority,
            frontiers: workspace.frontiers
          )
          .frame(width: 285)
        }
      }
      .padding(10)

      if workspace.visiblePanes.contains(.timeline) {
        TimelinePane(workspace: workspace)
          .frame(minHeight: 150, maxHeight: 210)
          .padding([.horizontal, .bottom], 10)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .toolbar {
      ToolbarItemGroup {
        ForEach(WorkspacePane.allCases) { pane in
          Toggle(
            pane.rawValue,
            isOn: Binding(
              get: { workspace.visiblePanes.contains(pane) },
              set: { workspace.setPane(pane, visible: $0) }
            )
          )
        }
      }
    }
  }

  private var productBlockBanner: some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Text("DRAWING BLOCKED")
        .font(.system(.headline, design: .monospaced, weight: .bold))
      Text("This prototype exposes no motion, pen, unlock, home, settings, or reset action.")
        .font(.callout)
      Spacer()
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color.red.opacity(0.82))
    .accessibilityElement(children: .combine)
  }
}

private struct AuthorityBar: View {
  let authority: ExecutionAuthority

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 18) {
        fact("ALLOWED", authority.allowed ? "YES" : "NO")
        fact("OPERATION", authority.operation.map(operationLabel) ?? "NONE")
        fact("PLAN", short(authority.planID))
        fact("MODEL", short(authority.modelID))
        fact("STATE", short(authority.stateEstimateID))
        Spacer()
      }
      if authority.blockers.isEmpty {
        Text("BLOCKERS: none")
          .font(.caption.monospaced())
      } else {
        ForEach(authority.blockers, id: \.code) { blocker in
          Text("BLOCKER \(blocker.code): \(blocker.summary)")
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
        }
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(alignment: .bottom) { Divider() }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(authorityAccessibilityLabel(authority))
  }

  private func fact(_ name: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(name).font(.caption2).foregroundStyle(.secondary)
      Text(value).font(.caption.monospaced()).textSelection(.enabled)
    }
  }
}

private struct DevicePane: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    SectionPanel(title: "PASSIVE DEVICE") {
      Text("Discovery and interrogation only. Both physical arms remain unavailable and off.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Button("Refresh Serial Devices") {
        workspace.refreshSerialDevices()
      }
      .buttonStyle(.borderedProminent)
      .disabled(workspace.passiveProbeInProgress || workspace.passiveProbeAttempted)

      if workspace.serialDevices.isEmpty {
        Text("No discovered /dev/cu.* serial devices.")
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
      } else {
        ForEach(workspace.serialDevices, id: \.identifier) { device in
          Button {
            workspace.selectSerialDevice(device)
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(device.displayName)
              Text(device.bsdPath ?? device.identifier)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .disabled(workspace.passiveProbeInProgress || workspace.passiveProbeAttempted)
          .padding(6)
          .background(
            workspace.selectedSerialDevice?.identifier == device.identifier
              ? Color.accentColor.opacity(0.18)
              : Color.clear
          )
          .clipShape(RoundedRectangle(cornerRadius: 5))
        }
      }

      Button("Request Passive Probe") {
        Task { await workspace.requestPassiveProbe() }
      }
      .disabled(workspace.passiveProbeUnavailableReason != nil)

      if let reason = workspace.passiveProbeUnavailableReason {
        Text(reason)
          .font(.caption)
          .foregroundStyle(.orange)
      }
      if let failure = workspace.passiveProbeFailure {
        Text("Probe failed: \(failure)")
          .font(.caption.monospaced())
          .foregroundStyle(.red)
          .textSelection(.enabled)
      }
      if let receipt = workspace.passiveProbeReceipt {
        ProbeSummary(receipt: receipt)
      }

      Divider()
      Text("MOTION ARM  UNAVAILABLE / OFF")
        .font(.caption.monospaced())
      Text("PEN ARM     UNAVAILABLE / OFF")
        .font(.caption.monospaced())

      Divider()
      Button("Run Deterministic Offline Replay") {
        Task { await workspace.runOfflinePrototype() }
      }
      .disabled(workspace.simulatorTaskState == .running)
    }
  }
}

private struct ProbeSummary: View {
  let receipt: PassiveProbeRunReceipt

  private var result: PassiveProbeResult { receipt.probe }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("PROBE RESULT")
        .font(.caption.bold())
      Text(result.link.bsdPath ?? result.link.identifier)
        .font(.caption2.monospaced())
        .textSelection(.enabled)
      Text("Exchanges: \(result.exchanges.count) · blockers: \(result.blockers.count)")
        .font(.caption)
      Text(
        "Completion authority receipt: "
          + "\(receipt.completionAuthority.authority.allowed ? "allowed" : "blocked")"
          + " · "
          + "\(receipt.completionAuthority.authority.operation.map(operationLabel) ?? "none")"
      )
      .font(.caption2.monospaced())
      .foregroundStyle(
        receipt.completionAuthority.authority.allowed ? Color.secondary : Color.orange
      )
      Text("One-shot link disconnected after this receipt was captured.")
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text("Ledger: \(receipt.ledgerURL.path)")
        .font(.caption2.monospaced())
        .textSelection(.enabled)
      ForEach(Array(result.blockers.enumerated()), id: \.offset) { entry in
        Text(machineBlockerLabel(entry.element))
          .font(.caption2.monospaced())
          .foregroundStyle(.orange)
      }
    }
  }
}

private struct OfflineModeBanner: View {
  let state: SimulatorUITaskState

  var body: some View {
    HStack {
      Image(systemName: "play.rectangle.on.rectangle")
      Text("OFFLINE SIMULATION / RECORDED REPLAY — NOT PHYSICAL EVIDENCE")
        .font(.caption.monospaced().bold())
      Spacer()
      Text(taskLabel)
        .font(.caption.monospaced())
    }
    .padding(8)
    .foregroundStyle(.yellow)
    .background(Color.black.opacity(0.86))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .accessibilityElement(children: .combine)
  }

  private var taskLabel: String {
    switch state {
    case .idle: "fixture loaded"
    case .running: "replaying…"
    case let .complete(sequence): "replayed through event \(sequence)"
    case let .failed(reason): "failed: \(reason)"
    }
  }
}

private struct LayerControls: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    HStack(spacing: 14) {
      Text("LAYERS").font(.caption2).foregroundStyle(.secondary)
      ForEach(CanvasLayer.allCases) { layer in
        Toggle(
          layer.rawValue,
          isOn: Binding(
            get: { workspace.visibleLayers.contains(layer) },
            set: { workspace.setLayer(layer, visible: $0) }
          )
        )
        .toggleStyle(.checkbox)
        .font(.caption)
      }
      Spacer()
    }
  }
}

private struct PrototypeCanvas: View {
  let program: DrawingProgram
  let correspondence: CorrespondedGeometry
  let visibleLayers: Set<CanvasLayer>

  var body: some View {
    GeometryReader { proxy in
      Canvas { context, size in
        let transform = PreviewTransform(field: program.fieldExtent, size: size)
        let border = Path(
          CGRect(
            x: transform.margin,
            y: transform.margin,
            width: transform.drawWidth,
            height: transform.drawHeight
          ))
        context.stroke(border, with: .color(.blue), lineWidth: 2)

        if visibleLayers.contains(.logical) {
          context.stroke(
            path(correspondence.intended, transform: transform),
            with: .color(.cyan),
            style: SwiftUI.StrokeStyle(lineWidth: 2)
          )
        }
        if visibleLayers.contains(.predicted) {
          context.stroke(
            path(correspondence.predicted, transform: transform),
            with: .color(.purple),
            style: SwiftUI.StrokeStyle(lineWidth: 2, dash: [8, 5])
          )
        }
        if visibleLayers.contains(.observed) {
          context.stroke(
            path(correspondence.observed, transform: transform),
            with: .color(.white),
            style: SwiftUI.StrokeStyle(lineWidth: 4)
          )
        }
        if visibleLayers.contains(.residuals) {
          for (predicted, observed) in zip(
            correspondence.predicted.points,
            correspondence.observed.points
          ) {
            var residual = Path()
            residual.move(to: transform.point(predicted))
            residual.addLine(to: transform.point(observed))
            context.stroke(residual, with: .color(.orange), lineWidth: 1.5)
          }
        }
      }
      .background(Color(nsColor: .textBackgroundColor).opacity(0.16))
      .overlay(alignment: .topLeading) {
        Text(
          "FIELDSPACE \(program.fieldExtent.width, specifier: "%.0f") × \(program.fieldExtent.height, specifier: "%.0f") nominal mm"
        )
        .font(.caption2.monospaced())
        .padding(8)
        .foregroundStyle(.secondary)
      }
      .overlay(alignment: .bottomLeading) {
        Text(
          "Cyan solid: logical · purple dashed: predicted · white: SIMULATED observation · orange: residual"
        )
        .font(.caption2)
        .padding(8)
        .background(.black.opacity(0.65))
        .foregroundStyle(.white)
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(canvasAccessibilityLabel)
    }
  }

  private func path(_ polyline: Polyline<FieldSpace>, transform: PreviewTransform) -> Path {
    var path = Path()
    guard let first = polyline.points.first else { return path }
    path.move(to: transform.point(first))
    for point in polyline.points.dropFirst() { path.addLine(to: transform.point(point)) }
    return path
  }

  private var canvasAccessibilityLabel: String {
    "Offline canvas. Logical, predicted, and simulated observed polylines. "
      + "The simulated observation is not physical ink evidence."
  }
}

private struct PreviewTransform {
  let field: Size2<FieldSpace>
  let size: CGSize
  let margin: CGFloat = 28

  var drawWidth: CGFloat { max(size.width - 2 * margin, 1) }
  var drawHeight: CGFloat { max(size.height - 2 * margin, 1) }

  func point(_ point: Point2<FieldSpace>) -> CGPoint {
    CGPoint(
      x: margin + CGFloat(point.x / field.width) * drawWidth,
      y: margin + CGFloat(1 - point.y / field.height) * drawHeight
    )
  }
}

private struct ExecutionFactsPane: View {
  let authority: ExecutionAuthority
  let frontiers: ExecutionFrontiers

  var body: some View {
    SectionPanel(title: "LITERAL EXECUTION FACTS") {
      literal("commanded", cursorLabel(frontiers.commandedThrough))
      literal("controller completed", cursorLabel(frontiers.controllerCompletedThrough))
      Text("Controller completed is not physical or ink verification.")
        .font(.caption)
        .foregroundStyle(.orange)

      Divider()
      Text("INK FACTS").font(.caption2).foregroundStyle(.secondary)
      if frontiers.inkBySlice.isEmpty {
        Text("none").font(.caption.monospaced())
      } else {
        ForEach(frontiers.inkBySlice.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
          VStack(alignment: .leading, spacing: 2) {
            Text("slice \(short(entry.key))")
              .font(.caption2.monospaced())
            Text(inkDispositionLabel(entry.value.disposition))
              .font(.caption.monospaced())
              .foregroundStyle(inkDispositionColor(entry.value.disposition))
          }
        }
      }

      Divider()
      Text("AUTHORITY LIMITS").font(.caption2).foregroundStyle(.secondary)
      literal("feed", "\(authority.limits.maximumFeed)")
      literal("distance", "\(authority.limits.maximumDistance)")
      literal("horizon ns", "\(authority.limits.maximumCommandHorizonNanoseconds)")
      literal("safety", short(authority.fixedSafetyPolicyID))
      literal("evidence IDs", "\(authority.evidence.count)")
    }
  }

  private func literal(_ name: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(name).font(.caption).foregroundStyle(.secondary)
      Spacer()
      Text(value).font(.caption.monospaced()).textSelection(.enabled)
    }
  }
}

private struct TimelinePane: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    SectionPanel(title: "PASSIVE / RECORDED EVENT TIMELINE") {
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 8) {
          ForEach(workspace.replayEvents, id: \.sequence) { event in
            timelineCard(
              sequence: event.sequence,
              title: recordedEventTitle(event.event),
              detail: recordedEventDetail(event.event),
              selection: .event(event.sequence)
            )
          }
          if let probe = workspace.passiveProbeResult {
            ForEach(probeTimelineEntries(probe)) { entry in
              timelineCard(
                sequence: nil,
                title: entry.title,
                detail: entry.detail,
                selection: nil
              )
            }
          }
        }
      }
      .scrollIndicators(.visible)
    }
  }

  private func timelineCard(
    sequence: UInt64?,
    title: String,
    detail: String,
    selection: WorkspaceSelection?
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(sequence.map { "#\($0)  \(title)" } ?? title)
        .font(.caption.bold())
      ScrollView(.vertical) {
        Text(detail)
          .font(.caption2.monospaced())
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
      }
      .frame(maxHeight: 180)
    }
    .frame(width: 320, alignment: .leading)
    .padding(8)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay {
      RoundedRectangle(cornerRadius: 5)
        .stroke(isSelected(selection) ? Color.accentColor : Color.secondary.opacity(0.25))
    }
    .contentShape(Rectangle())
    .onTapGesture {
      if let selection { workspace.selection = selection }
    }
  }

  private func isSelected(_ selection: WorkspaceSelection?) -> Bool {
    guard let selection else { return false }
    return workspace.selection == selection
  }
}

private struct SectionPanel<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.monospaced().bold())
        .foregroundStyle(.secondary)
      content
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .padding(10)
    .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}

private struct ProbeTimelineEntry: Identifiable {
  let id: String
  let title: String
  let detail: String
}

private func probeTimelineEntries(_ result: PassiveProbeResult) -> [ProbeTimelineEntry] {
  result.exchanges.flatMap { exchange in
    exchange.rawIO.enumerated().map { index, io in
      let direction = io.direction == .transmit ? "TX" : "RX"
      let payload = String(decoding: io.bytes, as: UTF8.self)
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\n", with: "\\n")
      let hex = io.bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
      return ProbeTimelineEntry(
        id: "\(exchange.commandID.uuidString)-\(index)",
        title: "PASSIVE \(direction) · \(exchange.query.rawValue)",
        detail: "escaped UTF-8\n\(payload)\n\nexact hex\n\(hex)"
      )
    }
  }
}

private func recordedEventTitle(_ event: RecordedRunEvent) -> String {
  switch event {
  case .runStarted: "RUN STARTED"
  case .authorityChanged: "AUTHORITY"
  case .instructionAdvanced: "INSTRUCTION"
  case .frontiersChanged: "FRONTIERS"
  case .checkpointResolved: "CHECKPOINT"
  case .successorPlanActivated: "SUCCESSOR PLAN"
  case .paused: "PAUSED"
  case .completed: "COMPLETE"
  case .aborted: "ABORTED"
  }
}

private func recordedEventDetail(_ event: RecordedRunEvent) -> String {
  switch event {
  case let .runStarted(_, planID, modelID, authority, _):
    "plan \(short(planID)) · model \(short(modelID)) · allowed \(authority.allowed)"
  case let .authorityChanged(authority):
    "allowed \(authority.allowed) · operation \(authority.operation.map(operationLabel) ?? "NONE")"
  case let .instructionAdvanced(cursor):
    cursorLabel(cursor)
  case let .frontiersChanged(frontiers):
    "commanded \(cursorLabel(frontiers.commandedThrough)) · controller completed \(cursorLabel(frontiers.controllerCompletedThrough))"
  case let .checkpointResolved(resolution):
    "resolution \(short(resolution.id))"
  case let .successorPlanActivated(activation):
    "plan \(short(activation.planID)) · model \(short(activation.modelID))"
      + " · allowed \(activation.authority.allowed)"
  case let .paused(blockers):
    blockers.map { "\($0.code): \($0.summary)" }.joined(separator: " · ")
  case .completed:
    "recorded run completed"
  case let .aborted(reason):
    reason
  }
}

private func operationLabel(_ operation: AuthorizedOperation) -> String {
  switch operation {
  case .passiveInterrogation: "passiveInterrogation"
  case .boundedPenUpTrial: "boundedPenUpTrial"
  case .isolatedTrainingProbe: "isolatedTrainingProbe"
  case .generalDrawing: "generalDrawing"
  }
}

private func cursorLabel(_ cursor: PlanCursor?) -> String {
  guard let cursor else { return "none" }
  return "instruction \(cursor.instructionIndex), command \(cursor.commandIndex)"
}

private func inkDispositionLabel(_ disposition: InkDisposition) -> String {
  switch disposition {
  case .awaitingInspection:
    "AWAITING INSPECTION"
  case let .verified(observationID):
    "INK VERIFIED · observation \(short(observationID))"
  case let .failed(evidenceID, reasons):
    "INK FAILED · evidence \(short(evidenceID)) · \(reasons.joined(separator: "; "))"
  case let .ambiguous(reasons):
    "AMBIGUOUS · \(reasons.joined(separator: "; "))"
  case let .operatorSkipped(reason):
    "OPERATOR SKIPPED · \(reason)"
  }
}

private func inkDispositionColor(_ disposition: InkDisposition) -> Color {
  switch disposition {
  case .verified: .green
  case .awaitingInspection: .yellow
  case .failed, .ambiguous, .operatorSkipped: .orange
  }
}

private func machineBlockerLabel(_ blocker: MachineBlocker) -> String {
  switch blocker {
  case .noSerialDevice: "noSerialDevice"
  case let .multipleSerialDevices(devices): "multipleSerialDevices(\(devices.count))"
  case let .transport(reason): "transport: \(reason)"
  case let .timeout(query): "timeout: \(query.rawValue)"
  case let .invalidReply(query, reason): "invalidReply(\(query.rawValue)): \(reason)"
  case let .responseLimitExceeded(query, maximumBytes, maximumChunks):
    "responseLimitExceeded(\(query.rawValue)): \(maximumBytes) bytes / \(maximumChunks) chunks"
  case let .storage(reason): "storage: \(reason)"
  case let .controllerAlarm(code): "controllerAlarm: \(code)"
  case let .controllerError(code): "controllerError: \(code)"
  }
}

private func authorityAccessibilityLabel(_ authority: ExecutionAuthority) -> String {
  let operation = authority.operation.map(operationLabel) ?? "none"
  let blockers =
    authority.blockers.isEmpty
    ? "no blockers"
    : authority.blockers.map { "\($0.code), \($0.summary)" }.joined(separator: ". ")
  return "Authority allowed \(authority.allowed). Operation \(operation). \(blockers)."
}

private func short<Tag>(_ id: StrongID<Tag>?) -> String {
  guard let id else { return "none" }
  return String(id.description.prefix(8))
}

private func short<Tag>(_ id: StrongID<Tag>) -> String {
  String(id.description.prefix(8))
}
