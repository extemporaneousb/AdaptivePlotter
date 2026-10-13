import Foundation
import PlotterModel
import PortraitArtists
import PortraitCore
import PortraitLibrary
import Testing
@testable import PortraitStudio

/// A real local experiment harness, opt-in independently of ordinary test runs.
/// Preparation/freeze never launch the worker. Ingestion only reads frozen outputs.
@Suite("Opt-in shared native face-preparation pilot", .serialized)
struct PortraitStudioFacePilotTests {
  @Test("Prepare all preselected originals through the actual native input owner",
    .enabled(if: Self.phase == "prepare"))
  func prepareFrozenSources() throws {
    let root = try Self.root()
    let selectionBytes = try read(root.appendingPathComponent("source-selection.json"))
    let selection = try object(selectionBytes)
    let photos = try #require(selection["photos"] as? [[String: Any]])
    #expect(photos.count == 10)
    let parametersBytes = try read(root.appendingPathComponent("preparation-parameters.json"))
    let parameters = try object(parametersBytes)
    let overrides = parameters["face_overrides"] as? [String: [String: Any]] ?? [:]
    let pass = try Self.preparationPass()
    let reportURL = root.appendingPathComponent(pass + "-report.json")
    guard !FileManager.default.fileExists(atPath: reportURL.path) else {
      throw DrawingTransferError.conflict("Preparation pass already exists; retain it and choose a new explicit pass.")
    }
    var preparedPhotos: [[String: Any]] = []
    for (index, photo) in photos.enumerated() {
      let sourceFolder = String(format: "photo-%02d", index)
      let original = try read(root.appendingPathComponent(sourceFolder + "/original.asset"))
      guard DrawingPackageCodec.sha256(original) == photo["source_sha256"] as? String else {
        throw DrawingTransferError.invalid("Frozen original source changed before preparation.")
      }
      let folder = sourceFolder + "/" + pass
      let destination = root.appendingPathComponent(folder, isDirectory: true)
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
      var retained = photo
      retained["folder"] = folder; retained["source_folder"] = sourceFolder
      do {
        let override: PortraitStudioArtistInput.FaceOverride?
        if let declared = overrides[String(index)] {
          override = .init(x: try number(declared["x"]), y: try number(declared["y"]),
            width: try number(declared["width"]), height: try number(declared["height"]),
            declaration: try string(declared["declaration"]))
        } else { override = nil }
        let input = try PortraitStudioArtistInput.prepare(original, faceOverride: override)
        let preparation = try object(input.preparationJSON)
        guard preparation["revision"] as? String == parameters["preparation_revision"] as? String,
          preparation["target_face_height_fraction"] as? Double == parameters["target_face_height_fraction"] as? Double,
          preparation["target_face_center_x_fraction"] as? Double == parameters["target_face_center_x_fraction"] as? Double,
          preparation["target_face_center_y_fraction"] as? Double == parameters["target_face_center_y_top_down_fraction"] as? Double else {
          throw DrawingTransferError.invalid("Native preparation settings differ from the declared pre-output parameters.")
        }
        guard input.source.bytes == original, input.squarePNG.pixelWidth == 1024,
          input.squarePNG.pixelHeight == 1024 else {
          throw DrawingTransferError.invalid("Native preparation changed original bytes or fixed canvas extent.")
        }
        let files: [(String, Data)] = [("fixed-input.png", input.squarePNG.bytes),
          ("preparation.json", input.preparationJSON), ("foreground-mask.png", input.foregroundMaskPNG.bytes),
          ("framed-source.png", input.framedSourcePNG.bytes)]
        for (name, bytes) in files { try bytes.write(to: destination.appendingPathComponent(name), options: .withoutOverwriting) }
        retained["preparation_status"] = "succeeded"
        retained["input_sha256"] = input.squarePNG.sha256
        retained["preparation_sha256"] = DrawingPackageCodec.sha256(input.preparationJSON)
        retained["foreground_mask_sha256"] = input.foregroundMaskPNG.sha256
        retained["framed_source_sha256"] = input.framedSourcePNG.sha256
        retained["preparation"] = try object(input.preparationJSON)
      } catch {
        retained["preparation_status"] = "unsupported"
        retained["preparation_error"] = error.localizedDescription
        try json(["status": "unsupported", "reason": error.localizedDescription,
          "source_sha256": try string(photo["source_sha256"])]).write(
            to: destination.appendingPathComponent("preparation-failure.json"), options: .withoutOverwriting)
      }
      preparedPhotos.append(retained)
    }
    let report: [String: Any] = ["schema_version": 1, "pilot_revision": "portrait-native-face-mask-v1",
      "source_selection_sha256": DrawingPackageCodec.sha256(selectionBytes),
      "preparation_parameters_sha256": DrawingPackageCodec.sha256(parametersBytes),
      "preparation_pass": pass, "photos": preparedPhotos,
      "prepared_count": preparedPhotos.filter { $0["preparation_status"] as? String == "succeeded" }.count,
      "model_jobs_launched": 0, "human_labels": 0]
    try json(report).write(to: reportURL, options: .withoutOverwriting)
  }

