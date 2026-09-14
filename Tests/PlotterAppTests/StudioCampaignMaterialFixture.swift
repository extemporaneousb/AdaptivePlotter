import Foundation
import PlotterModel
import PlotterRuntime
import Testing
@testable import PlotterApp

/// Software-only paired ink fixture for the cross-feature Studio journey.
/// The caller supplies a loaded durable material library, an active nominal
/// profile, declared paper stock, and current accepted plotter registration.
/// Raster ink and the unobstructed-visibility assertion are synthetic. This
/// exercises measurement/retention; it does not establish physical material accuracy.
@MainActor
func makeStudioCampaignMeasuredMaterial(
  _ fixture: DrawingWorkbenchApplicationFixture
) async throws -> DrawingMaterialRecord {
  let app = fixture.application
  let original = try #require(app.drawingMaterials.activeRecord)
  try #require(original.profile.qualification == .nominal)
  let registration = try #require(app.tipCameraRegistration)
  let applicability = try #require(app.currentMaterialApplicability)
  let displayed = try #require(app.displayedFrame)
  let optical = registration.applicability.opticalConfiguration
  try #require(displayed.source == optical.source)
  try #require(displayed.frame.width == optical.width && displayed.frame.height == optical.height)
  try #require(displayed.frame.pixelFormat == optical.pixelFormat)
  let pose = try #require(app.machineSnapshot?.machine.position)
  let feedsBefore = await fixture.machine.requestedFeeds.count
  let penCommandsBefore = await fixture.machine.requestedPenCommands.count
  let capturesBefore = await fixture.camera.poseCaptureCount
  let pair = try await Task.detached {
    try StudioMaterialPaintPair.make(registration: registration, template: displayed.frame)
  }.value
  let inspection = DrawingMaterialInspection(profile: original.profile,
    applicability: applicability, registration: registration,
    baseline: SamePoseFrameSample(source: displayed.source, frame: pair.baseline, controllerPosition: pose),
    result: SamePoseFrameSample(source: displayed.source, frame: pair.result, controllerPosition: pose),
    paths: [pair.path])
  // This existing inspection input is deliberately explicit: no replacement
  // camera affine, precomputed distribution, invented capture, or motion request.
  app.materialInspection = inspection
  let error = await app.confirmMaterialInspection(inspection)
  try #require(error == nil, "Production material confirmation refused: \(error ?? "")")
  app.drawingMaterialSelectionDidChange()
  let activated = try #require(app.drawingMaterials.activeRecord)
  let measurement = try #require(activated.measurement)
  let distribution = try #require(measurement.distribution,
    "Real estimator found no width samples: \(measurement.limitations.joined(separator: " "))")
  try #require(!measurement.samples.isEmpty)
  #expect(measurement.samples.count >= 3)
  #expect(measurement.samples.allSatisfy {
    $0.firstEdge != $0.secondEdge && $0.uncertaintyMM.isFinite && $0.uncertaintyMM > 0
      && $0.widthMM.isFinite && $0.widthMM > 0
  })
  #expect(measurement.qualification == .controllerCoordinateEstimate || measurement.qualification == .bounded)
  #expect(measurement.qualification != .independentlyMeasured)
  #expect(measurement.registration == registration)
  #expect(measurement.geometry == [pair.path])
  #expect(measurement.observationMode == .pairedNewInk)
  #expect(measurement.alignment?.shiftX == 0 && measurement.alignment?.shiftY == 0)
  #expect(measurement.source == displayed.source)
  #expect(measurement.visibilityEvidence?.inspectedFrames
    == [ExactFrameProvenance(frame: pair.baseline), ExactFrameProvenance(frame: pair.result)])
  #expect(measurement.frames?.baseline == ExactFrameProvenance(frame: pair.baseline))
  #expect(measurement.frames?.post == ExactFrameProvenance(frame: pair.result))
  #expect(distribution.uncertaintyMM > 0)
  let median = try #require(distribution.medianMM)
  // Raster edge quantization is compared in this exact registration's metric.
  // The estimator, not this synthetic ground truth, supplies the saved profile.
  #expect(abs(median - pair.paintedWidthMM) <= pair.perpendicularMMPerPixel * 1.5)
  #expect(activated.profile.id == original.profile.id)
  #expect(activated.profile.revision > original.profile.revision)
  #expect(activated.profile.measurementEvidenceID == measurement.id)
  #expect(activated.profile.depositedWidth == distribution)
  #expect(activated.applicability == applicability)
  #expect(app.drawingMaterials.records.contains(original))
  #expect(app.drawingMaterials.persistenceError == nil)
  #expect(app.drawingMaterials.pendingMutationCount == 0)
  #expect(app.materialInspection == nil)
  let media = try #require(activated.ownedMedia)
  try #require(media.count == 2)
  for (reference, expected) in zip(media, [pair.baseline, pair.result]) {
    let stored = try await fixture.stores.evidenceStore.readMedia(reference)
    #expect(reference.source == displayed.source)
    #expect(reference.frame == ExactFrameProvenance(frame: expected))
    #expect(ExactFrameProvenance(frame: stored) == ExactFrameProvenance(frame: expected))
    #expect(stored.bytes == expected.bytes)
  }
  #expect(media[0].frame.frameSHA256 != media[1].frame.frameSHA256)
  #expect(app.tipCameraRegistration == registration)
  #expect(await fixture.machine.requestedFeeds.count == feedsBefore)
  #expect(await fixture.machine.requestedPenCommands.count == penCommandsBefore)
  #expect(await fixture.camera.poseCaptureCount == capturesBefore)
  return activated
}

