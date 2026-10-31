@testable import PortraitArtists
import AppKit
import Foundation
import PortraitCore
import PortraitLibrary
@testable import PortraitStudioUI
import PlotterModel
import Vision
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

  @Test("production Portrait route retains one isolated dojo with reachable photos, branches and stage controls")
  func productionPortraitWorkspace() async throws {
    try await runPortraitChecks(requiresAX: false)
  }

  @Test("native dojo navigation and explicit choices require an AX-capable host",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_AX_CHECK"] == "1"))
  func dojoAXInteraction() async throws {
    await diagnoseKnownSwiftUIControl()
    try await runPortraitChecks(requiresAX: true)
  }

  private func runPortraitChecks(requiresAX: Bool) async throws {
    _ = NSApplication.shared
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let renderer = NativeDojoLayoutRenderer()
    let owner = PortraitStudioModel(candidateStore: .init(directoryURL: directory.appendingPathComponent("historical")),
      portfolioFactory: { stroke in
        FlowDojoModel(directory: directory.appendingPathComponent("native-layout.flowportfolio"),
          strokeStyle: stroke, purpose: .validationFixture,
          render: { data, recipe, style in try await renderer.render(data, recipe, style) },
          fit: { _, _ in .unavailable("Native layout fixture: no trained artist.") })
      })
    let fixture = try await DrawingWorkbenchApplicationFixture.make(portraitStudio: owner)
    defer { fixture.stores.remove() }
    let application = fixture.application
    do {
      let pen = application.drawingStrokeStyle, dojo = owner.portfolioDojo(strokeStyle: application.drawingStrokeStyle)
      await dojo.open()
      await dojo.addPhoto(data: try portraitTestImage(), title: "Source 01")
      dojo.count = 3; await dojo.generate(refining: false)
      let anchor = try #require(dojo.roundCandidates.first)
      await dojo.browseCandidate(anchor.id)
      await dojo.generate(refining: true)
      await dojo.generate(refining: false)
      await dojo.browseCandidate(anchor.id, prune: true)
      await dojo.edit(.remove, ids: [try #require(dojo.program?.strokes.first?.id)])
      await dojo.edit(.completeTarget)
      await dojo.presentRanking(scope: .round(try #require(dojo.round?.id)), count: 2)
      await dojo.fit()
      for index in 2...18 { await dojo.addPhoto(data: try portraitTestImage(), title: String(format: "Source %02d", index)) }
      await dojo.browseCandidate(anchor.id)
      try #require(dojo.error == nil && dojo.document?.sources.count == 18)
      try #require(dojo.document?.rounds.count == 3)
      #expect(dojo.document?.purpose == .validationFixture && dojo.directory.path.hasPrefix(directory.path))
      let store = try #require(dojo.store)
      let renders = await renderer.calls
      let stages: [FlowDojoModel.Stage] = requiresAX ? [.explore] : FlowDojoModel.Stage.allCases
      for size in [NSSize(width: 1000, height: 550), NSSize(width: 1280, height: 650)] {
        for stage in stages {
          dojo.stage = stage
          let revision = dojo.document?.revision, choices = dojo.document?.choices.count
          let selectedSource = dojo.selectedSource?.id, selectedCandidate = dojo.candidate?.id
          let programHash = dojo.program?.contentHash
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
          window.contentViewController = host; window.setContentSize(size); window.orderFront(nil)
          do {
            await settle(host.view)
            let name = "dojo-" + stage.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
            try captureOptionalSnapshots(host: host.view, width: Int(size.width), stage: name)
            try assertDojoGeometry(host: host.view, window: window, size: size, stage: stage)
            #expect(owner.portfolioDojo(strokeStyle: pen) === dojo && dojo.store === store)
            #expect(await renderer.calls == renders && owner.renderDiagnostics.startedWorkerCount == 0)
            #expect(!owner.cameraIsRunning && !owner.isCapturing && owner.preview.frame == nil)
            #expect(dojo.document?.revision == revision && dojo.document?.choices.count == choices)
            #expect(dojo.selectedSource?.id == selectedSource && dojo.candidate?.id == selectedCandidate)
            #expect(dojo.program?.contentHash == programHash && dojo.stage == stage)
            if requiresAX {
              try await exerciseDojoAX(dojo, in: window, host: host.view)
              #expect(await renderer.calls == renders && owner.renderDiagnostics.startedWorkerCount == 0)
            } else {
              let scrollers = views(host.view).compactMap { $0 as? NSScrollView }.filter {
                !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
              }
              for scroll in scrollers { try await assertReachableDocument(scroll, host: host.view) }
              #expect(dojo.document?.revision == revision && dojo.document?.choices.count == choices,
                "Scrolling photo, branch and drawing documents must not create feedback or navigation records.")
              #expect(dojo.selectedSource?.id == selectedSource && dojo.candidate?.id == selectedCandidate)
              #expect(await renderer.calls == renders)
              try captureOptionalSnapshots(host: host.view, width: Int(size.width), stage: name + "-scrolled")
              if stage == .fit {
                let visible = try renderedDojoLabels(host.view).map(normalizeDojoLabel)
                for title in ["Curation stage", "Results", "Activate"] {
                  #expect(visible.contains { $0.contains(normalizeDojoLabel(title)) },
                    "Fit history and the pinned stage selector must remain reachable after scrolling at \(size): \(visible)")
                }
              }
            }
            window.close()
          } catch { window.close(); throw error }
        }
      }
      await application.shutdown()
    } catch { await application.shutdown(); throw error }
  }

  private func assertDojoGeometry(host: NSView, window: NSWindow, size: NSSize, stage: FlowDojoModel.Stage) throws {
    #expect(!window.isKeyWindow)
    #expect(abs(host.bounds.width - size.width) < 2 && abs(host.bounds.height - size.height) < 2)
    let bounds = host.bounds.insetBy(dx: -2, dy: -2)
    let all = views(host)
    let scrolls = all.compactMap { $0 as? NSScrollView }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0
    }
    let sidebar = scrolls.filter { $0.convert($0.bounds, to: host).maxX < size.width / 2 }
    #expect(sidebar.count == 2, "The production dojo needs separate photo and branch scrollers.")
    for scroll in scrolls {
      let rect = scroll.convert(scroll.bounds, to: host)
      #expect(bounds.contains(rect), "Embedded \(stage.rawValue) viewport is clipped at \(size): \(rect)")
      let document = try #require(scroll.documentView)
      #expect(document.bounds.width <= scroll.contentView.bounds.width + 2,
        "Embedded \(stage.rawValue) document unexpectedly overflows horizontally: \(document.bounds), \(scroll.contentView.bounds)")
    }
    let branchScroll = try #require(sidebar.min { a, b in
      window.convertToScreen(a.convert(a.bounds, to: nil)).minY
        < window.convertToScreen(b.convert(b.bounds, to: nil)).minY
    })
    try assertVisibleBranchRow(branchScroll.contentView, host: host, size: size, stage: stage)
    let controls = all.compactMap { $0 as? NSControl }.filter {
      !$0.isHiddenOrHasHiddenAncestor && $0.bounds.width > 0 && $0.bounds.height > 0 && !($0 is NSTableView)
    }
    #expect(!controls.isEmpty)
    for control in controls {
      let rect = control.convert(control.bounds, to: host)
      if documentScrolls(of: control).isEmpty {
        #expect(bounds.contains(rect), "Embedded pinned control is clipped: \(rect) in \(host.bounds)")
      } else {
        #expect(rect.minX >= bounds.minX && rect.maxX <= bounds.maxX,
          "Embedded document control overflows horizontally: \(rect) in \(host.bounds)")
      }
    }
    let labels = try renderedDojoLabels(host).map(normalizeDojoLabel)
    let required = ["Flow Edge Dojo", "Import Photo", "Capture Photo", "Branches",
      "Curation stage", "Explore", "Prune", "Rank", "Fit & deploy"]
      + (stage == .explore ? ["Broad exploration", "Compare this set"]
        : stage == .prune ? ["Finish pruning", "Original"]
        : stage == .rank ? ["Rank by artistic preference", "Next pair"] : ["Fit portfolio", "No active checkpoint"])
    for title in required {
      #expect(labels.contains { $0.contains(normalizeDojoLabel(title)) },
        "Embedded \(stage.rawValue) core control '\(title)' is not visible at \(size): \(labels)")
    }
    #expect(labels.contains { $0.hasPrefix("branches") }, "Branch access must be visible without scrolling the photo library.")
  }

  private func assertVisibleBranchRow(_ clip: NSClipView, host: NSView, size: NSSize, stage: FlowDojoModel.Stage) throws {
    // Rich SwiftUI plain-button rows need not have NSButton backing views.
    // Inspect only the real branch viewport so a photo-row label cannot satisfy
    // the drawing-row contract, while strict action semantics remain in AX tests.
    // Cache the composited host first: caching the clip alone leaves its inherited
    // background transparent, making black heading glyphs invisible to OCR.
    let hostBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: hostBitmap)
    let hostImage = try #require(hostBitmap.cgImage)
    let clipFrame = clip.convert(clip.bounds, to: host)
    let scaleX = CGFloat(hostImage.width) / host.bounds.width
    let scaleY = CGFloat(hostImage.height) / host.bounds.height
    let top = host.isFlipped ? clipFrame.minY - host.bounds.minY : host.bounds.maxY - clipFrame.maxY
    let pixels = CGRect(x: (clipFrame.minX - host.bounds.minX) * scaleX, y: top * scaleY,
      width: clipFrame.width * scaleX, height: clipFrame.height * scaleY)
    let image = try #require(hostImage.cropping(to: pixels))
    let bitmap = NSBitmapImageRep(cgImage: image)
    if let path = ProcessInfo.processInfo.environment["PORTRAIT_NATIVE_LAYOUT_SNAPSHOT_DIR"], path.hasPrefix("/") {
      let name = stage.rawValue.lowercased().replacingOccurrences(of: " ", with: "-")
      let url = URL(fileURLWithPath: path).appendingPathComponent("studio-\(Int(size.width))-dojo-\(name)-branches.png")
      try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
    try VNImageRequestHandler(cgImage: image).perform([request])
    let rows = (request.results ?? []).compactMap { observation -> (String, CGRect)? in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      return (normalizeDojoLabel(text), observation.boundingBox)
    }
    let labels = rows.map(\.0)
    for text in ["Branches", "Set 1", "Drawing 1", "1 removed target"] {
      #expect(labels.contains { $0.contains(normalizeDojoLabel(text)) },
        "Branch viewport must show its heading and complete first drawing at \(size): \(labels)")
    }
    let title = try #require(rows.first { $0.0 == "drawing1" }?.1)
    let subtitle = try #require(rows.first { $0.0.contains("1removedtarget") }?.1)
    let center = title.union(subtitle).midY * clip.bounds.height
    // The 48pt thumbnail plus 4pt padding on each side defines the actual 56pt
    // row. Allow 2pt for optical glyph bounds versus the text-layout center.
    #expect(center - 28 >= -2 && center + 28 <= clip.bounds.height + 2,
      "The complete 56pt drawing row must fit the branch viewport: center=\(center), height=\(clip.bounds.height)")
  }

  private func assertReachableDocument(_ scroll: NSScrollView, host: NSView) async throws {
    let document = try #require(scroll.documentView), clip = scroll.contentView
    guard document.bounds.height > clip.bounds.height + 2 else { return }
    let before = clip.bounds.origin
    var reachedStableEnd = false
    // LazyVStack replaces estimated heights when the final rows materialize.
    // Follow the current end until it settles; never treat a stale first extent
    // as proof that the actual final photo or drawing is unreachable.
    for _ in 0..<6 {
      let height = document.bounds.height
      let end = document.isFlipped ? max(0, document.bounds.maxY - clip.bounds.height) : document.bounds.minY
      document.scrollToVisible(NSRect(x: document.bounds.minX, y: end,
        width: clip.bounds.width, height: clip.bounds.height))
      scroll.reflectScrolledClipView(clip); await settle(host)
      let tail = document.isFlipped ? document.bounds.maxY - 1 : document.bounds.minY + 1
      if abs(document.bounds.height - height) < 1 && clip.bounds.minY <= tail && clip.bounds.maxY >= tail {
        reachedStableEnd = true; break
      }
    }
    #expect(clip.bounds.origin != before, "An overflowing dojo document must allow navigation to its end.")
    #expect(reachedStableEnd,
      "The final photo, branch or drawing must be reachable after bounded layout settling: document=\(document.bounds), visible=\(clip.bounds)")
  }

  private func documentScrolls(of view: NSView) -> [NSScrollView] {
    var found: [NSScrollView] = [], current = view.superview
    while let parent = current {
      if let scroll = parent as? NSScrollView, let document = scroll.documentView, view.isDescendant(of: document) { found.append(scroll) }
      current = parent.superview
    }
    return found
  }

  private func renderedDojoLabels(_ host: NSView) throws -> [String] {
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let image = try #require(bitmap.cgImage)
    let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
    try VNImageRequestHandler(cgImage: image).perform([request])
    var labels = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    labels += views(host).compactMap { view -> String? in
      guard let button = view as? NSButton, !button.isHiddenOrHasHiddenAncestor,
        host.bounds.insetBy(dx: -2, dy: -2).contains(button.convert(button.bounds, to: host)),
        documentScrolls(of: button).allSatisfy({ $0.contentView.bounds.insetBy(dx: -2, dy: -2).contains(button.convert(button.bounds, to: $0.contentView)) }) else { return nil }
      return button.title.isEmpty ? button.accessibilityLabel() : button.title
    }
    return labels
  }

  private func normalizeDojoLabel(_ value: String) -> String {
    value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
  }

  private func exerciseDojoAX(_ dojo: FlowDojoModel, in window: NSWindow, host: NSView) async throws {
    for id in ["flowDojo.workspace", "flowDojo.broad", "flowDojo.refine"] {
      _ = try requiredElement(id, in: window)
    }
    // SwiftUI can expose the workspace's inherited identifier on these header
    // buttons. Their exact accessible action label is the native fallback.
    for (id, title) in [("flowDojo.importPhoto", "Import Photo"), ("flowDojo.openCamera", "Capture Photo")] {
      _ = try #require(descendants(window).first { element in
        element.accessibilityIdentifier() == id || (element.accessibilityRole() == .button
          && [element.accessibilityLabel(), (element as? NSButton)?.title].compactMap { $0 }
            .contains { normalizeDojoLabel($0) == normalizeDojoLabel(title) })
      }, "Missing native header action: \(title).")
    }
    #expect(!descendants(window).contains { ["portrait.style", "portrait.adjustmentInspector", "portrait.exploration.next"].contains($0.accessibilityIdentifier() ?? "") })
    let originalChoices = dojo.document?.choices.count ?? 0
    let candidate = try #require(dojo.roundCandidates.first)
    let browse = try #require(descendants(window).first { element in
      element.accessibilityRole() == .button
        && [element.accessibilityLabel(), (element as? NSButton)?.title].compactMap { $0 }
          .contains { normalizeDojoLabel($0) == "openprune" }
    }, "Missing native Open / prune action.")
    reveal(browse, in: window); await settle(host)
    #expect(browse.accessibilityPerformPress())
    let browseDeadline = ContinuousClock.now.advanced(by: .seconds(3))
    while dojo.stage != .prune && ContinuousClock.now < browseDeadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(dojo.stage == .prune && dojo.candidate?.id == candidate.id)
    #expect(dojo.document?.choices.count == originalChoices, "Opening a drawing must not cast a preference vote.")
    dojo.stage = .explore; await settle(host)
    let choice = try requiredElement("flowDojo.choose.\(candidate.slot)", in: window)
    reveal(choice, in: window); await settle(host)
    #expect(choice.accessibilityPerformPress())
    let deadline = ContinuousClock.now.advanced(by: .seconds(3))
    while (dojo.document?.choices.count ?? 0) == originalChoices && ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(dojo.document?.choices.count == originalChoices + 1)
    #expect(dojo.candidate?.id == candidate.id && dojo.stage == .explore)
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

private actor NativeDojoLayoutRenderer {
  private(set) var calls = 0
  func render(_ data: Data, _ recipe: FlowArtistRecipe, _ pen: PlotterModel.StrokeStyle) throws -> PortraitRenderResult {
    calls += 1
    let strokes = try (0..<12).map { index in
      let value = recipe.values[index % recipe.values.count]
      return LogicalStroke(id: StrokeID(), path: try Polyline(points: [
        .init(x: 8, y: Double(index) * 8 + 8),
        .init(x: 30 + value * 60, y: Double(index) * 8 + 8 + value * 3)]), style: pen, ordering: UInt32(index))
    }
    let program = try DrawingProgram(id: ProgramID(), fieldExtent: .init(width: 100, height: 110),
      strokes: strokes, source: .init(kind: "portrait", sourceIdentifier: "native-layout-fixture|" + DrawingPackageCodec.sha256(data)))
    return .init(raster: portraitTestRaster(), program: program)
  }
}
