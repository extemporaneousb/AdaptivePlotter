import CoreGraphics
import Foundation
import PlotterEpisodeModel
import PlotterEpisodeRuntime
import PlotterModel
import PlotterRuntime
import Testing

@testable import PlotterApp

@Suite("Dark-blue cap reference admission")
struct PenCapBlueReferenceAdmissionTests {
  @MainActor
  @Test("LIVE cap-reference rejection reaches the active video selection presentation")
  func liveRejectionReachesVideo() async throws {
    let log = EventLog()
    let machine = try LowerMachineSessionFixture(log: log)
    let camera = try TestObservationCameraSession()
    let app = plotterApplicationRuntime(machine: machine, camera: camera,
      loadPenCapAppearanceSelection: { nil }, log: log)
    do {
      await submitObservationConfigurationForTest(app, .selectSource(.live, nil))
      await app.establishMachineSession(machine.descriptor)
      await submitControllerSession(app, .requestPassiveProbe)
      let owner = LearningPathItemID.humanGuidedDiscovery(.penInteraction)
      await app.performTestExerciseAction(.start, for: owner)
      let initial = app.testActionSurfacePresentation
      let request = try #require(initial.pointSelectionRequest)
      let displayed = try #require(initial.displayedFrame)
      guard case .live = displayed.source else {
        Issue.record("This regression must exercise the LIVE presentation adapter")
        await app.shutdown()
        return
      }
      #expect(initial.pointSelectionFailure == nil)
      app.submitPointSelection(PlotterPointSelectionSubmission(selectionID: request.id,
        frame: request.frame, point: try Point2(x: 4, y: 4),
        presentationTransformRevision: request.presentationTransformRevision,
        referenceRegion: try AxisAlignedBounds(minX: 2, minY: 2, maxX: 8, maxY: 8)))
      try await waitUntil { app.discoveryError != nil }
      let refusal = try #require(app.discoveryError)
      #expect(refusal.contains(PenCapReferenceError.invalidRegion.localizedDescription))
      let rejected = app.testActionSurfacePresentation
      #expect(rejected.pointSelectionFailure == refusal)
      #expect(rejected.pointSelectionRequest == request)
      #expect(rejected.displayedFrame?.frame.id == displayed.frame.id)
      #expect(app.pointSelectionEpisodeProjection.exactPointSelection.selectedPoints.isEmpty)
      #expect(await machine.requestedPenCommands.isEmpty)
      #expect(await machine.requestedFeeds.isEmpty)

      // Initial identification is cancelled through Learning Off; the separate
      // reidentification workflow has its own Cancel action.
      #expect(app.learningIsEnabled)
      await app.submitTestPlotterUIAction(PlotterAppUIActionID.learningMode)
      #expect(app.testActionSurfacePresentation.pointSelectionRequest == nil)
      #expect(app.testActionSurfacePresentation.pointSelectionFailure == nil)
      await app.shutdown()
    } catch {
      await app.shutdown()
      throw error
    }
  }

