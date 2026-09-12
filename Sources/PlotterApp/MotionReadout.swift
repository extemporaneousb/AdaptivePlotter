import Foundation
import Observation
import PlotterRuntime
import SwiftUI

/// Presentation only: all acquisition, arbitration, monitoring and fault handling
/// remain with the existing controller owner. No UI callback sends a status query.
struct MotionReadoutPresentation: Equatable, Sendable {
  enum Freshness: String, Sendable { case live, stale, unavailable, disconnected }
  static let staleAfterNanoseconds: UInt64 = 2_000_000_000

  let freshness: Freshness
  let receipt: RuntimeTimestamp?
  let sequence: UInt64?
  let connection: String
  let controller: String
  let position: String
  let limits: String
  let commandedPen: String

  init(snapshot: MachineSnapshot?, nowNanoseconds: UInt64) {
    connection = snapshot?.connection.rawValue ?? "unavailable"
    commandedPen = snapshot?.penState.rawValue ?? "unknown"
    guard let snapshot, snapshot.connection != .disconnected else {
      freshness = snapshot == nil ? .unavailable : .disconnected
      receipt = nil
      sequence = nil
      controller = "unavailable"
      position = "unavailable"
      limits = "unavailable"
      return
    }
    guard let sample = snapshot.latestStatusSample else {
      freshness = .unavailable
      receipt = nil
      sequence = nil
      controller = "unavailable"
      position = "unavailable"
      limits = "unavailable"
      return
    }
    receipt = sample.receivedAt
    sequence = sample.sequence
    let received = sample.receivedAt.monotonicNanoseconds
    freshness = nowNanoseconds >= received
      && nowNanoseconds - received <= Self.staleAfterNanoseconds ? .live : .stale
    controller = sample.report.controllerState.rawValue
    if let point = sample.report.machinePosition?.point {
      position = String(format: "X %.3f   Y %.3f", point.x, point.y)
    } else { position = "not reported" }
    limits = sample.report.controllerPins.rawValue.isEmpty
      ? "none reported" : "Pn:\(sample.report.controllerPins.rawValue)"
  }

  var reportDescription: String {
    guard let sequence else { return freshness.rawValue }
    return "\(freshness.rawValue) · report \(sequence)"
  }
}

@MainActor @Observable
final class MotionReadoutModel {
  typealias SnapshotReader = @MainActor @Sendable () async -> MachineSnapshot?
  static let refreshIntervalNanoseconds: UInt64 = 200_000_000
  private(set) var presentation = MotionReadoutPresentation(snapshot: nil, nowNanoseconds: 0)
  private(set) var isRefreshing = false

  /// Called only by the leaf view's visibility-bound task. Cancellation also
  /// rejects an in-flight read, so a hidden pane cannot publish later results.
  func observe(
    reader: SnapshotReader,
    clock: any RuntimeClock = SystemRuntimeClock()
  ) async {
    isRefreshing = true
    defer { isRefreshing = false }
    while !Task.isCancelled {
      let snapshot = await reader()
      guard !Task.isCancelled else { return }
      refresh(snapshot: snapshot, nowNanoseconds: clock.nowNanoseconds())
      do { try await clock.sleep(nanoseconds: Self.refreshIntervalNanoseconds) }
      catch { return }
    }
  }

  func refresh(snapshot: MachineSnapshot?, nowNanoseconds: UInt64) {
    let next = MotionReadoutPresentation(snapshot: snapshot, nowNanoseconds: nowNanoseconds)
    if next != presentation { presentation = next }
  }
}

/// Only this leaf observes numeric samples. Its task is removed along with the
/// native panel's NSHostingView when View > Hide Motion removes pane membership.
struct MotionReadout: View {
  let reader: MotionReadoutModel.SnapshotReader
  @State private var model = MotionReadoutModel()

  var body: some View {
    let value = model.presentation
    VStack(alignment: .leading, spacing: 5) {
      row("Controller report", value.reportDescription)
        .foregroundStyle(value.freshness == .live ? Color.secondary : Color.orange)
      row("Controller link", value.connection)
      row("Controller", value.controller)
      row("MPos", value.position)
      row("Limit inputs", value.limits)
      row("Commanded pen", value.commandedPen)
    }
    .accessibilityIdentifier("motion.readout")
    .help("Controller report receipt determines freshness. Commanded pen state is not physical pose evidence. Last outcomes below are historical.")
    .task { await model.observe(reader: reader) }
  }

  private func row(_ title: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(title).foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
    }.font(.caption.monospaced())
  }
}
