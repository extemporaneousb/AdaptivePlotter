import SwiftUI

/// A product-capability statement copied from the current artifact owners.
///
/// This value is presentation only. Its cases deliberately do not form an
/// authorization ladder: controller admission remains owned by the runtime.
enum WorkbenchLearningCapabilityState: CaseIterable, Hashable, Sendable {
  case learningNeeded
  case savedMapNeedsRevalidation
  case mapReady
  case interactiveLearningComplete
  case adaptiveDrawingReady

  var title: String {
    switch self {
    case .learningNeeded: "Learning needed"
    case .savedMapNeedsRevalidation: "Saved map needs revalidation"
    case .mapReady: "Map ready"
    case .interactiveLearningComplete:
      "Interactive learning complete · one validation"
    case .adaptiveDrawingReady: "Adaptive drawing ready"
    }
  }

  var detail: String {
    switch self {
    case .learningNeeded:
      "No current accepted machine-to-tip map is available."
    case .savedMapNeedsRevalidation:
      "A saved map is quarantined until its current applicability is explicitly revalidated."
    case .mapReady:
      "The current accepted tip map is available; an observed-line validation is still pending."
    case .interactiveLearningComplete:
      "The current map has one attributable observed-line validation; adaptive readiness is not established."
    case .adaptiveDrawingReady:
      "The current typed drawing-readiness assessment is accepted for its declared scope."
    }
  }

  var colorToken: WorkbenchCapabilityColorToken {
    switch self {
    case .learningNeeded, .savedMapNeedsRevalidation: .needsAttention
    case .mapReady, .interactiveLearningComplete: .available
    case .adaptiveDrawingReady: .ready
    }
  }
}

/// Paper status is independent from learned model status. A current map never
/// implies that a drawable sheet is present in the camera view.
enum WorkbenchPaperSetupState: Hashable, Sendable {
  case setupRequired(reason: String)
  case current(detail: String)

  var title: String {
    switch self {
    case .setupRequired: "Paper setup required"
    case .current: "Paper current"
    }
  }

  var detail: String {
    switch self {
    case .setupRequired(let reason), .current(let reason): reason
    }
  }

  var colorToken: WorkbenchCapabilityColorToken {
    switch self {
    case .setupRequired: .needsAttention
    case .current: .available
    }
  }
}

enum WorkbenchCapabilityColorToken: Hashable, Sendable {
  case needsAttention
  case available
  case ready
}

struct WorkbenchCapabilityPresentation: Hashable, Sendable {
  let learning: WorkbenchLearningCapabilityState
  let paper: WorkbenchPaperSetupState

  var accessibilityValue: String {
    "\(learning.title). \(learning.detail) \(paper.title). \(paper.detail)"
  }
}

/// Compact toolbar rendering for already-derived capability and paper facts.
/// It receives no workspace or runtime owner.
struct WorkbenchCapabilityIndicator: View {
  let presentation: WorkbenchCapabilityPresentation

  var body: some View {
    HStack(spacing: 10) {
      status(
        title: presentation.learning.title,
        detail: presentation.learning.detail,
        colorToken: presentation.learning.colorToken,
        systemImage: "graduationcap.fill"
      )
      Divider().frame(height: 18)
      status(
        title: presentation.paper.title,
        detail: presentation.paper.detail,
        colorToken: presentation.paper.colorToken,
        systemImage: "doc.fill"
      )
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Drawing capability")
    .accessibilityValue(presentation.accessibilityValue)
  }

  private func status(
    title: String,
    detail: String,
    colorToken: WorkbenchCapabilityColorToken,
    systemImage: String
  ) -> some View {
    Label(title, systemImage: systemImage)
      .font(.caption)
      .foregroundStyle(color(for: colorToken))
      .help(detail)
  }

  private func color(for token: WorkbenchCapabilityColorToken) -> Color {
    switch token {
    case .needsAttention: .orange
    case .available: .green
    case .ready: .cyan
    }
  }
}
