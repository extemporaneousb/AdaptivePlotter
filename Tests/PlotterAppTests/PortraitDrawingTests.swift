import AppKit
import Foundation
import PlotterModel
import SwiftUI
import Testing

@testable import PlotterApp
@testable import PlotterRuntime

@Suite("Portrait authoring")
struct PortraitDrawingTests {
  @Test("supplied reference photo produces face-localized portrait styles",
        .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_REFERENCE_PHOTO"] != nil))
  @MainActor
  func referencePhoto() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PORTRAIT_REFERENCE_PHOTO"])
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let start = ContinuousClock.now
    let raster = try await Task.detached {
      try PortraitImageAnalyzer.analyze(data: data, options: PortraitAnalysisOptions())
    }.value
    #expect(raster.analysisSummary.contains("Face crop"))
    #expect(raster.analysisSummary.contains("Person background removed"))
    var programs: [DrawingProgram] = []
    for style in PortraitStyle.allCases {
      programs.append(try PortraitVectorizer.program(
        from: raster, pose: .front, style: style, strokeStyle: portraitTestStyle()))
    }
    print("Portrait reference: \(raster.analysisSummary); styles \(programs.map { $0.strokes.count }); elapsed \(start.duration(to: .now))")
    let comparison = HStack {
      ForEach(Array(programs.enumerated()), id: \.offset) { index, program in
        VStack {
          Text(PortraitStyle.allCases[index].rawValue).font(.headline)
          PortraitProgramPreview(program: program).frame(width: 300, height: 420)
        }
      }
    }.padding().background(.background)
    let renderer = ImageRenderer(content: comparison)
    let image = try #require(renderer.cgImage)
    try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-portrait-styles.png"))
    let presets = PortraitVectorPreset.allCases
    let variants = try presets.map { preset in
      try PortraitStyle.allCases.map { style in
        try PortraitVectorizer.program(from: raster, pose: .front, style: style,
          strokeStyle: portraitTestStyle(), vectorOptions: preset.options)
      }
    }
    let grid = VStack(alignment: .leading, spacing: 16) {
      Text("Marker estimate: 1.5 mm ink at 180 mm drawing height").font(.headline)
      ForEach(presets.indices, id: \.self) { row in
        Text(presets[row].rawValue).font(.headline)
        HStack {
          ForEach(PortraitStyle.allCases.indices, id: \.self) { column in
            VStack {
              Text(PortraitStyle.allCases[column].rawValue).font(.caption)
              PortraitProgramPreview(program: variants[row][column], inkWidth: 1.5, drawingHeight: 180)
                .frame(width: 180, height: 230)
              Text("\(variants[row][column].strokes.count) strokes").font(.caption2)
            }
          }
        }
      }
    }.padding().background(.white).foregroundStyle(.black)
    let gridImage = try #require(ImageRenderer(content: grid).cgImage)
    try PortraitImageAnalyzer.encodedImage(gridImage)
      .write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-portrait-marker-presets.png"))
    let model = PortraitStudioModel()
    model.setPhoto(data, for: .front, strokeStyle: try portraitTestStyle())
    await model.awaitRendering()
    #expect(model.program != nil)
    let editorImage = try await portraitEditorImage(PortraitStudioView(model: model,
      strokeStyle: try portraitTestStyle(), showOnPlotter: { _ in nil }))
    try PortraitImageAnalyzer.encodedImage(editorImage).write(to: URL(fileURLWithPath: "/tmp/adaptiveplotter-portrait-populated.png"))
  }

  @Test("older drawing evidence without source metadata remains readable")
  func legacyProgramReference() throws {
    let program = try PortraitVectorizer.program(from: portraitTestRaster(), pose: .front,
      style: .hatch, strokeStyle: portraitTestStyle())
    let reference = DrawingProgramEvidenceReference(programID: program.id, contentHash: program.contentHash)
    let decoded = try JSONDecoder().decode(DrawingProgramEvidenceReference.self, from: JSONEncoder().encode(reference))
    #expect(decoded.source == nil)
    #expect(decoded.contentHash == program.contentHash)
  }

