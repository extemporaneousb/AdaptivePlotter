import Foundation
import Darwin
import zlib

/// Deliberately bounded classic ZIP subset: single disk, no encryption/descriptors/ZIP64,
/// UTF-8 (or ASCII) names, stored or raw DEFLATE; no archive extraction process.
enum ExchangeZIP {
  struct Entry {
    let path: String
    let directory: Bool
    let method: UInt16
    let flags: UInt16
    let version: UInt16
    let modifiedTime: UInt16
    let modifiedDate: UInt16
    let crc: UInt32
    let compressed: UInt64
    let expanded: UInt64
    let local: UInt64
    let name: Data
    var dataOffset: UInt64 = 0
    var end: UInt64 = 0
  }
  static func extract(_ source: URL, to stage: URL, limits: ExchangeCarrierLimits,
    counters: ExchangeCarrierCounters, cancelled: @Sendable () -> Bool) throws {
    let file = try ExchangePinnedFile(source)
    var info = stat(); guard fstat(file.fd, &info) == 0, info.st_size >= 22 else { throw DrawingExchangeError.malformed("ZIP size") }
    let size = UInt64(info.st_size)
    func read(_ offset: UInt64, _ count: Int) throws -> Data {
      guard offset <= size, count >= 0, UInt64(count) <= size - offset else { throw DrawingExchangeError.malformed("ZIP range") }
      var data = Data(count: count)
      try data.withUnsafeMutableBytes { raw in
        var n = 0
        while n < count { let got = pread(file.fd, raw.baseAddress!.advanced(by: n), count - n, off_t(offset + UInt64(n))); guard got > 0 else { throw DrawingExchangeError.malformed("ZIP read") }; n += got }
      }
      counters.update { $0.sourceBytesRead += UInt64(count) }; return data
    }
    let tailCount = Int(min(size, 65_557)), tail = try read(size - UInt64(tailCount), tailCount)
    var eocd: Int?
    for i in stride(from: tail.count - 22, through: 0, by: -1) where tail.u32(i) == 0x06054b50 {
      if i + 22 + Int(tail.u16(i + 20)) == tail.count { eocd = i; break }
    }
    guard let end = eocd else { throw DrawingExchangeError.malformed("ZIP EOCD/trailing junk") }
    guard tail.u16(end + 4) == 0, tail.u16(end + 6) == 0, tail.u16(end + 8) == tail.u16(end + 10),
      tail.u16(end + 10) != UInt16.max else { throw DrawingExchangeError.malformed("ZIP disk/ZIP64") }
    let count = Int(tail.u16(end + 10)), centralSize = UInt64(tail.u32(end + 12)), centralOffset = UInt64(tail.u32(end + 16))
    guard count > 0, count <= limits.maximumEntries, centralOffset <= size, centralSize <= size - centralOffset,
      centralOffset + centralSize == size - UInt64(tailCount) + UInt64(end) else { throw DrawingExchangeError.malformed("ZIP central range") }
    var entries: [Entry] = [], position = centralOffset, paths = Set<String>(), folded = Set<String>(), total: UInt64 = 0
    for _ in 0..<count {
      if cancelled() { throw CancellationError() }
      let header = try read(position, 46)
      guard header.u32(0) == 0x02014b50 else { throw DrawingExchangeError.malformed("ZIP central signature") }
      let flags = header.u16(8), method = header.u16(10), nameCount = Int(header.u16(28)), extraCount = Int(header.u16(30)), commentCount = Int(header.u16(32))
      guard flags & ~UInt16(0x800) == 0, method == 0 || method == 8, header.u16(34) == 0, header.u16(6) <= 20,
        header.u32(20) != UInt32.max, header.u32(24) != UInt32.max, header.u32(42) != UInt32.max,
        nameCount > 0, nameCount <= 4096 else { throw DrawingExchangeError.malformed("Unsupported ZIP policy") }
      let variableLength = nameCount + extraCount + commentCount
      guard position + 46 <= centralOffset + centralSize, UInt64(variableLength) <= centralOffset + centralSize - position - 46 else { throw DrawingExchangeError.malformed("ZIP central record size") }
      let variable = try read(position + 46, variableLength), name = variable.prefix(nameCount)
      try extras(Data(variable.dropFirst(nameCount).prefix(extraCount)))
      guard let rawPath = String(data: name, encoding: .utf8), flags & 0x800 != 0 || name.allSatisfy({ $0 < 128 }) else { throw DrawingExchangeError.malformed("ZIP name encoding") }
      let directory = rawPath.hasSuffix("/"), path = directory ? String(rawPath.dropLast()) : rawPath
      try DrawingExchangeCarrier.safePath(path)
      guard paths.insert(path).inserted, folded.insert(DrawingExchangeCarrier.fold(path)).inserted else { throw DrawingExchangeError.malformed("ZIP duplicate/case collision") }
      let mode = header.u32(38) >> 16, kind = mode & 0xf000
      guard kind == 0 || kind == (directory ? 0x4000 : 0x8000), (header.u32(38) & 0x10 == 0 || directory) else { throw DrawingExchangeError.malformed("ZIP special entry") }
      let compressed = UInt64(header.u32(20)), expanded = UInt64(header.u32(24))
      try DrawingExchangeCarrier.addSize(expanded, total: &total, limits: limits)
      guard !directory || expanded == 0, method != 0 || compressed == expanded, method != 8 || compressed > 0,
        expanded == 0 || compressed > 0 && (expanded - 1) / compressed < limits.maximumCompressionRatio else { throw DrawingExchangeError.limit("ZIP ratio/length") }
      entries.append(.init(path: path, directory: directory, method: method, flags: flags, version: header.u16(6), modifiedTime: header.u16(12), modifiedDate: header.u16(14), crc: header.u32(16), compressed: compressed, expanded: expanded, local: UInt64(header.u32(42)), name: Data(name)))
      position += UInt64(46 + variableLength)
    }
    guard position == centralOffset + centralSize else { throw DrawingExchangeError.malformed("ZIP central trailing bytes") }
    // Parse every local header before writing, and prove exact nonoverlapping transport coverage.
    for i in entries.indices {
      let local = try read(entries[i].local, 30), entry = entries[i]
      guard local.u32(0) == 0x04034b50, local.u16(4) == entry.version, local.u16(10) == entry.modifiedTime, local.u16(12) == entry.modifiedDate, local.u16(6) == entry.flags, local.u16(8) == entry.method,
        local.u32(14) == entry.crc, UInt64(local.u32(18)) == entry.compressed, UInt64(local.u32(22)) == entry.expanded,
        Int(local.u16(26)) == entry.name.count else { throw DrawingExchangeError.malformed("ZIP local/central disagreement") }
      let extra = Int(local.u16(28)), variable = try read(entry.local + 30, entry.name.count + extra)
      guard variable.prefix(entry.name.count) == entry.name else { throw DrawingExchangeError.malformed("ZIP local name") }
      try extras(Data(variable.dropFirst(entry.name.count)))
      let start = entry.local + 30 + UInt64(entry.name.count + extra)
      guard start <= centralOffset, entry.compressed <= centralOffset - start else { throw DrawingExchangeError.malformed("ZIP payload range") }
      entries[i].dataOffset = start; entries[i].end = start + entry.compressed
    }
    var covered: UInt64 = 0
    for entry in entries.sorted(by: { $0.local < $1.local }) {
      guard entry.local == covered else { throw DrawingExchangeError.malformed("ZIP overlap/gap/prefix") }; covered = entry.end
    }
    guard covered == centralOffset else { throw DrawingExchangeError.malformed("ZIP unclaimed bytes") }
    // Refuse file/directory prefix ambiguity before creating any filesystem entries.
    var componentSpellings: [String: String] = [:]
    for entry in entries {
      let parts = entry.path.split(separator: "/")
      for n in 1...parts.count {
        let prefix = parts.prefix(n).joined(separator: "/"), folded = DrawingExchangeCarrier.fold(prefix)
        if let previous = componentSpellings[folded], previous != prefix { throw DrawingExchangeError.malformed("ZIP implicit directory case collision") }
        componentSpellings[folded] = prefix
      }
    }
    let files = Set(entries.filter { !$0.directory }.map(\.path))
    for entry in entries {
      let parts = entry.path.split(separator: "/")
      for n in 1..<parts.count where files.contains(parts.prefix(n).joined(separator: "/")) { throw DrawingExchangeError.malformed("ZIP file parent") }
    }
    for entry in entries {
      if cancelled() { throw CancellationError() }
      let target = stage.appendingPathComponent(entry.path)
      if entry.directory {
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if entry.compressed == 0 { guard entry.crc == 0 else { throw DrawingExchangeError.digestMismatch("ZIP empty directory CRC") }; continue }
      } else {
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      }
      let output = entry.directory ? Darwin.open("/dev/null", O_WRONLY | O_CLOEXEC) : Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o400)
      guard output >= 0 else { throw DrawingExchangeError.malformed("ZIP stage file") }; defer { Darwin.close(output) }
      var crc = crc32(0, nil, 0), expanded: UInt64 = 0
      func emit(_ bytes: [UInt8], _ n: Int) throws {
        guard UInt64(n) <= entry.expanded - min(expanded, entry.expanded) else { throw DrawingExchangeError.limit("ZIP expansion exceeded declaration") }
        try DrawingExchangeCarrier.writeAll(output, bytes, count: n)
        crc = bytes.withUnsafeBufferPointer { crc32(crc, $0.baseAddress, uInt(n)) }; expanded += UInt64(n)
        counters.update { $0.stagedBytesWritten += UInt64(n); $0.crcBytes += UInt64(n) }
      }
      var consumed: UInt64 = 0
      if entry.method == 0 {
        while consumed < entry.compressed {
          if cancelled() { throw CancellationError() }
          let data = try read(entry.dataOffset + consumed, Int(min(UInt64(limits.bufferBytes), entry.compressed - consumed)))
          try emit(Array(data), data.count); consumed += UInt64(data.count)
        }
      } else {
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw DrawingExchangeError.malformed("DEFLATE init") }
        defer { inflateEnd(&stream) }
        var ended = false, outputBuffer = [UInt8](repeating: 0, count: limits.bufferBytes)
        while consumed < entry.compressed && !ended {
          if cancelled() { throw CancellationError() }
          let input = [UInt8](try read(entry.dataOffset + consumed, Int(min(UInt64(limits.bufferBytes), entry.compressed - consumed))))
          try input.withUnsafeBufferPointer { raw in
            stream.next_in = UnsafeMutablePointer(mutating: raw.baseAddress); stream.avail_in = uInt(raw.count)
            repeat {
              if cancelled() { throw CancellationError() }
              let before = stream.avail_in
              let result = outputBuffer.withUnsafeMutableBufferPointer { out in
                stream.next_out = out.baseAddress; stream.avail_out = uInt(out.count)
                return inflate(&stream, Z_NO_FLUSH)
              }
              let n = outputBuffer.count - Int(stream.avail_out); try emit(outputBuffer, n)
              guard result == Z_OK || result == Z_STREAM_END else { throw DrawingExchangeError.malformed("DEFLATE stream") }
              if result == Z_STREAM_END { ended = true; break }
              guard before != stream.avail_in || n > 0 else { throw DrawingExchangeError.malformed("DEFLATE stalled") }
            } while stream.avail_in > 0 || stream.avail_out == 0
            consumed += UInt64(input.count - Int(stream.avail_in))
          }
        }
        guard ended, consumed == entry.compressed else { throw DrawingExchangeError.malformed("DEFLATE trailing/truncated bytes") }
      }
      guard expanded == entry.expanded, UInt32(crc) == entry.crc else { throw DrawingExchangeError.digestMismatch("ZIP expanded length/CRC") }
    }
    try file.check()
  }
  static func extras(_ bytes: Data) throws {
    var offset = 0
    while offset < bytes.count {
      guard bytes.count - offset >= 4 else { throw DrawingExchangeError.malformed("ZIP extra") }
      let kind = bytes.u16(offset), count = Int(bytes.u16(offset + 2))
      guard kind != 1, count <= bytes.count - offset - 4 else { throw DrawingExchangeError.malformed("ZIP64/extra") }
      offset += 4 + count
    }
  }
}
private extension Data {
  func u16(_ i: Int) -> UInt16 { UInt16(self[i]) | UInt16(self[i + 1]) << 8 }
  func u32(_ i: Int) -> UInt32 { UInt32(u16(i)) | UInt32(u16(i + 2)) << 16 }
}

