import Foundation
import PortraitCore

/// Domain owners validate payload schemas. The Library validates closed typed
/// dependencies and commits each bounded entity record with its assets atomically.
public struct DrawingLibraryCommitIntent: Hashable, Sendable {
  public let id: UUID
  public init(id:UUID=UUID()) { self.id=id }
}
public struct DrawingLibraryRecordKey: Hashable, Codable, Sendable {
  public let kind: String
  public let id: UUID
  public init(kind: String, id: UUID) { self.kind = kind; self.id = id }
}
public struct DrawingLibraryRecord: Codable, Sendable {
  public let kind: String
  public let id: UUID
  public let payload: Data
  public let drawings: [DrawingRef]
  public let photos: [PhotoRef]
  public let inputs: [ImageInputRef]
  public let assets: [ExchangeDigest]
  public var key: DrawingLibraryRecordKey { .init(kind:kind,id:id) }
  public init(kind: String, id: UUID, payload: Data, drawings: [DrawingRef] = [], photos: [PhotoRef] = [], inputs: [ImageInputRef] = [], assets: [ExchangeDigest] = []) {
    self.kind=kind;self.id=id;self.payload=payload;self.drawings=drawings;self.photos=photos;self.inputs=inputs;self.assets=assets
  }
}
package struct DrawingLibraryExistingRetention: Codable, Sendable {
  let metadata:LibraryExchangeMetadata
  let intent:UUID
  let request:ExchangeDigest
}
package struct DrawingLibraryDomainCommit: Codable, Sendable {
  let intent:UUID
  let request:ExchangeDigest
  let batch:DrawingLibraryRecordBatch
  let retained:[DrawingLibraryExistingRetention]
}
package struct DrawingLibraryRecordBatch: Codable, Sendable {
  let records:[DrawingLibraryRecord]
  let removing:[DrawingLibraryRecordKey]
  let photoMetadata:[DrawingLibraryPhotoMetadataUpdate]?
  let drawingRetention:[DrawingLibraryRetentionMutation]?
  init(records:[DrawingLibraryRecord],removing:[DrawingLibraryRecordKey],photoMetadata:[DrawingLibraryPhotoMetadataUpdate]=[],drawingRetention:[DrawingLibraryRetentionMutation]=[]) {
    self.records=records;self.removing=removing;self.photoMetadata=photoMetadata;self.drawingRetention=drawingRetention
  }
}