  @Test("Freeze exact accepted native inputs/settings before the bounded model batch",
    .enabled(if: Self.phase == "freeze"))
  func freezePreparedInputs() throws {
    let root = try Self.root(), pass = try Self.preparationPass()
    let manifestURL = root.appendingPathComponent("pilot-manifest.json")
    guard !FileManager.default.fileExists(atPath: manifestURL.path),
      !FileManager.default.fileExists(atPath: root.appendingPathComponent("pilot-run.json").path) else {
      throw DrawingTransferError.conflict("Pilot has already been frozen/attempted; preserve its exact identity.")
    }
    let selectionBytes = try read(root.appendingPathComponent("source-selection.json"))
    let selection = try object(selectionBytes)
    let parametersBytes = try read(root.appendingPathComponent("preparation-parameters.json"))
    let report = try object(read(root.appendingPathComponent(pass + "-report.json")))
    guard report["source_selection_sha256"] as? String == DrawingPackageCodec.sha256(selectionBytes),
      report["preparation_parameters_sha256"] as? String == DrawingPackageCodec.sha256(parametersBytes) else {
      throw DrawingTransferError.invalid("Preparation report does not bind the current frozen sources/parameters.")
    }
    var photos = try #require(report["photos"] as? [[String: Any]])
    let native = try Self.styles.map { style in
      try object(DrawingPackageCodec.encoder().encode(FrozenNativeOptions(style: style,
        analysis: .init(cropToFace: false, removeBackground: false), vectors: .nativeDefaults(for: style),
        inputPolicy: "same exact native face-framed foreground-removed 1024 square PNG as SwiftSketch; no secondary crop, background removal or head transform; fixed native defaults; 100mm square; nominal 0.4mm pen")))
    }
    for index in photos.indices {
      var photo = photos[index]
      let requestID = Self.stableUUID("native-face-mask-v1:" + (try string(photo["source_sha256"]))
        + ":" + DrawingPackageCodec.sha256(parametersBytes))
      let folder = try string(photo["folder"])
      var request: [String: Any] = ["schema_version": 1, "request_id": requestID.uuidString.lowercased(),
        "input_path": root.appendingPathComponent(folder + "/fixed-input.png").path,
        "preprocessing": "unchanged", "seed": 42, "mask_policy": "fixed-input-no-segmentation-v1",
        "native_preprocessing": "foreground removal already applied by native preparation; worker performs no segmentation",
        "source_sha256": try string(photo["source_sha256"])]
      if photo["preparation_status"] as? String == "succeeded" {
        for (name, key) in [("fixed-input.png", "input_sha256"), ("preparation.json", "preparation_sha256"),
                            ("foreground-mask.png", "foreground_mask_sha256"), ("framed-source.png", "framed_source_sha256")] {
          guard DrawingPackageCodec.sha256(try read(root.appendingPathComponent(folder + "/" + name))) == photo[key] as? String else {
            throw DrawingTransferError.invalid("Native prepared bytes changed before freezing.")
          }
        }
        request["input_sha256"] = try string(photo["input_sha256"])
        request["native_preparation_sha256"] = try string(photo["preparation_sha256"])
      } else {
        request["unsupported_preparation"] = try string(photo["preparation_error"])
        request["input_sha256"] = NSNull() // Descriptor retained, never submitted to the worker.
      }
      let bytes = try json(request)
      let requestRelative = folder + "/unchanged-request.json"
      try bytes.write(to: root.appendingPathComponent(requestRelative), options: .withoutOverwriting)
      photo["attempt"] = ["request_id": requestID.uuidString.lowercased(),
        "request_relative_path": requestRelative, "request_sha256": DrawingPackageCodec.sha256(bytes),
        "output_relative_path": folder + "/unchanged-attempt"]
      photos[index] = photo
    }
    var manifest = selection
    manifest["source_selection_sha256"] = DrawingPackageCodec.sha256(selectionBytes)
    manifest["preparation_parameters_sha256"] = DrawingPackageCodec.sha256(parametersBytes)
    manifest["preparation_report_sha256"] = DrawingPackageCodec.sha256(try read(root.appendingPathComponent(pass + "-report.json")))
    manifest["preparation_pass"] = pass; manifest["photos"] = photos; manifest["native_options"] = native
    manifest["fixed_input_policy"] = "studio-face-person-mask-srgb-square-v2"
    manifest["prepared_count"] = report["prepared_count"]
    manifest["frozen_at_unix"] = Date().timeIntervalSince1970
    manifest["comparison_seed_rule"] = "stable source/style/manifest-derived UUID and UInt64; recorded randomized A/B assignment, no inferred human preference"
    try json(manifest).write(to: manifestURL, options: .withoutOverwriting)
  }

