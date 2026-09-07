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
    let model = PortraitStudioModel()
    model.setPhoto(data, for: .front, strokeStyle: try portraitTestStyle())
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while model.isProcessing && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    #expect(model.program != nil)
    let editorImage = try await portraitEditorImage(PortraitStudioView(model: model, plotterCameraID: nil,
      strokeStyle: try portraitTestStyle(), useProgram: { _ in nil }))
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
    #expect(first.strokes.count > 1)
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

  @Test("portrait camera never selects or changes the observation camera")
  @MainActor
  func cameraOwnership() async throws {
    let plotterID = CameraDeviceID(rawValue: "plotter")
    let faceID = CameraDeviceID(rawValue: "face")
    let devices = [CameraDevice(id: plotterID, name: "Observation"), CameraDevice(id: faceID, name: "Portrait")]
    let plotterDriver = PortraitTestCameraDriver(devices: devices)
    let portraitDriver = PortraitTestCameraDriver(devices: devices)
    let plotter = CameraCapture(driver: plotterDriver)
    await plotter.discoverDevices()
    try await plotter.select(plotterID)
    await plotter.start()
    let before = await plotter.snapshot()
    let model = PortraitStudioModel(camera: CameraCapture(driver: portraitDriver))
    await model.discover(excluding: plotterID)
    #expect(model.devices.map(\.id) == [faceID])
    await model.startCamera()
    #expect(model.cameraIsRunning)
    #expect(await portraitDriver.startedIDs == [faceID])
    await model.stopCamera()
    #expect(await plotter.snapshot() == before)
    #expect(await plotterDriver.stopCount == 0)
    await plotter.stop()
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
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while model.isProcessing && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    let program = try #require(model.program)
    #expect(program.source.sourceIdentifier.contains("pose=Left|style=Crosshatch"))
    #expect(model.photos.count == 2)
    model.pose = .right
    model.render(strokeStyle: style)
    #expect(model.program == nil)
    #expect(!model.isProcessing)
  }

  @Test("portrait editor renders at its declared desktop size")
  @MainActor
  func editorLayout() async throws {
    let view = PortraitStudioView(model: PortraitStudioModel(), plotterCameraID: nil,
                                  strokeStyle: try portraitTestStyle(), useProgram: { _ in nil })
    let image = try await portraitEditorImage(view)
    #expect(image.width >= 760)
    #expect(image.width * 610 == image.height * 760)
    if let path = ProcessInfo.processInfo.environment["PORTRAIT_UI_SNAPSHOT"] {
      try PortraitImageAnalyzer.encodedImage(image).write(to: URL(fileURLWithPath: path))
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

private actor PortraitTestCameraDriver: CameraCaptureDriver {
  let devices: [CameraDevice]
  private(set) var startedIDs: [CameraDeviceID] = []
  private(set) var stopCount = 0
  init(devices: [CameraDevice]) { self.devices = devices }
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] { devices }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?,
             eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    startedIDs.append(deviceID)
    return CameraCaptureDriverStartResult(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async { stopCount += 1 }
}

@MainActor
private func portraitEditorImage(_ view: PortraitStudioView) async throws -> CGImage {
  _ = NSApplication.shared
  let host = NSHostingView(rootView: view.environment(\.colorScheme, .light)
    .background(Color(nsColor: .windowBackgroundColor)))
  let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 610),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.appearance = NSAppearance(named: .aqua)
  window.contentView = host
  host.frame = NSRect(x: 0, y: 0, width: 760, height: 610)
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
