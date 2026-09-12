import SwiftUI
import Observation
import PlotterEpisodeModel
import PlotterUI

enum OperatorButtonRole: CaseIterable, Hashable, Sendable {
  case affirmative
  case negative
  case neutral
  case stop

  func chrome(isEnabled: Bool) -> OperatorButtonChrome {
    guard isEnabled else { return .disabled }
    switch self {
    case .affirmative, .negative: return .neutralEnabled
    case .stop: return .stop
    case .neutral: return .neutralEnabled
    }
  }
}

enum OperatorButtonChrome: Hashable, Sendable {
  case stop
  case neutralEnabled
  case disabled

  fileprivate var backgroundColor: Color {
    switch self {
    case .stop: .red
    case .neutralEnabled: Color(nsColor: .controlColor)
    case .disabled: Color(nsColor: .controlBackgroundColor)
    }
  }

  fileprivate var foregroundColor: Color {
    switch self {
    case .disabled: .secondary
    case .stop: .white
    case .neutralEnabled: .primary
    }
  }

  fileprivate var borderColor: Color {
    switch self {
    case .disabled: Color.primary.opacity(0.08)
    default: Color.primary.opacity(0.24)
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
        chrome.backgroundColor,
        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(configuration.isPressed ? Color.primary.opacity(0.18) : .clear)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .stroke(configuration.isPressed ? Color.primary.opacity(0.65) : chrome.borderColor,
            lineWidth: configuration.isPressed ? 2 : 1)
      }
      .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
      .offset(y: configuration.isPressed && isEnabled ? 1 : 0)
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


extension PlotterLearningAction {
  var isImmediateStop: Bool {
    switch self {
    case .stop, .stopPenInteraction, .boundary(.stop): true
    default: false
    }
  }
}

extension PlotterUIAction {
  var isLearningStop: Bool {
    guard case .learningAction(let request) = intent else { return false }
    return request.action.isImmediateStop
  }
}

extension PlotterUILearningActionDecision {
  /// View identity is independent of an operation's cancellation capability.
  /// The latest exact request remains the value dispatched by the control.
  var controlIdentity: String {
    request.action.isImmediateStop ? "\(request.item.rawValue).stop" : "\(request.item.rawValue).\(title)"
  }
}

@MainActor @Observable
final class OperatorRequestFeedback {
  private(set) var isPending = false
  private(set) var result: String?
  private(set) var wasAccepted = false
  private(set) var startedAt: Date?

  /// Latch synchronously at mouse-up, before scheduling the asynchronous sink.
  func begin() -> Bool {
    guard !isPending else { return false }
    isPending = true
    startedAt = Date()
    result = nil
    wasAccepted = false
    return true
  }

  func finish(_ disposition: PlotterUIRequestDisposition) {
    isPending = false
    startedAt = nil
    switch disposition {
    case .accepted: wasAccepted = true; result = "Accepted"
    case .refused(let refusal): wasAccepted = false; result = refusal.remedy
    }
  }
}

struct OperatorRequestButton: View {
  let title: String
  var role: OperatorButtonRole = .neutral
  let request: PlotterUIRequest?
  let unavailableReason: String?
  let sink: any PlotterUIIntentSink
  var expands = false
  var nativeActionIdentifier: String? = nil
  var showsUnavailableReason = true
  @State private var feedback = OperatorRequestFeedback()

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        guard let request, feedback.begin() else { return }
        if let nativeActionIdentifier {
          WorkbenchRequestTelemetry.nativeActionHandled(nativeActionIdentifier)
        }
        Task { feedback.finish(await sink.submitPlotterUIRequest(request)) }
      } label: {
        HStack(spacing: 6) {
          if feedback.isPending {
            ProgressView().controlSize(.small)
          } else if role == .stop {
            Image(systemName: "stop.fill")
          } else if feedback.wasAccepted {
            Image(systemName: "checkmark")
          }
          Text(feedback.isPending ? "\(title)…" : title)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: expands ? .infinity : nil, minHeight: expands ? 32 : nil)
        .contentShape(Rectangle())
      }
      .operatorButton(role, isEnabled: request != nil && !feedback.isPending)
      .help(feedback.isPending ? "Request sent; waiting for completion" : unavailableReason ?? title)
      .accessibilityValue(feedback.isPending ? "In progress" : feedback.result ?? unavailableReason ?? "Ready")
      if let startedAt = feedback.startedAt {
        OperatorRequestElapsedTime(startedAt: startedAt)
      } else if let detail = feedback.result, !feedback.wasAccepted {
        Text(detail).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
      } else if let unavailableReason, showsUnavailableReason, !feedback.isPending {
        Text(unavailableReason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

struct OperatorRequestElapsedTime: View {
  let startedAt: Date

  var body: some View {
    TimelineView(.periodic(from: startedAt, by: 1)) { context in
      Text("In progress · \(Int(max(0, context.date.timeIntervalSince(startedAt)))) s")
        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
    }
  }
}