  @Test("Ingest exact face-pilot outputs and create unlabeled common-scale comparisons",
    .enabled(if: Self.phase == "ingest"))
  func ingestFrozenOutputs() async throws {
    let root = try Self.root()
    let manifestBytes = try read(root.appendingPathComponent("pilot-manifest.json"))
    let manifestHash = DrawingPackageCodec.sha256(manifestBytes)
    let manifest = try object(manifestBytes)
    let photos = try #require(manifest["photos"] as? [[String: Any]])
    let runBytes = try read(root.appendingPathComponent("pilot-run.json"))
    let run = try object(runBytes)
    let modelManifestBytes = try read(root.appendingPathComponent("model-manifest-exact.json"))
    guard DrawingPackageCodec.sha256(modelManifestBytes) == run["model_manifest_sha256"] as? String else {
      throw DrawingTransferError.invalid("Exact external model manifest differs from its batch identity.")
    }
    guard run["manifest_sha256"] as? String == manifestHash, photos.count == 10,
      manifest["maximum_model_jobs_including_failures"] as? Int == 10,
      manifest["maximum_native_jobs_including_failures"] as? Int == 30 else {
      throw DrawingTransferError.invalid("Frozen face pilot identity or job caps changed before ingestion.")
    }
    let runAttempts = try #require(run["attempts"] as? [[String: Any]])
    #expect(runAttempts.count == 10)
    let libraryURL = root.appendingPathComponent("PilotLibrary", isDirectory: true)
    guard !FileManager.default.fileExists(atPath: libraryURL.path),
      !FileManager.default.fileExists(atPath: root.appendingPathComponent("PilotDataset").path) else {
      throw DrawingTransferError.conflict("Face pilot library/dataset already exists; retain it without rebootstrap.")
    }
    let store = PortraitCandidateStore(directoryURL: libraryURL)
    let producer = try await store.reviewLibraryIdentity()
    let material = PortraitReviewMaterial(widthMM: 100, heightMM: 100, nominalLineWidthMM: 0.4,
      provenance: "Frozen common nominal authoring field; physical pen unmeasured")
    let conversion = try SwiftSketchConverter.settingsJSON(fieldWidthMM: 100, fieldHeightMM: 100, nominalPenWidthMM: 0.4)
    let frozenAt = Date(timeIntervalSince1970: try number(manifest["frozen_at_unix"]))
    let environment = try json(["recording": "External model outputs ingested later; original frozen request clock retained; native jobs recorded before rendering",
      "external_manifest_sha256": manifestHash,
      "external_run_receipt_sha256": DrawingPackageCodec.sha256(runBytes),
      "external_model_manifest_sha256": DrawingPackageCodec.sha256(modelManifestBytes),
      "clock_boundary": "Frozen request and supervisor admission clocks retained; internal worker start clock not observed by batch runner",
      "source_groups": "unknown-unassigned",
      "fixed_input_policy": "studio-face-person-mask-srgb-square-v2",
      "native_os": ProcessInfo.processInfo.operatingSystemVersionString])
    let swiftArtist = DrawingPackageArtist(identifier: "swiftsketch.cpu", revision: "pinned-worker-v1",
      settingsJSON: try json(["seed": 42, "preprocessing": "unchanged",
        "native_preparation_revision": "studio-face-person-mask-srgb-square-v2",
        "external_manifest_sha256": manifestHash,
        "mask_policy": "fixed-input-no-segmentation-v1: worker receives already masked native PNG; worker does no segmentation",
        "physical_field": "100mm square, nominal 0.4mm pen"]))
    let nativeJSON = try #require(manifest["native_options"] as? [[String: Any]])
    let nativeOptions = try nativeJSON.map { try JSONDecoder().decode(FrozenNativeOptions.self, from: json($0)) }
    #expect(nativeOptions.map(\.style) == Self.styles)
    var swiftDrawings: [Int: SavedDrawing] = [:]
    var nativeDrawings: [String: SavedDrawing] = [:]
    var failures: [String] = [], budget: [[String: Any]] = []
    var scheduledIDs: [UUID] = []
    for (index, photo) in photos.enumerated() {
      let sourceFolder = try string(photo["source_folder"]), folder = try string(photo["folder"])
      let sourceBytes = try read(root.appendingPathComponent(sourceFolder + "/original.asset"))
      guard DrawingPackageCodec.sha256(sourceBytes) == photo["source_sha256"] as? String else {
        throw DrawingTransferError.invalid("Frozen original photo changed before ingestion.")
      }
      let source = try PortraitStudioArtistInput.imageAsset(sourceBytes)
      let receiptBytes = try read(root.appendingPathComponent(sourceFolder + "/source-receipt.json"))
      guard DrawingPackageCodec.sha256(receiptBytes) == photo["source_receipt_sha256"] as? String else {
        throw DrawingTransferError.invalid("Frozen source/capture receipt changed before ingestion.")
      }
      let prepared = photo["preparation_status"] as? String == "succeeded"
      var inputAssets: [PortraitReviewAsset] = [.init(role: "source-receipt", asset: .init(mediaType: "application/json", bytes: receiptBytes)),
        .init(role: "external-frozen-manifest", asset: .init(mediaType: "application/json", bytes: manifestBytes))]
      var fixed: DrawingPackageAsset?
      if prepared {
        for (name, role, hashKey, type) in [
          ("fixed-input.png", "prepared-source", "input_sha256", "image/png"),
          ("foreground-mask.png", "foreground-mask", "foreground_mask_sha256", "image/png"),
          ("framed-source.png", "framed-source", "framed_source_sha256", "image/png"),
          ("preparation.json", "source-preparation", "preparation_sha256", "application/json")] {
          let bytes = try read(root.appendingPathComponent(folder + "/" + name))
          guard DrawingPackageCodec.sha256(bytes) == photo[hashKey] as? String else {
            throw DrawingTransferError.invalid("Exact native preparation/input bytes changed before ingestion.")
          }
          let asset = type == "image/png" ? try PortraitStudioArtistInput.imageAsset(bytes)
            : DrawingPackageAsset(mediaType: type, bytes: bytes)
          inputAssets.append(.init(role: role, asset: asset))
          if role == "prepared-source" { fixed = asset }
        }
      } else {
        inputAssets.append(.init(role: "preparation-refusal", asset: .init(mediaType: "application/json",
          bytes: try read(root.appendingPathComponent(folder + "/preparation-failure.json")))))
      }
      let attempt = try #require(photo["attempt"] as? [String: Any])
      let requestBytes = try read(root.appendingPathComponent(try string(attempt["request_relative_path"])))
      let originalRequest = try object(requestBytes)
      guard DrawingPackageCodec.sha256(requestBytes) == attempt["request_sha256"] as? String,
        originalRequest["seed"] as? Int == 42,
        originalRequest["preprocessing"] as? String == "unchanged",
        !prepared || fixed?.sha256 == originalRequest["input_sha256"] as? String else {
        throw DrawingTransferError.invalid("Frozen model request/settings/input identity changed before ingestion.")
      }
      let requestID = try uuid(attempt["request_id"])
      scheduledIDs.append(requestID)
      let capture = try uuid(photo["capture_id"])
      let acquisition = (photo["acquisition_id"] as? String).flatMap(UUID.init(uuidString:))
      let scheduled = try PortraitReviewGenerationRequest(id: requestID, captureID: capture, acquisitionID: acquisition,
        createdAt: frozenAt, source: source,
        inputs: inputAssets + [.init(role: "external-frozen-request", asset: .init(mediaType: "application/json", bytes: requestBytes)),
          .init(role: "external-run-receipt", asset: .init(mediaType: "application/json", bytes: runBytes)),
          .init(role: "external-model-manifest", asset: .init(mediaType: "application/json", bytes: modelManifestBytes))],
        artist: swiftArtist, environmentJSON: environment, conversionJSON: conversion, seed: 42, material: material,
        recordingMode: .retrospectiveExternalImport)
      try await store.beginReviewGeneration(scheduled)
      let runAttempt = try #require(runAttempts.first { $0["request_id"] as? String == requestID.uuidString.lowercased() })
      let output = root.appendingPathComponent(try string(attempt["output_relative_path"]), isDirectory: true)
      let responseURL = output.appendingPathComponent("response.json")
      if !prepared || !FileManager.default.fileExists(atPath: responseURL.path) {
        let reason = (photo["preparation_error"] as? String) ?? (runAttempt["reason"] as? String)
          ?? "Scheduled worker produced no complete response; exact supervisor disposition retained."
        let status: PortraitReviewGenerationStatus = !prepared ? .unsupported
          : (runAttempt["status"] as? String == "skipped_wall_time_limit" ? .skipped : .failed)
        failures.append("swift-\(index): \(reason)")
        _ = try await store.finishReviewGeneration(id: requestID, status: status, reason: reason,
          outputs: [.init(role: "external-supervisor-outcome", asset: .init(mediaType: "application/json", bytes: json(runAttempt)))])
      } else {
        var retained: [PortraitReviewAsset] = []
        var terminalStatus: PortraitReviewGenerationStatus = .failed
        var runtimeEnvironment: Data?, runtimeMetrics: Data?
        do {
          let responseBytes = try read(responseURL), response = try object(responseBytes)
          guard try uuid(response["request_id"]) == requestID else {
            throw DrawingTransferError.invalid("Model response is for a different frozen request.")
          }
          let status = try #require((response["status"] as? String).flatMap(SwiftSketchWorkerStatus.init(rawValue:)))
          terminalStatus = status == .cancelled ? .cancelled : (status == .unavailable ? .unsupported : .failed)
          runtimeMetrics = responseBytes
          func asset(_ name: String) throws -> Data? {
            let url = output.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let bytes = try read(url)
            guard let expected = (response["files"] as? [String: String])?[name], DrawingPackageCodec.sha256(bytes) == expected else {
              throw DrawingTransferError.invalid("Retained worker asset differs from its exact response hash.")
            }
            return bytes
          }
          let result = try SwiftSketchWorkerResult(requestID: requestID, status: status, reason: response["reason"] as? String,
            rawOutputJSON: asset("raw-curves.json"), artistInputPNG: asset("artist-input.png"),
            previewPNG: asset("preview.png"), provenanceJSON: asset("provenance.json"), responseJSON: responseBytes, attemptDirectory: output)
          retained = PortraitStudioArtistPackageFactory.assets(result)
          runtimeEnvironment = result.provenanceJSON
          guard result.status == .succeeded else { throw SwiftSketchError.invalid(result.reason ?? result.status.rawValue) }
          let package = try PortraitStudioArtistPackageFactory.package(request: scheduled, producerLibraryID: producer, result: result)
          let encoded = try DrawingPackageCodec.encode(package)
          let drawing = try await store.importDrawingPackage(encoded, restoreDeleted: false)
          #expect(try await store.exportDrawingPackage(drawing) == encoded)
          _ = try await store.finishReviewGeneration(id: requestID, status: .succeeded, drawing: drawing,
            outputs: retained, runtimeEnvironmentJSON: result.provenanceJSON, runtimeMetricsJSON: result.responseJSON)
          swiftDrawings[index] = drawing
          budget.append(["source_index": index, "artist": "swiftsketch.cpu", "program_hash": package.program.contentHash.description,
            "artist_input_sha256": package.artistInput.sha256, "strokes": package.program.strokes.count,
            "points": package.program.strokes.reduce(0) { $0 + $1.path.points.count }])
        } catch {
          failures.append("swift-\(index): \(error.localizedDescription)")
          _ = try await store.finishReviewGeneration(id: requestID, status: terminalStatus,
            reason: error.localizedDescription, outputs: retained,
            runtimeEnvironmentJSON: runtimeEnvironment, runtimeMetricsJSON: runtimeMetrics)
        }
      }
      for options in nativeOptions {
        let settings = try DrawingPackageCodec.encoder().encode(options)
        let artist = DrawingPackageArtist(identifier: "adaptiveplotter.baseline." + options.style.rawValue,
          revision: "fixed-native-defaults-face-pilot-v1", settingsJSON: settings)
        let id = Self.stableUUID(source.sha256 + options.style.rawValue + manifestHash)
        scheduledIDs.append(id)
        let nativeScheduled = try PortraitReviewGenerationRequest(id: id, captureID: capture, acquisitionID: acquisition,
          source: source, inputs: inputAssets, artist: artist, environmentJSON: environment,
          conversionJSON: Data("{\"nativeField\":\"100mm-square same exact masked face input, no secondary transform\"}".utf8),
          seed: nil, material: material)
        try await store.beginReviewGeneration(nativeScheduled)
        guard let fixed else {
          let reason = try string(photo["preparation_error"])
          failures.append("native-\(index):\(options.style.rawValue): \(reason)")
          _ = try await store.finishReviewGeneration(id: id, status: .unsupported, reason: reason)
          continue
        }
        do {
          let result = try await PortraitImageAnalyzer().render(.init(data: fixed.bytes, pose: .front, style: options.style,
            options: options.analysis, strokeStyle: StrokeStyle(nominalLineWidth: 0.4,
              penProfileID: PenProfileID(UUID(uuidString: "DB7E0C34-89CB-4DC0-BF23-3ADEA6745E10")!)),
            vectorOptions: options.vectors, sourcePixelExtent: .init(widthPixels: 1024, heightPixels: 1024)))
          #expect(result.program.fieldExtent.width == 100 && result.program.fieldExtent.height == 100)
          let record = try DrawingPackageCodec.encoder().encode(NativeResult(raster: result.raster, program: result.program, options: options))
          let preview = try PortraitStudioArtistInput.imageAsset(PortraitAttemptThumbnail.render(result.program))
          let package = try DrawingPackage(origin: .init(libraryID: producer, captureID: capture,
            resultID: "native-face-baseline-" + id.uuidString.lowercased(), resultRecordSHA256: DrawingPackageCodec.sha256(record),
            programHash: result.program.contentHash), program: result.program, createdAt: nativeScheduled.createdAt,
            title: "Baseline · " + options.style.rawValue, resultRecordJSON: record, source: source, artistInput: fixed,
            artist: artist, preview: preview)
          let encoded = try DrawingPackageCodec.encode(package)
          let drawing = try await store.importDrawingPackage(encoded, restoreDeleted: false)
          #expect(try await store.exportDrawingPackage(drawing) == encoded)
          _ = try await store.finishReviewGeneration(id: id, status: .succeeded, drawing: drawing,
            outputs: [.init(role: "native-raster", asset: .init(mediaType: "application/json", bytes: DrawingPackageCodec.encoder().encode(result.raster)))])
          nativeDrawings["\(index):\(options.style.rawValue)"] = drawing
          budget.append(["source_index": index, "artist": artist.identifier, "program_hash": package.program.contentHash.description,
            "artist_input_sha256": fixed.sha256, "strokes": result.program.strokes.count,
            "points": result.program.strokes.reduce(0) { $0 + $1.path.points.count }])
        } catch {
          failures.append("native-\(index):\(options.style.rawValue): \(error.localizedDescription)")
          _ = try await store.finishReviewGeneration(id: id, status: .failed, reason: error.localizedDescription)
        }
      }
    }
    #expect(scheduledIDs.count == 40 && Set(scheduledIDs).count == 40)
    var comparisons: [PortraitReviewComparison] = [], previewIndex: [[String: Any]] = []
    let qa = root.appendingPathComponent("preview-qa", isDirectory: true)
    try FileManager.default.createDirectory(at: qa, withIntermediateDirectories: false)
    for index in photos.indices {
      guard let swift = swiftDrawings[index] else { continue }
      for style in Self.styles {
        guard let native = nativeDrawings["\(index):\(style.rawValue)"] else { continue }
        let seedHex = String(DrawingPackageCodec.sha256(Data(("\(index):\(style.rawValue):" + manifestHash).utf8)).prefix(16))
        let seed = try #require(UInt64(seedHex, radix: 16))
        let comparison = try await store.createReviewComparison(first: native, second: swift, presentationSeed: seed,
          rubricVersion: "portrait-review-v1")
        #expect(try await store.reviewLabelHead(comparisonID: comparison.id) == nil)
        comparisons.append(comparison)
        var item: [String: Any] = ["comparison_id": comparison.id.uuidString.lowercased(), "source_index": index,
          "native_style": style.rawValue, "original_source_sha256": comparison.originalSourceSHA256,
          "display_revision": comparison.displayTransformRevision]
        for side in [PortraitReviewChoice.a, .b] {
          let asset = try await store.loadReviewDisplayPreview(comparisonID: comparison.id, side: side)
          let name = comparison.id.uuidString.lowercased() + "-" + side.rawValue + ".png"
          try asset.bytes.write(to: qa.appendingPathComponent(name), options: .withoutOverwriting)
          item[side.rawValue] = ["file": name, "sha256": asset.sha256,
            "artist": side == .a ? (try await store.loadReviewPackage(origin: comparison.a.origin)).artist.identifier
              : (try await store.loadReviewPackage(origin: comparison.b.origin)).artist.identifier]
        }
        previewIndex.append(item)
      }
    }
    for drawing in Array(swiftDrawings.values) + Array(nativeDrawings.values) {
      let reopened = PortraitCandidateStore(directoryURL: libraryURL)
      let exact = try await reopened.loadDrawing(drawing.id)
      #expect(exact == drawing)
      #expect(try DrawingPackageCodec.decode(try await reopened.exportDrawingPackage(exact)).program == drawing.program)
    }
    let exported = try await store.exportReviewDataset(to: root.appendingPathComponent("PilotDataset", isDirectory: true))
    #expect(exported.counts.requests == 40)
    #expect(exported.counts.labelRevisions == 0 && exported.counts.declaredSubjects == 0 && exported.counts.declaredPhotoSessions == 0)
    #expect(exported.counts.comparisons == comparisons.count)
    try json(["schema_version": 1, "manifest_sha256": manifestHash, "scheduled_model_jobs": 10,
      "scheduled_native_jobs": 30, "valid_model_drawings": swiftDrawings.count, "valid_native_drawings": nativeDrawings.count,
      "comparisons": comparisons.count, "maximum_comparisons": 30, "failures": failures, "human_labels": 0,
      "human_groups": "unknown-unassigned", "field_mm": [100, 100], "nominal_pen_mm": 0.4,
      "dataset": try object(DrawingPackageCodec.encoder().encode(exported)), "program_budgets": budget]).write(
        to: root.appendingPathComponent("pilot-integration-report.json"), options: .withoutOverwriting)
    try json(["schema_version": 1, "items": previewIndex, "human_quality_evaluation": "pending"]).write(
      to: qa.appendingPathComponent("index.json"), options: .withoutOverwriting)
  }