private struct StudioMaterialPaintPair: Sendable {
  let baseline: StampedFrame
  let result: StampedFrame
  let path: Polyline<MachineSpace>
  let paintedWidthMM: Double
  let perpendicularMMPerPixel: Double

  static func make(registration: TipCameraRegistration, template: StampedFrame) throws -> Self {
    let transform = registration.cameraFromMachine
    let inverse = try transform.inverted()
    let rectangle = registration.applicabilityRectangle
    let cameraCenter = try transform.applying(to: Point2<MachineSpace>(
      x: (rectangle.minX + rectangle.maxX) / 2,
      y: (rectangle.minY + rectangle.maxY) / 2))
    let maxScale = sqrt(transform.m11 * transform.m11 + transform.m12 * transform.m12
      + transform.m21 * transform.m21 + transform.m22 * transform.m22)
    // Production confirmation scans up to 6 controller-coordinate mm. Leave
    // additional real background outside its full exclusion region for alignment.
    let backgroundMargin = 6 * maxScale + 20
    var selected: (Point2<MachineSpace>, Point2<MachineSpace>, Double)?
    for horizontal in [true, false] {
      for lengthPixels in [120.0, 80.0, 48.0] {
        let dx = horizontal ? lengthPixels / 2 : 0
        let dy = horizontal ? 0 : lengthPixels / 2
        let ca = try Point2<CameraPixelSpace>(x: cameraCenter.x - dx, y: cameraCenter.y - dy)
        let cb = try Point2<CameraPixelSpace>(x: cameraCenter.x + dx, y: cameraCenter.y + dy)
        guard min(ca.x, cb.x) > backgroundMargin,
          min(ca.y, cb.y) > backgroundMargin,
          max(ca.x, cb.x) < Double(template.width) - backgroundMargin,
          max(ca.y, cb.y) < Double(template.height) - backgroundMargin else { continue }
        let a = try inverse.applying(to: ca), b = try inverse.applying(to: cb)
        let length = a.distance(to: b)
        let nx = -(b.y - a.y) / length, ny = (b.x - a.x) / length
        let cameraNX = horizontal ? 0.0 : -1.0
        let cameraNY = horizontal ? 1.0 : 0.0
        let perPixel = abs((nx * inverse.m11 + ny * inverse.m21) * cameraNX
          + (nx * inverse.m12 + ny * inverse.m22) * cameraNY)
        let width = 5 * perPixel
        guard perPixel.isFinite, perPixel > 0, width < 6,
          ceil(6 / perPixel) >= 3, ceil(6 / perPixel) < 512,
          length > width * 8 else { continue }
        func interior(_ point: Point2<MachineSpace>) -> Bool {
          point.x - width > rectangle.minX && point.x + width < rectangle.maxX
            && point.y - width > rectangle.minY && point.y + width < rectangle.maxY
        }
        guard interior(a), interior(b) else { continue }
        selected = (a, b, perPixel)
        break
      }
      if selected != nil { break }
    }
    let (a, b, perPixel) = try #require(selected,
      "Journey registration must support a central resolved stroke and real background; do not replace its affine to satisfy this fixture.")
    let widthMM = perPixel * 5
    let path = try Polyline<MachineSpace>(points: [a, b])
    let bytesPerPixel = template.pixelFormat.bytesPerPixel
    var before = [UInt8](repeating: 0, count: template.rowBytes * template.height)
    var after = before
    let dx = b.x - a.x, dy = b.y - a.y
    let squaredLength = dx * dx + dy * dy
    for y in 0..<template.height {
      try Task.checkCancellation()
      for x in 0..<template.width {
        let background = UInt8(225 + (x * 13 + y * 17) % 25)
        let point = try inverse.applying(to: Point2<CameraPixelSpace>(x: Double(x), y: Double(y)))
        let t = max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / squaredLength))
        let distance = hypot(point.x - a.x - t * dx, point.y - a.y - t * dy)
        let deposited = distance <= widthMM / 2 ? background - 190 : background
        let offset = y * template.rowBytes + x * bytesPerPixel
        switch template.pixelFormat {
        case .gray8:
          before[offset] = background; after[offset] = deposited
        case .rgba8, .bgra8:
          for channel in 0..<3 { before[offset + channel] = background; after[offset + channel] = deposited }
          before[offset + 3] = 255; after[offset + 3] = 255
        }
      }
    }
    try #require(template.sequence < UInt64.max - 2 && template.captureNanoseconds < UInt64.max - 2)
    func frame(_ bytes: [UInt8], offset: UInt64) throws -> StampedFrame {
      try StampedFrame(sequence: template.sequence + offset,
        captureNanoseconds: template.captureNanoseconds + offset,
        cameraConfigurationID: template.cameraConfigurationID,
        width: template.width, height: template.height, rowBytes: template.rowBytes,
        pixelFormat: template.pixelFormat, bytes: OwnedFrameBytes(bytes))
    }
    return try Self(baseline: frame(before, offset: 1), result: frame(after, offset: 2),
      path: path, paintedWidthMM: widthMM, perpendicularMMPerPixel: perPixel)
  }
}
