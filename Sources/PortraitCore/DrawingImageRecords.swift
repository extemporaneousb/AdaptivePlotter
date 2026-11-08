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
public enum DrawingImageDatedFact: Sendable {
  case known(ExchangeTimestamp,provenance:String)
  case unknown(provenance:String)
}
public struct FrozenPhotoRecord: Sendable {
  public let record:ExchangePhotoRecord
  public let assets:[DrawingImageAsset]
  public var reference:PhotoRef { record.reference }
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
