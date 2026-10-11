import CoreGraphics
import Foundation
import ImageIO
import PlotterModel
import PlotterRuntime
import PortraitArtists
import PortraitCore

package enum DrawingPackageLibraryValidation {
  package static func validate(_ package: DrawingPackage) throws {
    try package.validate()
    try validateImage(package.source); try validateImage(package.preview)
    if let legacy = package.legacyCandidateJSON {
      let candidate = try JSONDecoder().decode(PortraitCandidate.self, from: legacy)
      try candidate.validateIntegrity()
      let encoder = PortraitCandidateCoding.encoder()
      guard candidate.id == package.origin.resultID, candidate.photoID == package.origin.captureID,
        candidate.program == package.program, candidate.createdAt == package.createdAt,
        candidate.sourceData == package.source.bytes,
        try encoder.encode(candidate.raster) == package.artistInput.bytes,
        try encoder.encode(candidate.recipe) == package.artist.settingsJSON,
        candidate.producerRevision == package.artist.revision,
        package.artist.identifier == "adaptiveplotter." + candidate.recipe.style.rawValue,
        package.artistInput.pixelWidth == candidate.raster.width,
        package.artistInput.pixelHeight == candidate.raster.height else {
        throw DrawingTransferError.invalid("The legacy artist, source, input, or program differs from the frozen result.")
      }
    }
  }

  package static func validateImage(_ asset: DrawingPackageAsset) throws {
    try asset.validate(maximumBytes: DrawingTransferLimits.sourceBytes, requireImage: true)
    guard let image = CGImageSourceCreateWithData(asset.bytes as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary), CGImageSourceGetCount(image) == 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
      width.intValue == asset.pixelWidth, height.intValue == asset.pixelHeight,
      CGImageSourceGetType(image) as String? == (asset.mediaType == "image/png" ? "public.png" : "public.jpeg")
    else { throw DrawingTransferError.invalid("Image bytes do not match their declared type or dimensions.") }
  }

  static func sourceAsset(_ bytes: Data) throws -> DrawingPackageAsset {
    guard bytes.count <= DrawingTransferLimits.sourceBytes,
      let image = CGImageSourceCreateWithData(bytes as CFData,
        [kCGImageSourceShouldCache: false] as CFDictionary),
      let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
      let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
      throw DrawingTransferError.invalid("The retained source image cannot be exported.")
    }
    let type = CGImageSourceGetType(image) as String?
    guard type == "public.png" || type == "public.jpeg" else {
      throw DrawingTransferError.invalid("Version one transfers require retained PNG or JPEG source bytes.")
    }
    let asset = DrawingPackageAsset(mediaType: type == "public.png" ? "image/png" : "image/jpeg",
      bytes: bytes, pixelWidth: width.intValue, pixelHeight: height.intValue)
    try validateImage(asset)
    return asset
  }

  static func preview(_ program: DrawingProgram) throws -> DrawingPackageAsset {
    let scale = 768 / max(program.fieldExtent.width, program.fieldExtent.height)
    let width = max(1, Int(ceil(program.fieldExtent.width * scale)))
    let height = max(1, Int(ceil(program.fieldExtent.height * scale)))
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      throw DrawingTransferError.invalid("Unable to create the authored drawing preview.")
    }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setStrokeColor(CGColor(gray: 0, alpha: 1)); context.setLineCap(.round); context.setLineJoin(.round)
    for stroke in program.strokes {
      guard let first = stroke.path.points.first else { continue }
      context.beginPath()
      context.move(to: CGPoint(x: first.x * scale, y: Double(height) - first.y * scale))
      for point in stroke.path.points.dropFirst() {
        context.addLine(to: CGPoint(x: point.x * scale, y: Double(height) - point.y * scale))
      }
      context.setLineWidth(stroke.style.nominalLineWidth * scale); context.strokePath()
    }
    let bytes = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil) else {
      throw DrawingTransferError.invalid("Unable to encode the authored drawing preview.")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw DrawingTransferError.invalid("Preview encoding failed.") }
    return DrawingPackageAsset(mediaType: "image/png", bytes: bytes as Data, pixelWidth: width, pixelHeight: height)
  }
}

