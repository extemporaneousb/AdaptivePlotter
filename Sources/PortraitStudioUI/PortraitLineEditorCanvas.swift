import AppKit
import SwiftUI
import PlotterModel

/// AppKit supplies pointer capture, modifier keys and a canvas-local responder.
/// The observable edit model remains the sole owner of selection and undo state.
package struct PortraitLineEditorCanvas: NSViewRepresentable {
  package let model: PortraitLineEditModel
  package let program: DrawingProgram

  package func makeNSView(context: Context) -> PortraitLineEditorNSView { PortraitLineEditorNSView() }
  package func updateNSView(_ view: PortraitLineEditorNSView, context: Context) {
    view.model = model
    view.program = program
    // Observe these values in SwiftUI so native redraws follow every edit.
    view.removed = model.showsOriginal ? [] : model.removed
    view.selected = model.selection
    view.editingEnabled = model.canEdit
    view.tool = model.tool
    view.needsDisplay = true
  }
}

@MainActor
package final class PortraitLineEditorNSView: NSView {
  package var model: PortraitLineEditModel?
  package var program: DrawingProgram?
  /// The Dojo supplies durable callbacks; generic membership editing uses its model.
  package var onRemove: ((Set<StrokeID>) -> Void)?
  package var onRestore: ((Set<StrokeID>) -> Void)?
  package var onSelection: ((Set<StrokeID>) -> Void)?
  package var onUndo: (() -> Void)?
  package var onRedo: (() -> Void)?
  package var removed: Set<StrokeID> = []
  package var selected: Set<StrokeID> = []
  package var editingEnabled = false
  package var tool: PortraitLineEditModel.Tool = .erase
  private var geometry: PortraitLineSelectionGeometry?
  private var cachedHash: Digest?
  private var cachedSize = CGSize.zero
  private var paths: [StrokeID: NSBezierPath] = [:]
  private var hover: StrokeID?
  private var gesture: [CGPoint] = []
  private var tracking: NSTrackingArea?
  package override var isFlipped: Bool { true }
  package override var acceptsFirstResponder: Bool { true }

  package override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.image)
    setAccessibilityLabel("Drawing line editor")
    setAccessibilityIdentifier("portrait.lineEditor.canvas")
    setAccessibilityHelp("Click removes a whole line. Lasso selects touched lines. Restore recovers gray removed lines. Delete removes selection. Command Z undoes; Shift Command Z redoes.")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

  private func prepare() {
    guard let program else { return }
    guard cachedHash != program.contentHash || cachedSize != bounds.size else { return }
    let value = PortraitLineSelectionGeometry(program: program, size: bounds.size)
    geometry = value; cachedHash = program.contentHash; cachedSize = bounds.size
    paths = Dictionary(uniqueKeysWithValues: value.lines.map { line in
      let path = NSBezierPath(); path.move(to: line.points[0])
      for point in line.points.dropFirst() { path.line(to: point) }
      path.lineWidth = line.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
      return (line.id, path)
    })
  }

  package override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill(); bounds.fill()
    prepare()
    guard let geometry else { return }
    NSColor.white.setFill(); geometry.page.fill()
    for line in geometry.lines where !removed.contains(line.id) || (editingEnabled && tool == .restore) {
      guard let path = paths[line.id] else { continue }
      (removed.contains(line.id) ? NSColor.systemGray.withAlphaComponent(0.45) : NSColor.black).setStroke()
      path.stroke()
      if editingEnabled && (selected.contains(line.id) || hover == line.id) {
        (tool == .restore ? NSColor.systemGreen
          : tool == .erase && hover == line.id ? NSColor.systemRed : NSColor.selectedControlColor).setStroke()
        let highlight = path.copy() as! NSBezierPath
        highlight.lineWidth = max(line.width + 2, 3); highlight.stroke()
      }
    }
    if gesture.count > 1, tool == .lasso {
      let path = NSBezierPath(); path.move(to: gesture[0])
      for point in gesture.dropFirst() { path.line(to: point) }
      path.close(); NSColor.selectedControlColor.withAlphaComponent(0.12).setFill(); path.fill()
      NSColor.selectedControlColor.setStroke(); path.lineWidth = 1.5; path.stroke()
    }
  }

  package override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let tracking { removeTrackingArea(tracking) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
    addTrackingArea(area); tracking = area
  }
  package override func mouseMoved(with event: NSEvent) {
    prepare()
    let next = editingEnabled ? geometry?.hit(convert(event.locationInWindow, from: nil), excluding: excludedFromPicking) : nil
    if hover != next { hover = next; needsDisplay = true }
  }
  package override func mouseExited(with event: NSEvent) { hover = nil; needsDisplay = true }
  package override func mouseDown(with event: NSEvent) {
    guard editingEnabled else { return }
    window?.makeFirstResponder(self); prepare()
    gesture = [convert(event.locationInWindow, from: nil)]; needsDisplay = true
  }
  package override func mouseDragged(with event: NSEvent) {
    guard editingEnabled, tool == .lasso, let last = gesture.last else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard hypot(point.x-last.x, point.y-last.y) >= 3 else { return }
    if gesture.count >= 512 { gesture = gesture.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element) }
    gesture.append(point); needsDisplay = true
  }
  package override func mouseUp(with event: NSEvent) {
    defer { gesture = []; hover = nil; needsDisplay = true }
    guard editingEnabled, let start = gesture.first, let geometry else { return }
    let point = convert(event.locationInWindow, from: nil)
    if tool == .erase || tool == .restore {
      if hypot(point.x-start.x, point.y-start.y) < 5,
        let id = geometry.hit(point, excluding: excludedFromPicking) {
        if tool == .restore { restore([id]) } else { remove([id]) }
      }
    } else if gesture.count >= 3 {
      let hit = geometry.lasso(gesture, excluding: removed)
      select(event.modifierFlags.contains(.shift) ? selected.union(hit) : hit)
    } else if let id = geometry.hit(point, excluding: removed) {
      if event.modifierFlags.contains(.shift) {
        var next = selected
        if !next.insert(id).inserted { next.remove(id) }
        select(next)
      } else { select([id]) }
    } else if !event.modifierFlags.contains(.shift) { select([]) }
  }

  private func select(_ ids: Set<StrokeID>) { selected = ids; if let onSelection { onSelection(ids) } else { model?.selection = ids } }
  private func remove(_ ids: Set<StrokeID>) { if let onRemove { onRemove(ids) } else { model?.remove(ids) } }
  private func restore(_ ids: Set<StrokeID>) { if let onRestore { onRestore(ids) } else { model?.restore(ids) } }

  private var excludedFromPicking: Set<StrokeID> {
    tool == .restore ? Set(program?.strokes.map(\.id) ?? []).subtracting(removed) : removed
  }

  package override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard window?.firstResponder === self, event.modifierFlags.contains(.command),
      !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control),
      event.charactersIgnoringModifiers?.lowercased() == "z", editingEnabled else {
      return super.performKeyEquivalent(with: event)
    }
    if event.modifierFlags.contains(.shift) { if let onRedo { onRedo() } else { model?.redo() } }
    else { if let onUndo { onUndo() } else { model?.undo() } }
    return true
  }
  package override func keyDown(with event: NSEvent) {
    guard editingEnabled else { super.keyDown(with: event); return }
    if event.keyCode == 53 { gesture = []; select([]); needsDisplay = true }
    else if [51,117].contains(event.keyCode), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
      remove(selected)
    } else { super.keyDown(with: event) }
  }
}
