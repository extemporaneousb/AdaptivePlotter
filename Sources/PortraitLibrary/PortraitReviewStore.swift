import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PortraitCore
import PortraitArtists

package struct PortraitReviewGenerationSummary: Codable, Identifiable, Sendable {
  package let id: UUID
  package let captureID: UUID
  package let sourceSHA256: String
  package let groups: PortraitReviewGroups
  package let artist: DrawingPackageArtist
  package let status: PortraitReviewGenerationStatus?
  package let reason: String?
  package let pilotID: UUID?
  package let acquisitionID: UUID?
  package let split: PortraitReviewDatasetSplit
}

package struct PortraitReviewPackageReference: Codable {
  package let origin: DrawingOriginReference
  package let packageSHA256: String
  package let canonicalDrawingID: String
  package let canonicalPhotoID: UUID?
  package let material: PortraitReviewMaterial?
  package let dependency: PortraitReviewDatasetDependency?
}

/// The existing serialized library owner selects immutable review records in its own SQLite state.
/// Packages are exact evidence copies; this journal cannot save, restore, or execute artwork.
extension PortraitCandidateStore {
  package func reviewLibraryIdentity() throws -> UUID {
    try ensureLibraryGraph()
    try validateReviewMutationOwnership()
    let db = try libraryDatabase()
    if let text = try db.scalar("SELECT value FROM state WHERE key='library_uuid'") {
      guard let id = UUID(uuidString: text) else { throw DrawingTransferError.invalid("The library producer UUID is invalid.") }
      return id
    }
    let id = UUID()
    try db.transaction {
      try db.setState("library_uuid", id.uuidString.lowercased()); try db.execute("PRAGMA user_version=2")
      try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
    return id
  }

  package var reviewRoot: URL { directoryURL.appendingPathComponent("review-v1", isDirectory: true) }

  package func reviewKey(_ kind: String, _ id: UUID) -> String {
    "review." + kind + "." + id.uuidString.lowercased()
  }

  package func reviewFile(_ hash: String) throws -> URL {
    guard PortraitReviewValidation.isHash(hash) else { throw DrawingTransferError.invalid("Invalid review asset hash.") }
    return reviewRoot.appendingPathComponent("assets", isDirectory: true).appendingPathComponent(hash)
  }

  @discardableResult
  package func retainReviewBytes(_ bytes: Data) throws -> String {
    guard !bytes.isEmpty, bytes.count <= DrawingTransferLimits.drawingJSONBytes else {
      throw DrawingTransferError.limit("Review record exceeds its byte limit.")
    }
    let hash = DrawingPackageCodec.sha256(bytes), destination = try reviewFile(hash)
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    if !FileManager.default.fileExists(atPath: destination.path) {
      try bytes.write(to: destination, options: [.atomic])
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
      try synchronize(destination)
    }
    guard try readReviewBytes(hash) == bytes else { throw DrawingTransferError.conflict("Frozen review bytes differ.") }
    return hash
  }

  package func readReviewBytes(_ hash: String) throws -> Data {
    let url = try reviewFile(hash)
    let bytes = try Self.boundedReviewRead(url, maximumBytes: DrawingTransferLimits.drawingJSONBytes)
    guard DrawingPackageCodec.sha256(bytes) == hash else { throw DrawingTransferError.invalid("Stored review checksum mismatch.") }
    return bytes
  }

  package nonisolated static func boundedReviewRead(_ url: URL, maximumBytes: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true, let count = values.fileSize,
      count > 0, count <= maximumBytes else {
      throw DrawingTransferError.limit("Stored review bytes are missing or exceed their limit.")
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var bytes = Data()
    while let chunk = try handle.read(upToCount: min(65_536, count + 1 - bytes.count)), !chunk.isEmpty {
      bytes.append(chunk)
      guard bytes.count <= count else { throw DrawingTransferError.limit("Review asset grew during its bounded read.") }
    }
    guard bytes.count == count else { throw DrawingTransferError.invalid("Stored review byte count changed.") }
    return bytes
  }

  package func reviewRecord<T: Decodable>(_ type: T.Type, kind: String, id: UUID) throws -> T? {
    guard let hash = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", [reviewKey(kind, id)]) else { return nil }
    return try JSONDecoder().decode(type, from: readReviewBytes(hash))
  }

  private func commitReviewRecord<T: Encodable>(_ record: T, kind: String, id: UUID,
    summary: PortraitReviewGenerationSummary? = nil) throws {
    try validateReviewMutationOwnership()
    let bytes = try DrawingPackageCodec.encoder().encode(record), hash = try retainReviewBytes(bytes)
    try validateReviewMutationOwnership()
    let db = try libraryDatabase(), key = reviewKey(kind, id)
    try db.transaction {
      if let existing = try db.scalar("SELECT value FROM state WHERE key=?", [key]) {
        guard existing == hash else { throw DrawingTransferError.conflict("An immutable review identity already has different bytes.") }
      } else {
        try db.setState(key, hash)
        if let summary {
          try db.setState(reviewKey("summary", id), db.encode(summary))
          if kind == "request" {
            try db.setState(reviewKey("group-reference", id), db.encode(PortraitReviewDatasetGroup(requestID: id,
              captureID: summary.captureID, acquisitionID: summary.acquisitionID, sourceSHA256: summary.sourceSHA256,
              groups: summary.groups, split: summary.split,
              libraryID: try db.scalar("SELECT value FROM state WHERE key='library_uuid'").flatMap(UUID.init(uuidString:)))))
          }
        }
        if kind == "request", let pilotID = summary?.pilotID {
          let countKey = reviewKey("pilot-attempt-count", pilotID)
          let count = Int(try db.scalar("SELECT value FROM state WHERE key=?", [countKey]) ?? "0") ?? -1
          guard (0..<18).contains(count) else { throw DrawingTransferError.limit("The pilot attempt cap is exhausted or invalid.") }
          try db.setState(countKey, String(count + 1))
        }
        try db.bumpRevision()
      }
    }
    refreshCommittedLibraryGeneration()
  }

  package func reviewRecordSelectors(kind: String, offset: Int = 0, limit: Int = 32) throws -> [(UUID, String)] {
    guard offset >= 0, (1...20_001).contains(limit) else { throw DrawingTransferError.limit("Invalid review page bounds.") }
    let prefix = "review." + kind + "."
    return try libraryDatabase().rows("SELECT key,value FROM state WHERE key LIKE ? ORDER BY key LIMIT ? OFFSET ?",
      [prefix + "%", String(limit), String(offset)]).map {
      guard let key = $0[0], let hash = $0[1], let id = UUID(uuidString: String(key.dropFirst(prefix.count))),
        PortraitReviewValidation.isHash(hash) else { throw DrawingTransferError.invalid("Review selector identity is invalid.") }
      return (id, hash)
    }
  }

  package func freezeReviewPilot(_ pilot: PortraitReviewPilotManifest) throws {
    try pilot.validate(); try ensureLibraryGraph()
    try commitReviewRecord(pilot, kind: "pilot", id: pilot.id)
  }

  private func validatePilotRequest(_ request: PortraitReviewGenerationRequest) throws {
    guard let id = request.pilotID else { return }
    guard let pilot = try reviewRecord(PortraitReviewPilotManifest.self, kind: "pilot", id: id) else {
      throw DrawingTransferError.unavailable("Freeze the feasibility pilot before requesting generation.")
    }
    try pilot.validate()
    guard let source = pilot.sources.first(where: { $0.captureID == request.captureID }) else {
      throw DrawingTransferError.conflict("Generation capture is outside the frozen pilot source cohort.")
    }
    guard request.createdAt >= pilot.createdAt,
      source.acquisitionID == request.acquisitionID, source.sourceSHA256 == request.source.sha256,
      source.groups == request.groups, source.split == request.split,
      pilot.arms.contains(where: { $0.artist == request.artist && $0.environmentJSON == request.environmentJSON
        && (source.conversionJSON ?? $0.conversionJSON) == request.conversionJSON && $0.seed == request.seed
        && (source.material ?? $0.material) == request.material }) else {
      throw DrawingTransferError.conflict("Generation differs from the frozen pilot source, settings, groups, or material.")
    }
    let count = Int(try libraryDatabase().scalar("SELECT value FROM state WHERE key=?",
      [reviewKey("pilot-attempt-count", pilot.id)]) ?? "0") ?? -1
    guard count < pilot.maximumJobs else { throw DrawingTransferError.limit("The feasibility pilot has reached its 18-attempt cap.") }
  }

  package func beginReviewGeneration(_ request: PortraitReviewGenerationRequest) throws {
    try request.validate(); try DrawingPackageLibraryValidation.validateImage(request.source)
    try ensureLibraryGraph()
    let libraryID = try reviewLibraryIdentity()
    if let existing = try reviewRecord(PortraitReviewGenerationRequest.self, kind: "request", id: request.id) {
      guard existing == request else { throw DrawingTransferError.conflict("A generation request is already frozen differently.") }
      return
    }
    try validatePilotRequest(request)
    let groups = try reviewGroupingEntries() + [.init(requestID: request.id, captureID: request.captureID,
      acquisitionID: request.acquisitionID, sourceSHA256: request.source.sha256, groups: request.groups, split: request.split,
      libraryID: libraryID)]
    try PortraitReviewSplitValidation.validate(groups, dependencies: reviewArtifactDependencies())
    try commitReviewRecord(request, kind: "request", id: request.id,
      summary: .init(id: request.id, captureID: request.captureID, sourceSHA256: request.source.sha256,
        groups: request.groups, artist: request.artist, status: nil, reason: nil, pilotID: request.pilotID,
        acquisitionID: request.acquisitionID, split: request.split))
  }

  package func finishReviewGeneration(id: UUID, status: PortraitReviewGenerationStatus,
    drawing: SavedDrawing? = nil, reason: String? = nil, outputs: [PortraitReviewAsset] = [],
    now: Date = Date(), runtimeEnvironmentJSON: Data? = nil, runtimeMetricsJSON: Data? = nil) throws -> PortraitReviewGenerationOutcome {
    guard let request = try reviewRecord(PortraitReviewGenerationRequest.self, kind: "request", id: id),
      let requestHash = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", [reviewKey("request", id)]) else {
      throw DrawingTransferError.unavailable("The generation request was not durably frozen before its outcome.")
    }
    try request.validate()
    guard now >= request.createdAt else { throw DrawingTransferError.invalid("Generation outcome precedes its frozen request.") }
    var reference: PortraitReviewPackageReference?
    if status == .succeeded {
      guard let drawing else { throw DrawingTransferError.invalid("Successful generation requires canonical SavedDrawing.") }
      let bytes = try exportDrawingPackage(drawing), package = try DrawingPackageCodec.decode(bytes)
      guard package.origin.captureID == request.captureID, package.source == request.source,
        (package.createdAt >= request.createdAt || request.recordingMode == .retrospectiveExternalImport), package.createdAt <= now,
        package.artist == request.artist, package.program.fieldExtent.width == request.material.widthMM,
        package.program.fieldExtent.height == request.material.heightMM,
        package.program.strokes.allSatisfy({ $0.style.nominalLineWidth == request.material.nominalLineWidthMM }),
        request.inputs.first(where: { $0.role == "artist-input" }).map({ $0.asset == package.artistInput }) ?? true else {
        throw DrawingTransferError.conflict("Successful result differs from the frozen source, artist, material, or derived input.")
      }
      reference = try retainReviewPackage(drawing, material: request.material)
    } else if drawing != nil { throw DrawingTransferError.invalid("Non-success jobs cannot claim a DrawingPackage.") }
    let outcome = try PortraitReviewGenerationOutcome(id: id, requestSHA256: requestHash,
      status: status, recordedAt: now, origin: reference?.origin, packageSHA256: reference?.packageSHA256,
      reason: reason, outputs: outputs, runtimeEnvironmentJSON: runtimeEnvironmentJSON, runtimeMetricsJSON: runtimeMetricsJSON)
    try commitReviewRecord(outcome, kind: "outcome", id: id,
      summary: .init(id: request.id, captureID: request.captureID, sourceSHA256: request.source.sha256,
        groups: request.groups, artist: request.artist, status: outcome.status, reason: outcome.reason, pilotID: request.pilotID,
        acquisitionID: request.acquisitionID, split: request.split))
    return outcome
  }

  package func reviewGenerationPage(offset: Int = 0, limit: Int = 32) throws -> [PortraitReviewGenerationSummary] {
    guard (1...128).contains(limit) else { throw DrawingTransferError.limit("Generation page exceeds 128 records.") }
    let prefix = "review.summary."
    return try libraryDatabase().rows("SELECT key,value FROM state WHERE key LIKE ? ORDER BY key LIMIT ? OFFSET ?",
      [prefix + "%", String(limit), String(offset)]).map { row in
      guard let key = row[0], let value = row[1], value.utf8.count <= 2 * 1024 * 1024,
        let id = UUID(uuidString: String(key.dropFirst(prefix.count))) else {
        throw DrawingTransferError.invalid("Generation summary identity or limit is invalid.")
      }
      let summary = try JSONDecoder().decode(PortraitReviewGenerationSummary.self, from: Data(value.utf8))
      guard summary.id == id, PortraitReviewValidation.isHash(summary.sourceSHA256) else {
        throw DrawingTransferError.invalid("Generation summary differs from its selector.")
      }
      return summary
    }
  }

  package func reviewPackageReference(_ origin: DrawingOriginReference) throws -> PortraitReviewPackageReference? {
    guard let encoded = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", ["review.package." + origin.drawingID]) else { return nil }
    let reference = try JSONDecoder().decode(PortraitReviewPackageReference.self, from: Data(encoded.utf8))
    guard reference.origin == origin else { throw DrawingTransferError.conflict("Review package origin conflicts with its selector.") }
    return reference
  }

  private func retainReviewPackage(_ drawing: SavedDrawing, material: PortraitReviewMaterial? = nil) throws -> PortraitReviewPackageReference {
    try validateReviewMutationOwnership()
    let bytes = try exportDrawingPackage(drawing), package = try DrawingPackageCodec.decode(bytes)
    let reference = PortraitReviewPackageReference(origin: package.origin, packageSHA256: try retainReviewBytes(bytes),
      canonicalDrawingID: drawing.id, canonicalPhotoID: drawing.portraitCandidate?.photoID, material: material,
      dependency: try Self.reviewNativeDependency(package))
    let db = try libraryDatabase()
    try validateReviewMutationOwnership()
    try db.transaction {
      if let prior = try reviewPackageReference(package.origin) {
        guard prior.packageSHA256 == reference.packageSHA256, prior.canonicalDrawingID == reference.canonicalDrawingID,
          prior.canonicalPhotoID == reference.canonicalPhotoID,
          prior.dependency == reference.dependency,
          prior.material == nil || material == nil || prior.material == material else {
          throw DrawingTransferError.conflict("The frozen review package or material differs.")
        }
      } else {
        try db.setState("review.package." + package.origin.drawingID, db.encode(reference)); try db.bumpRevision()
      }
    }
    refreshCommittedLibraryGeneration()
    return try reviewPackageReference(package.origin) ?? reference
  }

  package func loadReviewPackage(origin: DrawingOriginReference) throws -> DrawingPackage {
    guard let reference = try reviewPackageReference(origin) else { throw DrawingTransferError.unavailable("The exact reviewed package is unavailable.") }
    let package = try DrawingPackageCodec.decode(readReviewBytes(reference.packageSHA256))
    try DrawingPackageLibraryValidation.validate(package)
    guard package.origin == reference.origin else { throw DrawingTransferError.invalid("Review package origin mismatch.") }
    return package
  }

  package func prepareReviewDrawing(_ drawing: SavedDrawing) throws -> DrawingPackage {
    let reference = try retainReviewPackage(drawing)
    return try loadReviewPackage(origin: reference.origin)
  }

  private func validateReviewLiveOrigin(_ origin: DrawingOriginReference) throws {
    guard let reference = try reviewPackageReference(origin) else { throw DrawingTransferError.unavailable("The reviewed result has no durable package.") }
    let drawing: SavedDrawing
    if let photo = reference.canonicalPhotoID {
      drawing = try loadDrawing(.init(candidateID: reference.canonicalDrawingID, photoID: photo))
    } else { drawing = try loadDrawing(reference.canonicalDrawingID) }
    try validateDurableDrawing(drawing)
    let bytes = try exportDrawingPackage(drawing)
    guard DrawingPackageCodec.sha256(bytes) == reference.packageSHA256,
      try DrawingPackageCodec.decode(bytes).origin == origin else {
      throw DrawingTransferError.conflict("The selected canonical result changed or was deleted. Reload before reviewing.")
    }
  }

  package func createReviewComparison(first: SavedDrawing, second: SavedDrawing, presentationSeed: UInt64,
    rubricVersion: String, now: Date = Date()) throws -> PortraitReviewComparison {
    let firstReference = try retainReviewPackage(first), secondReference = try retainReviewPackage(second)
    let p = try loadReviewPackage(origin: firstReference.origin), q = try loadReviewPackage(origin: secondReference.origin)
    let widths = Array(Set(p.program.strokes.map { $0.style.nominalLineWidth })).sorted()
    guard widths == Array(Set(q.program.strokes.map { $0.style.nominalLineWidth })).sorted(), let pen = widths.first else {
      throw DrawingTransferError.invalid("Matched review requires the same nominal pen widths on both results.")
    }
    let common = PortraitReviewMaterial(widthMM: max(p.program.fieldExtent.width, q.program.fieldExtent.width),
      heightMM: max(p.program.fieldExtent.height, q.program.fieldExtent.height), nominalLineWidthMM: pen,
      provenance: "Authored nominal dimensions and widths only; no measured physical pen claim.")
    let previewP = try reviewDisplayPreview(p.program, common: common)
    let previewQ = try reviewDisplayPreview(q.program, common: common)
    // The image bytes have their own content-addressed identity, independent of descriptor encoding.
    try retainReviewBytes(previewP.bytes); try retainReviewBytes(previewQ.bytes)
    let comparison = try PortraitReviewComparison(first: .init(package: p, packageSHA256: firstReference.packageSHA256,
      displayPreviewSHA256: previewP.sha256, material: firstReference.material),
      second: .init(package: q, packageSHA256: secondReference.packageSHA256,
        displayPreviewSHA256: previewQ.sha256, material: secondReference.material),
      presentationSeed: presentationSeed, rubricVersion: rubricVersion, createdAt: now,
      displayMaterial: common, displayPixelWidth: previewP.pixelWidth!, displayPixelHeight: previewP.pixelHeight!)
    try commitReviewRecord(comparison, kind: "comparison", id: comparison.id)
    return comparison
  }

  private func reviewDisplayPreview(_ program: DrawingProgram, common: PortraitReviewMaterial) throws -> DrawingPackageAsset {
    // One shared mm-to-pixel scale, centered letterboxing, no stretch or artist-specific styling.
    // FieldSpace and this bitmap CGContext are both y-up. Image/native artists already invert
    // image-pixel y during program conversion; subtracting y here would invert the portrait again.
    let padding = (program.strokes.map { $0.style.nominalLineWidth }.max() ?? 0) / 2
    let scale = 1024 / max(common.widthMM + 2 * padding, common.heightMM + 2 * padding)
    let width = min(1024, max(1, Int(ceil((common.widthMM + 2 * padding) * scale))))
    let height = min(1024, max(1, Int(ceil((common.heightMM + 2 * padding) * scale))))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DrawingTransferError.invalid("Cannot rasterize the matched review display.")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setStrokeColor(CGColor(gray: 0, alpha: 1)); context.setLineCap(.round); context.setLineJoin(.round)
    let dx = ((common.widthMM - program.fieldExtent.width) / 2 + padding) * scale
    let dy = ((common.heightMM - program.fieldExtent.height) / 2 + padding) * scale
    for stroke in program.strokes {
      guard let first = stroke.path.points.first else { continue }
      context.beginPath(); context.move(to: CGPoint(x: first.x * scale + dx, y: first.y * scale + dy))
      for point in stroke.path.points.dropFirst() {
        context.addLine(to: CGPoint(x: point.x * scale + dx, y: point.y * scale + dy))
      }
      context.setLineWidth(stroke.style.nominalLineWidth * scale); context.strokePath()
    }
    let bytes = NSMutableData()
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else {
      throw DrawingTransferError.invalid("Cannot encode the matched review display.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingTransferError.invalid("Matched review display encoding failed.") }
    return .init(mediaType: "image/png", bytes: bytes as Data, pixelWidth: width, pixelHeight: height)
  }

  package func loadReviewComparison(id: UUID) throws -> PortraitReviewComparison {
    guard let comparison = try reviewRecord(PortraitReviewComparison.self, kind: "comparison", id: id) else {
      throw DrawingTransferError.unavailable("Comparison is unavailable.")
    }
    try comparison.validate()
    guard comparison.id == id else { throw DrawingTransferError.invalid("Comparison selector identity differs.") }
    for reference in [comparison.a, comparison.b] {
      let package = try loadReviewPackage(origin: reference.origin)
      guard let retained = try reviewPackageReference(reference.origin), retained.packageSHA256 == reference.packageSHA256,
        package.source.sha256 == reference.sourceSHA256, package.preview.sha256 == reference.previewSHA256,
        package.program.fieldExtent.width == reference.material.widthMM,
        package.program.fieldExtent.height == reference.material.heightMM,
        Array(Set(package.program.strokes.map { $0.style.nominalLineWidth })).sorted() == reference.nominalLineWidthsMM else {
        throw DrawingTransferError.invalid("Comparison package identity or nominal material differs.")
      }
    }
    return comparison
  }

  package func loadReviewDisplayPreview(comparisonID: UUID, side: PortraitReviewChoice) throws -> DrawingPackageAsset {
    guard side == .a || side == .b else { throw DrawingTransferError.invalid("A matched display side must be A or B.") }
    let comparison = try loadReviewComparison(id: comparisonID), reference = side == .a ? comparison.a : comparison.b
    let asset = DrawingPackageAsset(mediaType: "image/png", bytes: try readReviewBytes(reference.displayPreviewSHA256),
      pixelWidth: comparison.displayPixelWidth, pixelHeight: comparison.displayPixelHeight)
    try DrawingPackageLibraryValidation.validateImage(asset)
    return asset
  }

  package func reviewComparisonPage(offset: Int = 0, limit: Int = 32) throws -> [PortraitReviewComparison] {
    guard (1...128).contains(limit) else { throw DrawingTransferError.limit("Comparison page exceeds 128 records.") }
    return try reviewRecordSelectors(kind: "comparison", offset: offset, limit: limit).map { id, hash in
      let comparison = try JSONDecoder().decode(PortraitReviewComparison.self, from: readReviewBytes(hash))
      try comparison.validate()
      guard comparison.id == id else { throw DrawingTransferError.invalid("Comparison summary selector differs.") }
      return comparison
    }
  }

  package func reviewLabelHead(comparisonID: UUID) throws -> PortraitReviewLabelRevision? {
    guard let value = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", [reviewKey("head", comparisonID)]) else { return nil }
    guard let id = UUID(uuidString: value), let revision = try reviewRecord(PortraitReviewLabelRevision.self, kind: "label", id: id) else {
      throw DrawingTransferError.invalid("Review label head is invalid.")
    }
    try revision.validate()
    guard revision.comparisonID == comparisonID, revision.id == id else { throw DrawingTransferError.invalid("Label head identity differs.") }
    return revision
  }

  package func appendReviewLabel(comparisonID: UUID, choices: [PortraitReviewDimension: PortraitReviewChoice],
    reviewerID: String?, expectedRevisionID: UUID?, now: Date = Date()) throws -> PortraitReviewLabelRevision {
    try validateReviewMutationOwnership()
    let comparison = try loadReviewComparison(id: comparisonID)
    try validateReviewLiveOrigin(comparison.a.origin); try validateReviewLiveOrigin(comparison.b.origin)
    let db = try libraryDatabase()
    guard let comparisonHash = try db.scalar("SELECT value FROM state WHERE key=?", [reviewKey("comparison", comparisonID)]) else {
      throw DrawingTransferError.unavailable("Comparison disappeared.")
    }
    let prior = try reviewLabelHead(comparisonID: comparisonID)
    guard prior?.id == expectedRevisionID, now >= comparison.createdAt,
      prior.map({ now >= $0.recordedAt }) ?? true else {
      throw DrawingTransferError.conflict("Review changed or its timestamp precedes the displayed comparison. Reload the explicit label head.")
    }
    let revision = try PortraitReviewLabelRevision(comparisonID: comparisonID, comparisonSHA256: comparisonHash,
      choices: choices, reviewerID: reviewerID, recordedAt: now, supersedes: expectedRevisionID)
    let hash = try retainReviewBytes(DrawingPackageCodec.encoder().encode(revision))
    try validateReviewMutationOwnership()
    try db.transaction {
      guard try reviewLabelHead(comparisonID: comparisonID)?.id == expectedRevisionID else {
        throw DrawingTransferError.conflict("Another review revision committed first.")
      }
      try db.setState(reviewKey("label", revision.id), hash)
      try db.setState(reviewKey("head", comparisonID), revision.id.uuidString.lowercased())
      try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
    return revision
  }

  package func reviewGroupDeclaration(origin: DrawingOriginReference) throws -> PortraitReviewGroupDeclaration? {
    guard let idText = try libraryDatabase().scalar("SELECT value FROM state WHERE key=?", ["review.group-origin." + origin.drawingID]),
      let id = UUID(uuidString: idText) else { return nil }
    guard let declaration = try reviewRecord(PortraitReviewGroupDeclaration.self, kind: "group", id: id),
      declaration.origin == origin, declaration.id == id else { throw DrawingTransferError.invalid("Group declaration identity differs.") }
    try declaration.validate()
    return declaration
  }

  package func declareReviewGroups(origin: DrawingOriginReference, groups: PortraitReviewGroups,
    split: PortraitReviewDatasetSplit = .unassigned, acquisitionID: UUID? = nil,
    now: Date = Date()) throws -> PortraitReviewGroupDeclaration {
    try validateReviewMutationOwnership(); try validateReviewLiveOrigin(origin)
    let package = try loadReviewPackage(origin: origin)
    if let existing = try reviewGroupDeclaration(origin: origin) {
      guard existing.groups == groups, existing.split == split, existing.acquisitionID == acquisitionID else {
        throw DrawingTransferError.conflict("Human groups and split were already frozen. They cannot be changed after viewing outcomes.")
      }
      return existing
    }
    let declaration = try PortraitReviewGroupDeclaration(origin: origin, sourceSHA256: package.source.sha256,
      acquisitionID: acquisitionID, groups: groups, split: split, declaredAt: now)
    try PortraitReviewSplitValidation.validate(try reviewGroupingEntries() + [.init(requestID: declaration.id,
      captureID: origin.captureID, acquisitionID: acquisitionID, sourceSHA256: package.source.sha256, groups: groups, split: split,
      libraryID: origin.libraryID)], dependencies: reviewArtifactDependencies())
    let hash = try retainReviewBytes(DrawingPackageCodec.encoder().encode(declaration)), db = try libraryDatabase()
    try validateReviewMutationOwnership()
    try db.transaction {
      guard try db.scalar("SELECT value FROM state WHERE key=?", ["review.group-origin." + origin.drawingID]) == nil else {
        throw DrawingTransferError.conflict("Human group declaration committed concurrently.")
      }
      try db.setState(reviewKey("group", declaration.id), hash)
      try db.setState("review.group-origin." + origin.drawingID, declaration.id.uuidString.lowercased())
      try db.setState(reviewKey("group-reference", declaration.id), db.encode(PortraitReviewDatasetGroup(requestID: declaration.id,
        captureID: origin.captureID, acquisitionID: acquisitionID, sourceSHA256: package.source.sha256, groups: groups, split: split,
        libraryID: origin.libraryID)))
      try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
    return declaration
  }

  package func reviewGroupingEntries() throws -> [PortraitReviewDatasetGroup] {
    var groups: [PortraitReviewDatasetGroup] = []
    var offset = 0, byteCount = 0
    let db = try libraryDatabase()
    while true {
      let rows = try db.rows("SELECT key,value FROM state WHERE key LIKE 'review.group-reference.%' ORDER BY key LIMIT 128 OFFSET ?", [String(offset)])
      for row in rows {
        guard let value = row[1] else { throw DrawingTransferError.invalid("Grouping summary is missing.") }
        byteCount += value.utf8.count
        guard groups.count < 20_000, byteCount <= 64 * 1024 * 1024 else {
          throw DrawingTransferError.limit("Review grouping metadata exceeds its supported limits.")
        }
        let group = try db.decode(PortraitReviewDatasetGroup.self, value)
        guard row[0] == reviewKey("group-reference", group.requestID) else {
          throw DrawingTransferError.invalid("Group summary identity differs from its selector.")
        }
        groups.append(group)
      }
      if rows.count < 128 { break }
      offset += rows.count
    }
    return groups
  }

  package nonisolated static func reviewNativeDependency(_ package: DrawingPackage) throws -> PortraitReviewDatasetDependency? {
    guard let bytes = package.legacyCandidateJSON else { return nil }
    let candidate = try JSONDecoder().decode(PortraitCandidate.self, from: bytes)
    try candidate.validateIntegrity()
    guard candidate.id == package.origin.resultID, candidate.photoID == package.origin.captureID,
      candidate.sourceSHA256 == package.source.sha256 else {
      throw DrawingTransferError.invalid("Native lineage does not bind the exact package occurrence.")
    }
    let namespace = "native:" + package.origin.libraryID.uuidString.lowercased() + ":"
    var ancestry = [namespace + "result:" + candidate.id,
      namespace + "family:" + candidate.lineage.ancestryGroupID.uuidString.lowercased()]
    if let parent = candidate.lineage.parentID { ancestry.append(namespace + "result:" + parent) }
    return .init(origin: package.origin, sourceSHA256: package.source.sha256, ancestryIDs: Array(Set(ancestry)).sorted())
  }

  package func reviewArtifactDependencies() throws -> [PortraitReviewDatasetDependency] {
    let rows = try libraryDatabase().rows("SELECT value FROM state WHERE key LIKE 'review.package.%' ORDER BY key LIMIT 10001")
    guard rows.count <= 10_000 else { throw DrawingTransferError.limit("Too many retained review artifacts.") }
    return try rows.compactMap { row in
      let reference = try libraryDatabase().decode(PortraitReviewPackageReference.self, row[0])
      try reference.dependency?.validate()
      guard reference.dependency == nil || reference.dependency?.origin == reference.origin else {
        throw DrawingTransferError.invalid("Native dependency selector identity differs.")
      }
      return reference.dependency
    }
  }
}
