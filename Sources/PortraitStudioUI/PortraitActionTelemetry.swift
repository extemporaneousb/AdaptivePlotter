import SwiftUI

private struct PortraitActionTelemetryKey: EnvironmentKey {
  static let defaultValue: (String) -> Void = { _ in }
}

extension EnvironmentValues {
  package var portraitActionTelemetry: (String) -> Void {
    get { self[PortraitActionTelemetryKey.self] }
    set { self[PortraitActionTelemetryKey.self] = newValue }
  }
}