  private static var phase: String? { ProcessInfo.processInfo.environment["PORTRAIT_FACE_PILOT_PHASE"] }
  private static let styles: [PortraitStyle] = [.flowEdges, .contours, .sketch]
  private static func root() throws -> URL {
    let path = try #require(ProcessInfo.processInfo.environment["PORTRAIT_FACE_PILOT_ROOT"])
    guard path.hasPrefix("/"), path != "/" else { throw DrawingTransferError.invalid("Pilot root must be absolute.") }
    return URL(fileURLWithPath: path, isDirectory: true)
  }
  private static func preparationPass() throws -> String {
    let value = ProcessInfo.processInfo.environment["PORTRAIT_FACE_PILOT_PREPARATION_PASS"] ?? "prepared-v1"
    guard value.count <= 40, value.range(of: "^prepared-v[0-9]+$", options: .regularExpression) != nil else {
      throw DrawingTransferError.invalid("Preparation pass must be a bounded prepared-vN directory name.")
    }
    return value
  }
  private func read(_ url: URL) throws -> Data { try PortraitStudioFiles.read(url, maximumBytes: 32 * 1024 * 1024) }
  private func object(_ bytes: Data) throws -> [String: Any] { try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any]) }
  private func string(_ value: Any?) throws -> String { try #require(value as? String) }
  private func number(_ value: Any?) throws -> Double { try #require(value as? Double) }
  private func uuid(_ value: Any?) throws -> UUID { try #require((value as? String).flatMap(UUID.init(uuidString:))) }
  private func json(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]) }
  private static func stableUUID(_ text: String) -> UUID {
    let id = Array(DrawingPackageCodec.sha256(Data(text.utf8)).prefix(32))
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
}
