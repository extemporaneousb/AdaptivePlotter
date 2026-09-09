import Foundation
import AppKit
import OSLog
import PlotterUI

/// Bounded metadata at the existing ingress, with no parallel event store.
enum WorkbenchRequestTelemetry {
  private static let logger = Logger(subsystem: "com.adaptiveplotter.app", category: "ui-actions")

  /// Installed only by the opt-in signed-app gate. This observes a real native
  /// control handler; it does not synthesize an action or retain an event log.
  @MainActor static var nativeActionObserver: ((String, TimeInterval?) -> Void)?

  @MainActor static func nativeActionHandled(_ identifier: String) {
    nativeActionObserver?(identifier, NSApplication.shared.currentEvent?.timestamp)
  }

  static func received(_ request: PlotterUIRequest, title: String) {
    logger.info("UI received request=\(request.id.rawValue.uuidString, privacy: .public) action=\(title, privacy: .public) revision=\(request.uiRevision.rawValue)")
  }

  static func finished(_ request: PlotterUIRequest, title: String,
    disposition: PlotterUIRequestDisposition, duration: Duration) {
    let seconds = Double(duration.components.seconds)
      + Double(duration.components.attoseconds) / 1e18
    switch disposition {
    case .accepted:
      logger.info("UI accepted request=\(request.id.rawValue.uuidString, privacy: .public) action=\(title, privacy: .public) elapsed_ms=\(seconds * 1000)")
    case .refused(let refusal):
      logger.error("UI refused request=\(request.id.rawValue.uuidString, privacy: .public) action=\(title, privacy: .public) elapsed_ms=\(seconds * 1000) reason=\(refusal.reason.rawValue, privacy: .public) owner=\(refusal.owner, privacy: .public)")
    }
  }

  static func phase(_ title: String, isStarting: Bool) {
    logger.info("Displayed computation phase=\(title, privacy: .public) starting=\(isStarting)")
  }
}
