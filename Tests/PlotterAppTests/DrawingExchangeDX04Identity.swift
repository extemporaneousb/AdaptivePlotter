import CryptoKit
import Darwin
import Foundation
import MachO

/// Test-only pre-clock loader/host binding. Identical bytes are used in both builds.
enum DX04ProbeError: Error { case arguments(String), imageMismatch, acknowledgement, timeout, invariant(String) }
enum DX04ProbeIdentity {
  static func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom:url); defer { try? handle.close() }
    var hash = SHA256()
    while let bytes = try handle.read(upToCount:1024*1024), !bytes.isEmpty { hash.update(data:bytes) }
    return hash.finalize().map { String(format:"%02x",$0) }.joined()
  }
  static func imageUUID(_ header: UnsafePointer<mach_header>) -> String? {
    let head = header.pointee
    guard head.magic == MH_MAGIC_64,head.ncmds < 65_536 else { return nil }
    var pointer = UnsafeRawPointer(header).advanced(by:MemoryLayout<mach_header_64>.size),remaining = Int(head.sizeofcmds)
    for _ in 0..<head.ncmds {
      guard remaining >= MemoryLayout<load_command>.size else { return nil }
      let command = pointer.load(as:load_command.self),length = Int(command.cmdsize)
      guard length >= MemoryLayout<load_command>.size,length <= remaining else { return nil }
      if command.cmd == LC_UUID,length >= MemoryLayout<uuid_command>.size { return UUID(uuid:pointer.load(as:uuid_command.self).uuid).uuidString.lowercased() }
      pointer = pointer.advanced(by:length);remaining -= length
    }
    return nil
  }
  static func observed() throws -> [String:Any] {
    var images: [[String:Any]] = []
    for index in 0..<_dyld_image_count() {
      guard let name = _dyld_get_image_name(index),let header = _dyld_get_image_header(index) else { continue }
      let path = String(cString:name)
      if URL(fileURLWithPath:path).lastPathComponent == "AdaptivePlotterPackageTests" {
        images.append(["path":path,"sha256":try sha256(URL(fileURLWithPath:path)),"uuid":imageUUID(header) as Any? ?? NSNull()])
      }
    }
    guard images.count == 1 else { throw DX04ProbeError.imageMismatch }
    return ["pid":getpid(),"parentPID":getppid(),"argv":CommandLine.arguments,"testImages":images]
  }
  static func required(_ env: [String:String],_ key: String) throws -> String {
    guard let value = env[key],!value.isEmpty else { throw DX04ProbeError.arguments(key) };return value
  }
  static func write(_ value: [String:Any],to url: URL) throws {
    guard !FileManager.default.fileExists(atPath:url.path) else { throw DX04ProbeError.arguments("Output already exists: " + url.path) }
    try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)
  }
  static func attest(_ env: [String:String]) throws -> [String:Any] {
    let actual = try observed(),image = (actual["testImages"] as! [[String:Any]])[0]
    let expectedPath = URL(fileURLWithPath:try required(env,"DX04_EXPECTED_IMAGE")).resolvingSymlinksInPath()
    guard URL(fileURLWithPath:image["path"] as! String).resolvingSymlinksInPath() == expectedPath,
      image["sha256"] as? String == env["DX04_EXPECTED_IMAGE_SHA256"] else { throw DX04ProbeError.imageMismatch }
    let token = try required(env,"DX04_PROBE_TOKEN"),identityURL = URL(fileURLWithPath:try required(env,"DX04_IDENTITY_OUTPUT"))
    var report = actual;report["token"] = token;report["status"] = "awaiting-host-acknowledgement"
    try write(report,to:identityURL)
    let ackURL = URL(fileURLWithPath:try required(env,"DX04_IDENTITY_ACK")),deadline = ContinuousClock.now.advanced(by:.seconds(20))
    while !FileManager.default.fileExists(atPath:ackURL.path),ContinuousClock.now < deadline { Thread.sleep(forTimeInterval:0.01) }
    let fd = Darwin.open(ackURL.path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
    guard fd >= 0 else { throw DX04ProbeError.timeout };defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd,&info) == 0,info.st_mode & S_IFMT == S_IFREG,info.st_nlink == 1,info.st_size > 0,info.st_size <= 4096 else { throw DX04ProbeError.acknowledgement }
    var bytes = [UInt8](repeating:0,count:4097)
    let count = Darwin.read(fd,&bytes,bytes.count)
    guard count > 0,count <= 4096,let ack = try JSONSerialization.jsonObject(with:Data(bytes.prefix(count))) as? [String:Any],
      Set(ack.keys) == Set(["token","pid","testImageSHA256"]),ack["token"] as? String == token,
      (ack["pid"] as? NSNumber)?.int32Value == getpid(),ack["testImageSHA256"] as? String == image["sha256"] as? String else {
      throw DX04ProbeError.acknowledgement
    }
    return report
  }
}
