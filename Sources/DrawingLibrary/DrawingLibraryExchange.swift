import Foundation
import PortraitCore

extension DrawingLibrary {
  /// Exports the exact selected current-format authored closure. External file
  /// transfer is a directory BagIt carrier, or a ZIP when its extension is zip.
  public func exportDrawing(_ ref:DrawingRef,to destination:URL)throws {
    _ = try drawing(ref)
    guard let db=try commonReadDatabase() else { throw DrawingLibraryError.missing(ref) }
    try commonSnapshot(db) {
      let selected = try selectedDrawingPublication(for: ref, database: db)
      let temp=FileManager.default.temporaryDirectory.appendingPathComponent("drawing-export-"+UUID().uuidString.lowercased(),isDirectory:true)
      try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
      defer { try? FileManager.default.removeItem(at:temp) }
      let admitted=try selectedExportPackage(selected,temporaryRoot:temp)
      if destination.pathExtension.lowercased()=="zip" { try DrawingExchangeCarrier.preserveZIP(admitted.files,to:destination) }
      else { try DrawingExchangeCarrier.preserveDirectory(admitted.files,to:destination) }
    }
  }
  /// The selected root is explicit even when its publication also retained its
  /// parent. Immutable drawing/program bytes and required index context survive.
  package func selectedExportPackage(_ selected:SelectedDrawingAdmission,temporaryRoot:URL)throws->ValidatedExchangePackage {
    let files=try selected.files.selectedVerifiedFiles()
    let bag=temporaryRoot.appendingPathComponent("bag",isDirectory:true)
    try DrawingExchangeCarrier.preserveDirectory(files,to:bag)
    let original=try ExchangeIndex(originalJSON:selected.originalIndexJSON)
    var index=try ExchangeJSON.validate(selected.originalIndexJSON)
    let encoder=DrawingArtifactCoding.encoder()
    index["kind"]="drawing"
    index["roots"]=try JSONSerialization.jsonObject(with:encoder.encode([selected.reference]))
    // These are roots outside the requested authored closure, not dependencies
    // of its source, parent or membership receipt.
    for key in ["attempts","assessments","jobs","rankingCapsules","photos","inputs"] { index[key]=[String]() }
    index.removeValue(forKey:"scope")
    let objects=Set(files.entries.values.filter{$0.path.hasPrefix("data/objects/sha256/")}.map(\.digest))
    index["assets"]=try JSONSerialization.jsonObject(with:encoder.encode(original.assets.filter{objects.contains($0.asset.object)}))
    // requiredFeatures and unknown index extension fields remain in the copied
    // context. They are never erased to manufacture semantic support.
    let bytes=try JSONSerialization.data(withJSONObject:index,options:[.sortedKeys,.withoutEscapingSlashes])
    try bytes.write(to:bag.appendingPathComponent("data/exchange.json"),options:.atomic)
    var entries=files.entries.values.filter{$0.path.hasPrefix("data/") && $0.path != "data/exchange.json"}.map{($0.path,$0.digest)}
    entries.append(("data/exchange.json",.hash(bytes)))
    let bagit=Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    let manifest=Data(entries.sorted{$0.0<$1.0}.map{$0.1.description+"  "+$0.0+"\n"}.joined().utf8)
    try bagit.write(to:bag.appendingPathComponent("bagit.txt"),options:.atomic)
    try manifest.write(to:bag.appendingPathComponent("manifest-sha256.txt"),options:.atomic)
    try Data((ExchangeDigest.hash(bagit).description+"  bagit.txt\n"+ExchangeDigest.hash(manifest).description+"  manifest-sha256.txt\n").utf8).write(to:bag.appendingPathComponent("tagmanifest-sha256.txt"),options:.atomic)
    let staged=try DrawingExchangeCarrier.stageDirectory(bag,stagingParent:temporaryRoot)
    return try ExchangeAdmission.validate(staged,producerValidators:producerValidators)
  }
  public func importDrawings(from source:URL)throws->[DrawingRef] {
    let temp=FileManager.default.temporaryDirectory.appendingPathComponent("drawing-import-"+UUID().uuidString.lowercased(),isDirectory:true)
    try FileManager.default.createDirectory(at:temp,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    defer { try? FileManager.default.removeItem(at:temp) }
    var directory:ObjCBool=false
    guard FileManager.default.fileExists(atPath:source.path,isDirectory:&directory) else { throw DrawingLibraryError.unavailable("Exchange source unavailable") }
    let staged=try directory.boolValue ? DrawingExchangeCarrier.stageDirectory(source,stagingParent:temp) : DrawingExchangeCarrier.stageZIP(source,stagingParent:temp)
    let admitted=try ExchangeAdmission.validate(staged,producerValidators:producerValidators)
    guard let index=admitted.index.known,index.kind=="drawing",index.requiredFeatures.isEmpty else { throw DrawingLibraryError.unsupportedFeature("Import requires the current Drawing Exchange profile") }
    // Retention of each root uses its original immutable publication; sibling
    // roots in an explicit imported package are the operator's selected unit.
    var prepared:[DrawingLibraryPreparedRetention]=[]
    do {
      for ref in index.roots {
        guard case .materialized(let frozen)?=admitted.drawings[ref] else { throw DrawingLibraryError.unsupportedFeature("Opaque imported drawing") }
        prepared.append(try prepareRetention(frozen.drawing,reason:"Import",closure:.init(publication:admitted)))
      }
      return try commitRetentions(prepared).map(\.reference)
    } catch {
      // Durable publication recovery owns any staged transaction; temporary
      // preparations can be dropped without making a partially imported Library.
      for value in prepared { discardPending(value.token) }
      throw error
    }
  }
}