extension DrawingLibrary {
  public func record(_ key:DrawingLibraryRecordKey)throws->DrawingLibraryRecord? {
    guard let db=try commonReadDatabase(),try tableExists("domain_record",in:db) else { return nil }
    return try commonSnapshot(db) {
      guard let raw=try db.scalar("SELECT payload FROM domain_record WHERE kind=? AND id=?",[key.kind,key.id.uuidString.lowercased()]) else { return nil }
      let value=try db.decode(DrawingLibraryRecord.self,raw)
      guard value.key==key else { throw DrawingLibraryError.invalidIdentity };return value
    }
  }
  public func records(kind:String) throws -> [DrawingLibraryRecord] {
    guard let db=try commonReadDatabase(),try tableExists("domain_record",in:db) else { return [] }
    return try commonSnapshot(db) {
      try db.rows("SELECT payload FROM domain_record WHERE kind=? ORDER BY id",[kind]).map { try db.decode(DrawingLibraryRecord.self,$0[0]) }
    }
  }
  public func asset(_ digest:ExchangeDigest,maximumBytes:Int=DrawingExchangeLimits.maximumProgramBytes)throws->Data {
    guard let db=try commonReadDatabase(),try tableExists("dx_object",in:db),let raw=try db.scalar("SELECT byte_length FROM dx_object WHERE digest=?",[digest.description]),let length=UInt64(raw),length<=UInt64(max(0,maximumBytes)) else { throw DrawingLibraryError.corruptAsset(digest) }
    return try commonSnapshot(db) {
      let path="objects/sha256/"+digest.description
      return try VerifiedExchangeFiles(catalogRoot:directoryURL,inventory:[.init(path:path,storagePath:path,digest:digest,byteLength:length)]).record(digest,maximumBytes:maximumBytes)
    }
  }
  public func commitRecords(_ records:[DrawingLibraryRecord],removing:[DrawingLibraryRecordKey]=[],assets:[DrawingLibraryClosureAsset]=[],intent:DrawingLibraryCommitIntent = .init(),closure:DrawingLibraryRetainedClosure = .empty,photoMetadata:[DrawingLibraryPhotoMetadataUpdate]=[])throws {
    let catalog=try commonCatalog()
    defer { refreshOwnership() }
    let batch=DrawingLibraryRecordBatch(records:records,removing:removing,photoMetadata:photoMetadata)
    guard photoMetadata.count <= 10_000 else { throw DrawingLibraryError.invalidQuery }
    for update in photoMetadata { try catalog.validatePhotoPatch(update.patch) }
    let request=try domainRequest(batch,assets:assets+closure.assets,closureRecords:closure.records)
    if try catalog.domainReceipt(intent.id,request:request) != nil { return }
    let prepared=try packageWithAssets(nil,assets:assets+closure.assets,publicationID:intent.id,records:closure.records)
    defer { try? FileManager.default.removeItem(at:prepared.temporaryRoot) }
    let commit=DrawingLibraryDomainCommit(intent:intent.id,request:request,batch:batch,retained:[])
    _ = try catalog.publish(prepared.package,domainCommit:commit)
  }
  package func domainRequest(_ batch:DrawingLibraryRecordBatch,assets:[DrawingLibraryClosureAsset],retentionRequest:ExchangeDigest?=nil,closureRecords:[DrawingLibraryClosureRecord]=[])throws->ExchangeDigest {
    let recordCount: Int = batch.records.count + batch.removing.count
    let mutationCount: Int = (batch.photoMetadata?.count ?? 0) + (batch.drawingRetention?.count ?? 0)
    let closureCount: Int = closureRecords.count + assets.count
    let totalCount: Int = recordCount + mutationCount + closureCount
    guard totalCount <= 10_000 else { throw DrawingExchangeError.limit("Commit count") }
    var total=0
    for record in batch.records {
      guard record.payload.count<=ExchangeJSON.maximumRecordBytes,record.payload.count<=16*1024*1024-total,record.drawings.count+record.photos.count+record.inputs.count+record.assets.count<=10_000 else { throw DrawingExchangeError.limit("Commit record bytes/references") };total += record.payload.count
    }
    total=0
    for size in assets.map({$0.bytes.count})+closureRecords.map({$0.originalJSON.count}) {
      guard size<=256*1024*1024-total else { throw DrawingExchangeError.limit("Commit asset bytes") };total += size
    }
    let ordered=DrawingLibraryRecordBatch(records:batch.records.sorted { ($0.kind,$0.id.uuidString)<($1.kind,$1.id.uuidString) },removing:batch.removing.sorted { ($0.kind,$0.id.uuidString)<($1.kind,$1.id.uuidString) },photoMetadata:batch.photoMetadata ?? [],drawingRetention:batch.drawingRetention ?? [])
    let encoder=DrawingArtifactCoding.encoder()
    let object:[String:Any] = ["batch":ExchangeDigest.hash(try encoder.encode(ordered)).description,"assets":try assets.map { value -> String in
      ExchangeDigest.hash(try encoder.encode(value.descriptor)).description+":"+ExchangeDigest.hash(value.bytes).description
    }.sorted(),"retention":retentionRequest?.description ?? "none","records":closureRecords.map { value -> String in
      let ref:LibraryExchangeReference
      switch value.reference { case .drawing(let r):ref = .drawing(r);case .photo(let r):ref = .photo(r);case .input(let r):ref = .input(r) }
      return (ref.key+[ref.digest.description,ExchangeDigest.hash(value.originalJSON).description]).joined(separator:":")
    }.sorted()]
    return .hash(try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes]))
  }
  /// Constructs a normal admitted new-format publication for domain assets, or
  /// extends a prepared authored publication without changing its drawing bytes.
  package func packageWithAssets(_ original:ValidatedExchangePackage?,assets:[DrawingLibraryClosureAsset],publicationID:UUID,records:[DrawingLibraryClosureRecord]=[])throws->(package:ValidatedExchangePackage,temporaryRoot:URL) {
    let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("drawing-records-"+UUID().uuidString.lowercased(),isDirectory:true)
    try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    var success=false
    defer { if !success { try? FileManager.default.removeItem(at:temporary) } }
    let bag=temporary.appendingPathComponent("bag",isDirectory:true)
    if let original { try DrawingExchangeCarrier.preserveDirectory(original.files,to:bag) }
    else { try FileManager.default.createDirectory(at:bag,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]) }
    var descriptors=Dictionary((original?.index.known?.assets ?? []).map{($0.asset.object,$0)},uniquingKeysWith:{$0 == $1 ? $0 : $1})
    var total=0
    guard assets.count<=10_000 else { throw DrawingExchangeError.limit("Domain assets") }
    for value in assets {
      guard value.bytes.count<=256*1024*1024-total else { throw DrawingExchangeError.limit("Domain asset bytes") };total += value.bytes.count
      try value.descriptor.asset.validate(value.bytes,maximumBytes:DrawingExchangeLimits.maximumProgramBytes)
      if let old=descriptors[value.descriptor.asset.object],old != value.descriptor { throw DrawingExchangeError.malformed("Asset descriptor conflict") }
      descriptors[value.descriptor.asset.object]=value.descriptor
      let target=bag.appendingPathComponent("data/objects/sha256/"+value.descriptor.asset.object.description)
      try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
      try value.bytes.write(to:target,options:.atomic)
    }
    guard records.count+assets.count<=10_000 else { throw DrawingExchangeError.limit("Domain closure") }
    for record in records {
      let path:String,digest:ExchangeDigest
      switch record.reference {
      case .drawing(let r):path="data/drawings/"+r.issuer.uuidString.lowercased()+"/"+r.revision.uuidString.lowercased()+"/drawing.json";digest=r.digest
      case .photo(let r):path="data/photos/"+r.issuer.uuidString.lowercased()+"/"+r.revision.uuidString.lowercased()+"/photo.json";digest=r.digest
      case .input(let r):path="data/inputs/"+r.issuer.uuidString.lowercased()+"/"+r.revision.uuidString.lowercased()+"/input.json";digest=r.digest
      }
      guard record.originalJSON.count<=ExchangeJSON.maximumRecordBytes,record.originalJSON.count<=256*1024*1024-total else { throw DrawingExchangeError.limit("Domain closure bytes") };total += record.originalJSON.count
      _ = try ExchangeJSON.validate(record.originalJSON)
      guard ExchangeDigest.hash(record.originalJSON)==digest else { throw DrawingExchangeError.digestMismatch("Domain exact record") }
      let target=bag.appendingPathComponent(path)
      try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
      if FileManager.default.fileExists(atPath:target.path),ExchangeDigest.hash(try Data(contentsOf:target)) != digest { throw DrawingExchangeError.digestMismatch("Domain record collision") }
      try record.originalJSON.write(to:target,options:.atomic)
    }
    var index:[String:Any]
    if let original { index=try ExchangeJSON.validate(original.index.originalJSON) }
    else { index=["profile":"adaptiveplotter.exchange/1","requiredFeatures":[String](),"kind":"feedback","roots":[String](),"attempts":[String](),"assessments":[String](),"includedAsOf":ISO8601DateFormatter().string(from:Date())] }
    index["localPublication"] = publicationID.uuidString.lowercased()
    index["assets"]=try JSONSerialization.jsonObject(with:DrawingArtifactCoding.encoder().encode(descriptors.values.sorted{$0.asset.object.description<$1.asset.object.description}))
    let data=bag.appendingPathComponent("data",isDirectory:true)
    try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
    try JSONSerialization.data(withJSONObject:index,options:[.sortedKeys,.withoutEscapingSlashes]).write(to:data.appendingPathComponent("exchange.json"),options:.atomic)
    let files=FileManager.default.enumerator(at:data,includingPropertiesForKeys:[.isRegularFileKey])!
    var entries:[(String,ExchangeDigest)]=[]
    let bagComponents=bag.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    for case let url as URL in files {
      if try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true {
        let entryComponents=url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard entryComponents.count>bagComponents.count,entryComponents.starts(with:bagComponents) else { throw DrawingExchangeError.malformed("Manifest entry outside private bag") }
        let relativeComponents=Array(entryComponents.dropFirst(bagComponents.count))
        guard relativeComponents.first=="data",relativeComponents.count>1 else { throw DrawingExchangeError.malformed("Manifest entry outside data") }
        let path=relativeComponents.joined(separator:"/")
        let bytes=try Data(contentsOf:url);entries.append((path,.hash(bytes)))
      }
    }
    let bagit=Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    let manifest=Data(entries.sorted{$0.0<$1.0}.map{$0.1.description+"  "+$0.0+"\n"}.joined().utf8)
    try bagit.write(to:bag.appendingPathComponent("bagit.txt"),options:.atomic)
    try manifest.write(to:bag.appendingPathComponent("manifest-sha256.txt"),options:.atomic)
    try Data((ExchangeDigest.hash(bagit).description+"  bagit.txt\n"+ExchangeDigest.hash(manifest).description+"  manifest-sha256.txt\n").utf8).write(to:bag.appendingPathComponent("tagmanifest-sha256.txt"),options:.atomic)
    let staged=try DrawingExchangeCarrier.stageDirectory(bag,stagingParent:temporary)
    let admitted=try ExchangeAdmission.validate(staged,producerValidators:producerValidators)
    success=true;return(admitted,temporary)
  }
}

