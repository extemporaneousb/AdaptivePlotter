import Darwin
import Foundation

/// Selected, checksum-verified original legacy bytes. Both startup import and
/// the command harness use this storage-only snapshot owner; the JSON reader
/// never publishes, upgrades, cleans up or retires its inputs.
enum PortraitLegacySnapshot {
  struct Verified { let directory:URL;let manifestSHA256:String;let receiptSHA256:String }
  static func capture(from source:URL,into snapshots:URL) throws -> Verified {
    let manager = FileManager.default,index = source.appendingPathComponent("index-v1.json")
    let original = try Data(contentsOf:index),hash = PortraitCandidateCoding.digest(original)
    let destination = snapshots.appendingPathComponent(hash)
    guard !destination.standardizedFileURL.path.hasPrefix(source.standardizedFileURL.path + "/"),destination.standardizedFileURL != source.standardizedFileURL else { throw PortraitLibraryError.database("snapshot must be outside mutable legacy namespace") }
    let envelope = try JSONDecoder().decode(IndexEnvelope.self,from:original)
    guard [1,2,3,4].contains(envelope.schemaVersion),PortraitCandidateCoding.digest(envelope.payload) == envelope.sha256 else { throw PortraitLibraryError.database("legacy manifest checksum/schema invalid") }
    var records = Set<String>(),assets = Set<String>()
    func scan(_ object:Any) throws {
      if let dictionary = object as? [String:Any] {
        for (key,value) in dictionary {
          if let identity = value as? String,["sourceSHA256","rasterSHA256"].contains(key) {
            guard identity.count == 64,identity.allSatisfy(\.isHexDigit) else { throw PortraitLibraryError.database("invalid legacy asset identity") }
            assets.insert(identity)
          } else if let identity = value as? String,["candidateSHA256","metadataSHA256","recordSHA256"].contains(key) {
            guard identity.count == 64,identity.allSatisfy(\.isHexDigit) else { throw PortraitLibraryError.database("invalid legacy record identity") }
            records.insert(identity)
          } else if key == "sha256",let identity = value as? String,dictionary["id"] != nil {
            guard identity.count == 64,identity.allSatisfy(\.isHexDigit) else { throw PortraitLibraryError.database("invalid legacy label identity") }
            records.insert(identity)
          }
          try scan(value)
        }
      } else if let array = object as? [Any] { for child in array { try scan(child) } }
    }
    try scan(JSONSerialization.jsonObject(with:envelope.payload))
    var originalFiles: [String:Data] = ["index-v1.json":original]
    var scanned = Set<String>()
    while let record = records.subtracting(scanned).first {
      let bytes = try Data(contentsOf:source.appendingPathComponent("records").appendingPathComponent(record))
      guard PortraitCandidateCoding.digest(bytes) == record else { throw PortraitLibraryError.database("legacy record checksum invalid") }
      originalFiles["records/"+record] = bytes;scanned.insert(record)
      try scan(JSONSerialization.jsonObject(with:bytes))
    }
    for asset in assets {
      let bytes = try Data(contentsOf:source.appendingPathComponent("assets").appendingPathComponent(asset))
      guard PortraitCandidateCoding.digest(bytes) == asset else { throw PortraitCandidateStoreError.invalidAsset(asset) }
      originalFiles["assets/"+asset] = bytes
    }
    try manager.createDirectory(at:destination,withIntermediateDirectories:true)
    var inventory: [[String:Any]] = []
    let previouslyVerified = manager.fileExists(atPath:destination.appendingPathComponent("verified-snapshot.json").path)
    for (relative,bytes) in originalFiles.sorted(by:{$0.key<$1.key}) {
      let file = destination.appendingPathComponent(relative),digest = PortraitCandidateCoding.digest(bytes)
      try manager.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
      if manager.fileExists(atPath:file.path) {
        if PortraitCandidateCoding.digest(try Data(contentsOf:file)) != digest {
          guard !previouslyVerified else { throw PortraitLibraryError.database("snapshot immutable bytes changed") }
          try bytes.write(to:file,options:.atomic)
        }
      } else { try bytes.write(to:file,options:.atomic) }
      let handle = try FileHandle(forWritingTo:file);try handle.synchronize();try handle.close()
      guard PortraitCandidateCoding.digest(try Data(contentsOf:file)) == digest else { throw PortraitLibraryError.database("snapshot verification failed") }
      inventory.append(["path":relative,"sha256":digest,"byteCount":bytes.count])
    }
    for name in ["records","assets",""] {
      let directory = name.isEmpty ? destination : destination.appendingPathComponent(name)
      if manager.fileExists(atPath:directory.path) { try sync(directory) }
    }
    guard try Data(contentsOf:index) == original else { throw PortraitLibraryError.staleGeneration }
    let receipt = try JSONSerialization.data(withJSONObject:["schemaVersion":1,"legacyManifestSHA256":hash,"files":inventory],options:[.sortedKeys,.prettyPrinted])
    let file = destination.appendingPathComponent("verified-snapshot.json")
    try receipt.write(to:file,options:.atomic)
    let handle = try FileHandle(forWritingTo:file);try handle.synchronize();try handle.close();try sync(destination);try sync(snapshots)
    return .init(directory:destination,manifestSHA256:hash,receiptSHA256:PortraitCandidateCoding.digest(receipt))
  }
  private static func sync(_ url:URL) throws {
    let fd = url.withUnsafeFileSystemRepresentation{Darwin.open($0!,O_RDONLY)}
    guard fd >= 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
    defer{Darwin.close(fd)}
    guard Darwin.fsync(fd) == 0 else { throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno)) }
  }
}