  @Test("a dark-blue cap and holder admit the clicked anchor and override legacy green detection",
    arguments: [FramePixelFormat.rgba8, .bgra8])
  func darkBlueReference(pixelFormat: FramePixelFormat) async throws {
    let configuration = CameraConfigurationID()
    let frame = try blueScene(configuration: configuration, pixelFormat: pixelFormat)
    let displayed = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "blue-reference-fixture")), frame: frame)
    let runtime = PlotterPointSelectionRuntime()
    let stage = try await runtime.stage(frame: displayed,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the cap inside its holder rectangle", purpose: .penCapAppearance,
      requiredPointCount: 1)
    let bounds = try AxisAlignedBounds<CameraPixelSpace>(minX: 20, minY: 16, maxX: 48, maxY: 40)
    let submission = try #require(ExactFramePointSubmissionBuilder.submission(
      presentation: ActionSurfacePresentation(displayedFrame: displayed, overlays: [],
        pointSelectionRequest: stage.request),
      viewport: ActionSurfaceViewportState(), at: CGPoint(x: 48, y: 70),
      viewSize: CGSize(width: 288, height: 192), referenceRegion: bounds))
    let anchor = try Point2<CameraPixelSpace>(x: 24, y: 35)
    #expect(submission.point == anchor)
    let result = try await runtime.submit(submission)
    guard case let .acceptedPenCap(sample, acceptedFrame, projection) = result else {
      Issue.record("A detailed dark-blue cap reference must not require green or bright cap pixels")
      return
    }
    let reference = try #require(sample.visualReference)
    #expect(reference.isValid)
    #expect(reference.anchor == anchor)
    #expect(sample.clickPoint == anchor)
    #expect(reference.region == PixelRect(x: 20, y: 16, width: 28, height: 24))
    #expect(reference.anchor.x != Double(reference.region.x) + Double(reference.region.width) / 2)
    #expect(reference.anchor.y != Double(reference.region.y) + Double(reference.region.height) / 2)
    #expect(sample.blue > sample.red && sample.blue > sample.green)
    let anchorOffset = (19 * reference.sampleWidth + 4) * 3
    #expect(Array(reference.rgb[anchorOffset..<(anchorOffset + 3)]) == [8, 12, 42])
    #expect(acceptedFrame.source == displayed.source)
    #expect(acceptedFrame.frame.id == frame.id)
    #expect(projection.exactPointSelection.phase == .accepted)
    #expect(projection.exactPointSelection.selectedPoints == [anchor])

    let translated = try blueScene(configuration: configuration, pixelFormat: pixelFormat,
      originX: 76, originY: 38)
    let legacy = try await VisionWorker().inspectPlotterScene(in: translated,
      requestedFeatures: [.penCap], penCapColor: .green)
    #expect(legacy.penCap.measurement == nil)
    let recognized = try await VisionWorker().inspectPlotterScene(in: translated,
      requestedFeatures: [.penCap], penCapColor: .green, penCapReference: reference)
    let cap = try #require(recognized.penCap.measurement)
    #expect(abs(cap.trackingPoint.x - 80) <= 1.5)
    #expect(abs(cap.trackingPoint.y - 57) <= 1.5)
    #expect(recognized.algorithmRevision.contains(reference.identity))
  }

  @Test("a uniform blue rectangle returns a detail remedy and permits a larger-rectangle retry")
  func lowDetailRetry() async throws {
    let frame = DisplayedFrame(source: .live(CameraDeviceID(rawValue: "blue-reference-fixture")),
      frame: try blueScene(configuration: CameraConfigurationID(), pixelFormat: .rgba8))
    let runtime = PlotterPointSelectionRuntime()
    let stage = try await runtime.stage(frame: frame,
      presentationTransformRevision: PlotterPresentationTransformRevision(),
      prompt: "Select the cap inside its holder rectangle", purpose: .penCapAppearance,
      requiredPointCount: 1)
    let anchor = try Point2<CameraPixelSpace>(x: 24, y: 35)
    let uniformCap = PlotterPointSelectionSubmission(selectionID: stage.request.id,
      frame: stage.request.frame, point: anchor,
      presentationTransformRevision: stage.request.presentationTransformRevision,
      referenceRegion: try AxisAlignedBounds(minX: 20, minY: 28, maxX: 32, maxY: 40))
    let refused = try await runtime.submit(uniformCap)
    guard case let .refused(projection, reason) = refused else {
      Issue.record("A uniform patch should report insufficient detail, not silently accept a color")
      return
    }
    #expect(reason == PenCapReferenceError.insufficientDetail.localizedDescription)
    #expect(projection.remedy == reason)
    #expect(projection.exactPointSelection.request?.id == stage.request.id)
    #expect(projection.exactPointSelection.phase == .collecting)
    #expect(projection.exactPointSelection.selectedPoints.isEmpty)

    let withHolder = PlotterPointSelectionSubmission(selectionID: stage.request.id,
      frame: stage.request.frame, point: anchor,
      presentationTransformRevision: stage.request.presentationTransformRevision,
      referenceRegion: try AxisAlignedBounds(minX: 20, minY: 16, maxX: 48, maxY: 40))
    let retried = try await runtime.submit(withHolder)
    guard case let .acceptedPenCap(sample, _, accepted) = retried else {
      Issue.record("A refusal must leave the same frozen-frame selection available for correction")
      return
    }
    #expect(sample.visualReference?.anchor == anchor)
    #expect(accepted.exactPointSelection.selectedPoints == [anchor])
    #expect(accepted.exactPointSelection.phase == .accepted)
  }

  private func blueScene(configuration: CameraConfigurationID, pixelFormat: FramePixelFormat,
    originX: Int = 20, originY: Int = 16) throws -> StampedFrame {
    let width = 144, height = 96
    var bytes = [UInt8](repeating: 220, count: width * height * 4)
    for index in stride(from: 3, to: bytes.count, by: 4) { bytes[index] = 255 }
    for y in 0..<24 {
      for x in 0..<28 {
        let rgb: [UInt8]
        if x < 12 && y >= 12 {
          // All cap channels are below the legacy chromatic detector's value floor.
          rgb = [8, 12, 42]
        } else if x > 17 && y < 17 {
          rgb = [75, 75, 75]
        } else if (x > 10 && x < 14) || y < 3 {
          rgb = [170, 170, 170]
        } else {
          rgb = [12, 12, 14]
        }
        let index = ((originY + y) * width + originX + x) * 4
        bytes[index] = rgb[pixelFormat == .rgba8 ? 0 : 2]
        bytes[index + 1] = rgb[1]
        bytes[index + 2] = rgb[pixelFormat == .rgba8 ? 2 : 0]
      }
    }
    return try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: configuration, width: width, height: height,
      rowBytes: width * 4, pixelFormat: pixelFormat, bytes: OwnedFrameBytes(bytes))
  }
}