extension ExchangeZIP {
  static func write(_ files: VerifiedExchangeFiles, to destination: URL, cancelled: @Sendable () -> Bool) throws {
    // Classic ZIP cannot represent an individual >=4GiB entry or >=4GiB transport.
    // Refuse before creating output rather than silently wrapping fields.
    let paths = files.entries.keys.sorted()
    guard paths.count < Int(UInt16.max) else { throw DrawingExchangeError.limit("Classic ZIP entry count") }
    var projected: UInt64 = 22
    for path in paths {
      let length = files.entries[path]!.byteLength, overhead = UInt64(76 + path.utf8.count * 2)
      guard length < UInt64(UInt32.max), projected < UInt64(UInt32.max), length + overhead < UInt64(UInt32.max) - projected else { throw DrawingExchangeError.limit("Classic ZIP size; use directory transport") }
      projected += length + overhead
    }
    let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o400)
    guard fd >= 0 else { throw DrawingExchangeError.malformed("ZIP preservation output") }; defer { Darwin.close(fd) }
    var offset: UInt64 = 0, central = Data()
    func put(_ data: Data) throws { try DrawingExchangeCarrier.writeAll(fd, Array(data), count: data.count); offset += UInt64(data.count); files.counters.update { $0.reexportBytesWritten += UInt64(data.count) } }
    for path in paths {
      if cancelled() { throw CancellationError() }
      let entry = files.entries[path]!, pinned = try files.pinned(at: path), name = Data(path.utf8)
      // CRC is a separate bounded pass required before classic local headers (no descriptors).
      var crc = crc32(0, nil, 0), buffer = [UInt8](repeating: 0, count: files.limits.bufferBytes)
      while true {
        if cancelled() { throw CancellationError() }
        let n = Darwin.read(pinned.fd, &buffer, buffer.count); guard n >= 0 else { throw DrawingExchangeError.malformed("ZIP CRC read") }; if n == 0 { break }
        crc = buffer.withUnsafeBufferPointer { crc32(crc, $0.baseAddress, uInt(n)) }
        files.counters.update { $0.reexportBytesRead += UInt64(n); $0.crcBytes += UInt64(n) }
      }
      try pinned.check(); guard lseek(pinned.fd, 0, SEEK_SET) == 0 else { throw DrawingExchangeError.malformed("ZIP rewind") }
      let localOffset = offset
      var local = Data(); local.le32(0x04034b50); local.le16(20); local.le16(0x800); local.le16(0); local.le16(0); local.le16(0)
      local.le32(UInt32(crc)); local.le32(UInt32(entry.byteLength)); local.le32(UInt32(entry.byteLength)); local.le16(UInt16(name.count)); local.le16(0); local.append(name)
      try put(local)
      while true {
        if cancelled() { throw CancellationError() }
        let n = Darwin.read(pinned.fd, &buffer, buffer.count); guard n >= 0 else { throw DrawingExchangeError.malformed("ZIP preserve read") }; if n == 0 { break }
        try put(Data(buffer[0..<n])); files.counters.update { $0.reexportBytesRead += UInt64(n) }
      }
      try pinned.check()
      central.le32(0x02014b50); central.le16(0x0314); central.le16(20); central.le16(0x800); central.le16(0); central.le16(0); central.le16(0)
      central.le32(UInt32(crc)); central.le32(UInt32(entry.byteLength)); central.le32(UInt32(entry.byteLength)); central.le16(UInt16(name.count)); central.le16(0); central.le16(0); central.le16(0); central.le16(0); central.le32(0o100400 << 16); central.le32(UInt32(localOffset)); central.append(name)
    }
    let centralOffset = offset; try put(central)
    var end = Data(); end.le32(0x06054b50); end.le16(0); end.le16(0); end.le16(UInt16(paths.count)); end.le16(UInt16(paths.count)); end.le32(UInt32(central.count)); end.le32(UInt32(centralOffset)); end.le16(0); try put(end)
  }
}
private extension Data {
  mutating func le16(_ value: UInt16) { append(UInt8(value & 255)); append(UInt8(value >> 8)) }
  mutating func le32(_ value: UInt32) { le16(UInt16(value & 65535)); le16(UInt16(value >> 16)) }
}
