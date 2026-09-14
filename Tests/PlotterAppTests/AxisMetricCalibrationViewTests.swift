import AppKit
import PlotterModel
import PlotterRuntime
import SwiftUI
import Testing
@testable import PlotterApp

@Suite("Axis metric operator form")
struct AxisMetricCalibrationViewTests {
  @Test("partial ruler entries preserve signed segment association and explicit uncertainty")
  func partialEntries() throws {
    var draft = AxisMetricRulerDraft()
    draft.rows[1] = .init(length: " 123.75 ", uncertainty: "0.25")
    draft.method = "Independent ruler; repeated endpoint readings"
    #expect(draft.validationMessage == nil)
    let values = try draft.measurements()
    #expect(values.count == 1)
    #expect(values.first?.segmentIndex == 1)
    #expect(values.first?.physicalLengthMM == 123.75)
    #expect(values.first?.uncertaintyMM == 0.25)
    #expect(!draft.axesConfirmed)
    #expect(draft.rows[0].isEmpty && draft.rows[2].isEmpty && draft.rows[3].isEmpty)
    draft.rows[3].length = "89"
    #expect(draft.validationMessage != nil)
    #expect(draft.rows[1].length == " 123.75 ")
    draft.rows[3].uncertainty = "0"
    #expect(draft.validationMessage == nil)
    #expect(try draft.measurements().map(\.segmentIndex) == [1, 3])
    for invalid in ["nan", "inf", "-1", "0"] {
      draft.rows[3].length = invalid
      #expect(draft.validationMessage != nil)
    }
  }

  @Test("controller schematic preserves unequal spans and maps +Y upward", arguments: [300.0, 390.0, 600.0])
  func diagramGeometry(width: Double) throws {
    let edges = try sampleEdges()
    let segments = AxisMetricControllerDiagram.segments(edges, size: CGSize(width: width, height: 200))
    #expect(segments.count == 4)
    #expect(edges.map(AxisMetricControllerDiagram.label) == ["1: +Y", "2: +X", "3: −Y", "4: −X"])
    #expect(segments[0].1.y < segments[0].0.y)
    #expect(segments[1].1.x > segments[1].0.x)
    let vertical = abs(segments[0].1.y - segments[0].0.y)
    let horizontal = abs(segments[1].1.x - segments[1].0.x)
    #expect(abs(horizontal / vertical - 2) < 0.000_001)
    for (index, segment) in segments.enumerated() {
      #expect(segment.1 == segments[(index + 1) % segments.count].0)
      for point in [segment.0, segment.1] {
        #expect(point.x >= 50 && point.x <= width - 50)
        #expect(point.y >= 30 && point.y <= 170)
      }
    }
  }

  @MainActor
  @Test("actual native ruler fields fit the hosted form without clipping", arguments: [300.0, 390.0, 600.0])
  func hostedRulerFields(width: Double) async throws {
    let fixture = try await CompleteAcceptedLearningFixture.make()
    let geometry = try LearningFrameMetricGeometry.extract(record: fixture.borderRecord)
    var saveCalls = 0
    var applyCalls = 0
    let form = AxisMetricCalibrationView(geometry: geometry, latestMeasurement: nil,
      proposal: nil, status: "Synthetic fixture: physical metric remains unverified.", busy: false,
      applyUnavailableReason: "Four associated ruler measurements are required.",
      onSave: { _, _, _ in saveCalls += 1 }, onApply: { applyCalls += 1 })
    _ = NSApplication.shared
    let host = NSHostingView(rootView: form.padding(12).frame(width: width)
      .fixedSize(horizontal: false, vertical: true))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 1800),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.close() }
    host.frame = NSRect(x: 0, y: 0, width: width, height: 1800)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    host.layoutSubtreeIfNeeded()
    let fitting = host.fittingSize
    #expect(fitting.width.isFinite && fitting.height.isFinite && fitting.height > 400)
    host.setFrameSize(NSSize(width: width, height: max(1800, fitting.height)))
    host.layoutSubtreeIfNeeded()
    let fields = nativeViews(host).compactMap { $0 as? NSTextField }
      .filter { $0.isEditable && !$0.isHidden }
    // Inspect real native editor geometry. No substitute accessibility tree or
    // generated image is used as evidence of reachable operator controls.
    #expect(fields.count >= 8)
    for field in fields {
      let rect = field.convert(field.bounds, to: host)
      #expect(rect.width >= 60 && rect.height > 0)
      #expect(rect.minX >= -1 && rect.maxX <= width + 1)
      #expect(rect.minY >= -1 && rect.maxY <= host.bounds.height + 1)
    }
    #expect(saveCalls == 0 && applyCalls == 0)
  }

  @MainActor
  private func nativeViews(_ root: NSView) -> [NSView] {
    [root] + root.subviews.flatMap(nativeViews)
  }

  private func sampleEdges() throws -> [LearningFrameMetricEdge] {
    let points = try [Point2<MachineSpace>(x: -30, y: -20), Point2(x: -30, y: 40),
      Point2(x: 90, y: 40), Point2(x: 90, y: -20), Point2(x: -30, y: -20)]
    return try (0..<4).map { index in
      try LearningFrameMetricEdge(segmentIndex: index, axis: index.isMultiple(of: 2) ? .y : .x,
        start: points[index], end: points[index + 1])
    }
  }
}
