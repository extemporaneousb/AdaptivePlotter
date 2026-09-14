import AppKit
import SwiftUI

/// A stable central canvas with optional, independently resizable control columns.
struct WorkbenchPanels<Content: View, CanvasContent: View>: View {
  @Binding var layout: WorkbenchLayoutState
  var select: (WorkbenchPanel) -> Void = { _ in }
  var autosavePrefix: String? = "AdaptivePlotter.workbench.v2"
  @ViewBuilder let content: (WorkbenchPanel) -> Content
  @ViewBuilder let canvas: () -> CanvasContent

  var body: some View {
    WorkbenchNativeSplit(name: "workspace", vertical: true, autosavePrefix: autosavePrefix, children:
      (layout.panels(in: .left).isEmpty ? [] : [column(.left)])
        + [.init(id: "canvas", minimum: 320, ideal: 680,
            content: AnyView(canvas().frame(maxWidth: .infinity, maxHeight: .infinity)
              .accessibilityIdentifier("workbench.video.canvas")))]
        + (layout.panels(in: .right).isEmpty ? [] : [column(.right)]))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func column(_ dock: WorkbenchDock) -> WorkbenchNativeSplit.Child {
    let panels = layout.panels(in: dock)
    return .init(id: dock.rawValue, minimum: 300, ideal: 340, children: panels.map { panel in
        .init(id: panel.rawValue, minimum: 180, ideal: 340, content: AnyView(panelView(panel)))
      })
  }

  private func panelView(_ panel: WorkbenchPanel) -> some View {
    VStack(spacing: 0) {
      HStack {
        Button { select(panel) } label: {
          Label(panel.title, systemImage: panel.systemImage).font(.headline)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workbench.focus.\(panel.rawValue)")
        Spacer()
        Button {
          WorkbenchRequestTelemetry.nativeActionHandled("workbench.hide.\(panel.rawValue)")
          layout.setPresented(panel, false)
        } label: { Image(systemName: "xmark") }
          .buttonStyle(.plain)
          .accessibilityLabel("Hide \(panel.title)")
          .accessibilityIdentifier("workbench.hide.\(panel.rawValue)")
      }.padding(10)
      Divider()
      content(panel).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("workbench.panel.\(panel.rawValue)")
  }
}

/// AppKit owns divider interaction and autosaved sizes. SwiftUI's layout value
/// alone owns membership. Hosting views survive sibling insertion/removal.
struct WorkbenchNativeSplit: NSViewRepresentable {
  struct Child {
    enum Content { case pane(AnyView), column([Child]) }
    let id: String
    let minimum: CGFloat
    let ideal: CGFloat
    let content: Content
    init(id: String, minimum: CGFloat, ideal: CGFloat, content: AnyView) {
      self.id = id; self.minimum = minimum; self.ideal = ideal; self.content = .pane(content)
    }
    init(id: String, minimum: CGFloat, ideal: CGFloat, children: [Child]) {
      self.id = id; self.minimum = minimum; self.ideal = ideal; content = .column(children)
    }
  }
  let name: String
  let vertical: Bool
  let autosavePrefix: String?
  let children: [Child]

  /// Native split views own frame-based geometry and divider events. Only the
  /// leaves host SwiftUI, so no intermediate hosting view imposes a fitting size.
  final class NativeView: NSSplitView {
    /// NSSplitView forwards optional sidebar selectors to its delegate. Using
    /// the split itself as delegate recurses in AppKit's responds(to:) lookup.
    @MainActor
    private final class SplitDelegate: NSObject, NSSplitViewDelegate {
      weak var owner: NativeView?

      func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        owner?.splitView(splitView, resizeSubviewsWithOldSize: oldSize)
      }
      func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
      func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        owner?.splitView(splitView, constrainMinCoordinate: proposed, ofSubviewAt: index) ?? proposed
      }
      func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
        owner?.splitView(splitView, constrainMaxCoordinate: proposed, ofSubviewAt: index) ?? proposed
      }
    }

    private let splitDelegate = SplitDelegate()
    var hosts: [String: NSView] = [:]
    var items: [Child] = []
    var identities: [String] { items.map(\.id) }
    private var useDefaultSizes = true
    override var isFlipped: Bool { true }

    init(vertical: Bool) {
      super.init(frame: .zero)
      isVertical = vertical
      dividerStyle = .thin
      splitDelegate.owner = self
      delegate = splitDelegate
      autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func update(name: String, autosavePrefix: String?, children: [Child]) {
      let membershipChanged = identities != children.map(\.id)
      let previousFrames = subviews.map(\.frame)
      let countChanged = items.count != children.count
      if membershipChanged { autosaveName = nil }
      for (id, view) in hosts where !children.contains(where: { $0.id == id }) {
        view.removeFromSuperview()
        hosts[id] = nil
      }
      for child in children {
        switch child.content {
        case .pane(let content):
          if let host = hosts[child.id] as? NSHostingView<AnyView> { host.rootView = content }
          else {
            let host = NSHostingView(rootView: content)
            host.sizingOptions = []
            host.autoresizingMask = [.width, .height]
            hosts[child.id] = host
          }
        case .column(let descendants):
          let column = (hosts[child.id] as? NativeView) ?? NativeView(vertical: false)
          column.setAccessibilityIdentifier("workbench.dock.\(child.id)")
          column.update(name: child.id, autosavePrefix: autosavePrefix, children: descendants)
          hosts[child.id] = column
        }
      }
      items = children
      if membershipChanged {
        subviews = children.compactMap { hosts[$0.id] }
        useDefaultSizes = countChanged
        if !countChanged {
          for (index, view) in subviews.enumerated() { view.frame = previousFrames[index] }
        }
        layoutItems()
        let topology = isVertical ? identities.joined(separator: "-") : String(children.count)
        let savedName = autosavePrefix.map { "\($0).\(name).\(topology)" }
        let hasSavedSizes = savedName.map { UserDefaults.standard.object(forKey: "NSSplitView Subview Frames " + $0) != nil } ?? false
        autosaveName = savedName
        if hasSavedSizes { useDefaultSizes = false }
      }
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
      layoutItems()
    }

    private func layoutItems() {
      guard !items.isEmpty else { return }
      let usable = (isVertical ? bounds.width : bounds.height) - dividerThickness * CGFloat(items.count - 1)
      guard usable >= items.reduce(0, { $0 + $1.minimum }) else { return }
      var sizes: [CGFloat]
      if let canvas = items.firstIndex(where: { $0.id == "canvas" }) {
        sizes = items.map { item in
          let current = hosts[item.id]?.frame.width ?? 0
          return max(item.minimum, useDefaultSizes ? item.ideal : current)
        }
        let controls = items.indices.filter { $0 != canvas }
        let minimum = controls.reduce(0) { $0 + items[$1].minimum }
        let desiredExtra = controls.reduce(0) { $0 + sizes[$1] - items[$1].minimum }
        let extraBudget = max(0, usable - items[canvas].minimum - minimum)
        let scale = desiredExtra > 0 ? min(1, extraBudget / desiredExtra) : 0
        for index in controls { sizes[index] = items[index].minimum + (sizes[index] - items[index].minimum) * scale }
        sizes[canvas] = usable - controls.reduce(0) { $0 + sizes[$1] }
      } else if items.count == 2 {
        let previous = items.map { hosts[$0.id]?.frame.height ?? 0 }
        let total = previous.reduce(0, +)
        let fraction = useDefaultSizes || total == 0 ? 0.5 : previous[0] / total
        let first = max(items[0].minimum, min(usable - items[1].minimum, usable * fraction))
        sizes = [first, usable - first]
      } else { sizes = [usable] }
      useDefaultSizes = false
      var origin: CGFloat = 0
      for (index, item) in items.enumerated() {
        let frame = isVertical
          ? NSRect(x: origin, y: 0, width: sizes[index], height: bounds.height)
          : NSRect(x: 0, y: origin, width: bounds.width, height: sizes[index])
        hosts[item.id]?.frame = frame
        origin += sizes[index] + dividerThickness
      }
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
      let frame = subviews[index].frame
      return max(proposed, (isVertical ? frame.minX : frame.minY) + items[index].minimum)
    }
    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposed: CGFloat, ofSubviewAt index: Int) -> CGFloat {
      let frame = subviews[index + 1].frame
      return min(proposed, (isVertical ? frame.maxX : frame.maxY) - items[index + 1].minimum - dividerThickness)
    }
  }

