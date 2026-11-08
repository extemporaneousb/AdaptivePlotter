import Foundation
import PortraitCore

public struct DrawingLibraryClosureAsset: Sendable {
  public let descriptor: ExchangeAssetDescriptor
  public let bytes: Data
  public init(descriptor: ExchangeAssetDescriptor, bytes: Data) { self.descriptor = descriptor; self.bytes = bytes }
}
public struct DrawingLibraryClosureRecord: Sendable {
  public enum Reference: Sendable { case drawing(DrawingRef), photo(PhotoRef), input(ImageInputRef) }
  public let reference: Reference
  public let originalJSON: Data
  public init(reference: Reference, originalJSON: Data) { self.reference = reference; self.originalJSON = originalJSON }
}
/// Explicit bounded authored dependencies. A bound imported drawing additionally
/// supplies its admitted original publication, preserving that index context.
public struct DrawingLibraryRetainedClosure: Sendable {
  public let assets: [DrawingLibraryClosureAsset]
  public let records: [DrawingLibraryClosureRecord]
  public let publication: ValidatedExchangePackage?
  public static let empty = DrawingLibraryRetainedClosure()
  public init(assets: [DrawingLibraryClosureAsset] = [], records: [DrawingLibraryClosureRecord] = [], publication: ValidatedExchangePackage? = nil) {
    self.assets = assets; self.records = records; self.publication = publication
  }
}
/// Local explicit-selection intent, distinct from a wire revision identity.
/// Reuse for retries; construct a new value for a new selection, even at equal geometry.
public struct DrawingLibraryRetentionIntent: Hashable, Sendable {
  public let id: UUID
  public init(id: UUID = UUID()) { self.id = id }
}
public struct DrawingLibraryRetention: Sendable {
  public let reference: DrawingRef
  public let wasAlreadyRetained: Bool
}

public struct DrawingLibraryPreparedRetention: Sendable {
  public let drawing: Drawing
  public let reference: DrawingRef
  package let token: UUID
  package let owner: UUID
  package let request: ExchangeDigest
}
package struct DrawingLibraryPendingRetention {
  let drawing: Drawing
  let reference: DrawingRef
  let requestDigest: ExchangeDigest
  let intent: UUID
  let metadata: LibraryExchangeMetadata
  let attachment: DrawingLibraryPublicationAttachment?
  let publication: ValidatedExchangePackage?
  let temporaryRoot: URL?
  let alreadyRetained: Bool
}

