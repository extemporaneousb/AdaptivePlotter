import SwiftUI

/// Native split regions retain multiple panels; scrolling keeps every panel
/// reachable when their combined minimum size exceeds the current window.
struct WorkbenchPanels<Content: View>: View {
  @Binding var layout: WorkbenchLayoutState
  var select: (WorkbenchPanel) -> Void = { _ in }
  @ViewBuilder let content: (WorkbenchPanel) -> Content

  var body: some View {
    VSplitView {
      if !layout.panels(in: .left).isEmpty || !layout.panels(in: .right).isEmpty {
        HSplitView {
          if !layout.panels(in: .left).isEmpty { verticalDock(.left) }
          if !layout.panels(in: .right).isEmpty { verticalDock(.right) }
        }
        .frame(minHeight: 220, maxHeight: .infinity)
      }
      if !layout.panels(in: .bottom).isEmpty { bottomDock }
      if !layout.hasVisiblePanels {
        ContentUnavailableView("Panels are hidden", systemImage: "rectangle.split.3x1",
          description: Text("Choose a panel from the Panels menu."))
      }
    }
  }

  private func verticalDock(_ dock: WorkbenchDock) -> some View {
    let panels = layout.panels(in: dock)
    return GeometryReader { proxy in
      ScrollView(.vertical) {
        VSplitView {
          ForEach(panels) { panel in
            panelView(panel)
              .frame(minHeight: panel == .video ? 280 : 220, maxHeight: .infinity)
          }
        }
        .frame(width: proxy.size.width, height: max(proxy.size.height,
          panels.reduce(CGFloat.zero) { $0 + ($1 == .video ? 440 : 280) }))
      }
    }
    .frame(minWidth: 300, idealWidth: panels.contains(.video) ? 660 : 360, maxWidth: .infinity)
    .accessibilityIdentifier("workbench.dock.\(dock.rawValue)")
  }

  private var bottomDock: some View {
    let panels = layout.panels(in: .bottom)
    return GeometryReader { proxy in
      ScrollView(.horizontal) {
        HSplitView {
          ForEach(panels) { panel in
            panelView(panel).frame(minWidth: panel == .video ? 400 : 320, maxWidth: .infinity)
          }
        }
        .frame(width: max(proxy.size.width, CGFloat(panels.count) * 400), height: proxy.size.height)
      }
    }
    .frame(minHeight: 200, idealHeight: 280, maxHeight: .infinity)
    .accessibilityIdentifier("workbench.dock.bottom")
  }

  private func panelView(_ panel: WorkbenchPanel) -> some View {
    VStack(spacing: 0) {
      HStack {
        Button { select(panel) } label: {
          Label(panel.title, systemImage: panel.systemImage).font(.headline)
        }
        .buttonStyle(.plain)
        .help(panel == .portraitStudio ? "Use portrait camera" :
          panel == .guidedLearning || panel == .activeLearning ? "Use plotter camera" : panel.title)
        .accessibilityIdentifier("workbench.focus.\(panel.rawValue)")
        Spacer()
        Menu {
          ForEach(WorkbenchDock.allCases) { dock in
            Button("Move to \(dock.title)") {
              WorkbenchRequestTelemetry.nativeActionHandled("workbench.move.\(panel.rawValue).\(dock.rawValue)")
              layout.move(panel, to: dock)
            }
              .accessibilityIdentifier("workbench.move.\(panel.rawValue).\(dock.rawValue)")
          }
        } label: { Image(systemName: "rectangle.3.group") }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Position \(panel.title)")
        .accessibilityIdentifier("workbench.position.\(panel.rawValue)")
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.hide.\(panel.rawValue)")
          layout.setPresented(panel, false)
        } label: { Image(systemName: "xmark") }
          .buttonStyle(.plain)
          .accessibilityLabel("Hide \(panel.title)")
          .accessibilityIdentifier("workbench.hide.\(panel.rawValue)")
      }
      .padding(10)
      Divider()
      content(panel).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workbench.panel.\(panel.rawValue)")
  }
}