  func makeNSView(context: Context) -> NativeView { NativeView(vertical: vertical) }
  func updateNSView(_ view: NativeView, context: Context) {
    view.update(name: name, autosavePrefix: autosavePrefix, children: children)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NativeView, context: Context) -> CGSize? {
    guard let width = proposal.width, let height = proposal.height,
      width.isFinite, height.isFinite else { return nil }
    return CGSize(width: width, height: height)
  }
}

struct WorkbenchMenuContext {
  let layout: WorkbenchLayoutState
  let toggle: (WorkbenchPanel) -> Void
  let restore: () -> Void
}

private struct WorkbenchMenuKey: FocusedValueKey { typealias Value = WorkbenchMenuContext }
extension FocusedValues {
  var workbenchMenu: WorkbenchMenuContext? {
    get { self[WorkbenchMenuKey.self] }
    set { self[WorkbenchMenuKey.self] = newValue }
  }
}

struct WorkbenchCommands: Commands {
  @FocusedValue(\.workbenchMenu) private var workbench
  var body: some Commands {
    CommandGroup(after: .sidebar) {
      ForEach(Array(WorkbenchPanel.allCases.enumerated()), id: \.element) { index, panel in
        Button(panel.actionTitle(isPresented: workbench?.layout.isPresented(panel) == true)) {
          workbench?.toggle(panel)
        }
        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: [.command, .option])
        .disabled(workbench == nil)
      }
      Divider()
      Button("Restore Default Layout") { workbench?.restore() }.disabled(workbench == nil)
    }
  }
}