package enum PlotAttachmentImportDisposition: Sendable { case imported, alreadyPresent }

package struct PlotAttachmentImportResult: Sendable {
  package let attachmentID: String
  package let disposition: PlotAttachmentImportDisposition
  package let linkedDrawingID: String?
  package let linkedPhotoID: UUID?
}

package struct PlotAttachmentSummary: Codable, Identifiable, Sendable {
  package let id: String
  package let origin: DrawingOriginReference
  package let producerArchiveID: UUID
  package let runID: UUID
  package let recordID: UUID
  package let recordSHA256: String
  package let linkedDrawingID: String?
  package let linkedPhotoID: UUID?
  package let mediaCount: Int
}

package struct PlotAttachmentPageCursor: Sendable {
  fileprivate let key: String
  fileprivate let generation: PortraitLibraryGeneration
  fileprivate let origin: DrawingOriginReference?
}

package struct PlotAttachmentPage: Sendable {
  package let attachments: [PlotAttachmentSummary]
  package let next: PlotAttachmentPageCursor?
}

package enum PortraitPlotAttachmentInspection {
  package static func record(_ attachment: PlotAttachment) throws -> DrawingRunEvidenceRecord {
    try attachment.validate()
    let record = try JSONDecoder().decode(DrawingRunEvidenceRecord.self, from: attachment.recordJSON)
    guard record.runID.rawValue == attachment.runID, record.recordID.rawValue == attachment.recordID,
      record.role == .ordinaryDrawing,
      let reference = record.attemptEvidence?.intent.context.candidate,
      reference.origin == attachment.origin,
      reference.candidateID == attachment.origin.drawingID,
      reference.sourceProgram.contentHash == attachment.origin.programHash else {
      throw DrawingTransferError.invalid("Terminal record does not bind the exact transferred drawing origin.")
    }
    let originals = record.attemptEvidence.map {
      $0.baselines + $0.progressFrames.map(\.media) + $0.terminalFrames
    } ?? []
    for reference in originals {
      let f = reference.frame
      guard f.width > 0, f.height > 0, f.width <= DrawingTransferLimits.maximumImageDimension,
        f.height <= DrawingTransferLimits.maximumImageDimension,
        f.width <= DrawingTransferLimits.maximumImagePixels / f.height,
        reference.byteCount <= DrawingTransferLimits.originalMediaBytes else {
        throw DrawingTransferError.limit("An original frame exceeds the transfer image limits.")
      }
    }
    guard attachment.media.allSatisfy({ $0.mediaType == "application/vnd.adaptiveplotter.frame-pixels" }) else {
      throw DrawingTransferError.invalid("Attachment originals must retain their raw pixel encoding.")
    }
    try record.validateOriginalMedia(Dictionary(uniqueKeysWithValues: attachment.media.map { ($0.sha256, $0.bytes) }))
    return record
  }

  package static func frame(_ attachment: PlotAttachment,
    reference: DrawingRunMediaReference) throws -> StampedFrame {
    let record = try self.record(attachment)
    let declared = record.attemptEvidence.map {
      $0.baselines + $0.progressFrames.map(\.media) + $0.terminalFrames
    } ?? []
    guard declared.contains(reference),
      let original = attachment.media.first(where: { $0.sha256 == reference.frame.frameSHA256 }) else {
      throw DrawingTransferError.invalid("The frame is not declared by this terminal record.")
    }
    return try DrawingRunMediaValidation.frame(reference: reference, bytes: original.bytes)
  }

  package static func attachment(_ exported: DrawingRunTerminalExport) throws -> PlotAttachment {
    guard let origin = exported.record.attemptEvidence?.intent.context.candidate?.origin else {
      throw DrawingTransferError.unavailable("This run did not capture a transferred drawing origin before motion.")
    }
    let attachment = try PlotAttachment(origin: origin, producerArchiveID: exported.archiveID,
      runID: exported.record.runID.rawValue, recordID: exported.record.recordID.rawValue,
      recordJSON: exported.recordJSON, media: exported.originalMedia.map {
        DrawingPackageAsset(mediaType: "application/vnd.adaptiveplotter.frame-pixels", bytes: $0.value)
      })
    _ = try record(attachment)
    return attachment
  }
}