  @Test("styles preserve deterministic vectors and source identity", arguments: PortraitStyle.allCases)
  func deterministicStyles(_ style: PortraitStyle) throws {
    let strokeStyle = try portraitTestStyle()
    let raster = portraitTestRaster()
    let first = try PortraitVectorizer.program(from: raster, pose: .front, style: style, strokeStyle: strokeStyle)
    let second = try PortraitVectorizer.program(from: raster, pose: .front, style: style, strokeStyle: strokeStyle)
    #expect(first == second)
    #expect(!first.strokes.isEmpty)
    #expect(first.strokes.allSatisfy { $0.style == strokeStyle && $0.semanticRole == .drawing })
    let decoded = try JSONDecoder().decode(DrawingProgram.self, from: JSONEncoder().encode(first))
    #expect(decoded == first)
    let left = try PortraitVectorizer.program(from: raster, pose: .left, style: style, strokeStyle: strokeStyle)
    #expect(left.contentHash != first.contentHash)
    #expect(left.source.sourceIdentifier.contains("pose=Left"))
  }

  @Test("tonal contours join into closed strokes without flattening the shape")
  func closedContours() throws {
    let width = 41
    let values = (0..<(width*width)).map { index in
      hypot(Double(index%width-20), Double(index/width-20)) < 12 ? 0.0 : 1.0
    }
    let raster = PortraitRaster(width: width, height: width, luminance: values,
                                provenance: "circle", analysisSummary: "fixture")
    let program = try PortraitVectorizer.program(from: raster, pose: .front, style: .contours,
                                                 levels: 1, strokeStyle: portraitTestStyle())
    #expect(program.strokes.count == 1)
    let path = try #require(program.strokes.first?.path)
    #expect(path.start == path.end)
    #expect(path.points.count > 8)
    #expect(path.points.count < 60)
    #expect(path.length > 170 && path.length < 210)
  }

  @Test("image decoding and FieldSpace conversion preserve the top of the portrait")
  func imageAndDrawingOrientation() throws {
    let data = try portraitTestImage()
    let raster = try PortraitImageAnalyzer.analyze(
      data: data, options: PortraitAnalysisOptions(cropToFace: false, removeBackground: false))
    #expect(raster.luminance[0] < 0.1)
    #expect(try #require(raster.luminance.last) > 0.9)
    let program = try PortraitVectorizer.program(from: raster, pose: .left, style: .hatch,
                                                 strokeStyle: portraitTestStyle())
    #expect(program.strokes.flatMap(\.path.points).allSatisfy { $0.y > 65 })
  }

  @Test("missed face detection retains the image for vectorization")
  func noFaceDoesNotBlockDrawing() throws {
    let raster = try PortraitImageAnalyzer.analyze(data: portraitTestImage(), options: PortraitAnalysisOptions())
    #expect(raster.analysisSummary.lowercased().contains("full photo"))
    let program = try PortraitVectorizer.program(from: raster, pose: .right, style: .hatch,
                                                 strokeStyle: portraitTestStyle())
    #expect(!program.strokes.isEmpty)
  }

  @Test("continuous hatch scans retain full runs instead of individual cell marks")
  func continuousHatching() throws {
    let raster = PortraitRaster(width: 100, height: 100, luminance: Array(repeating: 0.1, count: 10_000),
                                provenance: "dark", analysisSummary: "fixture")
    let hatch = try PortraitVectorizer.program(from: raster, pose: .front, style: .hatch, strokeStyle: portraitTestStyle())
    let cross = try PortraitVectorizer.program(from: raster, pose: .front, style: .crosshatch, strokeStyle: portraitTestStyle())
    #expect(hatch.strokes.count == 49)
    #expect(cross.strokes.count == 98)
    #expect(hatch.strokes.allSatisfy { $0.path.length == 100 })
  }

