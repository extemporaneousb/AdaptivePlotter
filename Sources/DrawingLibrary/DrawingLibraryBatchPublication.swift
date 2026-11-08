import Foundation
import PortraitCore

extension DrawingLibrary {
  /// Combines explicitly selected authored closures. Equal original publications
  /// are reused byte for byte; different closures get one new exchange index.
  package func prepareBatchPublication(_ packages:[ValidatedExchangePackage],roots:[DrawingRef],assets:[DrawingLibraryClosureAsset],publicationID:UUID)throws->(package:ValidatedExchangePackage,temporaryRoot:URL?) {
    func inventory(_ package:ValidatedExchangePackage)->[String] {
      package.files.entries.values.map{$0.path+":"+$0.digest.description+":"+String($0.byteLength)}.sorted()
    }
    if let first=packages.first,assets.isEmpty,packages.allSatisfy({inventory($0)==inventory(first)}) {
      return(first,nil)
    }
    if packages.isEmpty {
      let extra=try packageWithAssets(nil,assets:assets,publicationID:publicationID)
      return(extra.package,extra.temporaryRoot)
    }
    let temporary=FileManager.default.temporaryDirectory.appendingPathComponent("drawing-batch-"+UUID().uuidString.lowercased(),isDirectory:true)
    try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    var success=false
    defer { if !success { try? FileManager.default.removeItem(at:temporary) } }
    let bag=temporary.appendingPathComponent("bag",isDirectory:true)
    try FileManager.default.createDirectory(at:bag,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    var paths:[String:ExchangeDigest]=[:],descriptors:[ExchangeDigest:ExchangeAssetDescriptor]=[:],total=0
    func addDescriptor(_ descriptor:ExchangeAssetDescriptor)throws {
      if let old=descriptors[descriptor.asset.object],old != descriptor { throw DrawingExchangeError.malformed("Batch descriptor conflict") }
      descriptors[descriptor.asset.object]=descriptor
    }
    func file(_ path:String,bytes:Data,digest:ExchangeDigest)throws {
      if let prior=paths[path] {
        guard prior==digest else { throw DrawingExchangeError.digestMismatch("Batch path collision") };return
      }
      guard bytes.count<=256*1024*1024-total,paths.count<10_000 else { throw DrawingExchangeError.limit("Batch closure") };total += bytes.count
      guard ExchangeDigest.hash(bytes)==digest else { throw DrawingExchangeError.digestMismatch("Batch bytes") }
      let target=bag.appendingPathComponent(path)
      try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
      try bytes.write(to:target,options:.atomic);paths[path]=digest
    }
    for package in packages {
      guard let index=package.index.known,index.requiredFeatures.isEmpty,index.kind=="drawing" else { throw DrawingLibraryError.unsupportedFeature("Batch exchange context") }
      for descriptor in index.assets { try addDescriptor(descriptor) }
      for entry in package.files.entries.values where entry.path.hasPrefix("data/") && entry.path != "data/exchange.json" {
        if let prior=paths[entry.path] { guard prior==entry.digest else { throw DrawingExchangeError.digestMismatch("Batch path collision") };continue }
        try file(entry.path,bytes:package.files.record(at:entry.path,maximumBytes:DrawingExchangeLimits.maximumProgramBytes),digest:entry.digest)
      }
    }
    for asset in assets {
      try asset.descriptor.asset.validate(asset.bytes,maximumBytes:DrawingExchangeLimits.maximumProgramBytes)
      try addDescriptor(asset.descriptor)
      try file("data/objects/sha256/"+asset.descriptor.asset.object.description,bytes:asset.bytes,digest:asset.descriptor.asset.object)
    }
    let encoder=DrawingArtifactCoding.encoder()
    let index:[String:Any] = ["profile":"adaptiveplotter.exchange/1","requiredFeatures":[String](),"kind":"drawing","roots":try JSONSerialization.jsonObject(with:encoder.encode(roots)),"includedAsOf":ISO8601DateFormatter().string(from:Date()),"assets":try JSONSerialization.jsonObject(with:encoder.encode(descriptors.values.sorted{$0.asset.object.description<$1.asset.object.description})),"attempts":[String](),"assessments":[String](),"localPublication":publicationID.uuidString.lowercased()]
    let bytes=try JSONSerialization.data(withJSONObject:index,options:[.sortedKeys,.withoutEscapingSlashes])
    try file("data/exchange.json",bytes:bytes,digest:.hash(bytes))
    let bagit=Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    let manifest=Data(paths.keys.sorted().map{paths[$0]!.description+"  "+$0+"\n"}.joined().utf8)
    try bagit.write(to:bag.appendingPathComponent("bagit.txt"))
    try manifest.write(to:bag.appendingPathComponent("manifest-sha256.txt"))
    try Data((ExchangeDigest.hash(bagit).description+"  bagit.txt\n"+ExchangeDigest.hash(manifest).description+"  manifest-sha256.txt\n").utf8).write(to:bag.appendingPathComponent("tagmanifest-sha256.txt"))
    let staged=try DrawingExchangeCarrier.stageDirectory(bag,stagingParent:temporary)
    let admitted=try ExchangeAdmission.validate(staged,producerValidators:producerValidators)
    success=true;return(admitted,temporary)
  }
}
