import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore
import PortraitLibrary
import PortraitStudioUI
import Testing
import UniformTypeIdentifiers
@testable import PortraitStudio

@Suite("Standalone Studio composition", .serialized)
@MainActor
struct PortraitStudioCompositionTests {
  @Test("Selecting another camera restarts only the Studio camera owner")
  func cameraReselection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let driver = StudioTestCameraDriver()
    let studio = PortraitStudioComposition(directoryURL: directory, camera: CameraCapture(driver: driver))
    await studio.start()
    #expect(studio.model.devices.count == 2)
    studio.model.selectedDeviceID = .init(rawValue: "studio-first")
    #expect(await studio.selectCamera() == nil)
    #expect(studio.model.cameraIsRunning)
    #expect(await studio.selectCamera() == nil)
    #expect(await driver.startedDevices == [.init(rawValue: "studio-first")])
    studio.model.selectedDeviceID = .init(rawValue: "studio-second")
    #expect(await studio.selectCamera() == nil)
    #expect(await driver.startedDevices == [.init(rawValue: "studio-first"), .init(rawValue: "studio-second")])
    await studio.shutdown()
    #expect(!studio.model.cameraIsRunning)
    #expect(await studio.selectCamera() != nil)
    #expect(await driver.startedDevices.count == 2)
  }

  @Test("Synthetic photo authoring saves and exchanges an exact durable result between private libraries")
  func authoringExchangeRoundTrip() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("synthetic-source.png")
    try Self.syntheticPhoto().write(to: sourceURL)
    let authorURL = root.appendingPathComponent("author", isDirectory: true)
    let receiverURL = root.appendingPathComponent("receiver", isDirectory: true)
    let author = PortraitStudioComposition(directoryURL: authorURL,
      camera: CameraCapture(driver: StudioTestCameraDriver()))
    let receiver = PortraitStudioComposition(directoryURL: receiverURL,
      camera: CameraCapture(driver: StudioTestCameraDriver()))
    do {
      author.model.options.cropToFace = false
      author.model.options.removeBackground = false
      await author.model.importPhoto(sourceURL, strokeStyle: author.strokeStyle)
      await author.model.awaitRendering()
      let candidate = try #require(author.model.selectedCandidate)
      #expect(!candidate.program.strokes.isEmpty)
      #expect(await author.model.saveSelectedDrawing() == nil)
      let drawing = SavedDrawing(candidate: candidate)
      let exported = try await author.model.sketches.exportDrawingPackage(drawing)
      let package = try DrawingPackageCodec.decode(exported)
      #expect(package.program == candidate.program)
      #expect(package.source.bytes == candidate.sourceData)
      #expect(package.origin.programHash == candidate.program.contentHash)
      #expect(package.origin.captureID == candidate.photoID)
      #expect(DrawingPackageCodec.sha256(package.resultRecordJSON) == package.origin.resultRecordSHA256)
      await author.shutdown()

      let reopened = PortraitStudioComposition(directoryURL: authorURL,
        camera: CameraCapture(driver: StudioTestCameraDriver()))
      do {
        let retained = try await reopened.model.sketches.drawingForBrowsing(drawing.id, photoID: candidate.photoID)
        let reexported = try await reopened.model.sketches.exportDrawingPackage(retained)
        #expect(reexported == exported)
        await reopened.shutdown()
      } catch {
        await reopened.shutdown()
        throw error
      }

      let imported = try await receiver.model.sketches.importDrawingPackage(exported, restoreDeleted: true)
      #expect(imported.program == candidate.program)
      #expect(imported.transferredPackage?.origin == package.origin)
      #expect(imported.sourceImageData == candidate.sourceData)
      #expect(imported.sourcePhotoID == nil)
      #expect(imported.portraitCandidate == nil)
      #expect(try await receiver.model.sketches.exportDrawingPackage(imported) == exported)
      receiver.showsLibrary = true
      await receiver.browser.reload()
      await receiver.browser.selectDrawing(imported.id)
      #expect(receiver.browser.drawing?.program == candidate.program)
      #expect(receiver.browser.sourceData == candidate.sourceData)
      #expect(receiver.browser.photos.isEmpty)
      await receiver.editSelection()
      #expect(receiver.showsLibrary)
      #expect(receiver.model.selectedCandidate == nil)
      await receiver.shutdown()
    } catch {
      await author.shutdown()
      await receiver.shutdown()
      throw error
    }
  }

  @Test("Native drawing selection keeps the capture occurrence when candidate IDs coincide")
  func sameCandidateDifferentCaptureSelection() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("source.png")
    try Self.syntheticPhoto().write(to: source)
    let studio = PortraitStudioComposition(directoryURL: directory.appendingPathComponent("library"),
      camera: CameraCapture(driver: StudioTestCameraDriver()))
    do {
      studio.model.options.cropToFace = false
      studio.model.options.removeBackground = false
      await studio.model.importPhoto(source, strokeStyle: studio.strokeStyle)
      await studio.model.awaitRendering()
      let first = try #require(studio.model.selectedCandidate)
      let sourceSnapshot = try await studio.model.experimentalSourceSnapshot()
      #expect(studio.model.admitsExperimentalSource(sourceSnapshot))
      let second = try PortraitCandidate(sourceData: first.sourceData, sourcePixelExtent: first.sourcePixelExtent,
        raster: first.raster, recipe: first.recipe, program: first.program, photoID: UUID(),
        captureSessionID: UUID(), createdAt: first.createdAt.addingTimeInterval(1), lineage: first.lineage,
        checkpointID: first.checkpointID, pose: first.pose, proposal: first.proposal, warpManifest: first.warpManifest)
      #expect(first.id == second.id)
      #expect(first.photoID != second.photoID)
      let drawingA = SavedDrawing(candidate: first), drawingB = SavedDrawing(candidate: second)
      #expect(SavedDrawingSummary(drawingA).studioRowID != SavedDrawingSummary(drawingB).studioRowID)
      #expect(await studio.model.sketches.saveDrawing(drawingA) == nil)
      #expect(await studio.model.sketches.saveDrawing(drawingB) == nil)
      await studio.browser.reload()
      await studio.browser.selectDrawing(SavedDrawingSummary(drawingA))
      #expect(studio.browser.selectedPhotoID == first.photoID)
      await studio.browser.selectDrawing(SavedDrawingSummary(drawingB))
      #expect(studio.browser.selectedPhotoID == second.photoID)
      let selected = try #require(studio.browser.drawing)
      #expect(selected.portraitCandidate?.photoID == second.photoID)
      #expect(studio.browser.sourceData == second.sourceData)
      let package = try DrawingPackageCodec.decode(await studio.model.sketches.exportDrawingPackage(selected))
      #expect(package.origin.captureID == second.photoID)
      #expect(package.source.bytes == second.sourceData)
      await studio.editSelection()
      #expect(studio.model.selectedCandidate?.photoID == second.photoID)
      #expect(studio.model.selectedPhotoID == second.photoID)
      #expect(!studio.model.admitsExperimentalSource(sourceSnapshot))
      #expect(sourceSnapshot.admission.isCancelled)
      await studio.shutdown()
    } catch {
      await studio.shutdown()
      throw error
    }
  }

  private static func syntheticPhoto() throws -> Data {
    let width = 96, height = 128
    var pixels: [UInt8] = []
    pixels.reserveCapacity(width * height)
    for index in 0..<(width * height) {
      let x = index % width
      let y = index / width
      let checker = ((x / 12 + y / 16) % 2) * 90
      pixels.append(UInt8((x * 3 + y * 2 + checker) % 256))
    }
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
      bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider,
      decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let output = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return output as Data
  }
}

private actor StudioTestCameraDriver: CameraCaptureDriver {
  private(set) var startedDevices: [CameraDeviceID] = []
  func authorizationState() async -> CameraAuthorizationState { .authorized }
  func requestAccess() async -> Bool { true }
  func discoverDevices() async -> [CameraDevice] {
    [CameraDevice(id: .init(rawValue: "studio-first"), name: "First fixture"),
      CameraDevice(id: .init(rawValue: "studio-second"), name: "Second fixture")]
  }
  func start(deviceID: CameraDeviceID, maximumFramesPerSecond: Double?,
    eventHandler: @escaping @Sendable (CameraDriverEvent) -> Void) async throws -> CameraCaptureDriverStartResult {
    startedDevices.append(deviceID)
    return .init(appliedMaximumFramesPerSecond: maximumFramesPerSecond)
  }
  func stop() async {}
}
