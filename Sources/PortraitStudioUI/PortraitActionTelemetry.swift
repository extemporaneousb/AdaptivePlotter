import SwiftUI

private struct PortraitActionTelemetryKey: EnvironmentKey {
  static let defaultValue: @MainActor @Sendable (String) -> Void = { _ in }
}

extension EnvironmentValues {
  package var portraitActionTelemetry: @MainActor @Sendable (String) -> Void {
    get { self[PortraitActionTelemetryKey.self] }
    set { self[PortraitActionTelemetryKey.self] = newValue }
  }
}
