import Foundation
import OSLog
import PlotterUI

/// Bounded metadata at the existing ingress, with no parallel event store.
enum WorkbenchRequestTelemetry {
  private static let logger = Logger(subsystem: "com.adaptiveplotter.app", category: "ui-actions")

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
