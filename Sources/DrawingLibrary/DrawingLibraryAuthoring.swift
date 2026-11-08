import Foundation
import PortraitCore

extension DrawingLibrary {
  package func preparePublication(_ frozen: FrozenDrawingRecord, closure: DrawingLibraryRetainedClosure,
    database: DrawingLibraryDatabase?) throws -> (package: ValidatedExchangePackage, temporaryRoot: URL) {
    guard closure.assets.count + closure.records.count <= 10_000 else { throw DrawingExchangeError.limit("Authored closure count") }
    let name = "build"
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("drawing-library-" + UUID().uuidString.lowercased(), isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    let build = temporary.appendingPathComponent(name,isDirectory:true)
    try FileManager.default.createDirectory(at:build,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
    var succeeded = false
    defer { if !succeeded { try? FileManager.default.removeItem(at: temporary) } }
    var inventory: [String: ExchangeCatalogFile] = [:]
    var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
    var declaredBytes = 0
    func descriptor(_ value: ExchangeAssetDescriptor) throws {
      if let old = descriptors[value.asset.object], old != value { throw DrawingExchangeError.malformed("Authored descriptor conflict") }
      descriptors[value.asset.object] = value
    }
    func file(_ path: String, bytes: Data) throws {
      guard bytes.count <= 256 * 1024 * 1024 - declaredBytes else { throw DrawingExchangeError.limit("Authored closure bytes") }
      declaredBytes += bytes.count
      let target = build.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      try bytes.write(to: target, options: .atomic)
      let value = ExchangeCatalogFile(path: path, storagePath: path, digest: .hash(bytes), byteLength: UInt64(bytes.count))
      if let old = inventory[path], old.digest != value.digest { throw DrawingExchangeError.digestMismatch("Authored path collision") }
      inventory[path] = value
    }
    func addDependency(_ source:VerifiedExchangeFiles) throws {
      let entries=Array(source.entries.values)
      let original = try source.record(at: "data/exchange.json")
      let index = try ExchangeIndex(originalJSON: original)
      guard index.requiredFeatures.isEmpty, ["drawing", "result", "feedback"].contains(index.kind) else {
        throw DrawingLibraryError.unsupportedFeature(index.requiredFeatures.first ?? index.kind)
      }
      for value in index.assets { try descriptor(value) }
      for entry in entries where entry.path != "data/exchange.json" {
        if let old = inventory[entry.path], old.digest != entry.digest { throw DrawingExchangeError.digestMismatch("Dependency path collision") }
        try file(entry.path,bytes:source.record(at:entry.path,maximumBytes:DrawingExchangeLimits.maximumProgramBytes))
      }
    }
    if case .present(let parent) = frozen.drawing.parent {
      if let pending=pendingRetentions.values.first(where:{$0.reference==parent}),let publication=pending.publication {
        let proof=try ExchangeAdmission.selectDrawing(originalIndexJSON:publication.index.originalJSON,selected:parent,files:publication.files,producerValidators:producerValidators)
        guard case .materialized=proof.admission else { throw DrawingLibraryError.unsupportedFeature("Pending parent") }
        try addDependency(proof.files.selectedVerifiedFiles())
      } else {
        _ = try drawing(parent)
        guard let database else { throw DrawingLibraryError.missing(parent) }
        let proof = try selectedDrawingPublication(for: parent, database: database)
        try addDependency(proof.files.selectedVerifiedFiles())
      }
    }
    for asset in closure.assets {
      try asset.descriptor.asset.validate(asset.bytes, maximumBytes: DrawingExchangeLimits.maximumProgramBytes)
      try descriptor(asset.descriptor)
      try file("data/objects/sha256/" + asset.descriptor.asset.object.description, bytes: asset.bytes)
    }
    for record in closure.records {
      let path: String, digest: ExchangeDigest
      switch record.reference {
      case .drawing(let ref): path = "data/drawings/" + ref.issuer.uuidString.lowercased() + "/" + ref.revision.uuidString.lowercased() + "/drawing.json"; digest = ref.digest
      case .photo(let ref): path = "data/photos/" + ref.issuer.uuidString.lowercased() + "/" + ref.revision.uuidString.lowercased() + "/photo.json"; digest = ref.digest
      case .input(let ref): path = "data/inputs/" + ref.issuer.uuidString.lowercased() + "/" + ref.revision.uuidString.lowercased() + "/input.json"; digest = ref.digest
      }
      guard ExchangeDigest.hash(record.originalJSON) == digest else { throw DrawingExchangeError.digestMismatch("Authored dependency record") }
      try file(path, bytes: record.originalJSON)
    }
    if case .present(let input) = frozen.drawing.input {
      let path = "data/inputs/" + input.issuer.uuidString.lowercased() + "/" + input.revision.uuidString.lowercased() + "/input.json"
      if let included = inventory[path] {
        // Parent or explicit supplied closure already carries this exact input.
        // Final admission still proves its complete photo/raster/mask closure.
        guard included.digest == input.digest else { throw DrawingExchangeError.digestMismatch("Assembled input identity") }
      } else if let database {
        let source = try selectedInputPublication(for: input, database: database)
        try addDependency(source)
      }
    }
    let program = try ExchangeAsset(bytes: frozen.originalProgramJSON, mediaType: "application/json", encoding: DrawingExchangeCodec.strokeProfile)
    let producer = try ExchangeAsset(bytes: frozen.drawing.producer.originalJSON, mediaType: "application/json", encoding: "utf8-json")
    try descriptor(.init(asset: program)); try descriptor(.init(asset: producer))
    try file("data/objects/sha256/" + program.object.description, bytes: frozen.originalProgramJSON)
    try file("data/objects/sha256/" + producer.object.description, bytes: frozen.drawing.producer.originalJSON)
    let ref = frozen.reference
    try file("data/drawings/" + ref.issuer.uuidString.lowercased() + "/" + ref.revision.uuidString.lowercased() + "/drawing.json", bytes: frozen.originalJSON)
    func indexJSON(_ assets: [ExchangeAssetDescriptor]) throws -> Data {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let object: [String: Any] = ["profile": "adaptiveplotter.exchange/1", "requiredFeatures": [String](), "kind": "drawing",
        "roots": try JSONSerialization.jsonObject(with: encoder.encode([ref])), "includedAsOf": ISO8601DateFormatter().string(from: Date()),
        "assets": try JSONSerialization.jsonObject(with: encoder.encode(assets)), "attempts": [String](), "assessments": [String]()]
      return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    let provisional = try indexJSON(descriptors.values.sorted { $0.asset.object.description < $1.asset.object.description })
    try file("data/exchange.json", bytes: provisional)
    let resolver = try VerifiedExchangeFiles(catalogRoot: build, inventory: Array(inventory.values))
    _ = try resolver.record(at: "data/exchange.json")
    _ = try ExchangeAdmission.selectDrawing(originalIndexJSON: provisional, selected: ref, files: resolver, producerValidators: producerValidators)
    let selected = try resolver.selectedVerifiedFiles()
    let objects = Set(selected.entries.values.filter { $0.path.hasPrefix("data/objects/sha256/") }.map(\.digest))
    let finalIndex = try indexJSON(objects.compactMap { descriptors[$0] }.sorted { $0.asset.object.description < $1.asset.object.description })
    let finalPath = "final-exchange.json"
    try finalIndex.write(to: build.appendingPathComponent(finalPath), options: .atomic)
    var finalInventory = selected.entries.values.compactMap { inventory[$0.path] }.filter { $0.path != "data/exchange.json" }
    finalInventory.append(.init(path: "data/exchange.json", storagePath: finalPath, digest: .hash(finalIndex), byteLength: UInt64(finalIndex.count)))
    let finalFiles = try VerifiedExchangeFiles(catalogRoot: build, inventory: finalInventory)
    _ = try finalFiles.record(at: "data/exchange.json")
    _ = try ExchangeAdmission.selectDrawing(originalIndexJSON: finalIndex, selected: ref, files: finalFiles, producerValidators: producerValidators)
    let bag = temporary.appendingPathComponent("bag", isDirectory: true)
    try DrawingExchangeCarrier.preserveDirectory(finalFiles, to: bag)
    let bagit = Data("BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n".utf8)
    try bagit.write(to: bag.appendingPathComponent("bagit.txt"))
    let manifest = Data(finalInventory.sorted { $0.path < $1.path }.map { $0.digest.description + "  " + $0.path + "\n" }.joined().utf8)
    try manifest.write(to: bag.appendingPathComponent("manifest-sha256.txt"))
    let tags = Data((ExchangeDigest.hash(bagit).description + "  bagit.txt\n" + ExchangeDigest.hash(manifest).description + "  manifest-sha256.txt\n").utf8)
    try tags.write(to: bag.appendingPathComponent("tagmanifest-sha256.txt"))
    let staged = try DrawingExchangeCarrier.stageDirectory(bag, stagingParent: temporary)
    let admitted = try ExchangeAdmission.validate(staged, producerValidators: producerValidators)
    succeeded = true
    return (admitted, temporary)
  }
}

extension DrawingLibrary {
  package func selectedInputPublication(for input: ImageInputRef, database db: DrawingLibraryDatabase) throws -> VerifiedExchangeFiles {
    let reference = LibraryExchangeReference.input(input)
    if let stored = try db.scalar("SELECT digest FROM dx_record WHERE kind=? AND namespace=? AND identity=?", reference.key.map(Optional.some)), stored != input.digest.description {
      throw DrawingExchangeError.digestMismatch("Stored input identity")
    }
    let candidates = try publicationCandidates(reference, database: db)
    let path = "data/inputs/" + input.issuer.uuidString.lowercased() + "/" + input.revision.uuidString.lowercased() + "/input.json"
    var reason = "No supported input publication context"
    for candidate in candidates {
      let source = try publicationFiles(candidate, database: db)
      let indexBytes = try source.record(at: "data/exchange.json")
      guard ExchangeDigest.hash(indexBytes) == candidate.index, source.entries[path]?.digest == input.digest else {
        throw DrawingExchangeError.digestMismatch("Input publication identity")
      }
      do {
        let index = try ExchangeIndex(originalJSON: indexBytes)
        guard index.requiredFeatures.isEmpty, ["drawing", "result", "feedback"].contains(index.kind) else {
          reason = index.requiredFeatures.first ?? index.kind
          continue
        }
        var descriptors: [ExchangeDigest: ExchangeAssetDescriptor] = [:]
        for descriptor in index.assets {
          if let old = descriptors[descriptor.asset.object], old != descriptor { throw DrawingExchangeError.malformed("Conflicting input asset descriptors") }
          descriptors[descriptor.asset.object] = descriptor
        }
        // This verifies declared source/image facts conservatively. Unsupported
        // source semantics remain unknown; they are not a physical-width or
        // producer-reverification claim. Final Drawing admission owns capability.
        _ = try source.record(at: path)
        let admitted = try DrawingImageAdmission.input(input, files: source, assetDescriptors: descriptors)
        let photoPath = "data/photos/" + admitted.photo.issuer.uuidString.lowercased() + "/" + admitted.photo.revision.uuidString.lowercased() + "/photo.json"
        guard source.entries[photoPath]?.digest == admitted.photo.digest else { throw DrawingExchangeError.digestMismatch("Input Photo record path") }
        _ = try source.record(at: photoPath)
        return try source.selectedVerifiedFiles()
      } catch DrawingExchangeError.unsupportedProfile(let profile) {
        reason = profile
      }
    }
    throw DrawingLibraryError.unsupportedFeature(reason)
  }

  package func retentionRequestDigest(_ drawing: Drawing, closure: DrawingLibraryRetainedClosure) throws -> ExchangeDigest {
    guard closure.records.count+closure.assets.count<=10_000 else { throw DrawingExchangeError.limit("Retention closure count") }
    var total=0
    for size in closure.records.map({$0.originalJSON.count})+closure.assets.map({$0.bytes.count}) {
    guard size<=256*1024*1024-total else { throw DrawingExchangeError.limit("Retention closure bytes") };total += size
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    func json<T: Encodable>(_ value: T) throws -> Any {
      try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
    }
    var units: [String: Any] = [:]
    if let value = drawing.units.nominalPenWidthMM { units["nominalPenWidthMM"] = value }
    if let value = drawing.units.intendedPhysicalFieldMM { units["intendedPhysicalFieldMM"] = try json(value) }
    if let value = drawing.units.historical { units["historical"] = value }
    if let value = drawing.units.historicalReceipt { units["historicalReceipt"] = value.description }
    let assets = try closure.assets.map { value -> [String: Any] in
      ["descriptor": try json(value.descriptor), "actualBytes": ExchangeDigest.hash(value.bytes).description]
    }.sorted { String(describing: $0["actualBytes"]!) < String(describing: $1["actualBytes"]!) }
    let records = closure.records.map { value -> String in
      let kind: String, ref: String
      switch value.reference {
      case .drawing(let r): kind = "drawing"; ref = r.issuer.uuidString.lowercased() + "/" + r.revision.uuidString.lowercased() + "/" + r.digest.description
      case .photo(let r): kind = "photo"; ref = r.issuer.uuidString.lowercased() + "/" + r.revision.uuidString.lowercased() + "/" + r.digest.description
      case .input(let r): kind = "input"; ref = r.issuer.uuidString.lowercased() + "/" + r.revision.uuidString.lowercased() + "/" + r.digest.description
      }
      return kind + ":" + ref + ":" + ExchangeDigest.hash(value.originalJSON).description
    }.sorted()
    var commitment: [String: Any] = ["program": drawing.programDigest.description,
      "programJSON": ExchangeDigest.hash(try DrawingArtifactCoding.encoder().encode(drawing.program)).description,
      "producer": drawing.producer.record.description, "producerID": drawing.producer.id, "producerVersion": drawing.producer.version,
      "input": try json(drawing.input), "parent": try json(drawing.parent), "units": units,
      "requiredFeatures": drawing.requiredFeatures.sorted(), "assets": assets, "records": records]
    if let ref = drawing.reference { commitment["boundReference"] = try json(ref) }
    if let publication = closure.publication {
      commitment["publicationIndex"] = ExchangeDigest.hash(publication.index.originalJSON).description
      commitment["publicationInventory"] = publication.files.entries.values.map { $0.path + ":" + $0.digest.description + ":" + String($0.byteLength) }.sorted()
    }
    return .hash(try JSONSerialization.data(withJSONObject: commitment, options: [.sortedKeys, .withoutEscapingSlashes]))
  }
}