private struct FrozenDrawingPackageReference: Codable {
  let hash: String
  let origin: DrawingOriginReference
  let nativeCandidateRecordSHA256: String?
}

private struct FrozenPlotAttachmentReference: Codable {
  let hash: String
  let origin: DrawingOriginReference
  let producerArchiveID: UUID
  let runID: UUID
  let recordID: UUID
  let recordSHA256: String
  let mediaCount: Int
}

extension PortraitCandidateStore {
  package func ensureRetainedTransferredDrawing(_ drawing: SavedDrawing) throws {
    guard let package = drawing.transferredPackage else { throw DrawingTransferError.invalid("Transferred drawing required.") }
    try ensureLibraryGraph()
    let db = try libraryDatabase()
    if try packageReference(package.origin, db: db) != nil {
      try validateDurableDrawing(drawing)
    } else {
      let imported = try importDrawingPackage(DrawingPackageCodec.encode(package))
      guard imported == drawing else { throw DrawingTransferError.conflict("Retained drawing differs from the supplied package.") }
    }
  }
  private func transferFile(_ hash: String) throws -> URL {
    guard hash.utf8.count == 64,
      hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
      throw DrawingTransferError.invalid("Invalid transfer payload identity.")
    }
    return directoryURL.appendingPathComponent("transfers", isDirectory: true).appendingPathComponent(hash + ".json")
  }

  private func retainTransferBytes(_ bytes: Data) throws -> String {
    let hash = DrawingPackageCodec.sha256(bytes), url = try transferFile(hash)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: url.path) {
      guard try readTransferBytes(hash) == bytes else { throw DrawingTransferError.conflict("Frozen transfer payload differs.") }
    } else {
      try bytes.write(to: url, options: .atomic); try synchronize(url)
      guard try readTransferBytes(hash) == bytes else { throw DrawingTransferError.invalid("Transfer write verification failed.") }
    }
    return hash
  }

  private func readTransferBytes(_ hash: String) throws -> Data {
    let url = try transferFile(hash)
    let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard size.isRegularFile == true, let count = size.fileSize,
      count <= DrawingTransferLimits.attachmentJSONBytes else { throw DrawingTransferError.limit("Stored transfer exceeds its byte limit.") }
    let bytes = try Data(contentsOf: url)
    guard DrawingPackageCodec.sha256(bytes) == hash else { throw DrawingTransferError.invalid("Stored transfer checksum mismatch.") }
    return bytes
  }

  private func packageReference(_ origin: DrawingOriginReference, db: PortraitLibraryDatabase) throws -> FrozenDrawingPackageReference? {
    guard let value = try db.scalar("SELECT value FROM state WHERE key=?", ["transfer.package." + origin.drawingID]) else { return nil }
    let reference = try db.decode(FrozenDrawingPackageReference.self, value)
    guard reference.origin == origin else { throw DrawingTransferError.conflict("Frozen drawing origin conflicts with the library.") }
    return reference
  }

  private func libraryIdentity(_ db: PortraitLibraryDatabase) throws -> UUID {
    if let value = try db.scalar("SELECT value FROM state WHERE key='library_uuid'") {
      guard let id = UUID(uuidString: value) else { throw DrawingTransferError.invalid("Library identity is invalid.") }
      return id
    }
    let id = UUID()
    try db.transaction {
      try db.setState("library_uuid", id.uuidString.lowercased())
      try db.execute("PRAGMA user_version=2")
      try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
    return id
  }

  package func validateDurableDrawing(_ drawing: SavedDrawing) throws {
    try drawing.validateIntegrity()
    if let candidate = drawing.portraitCandidate { try validateDurableCandidate(candidate); return }
    try ensureLibraryGraph()
    let db = try libraryDatabase(); try assertCurrentInputs(db, checkEvidence: false)
    let exact = try loadDrawing(drawing.id)
    guard exact == drawing else { throw DrawingTransferError.conflict("The durable drawing differs from the selected artwork.") }
    if let package = drawing.transferredPackage {
      guard let reference = try packageReference(package.origin, db: db),
        try DrawingPackageCodec.decode(readTransferBytes(reference.hash)) == package else {
        throw DrawingTransferError.invalid("The complete drawing package is not durably retained.")
      }
    }
  }

  package func exportDrawingPackage(_ drawing: SavedDrawing) throws -> Data {
    try validateDurableDrawing(drawing)
    let db = try libraryDatabase()
    if let package = drawing.transferredPackage {
      guard let reference = try packageReference(package.origin, db: db) else {
        throw DrawingTransferError.unavailable("The imported package is unavailable.")
      }
      return try readTransferBytes(reference.hash)
    }
    guard let candidate = drawing.portraitCandidate else {
      throw DrawingTransferError.unavailable("Version one drawing transfer requires a retained portrait source.")
    }
    let encoder = PortraitCandidateCoding.encoder(), record = try encoder.encode(candidate)
    let origin = DrawingOriginReference(libraryID: try libraryIdentity(db), captureID: candidate.photoID,
      resultID: candidate.id, resultRecordSHA256: DrawingPackageCodec.sha256(record), programHash: candidate.program.contentHash)
    if let reference = try packageReference(origin, db: db) {
      let bytes = try readTransferBytes(reference.hash)
      let package = try DrawingPackageCodec.decode(bytes)
      try DrawingPackageLibraryValidation.validate(package)
      return bytes
    }
    let package = try DrawingPackage(origin: origin, program: candidate.program, createdAt: candidate.createdAt,
      title: candidate.recipe.title, resultRecordJSON: record,
      source: DrawingPackageLibraryValidation.sourceAsset(candidate.sourceData),
      artistInput: .init(mediaType: "application/vnd.adaptiveplotter.portrait-raster+json",
        bytes: encoder.encode(candidate.raster), pixelWidth: candidate.raster.width, pixelHeight: candidate.raster.height),
      artist: .init(identifier: "adaptiveplotter." + candidate.recipe.style.rawValue,
        revision: candidate.producerRevision, settingsJSON: encoder.encode(candidate.recipe)),
      preview: DrawingPackageLibraryValidation.preview(candidate.program), legacyCandidateJSON: record)
    try DrawingPackageLibraryValidation.validate(package)
    let bytes = try DrawingPackageCodec.encode(package), hash = try retainTransferBytes(bytes)
    let identity = PortraitDrawingIdentity(candidateID: candidate.id, photoID: candidate.photoID)
    guard let candidateHash = try db.scalar("SELECT candidate_record FROM drawing WHERE id=? AND deleted=0", [identity.id]) else {
      throw PortraitLibraryError.missingDrawing
    }
    try db.transaction {
      try assertCurrentInputs(db, checkEvidence: false)
      try db.setState("transfer.package." + origin.drawingID,
        db.encode(FrozenDrawingPackageReference(hash: hash, origin: origin, nativeCandidateRecordSHA256: candidateHash)))
      try db.execute("PRAGMA user_version=2"); try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
    return bytes
  }

  package nonisolated static func exactTransferredTombstone(_ tombstone: PortraitArchiveTombstone, id: String) -> Bool {
    tombstone.kind == .candidate && tombstone.identity == id
      && tombstone.affectedCandidateIDs.allSatisfy { $0 == id }
  }

  private func checkedTransferTombstones(_ drawing: SavedDrawing, db: PortraitLibraryDatabase,
    restoreDeleted: Bool) throws -> [PortraitArchiveTombstone] {
    try checkedTransferTombstones(SavedDrawingSummary(drawing), db: db, restoreDeleted: restoreDeleted)
  }

  private func checkedTransferTombstones(_ drawing: SavedDrawingSummary, db: PortraitLibraryDatabase,
    restoreDeleted: Bool) throws -> [PortraitArchiveTombstone] {
    let tombstones = try db.decode([PortraitArchiveTombstone].self,
      db.scalar("SELECT value FROM state WHERE key='tombstones'") ?? "[]")
    for tombstone in tombstones where drawing.createdAt <= tombstone.createdAt {
      if Self.exactTransferredTombstone(tombstone, id: drawing.id) {
        guard restoreDeleted else {
          throw DrawingTransferError.unavailable("This drawing was deleted. Use Import Drawing Package to restore it explicitly.")
        }
      } else if (tombstone.kind == .source && tombstone.identity == drawing.sourceSHA256)
        || tombstone.affectedCandidateIDs.contains(drawing.id) {
        throw DrawingTransferError.unavailable("An older broad source deletion covers this package. Version one cannot restore it without reviewed source-history reconciliation.")
      }
    }
    return restoreDeleted ? tombstones.filter { !Self.exactTransferredTombstone($0, id: drawing.id) } : tombstones
  }

  package func importDrawingPackage(_ bytes: Data, restoreDeleted: Bool = false) throws -> SavedDrawing {
    let package = try DrawingPackageCodec.decode(bytes)
    try DrawingPackageLibraryValidation.validate(package)
    let drawing = try SavedDrawing(package: package)
    try ensureLibraryGraph()
    let db = try libraryDatabase(); try assertCurrentInputs(db, checkEvidence: false)
    let prior = try packageReference(package.origin, db: db)
    if let prior {
      guard try readTransferBytes(prior.hash) == bytes else {
        throw DrawingTransferError.conflict("Different package bytes claim the same frozen drawing origin.")
      }
      if prior.nativeCandidateRecordSHA256 != nil {
        guard let linked = try linkedDrawing(package.origin, db: db), let photo = linked.photo else {
          throw DrawingTransferError.unavailable("The originating native capture was deleted or replaced; package import cannot restore native photo history.")
        }
        return try loadDrawing(PortraitDrawingIdentity(candidateID: linked.id, photoID: photo))
      }
    }
    // A live row is an integrity commitment. Missing or malformed selected
    // payloads must propagate failure, never turn retry into an implicit repair.
    if let value = try db.scalar("SELECT reference FROM generic_drawing WHERE id=?", [drawing.id]) {
      let reference = try db.decode(SavedDrawingRecordReference.self, value)
      guard reference.id == drawing.id, reference.candidateID == nil, reference.recordSHA256 != nil else {
        throw DrawingTransferError.invalid("The retained drawing reference is invalid.")
      }
      let existing = try loadDrawing(drawing.id)
      guard existing == drawing else { throw DrawingTransferError.conflict("The imported drawing record conflicts.") }
      try validateDurableDrawing(existing)
      return existing
    }
    if prior != nil {
      let retainedTombstones = try db.decode([PortraitArchiveTombstone].self,
        db.scalar("SELECT value FROM state WHERE key='tombstones'") ?? "[]")
      guard restoreDeleted, retainedTombstones.contains(where: {
        Self.exactTransferredTombstone($0, id: drawing.id) && drawing.createdAt <= $0.createdAt
      }) else {
        throw DrawingTransferError.unavailable("The retained drawing is missing without an explicitly restorable deletion. Reconcile the library before importing it again.")
      }
    }
    let tombstones = try checkedTransferTombstones(drawing, db: db, restoreDeleted: restoreDeleted)
    let hash = try retainTransferBytes(bytes)
    let recordHash = try installMetadata(StoredDrawing(drawing), encoder: PortraitCandidateCoding.encoder())
    let reference = SavedDrawingRecordReference(id: drawing.id, candidateID: nil, recordSHA256: recordHash)
    try db.transaction {
      try assertCurrentInputs(db, checkEvidence: false)
      _ = try checkedTransferTombstones(drawing, db: db, restoreDeleted: restoreDeleted)
      try db.execute("PRAGMA user_version=2")
      try db.setState("transfer.package." + drawing.id,
        db.encode(FrozenDrawingPackageReference(hash: hash, origin: package.origin, nativeCandidateRecordSHA256: nil)))
      try db.execute("INSERT INTO generic_drawing(id,reference,summary,ordinal) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET reference=excluded.reference,summary=excluded.summary",
        [drawing.id, try db.encode(reference), try db.encode(SavedDrawingSummary(drawing)), "0"])
      if restoreDeleted { try db.setState("tombstones", db.encode(tombstones)) }
      try db.bumpRevision()
    }
    refreshCommittedLibraryGeneration()
    try validateDurableDrawing(drawing)
    return drawing
  }

  private func linkedDrawing(_ origin: DrawingOriginReference, db: PortraitLibraryDatabase) throws -> (id: String, photo: UUID?)? {
    // Summary browsing reads metadata only. Selected drawing/attachment loading
    // verifies complete immutable payloads before presenting their source bytes.
    if let value = try db.scalar("SELECT summary FROM generic_drawing WHERE id=?", [origin.drawingID]) {
      let drawing = try db.decode(SavedDrawingSummary.self, value)
      guard drawing.id == origin.drawingID, drawing.transferOrigin == origin,
        drawing.programContentHash == origin.programHash.description else {
        throw DrawingTransferError.conflict("Drawing origin differs from its retained package.")
      }
      guard (try? checkedTransferTombstones(drawing, db: db, restoreDeleted: false)) != nil else { return nil }
      return (drawing.id, nil)
    }
    guard try db.scalar("SELECT value FROM state WHERE key='library_uuid'") == origin.libraryID.uuidString.lowercased(),
      let reference = try packageReference(origin, db: db),
      let nativeHash = reference.nativeCandidateRecordSHA256 else { return nil }
    let identity = PortraitDrawingIdentity(candidateID: origin.resultID, photoID: origin.captureID)
    guard let row = try db.rows("SELECT d.candidate_record,d.program_hash FROM drawing d JOIN photo p ON p.id=d.photo_id WHERE d.id=? AND d.deleted=0 AND p.deleted=0", [identity.id]).first,
      row[0] == nativeHash, row[1] == origin.programHash.description else { return nil }
    return (origin.resultID, origin.captureID)
  }

  package func importPlotAttachment(_ bytes: Data) throws -> PlotAttachmentImportResult {
    let attachment = try PlotAttachmentCodec.decode(bytes)
    _ = try PortraitPlotAttachmentInspection.record(attachment)
    try ensureLibraryGraph()
    let db = try libraryDatabase(); try assertCurrentInputs(db, checkEvidence: false)
    let key = "transfer.attachment." + attachment.id
    let disposition: PlotAttachmentImportDisposition
    if let existing = try db.scalar("SELECT value FROM state WHERE key=?", [key]) {
      let reference = try db.decode(FrozenPlotAttachmentReference.self, existing)
      guard try readTransferBytes(reference.hash) == bytes else {
        throw DrawingTransferError.conflict("A different terminal receipt already exists for this producer archive and run.")
      }
      disposition = .alreadyPresent
    } else {
      let hash = try retainTransferBytes(bytes)
      try db.transaction {
        try assertCurrentInputs(db, checkEvidence: false)
        try db.execute("PRAGMA user_version=2")
        try db.setState(key, db.encode(FrozenPlotAttachmentReference(hash: hash, origin: attachment.origin,
          producerArchiveID: attachment.producerArchiveID, runID: attachment.runID,
          recordID: attachment.recordID, recordSHA256: attachment.recordSHA256, mediaCount: attachment.media.count)))
        try db.bumpRevision()
      }
      refreshCommittedLibraryGeneration()
      disposition = .imported
    }
    let linked = try linkedDrawing(attachment.origin, db: db)
    return PlotAttachmentImportResult(attachmentID: attachment.id, disposition: disposition,
      linkedDrawingID: linked?.id, linkedPhotoID: linked?.photo)
  }

  package func plotAttachments(for origin: DrawingOriginReference? = nil) throws -> [PlotAttachmentSummary] {
    try plotAttachmentPage(for: origin).attachments
  }

  package func plotAttachmentPage(after cursor: PlotAttachmentPageCursor? = nil, limit requested: Int = 100,
    for origin: DrawingOriginReference? = nil) throws -> PlotAttachmentPage {
    try ensureLibraryGraph()
    let db = try libraryDatabase(); try assertCurrentInputs(db, checkEvidence: false)
    let generation = try db.generation, limit = min(100, max(1, requested))
    if let cursor, cursor.generation != generation || cursor.origin != origin { throw SavedDrawingBrowserError.archiveChanged }
    var predicate = "key LIKE 'transfer.attachment.%' AND key>?"
    var values: [String?] = [cursor?.key ?? ""]
    if let origin {
      predicate += " AND json_extract(value,'$.origin.libraryID')=? AND json_extract(value,'$.origin.captureID')=? AND json_extract(value,'$.origin.resultID')=? AND json_extract(value,'$.origin.resultRecordSHA256')=?"
      values += [origin.libraryID.uuidString, origin.captureID.uuidString, origin.resultID, origin.resultRecordSHA256]
    }
    values.append(String(limit + 1))
    let rows = try db.rows("SELECT key,value FROM state WHERE " + predicate + " ORDER BY key LIMIT ?", values)
    let selected = Array(rows.prefix(limit))
    let attachments: [PlotAttachmentSummary] = try selected.map { row in
      try Task.checkCancellation()
      let ref = try db.decode(FrozenPlotAttachmentReference.self, row[1])
      guard origin == nil || origin == ref.origin else { throw DrawingTransferError.invalid("Attachment origin metadata mismatch.") }
      let id = ref.producerArchiveID.uuidString.lowercased() + ":" + ref.runID.uuidString.lowercased()
      guard row[0] == "transfer.attachment." + id else { throw DrawingTransferError.invalid("Attachment metadata identity mismatch.") }
      let linked = try linkedDrawing(ref.origin, db: db)
      return PlotAttachmentSummary(id: id, origin: ref.origin, producerArchiveID: ref.producerArchiveID,
        runID: ref.runID, recordID: ref.recordID, recordSHA256: ref.recordSHA256,
        linkedDrawingID: linked?.id, linkedPhotoID: linked?.photo, mediaCount: ref.mediaCount)
    }
    guard try db.generation == generation else { throw SavedDrawingBrowserError.archiveChanged }
    let next = rows.count > limit ? PlotAttachmentPageCursor(key: selected.last![0]!, generation: generation, origin: origin) : nil
    return PlotAttachmentPage(attachments: attachments, next: next)
  }

  package func loadPlotAttachment(_ id: String) throws -> PlotAttachment {
    try ensureLibraryGraph()
    let db = try libraryDatabase(); try assertCurrentInputs(db, checkEvidence: false)
    guard let value = try db.scalar("SELECT value FROM state WHERE key=?", ["transfer.attachment." + id]) else {
      throw DrawingTransferError.unavailable("This plot attachment is unavailable.")
    }
    let reference = try db.decode(FrozenPlotAttachmentReference.self, value)
    let attachment = try PlotAttachmentCodec.decode(readTransferBytes(reference.hash))
    guard attachment.id == id, attachment.origin == reference.origin,
      attachment.recordSHA256 == reference.recordSHA256 else {
      throw DrawingTransferError.invalid("Retained terminal attachment identity mismatch.")
    }
    _ = try PortraitPlotAttachmentInspection.record(attachment)
    return attachment
  }
}
