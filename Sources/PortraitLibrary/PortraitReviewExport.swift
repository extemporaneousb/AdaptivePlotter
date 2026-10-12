import Foundation
import PlotterModel
import PortraitCore

extension PortraitCandidateStore {
  /// Writes a new directory only. All selectors and payloads are verified before the final rename.
  /// Split arguments confirm frozen assignments; export cannot silently move outcomes between splits.
  package func exportReviewDataset(to destination: URL,
    splitAssignments: [UUID: PortraitReviewDatasetSplit] = [:]) throws -> PortraitReviewDatasetManifest {
    guard destination.isFileURL, !FileManager.default.fileExists(atPath: destination.path) else {
      throw DrawingTransferError.conflict("Choose a new dataset export directory.")
    }
    let resolved = destination.standardizedFileURL.resolvingSymlinksInPath()
    let owned = directoryURL.standardizedFileURL.resolvingSymlinksInPath().path + "/"
    guard !resolved.path.hasPrefix(owned), resolved.path != directoryURL.standardizedFileURL.resolvingSymlinksInPath().path else {
      throw DrawingTransferError.invalid("Dataset exports must be outside the private library.")
    }
    try ensureLibraryGraph()
    let groups = try reviewGroupingEntries()
    let dependencies = try reviewArtifactDependencies()
    try PortraitReviewSplitValidation.validate(groups, dependencies: dependencies)
    let byGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.requestID, $0) })
    for (id, split) in splitAssignments {
      guard let group = byGroup[id], group.split == split else {
        throw DrawingTransferError.conflict("Export cannot change a frozen group split or invent a request identity.")
      }
    }
    let parent = destination.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let staging = parent.appendingPathComponent(".portrait-review-export-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: staging.appendingPathComponent("assets", isDirectory: true),
      withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var finished = false
    defer { if !finished { try? FileManager.default.removeItem(at: staging) } }
    var files: [String: PortraitReviewDatasetFile] = [:]
    var totalBytes = 0
    func writeAsset(_ bytes: Data, mediaType: String) throws -> String {
      guard !bytes.isEmpty, bytes.count <= DrawingTransferLimits.attachmentJSONBytes else {
        throw DrawingTransferError.limit("Dataset asset exceeds its supported byte limit.")
      }
      let hash = DrawingPackageCodec.sha256(bytes)
      if files[hash] != nil { return hash }
      guard files.count < 100_000, totalBytes <= 1024 * 1024 * 1024 - bytes.count else {
        throw DrawingTransferError.limit("Dataset export exceeds its 1 GiB or asset-count limit.")
      }
      let path = "assets/" + hash, file = staging.appendingPathComponent(path)
      try bytes.write(to: file, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      try synchronize(file)
      guard DrawingPackageCodec.sha256(try Self.boundedReviewRead(file, maximumBytes: DrawingTransferLimits.attachmentJSONBytes)) == hash else {
        throw DrawingTransferError.invalid("Dataset asset write verification failed.")
      }
      files[hash] = .init(path: path, bytes: bytes, mediaType: mediaType)
      totalBytes += bytes.count
      return hash
    }
    var records: [PortraitReviewDatasetRecord] = []
    var requests: [UUID: PortraitReviewGenerationRequest] = [:]
    var outcomes: [UUID: PortraitReviewGenerationOutcome] = [:]
    var comparisons: [UUID: PortraitReviewComparison] = [:]
    var labels: [UUID: PortraitReviewLabelRevision] = [:]
    var declarations: [DrawingOriginReference: PortraitReviewGroupDeclaration] = [:]
    let kinds = ["request", "outcome", "pilot", "group", "comparison", "label"]
    var selectorSnapshot: [String: [(UUID, String)]] = [:]
    for kind in kinds {
      let selected = try reviewRecordSelectors(kind: kind, limit: 20_001)
      guard records.count + selected.count <= 20_000 else { throw DrawingTransferError.limit("Dataset has more than 20,000 records.") }
      selectorSnapshot[kind] = selected
      for (id, hash) in selected {
        let bytes = try readReviewBytes(hash)
        _ = try writeAsset(bytes, mediaType: "application/vnd.adaptiveplotter.portrait-review-" + kind + "+json")
        var terminalStatus: PortraitReviewGenerationStatus?
        switch kind {
        case "request":
          let request = try JSONDecoder().decode(PortraitReviewGenerationRequest.self, from: bytes)
          try request.validate(); try DrawingPackageLibraryValidation.validateImage(request.source)
          guard request.id == id else { throw DrawingTransferError.invalid("Request selector mismatch.") }
          requests[id] = request
          _ = try writeAsset(request.source.bytes, mediaType: request.source.mediaType)
          for input in request.inputs { _ = try writeAsset(input.asset.bytes, mediaType: input.asset.mediaType) }
          for data in [request.artist.settingsJSON, request.environmentJSON, request.conversionJSON] {
            _ = try writeAsset(data, mediaType: "application/json")
          }
        case "outcome":
          let outcome = try JSONDecoder().decode(PortraitReviewGenerationOutcome.self, from: bytes)
          try outcome.validate()
          guard outcome.id == id else { throw DrawingTransferError.invalid("Outcome selector mismatch.") }
          outcomes[id] = outcome; terminalStatus = outcome.status
          for output in outcome.outputs { _ = try writeAsset(output.asset.bytes, mediaType: output.asset.mediaType) }
          for data in [outcome.runtimeEnvironmentJSON, outcome.runtimeMetricsJSON].compactMap({ $0 }) {
            _ = try writeAsset(data, mediaType: "application/json")
          }
        case "pilot":
          let pilot = try JSONDecoder().decode(PortraitReviewPilotManifest.self, from: bytes)
          try pilot.validate()
          guard pilot.id == id else { throw DrawingTransferError.invalid("Pilot selector mismatch.") }
        case "group":
          let declaration = try JSONDecoder().decode(PortraitReviewGroupDeclaration.self, from: bytes)
          try declaration.validate()
          guard declaration.id == id else { throw DrawingTransferError.invalid("Group selector mismatch.") }
          declarations[declaration.origin] = declaration
        case "comparison":
          let comparison = try loadReviewComparison(id: id)
          comparisons[id] = comparison
          for reference in [comparison.a, comparison.b] {
            _ = try writeAsset(readReviewBytes(reference.displayPreviewSHA256), mediaType: "image/png")
          }
        case "label":
          let label = try JSONDecoder().decode(PortraitReviewLabelRevision.self, from: bytes)
          try label.validate()
          guard label.id == id else { throw DrawingTransferError.invalid("Label selector mismatch.") }
          labels[id] = label
        default: break
        }
        records.append(.init(id: id, kind: kind, fileSHA256: hash, terminalStatus: terminalStatus))
      }
    }
    for (id, outcome) in outcomes {
      guard let request = requests[id], let selector = selectorSnapshot["request"]?.first(where: { $0.0 == id }),
        selector.1 == outcome.requestSHA256, outcome.recordedAt >= request.createdAt else {
        throw DrawingTransferError.invalid("Outcome has no exact frozen pre-generation request.")
      }
    }
    for request in requests.values {
      guard let group = byGroup[request.id], group.captureID == request.captureID,
        group.acquisitionID == request.acquisitionID, group.sourceSHA256 == request.source.sha256,
        group.groups == request.groups, group.split == request.split else {
        throw DrawingTransferError.invalid("Generation grouping summary differs from the frozen request.")
      }
    }
    for declaration in declarations.values {
      guard let group = byGroup[declaration.id], group.captureID == declaration.origin.captureID,
        group.libraryID == declaration.origin.libraryID, group.acquisitionID == declaration.acquisitionID,
        group.sourceSHA256 == declaration.sourceSHA256, group.groups == declaration.groups,
        group.split == declaration.split else { throw DrawingTransferError.invalid("Human group summary differs from its declaration.") }
    }
    guard groups.count == requests.count + declarations.count else {
      throw DrawingTransferError.invalid("Grouping summaries do not match the complete selected request/declaration journal.")
    }
    var ratedHeads = 0, skippedHeads = 0
    for comparison in comparisons.values {
      let hash = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", [reviewKey("comparison", comparison.id)])
      let head = try reviewLabelHead(comparisonID: comparison.id)
      if let head {
        guard labels[head.id] == head else { throw DrawingTransferError.invalid("Label head is missing from the export.") }
        if head.isSkipped { skippedHeads += 1 } else { ratedHeads += 1 }
      }
      for label in labels.values where label.comparisonID == comparison.id {
        guard label.comparisonSHA256 == hash, label.recordedAt >= comparison.createdAt,
          label.supersedes.map({ labels[$0]?.comparisonID == comparison.id }) ?? true else {
          throw DrawingTransferError.invalid("Label revision does not bind its immutable comparison or prior head.")
        }
      }
    }
    guard labels.values.allSatisfy({ comparisons[$0.comparisonID] != nil }) else {
      throw DrawingTransferError.invalid("A label references an unavailable comparison.")
    }
    let db = try libraryDatabase()
    let packageRows = try db.rows("SELECT value FROM state WHERE key LIKE 'review.package.%' ORDER BY key LIMIT 10001")
    guard packageRows.count <= 10_000 else { throw DrawingTransferError.limit("Dataset has more than 10,000 drawing results.") }
    var results: [PortraitReviewDatasetResult] = []
    for row in packageRows {
      let reference = try db.decode(PortraitReviewPackageReference.self, row[0])
      let bytes = try readReviewBytes(reference.packageSHA256), package = try DrawingPackageCodec.decode(bytes)
      try DrawingPackageLibraryValidation.validate(package)
      guard package.origin == reference.origin else { throw DrawingTransferError.invalid("Export package origin mismatch.") }
      guard try Self.reviewNativeDependency(package) == reference.dependency else {
        throw DrawingTransferError.invalid("Native lineage summary differs from the exact retained result bytes.")
      }
      _ = try writeAsset(bytes, mediaType: "application/vnd.adaptiveplotter.drawing-package+json")
      _ = try writeAsset(package.source.bytes, mediaType: package.source.mediaType)
      _ = try writeAsset(package.artistInput.bytes, mediaType: package.artistInput.mediaType)
      _ = try writeAsset(package.preview.bytes, mediaType: package.preview.mediaType)
      _ = try writeAsset(package.resultRecordJSON, mediaType: "application/json")
      let settingsHash = try writeAsset(package.artist.settingsJSON, mediaType: "application/json")
      let programHash = try writeAsset(DrawingPackageCodec.encoder().encode(package.program),
        mediaType: "application/vnd.adaptiveplotter.drawing-program+json")
      let generationMatches = outcomes.values.filter { $0.origin == package.origin }
      guard generationMatches.count <= 1 else { throw DrawingTransferError.conflict("Multiple generation requests claim one immutable result.") }
      let requestID = generationMatches.first?.id ?? declarations[package.origin]?.id
      if let outcome = generationMatches.first {
        guard outcome.status == .succeeded, outcome.packageSHA256 == reference.packageSHA256,
          let request = requests[outcome.id], package.source == request.source,
          package.artist == request.artist else { throw DrawingTransferError.invalid("Export result differs from its generation provenance.") }
      }
      let material = generationMatches.first.flatMap({ requests[$0.id]?.material }) ?? reference.material
        ?? .init(widthMM: package.program.fieldExtent.width, heightMM: package.program.fieldExtent.height,
          nominalLineWidthMM: package.program.strokes[0].style.nominalLineWidth)
      results.append(.init(origin: package.origin, packageSHA256: reference.packageSHA256,
        sourceSHA256: package.source.sha256, artistInputSHA256: package.artistInput.sha256,
        previewSHA256: package.preview.sha256, programSHA256: programHash,
        programContentHash: package.program.contentHash.description, resultRecordSHA256: package.origin.resultRecordSHA256,
        artistSettingsSHA256: settingsHash, material: material,
        nominalLineWidthsMM: Array(Set(package.program.strokes.map { $0.style.nominalLineWidth })).sorted(),
        requestID: requestID, split: requestID.flatMap({ byGroup[$0]?.split }) ?? .unassigned))
    }
    guard outcomes.values.compactMap(\.origin).allSatisfy({ origin in results.contains(where: { $0.origin == origin }) }),
      comparisons.values.allSatisfy({ comparison in [comparison.a, comparison.b].allSatisfy { reference in
        results.contains(where: { $0.origin == reference.origin && $0.packageSHA256 == reference.packageSHA256 })
      } }) else { throw DrawingTransferError.invalid("A success or comparison has no exact retained package.") }
    // Optional imported physical origins are exported separately; records remain controller/evidence claims.
    let physicalRows = try db.rows("SELECT value FROM state WHERE key LIKE 'transfer.attachment.%' ORDER BY key LIMIT 10001")
    guard physicalRows.count <= 10_000 else { throw DrawingTransferError.limit("Too many optional physical attachments.") }
    var plots: [PortraitReviewDatasetPlot] = []
    for row in physicalRows {
      guard let value = row[0], let object = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any],
        let hash = object["hash"] as? String, PortraitReviewValidation.isHash(hash) else {
        throw DrawingTransferError.invalid("Optional physical attachment selector is malformed.")
      }
      let url = directoryURL.appendingPathComponent("transfers", isDirectory: true).appendingPathComponent(hash + ".json")
      let bytes = try Self.boundedReviewRead(url, maximumBytes: DrawingTransferLimits.attachmentJSONBytes)
      guard DrawingPackageCodec.sha256(bytes) == hash else { throw DrawingTransferError.invalid("Physical attachment checksum differs.") }
      let attachment = try PlotAttachmentCodec.decode(bytes)
      guard results.contains(where: { $0.origin == attachment.origin }) else { continue }
      _ = try PortraitPlotAttachmentInspection.record(attachment)
      _ = try writeAsset(bytes, mediaType: "application/vnd.adaptiveplotter.plot-attachment+json")
      _ = try writeAsset(attachment.recordJSON, mediaType: "application/json")
      for media in attachment.media { _ = try writeAsset(media.bytes, mediaType: media.mediaType) }
      plots.append(.init(attachment: attachment, attachmentSHA256: hash))
    }
    // Detect concurrent selector mutation before publishing the snapshot.
    for kind in kinds {
      let current = try reviewRecordSelectors(kind: kind, limit: 20_001)
      guard current.map({ $0.0 }) == selectorSnapshot[kind]?.map({ $0.0 }),
        current.map({ $0.1 }) == selectorSnapshot[kind]?.map({ $0.1 }) else {
        throw DrawingTransferError.conflict("Review journal changed during export; retry from its new snapshot.")
      }
    }
    func count(_ status: PortraitReviewGenerationStatus) -> Int { outcomes.values.filter { $0.status == status }.count }
    let counts = PortraitReviewDatasetCounts(requests: requests.count, pending: requests.count - outcomes.count,
      succeeded: count(.succeeded), failed: count(.failed), cancelled: count(.cancelled), skipped: count(.skipped),
      unsupported: count(.unsupported), drawingResults: results.count, comparisons: comparisons.count,
      labelRevisions: labels.count, ratedComparisonHeads: ratedHeads, skippedComparisonHeads: skippedHeads,
      unlabeledComparisons: comparisons.count - ratedHeads - skippedHeads,
      declaredSubjects: Set(groups.compactMap { $0.groups.subjectID }).count,
      declaredPhotoSessions: Set(groups.compactMap { $0.groups.photoSessionID }).count,
      unassignedRequests: requests.values.filter { $0.split == .unassigned }.count,
      groupDeclarations: declarations.count, unassignedResults: results.filter { $0.split == .unassigned }.count,
      plotAttachments: plots.count)
    let manifest = try PortraitReviewDatasetManifest(exportedAt: Date(), groups: groups, results: results,
      records: records, files: files.values.sorted { $0.path < $1.path }, counts: counts, plotOrigins: plots,
      artifactDependencies: dependencies)
    let manifestURL = staging.appendingPathComponent("manifest.json")
    let manifestBytes = try DrawingPackageCodec.encoder().encode(manifest)
    guard manifestBytes.count <= 32 * 1024 * 1024 else { throw DrawingTransferError.limit("Dataset manifest exceeds 32 MiB.") }
    try manifestBytes.write(to: manifestURL, options: .atomic); try synchronize(manifestURL)
    try Self.verifyReviewDataset(at: staging)
    try FileManager.default.moveItem(at: staging, to: destination)
    finished = true
    return manifest
  }

  package nonisolated static func verifyReviewDataset(at directory: URL) throws {
    let url = directory.appendingPathComponent("manifest.json")
    let manifest = try JSONDecoder().decode(PortraitReviewDatasetManifest.self,
      from: boundedReviewRead(url, maximumBytes: 32 * 1024 * 1024))
    try manifest.validate()
    for file in manifest.files {
      let path = directory.appendingPathComponent(file.path)
      let values = try path.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
      guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == file.byteCount,
        file.byteCount <= DrawingTransferLimits.attachmentJSONBytes,
        DrawingPackageCodec.sha256(try boundedReviewRead(path, maximumBytes: DrawingTransferLimits.attachmentJSONBytes)) == file.sha256 else {
        throw DrawingTransferError.invalid("Dataset asset integrity failed: " + file.path)
      }
    }
  }
}
