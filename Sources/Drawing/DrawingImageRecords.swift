import Foundation

public struct DrawingImageAsset: Sendable {
  public let descriptor:ExchangeAssetDescriptor
  public let bytes:Data
  public init(descriptor:ExchangeAssetDescriptor,bytes:Data)throws {
    try descriptor.asset.validate(bytes,maximumBytes:DrawingExchangeLimits.maximumProgramBytes)
    self.descriptor=descriptor;self.bytes=bytes
  }
  public static func gray8(_ bytes:Data,width:Int,height:Int)throws->DrawingImageAsset {
    let layout=try ExchangeRasterLayout(width:width,height:height,bytesPerPixel:1,rowStride:width)
    try layout.validate(bytes)
    let asset=try ExchangeAsset(bytes:bytes,mediaType:"application/octet-stream",encoding:"raw-gray8")
    return try .init(descriptor:.init(asset:asset,dimensions:.init(width:width,height:height),pixelLayout:layout),bytes:bytes)
  }
}
public enum DrawingImageDatedFact: Codable, Hashable, Sendable {
  case known(ExchangeTimestamp,provenance:String)
  case unknown(provenance:String)
}
public struct FrozenPhotoRecord: Sendable {
  public let record:ExchangePhotoRecord
  public let assets:[DrawingImageAsset]
  public var reference:PhotoRef { record.reference }
  public var acquired: DrawingImageDatedFact? { try? DrawingImageRecords.datedFact(record.originalJSON, key: "acquired") }
  public var imported: DrawingImageDatedFact? { try? DrawingImageRecords.datedFact(record.originalJSON, key: "imported") }
}
public struct FrozenImageInputRecord: Sendable {
  public let record:ExchangeImageInputRecord
  public let photo:FrozenPhotoRecord
  public let assets:[DrawingImageAsset]
  public var reference:ImageInputRef { record.reference }
}
public enum DrawingInputMask: Sendable { case none, present(DrawingImageAsset) }
public struct DrawingImageOperation: Sendable {
  public let kind:String
  public let parametersJSON:Data
  public init(kind:String,parametersJSON:Data)throws {
    guard !kind.isEmpty else { throw DrawingExchangeError.malformed("Preparation operation") }
    _ = try ExchangeJSON.validate(parametersJSON);self.kind=kind;self.parametersJSON=parametersJSON
  }
}
/// Pure current-format factories. The caller supplies observed preparation facts;
/// unknown transforms cannot be replaced by an invented identity transform.
public enum DrawingImageRecords {
  /// Reuses original wire records and the carrier's bounded, sealed asset checks.
  /// Header validation of encoded sources does not establish decoded pixels.
  public static func admitPhoto(_ reference: PhotoRef, files: VerifiedExchangeFiles) throws -> FrozenPhotoRecord {
    try admitPhoto(reference, scopedFiles: files.scoped(maximumMaterializedBytes: files.limits.maximumMaterializedBytes))
  }
  private static func admitPhoto(_ reference: PhotoRef, scopedFiles files: VerifiedExchangeFiles) throws -> FrozenPhotoRecord {
    let index = try supportedSourceIndex(files)
    let path = "data/photos/" + reference.issuer.uuidString.lowercased() + "/" + reference.revision.uuidString.lowercased() + "/photo.json"
    guard files.entries[path]?.digest == reference.digest else { throw DrawingExchangeError.digestMismatch("Photo path") }
    let original = try ExchangeJSON.validate(files.record(at: path))
    guard try DrawingImageAdmission.features(original).isEmpty else { throw DrawingExchangeError.unsupportedProfile("Unsupported source required features") }
    let descriptors = try sourceDescriptors(index)
    let admitted = try DrawingImageAdmission.photo(reference, files: files, assetDescriptors: descriptors)
    let record = ExchangePhotoRecord(originalJSON: admitted.originalJSON, reference: admitted.reference,
      original: admitted.original, width: admitted.width, height: admitted.height,
      supportedSemantics: index.requiredFeatures.isEmpty && admitted.supportedSemantics)
    return .init(record: record, assets: try assets(in: [record.originalJSON], files: files, descriptors: descriptors))
  }
  public static func admitInput(_ reference: ImageInputRef, files: VerifiedExchangeFiles) throws -> FrozenImageInputRecord {
    let files = files.scoped(maximumMaterializedBytes: files.limits.maximumMaterializedBytes)
    let index = try supportedSourceIndex(files)
    let path = "data/inputs/" + reference.issuer.uuidString.lowercased() + "/" + reference.revision.uuidString.lowercased() + "/input.json"
    guard files.entries[path]?.digest == reference.digest else { throw DrawingExchangeError.digestMismatch("Input path") }
    let original = try ExchangeJSON.validate(files.record(at: path))
    guard try DrawingImageAdmission.features(original).isEmpty else { throw DrawingExchangeError.unsupportedProfile("Unsupported source required features") }
    let descriptors = try sourceDescriptors(index)
    let admitted = try DrawingImageAdmission.input(reference, files: files, assetDescriptors: descriptors)
    let photo = try admitPhoto(admitted.photo, scopedFiles: files)
    let record = ExchangeImageInputRecord(originalJSON: admitted.originalJSON, reference: admitted.reference,
      photo: admitted.photo, raster: admitted.raster, mask: admitted.mask, sourceToInput: admitted.sourceToInput,
      inputToField: admitted.inputToField, supportedSemantics: index.requiredFeatures.isEmpty && admitted.supportedSemantics)
    return .init(record: record, photo: photo, assets: try assets(in: [record.originalJSON, photo.record.originalJSON], files: files, descriptors: descriptors))
  }
  static func datedFact(_ bytes: Data, key: String) throws -> DrawingImageDatedFact {
    let object = try ExchangeJSON.validate(bytes)
    guard (object["requiredFeatures"] as? [String])?.isEmpty == true else { throw DrawingExchangeError.malformed("Unsupported dated context") }
    guard let fact = object[key] as? [String: Any], let provenance = fact["provenance"] as? String, !provenance.isEmpty else { throw DrawingExchangeError.malformed("Dated fact") }
    switch fact["state"] as? String {
    case "known": return .known(try DrawingImageAdmission.decode(fact["time"], as: ExchangeTimestamp.self), provenance: provenance)
    case "unknown": return .unknown(provenance: provenance)
    default: throw DrawingExchangeError.malformed("Dated fact state")
    }
  }
  private static func supportedSourceIndex(_ files: VerifiedExchangeFiles) throws -> ExchangeIndex {
    let index = try ExchangeIndex(originalJSON: files.record(at: "data/exchange.json"))
    guard index.requiredFeatures.isEmpty, ["drawing", "result", "feedback"].contains(index.kind) else {
      throw DrawingExchangeError.unsupportedProfile("Unsupported source publication context")
    }
    return index
  }
  private static func sourceDescriptors(_ index: ExchangeIndex) throws -> [ExchangeDigest: ExchangeAssetDescriptor] {
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    for value in index.assets {
      if let prior = descriptors[value.asset.object], prior != value { throw DrawingExchangeError.malformed("Conflicting source descriptors") }
      descriptors[value.asset.object] = value
    }
    return descriptors
  }
  private static func assets(in records: [Data], files: VerifiedExchangeFiles, descriptors: [ExchangeDigest: ExchangeAssetDescriptor]) throws -> [DrawingImageAsset] {
    var selected: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    func include(_ raw: Any?) throws {
      guard let raw else { return }
      let inline = try DrawingImageAdmission.decode(raw, as: ExchangeAssetDescriptor.self)
      let full = descriptors[inline.asset.object] ?? inline
      guard inline.asset == full.asset else { throw DrawingExchangeError.malformed("Conflicting asset descriptor") }
      if let prior = selected[full.asset.object], prior != full { throw DrawingExchangeError.malformed("Conflicting asset descriptors") }
      selected[full.asset.object] = full
    }
    for record in records {
      let json = try ExchangeJSON.validate(record)
      switch json["profile"] as? String {
      case "adaptiveplotter.photo/1":
        try include(json["original"]); try include(json["captureFacts"])
      case "adaptiveplotter.image-input/1":
        try include(json["raster"])
        if let mask = json["mask"] as? [String: Any], mask["state"] as? String == "present" { try include(mask["asset"]) }
        for operation in json["operations"] as? [[String: Any]] ?? [] { try include(operation["parameters"]) }
        if let preparation = json["preparation"] as? [String: Any], let raw = preparation["record"] as? String {
          let digest = try ExchangeDigest(raw)
          guard let descriptor = descriptors[digest] else { throw DrawingExchangeError.malformed("Preparation descriptor") }
          selected[digest] = descriptor
        }
      default: throw DrawingExchangeError.unsupportedProfile("Unsupported source profile")
      }
    }
    return try selected.values.sorted { $0.asset.object.description < $1.asset.object.description }.map {
      return try .init(descriptor: $0, bytes: files.record($0.asset.object, maximumBytes: DrawingExchangeLimits.maximumProgramBytes))
    }
  }
  public static func photo(identity:ExchangeIdentity,original:DrawingImageAsset,width:Int,height:Int,
    acquired:DrawingImageDatedFact,imported:DrawingImageDatedFact,captureFactsJSON:Data?=nil)throws->FrozenPhotoRecord {
    var assets=[original]
    var object:[String:Any] = ["profile":"adaptiveplotter.photo/1","requiredFeatures":[String](),"ref":try json(identity),"original":try json(original.descriptor),"dimensions":["width":width,"height":height],"acquired":try dated(acquired),"imported":try dated(imported)]
    if let facts=captureFactsJSON {
      _ = try ExchangeJSON.validate(facts)
      let asset=try DrawingImageAsset(descriptor:.init(asset:ExchangeAsset(bytes:facts,mediaType:"application/json",encoding:"utf8-json")),bytes:facts)
      object["captureFacts"]=try json(asset.descriptor.asset);assets.append(asset)
    }
    let bytes=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes])
    let reference=PhotoRef(issuer:identity.issuer,revision:identity.revision,digest:.hash(bytes))
    var objects=Dictionary(assets.map{($0.descriptor.asset.object,$0.bytes)},uniquingKeysWith:{$1});objects[reference.digest]=bytes
    let descriptors=Dictionary(assets.map{($0.descriptor.asset.object,$0.descriptor)},uniquingKeysWith:{$1})
    let record=try DrawingImageAdmission.photo(reference,objects:objects,assetDescriptors:descriptors)
    return .init(record:record,assets:assets)
  }
  public static func input(identity:ExchangeIdentity,photo:FrozenPhotoRecord,raster:DrawingImageAsset,
    width:Int,height:Int,orientation:String,sourceToInput:ExchangeTransform,inputToField:ExchangeTransform,
    mask:DrawingInputMask,operations:[DrawingImageOperation],preparation:DrawingProducerReceipt)throws->FrozenImageInputRecord {
    var assets=photo.assets+[raster]
    var maskJSON:[String:Any] = ["state":"none"]
    if case .present(let value)=mask { assets.append(value);maskJSON=["state":"present","asset":try json(value.descriptor)] }
    var operationJSON:[[String:Any]]=[]
    for operation in operations {
      let value=try DrawingImageAsset(descriptor:.init(asset:ExchangeAsset(bytes:operation.parametersJSON,mediaType:"application/json",encoding:"utf8-json")),bytes:operation.parametersJSON)
      assets.append(value);operationJSON.append(["kind":operation.kind,"parameters":try json(value.descriptor.asset)])
    }
    assets.append(try .init(descriptor:.init(asset:ExchangeAsset(bytes:preparation.originalJSON,mediaType:"application/json",encoding:"utf8-json")),bytes:preparation.originalJSON))
    let object:[String:Any] = ["profile":"adaptiveplotter.image-input/1","requiredFeatures":[String](),"ref":try json(identity),"photo":try json(photo.reference),"raster":try json(raster.descriptor),"pixelBasis":["orientation":orientation,"origin":"top-left","xAxis":"right","yAxis":"down","pixelEdges":"integer","pixelCenters":"half-integer","dimensions":["width":width,"height":height]],"sourceToInput":try json(sourceToInput),"inputToField":try json(inputToField),"mask":maskJSON,"operations":operationJSON,"preparation":["id":preparation.id,"version":preparation.version,"record":preparation.record.description]]
    let bytes=try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys,.withoutEscapingSlashes])
    let reference=ImageInputRef(issuer:identity.issuer,revision:identity.revision,digest:.hash(bytes))
    var objects=Dictionary(assets.map{($0.descriptor.asset.object,$0.bytes)},uniquingKeysWith:{$1});objects[photo.reference.digest]=photo.record.originalJSON;objects[reference.digest]=bytes
    let descriptors=Dictionary(assets.map{($0.descriptor.asset.object,$0.descriptor)},uniquingKeysWith:{$1})
    let record=try DrawingImageAdmission.input(reference,objects:objects,assetDescriptors:descriptors)
    return .init(record:record,photo:photo,assets:assets)
  }
  private static func json<T:Encodable>(_ value:T)throws->Any { try JSONSerialization.jsonObject(with:DrawingArtifactCoding.encoder().encode(value),options:[.fragmentsAllowed]) }
  private static func dated(_ fact:DrawingImageDatedFact)throws->[String:Any] {
    let result:[String:Any],provenance:String
    switch fact {
    case .known(let time,let source):provenance=source;result=["state":"known","time":try json(time),"provenance":source]
    case .unknown(let source):provenance=source;result=["state":"unknown","provenance":source]
    }
    guard !provenance.isEmpty else { throw DrawingExchangeError.malformed("Dated fact provenance") };return result
  }
}
