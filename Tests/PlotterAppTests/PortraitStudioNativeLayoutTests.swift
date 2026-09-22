import AppKit
import PlotterUI
import SwiftUI
import Testing
@testable import PlotterApp

/// Production Studio and Drawing panels hosted in owned, offscreen test windows. This
/// exercises hosted geometry and programmatic document scrolling by default.
/// Strict accessibility workflow assertions require the explicit
/// PORTRAIT_NATIVE_AX_CHECK=1 environment prerequisite; they remain pending in
/// SwiftPM hosts that cannot expose a known standalone SwiftUI AX control.
/// This is not an attended input, signed-launch, camera, motion, or ink receipt.
@Suite("Native Studio and shared Drawing panel routing", .serialized)
@MainActor
struct PortraitStudioNativeLayoutTests {
  private let sectionOrder = [
    "drawing.section.placement", "drawing.section.material",
    "drawing.section.paper", "drawing.section.run",
  ]

  @Test("production shared Drawing panel hosts placement and run geometry at three dock widths")
  func productionPanelGeometryAndSelection() async throws {
    try await runPanelChecks(requiresAX: false)
  }

  @Test("native AX shared Drawing order and Draw reachability require an AX-capable host",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func productionPanelAXOrderAndReachability() async throws {
    await diagnoseKnownSwiftUIControl()
    try await runPanelChecks(requiresAX: true)
  }

  @Test("production Portrait routing hosts exploration with detailed adjustments collapsed")
  func productionPortraitWorkspace() async throws {
    _ = NSApplication.shared
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let application = fixture.application
    do {
      let model = application.portraitStudio
      let pen = application.drawingStrokeStyle
      model.options = .init(cropToFace: false, removeBackground: false)
      model.setStyleComparisonExpanded(true, strokeStyle: pen)
      model.setPhoto(try portraitTestImage(), for: .front, strokeStyle: pen)
      await model.awaitRendering()
      #expect(model.algorithmCandidates.count == PortraitStyle.authoringCases.count)
      model.selectAlgorithm(.contours, strokeStyle: pen)
      let sizes = [NSSize(width: 1000, height: 550), NSSize(width: 1280, height: 650)]
      for (size, expanded) in sizes.flatMap({ size in [false, true].map { (size, $0) } }) {
        model.setStyleComparisonExpanded(false, strokeStyle: pen)
        await model.awaitRendering()
        let host = NSHostingController(rootView:
          PlotterApplicationRuntimeView(application: application).panelContent(.portraitStudio)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .light))
        host.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.contentViewController = host
        window.setContentSize(size)
        window.orderFront(nil)
        await settle(host.view)
        // Open Styles only after this actual host has appeared and the prior
        // window's onDisappear has finished removing its comparison demand.
        model.setStyleComparisonExpanded(expanded, strokeStyle: pen)
        await model.awaitRendering()
        await model.awaitExploration()
        await settle(host.view)
        #expect(model.explorationRound?.slots.count == 3)
        #expect(model.explorationRound?.center.id == model.selectedCandidate?.id)
        #expect(abs(host.view.bounds.width - size.width) < 2)
        #expect(abs(host.view.bounds.height - size.height) < 2)
        #expect(!window.isKeyWindow)
        #expect(model.isStyleComparisonExpanded == expanded)
        for scroll in views(host.view).compactMap({ $0 as? NSScrollView }) {
          let document = try #require(scroll.documentView)
          #expect(document.bounds.height <= scroll.contentView.bounds.height + 2,
            "Production Portrait route introduced vertical scrolling: \(document.bounds), \(scroll.contentView.bounds)")
        }
        let controls = views(host.view).compactMap { $0 as? NSControl }.filter {
          !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
        }
        #expect(!controls.isEmpty)
        for control in controls {
          let rect = control.convert(control.bounds, to: host.view)
          #expect(host.view.bounds.insetBy(dx: -2, dy: -2).contains(rect),
            "Production Portrait control was clipped: \(rect) in \(host.view.bounds)")
        }
        try captureOptionalSnapshots(host: host.view, width: Int(size.width), stage: "workspace-\(expanded ? "expanded" : "folded")")
        window.close()
      }
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  @Test("native exploration controls promote, resample and restore exact grids",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func explorationAXInteraction() async throws {
    await diagnoseKnownSwiftUIControl()
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let application = fixture.application
    let model = application.portraitStudio
    let stroke = application.drawingStrokeStyle
    model.options = .init(cropToFace: false, removeBackground: false)
    model.setPhoto(try portraitTestImage(), for: .front, strokeStyle: stroke)
    await model.awaitRendering()
    let size = NSSize(width: 1000, height: 550)
    let host = NSHostingController(rootView:
      PlotterApplicationRuntimeView(application: application).panelContent(.portraitStudio)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10000, y: -10000), size: size),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentViewController = host
    window.setContentSize(size)
    window.orderFront(nil)
    defer { window.close() }
    do {
      await settle(host.view)
      await model.awaitExploration()
      await settle(host.view)
      let original = try #require(model.explorationRound)
      #expect(!window.isKeyWindow)
      #expect(!descendants(window).contains { $0.accessibilityIdentifier() == "portrait.adjustmentInspector" })
      var frames: [CGRect] = []
      for index in 0..<3 {
        let tile = try requiredElement("portrait.exploration.slot.\(index)", in: window)
        let frame = tile.accessibilityFrame()
        #expect(frame.width >= 80 && frame.height >= 60)
        #expect(window.frame.insetBy(dx: -2, dy: -2).contains(frame))
        frames.append(frame)
      }
      #expect(abs(frames[0].minY - frames[2].minY) < 2)
      #expect(frames[0].maxX < frames[1].minX && frames[1].maxX < frames[2].minX)
      let neighbor = try #require(original.slots.first { $0.index != 1 && $0.candidate != nil })
      let choice = try #require(neighbor.candidate)
      #expect(try requiredElement("portrait.exploration.slot.\(neighbor.index)", in: window)
        .accessibilityPerformPress())
      await model.awaitExploration()
      await settle(host.view)
      #expect(model.selectedCandidate?.id == choice.id)
      let promoted = try #require(model.explorationRound)
      #expect(promoted.center.id == choice.id)
      #expect(try requiredElement("portrait.exploration.slot.1", in: window).accessibilityPerformPress())
      await model.awaitExploration()
      await settle(host.view)
      #expect(model.selectedCandidate?.id == choice.id)
      #expect(model.explorationRound?.id != promoted.id)
      #expect(try requiredElement("portrait.exploration.back", in: window).accessibilityPerformPress())
      await settle(host.view)
      #expect(model.explorationRound?.id == promoted.id)
      #expect(try requiredElement("portrait.exploration.back", in: window).accessibilityPerformPress())
      await settle(host.view)
      #expect(model.explorationRound?.id == original.id)
      #expect(model.selectedCandidate?.id == original.center.id)
      #expect(!descendants(window).contains { $0.accessibilityIdentifier() == "portrait.exploration.variation" })
      #expect(model.explorationVariation == original.variation)
      #expect(try requiredElement("portrait.adjustmentsDisclosure", in: window).accessibilityPerformPress())
      await settle(host.view)
      _ = try requiredElement("portrait.adjustmentInspector", in: window)
      _ = try requiredElement("portrait.sourceToggle", in: window)
      _ = try requiredElement("portrait.showOnPlotter", in: window)
      #expect(!window.isKeyWindow)
      try captureOptionalSnapshots(host: host.view, width: 1000, stage: "exploration-interaction")
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  private func runPanelChecks(requiresAX: Bool) async throws {
    _ = NSApplication.shared
    let fixture = try await DrawingWorkbenchApplicationFixture.make()
    defer { fixture.stores.remove() }
    let application = fixture.application
    do {
      let first = try portraitPersistenceCandidate(seed: 801)
      let second = try portraitPersistenceCandidate(seed: 802)
      #expect(application.portraitStudio.sketches.retain(candidate: first, reason: .shortlisted) == nil)
      #expect(application.portraitStudio.sketches.retain(candidate: second, reason: .shortlisted) == nil)
      await application.portraitStudio.sketches.awaitPersistence()
      #expect(application.drawingMaterials.createNominal(name: "Native layout nominal material", widthMM: 1.2) == nil)
      // Only the synthetic draft owner is touched. No Draw or movement request
      // is submitted, and the view's application-startup task is never mounted.
      let selectionProjection = application.plotterUIProjection(
        selectedItemID: application.testCurrentLearningPathItemID,
        manualDraft: ManualMotionDraft(), includesLearningPath: true,
        pendingDrawingProgram: first.program)
      let selectionRequest = try #require(selectionProjection.semantic.request(
        matching: .drawingDraft(.selectProgram(first.program))))
      let selectionOutcome = await application.submitPlotterUIRequest(selectionRequest)
      try #require(selectionOutcome == .accepted(requestID: selectionRequest.id),
        "Synthetic draft selection was refused: \(selectionOutcome).")
      for width in [300, 390, 600] {
        application.portraitStudio.sketches.selectedID = first.id
        try await inspectPanel(application: application, width: width, alternateSelection: second.id, requiresAX: requiresAX)
      }
      await application.shutdown()
    } catch {
      await application.shutdown()
      throw error
    }
  }

  private func inspectPanel(application: PlotterApplicationRuntime, width: Int, alternateSelection: String, requiresAX: Bool) async throws {
    let drawingPreview = try #require(application.drawingStudioPresentation.drawingPreview)
    #expect(drawingPreview.plane.geometry(in: CGSize(width: width - 24, height: 160)) != nil)
    let panel = PlotterApplicationRuntimeView(application: application).panelContent(.drawing)
    let host = NSHostingController(rootView: panel
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: CGFloat(width), height: 700),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .windowBackgroundColor
    window.contentViewController = host
    window.setContentSize(NSSize(width: width, height: 700))
    // Ordering the owned offscreen window materializes native accessibility;
    // neither making a key window nor activating an application is necessary.
    window.orderFront(nil)
    defer { window.close() }
    await settle(host.view)
    try assertHostedGeometry(host: host.view, window: window, width: width)
    try captureOptionalSnapshots(host: host.view, width: width, stage: "initial")
    if requiresAX {
      _ = NSAccessibility.unignoredChildrenForOnlyChild(from: host.view)
      try assertSectionOrder(in: window, width: width)
      try assertControlsFitHorizontally(in: window, width: width)
    }

    application.portraitStudio.sketches.selectedID = alternateSelection
    await settle(host.view)
    #expect(application.portraitStudio.selectedCandidate?.id == alternateSelection)
    #expect(application.drawingStudioPresentation.drawingPreview == drawingPreview,
      "Browsing a saved Studio drawing must not substitute the Drawing panel's program or plan.")
    try assertHostedGeometry(host: host.view, window: window, width: width)
    try captureOptionalSnapshots(host: host.view, width: width, stage: "selected")
    let outerScroll = try #require(views(host.view).compactMap { $0 as? NSScrollView }.first)
    let pinnedPreview = try pinnedPreviewPixels(host: host.view, controls: outerScroll)
    guard requiresAX else {
      let document = try #require(outerScroll.documentView)
      let before = outerScroll.contentView.bounds.origin
      let bottomY = document.isFlipped ? max(0, document.bounds.maxY - outerScroll.contentView.bounds.height) : document.bounds.minY
      document.scrollToVisible(NSRect(x: document.bounds.minX, y: bottomY,
        width: outerScroll.contentView.bounds.width, height: outerScroll.contentView.bounds.height))
      outerScroll.reflectScrolledClipView(outerScroll.contentView)
      await settle(host.view)
      if document.bounds.height > outerScroll.contentView.bounds.height + 2 {
        #expect(outerScroll.contentView.bounds.origin != before,
          "An overflowing Drawing document must allow vertical scrolling at \(width) pt.")
      } else {
        #expect(outerScroll.contentView.bounds.origin == before,
          "A complete Drawing panel should stay visible without scrolling at \(width) pt.")
      }
      #expect(try pinnedPreviewPixels(host: host.view, controls: outerScroll) == pinnedPreview,
        "The production drawing preview must remain fixed while the Drawing controls scroll.")
      try captureOptionalSnapshots(host: host.view, width: width, stage: "scrolled")
      // This proves document geometry and conditional scrolling; the opt-in
      // AX test additionally identifies Draw and checks its visible frame.
      return
    }
    try assertSectionOrder(in: window, width: width)
    let preview = try requiredElement("drawing.previewSection", in: window)
    #expect(descendants(window).filter { $0.accessibilityIdentifier() == "drawing.previewSection" }.count == 1)
    #expect(containingScrollViews(preview, in: window).isEmpty,
      "The sole Drawing preview must be outside the control scroller.")
    let previewFrame = preview.accessibilityFrame()
    #expect(window.frame.contains(previewFrame))

    // The material and run owners are generic; Portrait authoring and its
    // former rating/training sections do not belong to this scroll document.
    _ = try requiredElement("drawing.material.apply", in: window)
    try assertControlsFitHorizontally(in: window, width: width)

    let draw = try requiredElement("drawing.draw", in: window)
    let scrolls = containingScrollViews(draw, in: window)
    #expect(!scrolls.isEmpty, "Draw must remain inside the real panel scroll view.")
    let before = scrolls.map { $0.contentView.bounds.origin }
    let requiredScrolling = scrolls.contains { scroll in
      let clip = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
      return (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height + 2
        && !clip.insetBy(dx: -2, dy: -2).contains(draw.accessibilityFrame())
    }
    reveal(draw, in: window)
    await settle(host.view)
    #expect(preview.accessibilityFrame() == previewFrame)
    #expect(try pinnedPreviewPixels(host: host.view, controls: outerScroll) == pinnedPreview)
    let frame = draw.accessibilityFrame()
    #expect(frame.width > 0 && frame.height > 0)
    for scroll in scrolls {
      let clip = window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil)).insetBy(dx: -2, dy: -2)
      #expect(clip.contains(frame), "Draw is clipped after scrolling at \(width) pt: target=\(frame), clip=\(clip).")
    }
    if requiredScrolling {
      #expect(zip(before, scrolls).contains { $0.0 != $0.1.contentView.bounds.origin },
        "An initially clipped Draw action must be reachable by scrolling at \(width) pt.")
    }
    let run = try requiredElement("drawing.section.run", in: window)
    #expect(descendants(run).contains { $0.accessibilityIdentifier() == "drawing.draw" },
      "Draw must belong to the final run section.")
    // Never press Draw: disabled and enabled controls have identical geometry
    // requirements, while their admission authority remains separately tested.
  }

  private func assertHostedGeometry(host: NSView, window: NSWindow, width: Int) throws {
    #expect(abs(host.bounds.width - CGFloat(width)) <= 1)
    #expect(abs(host.bounds.height - 700) <= 1)
    #expect(!window.isKeyWindow, "The owned layout probe must not become the key window.")
    let nativeViews = views(host)
    let outerScroll = try #require(nativeViews.compactMap { $0 as? NSScrollView }.first)
    let clip = outerScroll.contentView
    let document = try #require(outerScroll.documentView)
    #expect(clip.bounds.width > 0 && clip.bounds.width <= CGFloat(width) + 1)
    #expect(clip.bounds.height > 0 && clip.bounds.height <= 701)
    #expect(document.bounds.width <= clip.bounds.width + 2,
      "Production Drawing unexpectedly overflows horizontally at \(width) pt: document=\(document.bounds), clip=\(clip.bounds).")
    #expect(document.bounds.height > 0,
      "The Drawing document must have a nonempty layout.")
    let controls = nativeViews.compactMap { $0 as? NSControl }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }
    #expect(!controls.isEmpty, "Production panel must host real native controls.")
    for control in controls {
      #expect(control.bounds.width <= clip.bounds.width + 2,
        "Native \(String(reflecting: type(of: control))) exceeds panel width \(width): \(control.bounds).")
      if !control.isDescendant(of: document) {
        #expect(host.bounds.insetBy(dx: -2, dy: -2).contains(control.convert(control.bounds, to: host)),
          "A pinned Drawing preview control must remain inside its viewport.")
        continue
      }
      let rect = control.convert(control.bounds, to: document)
      #expect(rect.minX >= document.bounds.minX - 2 && rect.maxX <= document.bounds.maxX + 2,
        "Native control extends beyond the hosted document at \(width) pt: \(rect).")
      if document.bounds.height <= clip.bounds.height + 2 {
        let viewportRect = control.convert(control.bounds, to: clip)
        #expect(clip.bounds.insetBy(dx: -2, dy: -2).contains(viewportRect),
          "A compact Drawing panel control is outside the visible viewport at \(width) pt: \(viewportRect).")
      }
    }
  }

  private func pinnedPreviewPixels(host: NSView, controls: NSScrollView) throws -> Data {
    let controlsFrame = controls.convert(controls.bounds, to: host)
    let top = host.isFlipped ? host.bounds.minY : controlsFrame.maxY
    let height = host.isFlipped ? controlsFrame.minY - host.bounds.minY
      : host.bounds.maxY - controlsFrame.maxY
    try #require(height > 40, "The actual production panel must retain a visible preview above its scroller.")
    let rect = CGRect(x: host.bounds.minX, y: top, width: host.bounds.width, height: height)
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: rect))
    host.cacheDisplay(in: rect, to: bitmap)
    return try #require(bitmap.representation(using: .png, properties: [:]))
  }

  private func assertSectionOrder(in window: NSWindow, width: Int) throws {
    let all = descendants(window)
    var indices: [Int] = []
    var frames: [CGRect] = []
    for identifier in sectionOrder {
      let matches = all.enumerated().filter { $0.element.accessibilityIdentifier() == identifier }
      #expect(matches.count == 1, "Expected one accessible \(identifier) at \(width) pt; found \(matches.count). IDs: \(all.compactMap { $0.accessibilityIdentifier() }.joined(separator: ", ")).")
      let match = try #require(matches.first)
      indices.append(match.offset)
      frames.append(match.element.accessibilityFrame())
    }
    #expect(zip(indices, indices.dropFirst()).allSatisfy { $0 < $1 }, "Native accessibility reading order differs from Drawing workflow at \(width) pt: \(indices).")
    #expect(frames.allSatisfy { $0.width > 0 && $0.height > 0 }, "Section frame is empty at \(width) pt: \(frames).")
    // Screen coordinates increase upwards; successive vertical sections must
    // appear below their predecessors even when outside the current viewport.
    #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.minY >= $1.maxY - 3 },
      "Drawing sections overlap or reverse visual order at \(width) pt: \(frames).")
  }

  private func assertControlsFitHorizontally(in window: NSWindow, width: Int) throws {
    let actionRoles: Set<NSAccessibility.Role> = [.button, .popUpButton, .textField, .slider, .checkBox, .radioButton, .comboBox]
    let controls = descendants(window).filter { element in
      guard let role = element.accessibilityRole() else { return false }
      return actionRoles.contains(role)
    }
    #expect(!controls.isEmpty)
    for control in controls {
      let frame = control.accessibilityFrame()
      guard frame.width > 0, frame.height > 0 else { continue }
      let identifier = control.accessibilityIdentifier() ?? control.accessibilityLabel() ?? "unidentified control"
      let scrolls = containingScrollViews(control, in: window)
      for scroll in scrolls {
        // Thumbnail galleries may intentionally scroll horizontally. Each
        // complete action must nevertheless fit within its containing clip.
        #expect(frame.width <= scroll.contentView.bounds.width + 2,
          "\(identifier) exceeds the available horizontal action width at \(width) pt: \(frame.width) > \(scroll.contentView.bounds.width).")
      }
      // Outside deliberately horizontal galleries, screen X must fit the
      // panel's viewport even when the control is vertically offscreen.
      let hasHorizontalGallery = scrolls.contains { scroll in
        (scroll.documentView?.bounds.width ?? 0) > scroll.contentView.bounds.width + 2
      }
      if !hasHorizontalGallery {
        let panel = window.convertToScreen(window.contentView!.bounds)
        #expect(frame.minX >= panel.minX - 2 && frame.maxX <= panel.maxX + 2,
          "\(identifier) is horizontally clipped at \(width) pt: target=\(frame), panel=\(panel).")
      }
    }
  }

  private func requiredElement(_ identifier: String, in window: NSWindow) throws -> any NSAccessibilityProtocol {
    try #require(descendants(window).first { $0.accessibilityIdentifier() == identifier }, "Missing native accessibility element: \(identifier).")
  }

  private func descendants(_ root: any NSAccessibilityProtocol) -> [any NSAccessibilityProtocol] {
    var result: [any NSAccessibilityProtocol] = [], pending: [any NSAccessibilityProtocol] = [root]
    var visited: Set<ObjectIdentifier> = []
    while let element = pending.popLast(), result.count < 8192 {
      guard visited.insert(ObjectIdentifier(element)).inserted else { continue }
      result.append(element)
      let children = (element.accessibilityChildren() ?? []).compactMap { $0 as? any NSAccessibilityProtocol }
      pending.append(contentsOf: children.reversed())
    }
    if let window = root as? NSWindow, !result.contains(where: { $0.accessibilityIdentifier() != nil }),
      let content = window.contentView {
      let direct = descendants(content)
      if direct.contains(where: { $0.accessibilityIdentifier() != nil }) {
        return [window] + direct
      }
      let unignored = NSAccessibility.unignoredChildrenForOnlyChild(from: content)
        .compactMap { $0 as? any NSAccessibilityProtocol }
      let resolved = unignored.flatMap(descendants)
      if resolved.contains(where: { $0.accessibilityIdentifier() != nil }) {
        return [window] + resolved
      }
    }
    return result
  }

  private func diagnoseKnownSwiftUIControl() async {
    let identifier = "native-layout.sanity.button"
    let content = VStack {
      Text("Known SwiftUI accessibility control")
      Button("Sanity button") { }.accessibilityIdentifier(identifier)
    }.padding(12)
    let host = NSHostingController(rootView: content
      .background(Color(nsColor: .windowBackgroundColor))
      .environment(\.colorScheme, .light))
    host.sizingOptions = []
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 160),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = NSAppearance(named: .aqua)
    window.backgroundColor = .windowBackgroundColor
    window.contentViewController = host
    window.setContentSize(NSSize(width: 300, height: 160))
    window.orderFront(nil)
    defer { window.close() }
    await settle(host.view)
    _ = NSAccessibility.unignoredChildrenForOnlyChild(from: host.view)
    let before = descendants(window)
    print("Studio AX known-control before finishLaunching: found=\(before.contains { $0.accessibilityIdentifier() == identifier }) finishedLaunching=\(NSRunningApplication.current.isFinishedLaunching) active=\(NSApp.isActive) key=\(window.isKeyWindow) roles=\(before.map { String(describing: $0.accessibilityRole()) }.joined(separator: ","))")
    // SwiftPM constructs NSApplication without necessarily completing AppKit's
    // normal process-local initialization. Completing it is not activation,
    // ordering a key window, or sending an event to another application.
    if !NSRunningApplication.current.isFinishedLaunching {
      NSApplication.shared.finishLaunching()
      await settle(host.view)
    }
    _ = NSAccessibility.unignoredChildrenForOnlyChild(from: host.view)
    let after = descendants(window)
    print("Studio AX known-control after finishLaunching: found=\(after.contains { $0.accessibilityIdentifier() == identifier }) finishedLaunching=\(NSRunningApplication.current.isFinishedLaunching) active=\(NSApp.isActive) key=\(window.isKeyWindow) identifiers=\(after.compactMap { $0.accessibilityIdentifier() }.joined(separator: ","))")
    // This independent probe diagnoses the host. It never skips or converts
    // any missing Studio section/control into a successful assertion.
  }

  private func captureOptionalSnapshots(host: NSView, width: Int, stage: String) throws {
    guard let path = ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_LAYOUT_SNAPSHOT_DIR"],
      path.hasPrefix("/") else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    func capture(_ view: NSView, name: String) throws {
      view.layoutSubtreeIfNeeded()
      let bounds = view.bounds
      guard bounds.width > 0, bounds.height > 0, bounds.width * bounds.height <= 20_000_000 else {
        print("Studio native bitmap unavailable: \(name), bounds=\(bounds)"); return
      }
      guard let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds) else {
        print("Studio native bitmap allocation unavailable: \(name), bounds=\(bounds)"); return
      }
      view.cacheDisplay(in: bounds, to: bitmap)
      guard let bytes = bitmap.representation(using: .png, properties: [:]) else {
        print("Studio native bitmap encoding unavailable: \(name)"); return
      }
      let url = directory.appendingPathComponent(name)
      try bytes.write(to: url, options: .atomic)
      print("Studio native bitmap saved: \(url.path), bounds=\(bounds), pixels=\(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
    }
    try capture(host, name: "studio-\(width)-\(stage)-viewport.png")
    if let outerScroll = views(host).compactMap({ $0 as? NSScrollView }).first,
      let document = outerScroll.documentView {
      try capture(document, name: "studio-\(width)-\(stage)-document.png")
    }
  }

  private func views(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(views) }

  private func containingScrollViews(_ target: any NSAccessibilityProtocol, in window: NSWindow) -> [NSScrollView] {
    guard let root = window.contentView else { return [] }
    let scrolls = views(root).compactMap { $0 as? NSScrollView }.filter { scroll in
      guard let document = scroll.documentView else { return false }
      return descendants(document).contains {
        ObjectIdentifier($0) == ObjectIdentifier(target)
          || (target.accessibilityIdentifier() != nil && $0.accessibilityIdentifier() == target.accessibilityIdentifier())
      }
    }
    return Array(scrolls.reversed())
  }

  private func reveal(_ target: any NSAccessibilityProtocol, in window: NSWindow) {
    for scroll in containingScrollViews(target, in: window) {
      guard let document = scroll.documentView else { continue }
      let rect = document.convert(window.convertFromScreen(target.accessibilityFrame()), from: nil)
      document.scrollToVisible(rect.insetBy(dx: -4, dy: -4))
      scroll.reflectScrolledClipView(scroll.contentView)
      window.contentView?.layoutSubtreeIfNeeded()
    }
    window.displayIfNeeded()
  }

  private func settle(_ view: NSView) async {
    for _ in 0..<8 {
      view.window?.layoutIfNeeded()
      view.layoutSubtreeIfNeeded()
      view.window?.displayIfNeeded()
      view.displayIfNeeded()
      try? await Task.sleep(for: .milliseconds(50))
    }
    view.layoutSubtreeIfNeeded()
    view.window?.displayIfNeeded()
    view.displayIfNeeded()
  }
}