extension DrawingLibrary {
  public func retain(_ drawing: Drawing, title: String? = nil, reason: String,
    closure: DrawingLibraryRetainedClosure = .empty, intent: DrawingLibraryRetentionIntent = .init()) throws -> DrawingLibraryRetention {
    let prepared = try prepareRetention(drawing,title:title,reason:reason,closure:closure,intent:intent)
    return try commitRetention(prepared)
  }
  public func prepareRetention(_ drawing:Drawing,title:String?=nil,reason:String,
    closure:DrawingLibraryRetainedClosure = .empty,intent:DrawingLibraryRetentionIntent = .init())throws->DrawingLibraryPreparedRetention {
    guard !reason.isEmpty,reason.utf8.count<=4096,title?.utf8.count ?? 0<=16_384 else { throw DrawingExchangeError.limit("Retention metadata") }
    guard !closed else { throw DrawingLibraryError.closed }
    let db=try commonReadDatabase()
    let request=try retentionRequestDigest(drawing,closure:closure)
    if let prior=pendingRetentions[intent.id] {
      guard prior.requestDigest==request else { throw DrawingLibraryError.retentionIntentConflict(intent.id,expected:prior.requestDigest,actual:request) }
      return .init(drawing:prior.drawing,reference:prior.reference,token:intent.id,owner:ownerID,request:request)
    }
    if let prior=try preparedIntent(intent.id,requestDigest:request,database:db) {
      let metadata=try preparedMetadata(prior,database:db) ?? .init(reference:.drawing(prior))
      if metadata.tombstoned { throw DrawingLibraryError.deleted(prior) }
      pendingRetentions[intent.id] = .init(drawing:try self.drawing(prior),reference:prior,requestDigest:request,intent:intent.id,metadata:metadata,attachment:nil,publication:nil,temporaryRoot:nil,alreadyRetained:true)
      return .init(drawing:try self.drawing(prior),reference:prior,token:intent.id,owner:ownerID,request:request)
    }
    guard pendingRetentions.count<128 else { throw DrawingExchangeError.limit("Pending selections") }
    let issuer=try db.flatMap { try assignedLibraryIdentity($0) } ?? ownerID
    let ref:DrawingRef, publication:ValidatedExchangePackage?, root:URL?, attachment:DrawingLibraryPublicationAttachment?, already:Bool
    let boundDrawing:Drawing
    var metadata:LibraryExchangeMetadata
    if let bound=drawing.reference,let db,try tableExists("dx_record",in:db),let actual=try db.scalar("SELECT digest FROM dx_record WHERE kind='drawing' AND namespace=? AND identity=?",[bound.issuer.uuidString.lowercased(),bound.revision.uuidString.lowercased()]) {
      guard actual==bound.digest.description else { throw DrawingLibraryError.referenceConflict(bound,actual:try ExchangeDigest(actual)) }
      boundDrawing = try self.drawing(bound)
      ref=bound;publication=nil;root=nil;attachment=nil;already=true
      metadata=try preparedMetadata(ref,database:db) ?? .init(reference:.drawing(ref))
      if metadata.tombstoned { throw DrawingLibraryError.deleted(ref) }
    } else {
      let frozen:FrozenDrawingRecord
      if let bound=drawing.reference {
        guard let supplied=closure.publication,case .materialized(let value)?=supplied.drawings[bound],value.drawing.program==drawing.program else { throw DrawingLibraryError.unavailable("Bound drawing needs its admitted original publication") }
        frozen=value;publication=supplied;root=nil
      } else {
        frozen=try DrawingExchangeCodec.freeze(drawing,identity:.init(issuer:issuer),createdAt:Date())
        let prepared=try preparePublication(frozen,closure:closure,database:db)
        publication=prepared.package;root=prepared.temporaryRoot
      }
      boundDrawing=frozen.drawing
      ref=frozen.reference;already=false
      metadata = .init(reference:.drawing(ref),title:title)
      attachment = .init(libraryUUID:issuer,intent:intent.id,requestDigest:request,summary:.init(frozen,createdAt:Date()))
    }
    if !metadata.retentionReasons.contains(reason) { metadata.retentionReasons.append(reason) }
    pendingRetentions[intent.id] = .init(drawing:boundDrawing,reference:ref,requestDigest:request,intent:intent.id,metadata:metadata,attachment:attachment,publication:publication,temporaryRoot:root,alreadyRetained:already)
    return .init(drawing:boundDrawing,reference:ref,token:intent.id,owner:ownerID,request:request)
  }
  package func preparedIntent(_ id:UUID,requestDigest:ExchangeDigest,database:DrawingLibraryDatabase?)throws->DrawingRef? {
    guard let db=database,try tableExists("dx_retention_intent",in:db),let row=try db.rows("SELECT issuer,revision,digest,request_digest FROM dx_retention_intent WHERE id=?",[id.uuidString.lowercased()]).first else { return nil }
    let expected=try ExchangeDigest(row[3]!)
    guard expected==requestDigest else { throw DrawingLibraryError.retentionIntentConflict(id,expected:expected,actual:requestDigest) }
    guard let issuer=row[0].flatMap(UUID.init(uuidString:)),let revision=row[1].flatMap(UUID.init(uuidString:)),let digest=row[2] else { throw DrawingLibraryError.invalidIdentity }
    return .init(issuer:issuer,revision:revision,digest:try ExchangeDigest(digest))
  }
  package func preparedMetadata(_ ref:DrawingRef,database:DrawingLibraryDatabase?)throws->LibraryExchangeMetadata? {
    guard let db=database,try tableExists("dx_metadata",in:db),let raw=try db.scalar("SELECT payload FROM dx_metadata WHERE kind='drawing' AND namespace=? AND identity=?",[ref.issuer.uuidString.lowercased(),ref.revision.uuidString.lowercased()]) else { return nil }
    let value=try db.decode(LibraryExchangeMetadata.self,raw)
    guard value.reference == .drawing(ref) else { throw DrawingLibraryError.invalidIdentity };return value
  }
  public func commitRetention(_ prepared:DrawingLibraryPreparedRetention,records:[DrawingLibraryRecord]=[],assets:[DrawingLibraryClosureAsset]=[])throws->DrawingLibraryRetention {
    try commitRetentions([prepared],records:records,assets:assets)[0]
  }
  /// Publishes all selected revisions, typed metadata and assets in one journal
  /// and one SQL transaction. The prepared values remain retryable on failure.
  public func commitRetentions(_ prepared:[DrawingLibraryPreparedRetention],records:[DrawingLibraryRecord]=[],assets:[DrawingLibraryClosureAsset]=[],intent:DrawingLibraryCommitIntent?=nil)throws->[DrawingLibraryRetention] {
    guard !prepared.isEmpty,prepared.count<=128,Set(prepared.map(\.token)).count==prepared.count,Set(prepared.map(\.reference)).count==prepared.count,prepared.allSatisfy({$0.owner==ownerID}) else { throw DrawingLibraryError.staleSelection }
    let catalog=try commonCatalog()
    defer { refreshOwnership() }
    let id=intent?.id ?? prepared.last!.token
    let bindings=prepared.map { value in [value.reference.issuer.uuidString.lowercased(),value.reference.revision.uuidString.lowercased(),value.reference.digest.description,value.token.uuidString.lowercased(),value.request.description].joined(separator:":") }.sorted()
    let retentionRequest=ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(bindings))
    let batch=DrawingLibraryRecordBatch(records:records,removing:[])
    let request=try domainRequest(batch,assets:assets,retentionRequest:retentionRequest)
    if try catalog.domainReceipt(id,request:request) != nil {
      for value in prepared {
        guard try catalog.retentionIntent(value.token,requestDigest:value.request)==value.reference else { throw DrawingLibraryError.staleSelection }
        discardPending(value.token)
      }
      return prepared.map{.init(reference:$0.reference,wasAlreadyRetained:true)}
    }
    var pending:[DrawingLibraryPendingRetention]=[]
    for value in prepared {
      guard let selected=pendingRetentions[value.token],selected.reference==value.reference,selected.requestDigest==value.request else { throw DrawingLibraryError.staleSelection }
      pending.append(selected)
    }
    var retained:[DrawingLibraryExistingRetention]=[]
    for selected in pending where selected.publication == nil {
      var metadata=try catalog.metadata(.drawing(selected.reference)) ?? .init(reference:.drawing(selected.reference))
      if metadata.tombstoned { throw DrawingLibraryError.deleted(selected.reference) }
      for reason in selected.metadata.retentionReasons where !metadata.retentionReasons.contains(reason) { metadata.retentionReasons.append(reason) }
      retained.append(.init(metadata:metadata,intent:selected.intent,request:selected.requestDigest))
    }
    let commit=DrawingLibraryDomainCommit(intent:id,request:request,batch:batch,retained:retained)
    let publications=pending.compactMap(\.publication)
    let roots=pending.filter{$0.publication != nil}.map(\.reference)
    let publication=try prepareBatchPublication(publications,roots:roots,assets:assets,publicationID:id)
    defer { if let root=publication.temporaryRoot { try? FileManager.default.removeItem(at:root) } }
    _ = try catalog.publish(publication.package,metadata:pending.filter{$0.publication != nil}.map(\.metadata),attachments:pending.compactMap(\.attachment),domainCommit:commit)
    for value in prepared { discardPending(value.token) }
    return pending.map{.init(reference:$0.reference,wasAlreadyRetained:$0.alreadyRetained)}
  }
  package func discardPending(_ token:UUID) {
    if let pending=pendingRetentions.removeValue(forKey:token),let root=pending.temporaryRoot { try? FileManager.default.removeItem(at:root) }
  }
  public func delete(_ ref:DrawingRef)throws {
    let catalog=try commonCatalog()
    defer { refreshOwnership() }
    var metadata=try catalog.metadata(.drawing(ref)) ?? .init(reference:.drawing(ref))
    metadata.tombstoned=true
    try catalog.updateMetadata(metadata)
    evictSelectedDrawing(ref)
  }
  public func rename(_ ref: DrawingRef, title: String?) throws {
    guard title?.utf8.count ?? 0 <= 16_384 else { throw DrawingExchangeError.limit("Drawing title") }
    let catalog = try commonCatalog()
    defer { refreshOwnership() }
    var metadata = try preparedMetadata(ref,database:catalog.database) ?? .init(reference: .drawing(ref))
    if metadata.tombstoned { throw DrawingLibraryError.deleted(ref) }
    metadata.title = title
    try catalog.updateMetadata(metadata)
  }
}

extension DrawingLibraryRetainedClosure {
  public init(photo:FrozenPhotoRecord) {
    self.init(assets:photo.assets.map{.init(descriptor:$0.descriptor,bytes:$0.bytes)},records:[.init(reference:.photo(photo.reference),originalJSON:photo.record.originalJSON)])
  }
  public init(input:FrozenImageInputRecord) {
    self.init(assets:input.assets.map{.init(descriptor:$0.descriptor,bytes:$0.bytes)},records:[.init(reference:.photo(input.photo.reference),originalJSON:input.photo.record.originalJSON),.init(reference:.input(input.reference),originalJSON:input.record.originalJSON)])
  }
}
