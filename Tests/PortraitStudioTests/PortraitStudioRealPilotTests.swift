import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import Testing
@testable import PortraitStudio

@Suite("Opt-in retained real SwiftSketch pilot", .serialized)
struct PortraitStudioRealPilotTests {
  @Test("Actual frozen outputs enter canonical drawings, unlabeled review and exact export",
    .enabled(if: ProcessInfo.processInfo.environment["PORTRAIT_REAL_PILOT_ROOT"] != nil))
  func ingestRetainedRealOutputs() async throws {
    let path = try #require(ProcessInfo.processInfo.environment["PORTRAIT_REAL_PILOT_ROOT"])
    let root = URL(fileURLWithPath: path, isDirectory: true)
    let pilotRoot = root.appendingPathComponent("pilot-v1", isDirectory: true)
    let manifestBytes = try read(pilotRoot.appendingPathComponent("pilot-manifest.json"))
    let manifest = try #require(try JSONSerialization.jsonObject(with: manifestBytes) as? [String: Any])
    let photos = try #require(manifest["photos"] as? [[String: Any]])
    #expect(photos.count == 6)
    #expect(manifest["maximum_attempts_including_failures"] as? Int == 18)
    let manifestHash = DrawingPackageCodec.sha256(manifestBytes)
    let clockURL = root.appendingPathComponent("pilot-ingestion.json")
    let ingestion: Ingestion
    if FileManager.default.fileExists(atPath: clockURL.path) {
      ingestion = try JSONDecoder().decode(Ingestion.self, from: read(clockURL))
      #expect(ingestion.originalManifestSHA256 == manifestHash)
    } else {
      ingestion = Ingestion(id: UUID(), importedAt: Date(), originalManifestSHA256: manifestHash,
        meaning: "Retrospective typed ingestion of pre-frozen Python outputs; original absolute request clock unknown; conversion material declared at ingestion; no human groups or labels.")
      try DrawingPackageCodec.encoder().encode(ingestion).write(to: clockURL, options: .atomic)
    }
    let libraryURL = root.appendingPathComponent("PilotLibrary", isDirectory: true)
    let store = PortraitCandidateStore(directoryURL: libraryURL)
    let producer = try await store.reviewLibraryIdentity()
    let conversion = try SwiftSketchConverter.settingsJSON(fieldWidthMM: 100, fieldHeightMM: 100, nominalPenWidthMM: 0.4)
    let sides = Array(repeating: 100.0, count: photos.count)
    let materials = sides.map { side in PortraitReviewMaterial(widthMM: side, heightMM: side, nominalLineWidthMM: 0.4,
      provenance: "prospective common square field declared at retrospective ingestion; physical pen unmeasured") }
    let conversions = Array(repeating: conversion, count: photos.count)
    let environment = try JSONSerialization.data(withJSONObject: [
      "ingestion": "retrospective; no worker invoked", "original_manifest_sha256": manifestHash,
      "original_absolute_request_clock": "unknown", "human_subject_session_groups": "unknown-unassigned",
      "preparation_policy": manifest["fixed_input_policy"] ?? "unknown"
    ], options: [.sortedKeys])
    let material = PortraitReviewMaterial(widthMM: 100, heightMM: 100, nominalLineWidthMM: 0.4,
      provenance: "prospective nominal conversion declared at typed ingestion; physical pen unmeasured")
    let variants = ["unchanged", "gamma08", "contrast115"]
    let artists = try variants.map { variant in
      DrawingPackageArtist(identifier: "swiftsketch.cpu", revision: "pinned-worker-v1",
        settingsJSON: try JSONSerialization.data(withJSONObject: [
          "seed": 42, "preprocessing": variant, "fixed_input_policy": manifest["fixed_input_policy"] ?? "unknown",
          "original_manifest_sha256": manifestHash, "conversion_policy": "common100mm square from the same exact retained padded source input, nominal pen0.4mm"
        ], options: [.sortedKeys]))
    }
    let pilotSources = try photos.enumerated().map { index, photo in
      PortraitReviewPilotSource(captureID: try uuid(photo["capture_id"]),
        acquisitionID: (photo["acquisition_id"] as? String).flatMap(UUID.init(uuidString:)),
        sourceSHA256: try #require(photo["source_sha256"] as? String), groups: .init(),
        material: materials[index], conversionJSON: conversions[index])
    }
    let pilot = try PortraitReviewPilotManifest(id: ingestion.id, createdAt: ingestion.importedAt,
      sources: pilotSources, arms: zip(variants, artists).map { variant, artist in
        .init(id: variant, artist: artist, environmentJSON: environment, conversionJSON: conversion, seed: 42, material: material)
      })
    try await store.freezeReviewPilot(pilot)
    var drawings: [String: SavedDrawing] = [:]
    var requestIDs: [UUID] = []
    var failures: [String] = []
    for (index, photo) in photos.enumerated() {
      let folder = pilotRoot.appendingPathComponent(String(format: "photo-%02d", index), isDirectory: true)
      let sourceBytes = try read(folder.appendingPathComponent("original.asset"))
      guard DrawingPackageCodec.sha256(sourceBytes) == photo["source_sha256"] as? String else {
        throw DrawingTransferError.invalid("Frozen pilot original bytes changed before ingestion.")
      }
      let source = try PortraitStudioArtistInput.imageAsset(sourceBytes)
      let fixed = try PortraitStudioArtistInput.imageAsset(read(folder.appendingPathComponent("fixed-input.png")))
      let receipt = try read(folder.appendingPathComponent("source-receipt.json"))
      for (armIndex, variant) in variants.enumerated() {
        let originalRequest = try read(folder.appendingPathComponent(variant + "-request.json"))
        let requestObject = try #require(try JSONSerialization.jsonObject(with: originalRequest) as? [String: Any])
        let attempts = try #require(photo["attempts"] as? [[String: Any]])
        let frozenAttempt = try #require(attempts.first(where: { $0["variant"] as? String == variant }))
        guard DrawingPackageCodec.sha256(originalRequest) == frozenAttempt["request_sha256"] as? String,
          fixed.sha256 == requestObject["input_sha256"] as? String,
          DrawingPackageCodec.sha256(receipt) == requestObject["source_receipt_sha256"] as? String,
          requestObject["preprocessing"] as? String == variant,
          requestObject["seed"] as? Int == 42 else {
          throw DrawingTransferError.invalid("Frozen pilot request, source receipt or prepared input changed.")
        }
        let id = try uuid(requestObject["request_id"])
        requestIDs.append(id)
        let scheduled = try PortraitReviewGenerationRequest(id: id, captureID: pilotSources[index].captureID,
          acquisitionID: pilotSources[index].acquisitionID, createdAt: ingestion.importedAt, source: source,
          inputs: [.init(role: "prepared-source", asset: fixed),
            .init(role: "original-source-receipt", asset: .init(mediaType: "application/json", bytes: receipt)),
            .init(role: "external-frozen-request", asset: .init(mediaType: "application/json", bytes: originalRequest)),
            .init(role: "external-frozen-manifest", asset: .init(mediaType: "application/json", bytes: manifestBytes))],
          groups: .init(), artist: artists[armIndex], environmentJSON: environment, conversionJSON: conversions[index],
          seed: 42, material: materials[index], pilotID: pilot.id, recordingMode: .retrospectiveExternalImport)
        try await store.beginReviewGeneration(scheduled)
        let output = folder.appendingPathComponent(variant + "-attempt", isDirectory: true)
        let responseBytes = try read(output.appendingPathComponent("response.json"))
        let response = try #require(try JSONSerialization.jsonObject(with: responseBytes) as? [String: Any])
        #expect(try uuid(response["request_id"]) == id)
        let status = try #require((response["status"] as? String).flatMap(SwiftSketchWorkerStatus.init(rawValue:)))
        func asset(_ name: String) throws -> Data? {
          let file = output.appendingPathComponent(name)
          guard FileManager.default.fileExists(atPath: file.path) else { return nil }
          let bytes = try read(file)
          if let expected = (response["files"] as? [String: String])?[name] {
            #expect(DrawingPackageCodec.sha256(bytes) == expected)
          }
          return bytes
        }
        let result = try SwiftSketchWorkerResult(requestID: id, status: status, reason: response["reason"] as? String,
          rawOutputJSON: asset("raw-curves.json"), artistInputPNG: asset("artist-input.png"),
          previewPNG: asset("preview.png"), provenanceJSON: asset("provenance.json"),
          responseJSON: responseBytes, attemptDirectory: output)
        let retained = PortraitStudioArtistPackageFactory.assets(result)
        do {
          guard result.status == .succeeded else { throw SwiftSketchError.invalid(result.reason ?? result.status.rawValue) }
          let package = try PortraitStudioArtistPackageFactory.package(request: scheduled,
            producerLibraryID: producer, result: result)
          let encoded = try DrawingPackageCodec.encode(package)
          let saved = try await store.importDrawingPackage(encoded, restoreDeleted: false)
          #expect(try await store.exportDrawingPackage(saved) == encoded)
          _ = try await store.finishReviewGeneration(id: id, status: .succeeded, drawing: saved,
            outputs: retained, runtimeEnvironmentJSON: result.provenanceJSON, runtimeMetricsJSON: result.responseJSON)
          drawings["\(index):\(variant)"] = saved
        } catch {
          failures.append("\(index):\(variant): \(error.localizedDescription)")
          _ = try await store.finishReviewGeneration(id: id, status: result.status == .cancelled ? .cancelled : .failed,
            reason: error.localizedDescription, outputs: retained,
            runtimeEnvironmentJSON: result.provenanceJSON, runtimeMetricsJSON: result.responseJSON)
        }
      }
    }
    #expect(requestIDs.count == 18 && Set(requestIDs).count == 18)
    #expect(!drawings.isEmpty)
    var nativeDrawings: [String: SavedDrawing] = [:]
    let nativeStyles: [PortraitStyle] = [.flowEdges, .contours, .sketch]
    for (index, photo) in photos.enumerated() {
      let folder = pilotRoot.appendingPathComponent(String(format: "photo-%02d", index), isDirectory: true)
      let source = try PortraitStudioArtistInput.imageAsset(read(folder.appendingPathComponent("original.asset")))
      let fixed = try PortraitStudioArtistInput.imageAsset(read(folder.appendingPathComponent("fixed-input.png")))
      let analysis = PortraitAnalysisOptions(cropToFace: false, removeBackground: false)
      for style in nativeStyles {
        let vectors = PortraitVectorOptions.nativeDefaults(for: style)
        let options = FrozenNativeOptions(style: style, analysis: analysis, vectors: vectors,
          inputPolicy: "same exact retained padded square input as SwiftSketch, no crop/background removal/head transform; fixed native defaults; 100mm square field; no tuning; controlled framing differs from normal Studio")
        let settings = try DrawingPackageCodec.encoder().encode(options)
        let artist = DrawingPackageArtist(identifier: "adaptiveplotter.baseline." + style.rawValue,
          revision: "fixed-native-defaults-pilot-v1", settingsJSON: settings)
        let id = Self.stableUUID(source.sha256 + style.rawValue + manifestHash)
        let scheduled = try PortraitReviewGenerationRequest(id: id, captureID: pilotSources[index].captureID,
          acquisitionID: pilotSources[index].acquisitionID, createdAt: ingestion.importedAt, source: source,
          inputs: [.init(role: "artist-input", asset: fixed)], groups: .init(), artist: artist,
          environmentJSON: environment, conversionJSON: Data("{\"nativeField\":\"100mm-square fixed input, no program transform\"}".utf8),
          seed: nil, material: material)
        try await store.beginReviewGeneration(scheduled)
        do {
          let result = try await PortraitImageAnalyzer().render(.init(data: fixed.bytes, pose: .front,
            style: style, options: analysis,
            strokeStyle: StrokeStyle(nominalLineWidth: 0.4,
              penProfileID: PenProfileID(UUID(uuidString: "DB7E0C34-89CB-4DC0-BF23-3ADEA6745E10")!)),
            vectorOptions: vectors,
            sourcePixelExtent: .init(widthPixels: Double(try #require(fixed.pixelWidth)),
              heightPixels: Double(try #require(fixed.pixelHeight)))))
          #expect(result.program.fieldExtent.width == 100 && result.program.fieldExtent.height == 100)
          let record = try DrawingPackageCodec.encoder().encode(NativeResult(raster: result.raster,
            program: result.program, options: options))
          let preview = try PortraitStudioArtistInput.imageAsset(PortraitAttemptThumbnail.render(result.program))
          let package = try DrawingPackage(origin: .init(libraryID: producer, captureID: pilotSources[index].captureID,
            resultID: "native-baseline-" + id.uuidString.lowercased(), resultRecordSHA256: DrawingPackageCodec.sha256(record),
            programHash: result.program.contentHash), program: result.program, createdAt: ingestion.importedAt,
            title: "Baseline · " + style.rawValue, resultRecordJSON: record, source: source,
            artistInput: fixed, artist: artist, preview: preview)
          let saved = try await store.importDrawingPackage(DrawingPackageCodec.encode(package), restoreDeleted: false)
          _ = try await store.finishReviewGeneration(id: id, status: .succeeded, drawing: saved,
            outputs: [.init(role: "native-raster", asset: .init(mediaType: "application/json",
              bytes: DrawingPackageCodec.encoder().encode(result.raster)))])
          nativeDrawings["\(index):\(style.rawValue)"] = saved
        } catch {
          failures.append("native-\(index):\(style.rawValue): \(error.localizedDescription)")
          _ = try await store.finishReviewGeneration(id: id, status: .failed, reason: error.localizedDescription)
        }
      }
    }
    var comparisons: [PortraitReviewComparison] = []
    for index in photos.indices {
      guard let first = drawings["\(index):unchanged"] else { continue }
      for variant in ["gamma08", "contrast115"] {
        if let second = drawings["\(index):\(variant)"] {
          let comparison = try await store.createReviewComparison(first: first, second: second,
            presentationSeed: UInt64(index) + 42, rubricVersion: "portrait-review-v1")
          #expect(try await store.reviewLabelHead(comparisonID: comparison.id) == nil)
          comparisons.append(comparison)
        }
      }
    }
    let preprocessingComparisons = comparisons.count
    for index in photos.indices {
      guard let swift = drawings["\(index):unchanged"] else { continue }
      for style in nativeStyles {
        if let native = nativeDrawings["\(index):\(style.rawValue)"] {
          let comparison = try await store.createReviewComparison(first: native, second: swift,
            presentationSeed: UInt64(index) + 84, rubricVersion: "portrait-review-v1")
          #expect(try await store.reviewLabelHead(comparisonID: comparison.id) == nil)
          comparisons.append(comparison)
        }
      }
    }
    #expect(!comparisons.isEmpty)
    let reopened = PortraitCandidateStore(directoryURL: libraryURL)
    for drawing in Array(drawings.values) + Array(nativeDrawings.values) {
      let retained = try await reopened.loadDrawing(drawing.id)
      #expect(retained == drawing)
      let bytes = try await reopened.exportDrawingPackage(retained)
      #expect(try DrawingPackageCodec.decode(bytes).program == drawing.program)
    }
    let exportURL = root.appendingPathComponent("PilotDataset", isDirectory: true)
    let exported = try await store.exportReviewDataset(to: exportURL)
    #expect(exported.counts.requests == 36)
    #expect(exported.counts.labelRevisions == 0)
    #expect(exported.counts.declaredSubjects == 0 && exported.counts.declaredPhotoSessions == 0)
    let report = Report(originalManifestSHA256: manifestHash, retrospectiveTypedIngestion: true,
      swiftSketchFieldSidesMM: sides, commonFieldHeightMM: 100, declaredNominalPenMM: 0.4,
      scheduledSwiftSketch: requestIDs.count, validSwiftSketchPackages: drawings.count,
      nativeBaselinePackages: nativeDrawings.count, conversionOrWorkerFailures: failures,
      preprocessingComparisons: preprocessingComparisons, artistComparisons: comparisons.count - preprocessingComparisons,
      humanLabels: 0, dataset: exported)
    try DrawingPackageCodec.encoder().encode(report).write(to: root.appendingPathComponent("pilot-integration-report.json"), options: .atomic)
  }

  private func read(_ url: URL) throws -> Data { try PortraitStudioFiles.read(url, maximumBytes: 32 * 1024 * 1024) }
  private func uuid(_ value: Any?) throws -> UUID { try #require((value as? String).flatMap(UUID.init(uuidString:))) }
  private static func stableUUID(_ text: String) -> UUID {
    let hash = DrawingPackageCodec.sha256(Data(text.utf8))
    let id = Array(hash.prefix(32))
    return UUID(uuidString: String(id[0..<8]) + "-" + String(id[8..<12]) + "-" + String(id[12..<16])
      + "-" + String(id[16..<20]) + "-" + String(id[20..<32]))!
  }
  private struct FrozenNativeOptions: Codable {
    let style: PortraitStyle
    let analysis: PortraitAnalysisOptions
    let vectors: PortraitVectorOptions
    let inputPolicy: String
  }
  private struct NativeResult: Codable {
    let raster: PortraitRaster
    let program: DrawingProgram
    let options: FrozenNativeOptions
  }
  private struct Ingestion: Codable {
    let id: UUID
    let importedAt: Date
    let originalManifestSHA256: String
    let meaning: String
  }
  private struct Report: Codable {
    let originalManifestSHA256: String
    let retrospectiveTypedIngestion: Bool
    let swiftSketchFieldSidesMM: [Double]
    let commonFieldHeightMM: Double
    let declaredNominalPenMM: Double
    let scheduledSwiftSketch: Int
    let validSwiftSketchPackages: Int
    let nativeBaselinePackages: Int
    let conversionOrWorkerFailures: [String]
    let preprocessingComparisons: Int
    let artistComparisons: Int
    let humanLabels: Int
    let dataset: PortraitReviewDatasetManifest
  }
}
