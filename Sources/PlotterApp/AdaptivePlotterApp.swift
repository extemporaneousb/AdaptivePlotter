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
      capabilityBanner
      CurrentStatusBar(workspace: workspace)

      HStack(alignment: .top, spacing: 10) {
        DevicePane(workspace: workspace)
          .frame(width: 250)

        VStack(spacing: 10) {
          Text("STATIC SIMULATED PREVIEW — NOT HARDWARE")
            .font(.caption.monospaced().bold())
            .foregroundStyle(.yellow)
          PrototypeCanvas(
            program: workspace.program,
            correspondence: workspace.correspondence,
            visibleLayers: workspace.visibleLayers
          )
          .frame(minHeight: 330)

          LayerControls(workspace: workspace)
        }
        .frame(maxWidth: .infinity)
      }
      .padding(10)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var capabilityBanner: some View {
    HStack(alignment: .firstTextBaseline, spacing: 14) {
      Text("PASSIVE PROBE BUILD")
        .font(.system(.headline, design: .monospaced, weight: .bold))
      Text("Controller interrogation is available. Motion, pen, and camera are the next work.")
        .font(.callout)
      Spacer()
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color.blue.opacity(0.78))
  }
}

private struct CurrentStatusBar: View {
  @Bindable var workspace: OperatorWorkspace

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 18) {
        fact("STATUS", status)
        fact("LAST PROBE", probeStatus)
        Spacer()
      }
      if let failure = workspace.passiveProbeFailure {
        Text(failure)
          .font(.caption.monospaced())
          .foregroundStyle(.orange)
      } else if let blockers = workspace.passiveProbeResult?.blockers, !blockers.isEmpty {
        ForEach(Array(blockers.enumerated()), id: \.offset) { entry in
          Text(machineBlockerLabel(entry.element))
            .font(.caption.monospaced())
            .foregroundStyle(.orange)
        }
      } else {
        Text("No current error")
          .font(.caption.monospaced())
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
    .background(Color(nsColor: .controlBackgroundColor))
    .overlay(alignment: .bottom) { Divider() }
  }

  private var status: String {
    if workspace.passiveProbeInProgress { return "PROBING" }
    if workspace.passiveProbeFailure != nil { return "PROBE FAILED" }
    if workspace.passiveProbeResult?.blockers.isEmpty == false { return "NEEDS ATTENTION" }
    if workspace.passiveProbeResult != nil { return "PROBE COMPLETE" }
    return "SELECT DEVICE"
  }

  private var probeStatus: String {
    guard let result = workspace.passiveProbeResult else { return "NONE" }
    return result.blockers.isEmpty ? "SUCCESS" : "FAILED"
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
      Text("Discovery and interrogation only. This build has no motion or pen commands.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Button("Refresh Serial Devices") {
        workspace.refreshSerialDevices()
      }
      .buttonStyle(.borderedProminent)
      .disabled(workspace.passiveProbeInProgress)

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
          .disabled(workspace.passiveProbeInProgress)
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
      Text(result.blockers.isEmpty ? "Completion: success" : "Completion: needs attention")
        .font(.caption2.monospaced())
        .foregroundStyle(result.blockers.isEmpty ? Color.secondary : Color.orange)
      Text("Link disconnected after this probe. You may run another probe.")
        .font(.caption2)
        .foregroundStyle(.secondary)
      if let ledgerURL = receipt.ledgerURL {
        Text("Session log: \(ledgerURL.path)")
          .font(.caption2.monospaced())
          .textSelection(.enabled)
      } else {
        Text("Session logging unavailable; probe continued.")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      ForEach(result.exchanges, id: \.commandID) { exchange in
        Text(
          "\(exchange.query.rawValue): \(exchange.lines.count) parsed lines · "
            + "\(exchange.rawIO.count) I/O records"
        )
        .font(.caption2.monospaced())
      }
      ForEach(Array(result.blockers.enumerated()), id: \.offset) { entry in
        Text(machineBlockerLabel(entry.element))
          .font(.caption2.monospaced())
          .foregroundStyle(.orange)
      }
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
    }
  }

  private func path(_ polyline: Polyline<FieldSpace>, transform: PreviewTransform) -> Path {
    var path = Path()
    guard let first = polyline.points.first else { return path }
    path.move(to: transform.point(first))
    for point in polyline.points.dropFirst() { path.addLine(to: transform.point(point)) }
    return path
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

private func machineBlockerLabel(_ blocker: MachineBlocker) -> String {
  switch blocker {
  case .noSerialDevice: "noSerialDevice"
  case let .multipleSerialDevices(devices): "multipleSerialDevices(\(devices.count))"
  case let .transport(reason): "transport: \(reason)"
  case let .timeout(query): "timeout: \(query.rawValue)"
  case let .invalidReply(query, reason): "invalidReply(\(query.rawValue)): \(reason)"
  case let .responseLimitExceeded(query, maximumBytes, maximumChunks):
    "responseLimitExceeded(\(query.rawValue)): \(maximumBytes) bytes / \(maximumChunks) chunks"
  case let .controllerAlarm(code): "controllerAlarm: \(code)"
  case let .controllerError(code): "controllerError: \(code)"
  }
}
