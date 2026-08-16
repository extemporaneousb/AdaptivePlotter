import SwiftUI

enum OperatorButtonRole: CaseIterable, Hashable, Sendable {
  case affirmative
  case negative
  case neutral

  func chrome(isEnabled: Bool) -> OperatorButtonChrome {
    guard isEnabled else { return .disabled }
    switch self {
    case .affirmative: return .affirmative
    case .negative: return .negative
    case .neutral: return .neutralEnabled
    }
  }
}

enum OperatorButtonChrome: Hashable, Sendable {
  case affirmative
  case negative
  case neutralEnabled
  case disabled

  fileprivate var backgroundColor: Color {
    switch self {
    case .affirmative: .green
    case .negative: .red
    case .neutralEnabled: Color(red: 0.46, green: 0.48, blue: 0.51)
    case .disabled: Color(red: 0.20, green: 0.21, blue: 0.23)
    }
  }

  fileprivate var foregroundColor: Color {
    switch self {
    case .disabled: Color.white.opacity(0.42)
    default: .white
    }
  }

  fileprivate var borderColor: Color {
    switch self {
    case .disabled: Color.white.opacity(0.08)
    default: Color.white.opacity(0.24)
    }
  }
}

struct OperatorButtonStyle: ButtonStyle {
  let role: OperatorButtonRole

  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize

  func makeBody(configuration: Configuration) -> some View {
    let chrome = role.chrome(isEnabled: isEnabled)
    configuration.label
      .fontWeight(role == .neutral ? .medium : .semibold)
      .foregroundStyle(chrome.foregroundColor)
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(
        chrome.backgroundColor.opacity(configuration.isPressed && isEnabled ? 0.72 : 1),
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(chrome.borderColor, lineWidth: 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
      .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
  }

  private var horizontalPadding: CGFloat {
    controlSize == .small || controlSize == .mini ? 8 : 11
  }

  private var verticalPadding: CGFloat {
    controlSize == .small || controlSize == .mini ? 4 : 6
  }

  private var cornerRadius: CGFloat {
    controlSize == .small || controlSize == .mini ? 5 : 7
  }
}

extension View {
  /// Applies the one operator-control color grammar and couples disabled chrome
  /// to actual SwiftUI interaction admission.
  func operatorButton(
    _ role: OperatorButtonRole = .neutral,
    isEnabled: Bool = true
  ) -> some View {
    buttonStyle(OperatorButtonStyle(role: role))
      .disabled(!isEnabled)
  }
}