extension LibraryExchangeCatalog {
  package func domainReceipt(_ intent:UUID,request:ExchangeDigest)throws->UUID? {
    guard let row=try database.rows("SELECT request_digest,transaction_id FROM domain_commit WHERE id=?",[intent.uuidString.lowercased()]).first else { return nil }
    let expected=try ExchangeDigest(row[0]!)
    guard expected==request else { throw DrawingLibraryError.recordIntentConflict(intent,expected:expected,actual:request) }
    guard let transaction=row[1].flatMap(UUID.init(uuidString:)) else { throw DrawingLibraryError.invalidIdentity };return transaction
  }
  package func applyDomainCommit(_ commit:DrawingLibraryDomainCommit,transaction:UUID)throws {
    if try domainReceipt(commit.intent,request:commit.request) != nil { return }
    try applyDomainBatch(commit.batch)
    for update in commit.batch.photoMetadata ?? [] { try applyPhotoMetadata(update) }
    for update in commit.batch.drawingRetention ?? [] { try applyRetentionMutation(update) }
    for retained in commit.retained {
      let metadata=retained.metadata,intent=retained.intent,request=retained.request
      guard case .drawing(let ref)=metadata.reference else { throw DrawingLibraryError.invalidIdentity }
      _ = try lookup(metadata.reference)
      if let prior=try retentionIntent(intent,requestDigest:request),prior != ref { throw DrawingLibraryError.staleSelection }
      try writeMetadata(metadata)
      try database.execute("INSERT OR IGNORE INTO dx_retention_intent(id,issuer,revision,digest,request_digest) VALUES(?,?,?,?,?)",[intent.uuidString.lowercased(),ref.issuer.uuidString.lowercased(),ref.revision.uuidString.lowercased(),ref.digest.description,request.description])
    }
    try database.execute("INSERT INTO domain_commit(id,request_digest,transaction_id) VALUES(?,?,?)",[commit.intent.uuidString.lowercased(),commit.request.description,transaction.uuidString.lowercased()])
  }
  /// Reject malformed or dangling domain records before creating a durable
  /// journal. The same checks run again inside the final transaction.
  package func validateDomainBatch(_ batch:DrawingLibraryRecordBatch,included:Set<LibraryExchangeReference>,objects:Set<ExchangeDigest>)throws {
    let recordCount: Int = batch.records.count + batch.removing.count
    let mutationCount: Int = (batch.photoMetadata?.count ?? 0) + (batch.drawingRetention?.count ?? 0)
    let totalCount: Int = recordCount + mutationCount
    guard totalCount <= 10_000,Set(batch.records.map(\.key)).count==batch.records.count,Set(batch.removing).count==batch.removing.count,Set(batch.records.map(\.key)).isDisjoint(with:Set(batch.removing)) else { throw DrawingExchangeError.limit("Domain records") }
    var bytes=0
    for record in batch.records {
      guard !record.kind.isEmpty,record.kind.utf8.count<=256,record.payload.count<=ExchangeJSON.maximumRecordBytes,record.payload.count<=16*1024*1024-bytes,record.drawings.count+record.photos.count+record.inputs.count+record.assets.count<=10_000 else { throw DrawingExchangeError.limit("Domain record bytes") };bytes += record.payload.count
      _ = try ExchangeJSON.validate(record.payload)
      let refs:[LibraryExchangeReference]=record.drawings.map{.drawing($0)}+record.photos.map{.photo($0)}+record.inputs.map{.input($0)}
      for ref in refs where !included.contains(ref) { _ = try lookup(ref) }
      for digest in record.assets where !objects.contains(digest) {
        guard try database.scalar("SELECT digest FROM dx_object WHERE digest=?",[digest.description]) != nil else { throw DrawingLibraryError.corruptAsset(digest) }
      }
    }
    for update in batch.photoMetadata ?? [] {
      try validatePhotoPatch(update.patch)
      if !included.contains(.photo(update.reference)) { _ = try lookup(.photo(update.reference)) }
    }
    for update in batch.drawingRetention ?? [] {
      if let reason = update.reason { guard !reason.isEmpty, reason.utf8.count <= 4096 else { throw DrawingLibraryError.invalidQuery } }
      _ = try lookup(.drawing(update.reference))
    }
    for key in batch.removing { guard !key.kind.isEmpty,key.kind.utf8.count<=256 else { throw DrawingLibraryError.invalidIdentity } }
  }
  package func applyDomainBatch(_ batch:DrawingLibraryRecordBatch)throws {
    try validateDomainBatch(batch,included:[],objects:[])
    var bytes=0
    for record in batch.records {
      guard !record.kind.isEmpty,record.kind.utf8.count<=256,record.payload.count<=ExchangeJSON.maximumRecordBytes, record.payload.count<=16*1024*1024-bytes else { throw DrawingExchangeError.limit("Domain record bytes") };bytes += record.payload.count
      _ = try ExchangeJSON.validate(record.payload)
      let refs:[LibraryExchangeReference]=record.drawings.map{.drawing($0)}+record.photos.map{.photo($0)}+record.inputs.map{.input($0)}
      for ref in refs { _ = try lookup(ref) }
      for digest in record.assets { guard try database.scalar("SELECT digest FROM dx_object WHERE digest=?",[digest.description]) != nil else { throw DrawingLibraryError.corruptAsset(digest) } }
      let id=record.id.uuidString.lowercased()
      try database.execute("INSERT INTO domain_record(kind,id,payload) VALUES(?,?,?) ON CONFLICT(kind,id) DO UPDATE SET payload=excluded.payload",[record.kind,id,try database.encode(record)])
      try database.execute("DELETE FROM domain_reference WHERE kind=? AND id=?",[record.kind,id])
      for ref in refs { try database.execute("INSERT OR IGNORE INTO domain_reference(kind,id,target_kind,namespace,identity,digest) VALUES(?,?,?,?,?,?)",[record.kind,id]+ref.key.map(Optional.some)+[ref.digest.description]) }
      try database.execute("DELETE FROM domain_asset WHERE kind=? AND id=?",[record.kind,id])
      for digest in Set(record.assets) { try database.execute("INSERT INTO domain_asset(kind,id,digest) VALUES(?,?,?)",[record.kind,id,digest.description]) }
    }
    for key in batch.removing { try database.execute("DELETE FROM domain_record WHERE kind=? AND id=?",[key.kind,key.id.uuidString.lowercased()]) }
  }
}
