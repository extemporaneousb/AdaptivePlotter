import Foundation
import PlotterModel
import Testing
@testable import PlotterRuntime

struct DrawingMaterialContractTests {
  @Test("Measured paired, existing-ink and unavailable records survive exact round trips")
  func supportedProducers() throws {
    for mode in [DrawingMaterialObservationMode.pairedNewInk, .existingInkLocalContrast] {
      for unavailable in [false, true] {
        let record = try fixture(mode: mode, unavailable: unavailable)
        let restored = try JSONDecoder().decode(DrawingMaterialRecord.self, from: JSONEncoder().encode(record))
        #expect(restored == record)
        try restored.validate()
      }
    }
    let nominal = try DrawingMaterialRecord(profile: DrawingMaterialProfileRevision(name: "Nominal", nominalWidthMM: 1))
    #expect(try JSONDecoder().decode(DrawingMaterialRecord.self, from: JSONEncoder().encode(nominal)) == nominal)
  }

  @Test("Registration digest is stable across multi-session decode and set insertion order")
  func stableRegistrationIdentity() throws {
    let first = try TipAuthorityFixture().registration()
    let sessions = [CameraCaptureSessionID(), CameraCaptureSessionID(), CameraCaptureSessionID()]
    let encodedSessions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sessions))
    let second = try JSONDecoder().decode(TipCameraRegistration.self,
      from: replacing(first, path: ["captureSessionIDs"], value: encodedSessions))
    let reversedSessions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sessions.reversed().map { $0 }))
    let third = try JSONDecoder().decode(TipCameraRegistration.self,
      from: replacing(first, path: ["captureSessionIDs"], value: reversedSessions))
    #expect(try DrawingMaterialApplicability.registrationHash(second) == DrawingMaterialApplicability.registrationHash(third))
    let restored = try JSONDecoder().decode(TipCameraRegistration.self, from: JSONEncoder().encode(second))
    #expect(try DrawingMaterialApplicability.registrationHash(second) == DrawingMaterialApplicability.registrationHash(restored))
  }

  @Test("Decoded registration hashes, revisions, applicability and operational fields cannot disagree")
  func applicabilityCorruption() throws {
    let record = try fixture()
    let cases: [([String], Any)] = [
      (["applicability", "registrationSHA256"], String(repeating: "0", count: 64)),
      (["applicability", "registrationRevisionID"], try json(LearningArtifactRevisionID())),
      (["applicability", "calibration", "paperContactPlane"], try json(PaperContactPlaneRevision())),
      (["applicability", "drawingFeedMMPerMinute"], -1),
      (["applicability", "paperStock"], "  "),
      (["applicability", "penActuationProfile", "raisedSpindleValue"], 1001),
      (["applicability", "penActuationProfile", "settleSeconds"], -0.1)
    ]
    for (path, value) in cases {
      let corrupted = try replacing(record, path: path, value: value)
      #expect(throws: (any Error).self) { try JSONDecoder().decode(DrawingMaterialRecord.self, from: corrupted) }
    }
  }

  @Test("Frame modes, sources, identity and overflow-sized provenance are refused")
  func frameCorruption() throws {
    let record = try fixture()
    let cases: [([String], Any)] = [
      (["measurement", "source"], try json(FrameSourceIdentity.simulated)),
      (["measurement", "frames", "source"], try json(FrameSourceIdentity.simulated)),
      (["measurement", "observationMode"], "existingInkLocalContrast"),
      (["measurement", "frames", "baseline", "frameSHA256"], "broken"),
      (["measurement", "frames", "baseline", "width"], Int.max),
      (["measurement", "frames", "post", "rowBytes"], -1),
      (["measurement", "alignment", "evaluatedPixelCount"], -1),
      (["measurement", "alignment", "supportRegion", "width"], Int.max)
    ]
    for (path, value) in cases {
      let corrupted = try replacing(record, path: path, value: value)
      #expect(throws: (any Error).self) { try JSONDecoder().decode(DrawingMaterialRecord.self, from: corrupted) }
    }
  }

  @Test("Samples must bind real geometry, frame edges, perpendicular widths and distributions")
  func sampleCorruption() throws {
    let record = try fixture()
    let cases: [([String], Any)] = [
      (["measurement", "samples", "0", "pathIndex"], -1),
      (["measurement", "samples", "0", "segmentIndex"], 99),
      (["measurement", "samples", "0", "pathFraction"], 2),
      (["measurement", "samples", "0", "directionRadians"], 0.7),
      (["measurement", "samples", "0", "widthMM"], 2),
      (["measurement", "samples", "0", "uncertaintyMM"], -1),
      (["measurement", "samples", "0", "firstEdge", "x"], -1),
      (["measurement", "samples", "0", "secondEdge", "y"], 200),
      (["measurement", "distribution", "sampleCount"], 2),
      (["measurement", "distribution", "directional", "0", "sampleCount"], 2),
      (["measurement", "geometry"], []),
      (["measurement", "algorithmRevision"], " "),
      (["profile", "measurementEvidenceID"], UUID().uuidString),
      (["profile", "depositedWidth", "upperBoundMM"], 2)
    ]
    for (path, value) in cases {
      let corrupted = try replacing(record, path: path, value: value)
      #expect(throws: (any Error).self) { try JSONDecoder().decode(DrawingMaterialRecord.self, from: corrupted) }
    }
  }

  @Test("Optional visibility evidence binds exact frames and source, not a fresh camera frame")
  func visibilityProvenance() throws {
    let record = try fixture(visibility: true)
    #expect(record.measurement?.visibilityEvidence?.method == "operator-confirmed-unobstructed-v1")
    try record.validate()
    let cases: [([String], Any)] = [
      (["measurement", "visibilityEvidence", "method"], "automatic-clear"),
      (["measurement", "visibilityEvidence", "source"], try json(FrameSourceIdentity.simulated)),
      (["measurement", "visibilityEvidence", "inspectedFrames"], []),
      (["measurement", "visibilityEvidence", "inspectedFrames", "0", "frameSHA256"], String(repeating: "0", count: 64))
    ]
    for (path, value) in cases {
      let corrupted = try replacing(record, path: path, value: value)
      #expect(throws: (any Error).self) { try JSONDecoder().decode(DrawingMaterialRecord.self, from: corrupted) }
    }
  }

  @Test("Declared existing-mark conditions retain their origin without claiming recovered run settings")
  func conditionsOrigin() throws {
    let record = try fixture(mode: .existingInkLocalContrast)
    let confirmed = try DrawingMaterialRecord(profile: record.profile, applicability: record.applicability,
      measurement: record.measurement, conditionsOrigin: "operator-confirmed-existing-mark-conditions-v1")
    let restored = try JSONDecoder().decode(DrawingMaterialRecord.self, from: JSONEncoder().encode(confirmed))
    #expect(restored == confirmed)
    let corrupted = try replacing(confirmed, path: ["conditionsOrigin"], value: "recovered-original-request")
    #expect(throws: (any Error).self) { try JSONDecoder().decode(DrawingMaterialRecord.self, from: corrupted) }
  }

  @Test("Non-finite in-memory sample values and profile dates cannot be retained")
  func constructorValidation() throws {
    let record = try fixture()
    let measurement = try #require(record.measurement)
    let sample = try #require(measurement.samples.first)
    let malformed = DepositedWidthSample(pathIndex: sample.pathIndex, segmentIndex: sample.segmentIndex,
      pathFraction: .nan, directionRadians: sample.directionRadians, firstEdge: sample.firstEdge,
      secondEdge: sample.secondEdge, widthMM: sample.widthMM, uncertaintyMM: sample.uncertaintyMM)
    let changed = DrawingMaterialMeasurement(id: measurement.id, algorithmRevision: measurement.algorithmRevision,
      frames: measurement.frames, registration: measurement.registration, geometry: measurement.geometry,
      qualification: measurement.qualification, distribution: measurement.distribution, samples: [malformed],
      limitations: [], alignment: measurement.alignment, source: measurement.source)
    #expect(throws: (any Error).self) {
      try DrawingMaterialRecord(profile: record.profile, applicability: record.applicability, measurement: changed)
    }
    let invalidDate = try DrawingMaterialProfileRevision(name: "Invalid date", nominalWidthMM: 1,
      createdAt: Date(timeIntervalSince1970: .infinity))
    #expect(throws: (any Error).self) { try DrawingMaterialRecord(profile: invalidDate) }
  }

  @Test("Full path may leave centre hull while each retained sample stays within calibrated domain")
  func fullGeometryAndSampleDomain() throws {
    let record = try fixture()
    let extending = try Polyline<MachineSpace>(points: [Point2(x: -1, y: 16), Point2(x: 37, y: 16)])
    // Keep the same sample centre while retaining an actual path that leaves the hull.
    let extendedData = try replacing(record, path: ["measurement", "geometry"], value: json([extending]))
    _ = try JSONDecoder().decode(DrawingMaterialRecord.self, from: extendedData)
    let outside = try replacing(record, path: ["measurement", "samples", "0", "firstEdge", "y"], value: 19)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(DrawingMaterialRecord.self, from: outside) }
  }

  private func fixture(mode: DrawingMaterialObservationMode = .pairedNewInk, unavailable: Bool = false,
    visibility: Bool = false) throws -> DrawingMaterialRecord {
    let authority = try TipAuthorityFixture()
    let registration = try authority.registration()
    let frame1 = try StampedFrame(sequence: 1, captureNanoseconds: 1,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes([UInt8](repeating: 240, count: 640 * 480)))
    let frame2 = try StampedFrame(sequence: 2, captureNanoseconds: 2,
      cameraConfigurationID: authority.cameraConfigurationID, width: 640, height: 480,
      rowBytes: 640, pixelFormat: .gray8, bytes: OwnedFrameBytes([UInt8](repeating: 200, count: 640 * 480)))
    let before = ExactFrameProvenance(frame: frame1), after = ExactFrameProvenance(frame: frame2)
    let pair = try DrawingObservationFramePair(source: authority.source, baseline: before, post: after)
    let geometry = try Polyline<MachineSpace>(points: [Point2(x: 6, y: 16), Point2(x: 30, y: 16)])
    let first = try registration.cameraFromMachine.applying(to: Point2<MachineSpace>(x: 18, y: 15.5))
    let second = try registration.cameraFromMachine.applying(to: Point2<MachineSpace>(x: 18, y: 16.5))
    let sample = DepositedWidthSample(pathIndex: 0, segmentIndex: 0, pathFraction: 0.5,
      directionRadians: 0, firstEdge: first, secondEdge: second, widthMM: 1, uncertaintyMM: 0.1)
    let distribution = try DepositedWidthDistribution(medianMM: 1, lowerBoundMM: 1, upperBoundMM: 1,
      uncertaintyMM: 0.1, sampleCount: 1,
      directional: [DirectionalWidthEstimate(directionRadians: 0, medianMM: 1, uncertaintyMM: 0.1, sampleCount: 1)])
    let alignment = IntegerFrameAlignment(shiftX: 0, shiftY: 0, backgroundMeanAbsoluteDifference: 0,
      estimatorRevision: "fixture-alignment", supportRegion: PixelRect(x: 0, y: 0, width: 640, height: 480),
      exclusionRegion: PixelRect(x: 10, y: 10, width: 100, height: 100), evaluatedPixelCount: 100)
    let measurement = DrawingMaterialMeasurement(algorithmRevision: "two-edge-material-v1",
      frames: mode == .pairedNewInk ? pair : nil, registration: registration, geometry: [geometry],
      qualification: unavailable ? .unavailable : .bounded, distribution: unavailable ? nil : distribution,
      samples: unavailable ? [] : [sample], limitations: ["Synthetic contract fixture"],
      recordedAt: Date(timeIntervalSince1970: 2), alignment: mode == .pairedNewInk ? alignment : nil,
      source: authority.source, singleFrame: mode == .existingInkLocalContrast ? after : nil, observationMode: mode,
      visibilityEvidence: visibility ? DrawingMaterialVisibilityEvidence(
        inspectedFrames: mode == .pairedNewInk ? [before, after] : [after], source: authority.source,
        confirmedAt: Date(timeIntervalSince1970: 1)) : nil)
    let profile = try DrawingMaterialProfileRevision(name: "Synthetic", nominalWidthMM: 1,
      qualification: measurement.qualification, depositedWidth: measurement.distribution,
      measurementEvidenceID: measurement.id, createdAt: Date(timeIntervalSince1970: 2))
    let applicability = try DrawingMaterialApplicability(registration: registration, paperStock: "Fixture paper",
      drawingFeedMMPerMinute: 300, penActuationProfile: .initialDefaults)
    return try DrawingMaterialRecord(profile: profile, applicability: applicability, measurement: measurement)
  }

  private func json<T: Encodable>(_ value: T) throws -> Any {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(value), options: [.fragmentsAllowed])
  }

  private func replacing<T: Encodable>(_ value: T, path: [String], value replacement: Any) throws -> Data {
    func replacing(_ node: Any, _ path: ArraySlice<String>) throws -> Any {
      guard let key = path.first else { return replacement }
      if var array = node as? [Any], let index = Int(key) {
        array[index] = try replacing(array[index], path.dropFirst()); return array
      }
      var object = try #require(node as? [String: Any])
      object[key] = try replacing(try #require(object[key]), path.dropFirst()); return object
    }
    return try JSONSerialization.data(withJSONObject: replacing(json(value), path[...]), options: [.sortedKeys])
  }
}