  @Test("rapid portrait edits coalesce behind held analysis and publish the newest result")
  @MainActor
  func renderCoalescing() async throws {
    let renderer = try HeldPortraitRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let style = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: style)
    try await renderer.waitUntilEntered()
    for index in 0..<20 {
      model.style = PortraitStyle.allCases[index % PortraitStyle.allCases.count]
      model.render(strokeStyle: style)
    }
    model.pose = .left
    model.style = .crosshatch
    model.setPhoto(Data([2]), for: .left, strokeStyle: style)
    #expect(model.renderDiagnostics.activeWorkerCount == 1)
    #expect(model.renderDiagnostics.startedWorkerCount == 1)
    await renderer.release()
    await model.awaitRendering()
    #expect(model.renderDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.renderDiagnostics.startedWorkerCount == 2)
    #expect(model.renderDiagnostics.settledWorkerCount == 2)
    #expect(await renderer.maximumConcurrentCount == 1)
    #expect(model.program?.source.sourceIdentifier.contains("pose=Left|style=Crosshatch") == true)
    #expect(!model.isProcessing)
  }

  @Test("cancelling held portrait work settles it, preserves photos, and permits reuse")
  @MainActor
  func renderCancellationAndReuse() async throws {
    let renderer = try HeldPortraitRenderer()
    let model = PortraitStudioModel(renderer: renderer)
    let style = try portraitTestStyle()
    model.setPhoto(Data([1]), for: .front, strokeStyle: style)
    try await renderer.waitUntilEntered()
    let cancellation = Task { await model.cancelRendering() }
    try await awaitPortraitTestState { !model.isProcessing }
    #expect(model.renderDiagnostics.activeWorkerCount == 1)
    #expect(model.renderDiagnostics.settledWorkerCount == 0)
    await renderer.release()
    await cancellation.value
    #expect(model.program == nil)
    #expect(model.photos.count == 1)
    #expect(model.renderDiagnostics.activeWorkerCount == 0)
    model.style = .hatch
    model.render(strokeStyle: style)
    await model.awaitRendering()
    #expect(model.program?.source.sourceIdentifier.contains("style=Hatch") == true)
    let program = model.program
    await model.shutdown()
    model.style = .crosshatch
    model.render(strokeStyle: style)
    #expect(model.program == program)
    #expect(model.renderDiagnostics.startedWorkerCount == 2)
  }

  @Test("pose switching and rapid style changes publish only the selected portrait")
  @MainActor
  func poseSelection() async throws {
    let model = PortraitStudioModel()
    model.options = PortraitAnalysisOptions(cropToFace: false, removeBackground: false)
    let style = try portraitTestStyle()
    let data = try portraitTestImage()
    model.setPhoto(data, for: .front, strokeStyle: style)
    model.pose = .left
    model.setPhoto(data, for: .left, strokeStyle: style)
    model.style = .crosshatch
    model.render(strokeStyle: style)
    await model.awaitRendering()
    let program = try #require(model.program)
    #expect(program.source.sourceIdentifier.contains("pose=Left|style=Crosshatch"))
    #expect(model.photos.count == 2)
    model.pose = .right
    model.render(strokeStyle: style)
    #expect(model.program == nil)
    #expect(!model.isProcessing)
  }

  @Test("held image import coalesces repeated acquisitions and publishes only the newest photo")
  @MainActor
  func acquisitionReplacement() async throws {
    let acquirer = HeldPortraitAcquirer()
    let model = PortraitStudioModel(renderer: try HeldPortraitRenderer(holdFirst: false), photoAcquirer: acquirer)
    let style = try portraitTestStyle()
    let first = Task { await model.importPhoto(URL(fileURLWithPath: "/tmp/1"), strokeStyle: style) }
    try await acquirer.waitUntilEntered()
    var replacements: [Task<Void, Never>] = []
    for index in 2...21 {
      replacements.append(Task { await model.importPhoto(URL(fileURLWithPath: "/tmp/\(index)"), strokeStyle: style) })
      try await awaitPortraitTestState { model.acquisitionDiagnostics.requestedWorkCount >= index }
    }
    #expect(model.photos.isEmpty)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 1)
    await acquirer.release()
    await first.value
    for replacement in replacements { await replacement.value }
    await model.awaitRendering()
    #expect(model.photos[.front] == Data([21]))
    #expect(await acquirer.inputs == [1, 21])
    #expect(model.acquisitionDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.acquisitionDiagnostics.settledWorkerCount == 2)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("source cancellation joins held capture encoding before returning and permits later import")
  @MainActor
  func acquisitionSourceCancellationAndReuse() async throws {
    let driver = PortraitAcquisitionDriver()
    let acquirer = HeldPortraitAcquirer()
    let model = PortraitStudioModel(camera: CameraCapture(driver: driver),
      renderer: try HeldPortraitRenderer(holdFirst: false), photoAcquirer: acquirer)
    let style = try portraitTestStyle()
    await model.discover(excluding: nil)
    await model.startCamera()
    await driver.emit()
    try await awaitPortraitTestState { model.preview.frame != nil }
    let capture = Task { await model.capture(strokeStyle: style) }
    // Model a continuing camera stream so the exposure boundary cannot
    // consume the test's sole frame when the main actor is busy.
    let frames = Task {
      var timestamp: UInt64 = 2
      while !Task.isCancelled && timestamp < 255 {
        await driver.emit(captureNanoseconds: timestamp)
        timestamp += 1
        do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
      }
    }
    defer { frames.cancel() }
    try await acquirer.waitUntilEntered()
    frames.cancel()
    await frames.value
    var didSettle = false
    let cancellation = Task { await model.cancelRendering(); didSettle = true }
    try await awaitPortraitTestState { model.acquisitionDiagnostics.cancellationCount > 0 }
    #expect(!didSettle)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 1)
    #expect(model.acquisitionDiagnostics.settledWorkerCount == 0)
    await acquirer.release()
    await cancellation.value
    await capture.value
    #expect(model.photos.isEmpty)
    #expect(model.renderDiagnostics.startedWorkerCount == 0)
    await model.importPhoto(URL(fileURLWithPath: "/tmp/2"), strokeStyle: style)
    await model.awaitRendering()
    #expect(model.photos[.front] == Data([2]))
    #expect(model.program != nil)
    #expect(model.acquisitionDiagnostics.maximumConcurrentWorkerCount == 1)
    #expect(model.workDiagnostics.maximumConcurrentWorkerCount == 1)
    await model.shutdown()
  }

  @Test("shutdown joins held photo decoding and cannot publish a photo, render, or error afterwards")
  @MainActor
  func acquisitionShutdown() async throws {
    let acquirer = HeldPortraitAcquirer()
    let model = PortraitStudioModel(renderer: try HeldPortraitRenderer(holdFirst: false), photoAcquirer: acquirer)
    let style = try portraitTestStyle()
    let importing = Task { await model.importPhoto(URL(fileURLWithPath: "/tmp/1"), strokeStyle: style) }
    try await acquirer.waitUntilEntered()
    let originalSummary = model.summary
    var didSettle = false
    let shutdown = Task { await model.shutdown(); didSettle = true }
    try await awaitPortraitTestState { model.acquisitionDiagnostics.cancellationCount > 0 }
    #expect(!didSettle)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 1)
    #expect(model.acquisitionDiagnostics.settledWorkerCount == 0)
    await acquirer.release()
    await shutdown.value
    await importing.value
    await model.importPhoto(URL(fileURLWithPath: "/tmp/2"), strokeStyle: style)
    model.setPhoto(Data([3]), for: .front, strokeStyle: style)
    #expect(model.photos.isEmpty)
    #expect(model.summary == originalSummary)
    #expect(model.renderDiagnostics.startedWorkerCount == 0)
    #expect(model.acquisitionDiagnostics.startedWorkerCount == 1)
    #expect(model.acquisitionDiagnostics.activeWorkerCount == 0)
  }

  @Test("portrait panel renders in narrow and wide docks", arguments: [320, 760])
  @MainActor
  func editorLayout(width: Int) async throws {
    let view = PortraitStudioView(model: PortraitStudioModel(),
                                  strokeStyle: try portraitTestStyle(), showOnPlotter: { _ in nil })
    let image = try await portraitEditorImage(view, width: width)
    #expect(image.width >= width)
    #expect(image.width * 610 == image.height * width)
    if let path = ProcessInfo.processInfo.environment["PORTRAIT_UI_SNAPSHOT"] {
      let output = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("\(width).png")
      try PortraitImageAnalyzer.encodedImage(image).write(to: output)
    }
  }
}

