import Foundation
import PortraitCore
import Testing
@testable import PortraitLibrary

@Suite("Portrait review dataset grouping and feasibility caps", .serialized)
struct PortraitReviewDatasetTests {
  @Test("Connected people, sessions, sources and ancestry cannot cross assigned splits")
  func connectedSplits() throws {
    let hashA = String(repeating: "a", count: 64), hashB = String(repeating: "b", count: 64)
    func entry(source: String, subject: String?, session: String?, ancestry: [String] = [],
      split: PortraitReviewDatasetSplit) -> PortraitReviewDatasetGroup {
      .init(requestID: UUID(), captureID: UUID(), acquisitionID: UUID(), sourceSHA256: source,
        groups: .init(subjectID: subject, photoSessionID: session,
          declaration: subject == nil && session == nil ? nil : "human declaration", ancestryIDs: ancestry), split: split)
    }
    let first = entry(source: hashA, subject: "p1", session: "s1", split: .train)
    for linked in [
      entry(source: hashB, subject: "p1", session: "s2", split: .test),
      entry(source: hashB, subject: "p2", session: "s1", split: .validation),
      entry(source: hashA, subject: "p2", session: "s2", split: .test)
    ] {
      #expect(throws: (any Error).self) { try PortraitReviewSplitValidation.validate([first, linked]) }
    }
    let chainA = entry(source: hashA, subject: "p1", session: "s1", ancestry: ["ancestor-1"], split: .train)
    let bridge = entry(source: hashB, subject: "p2", session: "s2", ancestry: ["ancestor-1", "ancestor-2"], split: .unassigned)
    let chainB = entry(source: String(repeating: "c", count: 64), subject: "p3", session: "s3",
      ancestry: ["ancestor-2"], split: .test)
    #expect(throws: (any Error).self) { try PortraitReviewSplitValidation.validate([chainA, bridge, chainB]) }
    try PortraitReviewSplitValidation.validate([first,
      entry(source: hashB, subject: "p2", session: "s2", split: .test)])
    #expect(throws: (any Error).self) {
      try PortraitReviewSplitValidation.validate([entry(source: hashA, subject: nil, session: nil, split: .train)])
    }
    #expect(throws: (any Error).self) {
      try PortraitReviewSplitValidation.validate([entry(source: hashA, subject: "p1", session: nil, split: .train)])
    }
  }

  @Test("Equal pixels retain separate capture occurrences and unknown human groups stay unassigned")
  func captureIdentityIsSeparate() throws {
    let source = String(repeating: "a", count: 64), acquisition = UUID()
    let a = PortraitReviewDatasetGroup(requestID: UUID(), captureID: UUID(), acquisitionID: acquisition,
      sourceSHA256: source, groups: .init(), split: .unassigned)
    let b = PortraitReviewDatasetGroup(requestID: UUID(), captureID: UUID(), acquisitionID: acquisition,
      sourceSHA256: source, groups: .init(), split: .unassigned)
    try PortraitReviewSplitValidation.validate([a, b])
    #expect(a.captureID != b.captureID && a.sourceSHA256 == b.sourceSHA256)
    #expect(!a.groups.sufficientForGroupedSplit)
    let encoded = try DrawingPackageCodec.encoder().encode([a, b])
    #expect(try JSONDecoder().decode([PortraitReviewDatasetGroup].self, from: encoded).map(\.captureID) == [a.captureID, b.captureID])
  }

  @Test("Pilot is frozen before jobs and failures or retries consume the same18-attempt budget")
  func pilotCapAndFreeze() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = PortraitCandidateStore(directoryURL: directory), package = try transferTestPackage()
    let id = UUID(), createdAt = Date(timeIntervalSinceReferenceDate: 100)
    let material = PortraitReviewMaterial(widthMM: package.program.fieldExtent.width,
      heightMM: package.program.fieldExtent.height, nominalLineWidthMM: package.program.strokes[0].style.nominalLineWidth)
    let planned = Data("{}".utf8)
    let arms = (0..<3).map { PortraitReviewPilotArm(id: "arm-\($0)",
      artist: .init(identifier: "artist-\($0)", revision: "1", settingsJSON: planned),
      environmentJSON: planned, conversionJSON: planned, seed: 42, material: material) }
    let pilot = try PortraitReviewPilotManifest(id: id, createdAt: createdAt,
      sources: [.init(captureID: package.origin.captureID, acquisitionID: nil, sourceSHA256: package.source.sha256, groups: .init())], arms: arms)
    func request() throws -> PortraitReviewGenerationRequest {
      try .init(captureID: package.origin.captureID, acquisitionID: nil,
        createdAt: Date(timeIntervalSinceReferenceDate: 101), source: package.source,
        artist: arms[0].artist, environmentJSON: planned, conversionJSON: planned, seed: 42, material: material, pilotID: id)
    }
    await #expect(throws: (any Error).self) { try await store.beginReviewGeneration(request()) }
    try await store.freezeReviewPilot(pilot)
    try await store.freezeReviewPilot(pilot)
    for _ in 0..<18 {
      let item = try request()
      try await store.beginReviewGeneration(item)
      try await store.beginReviewGeneration(item) // Exact retry is a read, not another attempt.
      _ = try await store.finishReviewGeneration(id: item.id, status: .failed, reason: "fixture preconversion failure",
        now: Date(timeIntervalSinceReferenceDate: 102))
    }
    await #expect(throws: (any Error).self) { try await store.beginReviewGeneration(request()) }
    #expect(try await store.reviewGenerationPage(limit: 32).count == 18)
    let replaced = try PortraitReviewPilotManifest(id: id, createdAt: createdAt,
      sources: pilot.sources, arms: [arms[0], arms[1], .init(id: "new-arm", artist: arms[2].artist,
        environmentJSON: planned, conversionJSON: planned, seed: 43, material: material)])
    await #expect(throws: (any Error).self) { try await store.freezeReviewPilot(replaced) }
  }

  @Test("Undecodable source bytes cannot enter the generation journal despite matching declared hash")
  func actualImageValidation() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let request = try PortraitReviewGenerationRequest(captureID: UUID(), acquisitionID: nil,
      source: .init(mediaType: "image/png", bytes: Data("not a PNG".utf8), pixelWidth: 1, pixelHeight: 1),
      artist: .init(identifier: "fixture", revision: "1", settingsJSON: Data("{}".utf8)),
      environmentJSON: Data("{}".utf8), conversionJSON: Data("{}".utf8), seed: nil,
      material: .init(widthMM: 100, heightMM: 100, nominalLineWidthMM: 0.5))
    let store = PortraitCandidateStore(directoryURL: directory)
    await #expect(throws: (any Error).self) { try await store.beginReviewGeneration(request) }
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("review-v1").path))
  }
}