func portraitTestStyle() throws -> PlotterModel.StrokeStyle {
  try PlotterModel.StrokeStyle(nominalLineWidth: 0.4,
                  penProfileID: PenProfileID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!))
}

func portraitTestRaster() -> PortraitRaster {
  let width = 80, height = 100
  let values = (0..<(width*height)).map { index -> Double in
    let x = Double(index%width-40)/30, y = Double(index/width-50)/42
    let radius = x*x+y*y
    return radius > 1 ? 1 : min(0.9, 0.15+radius*0.5+(x+1)*0.1)
  }
  return PortraitRaster(width: width, height: height, luminance: values,
                        provenance: "synthetic-tonal-ellipse", analysisSummary: "Synthetic fixture")
}

func portraitTestImage() throws -> Data {
  let width = 60, height = 80
  let bytes = Data((0..<(width*height)).map { $0/width < 20 ? UInt8(0) : UInt8(255) })
  let provider = try #require(CGDataProvider(data: bytes as CFData))
  let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
                                  bitsPerPixel: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
  return try PortraitImageAnalyzer.encodedImage(image)
}

private actor HeldPortraitRenderer: PortraitRendering {
  private var results: [String: PortraitRenderResult] = [:]
  private var entered = false
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  private var activeCount = 0
  private(set) var maximumConcurrentCount = 0

  init(holdFirst: Bool = true) throws {
    entered = !holdFirst
  }

  func render(_ request: PortraitRenderRequest) async throws -> PortraitRenderResult {
    activeCount += 1
    maximumConcurrentCount = max(maximumConcurrentCount, activeCount)
    defer { activeCount -= 1 }
    if !entered {
      entered = true
      await withCheckedContinuation { releaseWaiter = $0 }
    }
    // Deliberately ignores cancellation like a synchronous Vision request.
    // Build fixture vectors off the MainActor so other lifecycle tests can
    // reach their suspended workers while structural sketch generation runs.
    let key = request.pose.rawValue + request.style.rawValue
    if let result = results[key] { return result }
    let result = try await Task.detached {
      let raster = portraitTestRaster()
      return PortraitRenderResult(raster: raster,
        program: try PortraitVectorizer.program(from: raster, pose: request.pose,
          style: request.style, strokeStyle: portraitTestStyle()))
    }.value
    results[key] = result
    return result
  }

  func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !entered {
      try #require(ContinuousClock.now < deadline, "Held portrait renderer was never entered.")
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private actor HeldPortraitAcquirer: PortraitPhotoAcquiring {
  private(set) var inputs: [UInt8] = []
  private var releaseWaiter: CheckedContinuation<Void, Never>?
  func acquire(_ input: PortraitPhotoInput) async throws -> Data {
    let identifier: UInt8
    switch input {
    case .file(let url): identifier = UInt8(url.lastPathComponent)!
    case .frame(let frame): identifier = UInt8(frame.captureNanoseconds)
    }
    inputs.append(identifier)
    if inputs.count == 1 {
      await withCheckedContinuation { releaseWaiter = $0 }
    }
    // Models synchronous image decoding/encoding that cannot be preempted.
    return Data([identifier])
  }
  func waitUntilEntered() async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while inputs.isEmpty {
      try #require(ContinuousClock.now < deadline, "Held portrait acquisition was never entered.")
      try await Task.sleep(for: .milliseconds(1))
    }
  }
  func release() { releaseWaiter?.resume(); releaseWaiter = nil }
}

@MainActor
private func awaitPortraitTestState(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(5))
  while !condition() {
    try #require(ContinuousClock.now < deadline, "Portrait lifecycle state did not settle before the deadline.")
    try await Task.sleep(for: .milliseconds(1))
  }
}

private actor PortraitAcquisitionDriver: CameraCaptureDriver {
  var handler: (@Sendable (CameraDriverEvent) -> Void)?
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] { [.init(id: .init(rawValue: "portrait"), name: "Portrait fixture")] }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    handler = eventHandler
    return .init(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async { handler = nil }
  func emit(captureNanoseconds: UInt64 = 1) {
    handler?(.frame(.init(width: 2, height: 2, rowBytes: 8,
      bytes: Data(repeating: 0, count: 16), captureNanoseconds: captureNanoseconds)))
  }
}

@MainActor
private func portraitEditorImage(_ view: PortraitStudioView, width: Int = 760) async throws -> CGImage {
  _ = NSApplication.shared
  let host = NSHostingView(rootView: ScrollView { view.padding(12) }
    .frame(width: CGFloat(width), height: 610)
    .environment(\.colorScheme, .light)
    .background(Color(nsColor: .windowBackgroundColor)))
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: CGFloat(width), height: 610),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.appearance = NSAppearance(named: .aqua)
  window.contentView = host
  host.frame = NSRect(x: 0, y: 0, width: CGFloat(width), height: 610)
  host.layoutSubtreeIfNeeded()
  try await Task.sleep(for: .milliseconds(100))
  host.layoutSubtreeIfNeeded()
  window.display()
  host.display()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let image = try #require(bitmap.cgImage)
  window.close()
  return image
}
